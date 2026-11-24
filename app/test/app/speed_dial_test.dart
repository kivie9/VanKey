import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/vault_controller.dart';

void main() {
  Future<VaultController> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = VaultController()..debugUnlock();
    await t.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await t.pump();
    await t.tap(find.byTooltip('Thêm mục'));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('bấm vào CHỮ "Nhập tay" cũng mở màn thêm mục (không chỉ icon)', (t) async {
    await open(t);
    await t.tap(find.text('Nhập tay'));
    await t.pumpAndSettle();
    expect(find.byType(ItemEditorScreen), findsOneWidget);
  });

  testWidgets('menu dấu cộng không còn "Xem nhanh 2FA"', (t) async {
    await open(t);
    expect(find.text('Xem nhanh 2FA'), findsNothing);
    expect(find.text('Quét QR'), findsOneWidget);
  });

  testWidgets('bấm icon tròn vẫn hoạt động như cũ, và menu tự đóng sau khi chọn', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Nhập tay'));
    await t.pumpAndSettle();
    expect(find.byType(ItemEditorScreen), findsOneWidget);
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    expect(find.text('Nhập tay'), findsNothing, reason: 'menu đã đóng');
  });
}
