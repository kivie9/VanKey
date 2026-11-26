import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/vault_controller.dart';

void main() {
  test('cài mới: giao diện mặc định là sáng, không theo chế độ tối của điện thoại', () async {
    final tmp = Directory.systemTemp.createTempSync('vk_theme_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = VaultController();
    addTearDown(c.dispose);
    await c.init(dir: tmp);
    expect(c.themeMode, 'light');
    expect(c.accent, 1, reason: 'màu nhấn mặc định là xanh của logo');
  });

  test('lựa chọn của người dùng được giữ: chọn Tối hoặc Hệ thống thì lần sau vẫn thế', () async {
    final tmp = Directory.systemTemp.createTempSync('vk_theme_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final mode in ['dark', 'system', 'light']) {
      final a = VaultController();
      await a.init(dir: tmp);
      await a.setTheme(mode);
      a.dispose();
      final b = VaultController();
      await b.init(dir: tmp);
      expect(b.themeMode, mode);
      b.dispose();
    }
  });
}
