import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'sync_provider.dart';

/// Nguồn access token OAuth cho Google Drive (đăng nhập Google nằm ở tầng ứng dụng, xem `app/google_drive_auth.dart`).
abstract interface class AccessTokenSource {
  /// Trả về access token còn dùng được. [forceRefresh] = token vừa bị Google từ chối (401), lấy token mới.
  /// Ném [SyncAuthException] nếu cần đăng nhập lại.
  Future<String> token({bool forceRefresh = false});
}

/// Đồng bộ qua Google Drive: một file `vankey.vkv` (bản đã mã hóa) trong thư mục ẩn `appDataFolder` của app.
/// Chỉ cần quyền `drive.appdata`, Google không thấy nội dung vì file đã mã hóa từ máy.
///
/// **Không có ghi có điều kiện**: Drive không cho "chỉ ghi nếu file chưa đổi". [upload] kiểm tra bản đang có trên Drive
/// ngay trước khi ghi và báo [SyncConflictException] nếu lệch, nhưng vẫn còn một khoảng hở rất ngắn giữa lúc kiểm tra
/// và lúc ghi. Nếu hai máy lọt vào khoảng hở đó, một bên bị ghi đè; cách gộp ba chiều (`mergeVaults`) coi mục vắng mặt
/// là "chưa có" chứ không phải "đã xóa", nên máy bị ghi đè sẽ ghi lại phần của mình ở lần đồng bộ sau.
final class DriveSync implements SyncProvider {
  DriveSync(this._auth, {HttpClient? client, Uri? base, this.fileName = 'vankey.vkv'})
      : _client = client ?? (HttpClient()..connectionTimeout = connectTimeout),
        _base = base ?? Uri.parse('https://www.googleapis.com');

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const connectTimeout = Duration(seconds: 15);
  static const responseTimeout = Duration(seconds: 60);

  final AccessTokenSource _auth;
  final HttpClient _client;
  final Uri _base;
  final String fileName;

  @override
  String get name => 'Google Drive';

  /// Mã băm MD5 (hex) của nội dung: cũng là cách Drive báo `md5Checksum`, nên so sánh được với metadata.
  static String versionOf(Uint8List bytes) => md5.convert(bytes).toString();

  // ---- Gọi HTTP, tự làm mới token một lần khi bị 401 ----

  Future<(int, Uint8List)> _send(
    String method,
    String path, {
    Map<String, String> query = const {},
    Uint8List? body,
    String? contentType,
  }) async {
    for (var attempt = 0;; attempt++) {
      final token = await _auth.token(forceRefresh: attempt > 0);
      final uri = _base.replace(path: path, queryParameters: query.isEmpty ? null : query);
      try {
        final req = await _client.openUrl(method, uri);
        req.headers.set('authorization', 'Bearer $token');
        if (body != null) {
          req.headers.set('content-type', contentType ?? 'application/octet-stream');
          req.contentLength = body.length;
          req.add(body);
        }
        final res = await req.close().timeout(responseTimeout);
        final out = await res.fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d));
        final bytes = out.takeBytes();
        if (res.statusCode == 401 && attempt == 0) continue; // token hết hạn: lấy token mới rồi thử lại một lần
        return (res.statusCode, bytes);
      } on SocketException catch (e) {
        throw SyncNetworkException(e.message);
      } on TimeoutException {
        throw const SyncNetworkException('hết thời gian chờ Google Drive');
      } on HttpException catch (e) {
        throw SyncNetworkException(e.message);
      } on HandshakeException {
        throw const SyncNetworkException('không thiết lập được kết nối an toàn (TLS)');
      }
    }
  }

  /// Đổi mã trạng thái lỗi của Drive thành lỗi của tầng đồng bộ. Trả về nếu [status] là thành công (2xx).
  void _check(int status, Uint8List body) {
    if (status >= 200 && status < 300) return;
    var reason = '';
    var message = '';
    try {
      final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      final e = j['error'];
      if (e is Map<String, dynamic>) {
        message = '${e['message'] ?? ''}';
        final errors = e['errors'];
        if (errors is List && errors.isNotEmpty && errors.first is Map) reason = '${(errors.first as Map)['reason'] ?? ''}';
      }
    } on Object {
      // thân phản hồi không phải JSON
    }
    if (status == 401) throw const SyncAuthException('Google từ chối phiên đăng nhập. Đăng nhập lại.');
    if (status == 403) {
      if (reason == 'rateLimitExceeded' || reason == 'userRateLimitExceeded' || reason == 'sharingRateLimitExceeded') {
        throw const SyncNetworkException('Google Drive đang giới hạn tốc độ, sẽ thử lại sau');
      }
      if (reason == 'storageQuotaExceeded') throw const SyncNetworkException('Tài khoản Google đã hết dung lượng lưu trữ');
      throw SyncAuthException('Chưa được cấp quyền dùng Google Drive${message.isEmpty ? '' : ' ($message)'}. Đăng nhập lại và cho phép.');
    }
    if (status == 429 || status >= 500) throw SyncNetworkException('Google Drive trả lỗi $status');
    throw SyncNetworkException('Google Drive trả lỗi $status${message.isEmpty ? '' : ': $message'}');
  }

  // ---- Tìm file ----

  /// File kho trong appDataFolder. Nếu có nhiều file trùng tên (hai máy cùng tạo lần đầu), lấy file tạo sớm nhất để mọi
  /// máy cùng chọn một file; các file còn lại bị bỏ qua (máy nào tạo ra nó vẫn còn đủ dữ liệu của mình trên máy).
  Future<({String id, String md5})?> _find() async {
    final (status, body) = await _send('GET', '/drive/v3/files', query: {
      'spaces': 'appDataFolder',
      'q': "name = '${fileName.replaceAll("'", r"\'")}' and trashed = false",
      'fields': 'files(id,md5Checksum,createdTime)',
      'orderBy': 'createdTime',
      'pageSize': '10',
    });
    _check(status, body);
    final files = (jsonDecode(utf8.decode(body)) as Map<String, dynamic>)['files'];
    if (files is! List || files.isEmpty) return null;
    final sorted = [for (final f in files) if (f is Map<String, dynamic> && f['id'] is String) f]
      ..sort((a, b) {
        final c = '${a['createdTime']}'.compareTo('${b['createdTime']}');
        return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
      });
    if (sorted.isEmpty) return null;
    return (id: sorted.first['id'] as String, md5: '${sorted.first['md5Checksum'] ?? ''}');
  }

  @override
  Future<RemoteBlob?> fetch() async {
    final file = await _find();
    if (file == null) return null;
    final (status, body) = await _send('GET', '/drive/v3/files/${file.id}', query: {'alt': 'media'});
    if (status == 404) throw const SyncNetworkException('file trên Google Drive vừa bị xóa, sẽ thử lại');
    _check(status, body);
    // Phiên bản tính từ chính các byte vừa tải, nên luôn khớp với nội dung dù file có đổi giữa hai lệnh gọi.
    return RemoteBlob(body, versionOf(body));
  }

  @override
  Future<String> upload(Uint8List bytes, {String? ifMatch}) async {
    final file = await _find();
    if (file == null) {
      if (ifMatch != null) throw const SyncConflictException(); // file đã biến mất: tải lại rồi tạo mới
      await _create(bytes);
      return versionOf(bytes);
    }
    // Kiểm tra trước khi ghi (Drive không có ghi có điều kiện): lệch phiên bản thì báo xung đột.
    if (ifMatch == null || file.md5 != ifMatch) throw const SyncConflictException();
    final (status, body) = await _send('PATCH', '/upload/drive/v3/files/${file.id}',
        query: {'uploadType': 'media', 'fields': 'id'}, body: bytes);
    if (status == 404) throw const SyncConflictException();
    _check(status, body);
    return versionOf(bytes);
  }

  Future<void> _create(Uint8List bytes) async {
    const boundary = 'vankey-boundary-7f3c1a';
    final meta = jsonEncode({
      'name': fileName,
      'parents': ['appDataFolder'],
    });
    final b = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'))
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final (status, body) = await _send('POST', '/upload/drive/v3/files',
        query: {'uploadType': 'multipart', 'fields': 'id'}, body: b.takeBytes(), contentType: 'multipart/related; boundary=$boundary');
    _check(status, body);
  }

  void close() => _client.close(force: true);
}
