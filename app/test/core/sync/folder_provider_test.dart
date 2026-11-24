import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/sync/folder_sync_provider.dart';
import 'package:vankey/core/sync/sync_provider.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vk_sync_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('thư mục trống: fetch trả null; upload đầu tiên cần ifMatch null', () async {
    final p = FolderSyncProvider(dir);
    expect(await p.fetch(), isNull);
    final v = await p.upload(Uint8List.fromList([1, 2, 3]));
    final got = await p.fetch();
    expect(got!.bytes, [1, 2, 3]);
    expect(got.version, v);
  });

  test('ghi khi phiên bản đã đổi bị từ chối (xung đột)', () async {
    final p = FolderSyncProvider(dir);
    final v1 = await p.upload(Uint8List.fromList([1]));
    await p.upload(Uint8List.fromList([2]), ifMatch: v1); // máy khác ghi
    await expectLater(p.upload(Uint8List.fromList([3]), ifMatch: v1), throwsA(isA<SyncConflictException>()));
    expect((await p.fetch())!.bytes, [2]);
  });

  test('tạo mới khi đã có file bị từ chối', () async {
    final p = FolderSyncProvider(dir);
    await p.upload(Uint8List.fromList([1]));
    await expectLater(p.upload(Uint8List.fromList([9])), throwsA(isA<SyncConflictException>()));
  });
}
