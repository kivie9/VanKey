import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../errors.dart';
import '../vault/models.dart';
import 'base32.dart';

/// HOTP (RFC 4226) và TOTP (RFC 6238).
abstract final class Otp {
  static const minDigits = 6;
  static const maxDigits = 8;

  static Hash _hash(TotpAlgorithm a) => switch (a) {
        TotpAlgorithm.sha1 => sha1,
        TotpAlgorithm.sha256 => sha256,
        TotpAlgorithm.sha512 => sha512,
      };

  /// Mã HOTP cho [counter] (số nguyên không âm, tối đa 2^63-1).
  static String hotp({
    required Uint8List secret,
    required int counter,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
    int digits = 6,
  }) {
    if (digits < minDigits || digits > maxDigits) {
      throw const InvalidInputException('số chữ số phải từ 6 đến 8');
    }
    if (counter < 0) throw const InvalidInputException('bộ đếm không được âm');
    if (secret.isEmpty) throw const InvalidInputException('khóa rỗng');
    final msg = Uint8List(8)..buffer.asByteData().setUint64(0, counter);
    final mac = Hmac(_hash(algorithm), secret).convert(msg).bytes;
    final offset = mac.last & 0x0f;
    final bin = ((mac[offset] & 0x7f) << 24) |
        ((mac[offset + 1] & 0xff) << 16) |
        ((mac[offset + 2] & 0xff) << 8) |
        (mac[offset + 3] & 0xff);
    var mod = 1;
    for (var i = 0; i < digits; i++) {
      mod *= 10;
    }
    return (bin % mod).toString().padLeft(digits, '0');
  }

  /// Mã TOTP tại thời điểm [unixSeconds] (giây tính từ 1970-01-01 UTC).
  static String totpAt({
    required Uint8List secret,
    required int unixSeconds,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) {
    if (period < 1 || period > 3600) throw const InvalidInputException('chu kỳ không hợp lệ');
    return hotp(secret: secret, counter: unixSeconds ~/ period, algorithm: algorithm, digits: digits);
  }

  /// Bảng ký tự của Steam Guard.
  static const steamAlphabet = '23456789BCDFGHJKMNPQRTVWXY';

  /// Mã Steam Guard: cùng HMAC-SHA1 như TOTP nhưng đổi 31 bit cắt ra thành 5 ký tự theo [steamAlphabet].
  static String steamAt({required Uint8List secret, required int unixSeconds, int period = 30}) {
    if (secret.isEmpty) throw const InvalidInputException('khóa rỗng');
    final msg = Uint8List(8)..buffer.asByteData().setUint64(0, unixSeconds ~/ period);
    final mac = Hmac(sha1, secret).convert(msg).bytes;
    final offset = mac.last & 0x0f;
    var bin = ((mac[offset] & 0x7f) << 24) | ((mac[offset + 1] & 0xff) << 16) | ((mac[offset + 2] & 0xff) << 8) | (mac[offset + 3] & 0xff);
    final out = StringBuffer();
    for (var i = 0; i < 5; i++) {
      out.write(steamAlphabet[bin % steamAlphabet.length]);
      bin ~/= steamAlphabet.length;
    }
    return out.toString();
  }

  /// Mã hiện tại của một mục ([TotpParams], khóa dạng Base32): TOTP, HOTP hoặc Steam Guard.
  static String code(TotpParams p, DateTime now) {
    final secret = Base32.decode(p.secret);
    if (p.isHotp) return hotp(secret: secret, counter: p.counter, algorithm: p.algorithm, digits: p.digits);
    if (p.isSteam) return steamAt(secret: secret, unixSeconds: now.toUtc().millisecondsSinceEpoch ~/ 1000, period: p.period);
    return totpAt(
      secret: secret,
      unixSeconds: now.toUtc().millisecondsSinceEpoch ~/ 1000,
      algorithm: p.algorithm,
      digits: p.digits,
      period: p.period,
    );
  }

  /// Số giây còn lại của chu kỳ hiện tại (từ 1 đến [period]); dùng cho vòng đếm ngược.
  static int secondsRemaining(DateTime now, {int period = 30}) {
    final s = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    return period - (s % period);
  }

  /// Tỉ lệ thời gian còn lại của chu kỳ, trong khoảng (0, 1].
  static double fractionRemaining(DateTime now, {int period = 30}) {
    final ms = now.toUtc().millisecondsSinceEpoch % (period * 1000);
    return 1 - ms / (period * 1000);
  }

  /// Chia đôi mã để dễ đọc: `123456` → `123 456`, `12345678` → `1234 5678`.
  static String grouped(String code) {
    if (code.length == 6) return '${code.substring(0, 3)} ${code.substring(3)}';
    if (code.length == 8) return '${code.substring(0, 4)} ${code.substring(4)}';
    return code;
  }
}
