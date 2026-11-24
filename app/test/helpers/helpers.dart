import 'dart:math';
import 'dart:typed_data';

import 'package:vankey/core/crypto/csprng.dart';

/// Chuỗi hex → byte (bỏ khoảng trắng).
Uint8List hex(String s) {
  final c = s.replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList([for (var i = 0; i < c.length; i += 2) int.parse(c.substring(i, i + 2), radix: 16)]);
}

String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Nguồn ngẫu nhiên **có hạt giống cố định**, chỉ dùng cho test (kết quả lặp lại được).
final class SeededRandom implements RandomSource {
  SeededRandom(int seed) : _random = Random(seed);

  final Random _random;

  @override
  Uint8List bytes(int n) => Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  @override
  int nextInt(int max) => _random.nextInt(max);
}
