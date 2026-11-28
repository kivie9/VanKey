import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../crypto/kdf.dart';
import '../crypto/passphrase.dart';
import 'sync_provider.dart';

/// Phiên đăng nhập vào máy chủ Cloudflare. Giữ refresh token: lưu ở nơi an toàn (Keystore), không lưu ra file thường.
final class CloudflareSession {
  const CloudflareSession({
    required this.baseUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.deviceId,
    required this.accountId,
    required this.username,
  });

  final String baseUrl;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String deviceId;
  final String accountId;
  final String username;

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'accountId': accountId,
        'username': username,
      };

  factory CloudflareSession.fromJson(Map<String, dynamic> j) => CloudflareSession(
        baseUrl: j['baseUrl'] as String,
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        deviceId: j['deviceId'] as String,
        accountId: j['accountId'] as String,
        username: (j['username'] ?? j['email']) as String, // bản cũ lưu khóa 'email'
      );

  CloudflareSession withTokens(String access, String refresh, DateTime expires) => CloudflareSession(
        baseUrl: baseUrl,
        accessToken: access,
        refreshToken: refresh,
        expiresAt: expires,
        deviceId: deviceId,
        accountId: accountId,
        username: username,
      );
}

final class CloudflareDevice {
  const CloudflareDevice({required this.id, required this.name, required this.lastSeen, required this.current});
  final String id;
  final String name;
  final DateTime lastSeen;
  final bool current;
}

/// Phiên bản Điều khoản đang hiện hành. Phải khớp TERMS_VERSION của máy chủ (server/src/handler.ts).
const cloudflareTermsVersion = '2026-11-27';

/// Lỗi có thông điệp hiển thị được từ máy chủ (sai mật khẩu, tên đăng nhập đã dùng, bị khóa tạm...).
final class CloudflareApiException implements Exception {
  const CloudflareApiException(this.status, this.code, this.message, {this.retryAfter});
  final int status;
  final String code;
  final String message;
  final int? retryAfter;
  @override
  String toString() => 'CloudflareApiException($status $code: $message)';
}

/// Gọi API máy chủ VanKey (xem `server/`).
final class CloudflareApi {
  /// Chờ kết nối tối đa chừng này.
  static const connectTimeout = Duration(seconds: 15);

  /// Chờ một phản hồi tối đa chừng này.
  static const responseTimeout = Duration(seconds: 30);

  /// Phiên đăng nhập hết hạn sau chừng này nếu máy chủ không nói rõ (giây).
  static const defaultSessionSeconds = 900;

  /// Làm mới phiên khi còn ít hơn chừng này.
  static const refreshMargin = Duration(seconds: 30);

  CloudflareApi({HttpClient? client}) : _client = client ?? HttpClient()
    ..connectionTimeout = connectTimeout;

  final HttpClient _client;

  /// Khóa đăng nhập dẫn xuất từ mật khẩu. Máy chủ chỉ thấy khóa này, không thấy mật khẩu; khóa mở kho dẫn xuất riêng
  /// (salt khác, ngẫu nhiên trong file kho) nên máy chủ không dùng khóa này mở được kho. Tham số cố định vì mọi thiết bị
  /// phải ra cùng một khóa.
  ///
  /// Mật khẩu được chuẩn hóa NFKC như mật khẩu kho (`normalizePassphrase`), nên mật khẩu tiếng Việt gõ bằng bàn phím
  /// dựng sẵn hay tổ hợp đều ra cùng một khóa.
  static Future<String> deriveAuthKey(String username, String password, {Argon2Params params = Argon2Params.standard}) =>
      _derive(username, normalizePassphrase(password), params);

  /// Khóa theo cách cũ (chưa chuẩn hóa), chỉ để đăng nhập tài khoản tạo trước khi có chuẩn hóa rồi chuyển sang khóa mới.
  static Future<String> deriveLegacyAuthKey(String username, String password, {Argon2Params params = Argon2Params.standard}) =>
      _derive(username, Uint8List.fromList(utf8.encode(password)), params);

  /// Mật khẩu này có thể đã được đăng ký bằng khóa cũ khác khóa mới (chuẩn hóa làm đổi byte).
  static bool hasLegacyAuthKey(String password) => !_bytesEqual(normalizePassphrase(password), utf8.encode(password));

  static Future<String> _derive(String username, Uint8List passwordBytes, Argon2Params params) async {
    final salt = Uint8List.fromList(sha256.convert(utf8.encode('vankey-auth-v1|${username.trim().toLowerCase()}')).bytes.sublist(0, Kdf.saltLength));
    final key = await const Kdf().argon2id(passphraseBytes: passwordBytes, salt: salt, params: params);
    return base64.encode(key);
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Uri _uri(String baseUrl, String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<(int, Uint8List, HttpHeaders)> send(
    String method,
    String baseUrl,
    String path, {
    Map<String, Object?>? json,
    Uint8List? bytes,
    String? token,
    Map<String, String> headers = const {},
  }) async {
    try {
      final req = await _client.openUrl(method, _uri(baseUrl, path));
      if (token != null) req.headers.set('authorization', 'Bearer $token');
      headers.forEach(req.headers.set);
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(json)));
      } else if (bytes != null) {
        req.headers.contentType = ContentType.binary;
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(responseTimeout);
      final body = await res.fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d));
      return (res.statusCode, body.takeBytes(), res.headers);
    } on SocketException catch (e) {
      throw SyncNetworkException(e.message);
    } on TimeoutException {
      throw const SyncNetworkException('hết thời gian chờ');
    } on HttpException catch (e) {
      throw SyncNetworkException(e.message);
    } on HandshakeException {
      throw const SyncNetworkException('không thiết lập được kết nối an toàn (TLS)');
    }
  }

  CloudflareApiException _apiError(int status, Uint8List body) {
    try {
      final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      return CloudflareApiException(status, '${j['error'] ?? 'error'}', '${j['message'] ?? 'Lỗi máy chủ'}', retryAfter: j['retryAfter'] as int?);
    } on Object {
      return CloudflareApiException(status, 'error', 'Máy chủ trả về lỗi $status');
    }
  }

  CloudflareSession _sessionFrom(String baseUrl, Uint8List body, {DateTime? now}) {
    final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    return CloudflareSession(
      baseUrl: baseUrl,
      accessToken: j['accessToken'] as String,
      refreshToken: j['refreshToken'] as String,
      expiresAt: (now ?? DateTime.now()).add(Duration(seconds: (j['expiresIn'] as int?) ?? CloudflareApi.defaultSessionSeconds)),
      deviceId: j['deviceId'] as String,
      accountId: j['accountId'] as String,
      username: (j['username'] as String?) ?? '',
    );
  }

  Future<CloudflareSession> _auth(String baseUrl, String path, Map<String, Object?> body) async {
    final (status, resBody, _) = await send('POST', baseUrl, path, json: body);
    if (status != 200) throw _apiError(status, resBody);
    return _sessionFrom(baseUrl, resBody);
  }

  /// [registerCode]: mã mời, chỉ cần khi chủ máy chủ có đặt secret `REGISTER_CODE`.
  Future<CloudflareSession> register(String baseUrl, String username, String authKey, String deviceName, {String registerCode = '', String termsVersion = cloudflareTermsVersion}) =>
      _auth(baseUrl, '/auth/register', {'username': username, 'authKey': authKey, 'deviceName': deviceName, 'registerCode': registerCode, 'termsVersion': termsVersion});

  Future<CloudflareSession> login(String baseUrl, String username, String authKey, String deviceName) =>
      _auth(baseUrl, '/auth/login', {'username': username, 'authKey': authKey, 'deviceName': deviceName});

  /// Xoay vòng refresh token. Máy chủ trả 401 nếu thiết bị đã bị gỡ hoặc token hết hạn.
  Future<CloudflareSession> refresh(CloudflareSession s) async {
    final (status, body, _) = await send('POST', s.baseUrl, '/auth/refresh', json: {'refreshToken': s.refreshToken});
    if (status == 401 || status == 403) throw SyncAuthException(_apiError(status, body).message);
    if (status != 200) throw _apiError(status, body);
    final n = _sessionFrom(s.baseUrl, body);
    return s.withTokens(n.accessToken, n.refreshToken, n.expiresAt);
  }

  Future<void> logout(CloudflareSession s) async {
    await send('POST', s.baseUrl, '/auth/logout', token: s.accessToken);
  }

  Future<List<CloudflareDevice>> devices(CloudflareSession s) async {
    final (status, body, _) = await send('GET', s.baseUrl, '/devices', token: s.accessToken);
    if (status == 401 || status == 403) throw SyncAuthException(_apiError(status, body).message);
    if (status != 200) throw _apiError(status, body);
    final list = (jsonDecode(utf8.decode(body)) as Map<String, dynamic>)['devices'] as List;
    return [
      for (final d in list)
        CloudflareDevice(
          id: (d as Map)['id'] as String,
          name: d['name'] as String,
          lastSeen: DateTime.fromMillisecondsSinceEpoch(((d['lastSeen'] as num).toInt()) * 1000),
          current: d['current'] == true,
        ),
    ];
  }

  Future<void> revokeDevice(CloudflareSession s, String id) async {
    final (status, body, _) = await send('DELETE', s.baseUrl, '/devices/${Uri.encodeComponent(id)}', token: s.accessToken);
    if (status == 204) return;
    if (status == 401 || status == 403) throw SyncAuthException(_apiError(status, body).message);
    throw _apiError(status, body);
  }

  void close() => _client.close(force: true);
}

/// Đồng bộ qua máy chủ Cloudflare. Tự làm mới access token khi hết hạn; báo [SyncAuthException] khi phải đăng nhập lại.
final class CloudflareSync implements SyncProvider {
  CloudflareSync(this.api, CloudflareSession session, {this.onSession}) : _session = session;

  final CloudflareApi api;
  CloudflareSession _session;

  /// Gọi mỗi khi token đổi (để lưu lại refresh token mới). Được chờ xong trước khi dùng token mới, để app bị tắt
  /// ngay sau đó cũng không còn giữ refresh token đã bị thay.
  final FutureOr<void> Function(CloudflareSession)? onSession;

  /// Lần làm mới đang chạy, nếu có. Mọi lời gọi cùng lúc dùng chung một lần: không gửi cùng một refresh token hai lần.
  Future<void>? _refreshing;

  CloudflareSession get session => _session;

  @override
  String get name => 'cloudflare';

  Future<void> _ensureFresh() async {
    final running = _refreshing;
    if (running != null) return running;
    if (_session.expiresAt.difference(DateTime.now()) > CloudflareApi.refreshMargin) return;
    await _refresh();
  }

  Future<void> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<void> _doRefresh() async {
    final next = await api.refresh(_session);
    _session = next;
    await onSession?.call(next);
  }

  Future<(int, Uint8List, HttpHeaders)> _authed(Future<(int, Uint8List, HttpHeaders)> Function(String token) call) async {
    await _ensureFresh();
    var r = await call(_session.accessToken);
    if (r.$1 == 401) {
      await _refresh(); // token bị từ chối dù chưa hết hạn theo đồng hồ máy: thử làm mới một lần
      r = await call(_session.accessToken);
    }
    if (r.$1 == 401 || r.$1 == 403) throw const SyncAuthException('Phiên đăng nhập không còn hiệu lực. Đăng nhập lại.');
    return r;
  }

  /// Gọi một thao tác tài khoản cần nhập lại mật khẩu. 403 ở đây là "mật khẩu hiện tại sai", không phải mất phiên.
  Future<void> _account(String method, String path, Map<String, Object?> json) async {
    await _ensureFresh();
    var r = await api.send(method, _session.baseUrl, path, token: _session.accessToken, json: json);
    if (r.$1 == 401) {
      await _refresh();
      r = await api.send(method, _session.baseUrl, path, token: _session.accessToken, json: json);
    }
    if (r.$1 == 204) return;
    if (r.$1 == 401) throw const SyncAuthException('Phiên đăng nhập không còn hiệu lực. Đăng nhập lại.');
    throw api._apiError(r.$1, r.$2);
  }

  /// Danh sách thiết bị của tài khoản (tự làm mới phiên nếu access token đã hết hạn).
  Future<List<CloudflareDevice>> devices() async {
    await _ensureFresh();
    try {
      return await api.devices(_session);
    } on SyncAuthException {
      await _refresh(); // token bị từ chối dù chưa hết hạn theo đồng hồ máy: thử làm mới một lần
      return api.devices(_session);
    }
  }

  /// Gỡ một thiết bị của tài khoản (tự làm mới phiên nếu cần).
  Future<void> revokeDevice(String id) async {
    await _ensureFresh();
    try {
      await api.revokeDevice(_session, id);
    } on SyncAuthException {
      await _refresh();
      await api.revokeDevice(_session, id);
    }
  }

  /// Đăng xuất thiết bị này trên máy chủ (gỡ thiết bị). Tự làm mới phiên trước, để access token hết hạn
  /// không làm lần đăng xuất âm thầm thất bại mà thiết bị vẫn còn quyền trên máy chủ.
  Future<void> logout() async {
    await _authed((t) => api.send('POST', _session.baseUrl, '/auth/logout', token: t));
  }

  /// Đổi khóa đăng nhập trên máy chủ (sau khi đổi mật khẩu). Máy chủ gỡ các thiết bị khác của tài khoản.
  Future<void> changeAuthKey(String currentAuthKey, String newAuthKey) =>
      _account('POST', '/auth/password', {'authKey': currentAuthKey, 'newAuthKey': newAuthKey});

  /// Xóa hẳn tài khoản, kho trên máy chủ và mọi thiết bị. Không hoàn tác được.
  Future<void> deleteAccount(String authKey) => _account('DELETE', '/account', {'authKey': authKey});

  @override
  Future<RemoteBlob?> fetch() async {
    final (status, body, headers) = await _authed((t) => api.send('GET', _session.baseUrl, '/vault', token: t));
    if (status == 404) return null;
    if (status != 200) throw SyncNetworkException('máy chủ trả về $status');
    return RemoteBlob(body, headers.value('etag') ?? '');
  }

  @override
  Future<String> upload(Uint8List bytes, {String? ifMatch}) async {
    final cond = ifMatch == null ? {'if-none-match': '*'} : {'if-match': ifMatch};
    final (status, body, headers) = await _authed((t) => api.send('PUT', _session.baseUrl, '/vault', token: t, bytes: bytes, headers: cond));
    if (status == 200) return headers.value('etag') ?? '';
    if (status == 409) throw const SyncConflictException();
    if (status == 413) throw const SyncNetworkException('kho quá lớn so với giới hạn của máy chủ');
    if (status >= 500) throw SyncNetworkException('máy chủ lỗi ($status)');
    throw SyncNetworkException('máy chủ từ chối ($status): ${utf8.decode(body, allowMalformed: true)}');
  }
}
