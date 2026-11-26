import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/item_detail_screen.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/app/widgets/common.dart';
import 'package:vankey/core/vault/models.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

VaultController _controller([VaultData? d]) => VaultController()..debugUnlock(d);

void main() {
  testWidgets('thêm mục đăng nhập qua màn Thêm mục', (tester) async {
    final c = _controller();
    await tester.pumpWidget(_wrap(ItemEditorScreen(controller: c)));

    await tester.enterText(find.widgetWithText(TextField, 'Tên'), 'GitHub');
    await tester.enterText(find.widgetWithText(TextField, 'Tên đăng nhập'), 'van');
    await tester.tap(find.text('Lưu'));
    await tester.pump();

    expect(c.data.items, hasLength(1));
    expect(c.data.items.single.title, 'GitHub');
    expect(c.data.items.single.valueOf('username'), 'van');
  });

  testWidgets('không cho lưu khi thiếu tên', (tester) async {
    final c = _controller();
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(ItemEditorScreen(controller: c)));
    await tester.tap(find.text('Lưu'));
    await tester.pump();
    expect(c.data.items, isEmpty);
    expect(find.text('Nhập tên cho mục', skipOffstage: false), findsOneWidget);
  });

  testWidgets('dán link otpauth tự điền tên và khóa, mã 2FA hiện trong danh sách', (tester) async {
    final c = _controller();
    await tester.pumpWidget(_wrap(ItemEditorScreen(controller: c, startType: ItemType.totp)));
    await tester.enterText(find.widgetWithText(TextField, 'Khóa 2FA hoặc link otpauth://'), 'otpauth://totp/Example:alice@x.com?secret=JBSWY3DPEHPK3PXP&issuer=Example');
    await tester.pump();
    await tester.tap(find.text('Lưu'));
    await tester.pump();

    final item = c.data.items.single;
    expect(item.title, 'Example');
    expect(item.totp?.secret, 'JBSWY3DPEHPK3PXP');
  });

  testWidgets('xóa vào thùng rác rồi khôi phục', (tester) async {
    final c = _controller();
    final item = Item.create(type: ItemType.login, title: 'Gmail', clock: c.clock, values: {'username': 'a@b.c'});
    c.upsert(item);
    await tester.pumpWidget(_wrap(ItemDetailScreen(controller: c, itemId: item.id)));
    expect(find.text('Gmail'), findsWidgets);

    c.trash(c.data.byId(item.id)!);
    await tester.pump();
    expect(c.data.byId(item.id)!.inTrash, isTrue);
    expect(find.text('Mục không còn tồn tại'), findsOneWidget);

    c.restore(c.data.byId(item.id)!);
    await tester.pump();
    expect(c.data.byId(item.id)!.inTrash, isFalse);
  });

  testWidgets('đổi mật khẩu khi sửa cất mật khẩu cũ vào lịch sử', (tester) async {
    final c = _controller();
    final item = Item.create(type: ItemType.login, title: 'Site', clock: c.clock, values: {'username': 'u', 'password': 'old-pass-1'});
    c.upsert(item);
    await tester.pumpWidget(_wrap(ItemEditorScreen(controller: c, existing: item)));
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu'), 'new-pass-2');
    await tester.tap(find.text('Lưu'));
    await tester.pump();

    final saved = c.data.byId(item.id)!;
    expect(saved.password, 'new-pass-2');
    expect(saved.pwHistory.map((h) => h.value), contains('old-pass-1'));
  });

  testWidgets('tab Kho gom theo nhóm và tìm kiếm bỏ dấu', (tester) async {
    final c = _controller();
    c.upsert(Item.create(type: ItemType.login, title: 'Ngân hàng', clock: c.clock, group: 'Tiền'));
    c.upsert(Item.create(type: ItemType.login, title: 'Facebook', clock: c.clock, group: 'Mạng xã hội'));
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(HomeScreen(controller: c)));
    await tester.pump();

    expect(find.text('TIỀN'), findsOneWidget);
    expect(find.text('MẠNG XÃ HỘI'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'ngan hang');
    await tester.pump();
    expect(find.text('Ngân hàng'), findsOneWidget);
    expect(find.text('Facebook'), findsNothing);
  });

  testWidgets('tab Kho không hiện mục 2FA và không hiện mã; tab 2FA chỉ hiện mục có mã', (tester) async {
    final c = _controller();
    const secret = TotpParams(secret: 'JBSWY3DPEHPK3PXP');
    c.upsert(Item.create(type: ItemType.login, title: 'Ngân hàng', clock: c.clock));
    c.upsert(Item.create(type: ItemType.login, title: 'Gmail có 2FA', clock: c.clock, totp: secret));
    c.upsert(Item.create(type: ItemType.totp, title: 'Dropbox 2FA', clock: c.clock, totp: secret));
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(HomeScreen(controller: c)));
    await tester.pump();

    // Tab Kho: mật khẩu và mục đăng nhập (kể cả mục có gắn 2FA), nhưng không có mục loại 2FA và không có chip mã.
    expect(find.text('Ngân hàng'), findsOneWidget);
    expect(find.text('Gmail có 2FA'), findsOneWidget);
    expect(find.text('Dropbox 2FA'), findsNothing);
    expect(find.byType(TotpCode), findsNothing);

    // Tab 2FA: chỉ mục có mã, kèm mã.
    await tester.tap(find.text('2FA'));
    await tester.pump();
    expect(find.text('Ngân hàng'), findsNothing);
    expect(find.text('Gmail có 2FA'), findsOneWidget);
    expect(find.text('Dropbox 2FA'), findsOneWidget);
    expect(find.byType(TotpCode), findsNWidgets(2));
  });

  testWidgets('tab 2FA: chạm vào mục là chép mã (không mở mục); nhấn giữ vẫn ra menu, có thêm "Xem chi tiết"', (tester) async {
    final c = _controller();
    c.upsert(Item.create(type: ItemType.totp, title: 'Dropbox 2FA', clock: c.clock, totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP')));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(HomeScreen(controller: c)));
    await tester.pump();
    await tester.tap(find.text('2FA'));
    await tester.pump();

    await tester.tap(find.text('Dropbox 2FA'));
    await tester.pump();
    expect(copied, matches(RegExp(r'^\d{6}$')));
    expect(find.text('Đã chép mã 2FA'), findsOneWidget);
    expect(find.byType(ItemDetailScreen), findsNothing, reason: 'không mở màn chi tiết');

    await tester.longPress(find.text('Dropbox 2FA'));
    await tester.pumpAndSettle();
    expect(find.text('Xem chi tiết'), findsOneWidget);
    expect(find.text('Chép mã 2FA'), findsOneWidget);
    await tester.tap(find.text('Xem chi tiết'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 31)); // hết hẹn giờ tự xóa clipboard
  });
}
