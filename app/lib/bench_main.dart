// Ứng dụng đo tốc độ Argon2id trên thiết bị thật (không phải app chính).
//   flutter run --release -t lib/bench_main.dart
// Phải chạy bản --release: bản debug chậm hơn nhiều lần và cho số đo sai.
import 'dart:isolate';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:vankey/core/crypto/kdf.dart';

void main() => runApp(const BenchApp());

class BenchApp extends StatelessWidget {
  const BenchApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        title: 'VanKey Bench',
        home: BenchPage(),
      );
}

class _Case {
  const _Case(this.label, this.params);
  final String label;
  final Argon2Params params;
}

const _mib = 1024 * 1024;
const _cases = [
  _Case('2 vòng, 32 MiB (tối thiểu)', Argon2Params(opslimit: 2, memlimitBytes: 32 * _mib)),
  _Case('3 vòng, 64 MiB (chuẩn)', Argon2Params.standard),
  _Case('4 vòng, 64 MiB', Argon2Params(opslimit: 4, memlimitBytes: 64 * _mib)),
  _Case('3 vòng, 128 MiB', Argon2Params(opslimit: 3, memlimitBytes: 128 * _mib)),
];

/// Chạy trong isolate riêng, trả về mili giây của từng lần đo.
Future<List<int>> _measure(Argon2Params p, int runs) {
  debugPrint('BENCH spawn ${p.opslimit}/${p.memlimitBytes}');
  return Isolate.run(() async {
    final out = <int>[];
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      await const Kdf().argon2id(
        passphraseBytes: Uint8List.fromList('thử nghiệm đo tốc độ'.codeUnits),
        salt: Uint8List(Kdf.saltLength),
        params: p,
      );
      out.add(sw.elapsedMilliseconds);
      // ignore: avoid_print
      print('BENCH run $i = ${sw.elapsedMilliseconds} ms');
    }
    return out;
  });
}

class BenchPage extends StatefulWidget {
  const BenchPage({super.key});

  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  final _lines = <String>[];
  bool _running = false;
  int _ticks = 0; // chứng minh giao diện không đứng hình khi đang đo

  Future<void> _run() async {
    debugPrint('BENCH button pressed');
    setState(() {
      _running = true;
      _lines.clear();
    });
    final ticker = Stream<int>.periodic(const Duration(milliseconds: 100), (n) => n).listen((_) {
      if (mounted) setState(() => _ticks++);
    });
    for (final c in _cases) {
      try {
        final ms = await _measure(c.params, 3);
        final avg = ms.reduce((a, b) => a + b) ~/ ms.length;
        _lines.add('${c.label}\n   $ms ms  →  trung bình $avg ms');
      } catch (e) {
        _lines.add('${c.label}\n   LỖI: $e');
      }
      if (mounted) setState(() {});
    }
    await ticker.cancel();
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Đo Argon2id')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton(
                onPressed: _running ? null : _run,
                child: Text(_running ? 'Đang đo… (giao diện còn sống: $_ticks)' : 'Bắt đầu đo'),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    for (final l in _lines)
                      Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(l, style: const TextStyle(fontSize: 16))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
