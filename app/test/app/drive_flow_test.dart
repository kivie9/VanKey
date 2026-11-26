import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/google_drive_auth.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/vault_session.dart';

import '../helpers/mock_drive.dart';

/// Tài khoản Google giả: không có giao diện, token luôn là token tốt của Drive giả.
class _FakeGoogle implements DriveAccountAuth {
  _FakeGoogle(this.drive, {this.signInError});
  final MockDrive drive;
  final String? signInError;
  bool signedOut = false;

  @override
  String? get email => 'nguoi.dung@gmail.com';

  @override
  Future<String?> signIn() async => signInError;

  @override
  Future<void> signOut() async => signedOut = true;

  @override
  Future<String> token({bool forceRefresh = false}) async => drive.validToken;
}

const _pass = 'mat-khau-dai-cho-drive-1';

Future<VaultController> _device(Directory root, String name, MockDrive drive, {String? signInError, _FakeGoogle? google}) async {
  final dir = Directory('${root.path}${Platform.pathSeparator}$name')..createSync(recursive: true);
  final c = VaultController()
    ..driveBase = drive.base
    ..driveAuthFactory = (() => google ?? _FakeGoogle(drive, signInError: signInError));
  await c.init(dir: dir);
  addTearDown(c.dispose);
  return c;
}

Future<void> _until(bool Function() cond, {String what = ''}) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('quá thời gian chờ: $what');
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

void main() {
  late Directory tmp;
  late MockDrive drive;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('vk_drive_');
    drive = await MockDrive.start();
  });

  tearDown(() async {
    await drive.stop();
    tmp.deleteSync(recursive: true);
  });

  test('máy A: đăng nhập Google, Drive trống → tạo kho bằng một mật khẩu, lưu mã khôi phục rồi đồng bộ lên Drive', () async {
    final a = await _device(tmp, 'a', drive);
    expect(a.phase, Phase.onboarding);

    final r = await a.driveSignIn();
    expect(r.error, isNull);
    expect(r.hasVault, isFalse);

    expect(await a.driveCreateVault('ngan'), isNotNull, reason: 'mật khẩu quá ngắn');
    expect(await a.driveCreateVault(_pass), isNull);
    expect(a.pendingRecovery, isNotNull);
    expect(a.phase, Phase.onboarding, reason: 'chưa vào app tới khi xác nhận đã lưu mã khôi phục');
    expect(a.syncLabel, contains('nguoi.dung@gmail.com'));

    a.confirmRecoverySaved();
    expect(a.phase, Phase.unlocked);
    await _until(() => a.syncStatus == SyncStatus.idle && a.lastSync != null, what: 'A đẩy kho lên Drive');
    expect(drive.files, hasLength(1));
    expect(drive.files.values.single.name, 'vankey.vkv');
  });

  test('máy B: Drive đã có kho → phải MỞ (không tạo đè); sai mật khẩu bị từ chối; đúng mật khẩu thì vào và thấy dữ liệu của A', () async {
    final a = await _device(tmp, 'a', drive);
    await a.driveSignIn();
    await a.driveCreateVault(_pass);
    a.confirmRecoverySaved();
    await _until(() => a.syncStatus == SyncStatus.idle && a.lastSync != null, what: 'A đồng bộ lần đầu');
    a.upsert(Item.create(type: ItemType.login, title: 'GitHub', clock: a.clock, values: {'username': 'van'}));
    await a.syncNow();

    final b = await _device(tmp, 'b', drive);
    final r = await b.driveSignIn();
    expect(r.hasVault, isTrue);
    final bytesBefore = drive.files.values.single.bytes;
    expect(await b.driveCreateVault(_pass), isNotNull, reason: 'Drive đã có kho thì không được tạo đè');
    expect(b.pendingRecovery, isNull);
    expect(drive.files.values.single.bytes, bytesBefore, reason: 'kho trên Drive không bị đụng tới');

    await b.driveSignIn(); // sau lần từ chối phải đăng nhập Google lại
    expect(await b.driveOpenVault('sai-mat-khau-nhe-123'), isNotNull);
    expect(b.phase, Phase.onboarding);
    expect(await b.driveOpenVault(_pass), isNull);
    expect(b.phase, Phase.unlocked);
    expect(b.data.items.map((i) => i.title), contains('GitHub'));
    expect(b.syncLabel, contains('Google Drive'));
  });

  test('đăng nhập Google lỗi hoặc bị hủy: báo lỗi, không đổi trạng thái', () async {
    final a = await _device(tmp, 'a', drive, signInError: 'Đã hủy đăng nhập Google');
    final r = await a.driveSignIn();
    expect(r.error, 'Đã hủy đăng nhập Google');
    expect(a.phase, Phase.onboarding);
    expect(drive.requests, 0, reason: 'chưa đăng nhập thì không gọi Drive');
    expect(await a.driveCreateVault(_pass), isNotNull, reason: 'chưa đăng nhập Google');
  });

  test('khởi động lại app: cấu hình Drive được đọc lại, đồng bộ tiếp được', () async {
    final a = await _device(tmp, 'a', drive);
    await a.driveSignIn();
    await a.driveCreateVault(_pass);
    a.confirmRecoverySaved();
    await _until(() => a.syncStatus == SyncStatus.idle && a.lastSync != null, what: 'A đồng bộ lần đầu');
    await a.lock();

    final again = VaultController()
      ..driveBase = drive.base
      ..driveAuthFactory = (() => _FakeGoogle(drive));
    await again.init(dir: Directory('${tmp.path}${Platform.pathSeparator}a'));
    addTearDown(again.dispose);
    expect(again.provider, isNotNull, reason: 'phải dựng lại nơi đồng bộ Drive');
    expect(again.syncLabel, contains('Google Drive'));
    expect(await again.unlockWithPassphrase(_pass), isTrue);
    await again.syncNow();
    expect(again.syncStatus, SyncStatus.idle);
    expect(again.syncError, isNull);
  });

  test('bật Drive từ Cài đặt cho kho có sẵn: đẩy kho lên; Drive đã có kho KHÁC thì từ chối và không ghi đè', () async {
    final a = await _device(tmp, 'a', drive);
    await a.createVault(_pass);
    a.confirmRecoverySaved();
    a.upsert(Item.create(type: ItemType.login, title: 'Có sẵn', clock: a.clock, values: {'username': 'u'}));
    expect(await a.enableDriveSync(), isNull);
    await _until(() => a.syncStatus == SyncStatus.idle && a.lastSync != null, what: 'A đồng bộ');
    final onDrive = await VaultSession.openWithPassphrase(drive.files.values.single.bytes, _pass);
    expect(VaultData.fromJson(onDrive.payload).items.map((i) => i.title), contains('Có sẵn'));

    // Một người khác (kho khác, khóa khác) thử bật Drive cùng tài khoản: bị từ chối, kho trên Drive còn nguyên.
    final other = await _device(tmp, 'other', drive);
    await other.createVault('mot-mat-khau-khac-hoan-toan');
    other.confirmRecoverySaved();
    final before = drive.files.values.single.bytes;
    final err = await other.enableDriveSync();
    expect(err, isNotNull);
    expect(err, contains('kho khác'));
    expect(drive.files.values.single.bytes, before);
    expect(other.provider, isNull);
  });

  test('tắt đồng bộ khi dùng Drive: đăng xuất Google', () async {
    final google = _FakeGoogle(drive);
    final a = await _device(tmp, 'a', drive, google: google);
    await a.createVault(_pass);
    a.confirmRecoverySaved();
    expect(await a.enableDriveSync(), isNull);
    await a.disableSync();
    expect(google.signedOut, isTrue);
    expect(a.provider, isNull);
  });
}
