// "Không tự khóa": mở lại app vào thẳng kho, không hỏi mật khẩu. Tự khóa hoặc đổi chế độ thì lần sau phải nhập lại.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/constants.dart';
import 'package:vankey/app/vault_controller.dart';
import 'package:vankey/core/vault/models.dart';

const _pass = 'mat-khau-nho-123';

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
    dir = Directory.systemTemp.createTempSync('vk_remember_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> created() async {
    final a = await _open(dir);
    expect(a.lockAfterSeconds, LockPolicy.never, reason: 'mặc định không tự khóa');
    await a.createVault(_pass);
    a.confirmRecoverySaved();
    a.upsert(Item.create(type: ItemType.login, title: 'GitHub', clock: a.clock));
    await a.lock(); // ghi kho xuống đĩa
    expect(await a.unlockWithPassphrase(_pass), isTrue);
  }

  test('không tự khóa: mở lại app vào thẳng kho, không hỏi mật khẩu', () async {
    await created();
    final b = await _open(dir);
    expect(b.phase, Phase.unlocked);
    expect(b.data.items.map((i) => i.title), contains('GitHub'));
  });

  test('chỉ cất khóa kho, không cất mật khẩu; mở lại không cần mật khẩu', () async {
    await created();
    const s = FlutterSecureStorage();
    final all = await s.readAll();
    expect(all.keys, contains('vault.remember.key'));
    expect(all.keys, isNot(contains('vault.remember.passphrase')));
    expect(all.values.any((v) => v.contains(_pass)), isFalse, reason: 'mật khẩu không nằm trong Keystore');
    expect(base64Decode(all['vault.remember.key']!), hasLength(32));
  });

  test('bản trước đã cất mật khẩu: mở được, rồi đổi sang cất khóa', () async {
    await created();
    FlutterSecureStorage.setMockInitialValues({'vault.remember.passphrase': _pass});
    final b = await _open(dir);
    expect(b.phase, Phase.unlocked);
    final all = await const FlutterSecureStorage().readAll();
    expect(all.keys, contains('vault.remember.key'));
    expect(all.keys, isNot(contains('vault.remember.passphrase')));
  });

  test('khóa đã cất không còn khớp: hỏi mật khẩu, không vào được', () async {
    await created();
    FlutterSecureStorage.setMockInitialValues({'vault.remember.key': base64Encode(List.filled(32, 7))});
    final b = await _open(dir);
    expect(b.phase, Phase.locked);
    expect(b.error, isNull);
    expect(await const FlutterSecureStorage().read(key: 'vault.remember.key'), isNull);
  });

  test('tự bấm khóa: lần mở sau phải nhập mật khẩu, nhập xong lại được ghi nhớ', () async {
    await created();
    final b = await _open(dir);
    await b.lock();
    final c = await _open(dir);
    expect(c.phase, Phase.locked);
    expect(await c.unlockWithPassphrase(_pass), isTrue);
    final d = await _open(dir);
    expect(d.phase, Phase.unlocked);
  });

  test('đổi sang tự khóa sau 1 phút: lần mở sau phải nhập mật khẩu', () async {
    await created();
    final b = await _open(dir);
    await b.setLockAfter(60);
    final c = await _open(dir);
    expect(c.phase, Phase.locked);
    expect(await c.unlockWithPassphrase(_pass), isTrue);
    final d = await _open(dir);
    expect(d.phase, Phase.locked, reason: 'chế độ tự khóa không ghi nhớ mật khẩu');
  });

  test('đổi mật khẩu: mở lại app vẫn vào thẳng bằng mật khẩu mới', () async {
    await created();
    final b = await _open(dir);
    expect(await b.changeVaultPassword(_pass, 'mat-khau-moi-456'), isNull);
    final c = await _open(dir);
    expect(c.phase, Phase.unlocked);
    expect(await c.verifyPassphrase('mat-khau-moi-456'), isTrue);
  });
}
