import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/group_actions.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

void main() {
  late VaultController c;
  late Item a, b, d;

  setUp(() {
    c = VaultController()..debugUnlock();
    a = Item.create(type: ItemType.login, title: 'A', clock: c.clock, group: 'Việc');
    b = Item.create(type: ItemType.login, title: 'B', clock: c.clock, group: 'Việc');
    d = Item.create(type: ItemType.login, title: 'D', clock: c.clock, group: 'Nhà');
    for (final i in [a, b, d]) {
      c.upsert(i);
    }
  });

  test('đổi tên nhóm áp dụng cho mọi mục; trùng tên thì gộp', () {
    c.renameGroup('Việc', 'Công ty');
    expect(c.groups, ['Công ty', 'Nhà']);
    expect(c.data.byId(a.id)!.group, 'Công ty');
    c.renameGroup('Nhà', 'Công ty');
    expect(c.groups, ['Công ty']);
    expect(c.countInGroup('Công ty'), 3);
  });

  test('xóa nhóm: mục còn nguyên, chỉ bỏ nhóm', () {
    c.deleteGroup('Việc');
    expect(c.groups, ['Nhà']);
    expect(c.data.byId(a.id)!.group, '');
    expect(c.data.byId(a.id)!.inTrash, isFalse);
    expect(c.data.items.length, 3);
  });

  testWidgets('quản lý nhóm: xóa phải xác nhận', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => TextButton(onPressed: () => manageGroups(ctx, c), child: const Text('mo')))));
    await t.tap(find.text('mo'));
    await t.pumpAndSettle();
    expect(find.text('Việc'), findsOneWidget);
    await t.tap(find.byTooltip('Xóa thẻ').first);
    await t.pumpAndSettle();
    expect(find.text('Xóa thẻ "Nhà"?'), findsOneWidget);
    await t.tap(find.text('Hủy'));
    await t.pumpAndSettle();
    expect(c.groups.length, 2);
    await t.tap(find.byTooltip('Xóa thẻ').first);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Xóa thẻ'));
    await t.pumpAndSettle();
    expect(c.groups, ['Việc']);
  });

  testWidgets('form: chạm ô Nhóm chọn từ danh sách; tạo nhóm mới', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c)));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'Tên'), 'Mới');
    await t.tap(find.text('Không có thẻ'));
    await t.pumpAndSettle();
    await t.tap(find.text('Nhà').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Lưu'));
    await t.pump();
    expect(c.data.items.firstWhere((i) => i.title == 'Mới').group, 'Nhà');
  });

  testWidgets('form: nhóm mới gõ tay', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c)));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'Tên'), 'Mới');
    await t.tap(find.text('Không có thẻ'));
    await t.pumpAndSettle();
    await t.tap(find.text('Thẻ mới…'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Tên thẻ'), 'Game');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Tạo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lưu'));
    await t.pump();
    expect(c.data.items.firstWhere((i) => i.title == 'Mới').group, 'Game');
  });
}
