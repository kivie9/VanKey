import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/generator_screen.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/settings_tab.dart';
import 'package:vankey/app/vault_controller.dart';

void main() {
  late VaultController c;
  setUp(() => c = VaultController()..debugUnlock());

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await t.pump();
  }

  testWidgets('tab thứ ba là Tiện ích: lưới các chức năng, bấm ô mở đúng màn', (t) async {
    await open(t);
    await t.tap(find.text('Tiện ích').last);
    await t.pumpAndSettle();
    for (final s in ['Xem nhanh 2FA', 'Tạo mật khẩu', 'Kiểm tra bảo mật', 'Nhắc nhở', 'Mục trùng lặp', 'Thùng rác', 'Quét QR', 'Nhập dữ liệu']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    await t.tap(find.text('Tạo mật khẩu'));
    await t.pumpAndSettle();
    expect(find.byType(GeneratorScreen), findsOneWidget);
  });

  testWidgets('bánh răng góc trên trái mở trang Cài đặt, từ cả tab Kho và Tiện ích', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Cài đặt'));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Chủ đề'), findsOneWidget);
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    await t.tap(find.text('Tiện ích').last);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Cài đặt'));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
