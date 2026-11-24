// Chụp ảnh các màn hình chính (sáng và tối) ra build/screens/ để xem bằng mắt khi chỉnh giao diện.
// Không chạy trong `flutter test` thường. Chạy:  flutter test test/tool/screenshots_test.dart --dart-define=VK_SHOTS=1
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/screens/cloudflare_screens.dart';
import 'package:vankey/app/screens/generator_screen.dart';
import 'package:vankey/app/screens/health_screen.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/screens/item_detail_screen.dart';
import 'package:vankey/app/screens/item_editor_screen.dart';
import 'package:vankey/app/screens/onboarding_screen.dart';
import 'package:vankey/app/screens/qr_show_screen.dart';
import 'package:vankey/app/screens/settings_tab.dart';
import 'package:vankey/app/screens/sync_screen.dart';
import 'package:vankey/app/screens/theme_screen.dart';
import 'package:vankey/app/screens/trash_screen.dart';
import 'package:vankey/app/screens/unlock_screen.dart';
import 'package:vankey/app/theme.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

const _enabled = bool.fromEnvironment('VK_SHOTS');

Future<void> _loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? 'E:/code/libs/flutter'}/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async => ByteData.sublistView(Uint8List.fromList(File('$dir/$f').readAsBytesSync()));
  // Mỗi tệp một lần nạp cho cùng họ Roboto: nạp gộp trong một FontLoader làm các độ đậm bị trộn lẫn.
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf', 'roboto-light.ttf']) {
    final l = FontLoader('Roboto')..addFont(read(f));
    await l.load();
  }
  final brand = FontLoader('packages/simple_icons/SimpleIcons')
    ..addFont(Future.value(ByteData.sublistView(File('C:/Users/vanlo/AppData/Local/Pub/Cache/hosted/pub.dev/simple_icons-16.23.0/fonts/SimpleIcons.ttf').readAsBytesSync())));
  await brand.load();
  final icons = FontLoader('MaterialIcons')..addFont(read('materialicons-regular.otf'));
  await icons.load();
}

VaultController _sample() {
  final c = VaultController()..debugUnlock();
  Item add(String title, {String user = '', String group = '', bool fav = false, TotpParams? totp, ItemType type = ItemType.login, String pw = ''}) {
    final i = Item.create(type: type, title: title, clock: c.clock, values: {if (user.isNotEmpty) 'username': user, if (pw.isNotEmpty) 'password': pw}, group: group, favorite: fav, totp: totp);
    c.upsert(i);
    return i;
  }

  const t = TotpParams(secret: 'JBSWY3DPEHPK3PXP');
  add('GitHub', user: 'van.le', group: 'Công việc', fav: true, totp: t, pw: 'Xk9#mQ2\$vL7!');
  add('Google', user: 'van@gmail.com', group: 'Cá nhân', fav: true, totp: t, pw: 'tmp-pass-1');
  add('AWS Console', user: 'admin@corp.vn', group: 'Công việc', totp: t, pw: 'aws-secret-77');
  add('Cloudflare', user: 'ops@corp.vn', group: 'Công việc', totp: t, pw: 'cf-secret-88');
  add('Facebook', user: 'van.le.95', group: 'Cá nhân', pw: '123456');
  add('Vietcombank', user: '0912345678', group: 'Ngân hàng', pw: 'bank-pass-9');
  add('Techcombank', user: 'vanle', group: 'Ngân hàng', pw: 'bank-pass-9');
  add('Netflix', user: 'van@gmail.com', group: 'Giải trí', pw: 'nf-pass-3');
  add('Steam', user: 'vangamer', group: 'Giải trí', totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP', kind: 'steam', digits: 5));
  add('Wi-Fi nhà', type: ItemType.wifi, group: 'Cá nhân');
  return c;
}

Widget _app(Widget home, Brightness b) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light, 0, fontFamily: 'Roboto'),
      darkTheme: AppTheme.build(Brightness.dark, 0, fontFamily: 'Roboto'),
      themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: home,
    );

void main() {
  if (!_enabled) {
    test('chụp màn hình (bỏ qua: cần --dart-define=VK_SHOTS=1)', () {}, skip: 'chỉ chạy khi cần xem giao diện');
    return;
  }

  setUpAll(_loadFonts);

  final outDir = Directory('build/screens')..createSync(recursive: true);

  Future<void> shot(WidgetTester t, String name) async {
    final boundary = t.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${outDir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  final screens = <String, Widget Function(VaultController)>{
    '01_kho': (c) => HomeScreen(controller: c),
    '02_chi_tiet': (c) => ItemDetailScreen(controller: c, itemId: c.data.items.firstWhere((i) => i.title == 'GitHub').id),
    '03_them_muc': (c) => ItemEditorScreen(controller: c),
    '04_cai_dat': (c) => Scaffold(body: SafeArea(child: SettingsTab(controller: c))),
    '05_tao_kho': (c) => OnboardingScreen(controller: VaultController()),
    '06_mo_khoa': (c) => UnlockScreen(controller: VaultController()),
    '07_dong_bo': (c) => SyncScreen(controller: c),
    '08_dang_nhap_may_chu': (c) => CloudflareLoginScreen(controller: c),
    '09_tao_mat_khau': (c) => const GeneratorScreen(),
    '10_kiem_tra_bao_mat': (c) => HealthScreen(controller: c),
    '11_giao_dien': (c) => ThemeScreen(controller: c),
    '12_thung_rac': (c) => TrashScreen(controller: c),
    '13_qr': (c) => QrShowScreen.forItem(c.data.items.firstWhere((i) => i.totp != null)),
  };

  // Màn có tương tác (menu mở, hộp thoại, trang con).
  final steps = <String, Future<void> Function(WidgetTester, VaultController)>{
    '14_menu_loc': (t, c) async {
      await t.tap(find.byIcon(Icons.filter_list));
      await t.pumpAndSettle();
    },
    '15_hop_thoai': (t, c) async {
      unawaited(showDialog<void>(
        context: t.element(find.byType(Scaffold).first),
        builder: (ctx) => AlertDialog(
          title: const Text('Xóa vĩnh viễn "GitHub"?'),
          content: const Text('Không thể hoàn tác.'),
          actions: [TextButton(onPressed: () {}, child: const Text('Hủy')), FilledButton(onPressed: () {}, child: const Text('Xóa'))],
        ),
      ));
      await t.pumpAndSettle();
    },
    '16_nut_cong': (t, c) async {
      await t.tap(find.byTooltip('Thêm mục'));
      await t.pumpAndSettle();
    },
    '17_cai_dat_bao_mat': (t, c) async {
      await t.tap(find.text('Bảo mật'));
      await t.pumpAndSettle();
    },
    '18_cai_dat_tai_khoan': (t, c) async {
      await t.tap(find.text('Tài khoản'));
      await t.pumpAndSettle();
    },
  };
  Widget homeFor(String key, VaultController c) =>
      key.startsWith('17') || key.startsWith('18') ? Scaffold(body: SafeArea(child: SettingsTab(controller: c))) : HomeScreen(controller: c);
  for (final b in [Brightness.light, Brightness.dark]) {
    for (final e in steps.entries) {
      testWidgets('${e.key} ${b.name}', (t) async {
        await t.binding.setSurfaceSize(const Size(412, 915));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final c = _sample();
        await t.pumpWidget(RepaintBoundary(child: _app(homeFor(e.key, c), b)));
        await t.pump(const Duration(milliseconds: 300));
        await e.value(t, c);
        await shot(t, '${e.key}_${b.name}');
      });
    }
  }

  for (final b in [Brightness.light, Brightness.dark]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} ${b.name}', (t) async {
        await t.binding.setSurfaceSize(const Size(412, 915));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final c = _sample();
        await t.pumpWidget(RepaintBoundary(child: _app(e.value(c), b)));
        await t.pump(const Duration(milliseconds: 300));
        await shot(t, '${e.key}_${b.name}');
      });
    }
  }
}
