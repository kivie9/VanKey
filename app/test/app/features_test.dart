import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/item_detail_screen.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

void main() {
  testWidgets('thêm trường tùy ý khi tạo mục, và sửa lại giữ nguyên trường đó', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = VaultController()..debugUnlock();
    await tester.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c)));

    await tester.enterText(find.widgetWithText(TextField, 'Tên'), 'Router');
    await tester.tap(find.text('Thêm trường tùy ý'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Tên trường'), 'Mã PIN');
    await tester.enterText(find.widgetWithText(TextField, 'Giá trị'), '4321');
    await tester.tap(find.text('Lưu'));
    await tester.pump();

    final saved = c.data.items.single;
    final custom = saved.fields.where((f) => f.key == null).toList();
    expect(custom, hasLength(1));
    expect(custom.single.label, 'Mã PIN');
    expect(custom.single.value, '4321');
    expect(custom.single.secret, isTrue, reason: 'trường tùy ý mặc định ẩn');

    // Sửa lại mục: trường tùy ý vẫn còn và sửa được.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c, existing: saved)));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Giá trị'), '9999');
    await tester.tap(find.text('Lưu'));
    await tester.pump();
    final again = c.data.byId(saved.id)!.fields.where((f) => f.key == null).single;
    expect(again.value, '9999');
  });

  testWidgets('đổi nhóm nhanh trong màn chi tiết, kể cả nhóm mới', (tester) async {
    final c = VaultController()..debugUnlock();
    final item = Item.create(type: ItemType.login, title: 'Gmail', clock: c.clock, group: 'Cũ');
    c.upsert(item);
    c.upsert(Item.create(type: ItemType.login, title: 'Khác', clock: c.clock, group: 'Công việc'));
    await tester.pumpWidget(MaterialApp(home: ItemDetailScreen(controller: c, itemId: item.id)));

    await tester.tap(find.text('Cũ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Công việc'));
    await tester.pumpAndSettle();
    expect(c.data.byId(item.id)!.group, 'Công việc');

    await tester.tap(find.text('Công việc').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thẻ mới…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Tên thẻ'), 'Mới tinh');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo'));
    await tester.pumpAndSettle();
    expect(c.data.byId(item.id)!.group, 'Mới tinh');
  });

  testWidgets('HOTP: bấm mã kế tiếp tăng bộ đếm và đổi mã', (tester) async {
    final c = VaultController()..debugUnlock();
    final item = Item.create(
      type: ItemType.totp,
      title: 'Ngân hàng token',
      clock: c.clock,
      totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP', kind: 'hotp', counter: 0),
    );
    c.upsert(item);
    await tester.pumpWidget(MaterialApp(home: ItemDetailScreen(controller: c, itemId: item.id)));
    await tester.pump();

    expect(find.byTooltip('Mã kế tiếp'), findsOneWidget);
    await tester.tap(find.byTooltip('Mã kế tiếp'));
    await tester.pump();
    expect(c.data.byId(item.id)!.totp!.counter, 1);
    await tester.tap(find.byTooltip('Mã kế tiếp'));
    await tester.pump();
    expect(c.data.byId(item.id)!.totp!.counter, 2);
  });
}
