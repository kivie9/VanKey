// Chọn máy chủ: máy chủ VanKey (địa chỉ chính + địa chỉ phụ) hoặc máy chủ tự dựng.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/constants.dart';
import 'package:vankey/app/screens/onboarding_screen.dart';
import 'package:vankey/app/screens/server_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/sync/cloudflare_sync.dart';

Future<VaultController> _open(Directory dir) async {
  final c = VaultController();
  await c.init(dir: dir);
  addTearDown(c.dispose);
  return c;
}

Future<void> _size(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  group('lưu cấu hình', () {
    late Directory dir;
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('vk_server_');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('mặc định là máy chủ VanKey; self-host và mã mời còn nguyên sau khi mở lại app và xóa kho', () async {
      final a = await _open(dir);
      expect(a.isSelfHost, isFalse);
      expect(a.serverUrl, 'https://vankeyapp.onigix.com');

      await a.setServer(selfHostUrl: ' https://kho.example.com/ ', inviteCode: ' ma-moi-rat-dai ');
      expect(a.serverUrl, 'https://kho.example.com');
      await a.resetVault();

      final b = await _open(dir);
      expect(b.serverUrl, 'https://kho.example.com');
      expect(b.serverName, 'kho.example.com');
      expect(b.serverInviteCode, 'ma-moi-rat-dai');

      await b.setServer();
      final c = await _open(dir);
      expect(c.isSelfHost, isFalse);
      expect(c.serverInviteCode, isEmpty);
    });

    test('địa chỉ không an toàn bị bỏ qua; địa chỉ chính hay phụ không tính là self-host', () async {
      final a = await _open(dir);
      await a.setServer(selfHostUrl: 'https://kho.example.com');
      await a.setServer(selfHostUrl: 'http://kho.example.com');
      expect(a.serverUrl, 'https://kho.example.com');

      for (final u in [ServerPolicy.defaultUrl, '${ServerPolicy.backupUrl}/']) {
        await a.setServer(selfHostUrl: u);
        expect(a.isSelfHost, isFalse, reason: u);
      }
    });

    Future<VaultController> openOldInstall(String url) async {
      File('${dir.path}/${Storage.settingsFile}').writeAsStringSync(jsonEncode({
        'sync': {'type': 'cloudflare', 'url': url, 'username': 'a.b'},
      }));
      final session = CloudflareSession(baseUrl: url, accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.now(), deviceId: 'd', accountId: 'i', username: 'a.b');
      await const FlutterSecureStorage().write(key: 'cloudflare.session', value: jsonEncode(session.toJson()));
      return _open(dir);
    }

    test('bản cũ đang đăng nhập địa chỉ phụ: chuyển sang địa chỉ chính, không thành self-host', () async {
      final c = await openOldInstall(ServerPolicy.backupUrl);
      expect(c.isSelfHost, isFalse);
      expect(c.cfSession!.baseUrl, ServerPolicy.defaultUrl);
    });

    test('bản cũ đang đăng nhập máy chủ riêng: tự nhận là self-host, giữ nguyên địa chỉ', () async {
      final c = await openOldInstall('https://kho.example.com');
      expect(c.serverUrl, 'https://kho.example.com');
      expect(c.cfSession!.baseUrl, 'https://kho.example.com');
    });
  });

  group('giao diện', () {
    testWidgets('màn đăng nhập: mở cấu hình, chọn self-host, lưu xong tên máy chủ hiện ở màn đăng nhập', (tester) async {
      await _size(tester);
      FlutterSecureStorage.setMockInitialValues({});
      final c = VaultController();
      await tester.pumpWidget(MaterialApp(
        home: ListenableBuilder(listenable: c, builder: (_, _) => OnboardingScreen(controller: c, serverOnly: true)),
      ));
      await tester.tap(find.text('Máy chủ: vankeyapp.onigix.com'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), findsNothing, reason: 'máy chủ VanKey không cần cấu hình');

      await tester.tap(find.text('Tự dựng máy chủ (self-host)'));
      await tester.pump();
      bool canSave() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Lưu')).onPressed != null;
      expect(canSave(), isFalse);
      await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), 'http://kho.example.com');
      await tester.pump();
      expect(canSave(), isFalse);
      expect(find.text('Địa chỉ máy chủ phải bắt đầu bằng https://'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Địa chỉ máy chủ'), 'https://kho.example.com');
      await tester.pump();
      // Lưu có ghi file cài đặt nên cần chạy ngoài đồng hồ giả của test.
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Máy chủ: kho.example.com'), findsOneWidget);
    });

    testWidgets('đang đăng nhập: cấu hình máy chủ chỉ xem, không sửa được', (tester) async {
      await _size(tester);
      final c = VaultController()
        ..cfSession = CloudflareSession(baseUrl: ServerPolicy.defaultUrl, accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.now(), deviceId: 'd', accountId: 'i', username: 'a.b');
      await tester.pumpWidget(MaterialApp(home: ServerScreen(controller: c)));
      expect(find.text(ServerPolicy.defaultUrl), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Lưu'), findsNothing);
    });
  });
}
