import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Chạy server TypeScript thật bằng Node (lưu trong bộ nhớ) để test đầu cuối. Cần Node 22.6+.
class NodeServer {
  NodeServer._(this.process, this.url);
  final Process process;
  final String url;

  static Future<bool> available() async {
    try {
      return (await Process.run('node', ['--version'])).exitCode == 0;
    } on Object {
      return false;
    }
  }

  /// Máy chủ thử cho đăng ký mở. [registerCode] != null thì bật mã mời.
  static Future<NodeServer> start({String? registerCode}) async {
    final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = sock.port;
    await sock.close();
    final p = await Process.start(
      'node',
      ['dev/serve.ts', '$port'],
      workingDirectory: '../server',
      environment: {'REGISTER_CODE': ?registerCode},
    );
    final ready = Completer<void>();
    p.stdout.transform(utf8.decoder).listen((s) {
      if (s.contains('LISTENING') && !ready.isCompleted) ready.complete();
    });
    unawaited(p.stderr.drain<void>());
    await ready.future.timeout(const Duration(seconds: 20));
    return NodeServer._(p, 'http://127.0.0.1:$port');
  }

  void stop() => process.kill();
}
