import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/desktop_home.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/item_detail_screen.dart';
import 'package:vankey/app/screens/settings_tab.dart';
import 'package:vankey/app/theme.dart';
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
    expect(find.byType(DesktopHome), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: _ctrl())));
    await tester.pump();
    expect(find.byType(SliverGrid), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('máy tính: thanh bên lọc theo thẻ, mở các trang, Kho không hiện mục 2FA', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = _ctrl();
    c.upsert(Item.create(type: ItemType.totp, title: 'Discord', clock: c.clock, totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP')));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.build(Brightness.light, 0), home: HomeScreen(controller: c)));
    await tester.pump();
    expect(find.text('Ngân hàng'), findsOneWidget);
    expect(find.text('Discord'), findsNothing);

    // "Mạng xã hội" xuất hiện ở thanh bên (đầu tiên) và ở tiêu đề nhóm (chữ hoa).
    await tester.tap(find.text('Mạng xã hội'));
    await tester.pump();
    expect(find.text('Ngân hàng'), findsNothing);
    expect(find.text('Gmail'), findsOneWidget);

    await tester.tap(find.text('Mã 2FA'));
    await tester.pump();
    expect(find.text('Discord'), findsOneWidget);
    expect(find.text('Gmail'), findsNothing);

    await tester.tap(find.text('Tiện ích'));
    await tester.pump();
    expect(find.text('Thùng rác'), findsOneWidget);

    await tester.tap(find.text('Cài đặt'));
    await tester.pump();
    expect(find.text('Bảo mật'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('máy tính: chi tiết mở trong hộp thoại; xóa mục cuối của thẻ đang lọc thì về Tất cả', (tester) async {
    await tester.binding.setSurfaceSize(const Size(840, 600)); // bề rộng nhỏ nhất của bố cục máy tính
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = _ctrl();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.build(Brightness.dark, 0), home: HomeScreen(controller: c)));
    await tester.pump();

    await tester.tap(find.text('Ngân hàng'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(ItemDetailScreen), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('Tiền'));
    await tester.pump();
    c.trash(c.data.items.firstWhere((i) => i.title == 'Ngân hàng'));
    await tester.pump();
    expect(find.text('Gmail'), findsOneWidget);
    expect(find.text('Tiền'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5)); // cho các bộ hẹn giờ ngắn chạy xong
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
