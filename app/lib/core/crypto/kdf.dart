import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../errors.dart';

/// Tham số Argon2id, đặt tên theo libsodium (`crypto_pwhash`) để khớp đặc tả `docs/vault-format.md`.
///
/// Ánh xạ sang thư viện Dart: `iterations = opslimit`, `memory(KiB) = memlimitBytes / 1024`, song song hóa = 1.
final class Argon2Params {
  const Argon2Params({required this.opslimit, required this.memlimitBytes});

  final int opslimit;
  final int memlimitBytes;

  /// Mặc định dự kiến (chốt sau khi đo trên Android, xem `docs/spike-m0.md`).
  static const standard = Argon2Params(opslimit: 3, memlimitBytes: 64 * 1024 * 1024);

  // Cận dưới và cận trên bắt buộc khi đọc từ file (chống hạ tham số và chống file độc).
  static const minOps = 2;
  static const maxOps = 20;
  static const minMemBytes = 32 * 1024 * 1024;
  static const maxMemBytes = 1024 * 1024 * 1024;

  /// Ném [WeakKdfParametersException] nếu tham số ngoài khoảng cho phép.
  void validate() {
    if (opslimit < minOps || opslimit > maxOps) {
      throw const WeakKdfParametersException('opslimit nằm ngoài khoảng cho phép');
    }
    if (memlimitBytes < minMemBytes || memlimitBytes > maxMemBytes || memlimitBytes % 1024 != 0) {
      throw const WeakKdfParametersException('memlimit nằm ngoài khoảng cho phép');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Argon2Params && other.opslimit == opslimit && other.memlimitBytes == memlimitBytes;

  @override
  int get hashCode => Object.hash(opslimit, memlimitBytes);
}

/// Các hàm dẫn xuất khóa.
///
/// Lưu ý: Argon2id với tham số chuẩn chạy khoảng 1 giây trên CPU; khi gọi từ giao diện
/// phải chạy trong isolate riêng để không đứng hình (làm ở tầng ứng dụng, M2).
final class Kdf {
  const Kdf();

  static const saltLength = 16;
  static const keyLength = 32;

  /// Argon2id (RFC 9106, v1.3) → khóa 32 byte. Tương đương libsodium `crypto_pwhash(ALG_ARGON2ID13)`.
  Future<Uint8List> argon2id({
    required Uint8List passphraseBytes,
    required Uint8List salt,
    required Argon2Params params,
  }) async {
    params.validate();
    if (salt.length != saltLength) {
      throw const InvalidInputException('salt phải dài 16 byte');
    }
    final algo = Argon2id(
      memory: params.memlimitBytes ~/ 1024,
      parallelism: 1,
      iterations: params.opslimit,
      hashLength: keyLength,
    );
    final key = await algo.deriveKey(secretKey: SecretKey(passphraseBytes), nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }

  /// HKDF-SHA256 (RFC 5869).
  Future<Uint8List> hkdfSha256({
    required Uint8List ikm,
    required Uint8List salt,
    required Uint8List info,
    int length = keyLength,
  }) async {
    if (length <= 0 || length > 255 * 32) {
      throw const InvalidInputException('độ dài HKDF không hợp lệ');
    }
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: length);
    final out = await hkdf.deriveKey(secretKey: SecretKey(ikm), nonce: salt, info: info);
    return Uint8List.fromList(await out.extractBytes());
  }
}
