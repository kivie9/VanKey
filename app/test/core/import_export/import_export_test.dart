import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/errors.dart';
import 'package:vankey/core/import_export/csv.dart';
import 'package:vankey/core/import_export/exporters.dart';
import 'package:vankey/core/import_export/imported_item.dart';
import 'package:vankey/core/import_export/importers.dart';
import 'package:vankey/core/totp/migration.dart';
import 'package:vankey/core/totp/otpauth.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';

import '../../helpers/helpers.dart';

HlcClock clock() {
  var t = 1000;
  return HlcClock(node: 'T', nowMs: () => t += 1);
}

void main() {
  group('CSV (RFC 4180)', () {
    test('ô thường, ô có ngoặc kép, dấu phẩy, ngoặc kép lồng nhau, xuống dòng trong ô', () {
      final rows = parseCsv('a,"b,c","d ""q"" e","dòng1\ndòng2",\r\nx,y,z,w,v\r\n');
      expect(rows, [
        ['a', 'b,c', 'd "q" e', 'dòng1\ndòng2', ''],
        ['x', 'y', 'z', 'w', 'v'],
      ]);
    });

    test('mọi kiểu xuống dòng, thiếu xuống dòng cuối, dòng trống, BOM', () {
      expect(parseCsv('﻿a,b\nc,d'), [['a', 'b'], ['c', 'd']]);
      expect(parseCsv('a,b\rc,d\r'), [['a', 'b'], ['c', 'd']]);
      expect(parseCsv('a\n\n\nb\n'), [['a'], ['b']]);
      expect(parseCsv(''), isEmpty);
    });

    test('ô rỗng có ngoặc kép giữ vị trí cột; ngoặc kép giữa ô thường được coi là chữ', () {
      expect(parseCsv('a,"",c\n'), [['a', '', 'c']]);
      expect(parseCsv('5" pipe,x\n'), [['5" pipe', 'x']]);
    });

    test('ngoặc kép chưa đóng → lỗi', () {
      expect(() => parseCsv('a,"chưa đóng\nb'), throwsA(isA<InvalidInputException>()));
    });

    test('ghi rồi đọc lại cho kết quả y hệt (300 bảng ngẫu nhiên, gồm tiếng Việt, ngoặc kép, xuống dòng)', () {
      final rnd = SeededRandom(21);
      const pool = ['a', 'b', ' ', ',', '"', '\n', '\r\n', 'ệ', 'Đ', '日', 'x y', '=', '@'];
      for (var t = 0; t < 300; t++) {
        final rows = [
          for (var r = 0, n = 1 + rnd.nextInt(5); r < n; r++)
            [
              for (var c = 0, m = 2 + rnd.nextInt(4); c < m; c++)
                List.generate(1 + rnd.nextInt(6), (_) => pool[rnd.nextInt(pool.length)]).join(),
            ],
        ];
        // "\r\n" trong dữ liệu được giữ nguyên trong ô có ngoặc kép.
        expect(parseCsv(writeCsv(rows)), rows, reason: 'bảng $t');
      }
    });
  });

  group('nhập CSV của các trình quản lý mật khẩu', () {
    test('Bitwarden CSV: nhóm, yêu thích, ô nhiều dòng, mật khẩu có dấu phẩy và ngoặc kép, 2FA, ghi chú bảo mật', () {
      const text = 'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\r\n'
          'Dev,1,login,GitHub,"ghi chú\ndòng 2",,0,https://github.com,van,"p,ass""word",otpauth://totp/GitHub:van?secret=JBSWY3DPEHPK3PXP&issuer=GitHub\r\n'
          ',0,note,Ghi chú router,Đăng nhập 192.168.1.1,,0,,,,\r\n';
      final r = Importers.csv(text);
      expect(r.items.length, 2);
      final gh = r.items.first;
      expect(gh.title, 'GitHub');
      expect(gh.group, 'Dev');
      expect(gh.favorite, isTrue);
      expect(gh.username, 'van');
      expect(gh.password, 'p,ass"word');
      expect(gh.url, 'https://github.com');
      expect(gh.notes, 'ghi chú\ndòng 2');
      expect(gh.totp!.secret, 'JBSWY3DPEHPK3PXP');
      expect(r.items.last.type, ItemType.note);
      expect(r.items.last.notes, 'Đăng nhập 192.168.1.1');
      expect(r.warnings, isEmpty);
    });

    test('1Password CSV: khóa 2FA dạng Base32 thuần, thẻ tín dụng bị bỏ qua có cảnh báo', () {
      const text = 'Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes,Type\n'
          'Binance,binance.com,van@x.com,Zq4&mN7,jbsw y3dp ehpk 3pxp,0,0,Crypto,,Login\n'
          'Visa,,,,,0,0,,,Credit Card\n'
          'Mã wifi,,,,,0,0,,đừng cho ai,Secure Note\n';
      final r = Importers.csv(text);
      expect(r.items.map((i) => i.title), ['Binance', 'Mã wifi']);
      expect(r.items.first.totp!.secret, 'JBSWY3DPEHPK3PXP');
      expect(r.items.first.group, 'Crypto');
      expect(r.items.last.type, ItemType.note);
      expect(r.warnings.single.code, ImportWarningCode.skippedUnsupported);
      expect(r.warnings.single.position, 2);
    });

    test('KeePass CSV', () {
      const text = '"Account","Login Name","Password","Web Site","Comments"\n'
          '"Gmail","van@gmail.com","s3cret","https://mail.google.com","cũ"\n';
      final r = Importers.csv(text);
      expect(r.items.single.title, 'Gmail');
      expect(r.items.single.username, 'van@gmail.com');
      expect(r.items.single.notes, 'cũ');
    });

    test('Chrome CSV; thiếu tên thì lấy tên miền từ địa chỉ', () {
      const text = 'name,url,username,password,note\n,https://www.example.com/login,u,p,\n';
      expect(Importers.csv(text).items.single.title, 'example.com');
    });

    test('khóa 2FA hỏng: vẫn nhập phần còn lại, kèm cảnh báo', () {
      const text = 'name,username,password,totp\nX,u,p,không phải base32!!\n';
      final r = Importers.csv(text);
      expect(r.items.single.password, 'p');
      expect(r.items.single.totp, isNull);
      expect(r.warnings.single.code, ImportWarningCode.invalidTotp);
    });

    test('dòng trống hoàn toàn bị bỏ qua có cảnh báo; thiếu cột cần thiết → lỗi', () {
      final r = Importers.csv('name,username,password\nA,u,p\n,,\nB,u2,p2\n');
      expect(r.items.length, 2);
      expect(r.warnings.single.code, ImportWarningCode.emptyEntry);
      expect(() => Importers.csv('foo,bar\n1,2\n'), throwsA(isA<InvalidInputException>()));
      expect(() => Importers.csv(''), throwsA(isA<InvalidInputException>()));
    });
  });

  group('nhập JSON', () {
    test('Bitwarden JSON: đăng nhập, ghi chú, thẻ, danh tính bị bỏ qua, thư mục, trường tùy chỉnh ẩn', () {
      final json = jsonEncode({
        'encrypted': false,
        'folders': [
          {'id': 'f1', 'name': 'Ngân hàng'},
        ],
        'items': [
          {
            'type': 1,
            'name': 'Vietcombank',
            'folderId': 'f1',
            'favorite': true,
            'notes': null,
            'login': {
              'username': 'nguyen',
              'password': 'Đặng123',
              'totp': 'JBSWY3DPEHPK3PXP',
              'uris': [
                {'uri': 'https://vcb.com.vn'},
              ],
            },
            'fields': [
              {'name': 'Câu hỏi', 'value': 'Tên thú cưng', 'type': 1},
              {'name': 'Mã chi nhánh', 'value': '001', 'type': 0},
            ],
          },
          {'type': 2, 'name': 'Seed', 'notes': 'tower anchor velvet'},
          {
            'type': 3,
            'name': 'Visa',
            'card': {'cardholderName': 'NGUYEN VAN A', 'number': '4111111111111111', 'expMonth': '8', 'expYear': '2028', 'code': '123'},
          },
          {'type': 4, 'name': 'Danh tính'},
        ],
      });
      final r = Importers.bitwardenJson(json);
      expect(r.items.length, 3);
      final login = r.items[0];
      expect(login.group, 'Ngân hàng');
      expect(login.favorite, isTrue);
      expect(login.totp!.secret, 'JBSWY3DPEHPK3PXP');
      expect(login.extraFields.firstWhere((f) => f.label == 'Câu hỏi').secret, isTrue);
      expect(login.extraFields.firstWhere((f) => f.label == 'Mã chi nhánh').secret, isFalse);
      expect(r.items[1].type, ItemType.note);
      expect(r.items[2].type, ItemType.card);
      expect(r.items[2].extraValues['expiry'], '08/28');
      expect(r.warnings.single.code, ImportWarningCode.skippedUnsupported);
    });

    test('Bitwarden JSON đã mã hóa → EncryptedImportException', () {
      expect(() => Importers.bitwardenJson('{"encrypted":true,"items":[]}'), throwsA(isA<EncryptedImportException>()));
    });

    test('Aegis JSON: SHA256 8 chữ số, nhóm, Steam và HOTP được giữ; loại lạ bị bỏ qua; db là chuỗi → đã mã hóa', () {
      final json = jsonEncode({
        'version': 2,
        'header': {'slots': null, 'params': null},
        'db': {
          'version': 3,
          'entries': [
            {
              'type': 'totp',
              'name': 'van',
              'issuer': 'GitHub',
              'groups': ['g1'],
              'info': {'secret': 'JBSWY3DPEHPK3PXP', 'algo': 'SHA256', 'digits': 8, 'period': 60},
            },
            {
              'type': 'steam',
              'name': 'game',
              'info': {'secret': 'JBSWY3DPEHPK3PXP', 'algo': 'SHA1', 'digits': 5, 'period': 30},
            },
            {
              'type': 'hotp',
              'name': 'token',
              'issuer': 'Bank',
              'info': {'secret': 'JBSWY3DPEHPK3PXP', 'algo': 'SHA1', 'digits': 6, 'counter': 9},
            },
            {
              'type': 'yandex',
              'name': 'lạ',
              'info': {'secret': 'JBSWY3DPEHPK3PXP'},
            },
          ],
          'groups': [
            {'uuid': 'g1', 'name': 'Dev'},
          ],
        },
      });
      final r = Importers.aegis(json);
      expect(r.items.length, 3);
      final first = r.items.first;
      expect(first.totp!.algorithm, TotpAlgorithm.sha256);
      expect(first.totp!.digits, 8);
      expect(first.totp!.period, 60);
      expect(first.group, 'Dev');
      expect(r.items[1].totp!.toParams().isSteam, isTrue);
      expect(r.items[1].totp!.toParams().digits, 5);
      final hotp = r.items[2].totp!.toParams();
      expect(hotp.isHotp, isTrue);
      expect(hotp.counter, 9);
      expect(r.warnings.single.code, ImportWarningCode.skippedUnsupported);
      expect(() => Importers.aegis('{"db":"BASE64MA HOA"}'), throwsA(isA<EncryptedImportException>()));
    });

    test('2FAS JSON: TOTP và HOTP; loại lạ bị bỏ qua; services rỗng kèm servicesEncrypted → đã mã hóa', () {
      final json = jsonEncode({
        'services': [
          {
            'name': 'Google',
            'secret': 'JBSWY3DPEHPK3PXP',
            'otp': {'issuer': 'Google', 'account': 'van@gmail.com', 'digits': 6, 'period': 30, 'algorithm': 'SHA1', 'tokenType': 'TOTP'},
          },
          {
            'name': 'Hotp',
            'secret': 'JBSWY3DPEHPK3PXP',
            'otp': {'tokenType': 'HOTP', 'counter': 3},
          },
          {
            'name': 'Lạ',
            'secret': 'JBSWY3DPEHPK3PXP',
            'otp': {'tokenType': 'YANDEX'},
          },
        ],
      });
      final r = Importers.twoFas(json);
      expect(r.items.first.totp!.account, 'van@gmail.com');
      expect(r.items[1].totp!.type, OtpType.hotp);
      expect(r.items[1].totp!.counter, 3);
      expect(r.warnings.single.code, ImportWarningCode.skippedUnsupported);
      expect(() => Importers.twoFas('{"services":[],"servicesEncrypted":"xyz"}'), throwsA(isA<EncryptedImportException>()));
    });

    test('danh sách link: link hợp lệ, link hỏng, HOTP và Steam, mã Google Authenticator nhiều mục, dòng trống', () {
      final mig = Migration.encodeUri([
        const OtpAuth(type: OtpType.totp, secret: 'JBSWY3DPEHPK3PXP', issuer: 'A', account: 'a'),
        const OtpAuth(type: OtpType.totp, secret: 'GEZDGNBVGY3TQOJQ', issuer: 'B', account: 'b'),
      ]);
      final text = '''
otpauth://totp/GitHub:van?secret=JBSWY3DPEHPK3PXP&issuer=GitHub

hello world
otpauth://hotp/X?secret=JBSWY3DPEHPK3PXP&counter=1
otpauth://totp/Steam:me?secret=JBSWY3DPEHPK3PXP&issuer=Steam&encoder=steam
$mig
''';
      final r = Importers.otpauthLines(text);
      expect(r.items.map((i) => i.title), ['GitHub', 'X', 'Steam', 'A', 'B']);
      expect(r.items[1].totp!.type, OtpType.hotp);
      expect(r.items[1].totp!.counter, 1);
      expect(r.items[2].totp!.steam, isTrue);
      expect(r.warnings.map((w) => w.code), [ImportWarningCode.invalidLine]);
    });
  });

  group('tự nhận diện định dạng', () {
    test('mỗi loại file được chuyển đúng bộ đọc', () {
      expect(Importers.auto('{"db":{"entries":[]}}').items, isEmpty);
      expect(Importers.auto('{"services":[]}').items, isEmpty);
      expect(Importers.auto('{"items":[]}').items, isEmpty);
      expect(Importers.auto('otpauth://totp/X?secret=JBSWY3DPEHPK3PXP').items.length, 1);
      expect(Importers.auto('name,username,password\nA,u,p\n').items.length, 1);
    });

    test('rỗng, JSON lạ, JSON hỏng → InvalidInputException', () {
      for (final bad in ['', '   ', '{"foo":1}', '{hỏng', '[1,2]']) {
        expect(() => Importers.auto(bad), throwsA(isA<InvalidInputException>()), reason: bad);
      }
    });

    test('đánh dấu mục trùng với mục đã có (cùng tên và tài khoản, không phân biệt hoa thường)', () {
      final existing = [
        Item.create(type: ItemType.login, title: 'GitHub', clock: clock(), values: {'username': 'VAN'}),
        Item.create(type: ItemType.totp, title: 'Discord', clock: clock(), values: {'account': 'me'}),
      ];
      final r = Importers.csv('name,username,password\ngithub,van,x\nGitHub,khac,y\n');
      final marked = r.markDuplicates(existing);
      expect(marked.map((m) => m.duplicate), [true, false]);
    });
  });

  group('ImportedItem.toItem', () {
    test('mục chỉ có 2FA thành loại "Chỉ 2FA"', () {
      final r = Importers.otpauthLines('otpauth://totp/GitHub:van?secret=JBSWY3DPEHPK3PXP&issuer=GitHub');
      final item = r.items.single.toItem(clock: clock(), random: SeededRandom(1));
      expect(item.type, ItemType.totp);
      expect(item.title, 'GitHub');
      expect(item.valueOf('account'), 'van');
      expect(item.totp!.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('đăng nhập có ghi chú: ghi chú thành trường bí mật; nhóm có thể ghi đè', () {
      const imp = ImportedItem(title: 'X', username: 'u', password: 'p', url: 'x.com', notes: 'riêng tư', group: 'Cũ');
      final item = imp.toItem(clock: clock(), groupOverride: 'Nhập từ Bitwarden', random: SeededRandom(2));
      expect(item.type, ItemType.login);
      expect(item.group, 'Nhập từ Bitwarden');
      final notes = item.fields.firstWhere((f) => f.key == 'notes');
      expect(notes.secret, isTrue);
      expect(item.subtitle, 'u');
    });

    test('thẻ và ghi chú bảo mật', () {
      const card = ImportedItem(
        title: 'Visa',
        type: ItemType.card,
        extraValues: {'holder': 'NGUYEN', 'number': '4111', 'expiry': '08/28', 'cvv': '123'},
      );
      final c = card.toItem(clock: clock(), random: SeededRandom(3));
      expect(c.type, ItemType.card);
      expect(c.valueOf('cvv'), '123');
      expect(c.fields.firstWhere((f) => f.key == 'number').secret, isTrue);
      const note = ImportedItem(title: 'N', type: ItemType.note, notes: 'nội dung');
      expect(note.toItem(clock: clock(), random: SeededRandom(4)).valueOf('content'), 'nội dung');
    });
  });

  group('xuất', () {
    late List<Item> items;
    setUp(() {
      final c = clock();
      items = [
        Item.create(
          type: ItemType.login,
          title: 'GitHub',
          clock: c,
          values: {'username': 'van', 'password': 'p,"x"', 'url': 'github.com'},
          totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP'),
          group: 'Dev',
          favorite: true,
          random: SeededRandom(1),
        ),
        Item.create(
          type: ItemType.totp,
          title: 'Ngân hàng',
          clock: c,
          values: {'account': 'a@b.vn'},
          totp: const TotpParams(secret: 'GEZDGNBVGY3TQOJQ', algorithm: TotpAlgorithm.sha256, digits: 8),
          random: SeededRandom(2),
        ),
        Item.create(type: ItemType.note, title: 'Ghi chú', clock: c, values: {'content': 'dòng 1\ndòng 2'}, random: SeededRandom(3)),
        Item.create(
          type: ItemType.card,
          title: 'Visa',
          clock: c,
          values: {'holder': 'NGUYEN', 'number': '4111 1111 1111 1111', 'cvv': '123'},
          random: SeededRandom(4),
        ),
      ];
    });

    test('link otpauth: chỉ mục có 2FA, đọc lại đúng, không có mục trong thùng rác', () {
      final withTrash = [...items, items.first.moveToTrash(clock: clock()).copyWith(title: 'Đã xóa')]; // cùng id, bản thùng rác thắng khi lọc
      final text = Exporters.otpauthLines(items);
      final back = Importers.otpauthLines(text);
      expect(back.items.length, 2);
      expect(back.items.map((i) => i.totp!.secret), ['JBSWY3DPEHPK3PXP', 'GEZDGNBVGY3TQOJQ']);
      expect(back.items[1].totp!.algorithm, TotpAlgorithm.sha256);
      expect(back.items[1].totp!.digits, 8);
      expect(Exporters.otpauthLines([withTrash.last]), isEmpty, reason: 'mục trong thùng rác bị bỏ');
      expect(Exporters.otpauthLines([withTrash.last], includeTrash: true), isNotEmpty);
    });

    test('Google Authenticator: chia lô 10 mục mỗi mã QR, đọc lại đủ và đúng thứ tự lô', () {
      final many = [
        for (var i = 0; i < 25; i++)
          Item.create(
            type: ItemType.totp,
            title: 'D$i',
            clock: clock(),
            values: {'account': 'u$i'},
            totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP'),
            random: SeededRandom(i + 10),
          ),
      ];
      final uris = Exporters.googleMigrationUris(many);
      expect(uris.length, 3);
      final parsed = uris.map(Migration.parseUri).toList();
      expect(parsed.map((p) => p.entries.length), [10, 10, 5]);
      expect(parsed.map((p) => p.batchIndex), [0, 1, 2]);
      expect(parsed.every((p) => p.batchSize == 3), isTrue);
      expect(Exporters.googleMigrationUris([items[2]]), isEmpty);
    });

    test('CSV: vòng đi vòng lại cho đăng nhập và ghi chú; thẻ gom vào cột ghi chú, không mất dữ liệu', () {
      final csv = Exporters.csv(items);
      final rows = parseCsv(csv);
      expect(rows.first, Exporters.csvHeader);
      expect(rows.length, 5);

      final back = Importers.csv(csv);
      final gh = back.items.firstWhere((i) => i.title == 'GitHub');
      expect(gh.username, 'van');
      expect(gh.password, 'p,"x"');
      expect(gh.url, 'github.com');
      expect(gh.group, 'Dev');
      expect(gh.favorite, isTrue);
      expect(gh.totp!.secret, 'JBSWY3DPEHPK3PXP');
      expect(back.items.firstWhere((i) => i.title == 'Ghi chú').notes, 'dòng 1\ndòng 2');

      // Thẻ: CSV chung không mang được cấu trúc thẻ nên bị bỏ qua khi nhập lại, nhưng dữ liệu vẫn nằm trong cột ghi chú.
      final cardRow = rows.firstWhere((r) => r[0] == 'Visa');
      expect(cardRow[6], contains('number: 4111 1111 1111 1111'));
      expect(cardRow[6], contains('cvv: 123'));
      expect(back.warnings.any((w) => w.code == ImportWarningCode.skippedUnsupported), isTrue);
    });
  });

  group('độ bền: dữ liệu rác không bao giờ làm sập app', () {
    // Mọi lỗi phải là VaultException (có kiểm soát). RangeError, TypeError, StateError... đều là lỗi mã nguồn.
    void mustBeControlled(String label, void Function() f) {
      try {
        f();
      } on VaultException {
        // chấp nhận
      } catch (e, st) {
        fail('$label ném lỗi không kiểm soát: $e\n$st');
      }
    }

    test('chuỗi ngẫu nhiên và mẫu bị cắt/đột biến, qua mọi bộ đọc (1500 lần)', () {
      final rnd = SeededRandom(77);
      final seeds = [
        'name,username,password,totp\nA,u,p,JBSWY3DPEHPK3PXP\n',
        '{"items":[{"type":1,"name":"x","login":{"username":"u","uris":[{"uri":"a"}]}}],"folders":[{"id":"1","name":"f"}]}',
        '{"db":{"entries":[{"type":"totp","info":{"secret":"JBSWY3DPEHPK3PXP"}}],"groups":[]}}',
        '{"services":[{"name":"n","secret":"JBSWY3DPEHPK3PXP","otp":{}}]}',
        'otpauth://totp/A:b?secret=JBSWY3DPEHPK3PXP\notpauth-migration://offline?data=CjEKCkhlbGxvId6tvu8SGEV4YW1wbGU6YWxpY2VAZ29vZ2xlLmNvbRIHRXhhbXBsZTAC',
      ];
      for (var i = 0; i < 1500; i++) {
        final seed = seeds[rnd.nextInt(seeds.length)];
        String s;
        switch (rnd.nextInt(3)) {
          case 0: // cắt
            s = seed.substring(0, rnd.nextInt(seed.length + 1));
          case 1: // đột biến vài ký tự
            final chars = seed.split('');
            for (var k = 0, n = 1 + rnd.nextInt(4); k < n; k++) {
              chars[rnd.nextInt(chars.length)] = String.fromCharCode(32 + rnd.nextInt(95));
            }
            s = chars.join();
          default: // hoàn toàn ngẫu nhiên
            s = String.fromCharCodes(List.generate(rnd.nextInt(80), (_) => 1 + rnd.nextInt(0x2fff)));
        }
        mustBeControlled('auto #$i', () => Importers.auto(s));
        mustBeControlled('csv #$i', () => Importers.csv(s));
        mustBeControlled('otpauthLines #$i', () => Importers.otpauthLines(s));
      }
    });
  });
}
