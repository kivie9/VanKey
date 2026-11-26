import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/crypto/kdf.dart';
import 'package:vankey/core/errors.dart';
import 'package:vankey/core/sync/sync_provider.dart';
import 'package:vankey/core/sync/sync_service.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/vault_session.dart';

const _fast = Argon2Params(opslimit: 2, memlimitBytes: 32 * 1024 * 1024);

/// Một thiết bị giả: có phiên, đồng hồ HLC và trạng thái đồng bộ riêng.
class Dev {
  Dev(this.session, String node, {this.maxAttempts = 5})
      : clock = HlcClock(node: node),
        data = VaultData.fromJson(session.payload),
        service = SyncService(FakeSyncProvider(), delay: (_) async {});

  final VaultSession session;
  final HlcClock clock;
  VaultData data;
  SyncState state = const SyncState();
  SyncService service;
  final int maxAttempts;

  Item add(String title, {String user = ''}) {
    final i = Item.create(type: ItemType.login, title: title, clock: clock, values: {'username': user});
    data = data.upsert(i);
    return i;
  }

  void edit(String id, String newTitle) => data = data.upsert(data.byId(id)!.edit(clock: clock, title: newTitle));

  Future<SyncOutcome> sync(FakeSyncProvider p) async {
    service = SyncService(p, delay: (_) async {});
    final out = await service.sync(session: session, local: data, state: state);
    data = out.data;
    state = out.state;
    return out;
  }
}

Future<(Dev, Dev, FakeSyncProvider)> _pair() async {
  final (sa, _) = await VaultSession.create(passphrase: 'correct horse battery', params: _fast);
  sa.payload = const VaultData().toJson();
  final a = Dev(sa, 'dev-a');
  final p = FakeSyncProvider();
  await a.sync(p); // A tải bản đầu lên
  final sb = await VaultSession.openWithPassphrase(p.stored!, 'correct horse battery');
  final b = Dev(sb, 'dev-b');
  await b.sync(p); // B nhận bản đầu
  return (a, b, p);
}

/// Nơi lưu KHÔNG có ghi có điều kiện (như Google Drive): mọi lần tải lên đều thành công và ghi đè bản cũ.
class NoCasProvider implements SyncProvider {
  NoCasProvider(this.inner);
  final FakeSyncProvider inner;

  @override
  String get name => 'no-cas';

  @override
  Future<RemoteBlob?> fetch() => inner.fetch();

  @override
  Future<String> upload(Uint8List bytes, {String? ifMatch}) async {
    inner.put(bytes); // bỏ qua ifMatch
    return inner.version;
  }
}

/// Máy đọc một bản CŨ (đọc trước khi máy kia ghi) rồi ghi đè lên nơi lưu không có ghi có điều kiện.
class StaleReadProvider implements SyncProvider {
  StaleReadProvider(this.stale, this.target);
  final RemoteBlob? stale;
  final SyncProvider target;
  bool _first = true;

  @override
  String get name => 'stale';

  @override
  Future<RemoteBlob?> fetch() async {
    if (_first) {
      _first = false;
      return stale;
    }
    return target.fetch();
  }

  @override
  Future<String> upload(Uint8List bytes, {String? ifMatch}) => target.upload(bytes, ifMatch: ifMatch);
}

void main() {
  test('nơi lưu không có ghi có điều kiện: hai máy ghi đè nhau nhưng sau vài lần đồng bộ không ai mất mục nào', () async {
    final (a, b, p) = await _pair();
    final nocas = NoCasProvider(p);
    a.add('chỉ có ở A');
    b.add('chỉ có ở B');
    final stale = await p.fetch(); // B đọc bản này TRƯỚC khi A ghi
    final serviceA = SyncService(nocas, delay: (_) async {});
    final serviceB = SyncService(StaleReadProvider(stale, nocas), delay: (_) async {});
    final outA = await serviceA.sync(session: a.session, local: a.data, state: a.state);
    a..data = outA.data..state = outA.state;
    final outB = await serviceB.sync(session: b.session, local: b.data, state: b.state);
    b..data = outB.data..state = outB.state;

    // Xác nhận đúng kịch bản: B đã ghi đè A, bản trên nơi lưu chỉ còn mục của B.
    final onStore = await VaultSession.openWithPassphrase(p.stored!, 'correct horse battery');
    final titlesOnStore = VaultData.fromJson(onStore.payload).items.map((i) => i.title).toSet();
    expect(titlesOnStore, {'chỉ có ở B'}, reason: 'A bị ghi đè');

    // Đồng bộ lại vài vòng: kết quả cuối cùng phải có đủ cả hai mục ở cả hai máy.
    for (var round = 0; round < 3; round++) {
      final oa = await serviceA.sync(session: a.session, local: a.data, state: a.state);
      a..data = oa.data..state = oa.state;
      final ob = await serviceB.sync(session: b.session, local: b.data, state: b.state);
      b..data = ob.data..state = ob.state;
    }
    final expected = {'chỉ có ở A', 'chỉ có ở B'};
    expect(a.data.items.map((i) => i.title).toSet(), expected);
    expect(b.data.items.map((i) => i.title).toSet(), expected);
    expect(a.data.tombstones, isEmpty, reason: 'không được sinh tombstone từ việc mất bản cập nhật');
  });

  test('tải bản đầu lên khi máy chủ còn trống', () async {
    final (s, _) = await VaultSession.create(passphrase: 'x' * 10, params: _fast);
    final d = Dev(s, 'a');
    d.add('GitHub');
    final p = FakeSyncProvider();
    final out = await d.sync(p);
    expect(out.uploaded, isTrue);
    expect(p.stored, isNotNull);
  });

  test('máy B thấy mục máy A thêm, và ngược lại', () async {
    final (a, b, p) = await _pair();
    a.add('Gmail');
    await a.sync(p);
    final out = await b.sync(p);
    expect(out.changedLocal, isTrue);
    expect(b.data.items.map((i) => i.title), ['Gmail']);

    b.add('Facebook');
    await b.sync(p);
    await a.sync(p);
    expect(a.data.items.map((i) => i.title).toSet(), {'Gmail', 'Facebook'});
  });

  test('hai máy sửa KHÁC mục cùng lúc: không mất mục nào, không xung đột', () async {
    final (a, b, p) = await _pair();
    final x = a.add('X');
    final y = a.add('Y');
    await a.sync(p);
    await b.sync(p);

    a.edit(x.id, 'X-từ-A');
    b.edit(y.id, 'Y-từ-B');
    await a.sync(p);
    final out = await b.sync(p);
    await a.sync(p);

    expect(out.conflicts, isEmpty);
    for (final d in [a, b]) {
      expect(d.data.byId(x.id)!.title, 'X-từ-A');
      expect(d.data.byId(y.id)!.title, 'Y-từ-B');
    }
  });

  test('hai máy sửa CÙNG mục: báo xung đột, hai máy cuối cùng giống nhau', () async {
    final (a, b, p) = await _pair();
    final x = a.add('X');
    await a.sync(p);
    await b.sync(p);

    a.edit(x.id, 'bản A');
    b.edit(x.id, 'bản B');
    await a.sync(p);
    final out = await b.sync(p);
    await a.sync(p);

    expect(out.conflicts, hasLength(1));
    expect(a.data.byId(x.id)!.title, b.data.byId(x.id)!.title);
  });

  test('máy A xóa vĩnh viễn, máy B không sửa: B cũng mất mục; xóa không "sống lại"', () async {
    final (a, b, p) = await _pair();
    final x = a.add('X');
    await a.sync(p);
    await b.sync(p);

    a.data = a.data.purge(x.id, clock: a.clock);
    await a.sync(p);
    await b.sync(p);
    expect(b.data.byId(x.id), isNull);
    await a.sync(p);
    expect(a.data.byId(x.id), isNull);
  });

  test('máy khác ghi chen giữa lúc tải và tải lên: tự thử lại, không mất dữ liệu của ai', () async {
    final (a, b, p) = await _pair();
    // B chuẩn bị sẵn một bản có mục B2 (dựa trên bản máy chủ hiện tại).
    b.add('B2');
    b.session.payload = b.data.toJson();
    final bBytes = await b.session.save();

    a.add('A2');
    final before = int.parse(p.version);
    p.beforeUpload = () => p.put(bBytes); // đúng lúc A tải lên, B ghi chen vào
    final out = await a.sync(p);

    expect(out.uploaded, isTrue);
    expect(int.parse(p.version), greaterThan(before + 1)); // có lần ghi chen và lần ghi sau khi thử lại
    expect(a.data.items.map((i) => i.title).toSet(), {'A2', 'B2'});
    await b.sync(p);
    expect(b.data.items.map((i) => i.title).toSet(), {'A2', 'B2'});
  });

  test('mất mạng: ném lỗi mạng, dữ liệu cục bộ còn nguyên, có mạng lại thì đồng bộ được', () async {
    final (a, _, p) = await _pair();
    a.add('Offline');
    p.offline = true;
    await expectLater(a.sync(p), throwsA(isA<SyncNetworkException>()));
    expect(a.data.items.map((i) => i.title), ['Offline']);

    p.offline = false;
    await a.sync(p);
    expect(p.stored, isNotNull);
  });

  test('mất mạng giữa chừng lúc tải lên rồi được thử lại thành công', () async {
    final (a, _, p) = await _pair();
    a.add('Retry');
    p.failUploads = 2;
    final out = await a.sync(p);
    expect(out.uploaded, isTrue);
  });

  test('đổi mật khẩu ở máy A lan sang máy B qua đồng bộ', () async {
    final (a, b, p) = await _pair();
    await a.session.changePassphrase('mật khẩu mới rất dài', params: _fast);
    await a.sync(p); // slotsRev mới hơn → phải tải lên dù dữ liệu không đổi
    await b.sync(p);

    final bytes = await b.session.save();
    final reopened = await VaultSession.openWithPassphrase(bytes, 'mật khẩu mới rất dài');
    expect(reopened.vaultId, a.session.vaultId);
    await expectLater(VaultSession.openWithPassphrase(bytes, 'correct horse battery'), throwsA(isA<AuthenticationFailedException>()));
  });

  test('bản trên máy chủ thuộc kho khác: từ chối, không ghi đè', () async {
    final (a, _, p) = await _pair();
    final (other, _) = await VaultSession.create(passphrase: 'another-passphrase', params: _fast);
    p.put(await other.save());
    await expectLater(a.sync(p), throwsA(isA<VaultException>()));
  });

  test('bản trên máy chủ bị sửa: không giải mã được, không bị ghi đè', () async {
    final (a, _, p) = await _pair();
    final bad = List<int>.from(p.stored!);
    bad[bad.length - 5] ^= 0xFF;
    final before = p.version;
    p.put(Uint8List.fromList(bad));
    await expectLater(a.sync(p), throwsA(isA<AuthenticationFailedException>()));
    expect(int.parse(p.version), int.parse(before) + 1); // chỉ lần put giả, không có lần ghi nào của ta
  });
}
