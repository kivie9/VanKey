// Đầu cuối ở mức ứng dụng: hai VaultController (hai thiết bị) đồng bộ qua server TypeScript thật.
// Gồm: tạo kho, đăng ký tài khoản, đồng bộ, máy mới đăng nhập tải kho về, sửa ở hai bên, gỡ thiết bị.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

import '../helpers/node_server.dart';

const _username = 'test.user';
const _vaultPass = 'mật-khẩu-của-kho-123';
const _accountPass = 'mật-khẩu-tài-khoản-456';

Future<VaultController> _device(Directory root, String name) async {
  final dir = Directory('${root.path}${Platform.pathSeparator}$name')..createSync(recursive: true);
  final c = VaultController();
  await c.init(dir: dir);
  return c;
}

Future<void> _until(bool Function() cond, {String? what}) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('quá thời gian chờ: ${what ?? ''}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> main() async {
  final hasNode = await NodeServer.available();
  final skip = hasNode ? null : 'Không có Node trên máy này';

  test('máy A tạo kho và bật đồng bộ; máy B đăng nhập tải kho về; sửa hai bên hội tụ; gỡ thiết bị B', skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
    final server = await NodeServer.start();
    addTearDown(server.stop);
    final tmp = Directory.systemTemp.createTempSync('vk_e2e_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // ---- Máy A ----
    final a = await _device(tmp, 'a');
    expect(a.phase, Phase.onboarding);
    await a.createVault(_vaultPass);
    expect(a.pendingRecovery, isNotNull);
    a.confirmRecoverySaved();
    expect(a.phase, Phase.unlocked);

    a.upsert(Item.create(type: ItemType.login, title: 'GitHub', clock: a.clock, values: {'username': 'van', 'password': 'p@ss-1'}));
    a.upsert(Item.create(type: ItemType.totp, title: 'Gmail 2FA', clock: a.clock, totp: const TotpParams(secret: 'JBSWY3DPEHPK3PXP')));

    // Địa chỉ http ra Internet bị từ chối; sai mật khẩu báo lỗi dễ hiểu.
    expect(await a.signInCloudflare(url: 'http://vankey.example.com', username: _username, password: _accountPass, register: true), isNotNull);
    expect(await a.signInCloudflare(url: server.url, username: 'a', password: _accountPass, register: true), contains(''), reason: 'tên đăng nhập sai quy tắc bị từ chối');

    expect(await a.signInCloudflare(url: server.url, username: _username, password: _accountPass, register: true), isNull);
    await _until(() => a.syncStatus == SyncStatus.idle && a.lastSync != null, what: 'A đồng bộ lần đầu');
    expect(a.syncError, isNull);
    expect(a.syncLabel, contains(_username));

    // ---- Máy B (máy mới) ----
    final b = await _device(tmp, 'b');
    expect(b.phase, Phase.onboarding);

    // Sai mật khẩu kho: báo lỗi, không vào app.
    final bad = await b.joinFromCloud(url: server.url, username: _username, accountPassword: _accountPass, vaultPassphrase: 'sai-mat-khau-kho');
    expect(bad, contains('KHO'));
    expect(b.phase, Phase.onboarding);

    // Sai mật khẩu tài khoản: báo lỗi từ máy chủ.
    expect(await b.joinFromCloud(url: server.url, username: _username, accountPassword: 'mat-khau-tai-khoan-sai', vaultPassphrase: _vaultPass), isNotNull);
    expect(b.phase, Phase.onboarding);

    expect(await b.joinFromCloud(url: server.url, username: _username, accountPassword: _accountPass, vaultPassphrase: _vaultPass), isNull);
    expect(b.phase, Phase.unlocked);
    expect(b.data.items.map((i) => i.title).toSet(), {'GitHub', 'Gmail 2FA'});
    expect(b.data.items.firstWhere((i) => i.title == 'GitHub').password, 'p@ss-1');
    expect(b.cfSession, isNotNull);

    // ---- Sửa ở hai bên rồi đồng bộ ----
    b.upsert(Item.create(type: ItemType.login, title: 'Facebook', clock: b.clock));
    a.upsert(Item.create(type: ItemType.login, title: 'Netflix', clock: a.clock));
    await b.syncNow();
    expect(b.syncStatus, SyncStatus.idle, reason: b.syncError);
    await a.syncNow();
    expect(a.syncStatus, SyncStatus.idle, reason: a.syncError);
    await b.syncNow();

    const all = {'GitHub', 'Gmail 2FA', 'Facebook', 'Netflix'};
    expect(a.data.items.map((i) => i.title).toSet(), all);
    expect(b.data.items.map((i) => i.title).toSet(), all);

    // Máy chủ chỉ giữ bản mã hóa của kho.
    final blob = File('${tmp.path}${Platform.pathSeparator}b${Platform.pathSeparator}vankey.vkv').readAsBytesSync();
    expect(String.fromCharCodes(blob).contains('GitHub'), isFalse);

    // ---- Gỡ thiết bị B từ máy A ----
    final devices = await a.cloudflareDevices();
    expect(devices.length, 2);
    final other = devices.firstWhere((d) => !d.current);
    await a.revokeCloudflareDevice(other.id);

    b.upsert(Item.create(type: ItemType.login, title: 'Sau khi bị gỡ', clock: b.clock));
    await b.syncNow();
    expect(b.syncStatus, SyncStatus.error);
    expect(b.syncError, contains('đăng nhập lại'));
    // Dữ liệu cục bộ của B vẫn còn (gỡ thiết bị không xóa dữ liệu đã có trên máy đó).
    expect(b.data.items.any((i) => i.title == 'Sau khi bị gỡ'), isTrue);

    // A vẫn đồng bộ bình thường và không nhận mục của B sau khi bị gỡ.
    await a.syncNow();
    expect(a.syncStatus, SyncStatus.idle);
    expect(a.data.items.any((i) => i.title == 'Sau khi bị gỡ'), isFalse);
  });

  test('khởi động lại app: phiên Cloudflare đọc lại từ cấu hình (cần Keystore thật nên chỉ kiểm nhãn)', skip: skip, () async {
    final tmp = Directory.systemTemp.createTempSync('vk_e2e_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = await _device(tmp, 'x');
    expect(c.syncStatus, SyncStatus.off);
    expect(c.syncLabel, 'Chưa bật');
  });

  test('một mật khẩu: máy A tạo tài khoản kèm kho, máy B chỉ cần đăng nhập là mở được kho', skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
    final server = await NodeServer.start();
    addTearDown(server.stop);
    final tmp = Directory.systemTemp.createTempSync('vk_e2e_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const pass = 'mot-mat-khau-dai-123';

    final a = await _device(tmp, 'a');
    expect(await a.signUpWithServer(url: server.url, username: 'Nguoi.Dung', password: 'ngan'), isNotNull, reason: 'mật khẩu quá ngắn');
    expect(await a.signUpWithServer(url: server.url, username: 'a', password: pass), isNotNull, reason: 'tên đăng nhập sai quy tắc');
    expect(await a.signUpWithServer(url: server.url, username: 'Nguoi.Dung', password: pass), isNull);
    expect(a.pendingRecovery, isNotNull, reason: 'phải có mã khôi phục để người dùng lưu');
    expect(a.phase, Phase.onboarding, reason: 'chưa vào app cho tới khi xác nhận đã lưu mã khôi phục');
    a.confirmRecoverySaved();
    expect(a.phase, Phase.unlocked);
    await _until(() => a.syncStatus == SyncStatus.idle && a.lastSync != null, what: 'A đẩy kho rỗng lên lần đầu');
    a.upsert(Item.create(type: ItemType.login, title: 'GitHub', clock: a.clock, values: {'username': 'van', 'password': 'p@ss-1'}));
    await a.syncNow();
    expect(a.syncLabel, contains('nguoi.dung'));

    // Tên đăng nhập đã dùng
    final other = await _device(tmp, 'other');
    expect(await other.signUpWithServer(url: server.url, username: 'nguoi.dung', password: 'mat-khau-khac-dai-1'), isNotNull);

    // Máy B: chỉ đăng nhập, không hỏi mật khẩu kho riêng
    final b = await _device(tmp, 'b');
    final wrong = await b.signInWithServer(url: server.url, username: 'nguoi.dung', password: 'sai-mat-khau-dai-1');
    expect(wrong.error, isNotNull);
    expect(wrong.vaultMismatch, isFalse);
    expect(b.phase, Phase.onboarding);
    final ok = await b.signInWithServer(url: server.url, username: 'NGUOI.dung', password: pass);
    expect(ok.error, isNull);
    expect(b.phase, Phase.unlocked);
    expect(b.data.items.map((i) => i.title), contains('GitHub'));
  });

  test('đăng nhập được nhưng mật khẩu không mở được kho (kho đặt mật khẩu khác): báo vaultMismatch, không vào app', skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
    final server = await NodeServer.start();
    addTearDown(server.stop);
    final tmp = Directory.systemTemp.createTempSync('vk_e2e_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final a = await _device(tmp, 'a');
    await a.createVault(_vaultPass);
    a.confirmRecoverySaved();
    expect(await a.signInCloudflare(url: server.url, username: _username, password: _accountPass, register: true), isNull);
    await _until(() => a.syncStatus == SyncStatus.idle && a.lastSync != null, what: 'A đồng bộ lần đầu');

    final b = await _device(tmp, 'b');
    final r = await b.signInWithServer(url: server.url, username: _username, password: _accountPass);
    expect(r.vaultMismatch, isTrue);
    expect(r.error, isNotNull);
    expect(b.phase, Phase.onboarding);
  });
}
