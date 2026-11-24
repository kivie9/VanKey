import 'dart:typed_data';

import '../errors.dart';

/// Base32 theo RFC 4648 (bảng `A-Z2-7`).
abstract final class Base32 {
  static const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String encode(List<int> data, {bool padding = false}) {
    var acc = 0;
    var bits = 0;
    final sb = StringBuffer();
    for (final x in data) {
      acc = (acc << 8) | (x & 0xff);
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        sb.write(alphabet[(acc >> bits) & 31]);
        acc &= (1 << bits) - 1;
      }
    }
    if (bits > 0) sb.write(alphabet[(acc << (5 - bits)) & 31]);
    if (padding) {
      while (sb.length % 8 != 0) {
        sb.write('=');
      }
    }
    return sb.toString();
  }

  /// Chuẩn hóa chuỗi người dùng nhập: chữ hoa, bỏ khoảng trắng, gạch ngang và dấu `=`.
  /// Ném [InvalidInputException] nếu còn ký tự ngoài bảng chữ hoặc rỗng.
  static String normalize(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s\-=]'), '');
    if (s.isEmpty) throw const InvalidInputException('khóa rỗng');
    for (var i = 0; i < s.length; i++) {
      if (!alphabet.contains(s[i])) throw const InvalidInputException('khóa có ký tự không hợp lệ (chỉ A-Z và 2-7)');
    }
    return s;
  }

  static Uint8List decode(String input) {
    final s = normalize(input);
    var acc = 0;
    var bits = 0;
    final out = <int>[];
    for (var i = 0; i < s.length; i++) {
      acc = (acc << 5) | alphabet.indexOf(s[i]);
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((acc >> bits) & 0xff);
        acc &= (1 << bits) - 1;
      }
    }
    return Uint8List.fromList(out);
  }

  static bool isValid(String input) {
    try {
      normalize(input);
      return true;
    } on InvalidInputException {
      return false;
    }
  }
}
