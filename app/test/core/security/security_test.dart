import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/errors.dart';
import 'package:vankey/core/security/duplicates.dart';
import 'package:vankey/core/security/health.dart';
import 'package:vankey/core/security/hibp.dart';
import 'package:vankey/core/security/password_generator.dart';
import 'package:vankey/core/security/password_strength.dart';
import 'package:vankey/core/security/reminders.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';

import '../../helpers/helpers.dart';

int _t = 1000;
HlcClock clock([String n = 'A']) => HlcClock(node: n, nowMs: () => _t += 1);
int _seed = 0;

Item login(String title, {String user = 'u', String pw = 'x', TotpParams? totp, DateTime? at, Reminder? reminder, String group = ''}) =>
    Item.create(
      type: ItemType.login,
      title: title,
      clock: clock(),
      values: {'username': user, 'password': pw},
      totp: totp,
      group: group,
      now: at ?? DateTime.utc(2026, 1, 1),
      random: SeededRandom(++_seed),
    ).copyWith(reminder: reminder);

const totp1 = TotpParams(secret: 'JBSWY3DPEHPK3PXP');
const totp2 = TotpParams(secret: 'GEZDGNBVGY3TQOJQ');
const strongPw = '8x%rfwMJc+U*K+K9i@tT';

void main() {
  group('PasswordStrength', () {
    test('mật khẩu yếu phổ biến đều bị đánh giá yếu', () {
      for (final p in [
        '', 'abc12345', '12345678', '1234567890', 'aaaaaaaaaaaaaaaaaaaa', 'qwertyuiop', 'Password1!', 'p@ssw0rd', 'Admin123',
        'matkhau123', 'abcdefghijklmnop', 'Letmein2024', 'iloveyou!',
      ]) {
        expect(PasswordStrength.estimate(p).isWeak, isTrue, reason: '"$p" = ${PasswordStrength.estimate(p).bits.toStringAsFixed(1)} bit');
      }
    });

    test('mật khẩu ngẫu nhiên dài và cụm từ dài thì mạnh', () {
      expect(PasswordStrength.estimate(strongPw).level, StrengthLevel.veryStrong);
      expect(PasswordStrength.estimate('correct horse battery staple').level, StrengthLevel.veryStrong);
      expect(PasswordStrength.estimate('Hôm nay trời đẹp quá nên đi chơi').level.index >= StrengthLevel.strong.index, isTrue);
      expect(PasswordStrength.estimate('Tr0ub4dor&3').isWeak, isFalse);
    });

    test('dài hơn thì nhiều bit hơn; thêm loại ký tự thì nhiều bit hơn', () {
      final a = PasswordStrength.estimate('x8Kq2mZp').bits;
      final b = PasswordStrength.estimate('x8Kq2mZpV4nR').bits;
      expect(b, greaterThan(a));
      final lowerOnly = PasswordStrength.estimate('xkqmzpvnrtws').bits;
      final mixed = PasswordStrength.estimate('xKq2mZ!vNrTw').bits;
      expect(mixed, greaterThan(lowerOnly));
    });

    test('mật khẩu sinh ngẫu nhiên 20 ký tự luôn rất mạnh (200 lần)', () {
      final rnd = SeededRandom(1);
      for (var i = 0; i < 200; i++) {
        final p = PasswordGenerator.generate(random: rnd);
        expect(PasswordStrength.estimate(p).level, StrengthLevel.veryStrong, reason: p);
      }
    });
  });

  group('PasswordGenerator', () {
    test('đúng độ dài, và luôn có ít nhất một ký tự của mỗi loại được bật (500 lần)', () {
      final rnd = SeededRandom(2);
      for (var i = 0; i < 500; i++) {
        final len = 4 + rnd.nextInt(60);
        final p = PasswordGenerator.generate(length: len, random: rnd);
        expect(p.length, len);
        expect(RegExp('[A-Z]').hasMatch(p), isTrue, reason: p);
        expect(RegExp('[a-z]').hasMatch(p), isTrue, reason: p);
        expect(RegExp('[0-9]').hasMatch(p), isTrue, reason: p);
        expect(RegExp(r'[^A-Za-z0-9]').hasMatch(p), isTrue, reason: p);
      }
    });

    test('không bao giờ có ký tự dễ nhầm (I O l 0 1) khi bật tránh nhầm lẫn', () {
      final rnd = SeededRandom(3);
      for (var i = 0; i < 300; i++) {
        expect(PasswordGenerator.generate(length: 64, random: rnd), isNot(matches(RegExp('[IOl01]'))));
      }
    });

    test('tắt tránh nhầm lẫn thì có thể có 0 1 I O l', () {
      final rnd = SeededRandom(4);
      final all = List.generate(300, (_) => PasswordGenerator.generate(length: 64, avoidAmbiguous: false, random: rnd)).join();
      expect(all, matches(RegExp('[IOl01]')));
    });

    test('chỉ bật một loại thì chỉ có loại đó', () {
      final rnd = SeededRandom(5);
      expect(PasswordGenerator.generate(length: 30, useUpper: false, useLower: false, useSymbols: false, random: rnd), matches(RegExp(r'^[0-9]{30}$')));
      expect(PasswordGenerator.generate(length: 30, useUpper: false, useDigits: false, useSymbols: false, random: rnd), matches(RegExp(r'^[a-z]{30}$')));
    });

    test('phân phối đều (không thiên lệch): mỗi chữ cái xuất hiện gần bằng nhau', () {
      final rnd = SeededRandom(6);
      final counts = <String, int>{};
      for (var i = 0; i < 300; i++) {
        for (final ch in PasswordGenerator.generate(length: 100, useUpper: false, useDigits: false, useSymbols: false, random: rnd).split('')) {
          counts[ch] = (counts[ch] ?? 0) + 1;
        }
      }
      expect(counts.length, 25, reason: 'bỏ chữ l');
      final expected = 30000 / 25;
      for (final e in counts.entries) {
        expect(e.value, inInclusiveRange(expected * 0.85, expected * 1.15), reason: '${e.key}: ${e.value}');
      }
    });

    test('cùng hạt giống thì cùng kết quả; khác hạt giống thì khác', () {
      expect(PasswordGenerator.generate(random: SeededRandom(9)), PasswordGenerator.generate(random: SeededRandom(9)));
      expect(PasswordGenerator.generate(random: SeededRandom(9)), isNot(PasswordGenerator.generate(random: SeededRandom(10))));
    });

    test('tham số sai → InvalidInputException', () {
      expect(() => PasswordGenerator.generate(useUpper: false, useLower: false, useDigits: false, useSymbols: false), throwsA(isA<InvalidInputException>()));
      expect(() => PasswordGenerator.generate(length: 3), throwsA(isA<InvalidInputException>()));
      expect(() => PasswordGenerator.generate(length: 129), throwsA(isA<InvalidInputException>()));
    });
  });

  group('mục trùng lặp', () {
    test('trùng khóa 2FA, trùng tên + tài khoản, dùng chung mật khẩu; mới nhất ở đầu', () {
      final a = login('GitHub', user: 'van', pw: 'p1', totp: totp1, at: DateTime.utc(2026, 1, 1));
      final b = login('GitHub', user: 'van', pw: 'p2', totp: totp1, at: DateTime.utc(2026, 6, 1));
      final c = login('Facebook', user: 'van', pw: 'shared');
      final d = login('Instagram', user: 'van', pw: 'shared');
      final e = login('Khác', user: 'x', pw: 'riêng');
      final groups = findDuplicates([a, b, c, d, e]);
      expect(groups.map((g) => g.kind), [DuplicateKind.sameTotp, DuplicateKind.sharedPassword],
          reason: 'cặp a,b trùng cả 2FA lẫn tên nhưng chỉ báo một lần');
      expect(groups[0].items.map((i) => i.id), [b.id, a.id], reason: 'mới nhất trước');
      expect(groups[1].items.map((i) => i.title).toSet(), {'Facebook', 'Instagram'});
    });

    test('trùng tên + tài khoản không phân biệt hoa thường, bỏ qua mục không có tài khoản và mục trong thùng rác', () {
      final a = login('Gmail', user: 'Van@X.com');
      final b = login('GMAIL', user: 'van@x.com', pw: 'khác');
      final trashed = login('Gmail', user: 'van@x.com', pw: 'khác 2').moveToTrash(clock: clock());
      final noAcc1 = Item.create(type: ItemType.note, title: 'Ghi chú', clock: clock(), random: SeededRandom(100));
      final noAcc2 = Item.create(type: ItemType.note, title: 'Ghi chú', clock: clock(), random: SeededRandom(101));
      final groups = findDuplicates([a, b, trashed, noAcc1, noAcc2]);
      expect(groups.single.kind, DuplicateKind.sameTitleAccount);
      expect(groups.single.items.length, 2);
    });

    test('gộp: giữ bản mới nhất, mang theo 2FA/nhóm/yêu thích, cất mật khẩu khác vào lịch sử, đưa bản cũ vào thùng rác', () {
      final old = login('GitHub', user: 'van', pw: 'cũ', totp: totp1, at: DateTime.utc(2026, 1, 1), group: 'Dev').copyWith(favorite: true);
      final newest = login('GitHub', user: 'van', pw: 'mới', at: DateTime.utc(2026, 6, 1));
      final g = findDuplicates([old, newest]).single;
      expect(g.kind, DuplicateKind.sameTitleAccount);
      final out = mergeDuplicateGroup(g, clock: clock());
      expect(out.kept.id, newest.id);
      expect(out.kept.password, 'mới');
      expect(out.kept.totp, totp1, reason: 'mang theo 2FA');
      expect(out.kept.group, 'Dev');
      expect(out.kept.favorite, isTrue);
      expect(out.kept.pwHistory.map((h) => h.value), ['cũ'], reason: 'không mất mật khẩu cũ');
      expect(out.trashed.single.id, old.id);
      expect(out.trashed.single.inTrash, isTrue);
      expect(out.kept.version > newest.version, isTrue);
    });

    test('nhóm chỉ trùng mật khẩu không thể tự gộp', () {
      final g = findDuplicates([login('A', pw: 's'), login('B', pw: 's')]).single;
      expect(g.canMerge, isFalse);
      expect(() => mergeDuplicateGroup(g, clock: clock()), throwsA(isA<InvalidInputException>()));
    });
  });

  group('kiểm tra bảo mật (HealthReport)', () {
    test('kho trống hoặc toàn mục tốt có 100 điểm', () {
      expect(healthReport(const []).score, 100);
      final good = [login('A', pw: strongPw, totp: totp1), login('B', pw: '$strongPw-2', totp: totp2)];
      final r = healthReport(good);
      expect(r.score, 100);
      expect(r.level, HealthLevel.good);
      expect(r.issueCount, 0);
    });

    test('đếm đúng từng loại vấn đề và trừ điểm đúng công thức', () {
      final items = [
        login('Yếu', pw: 'abc12345', totp: totp1), // yếu
        login('Dùng chung 1', pw: strongPw, totp: totp1), // dùng chung
        login('Dùng chung 2', pw: strongPw, totp: totp2), // dùng chung
        login('Chưa 2FA', pw: '$strongPw-ok'), // chưa bật 2FA
      ];
      final r = healthReport(items);
      expect(r.weak.map((i) => i.title), ['Yếu']);
      expect(r.reusedItemCount, 2);
      expect(r.noTotp.map((i) => i.title), ['Chưa 2FA']);
      expect(r.score, 100 - 10 - 10 - 3);
    });

    test('mục bị rò rỉ trừ 15 điểm mỗi mục; mục trong thùng rác không tính', () {
      final a = login('Rò rỉ', pw: strongPw, totp: totp1);
      final trashed = login('Thùng rác', pw: 'abc12345').moveToTrash(clock: clock());
      final r = healthReport([a, trashed], leakedIds: {a.id, trashed.id});
      expect(r.leaked.single.id, a.id);
      expect(r.weak, isEmpty);
      expect(r.score, 85);
    });

    test('điểm không xuống dưới 0 và có trần cho từng loại', () {
      final bad = [for (var i = 0; i < 30; i++) login('Yếu $i', pw: 'abc1234$i')];
      final r = healthReport(bad, leakedIds: {for (final i in bad) i.id});
      expect(r.score, inInclusiveRange(0, 100));
      expect(r.level, HealthLevel.atRisk);
    });
  });

  group('HIBP (k-anonymity)', () {
    test('mã băm SHA-1 chuẩn: password và abc', () {
      final p = Hibp.split('password');
      expect(p.prefix, '5BAA6');
      expect(p.suffix, '1E4C9B93F3F0682250B6CF8331B7EE68FD8');
      final a = Hibp.split('abc');
      expect('${a.prefix}${a.suffix}', 'A9993E364706816ABA3E25717850C26C9CD0D89D');
    });

    test('đọc phản hồi: tìm thấy, không thấy, bỏ dòng đệm, phản hồi xuống dòng kiểu Windows', () {
      const body = '0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n1E4C9B93F3F0682250B6CF8331B7EE68FD8:9545824\r\nFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:0\r\n';
      expect(Hibp.countFromResponse(body, '1E4C9B93F3F0682250B6CF8331B7EE68FD8'), 9545824);
      expect(Hibp.countFromResponse(body, '1e4c9b93f3f0682250b6cf8331b7ee68fd8'), 9545824, reason: 'không phân biệt hoa thường');
      expect(Hibp.countFromResponse(body, '0000000000000000000000000000000000'), 0);
      expect(Hibp.countFromResponse('', 'ABC'), 0);
      expect(Hibp.countFromResponse('rác không có dấu hai chấm', 'ABC'), 0);
    });

    test('chỉ tiền tố 5 ký tự được gửi đi, mật khẩu và mã băm đầy đủ không bao giờ rời khỏi hàm', () async {
      final sent = <String>[];
      final n = await Hibp.check('password', (prefix) async {
        sent.add(prefix);
        return '1E4C9B93F3F0682250B6CF8331B7EE68FD8:42';
      });
      expect(n, 42);
      expect(sent, ['5BAA6']);
      expect(sent.single.length, 5);
      expect(sent.single.toLowerCase().contains('password'), isFalse);
    });
  });

  group('nhắc hạn', () {
    test('cộng tháng theo lịch: cuối tháng, năm nhuận, qua năm', () {
      expect(addMonths(DateTime.utc(2026, 1, 31), 1), DateTime.utc(2026, 2, 28));
      expect(addMonths(DateTime.utc(2028, 1, 31), 1), DateTime.utc(2028, 2, 29));
      expect(addMonths(DateTime.utc(2026, 11, 15), 3), DateTime.utc(2027, 2, 15));
      expect(addMonths(DateTime.utc(2026, 5, 10, 8, 30), 12), DateTime.utc(2027, 5, 10, 8, 30));
      expect(addMonths(DateTime.utc(2026, 12, 31), 2), DateTime.utc(2027, 2, 28));
    });

    Item withReminder(DateTime changed, {int months = 3, int notice = 7}) =>
        login('X', reminder: Reminder(months: months, noticeDays: notice, lastChangedAt: changed));

    test('mật khẩu: ổn, sắp hết hạn, quá hạn, và các mốc biên', () {
      final item = withReminder(DateTime.utc(2026, 1, 1)); // hạn 2026-04-01
      DateTime at(int m, int d) => DateTime.utc(2026, m, d);
      expect(passwordReminder(item, at(1, 10))!.state, ReminderState.ok);
      expect(passwordReminder(item, at(3, 24))!.daysLeft, 8);
      expect(passwordReminder(item, at(3, 24))!.state, ReminderState.ok);
      expect(passwordReminder(item, at(3, 25))!.state, ReminderState.soon, reason: 'còn đúng 7 ngày');
      expect(passwordReminder(item, at(4, 1))!.daysLeft, 0);
      expect(passwordReminder(item, at(4, 1))!.state, ReminderState.soon);
      expect(passwordReminder(item, at(4, 2))!.daysLeft, -1);
      expect(passwordReminder(item, at(4, 2))!.state, ReminderState.overdue);
    });

    test('không đặt nhắc hoặc số tháng 0 thì không có trạng thái', () {
      expect(passwordReminder(login('X'), DateTime.utc(2026, 1, 1)), isNull);
      expect(passwordReminder(withReminder(DateTime.utc(2026, 1, 1), months: 0), DateTime.utc(2026, 1, 1)), isNull);
    });

    test('hạn thẻ: MM/YY, MM/YYYY, cuối tháng; API key: dd/mm/yyyy và yyyy-mm-dd; sai thì null', () {
      Item card(String exp) => Item.create(type: ItemType.card, title: 'Visa', clock: clock(), values: {'holder': 'A', 'expiry': exp}, random: SeededRandom(200));
      Item key(String exp) => Item.create(type: ItemType.key, title: 'K', clock: clock(), values: {'service': 's', 'expiry': exp}, random: SeededRandom(201));
      expect(expiryDate(card('08/28')), DateTime.utc(2028, 8, 31, 23, 59, 59));
      expect(expiryDate(card('02/2028')), DateTime.utc(2028, 2, 29, 23, 59, 59));
      expect(expiryDate(card('13/28')), isNull);
      expect(expiryDate(card('abc')), isNull);
      expect(expiryDate(card('')), isNull);
      expect(expiryDate(key('15/03/2027')), DateTime.utc(2027, 3, 15, 23, 59, 59));
      expect(expiryDate(key('2027-03-15')), DateTime.utc(2027, 3, 15, 23, 59, 59));
      expect(expiryDate(key('31/02/2027')), isNull);
      expect(expiryDate(login('X')), isNull, reason: 'mục đăng nhập không có hạn thẻ/khóa');
    });

    test('danh sách nhắc nhở: sắp theo số ngày, bỏ mục ổn và mục trong thùng rác, hẹn lại và hết hẹn', () {
      final now = DateTime.utc(2026, 3, 30);
      final soon = withReminder(DateTime.utc(2026, 1, 1)); // hạn 1/4: còn 2 ngày
      final overdue = withReminder(DateTime.utc(2025, 10, 1)); // hạn 1/1: quá hạn
      final fine = withReminder(DateTime.utc(2026, 3, 1)); // hạn 1/6
      final trashed = withReminder(DateTime.utc(2025, 10, 1)).moveToTrash(clock: clock());
      final card = Item.create(type: ItemType.card, title: 'Visa', clock: clock(), values: {'holder': 'A', 'expiry': '03/26'}, random: SeededRandom(300));
      final farCard = Item.create(type: ItemType.card, title: 'Xa', clock: clock(), values: {'holder': 'A', 'expiry': '04/26'}, random: SeededRandom(301));

      final alerts = pendingAlerts([fine, soon, overdue, trashed, card, farCard], now);
      expect(alerts.first.item.id, overdue.id, reason: 'quá hạn đứng đầu');
      expect(alerts.first.status.state, ReminderState.overdue);
      expect(alerts.map((a) => a.item.id).toSet(), {overdue.id, soon.id, card.id}, reason: 'thẻ hết hạn xa hơn 30 ngày chưa nhắc');
      expect(alerts.any((a) => a.kind == AlertKind.cardExpiry), isTrue);

      final snoozed = pendingAlerts([soon, overdue], now, snoozedUntil: {'${overdue.id}:passwordExpiry': now.add(const Duration(days: 7))});
      expect(snoozed.map((a) => a.item.id), [soon.id]);
      final expired = pendingAlerts([soon, overdue], now, snoozedUntil: {'${overdue.id}:passwordExpiry': now.subtract(const Duration(hours: 1))});
      expect(expired.length, 2, reason: 'hẹn đã hết hạn thì hiện lại');
    });

    test('lịch thông báo: báo trước và đúng ngày hết hạn; không hẹn cho mục đã quá hạn', () {
      final now = DateTime.utc(2026, 1, 15);
      final item = withReminder(DateTime.utc(2026, 1, 1)); // hạn 1/4, báo trước 7 ngày → 25/3
      final overdue = withReminder(DateTime.utc(2025, 6, 1));
      final notices = upcomingNotices([item, overdue], now);
      expect(notices.length, 2);
      expect(notices[0].fireAt, DateTime.utc(2026, 3, 25));
      expect(notices[0].isDueDate, isFalse);
      expect(notices[1].fireAt, DateTime.utc(2026, 4, 1));
      expect(notices[1].isDueDate, isTrue);
      expect(notices.every((n) => n.itemId == item.id), isTrue);
      // Ngoài chân trời thì không hẹn.
      expect(upcomingNotices([item], now, horizonDays: 30), isEmpty);
    });
  });
}
