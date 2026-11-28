// Dựng ảnh màn hình cho trang giới thiệu (site/) từ chính mã giao diện của app, với dữ liệu mẫu.
// Không đụng tới kho thật. Nằm ở tool/ nên `flutter test` thường và CI không chạy. Chạy tay trong app/:
//   flutter test tool/site_screenshots_test.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vankey/app/demo_data.dart';
import 'package:vankey/app/screens/home_screen.dart';
import 'package:vankey/app/theme.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

const _out = '../site/src/assets/screens';

/// Chọn vài mục mẫu tiêu biểu, bỏ các mục chỉ dùng để thử giao diện (tên quá dài, thùng rác...).
const _titles = [
  'Facebook', 'Google', 'GitHub', 'Netflix', 'Spotify', 'Discord', 'Apple ID',
  'Visa Techcombank', 'Wi-Fi nhà', 'Ghi chú ngắn', 'Amazon AWS', 'Steam',
];

VaultController _controller() {
  final c = VaultController()..debugUnlock();
  final items = buildDemoItems(c.clock);
  for (final (n, title) in _titles.reversed.indexed) {
    var item = items.firstWhere((Item i) => i.title == title);
    final totp = item.totp;
    // Mỗi mục một khóa mẫu khác nhau, để các mã trong ảnh không trùng nhau.
    if (totp != null && totp.kind == 'totp') {
      item = item.copyWith(totp: TotpParams(secret: 'JBSWY3DPEHPK3P${'ABCDEFGHIJKLMNOP'[n]}Q', digits: totp.digits));
    }
    c.upsert(item);
  }
  return c;
}

Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

final _boundary = GlobalKey();

Future<void> _pump(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(Brightness.dark, 0),
        home: HomeScreen(controller: _controller()),
      ),
    ),
  );
  await _settle(tester);
}

/// Không dùng pumpAndSettle vì đồng hồ đếm ngược 2FA chạy liên tục.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  }
}

Future<void> _capture(WidgetTester tester, String name, double pixelRatio) async {
  await tester.runAsync(() async {
    final render = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    print('${file.path}: ${image.width}x${image.height}');
    image.dispose();
  });
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  await tester.binding.setSurfaceSize(null);
  tester.view.reset();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('điện thoại: kho và mã 2FA', (tester) async {
    debugDisableShadows = false;
    await _pump(tester, const Size(390, 780));
    await _capture(tester, 'phone-list', 2.5);

    await tester.tap(find.text('2FA').last);
    await _settle(tester);
    await _capture(tester, 'phone-codes', 2.5);
    await _finish(tester);
    debugDisableShadows = true;
  });

  testWidgets('máy tính: bố cục rộng', (tester) async {
    debugDisableShadows = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await _pump(tester, const Size(1160, 720));
    await _capture(tester, 'desktop', 2);
    await _finish(tester);
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  });
}
