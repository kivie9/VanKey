import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/item_detail_screen.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/screens/qr_show_screen.dart';
import 'package:vankey/app/screens/settings_tab.dart';
import 'package:vankey/app/screens/trash_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/app/widgets/common.dart';
import 'package:vankey/app/widgets/qr_view.dart';
import 'package:vankey/core/import_export/exporters.dart';
import 'package:vankey/core/totp/migration.dart';
import 'package:vankey/core/vault/models.dart';

VaultController _ctrl() => VaultController()..debugUnlock();

void main() {
  group('hiện mã QR', () {
    testWidgets('một mục 2FA: có QrView và cảnh báo bí mật', (tester) async {
      final c = _ctrl();
      final item = Item.create(type: ItemType.totp, title: 'GitHub', clock: c.clock, totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP'));
      await tester.pumpWidget(MaterialApp(home: QrShowScreen.forItem(item)));
      expect(find.byType(QrView), findsOneWidget);
      expect(find.textContaining('chứa khóa bí mật'), findsOneWidget);
    });

    testWidgets('nhiều mục: chia nhiều mã, chuyển trang qua lại', (tester) async {
      tester.view
      ..physicalSize = const Size(420, 1000)
      ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _ctrl();
      final items = [
        for (var i = 0; i < 8; i++) Item.create(type: ItemType.totp, title: 'D$i', clock: c.clock, totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP')),
      ];
      await tester.pumpWidget(MaterialApp(home: QrShowScreen.forGoogleAuthenticator(items)));
      expect(find.text('Mã 1 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Mã sau'));
      await tester.pump();
      expect(find.text('Mã 2 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Mã trước'));
      await tester.pump();
      expect(find.text('Mã 1 / 2'), findsOneWidget);
    });

    test('các mã migration được tạo chứa đủ mọi mục và đọc lại đúng', () {
      final c = _ctrl();
      final items = [
        for (var i = 0; i < 8; i++)
          Item.create(type: ItemType.totp, title: 'D$i', clock: c.clock, values: {'account': 'u$i'}, totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP')),
      ];
      final uris = Exporters.googleMigrationUris(items, perBatch: 6);
      expect(uris, hasLength(2));
      final back = [for (final u in uris) ...Migration.parseUri(u).entries.map((e) => e.issuer)];
      expect(back, [for (var i = 0; i < 8; i++) 'D$i']);
    });

    testWidgets('chưa có mục 2FA: báo rõ, không crash', (tester) async {
      await tester.pumpWidget(MaterialApp(home: QrShowScreen.forGoogleAuthenticator(const [])));
      expect(find.text('Chưa có mục 2FA nào để xuất.'), findsOneWidget);
    });

    testWidgets('màn chi tiết chỉ có nút QR khi mục có 2FA', (tester) async {
      final c = _ctrl();
      final withTotp = Item.create(type: ItemType.totp, title: 'A', clock: c.clock, totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP'));
      final plain = Item.create(type: ItemType.login, title: 'B', clock: c.clock);
      c.upsert(withTotp);
      c.upsert(plain);
      await tester.pumpWidget(MaterialApp(home: ItemDetailScreen(controller: c, itemId: withTotp.id)));
      expect(find.byTooltip('Hiện mã QR'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: ItemDetailScreen(controller: c, itemId: plain.id)));
      expect(find.byTooltip('Hiện mã QR'), findsNothing);
    });
  });

  testWidgets('thanh độ mạnh hiện khi gõ mật khẩu và đổi theo độ mạnh', (tester) async {
    tester.view
      ..physicalSize = const Size(420, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: _ctrl())));
    expect(find.text('Yếu'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu'), '123456');
    await tester.pump();
    expect(find.text('Yếu'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu'), r'Xk9#mQ2$vL7!pR4&wZ8@');
    await tester.pump();
    expect(find.text('Rất mạnh'), findsOneWidget);
  });

  group('sắp xếp', () {
    testWidgets('theo tên, mới sửa trước, mới tạo trước', (tester) async {
      tester.view
      ..physicalSize = const Size(420, 900)
      ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _ctrl();
      final a = Item.create(type: ItemType.login, title: 'Alpha', clock: c.clock, now: DateTime.utc(2026, 1, 1));
      final b = Item.create(type: ItemType.login, title: 'Bravo', clock: c.clock, now: DateTime.utc(2026, 1, 2));
      final z = Item.create(type: ItemType.login, title: 'Zulu', clock: c.clock, now: DateTime.utc(2026, 1, 3));
      for (final i in [b, z, a]) {
        c.upsert(i);
      }
      await c.setGroupBy(GroupBy.none).catchError((Object _) {});
      c.groupBy = GroupBy.none;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pump();

      List<String> order() => tester.widgetList<ItemTile>(find.byType(ItemTile)).map((t) => t.item.title).toList();
      expect(order(), ['Alpha', 'Bravo', 'Zulu']);

      c.sortBy = SortBy.created;
      c.notifyListeners();
      await tester.pump();
      expect(order(), ['Zulu', 'Bravo', 'Alpha']);

      c.sortBy = SortBy.updated;
      c.upsert(a.edit(clock: c.clock, title: 'Alpha', now: DateTime.utc(2026, 6, 1))); // Alpha mới sửa gần nhất
      await tester.pump();
      expect(order().first, 'Alpha');
    });
  });

  group('thùng rác', () {
    test('emptyTrash xóa vĩnh viễn mọi mục trong thùng, giữ mục thường, để lại dấu xóa', () {
      final c = _ctrl();
      final keep = Item.create(type: ItemType.login, title: 'Giữ', clock: c.clock);
      final del1 = Item.create(type: ItemType.login, title: 'Xóa 1', clock: c.clock);
      final del2 = Item.create(type: ItemType.login, title: 'Xóa 2', clock: c.clock);
      for (final i in [keep, del1, del2]) {
        c.upsert(i);
      }
      c.trash(c.data.byId(del1.id)!);
      c.trash(c.data.byId(del2.id)!);
      c.emptyTrash();
      expect(c.data.items.map((i) => i.title), ['Giữ']);
      expect(c.data.tombstones.map((t) => t.id).toSet(), {del1.id, del2.id}, reason: 'cần dấu xóa để đồng bộ không làm sống lại');
    });

    testWidgets('nút Dọn sạch hỏi xác nhận rồi xóa', (tester) async {
      final c = _ctrl();
      final i = Item.create(type: ItemType.login, title: 'Rác', clock: c.clock);
      c.upsert(i);
      c.trash(c.data.byId(i.id)!);
      await tester.pumpWidget(MaterialApp(home: TrashScreen(controller: c)));
      await tester.tap(find.text('Dọn sạch'));
      await tester.pumpAndSettle();
      expect(find.text('Dọn sạch thùng rác?'), findsOneWidget);
      await tester.tap(find.text('Xóa hết'));
      await tester.pumpAndSettle();
      expect(c.data.items, isEmpty);
      expect(find.text('Thùng rác trống'), findsOneWidget);
    });
  });

  testWidgets('màn Tài khoản hiện trạng thái lưu trên máy', (tester) async {
    tester.view
      ..physicalSize = const Size(420, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsTab(controller: _ctrl()))));
    await tester.tap(find.text('Tài khoản'));
    await tester.pumpAndSettle();
    expect(find.text('Chỉ lưu trên máy này'), findsOneWidget);
  });
}
