import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../errors.dart';

/// Mã hóa xác thực **XChaCha20-Poly1305** (tương đương libsodium `crypto_aead_xchacha20poly1305_ietf`).
///
/// Đầu ra của [seal] là `bản mã || tag(16 byte)`; nonce do người gọi cung cấp và lưu riêng.
/// **Mỗi lần mã hóa phải dùng nonce mới** (nonce 24 byte ngẫu nhiên là đủ an toàn).
abstract final class Aead {
  static const keyLength = 32;
  static const nonceLength = 24;
  static const tagLength = 16;

  static final Xchacha20 _algo = Xchacha20.poly1305Aead();

  static void _check(Uint8List key, Uint8List nonce) {
    if (key.length != keyLength) throw const InvalidInputException('khóa phải dài 32 byte');
    if (nonce.length != nonceLength) throw const InvalidInputException('nonce phải dài 24 byte');
  }

  static Future<Uint8List> seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
    Uint8List? aad,
  }) async {
    _check(key, nonce);
    final box = await _algo.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad ?? const <int>[],
    );
    final out = Uint8List(box.cipherText.length + tagLength)
      ..setRange(0, box.cipherText.length, box.cipherText)
      ..setRange(box.cipherText.length, box.cipherText.length + tagLength, box.mac.bytes);
    return out;
  }

  /// Giải mã và **xác thực**. Sai khóa, sai nonce, sai AAD hoặc bản mã bị sửa → [AuthenticationFailedException].
  /// Không bao giờ trả dữ liệu một phần.
  static Future<Uint8List> open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List sealed,
    Uint8List? aad,
  }) async {
    _check(key, nonce);
    if (sealed.length < tagLength) {
      throw const CorruptVaultException('dữ liệu mã hóa quá ngắn');
    }
    final split = sealed.length - tagLength;
    final box = SecretBox(
      Uint8List.sublistView(sealed, 0, split),
      nonce: nonce,
      mac: Mac(Uint8List.sublistView(sealed, split)),
    );
    try {
      final plain = await _algo.decrypt(box, secretKey: SecretKey(key), aad: aad ?? const <int>[]);
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const AuthenticationFailedException();
    }
  }
}
