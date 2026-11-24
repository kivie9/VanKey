import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../vault/vault_storage.dart';
import 'sync_provider.dart';

/// Đồng bộ qua một thư mục (OneDrive, Dropbox, Syncthing, ổ mạng...). Chỉ chứa file đã mã hóa.
/// Phiên bản = SHA-256 của nội dung nên không phụ thuộc đồng hồ máy.
final class FolderSyncProvider implements SyncProvider {
  FolderSyncProvider(this.directory, {this.fileName = 'vankey-sync.vkv'});

  final Directory directory;
  final String fileName;

  @override
  String get name => 'folder';

  File get _file => File('${directory.path}${Platform.pathSeparator}$fileName');

  static String _version(Uint8List b) => sha256.convert(b).toString();

  @override
  Future<RemoteBlob?> fetch() async {
    try {
      final f = _file;
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      return RemoteBlob(bytes, _version(bytes));
    } on FileSystemException catch (e) {
      throw SyncNetworkException('không đọc được thư mục đồng bộ: ${e.message}');
    }
  }

  @override
  Future<String> upload(Uint8List bytes, {String? ifMatch}) async {
    try {
      final current = await fetch();
      if ((current?.version) != ifMatch) throw const SyncConflictException();
      await VaultStorage.writeAtomic(_file, bytes);
      return _version(bytes);
    } on FileSystemException catch (e) {
      throw SyncNetworkException('không ghi được thư mục đồng bộ: ${e.message}');
    }
  }
}
