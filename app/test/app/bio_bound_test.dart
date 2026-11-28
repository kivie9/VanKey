// Mở khóa sinh trắc gắn với phần cứng (Android Keystore, Windows Hello): app chỉ cất vault key đã được bọc bằng khóa
// của hệ điều hành, không bao giờ cất mật khẩu. Kênh "vankey/platform" được giả lập; phần thật nằm ở
// BiometricVault.kt và windows/runner/hello_vault.cpp.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/platform_bridge.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

const _pass = 'mat-khau-nho-123';
const _bridge = MethodChannel('vankey/platform');

/// Khóa phần cứng giả: XOR với một byte. [failWith] khác null thì lần giải mã sau ném lỗi đó.
final class _FakeHello {
  String? failWith;
  int prompts = 0;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'bioAvailable':
        return true;
      case 'bioDelete':
        return null;
      case 'bioEncrypt' || 'bioDecrypt':
        prompts++;
        if (call.method == 'bioDecrypt' && failWith != null) throw PlatformException(code: failWith!);
        final data = (call.arguments as Map)['data'] as Uint8List;
        return Uint8List.fromList([for (final b in data) b ^ 0x5a]);
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _FakeHello hello;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('vk_bio_');
    hello = _FakeHello();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_bridge, hello.handle);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_bridge, null);
    dir.deleteSync(recursive: true);
  });

  Future<VaultController> open() async {
    final c = VaultController();
    await c.init(dir: dir);
    addTearDown(c.dispose);
    return c;
  }

  Future<VaultController> created() async {
    final a = await open();
    await a.createVault(_pass);
    a.confirmRecoverySaved();
    a.upsert(Item.create(type: ItemType.login, title: 'GitHub', clock: a.clock));
    await a.lock();
    expect(await a.unlockWithPassphrase(_pass), isTrue);
    return a;
  }

  test('bật: chỉ cất vault key đã bọc, không cất mật khẩu', () async {
    final a = await created();
    expect(await a.enableBiometric(_pass), isNull);
    expect(a.biometricEnabled, isTrue);
    final all = await const FlutterSecureStorage().readAll();
    expect(all.keys, contains('vault.bio.key.v1'));
    expect(all.keys, isNot(contains('vault.bio.passphrase')));
    expect(all.values.any((v) => v.contains(_pass)), isFalse);
  }, skip: !PlatformBridge.bioBound);

  test('mở bằng sinh trắc sau khi khóa', () async {
    final a = await created();
    await a.enableBiometric(_pass);
    await a.lock();
    hello.prompts = 0;
    expect(await a.unlockWithBiometric(), isTrue);
    expect(a.phase, Phase.unlocked);
    expect(hello.prompts, 1, reason: 'mỗi lần mở hỏi Windows Hello / vân tay đúng một lần');
    expect(a.data.items.map((i) => i.title), contains('GitHub'));
  }, skip: !PlatformBridge.bioBound);

  test('người dùng hủy: vẫn khóa, vẫn giữ thiết lập để thử lại', () async {
    final a = await created();
    await a.enableBiometric(_pass);
    await a.lock();
    hello.failWith = 'canceled';
    expect(await a.unlockWithBiometric(), isFalse);
    expect(a.phase, Phase.locked);
    expect(a.biometricEnabled, isTrue);
  }, skip: !PlatformBridge.bioBound);

  test('khóa Windows Hello / Keystore mất (đặt lại Hello, đổi vân tay): tắt, báo bật lại', () async {
    final a = await created();
    await a.enableBiometric(_pass);
    await a.lock();
    hello.failWith = 'invalidated';
    expect(await a.unlockWithBiometric(), isFalse);
    expect(a.biometricEnabled, isFalse);
    expect(a.error, isNotNull);
    expect(await const FlutterSecureStorage().read(key: 'vault.bio.key.v1'), isNull);
  }, skip: !PlatformBridge.bioBound);

  test('bản cũ cất mật khẩu (chỉ chặn bằng giao diện): xóa ngay khi mở app, nhắc bật lại', () async {
    await created();
    final stored = await const FlutterSecureStorage().readAll();
    FlutterSecureStorage.setMockInitialValues({...stored, 'vault.bio.passphrase': _pass});
    final b = await open();
    expect(b.biometricEnabled, isFalse);
    expect(b.bioNeedsReenable, isTrue);
    expect(await const FlutterSecureStorage().read(key: 'vault.bio.passphrase'), isNull);
  }, skip: !PlatformBridge.bioBound);

  test('blob hỏng: tắt sinh trắc, không mở kho', () async {
    final a = await created();
    await a.enableBiometric(_pass);
    await a.lock();
    final all = await const FlutterSecureStorage().readAll();
    FlutterSecureStorage.setMockInitialValues({...all, 'vault.bio.key.v1': base64Encode(List.filled(32, 1))});
    expect(await a.unlockWithBiometric(), isFalse);
    expect(a.phase, Phase.locked);
  }, skip: !PlatformBridge.bioBound);
}
