import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

bool _obscured(WidgetTester t, String label) {
  final field = find.widgetWithText(TextField, label);
  expect(field, findsOneWidget, reason: label);
  return t.widget<TextField>(field).obscureText;
}

void main() {
  late VaultController c;

  setUp(() => c = VaultController()..debugUnlock());

  Future<void> open(WidgetTester t, Item item) async {
    await t.binding.setSurfaceSize(const Size(420, 2200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c, existing: item)));
    await t.pump();
  }

  testWidgets('sửa mục đăng nhập: mật khẩu và khóa 2FA mặc định bị che; tên đăng nhập hiện', (t) async {
    final item = Item.create(
      type: ItemType.login,
      title: 'GitHub',
      clock: c.clock,
      values: {'username': 'van.le', 'password': 'Sup3r-Secret!', 'backupCodes': 'aaaa-bbbb\ncccc-dddd'},
      customFields: const [Field(key: 'notes', value: 'ghi chú riêng tư', secret: true, kind: 'multiline')],
      totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP'),
    );
    c.upsert(item);
    await open(t, item);

    expect(_obscured(t, 'Mật khẩu'), isTrue);
    expect(_obscured(t, 'Khóa 2FA (không bắt buộc)'), isTrue);
    expect(_obscured(t, 'Tên đăng nhập'), isFalse);

    // Trường nhiều dòng nhạy cảm bị che hẳn: nội dung không có trong cây widget.
    expect(find.text('Hiện để sửa'), findsNWidgets(2));
    expect(find.textContaining('aaaa-bbbb'), findsNothing);
    expect(find.textContaining('ghi chú riêng tư'), findsNothing);
  });

  testWidgets('bấm "Hiện để sửa" thì hiện ô sửa với nội dung hiện tại; bấm mắt thì hiện khóa 2FA', (t) async {
    final item = Item.create(
      type: ItemType.login,
      title: 'Router',
      clock: c.clock,
      values: {'backupCodes': 'aaaa-bbbb'},
      customFields: const [Field(key: 'notes', value: 'pass wifi: 12345', secret: true, kind: 'multiline')],
      totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP'),
    );
    c.upsert(item);
    await open(t, item);

    await t.tap(find.text('Hiện để sửa').last); // ghi chú
    await t.pump();
    expect(find.text('pass wifi: 12345'), findsOneWidget);
    expect(find.text('Hiện để sửa'), findsOneWidget, reason: 'mã dự phòng vẫn còn che');

    await t.tap(find.text('Hiện để sửa'));
    await t.pump();
    expect(find.text('aaaa-bbbb'), findsOneWidget);

    await t.tap(find.byTooltip('Hiện').last);
    await t.pump();
    expect(_obscured(t, 'Khóa 2FA (không bắt buộc)'), isFalse);
  });

  testWidgets('sửa tiếp không đụng tới phần đang che thì lưu vẫn giữ nguyên dữ liệu đó', (t) async {
    final item = Item.create(
      type: ItemType.login,
      title: 'Router',
      clock: c.clock,
      values: {'password': 'keep-me-1', 'backupCodes': 'aaaa-bbbb'},
      customFields: const [Field(key: 'notes', value: 'giữ ghi chú', secret: true, kind: 'multiline')],
      totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP'),
    );
    c.upsert(item);
    await open(t, item);
    await t.enterText(find.widgetWithText(TextField, 'Tên'), 'Router mới');
    await t.tap(find.text('Lưu'));
    await t.pump();

    final saved = c.data.byId(item.id)!;
    expect(saved.title, 'Router mới');
    expect(saved.password, 'keep-me-1');
    expect(saved.valueOf('backupCodes'), 'aaaa-bbbb');
    expect(saved.valueOf('notes'), 'giữ ghi chú');
    expect(saved.totp?.secret, 'JBSWY3DPEHPK3PXP');
  });

  testWidgets('thêm mới (chưa có dữ liệu): không che ô nhiều dòng, nhưng mật khẩu và khóa 2FA vẫn ẩn khi gõ', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c)));
    expect(find.text('Hiện để sửa'), findsNothing);
    expect(_obscured(t, 'Mật khẩu'), isTrue);
    expect(_obscured(t, 'Khóa 2FA (không bắt buộc)'), isTrue);
  });
}
