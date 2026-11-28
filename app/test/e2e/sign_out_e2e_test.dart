// Đầu cuối: đăng xuất trong app (VaultController thật, server TypeScript thật). Bỏ qua nếu máy không có Node.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

import '../helpers/node_server.dart';

const _pass = 'mat-khau-dang-xuat-thu-123';

Future<void> _until(bool Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('quá thời gian chờ');
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<void> main() async {
  final skip = await NodeServer.available() ? null : 'Không có Node trên máy này';

  test('đăng xuất: đẩy thay đổi lên máy chủ, xóa kho trên máy, về màn đăng nhập; đăng nhập lại thấy đủ dữ liệu', skip: skip, () async {
    final server = await NodeServer.start();
    addTearDown(server.stop);
    final tmp = Directory.systemTemp.createTempSync('vk_signout_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = VaultController();
    addTearDown(c.dispose);
    await c.init(dir: tmp);
    await c.createVault(_pass);
    c.confirmRecoverySaved();
    expect(await c.signInCloudflare(url: server.url, username: 'signout.user', password: _pass, register: true), isNull);
    await _until(() => c.lastSync != null && c.syncStatus == SyncStatus.idle);

    // Sửa rồi đăng xuất ngay, trước khi đồng bộ hẹn giờ kịp chạy.
    c.upsert(Item.create(type: ItemType.login, title: 'vừa thêm', clock: c.clock, values: {'username': 'u'}));
    expect(await c.signOutCloudflare(), isTrue);

    expect(c.phase, Phase.onboarding);
    expect(c.cfSession, isNull);
    expect(c.provider, isNull);
    expect(c.data.items, isEmpty);
    expect(File('${tmp.path}${Platform.pathSeparator}vankey.vkv').existsSync(), isFalse);

    expect(await c.joinFromCloud(url: server.url, username: 'signout.user', accountPassword: _pass, vaultPassphrase: _pass), isNull);
    expect(c.phase, Phase.unlocked);
    expect(c.data.items.map((i) => i.title), ['vừa thêm']);

    // Máy chủ không gọi được: giữ nguyên kho; chỉ xóa khi người dùng ép đăng xuất.
    server.stop();
    await server.process.exitCode;
    expect(await c.signOutCloudflare(), isFalse);
    expect(c.phase, Phase.unlocked);
    expect(c.cfSession, isNotNull);
    expect(c.data.items, hasLength(1));
    expect(await c.signOutCloudflare(force: true), isTrue);
    expect(c.phase, Phase.onboarding);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
