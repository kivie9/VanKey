import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/settings_tab.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/sync/cloudflare_sync.dart';

void main() {
  testWidgets('menu Cài đặt: nút Đăng xuất nằm dưới Giới thiệu, chỉ hiện khi đang đăng nhập máy chủ', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = VaultController()..debugUnlock();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsTab(controller: c))));
    expect(find.text('Đăng xuất'), findsNothing);

    c.cfSession = CloudflareSession(baseUrl: 'https://vankey.example.com', accessToken: 'a', refreshToken: 'r', expiresAt: DateTime.now(), deviceId: 'd', accountId: 'i', username: 'a.b');
    c.debugUnlock(); // báo giao diện dựng lại
    await tester.pump();
    expect(tester.getTopLeft(find.text('Đăng xuất')).dy, greaterThan(tester.getTopLeft(find.text('Giới thiệu')).dy));

    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    expect(find.text('Đăng xuất?'), findsOneWidget);
  });
}
