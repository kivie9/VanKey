import 'dart:typed_data';

/// Một bản kho trên nơi đồng bộ. [version] là mã phiên bản do nơi đó cấp (ETag, số thứ tự...), chỉ để so sánh bằng nhau.
final class RemoteBlob {
  const RemoteBlob(this.bytes, this.version);
  final Uint8List bytes;
  final String version;
}

/// Có người khác ghi vào kho trên máy chủ sau lần ta đọc cuối. Lặp lại từ bước tải.
final class SyncConflictException implements Exception {
  const SyncConflictException();
  @override
  String toString() => 'SyncConflictException';
}

/// Lỗi mạng hoặc máy chủ tạm thời. Thử lại sau được.
final class SyncNetworkException implements Exception {
  const SyncNetworkException(this.message);
  final String message;
  @override
  String toString() => 'SyncNetworkException: $message';
}

/// Cần đăng nhập lại (token hết hạn, bị thu hồi). Thử lại không giúp ích.
final class SyncAuthException implements Exception {
  const SyncAuthException(this.message);
  final String message;
  @override
  String toString() => 'SyncAuthException: $message';
}

/// Nơi lưu bản mã hóa của kho: Google Drive, Cloudflare, thư mục cục bộ... Chỉ thấy byte đã mã hóa.
abstract interface class SyncProvider {
  String get name;

  /// `null` nếu chưa có kho trên nơi đồng bộ.
  Future<RemoteBlob?> fetch();

  /// Tải lên và trả về phiên bản mới. [ifMatch] = phiên bản ta đã đọc; `null` nghĩa là "chỉ tạo mới".
  /// Lệch phiên bản → [SyncConflictException].
  Future<String> upload(Uint8List bytes, {String? ifMatch});
}

/// Bản trong bộ nhớ để test: giống một máy chủ thật có kiểm tra phiên bản, kèm cách giả lập lỗi.
final class FakeSyncProvider implements SyncProvider {
  FakeSyncProvider({this.name = 'fake'});

  @override
  final String name;

  Uint8List? _bytes;
  int _version = 0;

  /// Đang mất mạng: mọi lệnh ném [SyncNetworkException].
  bool offline = false;

  /// Số lần tải lên kế tiếp sẽ bị lỗi mạng (để thử "mất mạng giữa chừng").
  int failUploads = 0;

  /// Chạy ngay trước khi nhận tải lên (để giả lập máy khác ghi chen vào).
  void Function()? beforeUpload;

  int uploadCount = 0;

  Uint8List? get stored => _bytes;
  String get version => '$_version';

  @override
  Future<RemoteBlob?> fetch() async {
    if (offline) throw const SyncNetworkException('offline');
    final b = _bytes;
    return b == null ? null : RemoteBlob(Uint8List.fromList(b), '$_version');
  }

  @override
  Future<String> upload(Uint8List bytes, {String? ifMatch}) async {
    if (offline) throw const SyncNetworkException('offline');
    final hook = beforeUpload;
    if (hook != null) {
      beforeUpload = null;
      hook();
    }
    if (failUploads > 0) {
      failUploads--;
      throw const SyncNetworkException('mất mạng giữa chừng');
    }
    final current = _bytes == null ? null : '$_version';
    if (ifMatch != current) throw const SyncConflictException();
    _bytes = Uint8List.fromList(bytes);
    _version++;
    uploadCount++;
    return '$_version';
  }

  /// Giả lập máy khác ghi thẳng một bản lên.
  void put(Uint8List bytes) {
    _bytes = Uint8List.fromList(bytes);
    _version++;
  }
}
