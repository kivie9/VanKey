import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/item_detail_screen.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/theme.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/app/widgets/service_field.dart';
import 'package:vankey/app/widgets/service_stack_header.dart';
import 'package:vankey/core/vault/models.dart';

Item _add(VaultController c, String title, {String user = '', String url = '', String group = ''}) {
  final i = Item.create(type: ItemType.login, title: title, clock: c.clock, group: group, values: {if (user.isNotEmpty) 'username': user, if (url.isNotEmpty) 'url': url});
  c.upsert(i);
  return i;
}

VaultController _ctrl() {
  final c = VaultController()..debugUnlock();
  _add(c, 'Facebook', user: 'van@gmail.com', url: 'facebook.com', group: 'Cá nhân');
  _add(c, 'FB bán hàng', user: 'shop@gmail.com', url: 'https://www.facebook.com/login');
  _add(c, 'Netflix', user: 'xem@gmail.com', url: 'netflix.com');
  return c;
}

Widget _app(Widget home) => MaterialApp(theme: AppTheme.build(Brightness.light, 0), home: home);

Future<void> _size(WidgetTester t, Size size) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
}

Finder _field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

String _textOf(WidgetTester t, String label) => t.widget<TextField>(_field(label)).controller!.text;

void main() {
  for (final size in [const Size(420, 900), const Size(840, 600), const Size(1280, 720)]) {
    testWidgets('gom theo dịch vụ: nhiều tài khoản xếp chồng, bấm để mở (rộng ${size.width.toInt()})', (t) async {
      await _size(t, size);
      final c = _ctrl()..groupBy = GroupBy.service;
      await t.pumpWidget(_app(HomeScreen(controller: c)));
      await t.pump();
      expect(find.byType(ServiceStackHeader), findsOneWidget);
      expect(find.text('2 tài khoản'), findsOneWidget);
      expect(find.text('Netflix'), findsOneWidget, reason: 'tài khoản lẻ vẫn hiện bình thường');
      expect(find.text('FB bán hàng'), findsNothing);

      await t.tap(find.byType(ServiceStackHeader));
      await t.pumpAndSettle();
      // Tên trùng tên dịch vụ thì đưa tên đăng nhập lên dòng chính; tên tự đặt thì giữ.
      expect(find.text('van@gmail.com'), findsOneWidget);
      expect(find.text('FB bán hàng'), findsOneWidget);
      expect(find.text('Cá nhân'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('đang tìm kiếm thì nhóm tự mở', (t) async {
    await _size(t, const Size(1280, 720));
    final c = _ctrl()..groupBy = GroupBy.service;
    await t.pumpWidget(_app(HomeScreen(controller: c)));
    await t.tap(find.byTooltip('Tìm kiếm'));
    await t.pump();
    await t.enterText(find.byType(TextField), 'facebook');
    await t.pump();
    expect(find.text('FB bán hàng'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
  });

  test('gợi ý của ô dịch vụ: dịch vụ đã có đứng trước, trang lạ thêm mới được', () {
    final c = _ctrl();
    expect(serviceOptions('', c.data.items).map((o) => (o.name, o.count)), [('Facebook', 2), ('Netflix', 1)]);
    expect(serviceOptions('fb', c.data.items).first.name, 'Facebook');
    final typed = serviceOptions('goo', c.data.items);
    expect(typed.first.name, 'Google');
    expect(typed.last.isNew, isTrue);
    final site = serviceOptions('erp.congty.com.vn', c.data.items).single;
    expect((site.isNew, site.domain, site.key), (true, 'erp.congty.com.vn', 'd:congty.com.vn'));
  });

  testWidgets('thêm mục: chọn dịch vụ thì tự điền tên và địa chỉ; đổi tên riêng không bị ghi đè', (t) async {
    await _size(t, const Size(600, 1600));
    final c = _ctrl();
    await t.pumpWidget(_app(ItemEditorScreen(controller: c, startType: ItemType.login)));
    await t.enterText(_field('Dịch vụ'), 'face');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ListTile, 'Facebook'));
    await t.pumpAndSettle();
    expect(_textOf(t, 'Tên'), 'Facebook');
    expect(_textOf(t, 'Địa chỉ web'), 'facebook.com');

    await t.enterText(_field('Tên'), 'FB phụ');
    await t.enterText(_field('Địa chỉ web'), 'https://mail.google.com');
    await t.pump();
    expect(_textOf(t, 'Dịch vụ'), 'Google', reason: 'dán địa chỉ thì ô dịch vụ tự nhận ra');
    expect(_textOf(t, 'Tên'), 'FB phụ');
  });

  testWidgets('mục cũ gõ sai tên: chỉ sửa khi bấm Đúng; bấm Không thì thôi hỏi', (t) async {
    await _size(t, const Size(500, 1400));
    final c = VaultController()..debugUnlock();
    final typo = _add(c, 'Facebok', user: 'a');
    final other = _add(c, 'Gooogle', user: 'b');
    expect(c.serviceSuggestions.length, 2);

    await t.pumpWidget(_app(ItemDetailScreen(controller: c, itemId: typo.id)));
    await t.pump();
    expect(c.data.byId(typo.id)!.valueOf('url'), isNull, reason: 'app không tự sửa');
    await t.tap(find.text('Đúng'));
    await t.pump();
    expect(c.data.byId(typo.id)!.valueOf('url'), 'facebook.com');
    expect(c.data.byId(typo.id)!.title, 'Facebok');
    expect(find.text('Đúng'), findsNothing);

    await c.dismissServiceSuggestion(other, c.serviceSuggestionFor(other)!).catchError((Object _) {});
    expect(c.serviceSuggestions, isEmpty);
    await t.pump(const Duration(seconds: 5));
  });
}
