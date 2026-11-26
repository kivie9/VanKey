import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/crypto/kdf.dart';
import 'package:vankey/core/sync/drive_sync.dart';
import 'package:vankey/core/sync/sync_provider.dart';
import 'package:vankey/core/sync/sync_service.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/vault_session.dart';

import '../../helpers/mock_drive.dart';

const _fast = Argon2Params(opslimit: 2, memlimitBytes: 32 * 1024 * 1024);
const _pass = 'correct horse battery';

/// Token giả: lần đầu trả token hết hạn; sau khi bị từ chối (forceRefresh) trả token tốt.
class _Auth implements AccessTokenSource {
  _Auth(this.drive, {this.startExpired = false, this.neverRefreshes = false});
  final MockDrive drive;
  final bool startExpired;
  final bool neverRefreshes;
  int refreshes = 0;

  @override
  Future<String> token({bool forceRefresh = false}) async {
    if (forceRefresh) refreshes++;
    if (neverRefreshes) return 'het-han';
    return startExpired && !forceRefresh && refreshes == 0 ? 'het-han' : drive.validToken;
  }
}

Uint8List _bytes(int n, int fill) => Uint8List(n)..fillRange(0, n, fill);

/// Một thiết bị giả dùng DriveSync thật.
class _Dev {
  _Dev(this.session, String node, this.drive)
      : clock = HlcClock(node: node),
        data = VaultData.fromJson(session.payload);
  final VaultSession session;
  final HlcClock clock;
  final MockDrive drive;
  VaultData data;
  SyncState state = const SyncState();

  Item add(String title) {
    final i = Item.create(type: ItemType.login, title: title, clock: clock, values: {'username': 'u'});
    data = data.upsert(i);
    return i;
  }

  Future<SyncOutcome> sync() async {
    final p = DriveSync(_Auth(drive), base: drive.base);
    addTearDown(p.close);
    final out = await SyncService(p, delay: (_) async {}).sync(session: session, local: data, state: state);
    data = out.data;
    state = out.state;
    return out;
  }

  Set<String> get titles => data.items.map((i) => i.title).toSet();
}

Future<(_Dev, _Dev, MockDrive)> _pair() async {
  final drive = await MockDrive.start();
  addTearDown(drive.stop);
  final (sa, _) = await VaultSession.create(passphrase: _pass, params: _fast);
  sa.payload = const VaultData().toJson();
  final a = _Dev(sa, 'dev-a', drive);
  await a.sync();
  final sb = await VaultSession.openWithPassphrase(drive.files.values.single.bytes, _pass);
  final b = _Dev(sb, 'dev-b', drive);
  await b.sync();
  return (a, b, drive);
}

void main() {
  group('DriveSync với Drive giả', () {
    late MockDrive drive;
    late DriveSync sync;

    setUp(() async {
      drive = await MockDrive.start();
      sync = DriveSync(_Auth(drive), base: drive.base);
    });

    tearDown(() async {
      sync.close();
      await drive.stop();
    });

    test('chưa có file → fetch trả null; tải lên không điều kiện tạo file mới; đọc lại đúng byte và phiên bản', () async {
      expect(await sync.fetch(), isNull);
      final blob = _bytes(300, 7);
      final v = await sync.upload(blob);
      expect(drive.files, hasLength(1));
      expect(drive.files.values.single.name, 'vankey.vkv');
      final got = (await sync.fetch())!;
      expect(got.bytes, blob);
      expect(got.version, v);
      expect(got.version, DriveSync.versionOf(blob));
    });

    test('ghi đè khi phiên bản đúng; phiên bản đổi theo nội dung', () async {
      final v1 = await sync.upload(_bytes(100, 1));
      final v2 = await sync.upload(_bytes(100, 2), ifMatch: v1);
      expect(v2, isNot(v1));
      expect((await sync.fetch())!.bytes, _bytes(100, 2));
    });

    test('phiên bản lệch → SyncConflictException và KHÔNG ghi đè; tạo mới khi đã có file → xung đột', () async {
      final v1 = await sync.upload(_bytes(100, 1));
      drive.files.values.single.bytes = _bytes(100, 9); // máy khác vừa ghi
      await expectLater(sync.upload(_bytes(100, 2), ifMatch: v1), throwsA(isA<SyncConflictException>()));
      expect(drive.files.values.single.bytes, _bytes(100, 9), reason: 'bản của máy kia còn nguyên');
      await expectLater(sync.upload(_bytes(100, 3)), throwsA(isA<SyncConflictException>()));
    });

    test('file đã biến mất mà ta tưởng còn → xung đột (tải lại rồi tạo mới), không tạo trùng', () async {
      final v1 = await sync.upload(_bytes(100, 1));
      drive.files.clear();
      await expectLater(sync.upload(_bytes(100, 2), ifMatch: v1), throwsA(isA<SyncConflictException>()));
      expect(drive.files, isEmpty);
    });

    test('có nhiều file trùng tên (hai máy cùng tạo lần đầu): mọi máy chọn file tạo sớm nhất', () async {
      drive.put('vankey.vkv', _bytes(50, 1)); // tạo trước
      drive.put('vankey.vkv', _bytes(50, 2));
      expect((await sync.fetch())!.bytes, _bytes(50, 1));
      drive.put('khac.vkv', _bytes(50, 3));
      expect((await sync.fetch())!.bytes, _bytes(50, 1), reason: 'file tên khác bị bỏ qua');
    });

    test('token hết hạn (401): lấy token mới một lần rồi chạy tiếp', () async {
      final auth = _Auth(drive, startExpired: true);
      final s = DriveSync(auth, base: drive.base);
      addTearDown(s.close);
      expect(await s.fetch(), isNull);
      expect(auth.refreshes, 1);
    });

    test('token vẫn bị từ chối sau khi làm mới → SyncAuthException (cần đăng nhập lại)', () async {
      final s = DriveSync(_Auth(drive, neverRefreshes: true), base: drive.base);
      addTearDown(s.close);
      await expectLater(s.fetch(), throwsA(isA<SyncAuthException>()));
    });

    test('lỗi tạm thời → SyncNetworkException (được thử lại): giới hạn tốc độ, hết dung lượng, 500, 429', () async {
      for (final (status, reason) in [(403, 'rateLimitExceeded'), (403, 'userRateLimitExceeded'), (403, 'storageQuotaExceeded'), (500, 'backendError'), (429, 'rateLimitExceeded')]) {
        drive.injected.add((status, reason));
        await expectLater(sync.fetch(), throwsA(isA<SyncNetworkException>()), reason: '$status $reason');
      }
    });

    test('403 do thiếu quyền → SyncAuthException, không phải lỗi mạng', () async {
      drive.injected.add((403, 'insufficientPermissions'));
      await expectLater(sync.fetch(), throwsA(isA<SyncAuthException>()));
    });

    test('mất kết nối → SyncNetworkException', () async {
      final dead = DriveSync(_Auth(drive), base: Uri.parse('http://127.0.0.1:1'));
      addTearDown(dead.close);
      await expectLater(dead.fetch(), throwsA(isA<SyncNetworkException>()));
    });

    test('SyncService thử lại khi gặp giới hạn tốc độ rồi thành công', () async {
      final (s, _) = await VaultSession.create(passphrase: _pass, params: _fast);
      s.payload = const VaultData().toJson();
      drive.injected
        ..add((403, 'rateLimitExceeded'))
        ..add((503, 'backendError'));
      final out = await SyncService(sync, delay: (_) async {}).sync(session: s, local: VaultData.fromJson(s.payload));
      expect(out.uploaded, isTrue);
      expect(drive.files, hasLength(1));
    });
  });

  group('hai máy qua Drive giả', () {
    test('mỗi máy thêm một mục: sau khi đồng bộ cả hai máy đều có đủ', () async {
      final (a, b, _) = await _pair();
      a.add('từ A');
      await a.sync();
      b.add('từ B');
      await b.sync();
      await a.sync();
      expect(a.titles, {'từ A', 'từ B'});
      expect(b.titles, {'từ A', 'từ B'});
    });

    test('máy B đã đọc xong nhưng máy A kịp ghi trước khi B ghi: kiểm tra trước khi ghi bắt được, B gộp lại, không ai mất mục', () async {
      final (a, b, drive) = await _pair();
      a.add('từ A');
      b.add('từ B');
      await a.sync(); // A ghi trước
      await b.sync(); // B đọc bản mới của A, gộp rồi ghi
      await a.sync();
      expect(a.titles, {'từ A', 'từ B'});
      expect(b.titles, {'từ A', 'từ B'});
      expect(a.data.tombstones, isEmpty);
      expect(drive.files, hasLength(1));
    });

    test('KHOẢNG HỞ: máy khác ghi chen đúng giữa lúc kiểm tra và lúc ghi (bị ghi đè) → sau vài lần đồng bộ không ai mất mục', () async {
      final (a, b, drive) = await _pair();
      a.add('từ A');
      b.add('từ B');

      // B đã ghi THÀNH CÔNG bản có "từ B" lên Drive (nên gốc đồng bộ của B đã có mục đó), rồi A ghi đè ngay sau đó
      // vì A kiểm tra phiên bản xong thì B mới ghi chen vào đúng khoảng hở.
      b.session.payload = b.data.toJson();
      final bBytes = await b.session.save();
      b.state = SyncState(baseBytes: bBytes, remoteVersion: DriveSync.versionOf(bBytes));
      drive.beforePatch = (file) => file.bytes = bBytes; // B ghi chen ngay trước khi lệnh ghi của A chạy
      await a.sync(); // A kiểm tra phiên bản (khớp) rồi ghi: bản của A đè lên bản của B

      expect(drive.files.values.single.bytes, isNot(bBytes), reason: 'bản của B đã bị ghi đè');
      for (var round = 0; round < 3; round++) {
        await b.sync();
        await a.sync();
      }
      expect(a.titles, {'từ A', 'từ B'});
      expect(b.titles, {'từ A', 'từ B'});
      expect(a.data.tombstones, isEmpty);
      expect(b.data.tombstones, isEmpty);
    });

    test('kho trên Drive là bản mã hóa: Google chỉ thấy byte, không có tên mục hay mật khẩu', () async {
      final (a, _, drive) = await _pair();
      a.add('MatKhauNganHang-Bi-Mat');
      await a.sync();
      final raw = String.fromCharCodes(drive.files.values.single.bytes);
      expect(raw.contains('MatKhauNganHang'), isFalse);
      expect(raw.contains('username'), isFalse);
      // và chỉ mở được bằng đúng mật khẩu
      await expectLater(VaultSession.openWithPassphrase(drive.files.values.single.bytes, 'sai-mat-khau'), throwsA(anything));
    });
  });
}
