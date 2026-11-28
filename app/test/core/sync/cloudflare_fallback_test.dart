// Địa chỉ phụ của máy chủ VanKey: chỉ dùng khi không kết nối được địa chỉ chính.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/sync/cloudflare_sync.dart';
import 'package:vankey/core/sync/sync_provider.dart';

void main() {
  group('địa chỉ phụ', () {
    Future<HttpServer> serve(List<String> hits) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((r) {
        hits.add(r.uri.path);
        r.response.write('ok');
        r.response.close();
      });
      addTearDown(() => s.close(force: true));
      return s;
    }

    Future<String> closedUrl() async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final url = 'http://127.0.0.1:${s.port}';
      await s.close();
      return url;
    }

    test('không kết nối được địa chỉ chính thì dùng địa chỉ phụ', () async {
      final hits = <String>[];
      final backup = await serve(hits);
      final main = await closedUrl();
      final api = CloudflareApi(fallbacks: {main: 'http://127.0.0.1:${backup.port}'});
      final (status, _, _) = await api.send('GET', '$main/', '/vault');
      expect(status, 200);
      expect(hits, ['/vault']);
    });

    test('địa chỉ chính chạy được thì không đụng địa chỉ phụ', () async {
      final mainHits = <String>[], backupHits = <String>[];
      final main = await serve(mainHits);
      final backup = await serve(backupHits);
      final url = 'http://127.0.0.1:${main.port}';
      final api = CloudflareApi(fallbacks: {url: 'http://127.0.0.1:${backup.port}'});
      await api.send('GET', url, '/vault');
      expect(mainHits, ['/vault']);
      expect(backupHits, isEmpty);
    });

    test('máy chủ tự dựng không kết nối được thì báo lỗi, không chuyển đi đâu', () async {
      final hits = <String>[];
      final other = await serve(hits);
      final api = CloudflareApi(fallbacks: {await closedUrl(): 'http://127.0.0.1:${other.port}'});
      await expectLater(api.send('GET', await closedUrl(), '/vault'), throwsA(isA<SyncNetworkException>()));
      expect(hits, isEmpty);
    });
  });
}
