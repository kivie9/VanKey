import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/constants.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/item_detail_screen.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/app/widgets/common.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/search.dart';

VaultController _ctrl() => VaultController()..debugUnlock();

void main() {
  group('xác nhận trước khi xóa', () {
    testWidgets('bấm Hủy thì mục vẫn còn; bấm đồng ý thì vào thùng rác', (tester) async {
      final c = _ctrl();
      final item = Item.create(type: ItemType.login, title: 'Gmail', clock: c.clock);
      c.upsert(item);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemDetailScreen(controller: c, itemId: item.id))),
        child: const Text('mở'),
      ))))));
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Xóa vào thùng rác'));
      await tester.pumpAndSettle();
      expect(find.text('Chuyển "Gmail" vào thùng rác?'), findsOneWidget);
      expect(c.data.byId(item.id)!.inTrash, isFalse, reason: 'chưa đồng ý thì chưa xóa');

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(c.data.byId(item.id)!.inTrash, isFalse);
      expect(find.byType(ItemDetailScreen), findsOneWidget, reason: 'Hủy thì ở lại màn chi tiết');

      await tester.tap(find.byTooltip('Xóa vào thùng rác'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chuyển vào thùng rác'));
      await tester.pumpAndSettle();
      expect(c.data.byId(item.id)!.inTrash, isTrue);
      expect(find.byType(ItemDetailScreen), findsNothing);
      expect(find.text('Hoàn tác'), findsOneWidget);

      await tester.pump(Timing.undoSnack);
      await tester.pumpAndSettle();
      expect(find.text('Hoàn tác'), findsNothing, reason: 'thanh Hoàn tác tự đóng');
    });
  });

  testWidgets('mỗi mục một thẻ riêng trong danh sách', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = _ctrl();
    for (final n in ['A', 'B', 'C']) {
      c.upsert(Item.create(type: ItemType.login, title: 'Mục $n', clock: c.clock, group: 'Nhóm'));
    }
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await tester.pump();

    final tiles = find.byType(ItemTile);
    expect(tiles, findsNWidgets(3));
    for (final t in tester.widgetList<ItemTile>(tiles)) {
      final card = find.ancestor(of: find.byWidget(t), matching: find.byType(Card));
      expect(card, findsOneWidget);
    }
    // Ba mục = ba thẻ khác nhau (không gom chung một thẻ).
    final cards = tester.widgetList<Card>(find.ancestor(of: tiles, matching: find.byType(Card))).toSet();
    expect(cards.length, 3);
  });

  group('bảng sắp xếp và lọc', () {
    testWidgets('mở bảng, chọn sắp xếp, gom và nhóm; "Đặt lại" trả về mặc định', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = _ctrl();
      c.upsert(Item.create(type: ItemType.login, title: 'Ngân hàng', clock: c.clock, group: 'Tiền'));
      c.upsert(Item.create(type: ItemType.login, title: 'Facebook', clock: c.clock, group: 'Mạng'));
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      expect(find.text('Sắp xếp và lọc'), findsOneWidget);
      for (final t in ['Gom theo', 'Sắp xếp', 'Lọc theo thẻ', 'Tên A–Z', 'Mới sửa', 'Mới tạo', 'Tất cả', 'Tiền', 'Mạng']) {
        expect(find.text(t), findsWidgets, reason: t);
      }

      await tester.tap(find.text('Mới tạo'));
      await tester.pump();
      expect(c.sortBy, SortBy.created);
      await tester.tap(find.text('Loại'));
      await tester.pump();
      expect(c.groupBy, GroupBy.type);

      await tester.tap(find.text('Tiền'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xong'));
      await tester.pumpAndSettle();
      expect(find.text('Ngân hàng'), findsOneWidget);
      expect(find.text('Facebook'), findsNothing, reason: 'đã lọc theo thẻ Tiền');

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đặt lại'));
      await tester.pumpAndSettle();
      expect(c.sortBy, SortBy.name);
      expect(c.groupBy, GroupBy.group);
      await tester.tap(find.text('Xong'));
      await tester.pumpAndSettle();
      expect(find.text('Facebook'), findsOneWidget);
    });
  });

  group('ghi chú cho mục', () {
    testWidgets('thêm ghi chú khi tạo mục (không phải loại Ghi chú), hiện ở chi tiết, sửa được, xóa được', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = _ctrl();
      await tester.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c)));

      await tester.enterText(find.widgetWithText(TextField, 'Tên'), 'Router nhà');
      await tester.enterText(find.widgetWithText(TextField, 'Ghi chú'), 'Đổi pass mỗi quý\nCổng 8080');
      await tester.tap(find.text('Lưu'));
      await tester.pump();

      var item = c.data.items.single;
      expect(item.type, ItemType.login);
      expect(item.valueOf('notes'), 'Đổi pass mỗi quý\nCổng 8080');
      expect(item.fields.where((f) => f.key == 'notes').single.secret, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: ItemDetailScreen(controller: c, itemId: item.id)));
      await tester.pump();
      expect(find.text('Ghi chú'), findsOneWidget);

      // Sửa lại ghi chú, rồi xóa trắng.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c, existing: item)));
      // Sửa mục có sẵn: ghi chú bị che cho đến khi bấm "Hiện để sửa".
      expect(find.widgetWithText(TextField, 'Ghi chú'), findsNothing);
      await tester.tap(find.text('Hiện để sửa'));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Ghi chú'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Ghi chú'), 'Bản mới');
      await tester.tap(find.text('Lưu'));
      await tester.pump();
      item = c.data.byId(item.id)!;
      expect(item.fields.where((f) => f.key == 'notes'), hasLength(1), reason: 'không nhân đôi ghi chú');
      expect(item.valueOf('notes'), 'Bản mới');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: c, existing: item)));
      await tester.tap(find.text('Hiện để sửa'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Ghi chú'), '');
      await tester.tap(find.text('Lưu'));
      await tester.pump();
      expect(c.data.byId(item.id)!.valueOf('notes'), isNull);
    });

    testWidgets('loại "Ghi chú" không có ô ghi chú phụ (đã có ô Nội dung)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: ItemEditorScreen(controller: _ctrl(), startType: ItemType.note)));
      expect(find.widgetWithText(TextField, 'Nội dung'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Ghi chú'), findsNothing);
    });

    test('ghi chú không làm hỏng dòng phụ và không bị tìm kiếm lộ ra (là trường bí mật)', () {
      final c = _ctrl();
      final i = Item.create(
        type: ItemType.wifi,
        title: 'Wi-Fi nhà',
        clock: c.clock,
        customFields: const [Field(key: 'notes', value: 'mật-khẩu-trong-ghi-chú', secret: true, kind: 'multiline')],
      );
      expect(i.subtitle, isNot(contains('mật-khẩu')));
      expect(matchesQuery(i, 'mat khau trong ghi chu'), isFalse);
    });
  });
}
