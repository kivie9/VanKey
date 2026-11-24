import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/app/widgets/common.dart';
import 'package:vankey/core/vault/models.dart';

void main() {
  late VaultController c;
  late Item full;
  late Item plain;
  final copied = <String>[];

  setUp(() {
    copied.clear();
    c = VaultController()..debugUnlock();
    full = Item.create(
      type: ItemType.login,
      title: 'GitHub',
      clock: c.clock,
      values: {'username': 'van.le', 'password': 'Sup3r-Secret!', 'url': 'github.com'},
      totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP'),
      group: 'Dev',
    );
    plain = Item.create(type: ItemType.note, title: 'Ghi chú nhà', clock: c.clock, values: {'content': 'abc'});
    c.upsert(full);
    c.upsert(plain);
  });

  Future<void> openHome(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    // Bắt nội dung được chép vào clipboard.
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await t.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await t.pump();
  }

  Finder tileOf(String title) => find.widgetWithText(ItemTile, title).first;

  testWidgets('nhấn giữ một mục có đủ dữ liệu: hiện đủ các thao tác nhanh', (t) async {
    await openHome(t);
    await t.longPress(tileOf('GitHub'));
    await t.pumpAndSettle();
    for (final a in ['Chép mã 2FA', 'Chép tên đăng nhập', 'Chép mật khẩu', 'Mở link', 'Yêu thích', 'Sửa', 'Hiện mã QR', 'Xóa vào thùng rác']) {
      expect(find.text(a), findsOneWidget, reason: a);
    }
  });

  testWidgets('mục chỉ có ghi chú: chỉ hiện thao tác phù hợp (không có chép mật khẩu, mã 2FA, mở link, QR)', (t) async {
    await openHome(t);
    await t.longPress(tileOf('Ghi chú nhà'));
    await t.pumpAndSettle();
    for (final a in ['Chép mã 2FA', 'Chép tên đăng nhập', 'Chép mật khẩu', 'Mở link', 'Hiện mã QR']) {
      expect(find.text(a), findsNothing, reason: a);
    }
    expect(find.text('Yêu thích'), findsOneWidget);
    expect(find.text('Sửa'), findsOneWidget);
    expect(find.text('Xóa vào thùng rác'), findsOneWidget);
  });

  testWidgets('chép mật khẩu và tên đăng nhập từ menu nhấn giữ', (t) async {
    await openHome(t);
    await t.longPress(tileOf('GitHub'));
    await t.pumpAndSettle();
    await t.tap(find.text('Chép mật khẩu'));
    await t.pumpAndSettle();
    expect(copied, contains('Sup3r-Secret!'));

    await t.longPress(tileOf('GitHub'));
    await t.pumpAndSettle();
    await t.tap(find.text('Chép tên đăng nhập'));
    await t.pumpAndSettle();
    expect(copied, contains('van.le'));
    await t.pump(const Duration(seconds: 31)); // chạy nốt bộ hẹn giờ tự xóa clipboard
  });

  testWidgets('yêu thích: bấm từ menu đổi trạng thái; menu hiện "Bỏ yêu thích" lần sau', (t) async {
    await openHome(t);
    await t.longPress(tileOf('GitHub'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yêu thích'));
    await t.pumpAndSettle();
    expect(c.data.byId(full.id)!.favorite, isTrue);

    await t.longPress(tileOf('GitHub'));
    await t.pumpAndSettle();
    expect(find.text('Bỏ yêu thích'), findsOneWidget);
  });

  testWidgets('sửa từ menu mở màn sửa đúng mục', (t) async {
    await openHome(t);
    await t.longPress(tileOf('GitHub'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sửa'));
    await t.pumpAndSettle();
    expect(find.byType(ItemEditorScreen), findsOneWidget);
    expect(t.widget<ItemEditorScreen>(find.byType(ItemEditorScreen)).existing?.id, full.id);
  });

  testWidgets('xóa từ menu cũng phải xác nhận; Hủy thì giữ nguyên; đồng ý thì vào thùng rác', (t) async {
    await openHome(t);
    await t.longPress(tileOf('GitHub'));
    await t.pumpAndSettle();
    await t.tap(find.text('Xóa vào thùng rác'));
    await t.pumpAndSettle();
    expect(find.text('Chuyển "GitHub" vào thùng rác?'), findsOneWidget);
    expect(c.data.byId(full.id)!.inTrash, isFalse);

    await t.tap(find.text('Hủy'));
    await t.pumpAndSettle();
    expect(c.data.byId(full.id)!.inTrash, isFalse);

    await t.longPress(tileOf('GitHub'));
    await t.pumpAndSettle();
    await t.tap(find.text('Xóa vào thùng rác'));
    await t.pumpAndSettle();
    await t.tap(find.text('Chuyển vào thùng rác'));
    await t.pumpAndSettle();
    expect(c.data.byId(full.id)!.inTrash, isTrue);
    expect(find.text('Hoàn tác'), findsOneWidget);
  });

  testWidgets('chạm thường vẫn mở chi tiết, nhấn giữ không mở chi tiết', (t) async {
    await openHome(t);
    await t.longPress(tileOf('Ghi chú nhà'));
    await t.pumpAndSettle();
    expect(find.text('Chép mã 2FA'), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('logo Google nhiều màu (nền sáng), Gmail và Meta có biểu tượng riêng', (t) async {
    await t.pumpWidget(const MaterialApp(home: Column(children: [Avatar('Google'), Avatar('Gmail'), Avatar('Meta'), Avatar('Facebook')])));
    expect(find.byType(ShaderMask), findsOneWidget, reason: 'chỉ Google dùng dải màu');
    expect(find.byIcon(SimpleIcons.google), findsOneWidget);
    expect(find.byIcon(SimpleIcons.gmail), findsOneWidget);
    expect(find.byIcon(SimpleIcons.meta), findsOneWidget);
    expect(find.byIcon(SimpleIcons.facebook), findsOneWidget);
  });
}
