import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/crypto/kdf.dart';
import 'package:vankey/core/vault/hlc.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/vault_session.dart';
import 'package:vankey/core/vault/vault_storage.dart';

import '../../helpers/helpers.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('vankey_test_'));
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('VaultStorage', () {
    test('ghi rồi đọc lại; không còn file tạm', () async {
      final f = File('${dir.path}/vault.vkv');
      await VaultStorage.writeAtomic(f, Uint8List.fromList([1, 2, 3]));
      expect(await VaultStorage.read(f), [1, 2, 3]);
      expect(await File('${f.path}.tmp').exists(), isFalse);
    });

    test('ghi đè: nội dung mới thay thế, bản trước được giữ ở .bak', () async {
      final f = File('${dir.path}/vault.vkv');
      await VaultStorage.writeAtomic(f, Uint8List.fromList([1, 1, 1]));
      await VaultStorage.writeAtomic(f, Uint8List.fromList([2, 2, 2, 2]));
      expect(await VaultStorage.read(f), [2, 2, 2, 2]);
      expect(await VaultStorage.readBackup(f), [1, 1, 1]);
    });

    test('tự tạo thư mục còn thiếu; đọc file chưa có trả null', () async {
      final f = File('${dir.path}/a/b/c/vault.vkv');
      expect(await VaultStorage.read(f), isNull);
      await VaultStorage.writeAtomic(f, Uint8List.fromList([9]));
      expect(await VaultStorage.read(f), [9]);
    });

    test('kho thật: lưu xuống đĩa, mở lại bằng passphrase, và hai lần lưu liên tiếp giữ được bản trước', () async {
      const fast = Argon2Params(opslimit: 2, memlimitBytes: 32 * 1024 * 1024);
      final clock = HlcClock(node: 'A');
      final item = Item.create(type: ItemType.login, title: 'Ngân hàng', clock: clock, values: {'username': 'u', 'password': 'p'});
      final data = const VaultData().upsert(item);
      final (s, _) = await VaultSession.create(passphrase: 'Việt', initialPayload: data.toJson(), params: fast, random: SeededRandom(1));

      final f = File('${dir.path}/vault.vkv');
      await VaultStorage.writeAtomic(f, await s.save());
      final more = data.upsert(item.edit(clock: clock, title: 'Ngân hàng 2'));
      s.payload = more.toJson();
      await VaultStorage.writeAtomic(f, await s.save());

      final now = await VaultSession.openWithPassphrase((await VaultStorage.read(f))!, 'Việt');
      expect(VaultData.fromJson(now.payload).items.single.title, 'Ngân hàng 2');
      final before = await VaultSession.openWithPassphrase((await VaultStorage.readBackup(f))!, 'Việt');
      expect(VaultData.fromJson(before.payload).items.single.title, 'Ngân hàng');
    });
  });

  group('dọn thùng rác', () {
    test('mục trong thùng rác từ 30 ngày trở lên bị xóa vĩnh viễn, mục mới hơn được giữ', () {
      final clock = HlcClock(node: 'A');
      final now = DateTime.utc(2026, 6, 30);
      Item trashedDaysAgo(String title, int days) =>
          Item.create(type: ItemType.login, title: title, clock: clock, random: SeededRandom(title.hashCode))
              .moveToTrash(clock: clock, now: now.subtract(Duration(days: days)));
      final old = trashedDaysAgo('cũ', 31);
      final edge = trashedDaysAgo('đúng 30', 30);
      final fresh = trashedDaysAgo('mới', 29);
      final live = Item.create(type: ItemType.login, title: 'đang dùng', clock: clock, random: SeededRandom(7));
      var d = const VaultData();
      for (final i in [old, edge, fresh, live]) {
        d = d.upsert(i);
      }
      final out = d.purgeExpiredTrash(now: now, clock: clock);
      expect(out.items.map((i) => i.title).toSet(), {'mới', 'đang dùng'});
      expect(out.tombstones.map((t) => t.id).toSet(), {old.id, edge.id}, reason: 'để lại tombstone cho việc xóa lan sang máy khác');
    });
  });
}
