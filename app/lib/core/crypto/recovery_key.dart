import 'dart:typed_data';

import '../errors.dart';
import 'csprng.dart';

/// Recovery key: 24 ký tự từ bảng 32 ký hiệu → **120 bit entropy** (15 byte).
///
/// Bảng chữ bỏ `0 O 1 I` để khỏi nhầm khi đọc/chép tay. Hiển thị nhóm 4 ký tự, ngăn bằng gạch ngang.
final class RecoveryKey {
  RecoveryKey._(this.bytes);

  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const symbolCount = 24;
  static const byteLength = 15;

  /// 15 byte gốc, dùng làm nguyên liệu cho HKDF.
  final Uint8List bytes;

  factory RecoveryKey.generate([RandomSource? random]) =>
      RecoveryKey._((random ?? Csprng()).bytes(byteLength));

  /// Đọc từ chuỗi người dùng nhập: bỏ khoảng trắng và gạch ngang, không phân biệt hoa thường.
  factory RecoveryKey.parse(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (s.length != symbolCount) {
      throw const InvalidInputException('recovery key phải có 24 ký tự');
    }
    var acc = 0;
    var bits = 0;
    final out = <int>[];
    for (final ch in s.split('')) {
      final idx = alphabet.indexOf(ch);
      if (idx < 0) throw const InvalidInputException('recovery key có ký tự không hợp lệ');
      acc = (acc << 5) | idx;
      bits += 5;
      while (bits >= 8) {
        bits -= 8;
        out.add((acc >> bits) & 0xff);
        acc &= (1 << bits) - 1;
      }
    }
    return RecoveryKey._(Uint8List.fromList(out));
  }

  /// Chuỗi thô 24 ký tự.
  String get raw {
    var acc = 0;
    var bits = 0;
    final sb = StringBuffer();
    for (final x in bytes) {
      acc = (acc << 8) | x;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        sb.write(alphabet[(acc >> bits) & 31]);
        acc &= (1 << bits) - 1;
      }
    }
    return sb.toString();
  }

  /// `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`.
  String get formatted {
    final r = raw;
    return [for (var i = 0; i < r.length; i += 4) r.substring(i, i + 4)].join('-');
  }

  /// Ghi đè 0 lên các byte (mức cố gắng tối đa).
  void wipe() => bytes.fillRange(0, bytes.length, 0);
}
