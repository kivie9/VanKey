import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/errors.dart';
import 'package:vankey/core/totp/base32.dart';
import 'package:vankey/core/totp/migration.dart';
import 'package:vankey/core/totp/otpauth.dart';
import 'package:vankey/core/totp/totp.dart';
import 'package:vankey/core/vault/models.dart';

import '../../helpers/helpers.dart';

Uint8List ascii(String s) => Uint8List.fromList(ascii_.encode(s));
const ascii_ = AsciiCodec();

void main() {
  group('Base32 (RFC 4648)', () {
    const vectors = {
      '': '',
      'f': 'MY======',
      'fo': 'MZXQ====',
      'foo': 'MZXW6===',
      'foob': 'MZXW6YQ=',
      'fooba': 'MZXW6YTB',
      'foobar': 'MZXW6YTBOI======',
    };

    test('mã hóa khớp vector chuẩn (có padding)', () {
      vectors.forEach((plain, enc) => expect(Base32.encode(ascii(plain), padding: true), enc, reason: '"$plain"'));
    });

    test('giải mã khớp vector chuẩn, có hoặc không có padding', () {
      vectors.forEach((plain, enc) {
        if (plain.isEmpty) return; // chuỗi rỗng bị từ chối có chủ ý (khóa không được rỗng)
        expect(ascii_.decode(Base32.decode(enc)), plain);
        expect(ascii_.decode(Base32.decode(enc.replaceAll('=', ''))), plain);
      });
    });

    test('chấp nhận chữ thường, khoảng trắng, gạch ngang (cách người dùng hay chép khóa)', () {
      expect(Base32.normalize('jbsw y3dp-ehpk 3pxp'), 'JBSWY3DPEHPK3PXP');
    });

    test('từ chối ký tự ngoài bảng (0, 1, 8, 9) và chuỗi rỗng', () {
      for (final bad in ['JBSWY3DP0', 'JBSWY3DP1', 'JBSWY3DP8', 'JBSWY3DP9', 'JBSW!Y3DP', '', '   ', '====']) {
        expect(() => Base32.decode(bad), throwsA(isA<InvalidInputException>()), reason: '"$bad"');
      }
      expect(Base32.isValid('JBSWY3DPEHPK3PXP'), isTrue);
      expect(Base32.isValid('0000'), isFalse);
    });

    test('vòng đi vòng lại với byte ngẫu nhiên (500 lần)', () {
      final rnd = SeededRandom(5);
      for (var i = 0; i < 500; i++) {
        final data = rnd.bytes(1 + rnd.nextInt(40));
        expect(Base32.decode(Base32.encode(data)), data);
      }
    });
  });

  group('HOTP (RFC 4226, phụ lục D)', () {
    test('10 giá trị đầu của bộ đếm', () {
      final secret = ascii('12345678901234567890');
      const expected = ['755224', '287082', '359152', '969429', '338314', '254676', '287922', '162583', '399871', '520489'];
      for (var c = 0; c < expected.length; c++) {
        expect(Otp.hotp(secret: secret, counter: c), expected[c], reason: 'counter $c');
      }
    });

    test('từ chối số chữ số, bộ đếm, khóa không hợp lệ', () {
      final s = ascii('12345678901234567890');
      expect(() => Otp.hotp(secret: s, counter: 0, digits: 5), throwsA(isA<InvalidInputException>()));
      expect(() => Otp.hotp(secret: s, counter: 0, digits: 9), throwsA(isA<InvalidInputException>()));
      expect(() => Otp.hotp(secret: s, counter: -1), throwsA(isA<InvalidInputException>()));
      expect(() => Otp.hotp(secret: Uint8List(0), counter: 0), throwsA(isA<InvalidInputException>()));
    });
  });

  group('TOTP (RFC 6238, phụ lục B, 8 chữ số)', () {
    final s1 = ascii('12345678901234567890');
    final s256 = ascii('12345678901234567890123456789012');
    final s512 = ascii('1234567890123456789012345678901234567890123456789012345678901234');

    // thời điểm (giây) → [SHA1, SHA256, SHA512]
    const table = <int, List<String>>{
      59: ['94287082', '46119246', '90693936'],
      1111111109: ['07081804', '68084774', '25091201'],
      1111111111: ['14050471', '67062674', '99943326'],
      1234567890: ['89005924', '91819424', '93441116'],
      2000000000: ['69279037', '90698825', '38618901'],
      20000000000: ['65353130', '77737706', '47863826'],
    };

    test('khớp toàn bộ vector chuẩn cho SHA1, SHA256, SHA512', () {
      table.forEach((t, want) {
        expect(Otp.totpAt(secret: s1, unixSeconds: t, digits: 8), want[0], reason: 'SHA1 t=$t');
        expect(Otp.totpAt(secret: s256, unixSeconds: t, digits: 8, algorithm: TotpAlgorithm.sha256), want[1], reason: 'SHA256 t=$t');
        expect(Otp.totpAt(secret: s512, unixSeconds: t, digits: 8, algorithm: TotpAlgorithm.sha512), want[2], reason: 'SHA512 t=$t');
      });
    });

    test('mã 6 chữ số chính là 6 chữ số cuối của mã 8 chữ số', () {
      table.forEach((t, want) {
        expect(Otp.totpAt(secret: s1, unixSeconds: t), want[0].substring(2), reason: 't=$t');
      });
    });

    test('mã đổi đúng ở ranh giới 30 giây, không đổi trong cùng chu kỳ', () {
      final a = Otp.totpAt(secret: s1, unixSeconds: 59);
      final b = Otp.totpAt(secret: s1, unixSeconds: 30);
      final c = Otp.totpAt(secret: s1, unixSeconds: 60);
      expect(a, b, reason: '30..59 cùng một chu kỳ');
      expect(a, isNot(c), reason: 'giây 60 sang chu kỳ mới');
    });

    test('chu kỳ 60 giây', () {
      final a = Otp.totpAt(secret: s1, unixSeconds: 0, period: 60);
      final b = Otp.totpAt(secret: s1, unixSeconds: 59, period: 60);
      final c = Otp.totpAt(secret: s1, unixSeconds: 60, period: 60);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('Otp.code dùng tham số của mục (khóa Base32)', () {
      final p = TotpParams(secret: Base32.encode(s1), digits: 8);
      expect(Otp.code(p, DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true)), '94287082');
    });

    test('đếm ngược: còn lại từ 1 đến chu kỳ, và tỉ lệ trong (0,1]', () {
      DateTime at(int s, [int ms = 0]) => DateTime.fromMillisecondsSinceEpoch(s * 1000 + ms, isUtc: true);
      expect(Otp.secondsRemaining(at(0)), 30);
      expect(Otp.secondsRemaining(at(1)), 29);
      expect(Otp.secondsRemaining(at(59)), 1);
      expect(Otp.secondsRemaining(at(60)), 30);
      expect(Otp.fractionRemaining(at(0)), 1.0);
      expect(Otp.fractionRemaining(at(15)), closeTo(0.5, 1e-9));
      expect(Otp.fractionRemaining(at(29, 999)) > 0, isTrue);
    });

    test('chia nhóm mã để dễ đọc', () {
      expect(Otp.grouped('123456'), '123 456');
      expect(Otp.grouped('12345678'), '1234 5678');
      expect(Otp.grouped('1234567'), '1234567');
    });
  });

  group('OtpAuth (otpauth://)', () {
    test('ví dụ chuẩn của Google', () {
      final o = OtpAuth.parse('otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example');
      expect(o.type, OtpType.totp);
      expect(o.issuer, 'Example');
      expect(o.account, 'alice@google.com');
      expect(o.secret, 'JBSWY3DPEHPK3PXP');
      expect(o.algorithm, TotpAlgorithm.sha1);
      expect(o.digits, 6);
      expect(o.period, 30);
      expect(o.title, 'Example');
    });

    test('chỉ có nhãn, không có issuer; có khoảng trắng và %3A trong nhãn', () {
      final a = OtpAuth.parse('otpauth://totp/alice@x.com?secret=jbswy3dpehpk3pxp');
      expect(a.issuer, '');
      expect(a.account, 'alice@x.com');
      expect(a.secret, 'JBSWY3DPEHPK3PXP', reason: 'chuẩn hóa chữ hoa');
      final b = OtpAuth.parse('otpauth://totp/GitHub%3A%20van?secret=JBSWY3DPEHPK3PXP');
      expect(b.issuer, 'GitHub');
      expect(b.account, 'van');
    });

    test('tham số issuer ưu tiên hơn tiền tố trong nhãn', () {
      final o = OtpAuth.parse('otpauth://totp/Cũ:van?secret=JBSWY3DPEHPK3PXP&issuer=Mới');
      expect(o.issuer, 'Mới');
      expect(o.account, 'van');
    });

    test('SHA256, 8 chữ số, chu kỳ 60', () {
      final o = OtpAuth.parse('otpauth://totp/X?secret=JBSWY3DPEHPK3PXP&algorithm=sha256&digits=8&period=60');
      expect(o.algorithm, TotpAlgorithm.sha256);
      expect(o.digits, 8);
      expect(o.period, 60);
      expect(o.toParams(), TotpParams(secret: 'JBSWY3DPEHPK3PXP', algorithm: TotpAlgorithm.sha256, digits: 8, period: 60));
    });

    test('HOTP cần counter', () {
      final o = OtpAuth.parse('otpauth://hotp/X?secret=JBSWY3DPEHPK3PXP&counter=7');
      expect(o.type, OtpType.hotp);
      expect(o.counter, 7);
      expect(() => OtpAuth.parse('otpauth://hotp/X?secret=JBSWY3DPEHPK3PXP'), throwsA(isA<InvalidInputException>()));
    });

    test('từ chối link sai', () {
      for (final bad in [
        'https://example.com',
        'otpauth://steam/X?secret=JBSWY3DPEHPK3PXP',
        'otpauth://totp/X',
        'otpauth://totp/X?secret=',
        'otpauth://totp/X?secret=0000000000000000',
        'otpauth://totp/X?secret=ABC',
        'otpauth://totp/X?secret=JBSWY3DPEHPK3PXP&algorithm=MD5',
        'otpauth://totp/X?secret=JBSWY3DPEHPK3PXP&digits=9',
        'otpauth://totp/X?secret=JBSWY3DPEHPK3PXP&digits=abc',
        'otpauth://totp/X?secret=JBSWY3DPEHPK3PXP&period=0',
        '',
      ]) {
        expect(() => OtpAuth.parse(bad), throwsA(isA<InvalidInputException>()), reason: bad);
      }
    });

    test('dựng link rồi đọc lại cho kết quả y hệt (kể cả tiếng Việt và ký tự đặc biệt)', () {
      const cases = [
        OtpAuth(type: OtpType.totp, secret: 'JBSWY3DPEHPK3PXP', issuer: 'Ngân hàng Á Châu', account: 'nguyễn+văn@x.com'),
        OtpAuth(type: OtpType.totp, secret: 'JBSWY3DPEHPK3PXP', account: 'chỉ có tài khoản'),
        OtpAuth(type: OtpType.totp, secret: 'JBSWY3DPEHPK3PXP', issuer: 'A:B', account: 'c', algorithm: TotpAlgorithm.sha512, digits: 8, period: 45),
        OtpAuth(type: OtpType.hotp, secret: 'JBSWY3DPEHPK3PXP', issuer: 'H', account: 'k', counter: 123),
      ];
      for (final c in cases) {
        final back = OtpAuth.parse(c.toUri());
        // Một issuer chứa dấu ":" được mã hóa phần trăm nên vẫn đọc lại đúng.
        expect(back, c, reason: c.toUri());
      }
    });
  });

  group('Migration (Google Authenticator)', () {
    test('mẫu công khai: bí mật và kiểu đúng', () {
      final p = Migration.parseUri('otpauth-migration://offline?data=CjEKCkhlbGxvId6tvu8SGEV4YW1wbGU6YWxpY2VAZ29vZ2xlLmNvbRIHRXhhbXBsZTAC');
      expect(p.entries.length, 1);
      expect(p.entries.single.secret, 'JBSWY3DPEHPK3PXP');
      expect(p.entries.single.type, OtpType.totp);
      expect(p.entries.single.algorithm, TotpAlgorithm.sha1);
      expect(p.entries.single.digits, 6);
      expect(p.skipped, 0);
    });

    test('mã hóa rồi đọc lại nhiều mục: tên, issuer, thuật toán, số chữ số, HOTP', () {
      const entries = [
        OtpAuth(type: OtpType.totp, secret: 'JBSWY3DPEHPK3PXP', issuer: 'GitHub', account: 'van'),
        OtpAuth(type: OtpType.totp, secret: 'GEZDGNBVGY3TQOJQ', issuer: 'Ngân hàng', account: 'a@b.vn', algorithm: TotpAlgorithm.sha256, digits: 8),
        OtpAuth(type: OtpType.totp, secret: 'MFRGGZDFMZTWQ2LK', account: 'không issuer', algorithm: TotpAlgorithm.sha512),
        OtpAuth(type: OtpType.hotp, secret: 'NBSWY3DPEB3W64TM', issuer: 'H', account: 'k', counter: 42),
      ];
      final uri = Migration.encodeUri(entries, batchSize: 3, batchIndex: 1, batchId: 777);
      final p = Migration.parseUri(uri);
      expect(p.entries, entries);
      expect(p.batchSize, 3);
      expect(p.batchIndex, 1);
      expect(p.batchId, 777);
    });

    test('chịu được "+" bị đọc thành khoảng trắng và base64 kiểu URL-safe', () {
      final entries = [for (var i = 0; i < 12; i++) OtpAuth(type: OtpType.totp, secret: 'JBSWY3DPEHPK3PXP', issuer: 'I$i', account: 'acc$i?>~')];
      final raw = base64.encode(Migration.encode(entries));
      expect(raw.contains('+') || raw.contains('/'), isTrue, reason: 'dữ liệu thử phải có "+" hoặc "/"');
      // 1) "+" không mã hóa trong link → Uri đọc thành khoảng trắng
      expect(Migration.parseUri('otpauth-migration://offline?data=$raw').entries, entries);
      // 2) base64 URL-safe, không padding
      final urlSafe = raw.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
      expect(Migration.parseUri('otpauth-migration://offline?data=$urlSafe').entries, entries);
    });

    test('mục dùng MD5 hoặc không có khóa bị bỏ qua và được đếm', () {
      // Tự dựng payload có 1 mục MD5 (algorithm=4) và 1 mục SHA1 hợp lệ.
      final w = BytesBuilder();
      void entry(int algo, List<int> secret) {
        final inner = BytesBuilder()
          ..add([0x0a, secret.length, ...secret])
          ..add([0x12, 1, 0x41]) // name "A"
          ..add([0x20, algo]) // algorithm
          ..add([0x30, 2]); // type TOTP
        w
          ..add([0x0a, inner.length])
          ..add(inner.toBytes());
      }

      entry(4, [1, 2, 3, 4, 5]);
      entry(1, [1, 2, 3, 4, 5]);
      entry(1, []); // không có khóa
      final p = Migration.parseBytes(w.toBytes());
      expect(p.entries.length, 1);
      expect(p.skipped, 2);
    });

    test('dữ liệu hỏng, cắt cụt hoặc độc hại → InvalidInputException, không bao giờ vượt biên', () {
      final good = Migration.encode([const OtpAuth(type: OtpType.totp, secret: 'JBSWY3DPEHPK3PXP', issuer: 'X', account: 'y')]);
      for (var cut = 1; cut < good.length; cut++) {
        final truncated = Uint8List.sublistView(good, 0, cut);
        try {
          Migration.parseBytes(truncated);
        } on InvalidInputException {
          // cắt giữa chừng thì lỗi là đúng; cắt đúng ranh giới trường thì có thể đọc được phần đầu
        }
      }
      // độ dài trường vượt quá dữ liệu
      expect(() => Migration.parseBytes(Uint8List.fromList([0x0a, 0x7f, 1, 2])), throwsA(isA<InvalidInputException>()));
      // varint không kết thúc
      expect(() => Migration.parseBytes(Uint8List.fromList(List.filled(20, 0xff))), throwsA(isA<InvalidInputException>()));
      // kiểu dây không hợp lệ
      expect(() => Migration.parseBytes(Uint8List.fromList([0x0f])), throwsA(isA<InvalidInputException>()));
      // link sai
      expect(() => Migration.parseUri('otpauth://totp/x?secret=JBSWY3DPEHPK3PXP'), throwsA(isA<InvalidInputException>()));
      expect(() => Migration.parseUri('otpauth-migration://offline'), throwsA(isA<InvalidInputException>()));
      expect(() => Migration.parseUri('otpauth-migration://offline?data=@@@'), throwsA(isA<InvalidInputException>()));
    });

    test('quét dữ liệu ngẫu nhiên không làm app sập (1000 lần)', () {
      final rnd = SeededRandom(9);
      for (var i = 0; i < 1000; i++) {
        final bytes = rnd.bytes(1 + rnd.nextInt(60));
        try {
          Migration.parseBytes(bytes);
        } on InvalidInputException {
          // lỗi có kiểm soát là chấp nhận được
        }
      }
    });
  });

  group('Steam Guard và HOTP theo tham số của mục', () {
    final secret = Base32.decode('JBSWY3DPEHPK3PXP');

    // Vector tạo bằng bản cài đặt độc lập (Node crypto), không dùng lại mã Dart.
    test('Steam Guard: 5 ký tự, khớp bản cài đặt độc lập', () {
      const vectors = {0: 'VH8YJ', 59: '2YXGV', 1111111109: 'CWDGV', 1234567890: 'K8G5W', 2000000000: 'HNCVQ'};
      vectors.forEach((t, expected) {
        expect(Otp.steamAt(secret: secret, unixSeconds: t), expected, reason: 'tại $t');
      });
    });

    test('Otp.code theo kind: totp, steam, hotp', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1234567890 * 1000, isUtc: true);
      const base = 'JBSWY3DPEHPK3PXP';
      expect(Otp.code(const TotpParams(secret: base, kind: 'steam', digits: 5), now), 'K8G5W');
      expect(Otp.code(const TotpParams(secret: base), now), Otp.totpAt(secret: secret, unixSeconds: 1234567890));
      final h0 = Otp.code(const TotpParams(secret: base, kind: 'hotp', counter: 0), now);
      final h1 = Otp.code(const TotpParams(secret: base, kind: 'hotp', counter: 1), now);
      expect(h0, Otp.hotp(secret: secret, counter: 0));
      expect(h1, Otp.hotp(secret: secret, counter: 1));
      expect(h0, isNot(h1));
    });

    test('HOTP: tăng bộ đếm đổi mã; kind và counter được lưu qua JSON', () {
      const p = TotpParams(secret: 'JBSWY3DPEHPK3PXP', kind: 'hotp', counter: 4);
      final next = p.copyWith(counter: 5);
      expect(next.counter, 5);
      expect(TotpParams.fromJson(next.toJson()), next);
      expect(TotpParams.fromJson(const TotpParams(secret: 'JBSWY3DPEHPK3PXP').toJson()).kind, 'totp');
      expect(const TotpParams(secret: 'JBSWY3DPEHPK3PXP').toJson().containsKey('kind'), isFalse);
    });

    test('link otpauth: encoder=steam được nhận và ghi lại', () {
      final o = OtpAuth.parse('otpauth://totp/Steam:me?secret=JBSWY3DPEHPK3PXP&issuer=Steam&encoder=steam');
      expect(o.steam, isTrue);
      expect(o.toParams().kind, 'steam');
      expect(OtpAuth.parse(o.toUri()).steam, isTrue);
    });
  });
}
