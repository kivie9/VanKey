import 'dart:math';
import 'dart:typed_data';

/// Nguồn ngẫu nhiên. Tách ra thành giao diện để test có thể thay bằng nguồn cố định.
abstract interface class RandomSource {
  /// [n] byte ngẫu nhiên.
  Uint8List bytes(int n);

  /// Số nguyên đều trong `[0, max)`, **không thiên lệch modulo**.
  int nextInt(int max);
}

/// Nguồn ngẫu nhiên an toàn mật mã của hệ điều hành (`Random.secure()`).
final class Csprng implements RandomSource {
  Csprng() : _random = Random.secure();

  final Random _random;

  @override
  Uint8List bytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  @override
  int nextInt(int max) => _random.nextInt(max);
}

/// UUID v4 (chuỗi chữ thường, có gạch ngang).
String uuidV4([RandomSource? random]) {
  final b = (random ?? Csprng()).bytes(16);
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int from, int to) =>
      b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
