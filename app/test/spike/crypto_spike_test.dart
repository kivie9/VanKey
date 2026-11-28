// M0 — spike mật mã (phương án thuần Dart: package `cryptography`).
//
// Mục đích: kiểm chứng XChaCha20-Poly1305 và Argon2id chạy đúng, và xuất kết quả
// cố định để đối chiếu với libsodium độc lập (xem docs/technical/spike-m0.md).
// Đây là mã THỬ NGHIỆM, không phải mã sản phẩm.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> hex(String s) {
  final c = s.replaceAll(RegExp(r'\s'), '');
  return [for (var i = 0; i < c.length; i += 2) int.parse(c.substring(i, i + 2), radix: 16)];
}

String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final aead = Xchacha20.poly1305Aead();

  // Test vector: draft-irtf-cfrg-xchacha-03, phụ lục A.3.1
  const vecPlain =
      "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
  final vecAad = hex('50515253c0c1c2c3c4c5c6c7');
  final vecKey = hex('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
  final vecNonce = hex('404142434445464748494a4b4c4d4e4f5051525354555657');
  const vecCipher =
      'bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b4522f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff921f9664c97637da9768812f615c68b13b52e';
  const vecTag = 'c0875924c1c7987947deafd8780acf49';

  test('XChaCha20-Poly1305 khớp test vector của draft-irtf-cfrg-xchacha', () async {
    final box = await aead.encrypt(
      utf8.encode(vecPlain),
      secretKey: SecretKey(vecKey),
      nonce: vecNonce,
      aad: vecAad,
    );
    expect(toHex(box.cipherText), vecCipher);
    expect(toHex(box.mac.bytes), vecTag);
    final back = await aead.decrypt(box, secretKey: SecretKey(vecKey), aad: vecAad);
    expect(utf8.decode(back), vecPlain);
  });

  test('mã hóa rồi giải mã (khóa và nonce ngẫu nhiên)', () async {
    final key = await aead.newSecretKey();
    final nonce = aead.newNonce();
    final box = await aead.encrypt(utf8.encode('xin chào, két sắt'), secretKey: key, nonce: nonce);
    expect(nonce.length, 24);
    expect(box.mac.bytes.length, 16);
    expect(utf8.decode(await aead.decrypt(box, secretKey: key)), 'xin chào, két sắt');
  });

  test('sai khóa thì phải lỗi, không trả dữ liệu', () async {
    final key = await aead.newSecretKey();
    final wrong = await aead.newSecretKey();
    final box = await aead.encrypt([1, 2, 3, 4], secretKey: key);
    expect(() => aead.decrypt(box, secretKey: wrong), throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('sửa 1 byte bản mã hoặc tag thì phải lỗi', () async {
    final key = await aead.newSecretKey();
    final box = await aead.encrypt(List<int>.generate(64, (i) => i), secretKey: key);
    final badCipher = [...box.cipherText]..[10] ^= 1;
    final badTag = [...box.mac.bytes]..[0] ^= 1;
    expect(
      () => aead.decrypt(SecretBox(badCipher, nonce: box.nonce, mac: box.mac), secretKey: key),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    expect(
      () => aead.decrypt(SecretBox(box.cipherText, nonce: box.nonce, mac: Mac(badTag)), secretKey: key),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('AAD khác thì phải lỗi (chống sửa header)', () async {
    final key = await aead.newSecretKey();
    final box = await aead.encrypt([9, 9, 9], secretKey: key, aad: [1, 2, 3]);
    expect(
      () => aead.decrypt(box, secretKey: key, aad: [1, 2, 4]),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('Argon2id: cùng đầu vào cho cùng khóa, khác salt cho khóa khác', () async {
    final a = Argon2id(memory: 1024, parallelism: 1, iterations: 1, hashLength: 32);
    final salt1 = List<int>.generate(16, (i) => i);
    final salt2 = List<int>.generate(16, (i) => i + 1);
    final k1 = await (await a.deriveKeyFromPassword(password: 'abc', nonce: salt1)).extractBytes();
    final k1b = await (await a.deriveKeyFromPassword(password: 'abc', nonce: salt1)).extractBytes();
    final k2 = await (await a.deriveKeyFromPassword(password: 'abc', nonce: salt2)).extractBytes();
    expect(k1, k1b);
    expect(k1, isNot(k2));
    expect(k1.length, 32);
  });

  test('xuất dữ liệu cố định để đối chiếu libsodium độc lập', () async {
    // Argon2id: tương đương crypto_pwhash(opslimit=3, memlimit=64 MiB, ALG_ARGON2ID13)
    const passphrase = 'mật khẩu thử nghiệm Việt Nam 123!';
    final salt = List<int>.generate(16, (i) => 0xa0 + i);
    final argon = Argon2id(memory: 65536, parallelism: 1, iterations: 3, hashLength: 32);
    final sw = Stopwatch()..start();
    final key = await (await argon.deriveKeyFromPassword(password: passphrase, nonce: salt)).extractBytes();
    sw.stop();

    // AEAD với đầu vào cố định (khác test vector để kiểm cả nội dung tiếng Việt)
    final aeadKey = List<int>.generate(32, (i) => i * 3 + 1);
    final nonce = List<int>.generate(24, (i) => 0x10 + i);
    final aad = utf8.encode('VKV1|header');
    final plain = utf8.encode('{"items":[{"title":"Ngân hàng","pw":"Đặng Thị Ngọc"}]}');
    final box = await aead.encrypt(plain, secretKey: SecretKey(aeadKey), nonce: nonce, aad: aad);

    final out = {
      'argon2id': {
        'passphrase': passphrase,
        'saltHex': toHex(salt),
        'opslimit': 3,
        'memlimitBytes': 65536 * 1024,
        'keyHex': toHex(key),
        'dartMillis_jit': sw.elapsedMilliseconds,
      },
      'aead': {
        'keyHex': toHex(aeadKey),
        'nonceHex': toHex(nonce),
        'aadHex': toHex(aad),
        'plainHex': toHex(plain),
        'cipherHex': toHex(box.cipherText),
        'tagHex': toHex(box.mac.bytes),
      },
    };
    final dir = Directory('build')..createSync(recursive: true);
    File('${dir.path}/spike_out.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
    // ignore: avoid_print
    print('Argon2id 64MiB x3 (JIT, trong flutter test): ${sw.elapsedMilliseconds} ms');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
