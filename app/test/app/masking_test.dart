import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/item_detail_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

final _sixDigits = RegExp(r'^\d{3} \d{3}$');

Finder _visibleCode() => find.byWidgetPredicate((w) => w is Text && w.data != null && _sixDigits.hasMatch(w.data!));

void main() {
  late VaultController c;
  late Item item;

  setUp(() {
    c = VaultController()..debugUnlock();
    item = Item.create(
      type: ItemType.login,
      title: 'GitHub',
      clock: c.clock,
      values: {'username': 'van.le', 'password': 'Sup3r-Secret!'},
      customFields: const [Field(key: 'notes', value: 'ghi chú riêng tư', secret: true, kind: 'multiline')],
      totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP'),
    );
    c.upsert(item);
  });

  Future<void> open(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: ItemDetailScreen(controller: c, itemId: item.id)));
    await t.pump();
  }

  testWidgets('mở chi tiết: mã 2FA hiện sẵn (như ở danh sách); mật khẩu và ghi chú vẫn ẩn', (t) async {
    await open(t);
    expect(_visibleCode(), findsOneWidget, reason: 'mã 2FA 6 số hiện mặc định, không có nút ẩn');
    expect(find.byTooltip('Ẩn mã 2FA'), findsNothing);
    expect(find.byTooltip('Hiện mã 2FA'), findsNothing);
    expect(find.text('Sup3r-Secret!'), findsNothing);
    expect(find.text('ghi chú riêng tư'), findsNothing);
    expect(find.text('van.le'), findsOneWidget);
  });

  testWidgets('hiện mật khẩu từng trường; sau 30 giây tự ẩn lại mật khẩu, mã 2FA vẫn hiện', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Hiện').first);
    await t.pump();
    expect(find.text('Sup3r-Secret!'), findsOneWidget);

    await t.pump(const Duration(seconds: 31));
    expect(find.text('Sup3r-Secret!'), findsNothing);
    expect(_visibleCode(), findsOneWidget);
  });
}
