// Đầu cuối: client Dart thật nói chuyện với server TypeScript thật (chạy bằng Node, lưu trong bộ nhớ).
// Bỏ qua nếu máy không có Node.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/crypto/kdf.dart';
import 'package:vankey/core/sync/cloudflare_sync.dart';
import 'package:vankey/core/sync/sync_provider.dart';
import 'package:vankey/core/sync/sync_service.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/vault_session.dart';

import '../helpers/node_server.dart';

const _fast = Argon2Params(opslimit: 2, memlimitBytes: 32 * 1024 * 1024);
const _email = 'test@example.com';

Future<void> main() async {
  final hasNode = await NodeServer.available();
  final skip = hasNode ? null : 'Không có Node trên máy này';

  late NodeServer server;
  late CloudflareApi api;
  setUpAll(() async {
    if (hasNode) server = await NodeServer.start();
    api = CloudflareApi();
  });
  tearDownAll(() {
    if (hasNode) server.stop();
    api.close();
  });

  Future<String> authKey(String pw) => CloudflareApi.deriveAuthKey(_email, pw, params: _fast);

  test('khóa đăng nhập: cùng email+mật khẩu ra cùng khóa; khác mật khẩu hoặc khác email ra khóa khác; email không phân biệt hoa thường', () async {
    final a = await CloudflareApi.deriveAuthKey(_email, 'mật khẩu', params: _fast);
    expect(await CloudflareApi.deriveAuthKey('TEST@Example.com', 'mật khẩu', params: _fast), a);
    expect(await CloudflareApi.deriveAuthKey(_email, 'mật khẩu 2', params: _fast), isNot(a));
    expect(await CloudflareApi.deriveAuthKey('khac@example.com', 'mật khẩu', params: _fast), isNot(a));
    expect(base64.decode(a), hasLength(32));
    expect(a.contains('mật khẩu'), isFalse);
  });

  test('đăng ký, đăng nhập, sai mật khẩu, email không được phép', skip: skip, () async {
    final key = await authKey('mật-khẩu-tài-khoản');
    final s = await api.register(server.url, _email, key, 'Máy A');
    expect(s.accessToken, isNotEmpty);
    expect(s.email, _email);

    await expectLater(api.register(server.url, _email, key, 'Máy A'), throwsA(isA<CloudflareApiException>().having((e) => e.status, 'status', 409)));
    final login = await api.login(server.url, _email, key, 'Máy B');
    expect(login.accountId, s.accountId);

    await expectLater(
      api.login(server.url, _email, await authKey('sai'), 'X'),
      throwsA(isA<CloudflareApiException>().having((e) => e.status, 'status', 401)),
    );
    await expectLater(
      api.register(server.url, 'la@example.com', key, 'X'),
      throwsA(isA<CloudflareApiException>().having((e) => e.status, 'status', 403)),
    );
  });

  test('hai thiết bị đồng bộ kho thật qua HTTP: thêm, gộp, mã hóa đầu cuối', skip: skip, () async {
    final srv = await NodeServer.start();
    addTearDown(srv.stop);
    final key = await authKey('mk-2');
    final sa = await api.register(srv.url, _email, key, 'Điện thoại');
    final sb = await api.login(srv.url, _email, key, 'Máy tính');

    final (vaultA, _) = await VaultSession.create(passphrase: 'vault-passphrase-1', params: _fast);
    final clockA = HlcClock(node: 'phone');
    final dataA = const VaultData().upsert(Item.create(type: ItemType.login, title: 'GitHub', clock: clockA, values: {'username': 'van', 'password': 'bí-mật-123'}));

    final svcA = SyncService(CloudflareSync(api, sa));
    final out = await svcA.sync(session: vaultA, local: dataA);
    expect(out.uploaded, isTrue);
    final stateA = out.state;

    // Máy chủ chỉ thấy bản mã hóa: không chứa mật khẩu hay tên mục ở dạng đọc được.
    final raw = (await CloudflareSync(api, sa).fetch())!.bytes;
    final text = latin1.decode(raw);
    expect(text.contains('bí-mật-123'), isFalse);
    expect(text.contains('GitHub'), isFalse);

    // Máy B mở cùng kho bằng passphrase rồi đồng bộ.
    final vaultB = await VaultSession.openWithPassphrase(raw, 'vault-passphrase-1');
    var dataB = VaultData.fromJson(vaultB.payload);
    expect(dataB.items.single.title, 'GitHub');
    dataB = dataB.upsert(Item.create(type: ItemType.login, title: 'Gmail', clock: HlcClock(node: 'laptop')));
    final outB = await SyncService(CloudflareSync(api, sb)).sync(session: vaultB, local: dataB, state: SyncState(baseBytes: raw));
    expect(outB.uploaded, isTrue);

    // Máy A đồng bộ lại thấy mục của B.
    final outA2 = await svcA.sync(session: vaultA, local: dataA, state: stateA);
    expect(outA2.data.items.map((i) => i.title).toSet(), {'GitHub', 'Gmail'});
  });

  test('ghi chen thật qua HTTP: bên giữ phiên bản cũ nhận 409 rồi tự gộp và hội tụ', skip: skip, () async {
    final srv = await NodeServer.start();
    addTearDown(srv.stop);
    final key = await authKey('mk-3');
    final sa = await api.register(srv.url, _email, key, 'A');
    final sb = await api.login(srv.url, _email, key, 'B');

    final (va, _) = await VaultSession.create(passphrase: 'vault-passphrase-2', params: _fast);
    final ca = HlcClock(node: 'a');
    var da = const VaultData().upsert(Item.create(type: ItemType.login, title: 'A1', clock: ca));
    final seed = (await SyncService(CloudflareSync(api, sa)).sync(session: va, local: da)).state;

    final vb = await VaultSession.openWithPassphrase(seed.baseBytes!, 'vault-passphrase-2');
    var db = VaultData.fromJson(vb.payload);
    db = db.upsert(Item.create(type: ItemType.login, title: 'B1', clock: HlcClock(node: 'b')));
    da = da.upsert(Item.create(type: ItemType.login, title: 'A2', clock: ca));

    // B đẩy lên trước; A (còn giữ trạng thái cũ) đẩy sau → phải gộp, không mất mục nào.
    await SyncService(CloudflareSync(api, sb)).sync(session: vb, local: db, state: seed);
    final outA = await SyncService(CloudflareSync(api, sa)).sync(session: va, local: da, state: seed);
    expect(outA.data.items.map((i) => i.title).toSet(), {'A1', 'A2', 'B1'});
  });

  test('refresh tự động khi access token hết hạn, và báo lại token mới', skip: skip, () async {
    final srv = await NodeServer.start();
    addTearDown(srv.stop);
    final s0 = await api.register(srv.url, _email, await authKey('mk-4'), 'A');
    final stale = s0.withTokens(s0.accessToken, s0.refreshToken, DateTime.now().subtract(const Duration(minutes: 1)));
    CloudflareSession? saved;
    final sync = CloudflareSync(api, stale, onSession: (s) => saved = s);
    expect(await sync.fetch(), isNull); // chưa có kho, nhưng phải xác thực được
    expect(saved, isNotNull);
    expect(saved!.refreshToken, isNot(s0.refreshToken), reason: 'refresh token phải được xoay vòng');
    expect(sync.session.expiresAt.isAfter(DateTime.now()), isTrue);
  });

  test('thu hồi thiết bị: thiết bị bị gỡ nhận SyncAuthException ngay', skip: skip, () async {
    final srv = await NodeServer.start();
    addTearDown(srv.stop);
    final key = await authKey('mk-5');
    final sa = await api.register(srv.url, _email, key, 'Điện thoại');
    final sb = await api.login(srv.url, _email, key, 'Máy bị mất');

    final list = await api.devices(sa);
    expect(list.map((d) => d.name), containsAll(['Điện thoại', 'Máy bị mất']));
    expect(list.where((d) => d.current).single.name, 'Điện thoại');

    await api.revokeDevice(sa, sb.deviceId);
    await expectLater(CloudflareSync(api, sb).fetch(), throwsA(isA<SyncAuthException>()));
    expect((await api.devices(sa)).length, 1);
  });

  test('mất kết nối: ném SyncNetworkException (không phải lỗi khác)', () async {
    final unreachable = CloudflareSync(
      api,
      CloudflareSession(
        baseUrl: 'http://127.0.0.1:1',
        accessToken: 'x',
        refreshToken: 'y',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        deviceId: 'd',
        accountId: 'a',
        email: _email,
      ),
    );
    await expectLater(unreachable.fetch(), throwsA(isA<SyncNetworkException>()));
  });
}
