import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/settings_tab.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

VaultController _ctrl() {
  final c = VaultController()..debugUnlock();
  c.upsert(Item.create(type: ItemType.login, title: 'Ngân hàng', clock: c.clock, group: 'Tiền'));
  c.upsert(Item.create(type: ItemType.login, title: 'Facebook', clock: c.clock, group: 'Mạng xã hội'));
  c.upsert(Item.create(type: ItemType.login, title: 'Gmail', clock: c.clock, group: 'Mạng xã hội'));
  return c;
}

void main() {
  testWidgets('màn rộng: danh sách dạng lưới nhiều cột, điện thoại: danh sách một cột', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: _ctrl())));
    await tester.pump();
    expect(find.byType(SliverGrid), findsWidgets);
    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: _ctrl())));
    await tester.pump();
    expect(find.byType(SliverGrid), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('lọc theo nhóm từ icon bộ lọc', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: _ctrl())));
    await tester.pump();
    expect(find.text('Ngân hàng'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mạng xã hội').last);
    await tester.pumpAndSettle();

    expect(find.text('Ngân hàng'), findsNothing);
    expect(find.text('Facebook'), findsOneWidget);
    expect(find.text('Gmail'), findsOneWidget);
  });

  testWidgets('Cài đặt có đủ 7 menu và mở được trang con', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = _ctrl();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsTab(controller: c))));
    for (final t in ['Tài khoản', 'Dữ liệu', 'Bảo mật', 'Chủ đề', 'Chung', 'Hỗ trợ', 'Giới thiệu']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.tap(find.text('Dữ liệu'));
    await tester.pumpAndSettle();
    expect(find.text('Thùng rác'), findsOneWidget);
    expect(find.text('Nhập dữ liệu'), findsOneWidget);
  });
}
