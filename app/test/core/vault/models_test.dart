import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/crypto/kdf.dart';
import 'package:vankey/core/errors.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/vault_session.dart';

import '../../helpers/helpers.dart';

HlcClock newClock([String node = 'A']) {
  var t = 1000;
  return HlcClock(node: node, nowMs: () => t += 1);
}

void main() {
  group('Hlc và HlcClock', () {
    test('định dạng và đọc lại', () {
      const h = Hlc(1700000000000, 3, 'dev-1');
      expect(h.toString(), '1700000000000:3:dev-1');
      expect(Hlc.parse(h.toString()), h);
    });

    test('thứ tự toàn phần: ms, rồi bộ đếm, rồi id thiết bị', () {
      expect(const Hlc(2, 0, 'a') > const Hlc(1, 9, 'z'), isTrue);
      expect(const Hlc(1, 2, 'a') > const Hlc(1, 1, 'z'), isTrue);
      expect(const Hlc(1, 1, 'b') > const Hlc(1, 1, 'a'), isTrue);
      expect(const Hlc(1, 1, 'a') == const Hlc(1, 1, 'a'), isTrue);
    });

    test('chuỗi hỏng đọc thành zero (cổ nhất), không ném lỗi', () {
      for (final bad in ['', 'abc', '1:2', '1:x:n', '-1:0:n', '1:0:bad node', null]) {
        expect(Hlc.parse(bad), Hlc.zero, reason: '"$bad"');
      }
    });

    test('next() luôn tăng dần, kể cả khi giờ máy đứng yên hoặc lùi', () {
      var t = 5000;
      final c = HlcClock(node: 'A', nowMs: () => t);
      final a = c.next();
      final b = c.next(); // cùng mili-giây
      t = 100; // giờ máy bị chỉnh lùi
      final d = c.next();
      expect(b > a, isTrue);
      expect(d > b, isTrue);
    });

    test('observe() đẩy đồng hồ vượt qua HLC của thiết bị khác', () {
      final c = HlcClock(node: 'A', nowMs: () => 1000);
      c.observe(const Hlc(999999, 7, 'B'));
      expect(c.next() > const Hlc(999999, 7, 'B'), isTrue);
    });

    test('id thiết bị chỉ cho phép chữ, số, gạch ngang, gạch dưới', () {
      expect(() => HlcClock(node: 'a:b'), throwsA(isA<InvalidInputException>()));
      expect(() => HlcClock(node: ''), throwsA(isA<InvalidInputException>()));
      expect(HlcClock(node: 'dev_1-A').node, 'dev_1-A');
    });
  });

  group('Item', () {
    test('tạo theo mẫu: loại Đăng nhập có trường bí mật đúng', () {
      final item = Item.create(
        type: ItemType.login,
        title: 'GitHub',
        clock: newClock(),
        values: {'username': 'van', 'password': 'p@ss', 'url': 'github.com'},
      );
      expect(item.type, ItemType.login);
      expect(item.fields.map((f) => f.key), ['username', 'password', 'url']);
      expect(item.fields.firstWhere((f) => f.key == 'password').secret, isTrue);
      expect(item.fields.firstWhere((f) => f.key == 'username').secret, isFalse);
      expect(item.password, 'p@ss');
    });

    test('dòng phụ chỉ lấy trường KHÔNG bí mật (không lộ cụm từ khôi phục)', () {
      final wallet = Item.create(
        type: ItemType.crypto,
        title: 'Ví lạnh',
        clock: newClock(),
        values: {'wallet': 'Ledger', 'seedPhrase': 'tower anchor velvet nine'},
      );
      expect(wallet.subtitle, 'Ledger');
      expect(wallet.subtitle.contains('tower'), isFalse);

      final onlySecret = Item.create(
        type: ItemType.crypto,
        title: 'Chỉ có seed',
        clock: newClock(),
        values: {'seedPhrase': 'tower anchor velvet nine'},
      );
      expect(onlySecret.subtitle, '');

      final note = Item.create(type: ItemType.note, title: 'Ghi chú', clock: newClock(), values: {'content': 'bí mật'});
      expect(note.subtitle, '');
    });

    test('sửa tạo HLC mới lớn hơn và cập nhật updatedAt', () {
      final clock = newClock();
      final a = Item.create(type: ItemType.login, title: 'A', clock: clock, values: {'username': 'u'});
      final b = a.edit(clock: clock, title: 'B');
      expect(b.title, 'B');
      expect(b.version > a.version, isTrue);
      expect(b.id, a.id);
      expect(a.title, 'A', reason: 'mục gốc bất biến');
    });

    test('đổi mật khẩu: cất bản cũ vào lịch sử, tối đa 10, tính lại hạn nhắc', () {
      final clock = newClock();
      final t0 = DateTime.utc(2026, 1, 1);
      var item = Item.create(
        type: ItemType.login,
        title: 'X',
        clock: clock,
        values: {'username': 'u', 'password': 'p0'},
        now: t0,
      ).copyWith(reminder: Reminder(months: 3, noticeDays: 7, lastChangedAt: t0));

      for (var i = 1; i <= 12; i++) {
        item = item.changePassword('p$i', clock: clock, now: DateTime.utc(2026, 1, 1).add(Duration(days: i)));
      }
      expect(item.password, 'p12');
      expect(item.pwHistory.length, 10);
      expect(item.pwHistory.first.value, 'p11', reason: 'mới nhất ở đầu');
      expect(item.pwHistory.last.value, 'p2');
      expect(item.reminder!.lastChangedAt, DateTime.utc(2026, 1, 13));
    });

    test('đổi mật khẩu trên mục không có trường mật khẩu → lỗi', () {
      final note = Item.create(type: ItemType.note, title: 'n', clock: newClock());
      expect(() => note.changePassword('x', clock: newClock()), throwsA(isA<InvalidInputException>()));
    });

    test('thùng rác và khôi phục', () {
      final clock = newClock();
      final a = Item.create(type: ItemType.login, title: 'A', clock: clock);
      final t = a.moveToTrash(clock: clock);
      expect(t.inTrash, isTrue);
      expect(t.version > a.version, isTrue);
      final r = t.restore(clock: clock);
      expect(r.inTrash, isFalse);
      expect(r.version > t.version, isTrue);
    });

    test('JSON vòng đi vòng lại và giữ nguyên trường lạ (kể cả loại mục chưa biết)', () {
      final json = {
        'id': 'i1',
        'type': 'passkey', // loại của phiên bản tương lai
        'title': 'Từ tương lai',
        'fields': [
          {'key': 'x', 'value': 'v', 'secret': true, 'kind': 'text'},
        ],
        'group': 'Dev',
        'favorite': true,
        'pwHistory': <dynamic>[],
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-02T00:00:00.000Z',
        'deletedAt': null,
        'hlc': '5:0:A',
        'newFeature': {'a': 1},
      };
      final item = Item.fromJson(json);
      expect(item.type, ItemType.note, reason: 'loại lạ được hiểu tạm là ghi chú');
      final back = item.toJson();
      expect(back['type'], 'passkey', reason: 'nhưng khi ghi lại vẫn giữ loại gốc');
      expect(back['newFeature'], {'a': 1});
      expect(Item.fromJson(back).toJson(), back);
    });
  });

  group('VaultData', () {
    test('upsert thay thế theo id và tự ghi nhận nhóm mới', () {
      final clock = newClock();
      final a = Item.create(type: ItemType.login, title: 'A', clock: clock, group: 'Dev');
      var d = const VaultData().upsert(a);
      expect(d.groups, ['Dev']);
      d = d.upsert(a.edit(clock: clock, title: 'A2'));
      expect(d.items.length, 1);
      expect(d.byId(a.id)!.title, 'A2');
    });

    test('xóa vĩnh viễn để lại tombstone; thêm lại cùng id thì bỏ tombstone', () {
      final clock = newClock();
      final a = Item.create(type: ItemType.login, title: 'A', clock: clock);
      var d = const VaultData().upsert(a).purge(a.id, clock: clock);
      expect(d.items, isEmpty);
      expect(d.tombstones.single.id, a.id);
      d = d.upsert(a.edit(clock: clock, title: 'lại'));
      expect(d.tombstones, isEmpty);
    });

    test('lược đồ mới hơn → UnsupportedVersionException', () {
      expect(() => VaultData.fromJson({'schema': 2}), throwsA(isA<UnsupportedVersionException>()));
    });

    test('JSON vòng đi vòng lại giữ trường lạ ở mức kho', () {
      final j = {'schema': 1, 'groups': ['x'], 'items': <dynamic>[], 'tombstones': <dynamic>[], 'future': 'keep'};
      expect(VaultData.fromJson(j).toJson(), j);
    });

    test('kho thật: lưu và mở lại qua VaultSession với dữ liệu tiếng Việt', () async {
      final clock = newClock();
      final item = Item.create(
        type: ItemType.card,
        title: 'Thẻ Vietcombank',
        clock: clock,
        values: {'holder': 'NGUYỄN VĂN Á', 'number': '4111 1111 1111 1111', 'cvv': '123'},
        group: 'Ngân hàng',
      );
      final data = const VaultData().upsert(item);
      const fast = Argon2Params(opslimit: 2, memlimitBytes: 32 * 1024 * 1024);
      final (s, _) = await VaultSession.create(
        passphrase: 'mật khẩu',
        initialPayload: data.toJson(),
        params: fast,
        random: SeededRandom(3),
      );
      final bytes = await s.save();
      final opened = await VaultSession.openWithPassphrase(bytes, 'mật khẩu');
      final back = VaultData.fromJson(opened.payload);
      expect(back.items.single.toJson(), item.toJson());
      expect(back.groups, ['Ngân hàng']);
    });
  });
}
