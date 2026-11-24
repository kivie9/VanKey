import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/crypto/aead.dart';
import 'package:vankey/core/crypto/csprng.dart';
import 'package:vankey/core/crypto/kdf.dart';
import 'package:vankey/core/crypto/passphrase.dart';
import 'package:vankey/core/crypto/recovery_key.dart';
import 'package:vankey/core/errors.dart';

import '../../helpers/helpers.dart';

void main() {
  // Test vector nguyên thủy đã đối chiếu với libsodium (xem docs/spike-m0.md).
  final vec = jsonDecode(File('test/vectors/primitives-v0.json').readAsStringSync()) as Map<String, dynamic>;
  final argonVec = vec['argon2id'] as Map<String, dynamic>;
  final aeadVec = vec['aead'] as Map<String, dynamic>;

  group('Aead (XChaCha20-Poly1305)', () {
    test('khớp test vector chính thức draft-irtf-cfrg-xchacha A.3.1', () async {
      final key = hex('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
      final nonce = hex('404142434445464748494a4b4c4d4e4f5051525354555657');
      final aad = hex('50515253c0c1c2c3c4c5c6c7');
      final plain = Uint8List.fromList(utf8.encode(
          "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."));
      final sealed = await Aead.seal(key: key, nonce: nonce, plaintext: plain, aad: aad);
      expect(
        toHex(sealed),
        'bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b4522f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff921f9664c97637da9768812f615c68b13b52e'
        'c0875924c1c7987947deafd8780acf49',
      );
      expect(await Aead.open(key: key, nonce: nonce, sealed: sealed, aad: aad), plain);
    });

    test('khớp vector đã đối chiếu với libsodium (có tiếng Việt)', () async {
      final sealed = await Aead.seal(
        key: hex(aeadVec['keyHex'] as String),
        nonce: hex(aeadVec['nonceHex'] as String),
        plaintext: hex(aeadVec['plainHex'] as String),
        aad: hex(aeadVec['aadHex'] as String),
      );
      expect(toHex(sealed), (aeadVec['cipherHex'] as String) + (aeadVec['tagHex'] as String));
    });

    test('sai khóa, sai nonce, sai AAD, sửa bản mã, sửa tag → đều lỗi xác thực', () async {
      final key = Csprng().bytes(32);
      final nonce = Csprng().bytes(24);
      final aad = Uint8List.fromList([1, 2, 3]);
      final sealed = await Aead.seal(key: key, nonce: nonce, plaintext: Uint8List.fromList(List.generate(50, (i) => i)), aad: aad);

      Future<void> expectAuthFail(Uint8List k, Uint8List n, Uint8List s, Uint8List a) =>
          expectLater(Aead.open(key: k, nonce: n, sealed: s, aad: a), throwsA(isA<AuthenticationFailedException>()));

      await expectAuthFail(Csprng().bytes(32), nonce, sealed, aad);
      await expectAuthFail(key, Csprng().bytes(24), sealed, aad);
      await expectAuthFail(key, nonce, sealed, Uint8List.fromList([1, 2, 4]));
      await expectAuthFail(key, nonce, Uint8List.fromList(sealed)..[5] ^= 1, aad);
      await expectAuthFail(key, nonce, Uint8List.fromList(sealed)..[sealed.length - 1] ^= 1, aad);
    });

    test('dữ liệu quá ngắn → CorruptVaultException; độ dài khóa/nonce sai → InvalidInputException', () async {
      final key = Csprng().bytes(32);
      final nonce = Csprng().bytes(24);
      await expectLater(Aead.open(key: key, nonce: nonce, sealed: Uint8List(5)), throwsA(isA<CorruptVaultException>()));
      await expectLater(Aead.seal(key: Uint8List(31), nonce: nonce, plaintext: Uint8List(1)), throwsA(isA<InvalidInputException>()));
      await expectLater(Aead.seal(key: key, nonce: Uint8List(12), plaintext: Uint8List(1)), throwsA(isA<InvalidInputException>()));
    });

    test('bản rõ rỗng vẫn mã hóa/giải mã được (chỉ còn tag)', () async {
      final key = Csprng().bytes(32);
      final nonce = Csprng().bytes(24);
      final sealed = await Aead.seal(key: key, nonce: nonce, plaintext: Uint8List(0));
      expect(sealed.length, 16);
      expect(await Aead.open(key: key, nonce: nonce, sealed: sealed), isEmpty);
    });
  });

  group('Kdf', () {
    const kdf = Kdf();

    test('Argon2id khớp vector đã đối chiếu với libsodium (64 MiB, 3 vòng)', () async {
      final key = await kdf.argon2id(
        passphraseBytes: normalizePassphrase(argonVec['passphrase'] as String),
        salt: hex(argonVec['saltHex'] as String),
        params: Argon2Params(opslimit: argonVec['opslimit'] as int, memlimitBytes: argonVec['memlimitBytes'] as int),
      );
      expect(toHex(key), argonVec['keyHex']);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Argon2id: cùng đầu vào cùng khóa, khác salt khác khóa', () async {
      const p = Argon2Params(opslimit: 2, memlimitBytes: 32 * 1024 * 1024);
      final pass = normalizePassphrase('abc');
      final s1 = Uint8List.fromList(List.generate(16, (i) => i));
      final s2 = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final a = await kdf.argon2id(passphraseBytes: pass, salt: s1, params: p);
      final b = await kdf.argon2id(passphraseBytes: pass, salt: s1, params: p);
      final c = await kdf.argon2id(passphraseBytes: pass, salt: s2, params: p);
      expect(a, b);
      expect(a, isNot(c));
      expect(a.length, 32);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('từ chối tham số quá yếu hoặc quá nặng, salt sai độ dài', () async {
      final pass = normalizePassphrase('x');
      final salt = Uint8List(16);
      for (final bad in const [
        Argon2Params(opslimit: 1, memlimitBytes: 64 * 1024 * 1024),
        Argon2Params(opslimit: 3, memlimitBytes: 16 * 1024 * 1024),
        Argon2Params(opslimit: 99, memlimitBytes: 64 * 1024 * 1024),
        Argon2Params(opslimit: 3, memlimitBytes: 2 * 1024 * 1024 * 1024),
        Argon2Params(opslimit: 3, memlimitBytes: 64 * 1024 * 1024 + 1),
      ]) {
        await expectLater(kdf.argon2id(passphraseBytes: pass, salt: salt, params: bad), throwsA(isA<WeakKdfParametersException>()));
      }
      await expectLater(
          kdf.argon2id(passphraseBytes: pass, salt: Uint8List(8), params: Argon2Params.standard), throwsA(isA<InvalidInputException>()));
    });

    test('HKDF-SHA256 khớp RFC 5869 (test case 1 và 3)', () async {
      final ikm = Uint8List.fromList(List.filled(22, 0x0b));
      final okm1 = await kdf.hkdfSha256(
        ikm: ikm,
        salt: hex('000102030405060708090a0b0c'),
        info: hex('f0f1f2f3f4f5f6f7f8f9'),
        length: 42,
      );
      expect(toHex(okm1), '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');
      final okm3 = await kdf.hkdfSha256(ikm: ikm, salt: Uint8List(0), info: Uint8List(0), length: 42);
      expect(toHex(okm3), '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8');
    });
  });

  group('normalizePassphrase (NFKC)', () {
    test('chữ Việt dựng sẵn và tổ hợp cho cùng chuỗi byte', () {
      const composed = 'Việt Nam'; // ệ dựng sẵn
      const decomposed = 'Việt Nam'; // e + dấu chấm dưới + dấu mũ
      expect(composed == decomposed, isFalse, reason: 'hai chuỗi gốc phải khác nhau');
      expect(normalizePassphrase(composed), normalizePassphrase(decomposed));
    });

    test('ký tự toàn chiều rộng được đưa về dạng thường (NFKC)', () {
      expect(normalizePassphrase('ＡＢＣ１２３'), normalizePassphrase('ABC123'));
    });

    test('không cắt khoảng trắng, phân biệt hoa thường', () {
      expect(normalizePassphrase(' a '), isNot(normalizePassphrase('a')));
      expect(normalizePassphrase('A'), isNot(normalizePassphrase('a')));
    });
  });

  group('RecoveryKey', () {
    test('định dạng 6 nhóm x 4 ký tự, đúng bảng chữ', () {
      final k = RecoveryKey.generate(SeededRandom(1));
      expect(k.formatted, matches(RegExp(r'^[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){5}$')));
      expect(k.raw.length, 24);
      expect(k.bytes.length, 15);
    });

    test('vòng đi vòng lại 300 khóa ngẫu nhiên', () {
      final rnd = SeededRandom(42);
      for (var i = 0; i < 300; i++) {
        final k = RecoveryKey.generate(rnd);
        expect(RecoveryKey.parse(k.formatted).bytes, k.bytes);
        expect(RecoveryKey.parse(k.raw).bytes, k.bytes);
      }
    });

    test('chấp nhận chữ thường, khoảng trắng và gạch ngang thừa', () {
      final k = RecoveryKey.generate(SeededRandom(7));
      final messy = ' ${k.formatted.toLowerCase().replaceAll('-', ' - ')} ';
      expect(RecoveryKey.parse(messy).bytes, k.bytes);
    });

    test('từ chối sai độ dài và ký tự ngoài bảng (0 O 1 I)', () {
      expect(() => RecoveryKey.parse('ABCD'), throwsA(isA<InvalidInputException>()));
      expect(() => RecoveryKey.parse('${'A' * 23}0'), throwsA(isA<InvalidInputException>()));
      expect(() => RecoveryKey.parse('${'A' * 23}O'), throwsA(isA<InvalidInputException>()));
      expect(() => RecoveryKey.parse('${'A' * 23}1'), throwsA(isA<InvalidInputException>()));
      expect(() => RecoveryKey.parse('${'A' * 23}I'), throwsA(isA<InvalidInputException>()));
    });

    test('wipe ghi đè 0', () {
      final k = RecoveryKey.generate(SeededRandom(3))..wipe();
      expect(k.bytes.every((b) => b == 0), isTrue);
    });
  });

  group('Csprng', () {
    test('byte đúng độ dài, nhiều lần gọi cho kết quả khác nhau', () {
      final r = Csprng();
      expect(r.bytes(32).length, 32);
      expect(r.bytes(32), isNot(r.bytes(32)));
    });

    test('nextInt luôn trong khoảng', () {
      final r = Csprng();
      for (var i = 0; i < 1000; i++) {
        final v = r.nextInt(7);
        expect(v >= 0 && v < 7, isTrue);
      }
    });

    test('uuidV4 đúng định dạng, version 4, variant 10xx', () {
      final u = uuidV4();
      expect(u, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(uuidV4(), isNot(u));
    });
  });
}
