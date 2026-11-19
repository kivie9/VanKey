// M0 — đo thời gian Argon2id (thuần Dart) ở chế độ AOT, gần với bản phát hành hơn `flutter test`.
// Chạy:  dart compile exe test/spike/argon2_bench.dart -o build/argon2_bench.exe  rồi chạy file exe.
import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final salt = List<int>.generate(16, (i) => i);
  // (vòng lặp, bộ nhớ KiB). libsodium: opslimit = vòng lặp, memlimit = KiB * 1024 byte.
  final cases = <(int, int)>[(1, 16384), (2, 32768), (3, 65536), (3, 131072)];
  for (final (iter, mem) in cases) {
    final a = Argon2id(memory: mem, parallelism: 1, iterations: iter, hashLength: 32);
    final sw = Stopwatch()..start();
    await a.deriveKeyFromPassword(password: 'khoa thu nghiem', nonce: salt);
    sw.stop();
    // ignore: avoid_print
    print('Argon2id t=$iter m=${mem ~/ 1024}MiB : ${sw.elapsedMilliseconds} ms');
  }
}
