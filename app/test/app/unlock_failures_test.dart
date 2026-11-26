// Bộ đếm nhập sai mật khẩu nằm trong kho khóa của hệ điều hành: tắt app mở lại không được đếm lại từ đầu.
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/constants.dart';
import 'package:vankey/app/vault_controller.dart';

const _pass = 'mat-khau-dung-123';

Future<VaultController> _open(Directory dir) async {
  final c = VaultController();
  await c.init(dir: dir);
  addTearDown(c.dispose);
  return c;
}

void main() {
  late Directory dir;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('vk_fail_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('sai đủ số lần thì bị chờ; mở lại app vẫn phải chờ; đúng mật khẩu thì xóa bộ đếm', () async {
    final a = await _open(dir);
    await a.createVault(_pass);
    a.confirmRecoverySaved();
    await a.setLockAfter(0);
    await a.lock();
    for (var i = 0; i < LockPolicy.freeAttempts; i++) {
      expect(await a.unlockWithPassphrase('sai-$i'), isFalse);
    }

    final b = await _open(dir);
    expect(b.phase, Phase.locked);
    expect(await b.unlockWithPassphrase(_pass), isFalse, reason: 'vẫn đang trong thời gian chờ sau khi mở lại app');
    expect(b.error, contains('${LockPolicy.baseWaitSeconds}'));

    // Hết thời gian chờ (giả lập bằng cách sửa thời điểm đã lưu về quá khứ): mở được và bộ đếm bị xóa.
    const s = FlutterSecureStorage();
    await s.write(key: 'vault.unlock.failures', value: '{"n":${LockPolicy.freeAttempts},"until":"2000-01-01T00:00:00Z"}');
    final c = await _open(dir);
    expect(await c.unlockWithPassphrase(_pass), isTrue);
    expect(await s.read(key: 'vault.unlock.failures'), isNull);
  });

  test('thời điểm chờ đã lưu xa bất thường bị giới hạn ở mức chờ tối đa', () async {
    final a = await _open(dir);
    await a.createVault(_pass);
    a.confirmRecoverySaved();
    await a.setLockAfter(0);
    await a.lock();
    await const FlutterSecureStorage().write(key: 'vault.unlock.failures', value: '{"n":3,"until":"2999-01-01T00:00:00Z"}');
    final b = await _open(dir);
    expect(await b.unlockWithPassphrase(_pass), isFalse);
    final secs = int.parse(RegExp(r'\d+').firstMatch(b.error!)!.group(0)!);
    expect(secs, lessThanOrEqualTo(LockPolicy.maxWaitSeconds + 1));
  });
}
