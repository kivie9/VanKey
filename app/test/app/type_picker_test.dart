import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/labels.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

void main() {
  late VaultController c;
  setUp(() => c = VaultController()..debugUnlock());

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(412, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c)));
    await t.pump();
  }

  testWidgets('cả 7 loại hiện sẵn trên một hàng, chỉ icon (có tên khi nhấn giữ)', (t) async {
    await open(t);
    final ys = <double>{};
    for (final type in ItemType.values) {
      final tile = find.byTooltip(L.type(type));
      expect(tile, findsOneWidget, reason: L.type(type));
      ys.add(t.getCenter(tile).dy);
      expect(find.descendant(of: tile, matching: find.byType(Text)), findsNothing, reason: 'ô loại không có chữ');
    }
    expect(ys.length, 1, reason: 'cả 7 ô nằm trên cùng một hàng');
    expect(find.byType(ListView), findsOneWidget, reason: 'chỉ còn danh sách dọc của form, không còn hàng cuộn ngang');
    final lv = t.widget<ListView>(find.byType(ListView));
    expect(lv.scrollDirection, Axis.vertical);
  });

  testWidgets('chạm một lần là đổi loại và các trường đổi theo', (t) async {
    await open(t);
    expect(find.widgetWithText(TextField, 'Tên đăng nhập'), findsOneWidget);

    await t.tap(find.byTooltip(L.type(ItemType.card)));
    await t.pump();
    expect(find.widgetWithText(TextField, 'Số thẻ'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Tên đăng nhập'), findsNothing);

    await t.tap(find.byTooltip(L.type(ItemType.wifi)));
    await t.pump();
    expect(find.widgetWithText(TextField, 'Tên mạng'), findsOneWidget);
  });

  testWidgets('lần sau mở sẵn loại vừa tạo (thẻ), không phải chọn lại', (t) async {
    await open(t);
    await t.tap(find.byTooltip(L.type(ItemType.card)));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'Tên'), 'Visa của tôi');
    await t.tap(find.text('Lưu'));
    await t.pump();
    expect(c.data.items.single.type, ItemType.card);
    expect(c.lastType, ItemType.card);

    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c)));
    await t.pump();
    expect(find.widgetWithText(TextField, 'Số thẻ'), findsOneWidget, reason: 'mở sẵn loại Thẻ');
  });

  testWidgets('mở từ "Xem nhanh/QR" (startType) vẫn ưu tiên loại được chỉ định', (t) async {
    c.lastType = ItemType.card;
    await t.binding.setSurfaceSize(const Size(412, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c, startType: ItemType.totp)));
    await t.pump();
    expect(find.widgetWithText(TextField, 'Số thẻ'), findsNothing);
  });
}
