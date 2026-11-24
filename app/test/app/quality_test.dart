import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/screens/onboarding_screen.dart';
import 'package:vankey/app/screens/settings_tab.dart';
import 'package:vankey/app/screens/unlock_screen.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/search.dart';

VaultController _ctrl([int n = 6]) {
  final c = VaultController()..debugUnlock();
  for (var i = 0; i < n; i++) {
    c.upsert(Item.create(
      type: ItemType.login,
      title: 'Dịch vụ số $i',
      clock: c.clock,
      values: {'username': 'user$i@example.com', 'password': 'pw-$i'},
      group: 'Nhóm ${i % 7}',
    ));
  }
  return c;
}

Widget _scaled(Widget child, double scale) => MaterialApp(
      home: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)), child: child),
    );

void main() {
  const sizes = {'điện thoại nhỏ': Size(320, 640), 'điện thoại': Size(412, 915)};

  for (final entry in sizes.entries) {
    group('chữ hệ thống lớn không vỡ bố cục (${entry.key})', () {
      for (final scale in [1.0, 1.5, 2.0]) {
        Future<void> setUp(WidgetTester t) async {
          await t.binding.setSurfaceSize(entry.value);
          addTearDown(() => t.binding.setSurfaceSize(null));
        }

        testWidgets('Kho x$scale', (t) async {
          await setUp(t);
          await t.pumpWidget(_scaled(HomeScreen(controller: _ctrl()), scale));
          await t.pump();
          expect(t.takeException(), isNull);
        });

        testWidgets('Thêm mục x$scale', (t) async {
          await setUp(t);
          await t.pumpWidget(_scaled(ItemEditorScreen(controller: _ctrl()), scale));
          await t.pump();
          expect(t.takeException(), isNull);
        });

        testWidgets('Cài đặt x$scale', (t) async {
          await setUp(t);
          await t.pumpWidget(_scaled(Scaffold(body: SettingsTab(controller: _ctrl())), scale));
          await t.pump();
          expect(t.takeException(), isNull);
        });

        testWidgets('Tạo kho x$scale', (t) async {
          await setUp(t);
          await t.pumpWidget(_scaled(OnboardingScreen(controller: VaultController()), scale));
          await t.pump();
          expect(t.takeException(), isNull);
        });

        testWidgets('Mở khóa x$scale', (t) async {
          await setUp(t);
          await t.pumpWidget(_scaled(UnlockScreen(controller: VaultController()), scale));
          await t.pump();
          expect(t.takeException(), isNull);
        });
      }
    });
  }

  testWidgets('trình đọc màn hình: nút chỉ có icon đều có nhãn (tooltip)', (t) async {
    final handle = t.ensureSemantics();
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: HomeScreen(controller: _ctrl())));
    await t.pump();
    for (final label in ['Tìm kiếm', 'Nhắc nhở', 'Sắp xếp và lọc', 'Thêm mục']) {
      expect(find.byTooltip(label), findsWidgets, reason: label); // tooltip chính là nhãn của trình đọc màn hình
    }
    handle.dispose();
  });

  group('danh sách 500 mục', () {
    testWidgets('dựng, cuộn và tìm kiếm không lỗi và đủ nhanh', (t) async {
      await t.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = _ctrl(500);
      final sw = Stopwatch()..start();
      await t.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(sw.elapsedMilliseconds, lessThan(5000), reason: 'dựng lần đầu quá chậm');

      // Danh sách lười: chỉ dựng các dòng đang nhìn thấy.
      expect(find.byType(ListTile).evaluate().length, lessThan(60));

      sw.reset();
      for (var i = 0; i < 10; i++) {
        await t.drag(find.byType(CustomScrollView).first, const Offset(0, -600));
        await t.pump();
      }
      expect(t.takeException(), isNull);
      expect(sw.elapsedMilliseconds, lessThan(8000), reason: 'cuộn quá chậm');
    });

    test('tìm kiếm trên 500 mục chạy dưới 200 ms', () {
      final c = _ctrl(500);
      final sw = Stopwatch()..start();
      final hits = c.data.items.where((i) => matchesQuery(i, 'dich vu so 4')).length;
      sw.stop();
      expect(hits, greaterThan(0));
      expect(sw.elapsedMilliseconds, lessThan(200));
    });
  });
}
