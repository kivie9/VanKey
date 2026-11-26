import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/sync/sync_provider.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/vault_session.dart';

/// Nơi lưu giả mà lệnh tải về bị giữ lại cho tới khi test cho đi: để sửa dữ liệu ĐÚNG LÚC đang đồng bộ.
class _GatedProvider implements SyncProvider {
  _GatedProvider(this.inner);
  final FakeSyncProvider inner;
  Completer<void>? gate;

  @override
  String get name => 'gated';

  @override
  Future<RemoteBlob?> fetch() async {
    final g = gate;
    if (g != null) await g.future;
    return inner.fetch();
  }

  @override
  Future<String> upload(Uint8List bytes, {String? ifMatch}) => inner.upload(bytes, ifMatch: ifMatch);
}

const _pass = 'mat-khau-thu-nghiem-123';

Item _login(VaultController c, String title) =>
    Item.create(type: ItemType.login, title: title, clock: c.clock, values: {'username': 'u'});

Future<List<String>> _titlesOnStore(FakeSyncProvider p) async {
  final s = await VaultSession.openWithPassphrase(p.stored!, _pass);
  return [for (final i in VaultData.fromJson(s.payload).items) i.title];
}

void main() {
  test('sửa dữ liệu đúng lúc đang đồng bộ: phần vừa sửa không bị ghi đè mất và được đồng bộ ở lần sau', () async {
    final tmp = Directory.systemTemp.createTempSync('vk_midedit_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = VaultController();
    addTearDown(c.dispose);
    await c.init(dir: tmp);
    await c.createVault(_pass);
    c.confirmRecoverySaved();

    final store = FakeSyncProvider();
    final provider = _GatedProvider(store);
    c.provider = provider;
    c.upsert(_login(c, 'có từ trước'));

    // Lần đồng bộ đầu bị giữ ở bước tải về.
    provider.gate = Completer<void>();
    final running = c.syncNow();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.syncStatus, SyncStatus.syncing);

    // Người dùng thêm mục trong lúc đang đồng bộ.
    c.upsert(_login(c, 'thêm giữa chừng'));
    provider.gate!.complete();
    await running;

    expect(c.data.items.map((i) => i.title).toSet(), {'có từ trước', 'thêm giữa chừng'}, reason: 'mục vừa thêm không được biến mất');

    // Lần đồng bộ sau đẩy nốt mục đó lên.
    provider.gate = null;
    await c.syncNow();
    expect((await _titlesOnStore(store)).toSet(), {'có từ trước', 'thêm giữa chừng'});
  });
}
