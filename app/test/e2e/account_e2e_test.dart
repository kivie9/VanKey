// Đầu cuối với server TypeScript thật: đổi mật khẩu đổi luôn trên máy chủ, và xóa tài khoản.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/sync/cloudflare_sync.dart';
import 'package:vankey/core/vault/models.dart';

import '../helpers/node_server.dart';

const _user = 'tai.khoan';
const _pass = 'mat-khau-ban-dau-123';
const _next = 'mat-khau-moi-hon-456';

Future<VaultController> _device(Directory root, String name) async {
  final dir = Directory('${root.path}${Platform.pathSeparator}$name')..createSync(recursive: true);
  final c = VaultController();
  await c.init(dir: dir);
  addTearDown(c.dispose);
  return c;
}

Future<void> _until(bool Function() cond, {String? what}) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('quá thời gian chờ: ${what ?? ''}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Máy A đăng ký bằng một mật khẩu, lưu mã khôi phục và đẩy kho lên.
Future<VaultController> _signedUp(Directory tmp, String url) async {
  final a = await _device(tmp, 'a');
  expect(await a.signUpWithServer(url: url, username: _user, password: _pass), isNull);
  a.confirmRecoverySaved();
  a.upsert(Item.create(type: ItemType.login, title: 'GitHub', clock: a.clock, values: {'username': 'van'}));
  await a.syncNow();
  await _until(() => a.syncStatus == SyncStatus.idle && a.lastSync != null, what: 'A đồng bộ');
  return a;
}

Future<void> main() async {
  final hasNode = await NodeServer.available();
  final skip = hasNode ? null : 'Không có Node trên máy này';

  test('đổi mật khẩu khi đã đăng nhập máy chủ: máy mới đăng nhập bằng mật khẩu MỚI và mở được kho; mật khẩu cũ bị từ chối', skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
    final server = await NodeServer.start();
    addTearDown(server.stop);
    final tmp = Directory.systemTemp.createTempSync('vk_acc_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final a = await _signedUp(tmp, server.url);
    expect(await a.changeVaultPassword('sai-mat-khau-hien-tai', _next), isNotNull);
    expect(await a.changeVaultPassword(_pass, _next), isNull);
    await a.syncNow();
    await _until(() => a.syncStatus != SyncStatus.syncing, what: 'A đồng bộ sau khi đổi');
    expect(a.syncError, isNull, reason: 'máy đang đổi vẫn giữ phiên');

    final b = await _device(tmp, 'b');
    final old = await b.signInWithServer(url: server.url, username: _user, password: _pass);
    expect(old.error, isNotNull, reason: 'mật khẩu cũ không còn đăng nhập được');
    final r = await b.signInWithServer(url: server.url, username: _user, password: _next);
    expect(r.error, isNull);
    expect(b.phase, Phase.unlocked);
    expect(b.data.items.map((i) => i.title), contains('GitHub'));
  });

  test('đổi mật khẩu khi máy chủ không kết nối được: báo lỗi và KHÔNG đổi trên máy (tránh lệch)', skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
    final server = await NodeServer.start();
    final tmp = Directory.systemTemp.createTempSync('vk_acc_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final a = await _signedUp(tmp, server.url);
    server.stop();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(await a.changeVaultPassword(_pass, _next), isNotNull);
    expect(await a.verifyPassphrase(_pass), isTrue, reason: 'mật khẩu trên máy giữ nguyên');
    // Đợi lần đồng bộ nền (đang thử máy chủ đã tắt) xong rồi khóa, để không chạy tiếp sau khi test kết thúc.
    await _until(() => a.syncStatus != SyncStatus.syncing, what: 'đồng bộ nền dừng');
    await a.lock();
  });

  test('xóa tài khoản: sai mật khẩu bị từ chối; đúng thì xóa trên máy chủ và trên máy, về màn đầu, đăng nhập lại không được', skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
    final server = await NodeServer.start();
    addTearDown(server.stop);
    final tmp = Directory.systemTemp.createTempSync('vk_acc_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final a = await _signedUp(tmp, server.url);
    expect(await a.deleteServerAccount('sai-mat-khau-roi-123'), isNotNull);
    expect(a.phase, Phase.unlocked);

    expect(await a.deleteServerAccount(_pass), isNull);
    expect(a.phase, Phase.onboarding);
    expect(a.provider, isNull);
    expect(a.cfSession, isNull);
    expect(a.data.items, isEmpty);

    final b = await _device(tmp, 'b');
    expect((await b.signInWithServer(url: server.url, username: _user, password: _pass)).error, isNotNull);
    expect(await b.signUpWithServer(url: server.url, username: _user, password: _pass), isNull, reason: 'tên đăng nhập đã được giải phóng');
  });
  test('tài khoản cũ đăng ký bằng khóa chưa chuẩn hóa (dấu rời): vẫn đăng nhập được, được chuyển sang khóa NFKC, rồi máy gõ dấu dựng sẵn cũng vào được', skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
    final server = await NodeServer.start();
    addTearDown(server.stop);
    final tmp = Directory.systemTemp.createTempSync('vk_acc_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const nfd = 'mật khẩu dược 123'; // "mật khẩu dược 123", dấu rời
    const nfc = 'mật khẩu dược 123'; // cùng chữ, dựng sẵn

    final api = CloudflareApi();
    addTearDown(api.close);
    await api.register(server.url, _user, await CloudflareApi.deriveLegacyAuthKey(_user, nfd), 'Máy cũ');

    final b = await _device(tmp, 'b');
    expect((await b.signInWithServer(url: server.url, username: _user, password: nfd)).error, isNull, reason: 'thử khóa cũ khi khóa mới bị từ chối');
    b.confirmRecoverySaved();
    await _until(() => b.syncStatus == SyncStatus.idle && b.lastSync != null, what: 'B đồng bộ lần đầu');
    final first = b.lastSync;
    b.upsert(Item.create(type: ItemType.login, title: 'GitHub', clock: b.clock));
    await b.syncNow();
    await _until(() => b.syncStatus == SyncStatus.idle && b.lastSync != first, what: 'B đẩy mục mới');

    await expectLater(api.login(server.url, _user, await CloudflareApi.deriveLegacyAuthKey(_user, nfd), 'x'), throwsA(isA<CloudflareApiException>()), reason: 'khóa cũ đã bị thay');
    final c = await _device(tmp, 'c');
    expect((await c.signInWithServer(url: server.url, username: _user, password: nfc)).error, isNull);
    expect(c.phase, Phase.unlocked);
    expect(c.data.items.map((i) => i.title), contains('GitHub'));
  });
}
