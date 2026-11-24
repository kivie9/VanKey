import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../crypto/kdf.dart';
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
    required this.email,
  });

  final String baseUrl;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String deviceId;
  final String accountId;
  final String email;

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'accountId': accountId,
        'email': email,
      };

  factory CloudflareSession.fromJson(Map<String, dynamic> j) => CloudflareSession(
        baseUrl: j['baseUrl'] as String,
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        deviceId: j['deviceId'] as String,
        accountId: j['accountId'] as String,
        email: j['email'] as String,
      );

  CloudflareSession withTokens(String access, String refresh, DateTime expires) => CloudflareSession(
        baseUrl: baseUrl,
        accessToken: access,
        refreshToken: refresh,
        expiresAt: expires,
        deviceId: deviceId,
        accountId: accountId,
        email: email,
      );
}

final class CloudflareDevice {
  const CloudflareDevice({required this.id, required this.name, required this.lastSeen, required this.current});
  final String id;
  final String name;
  final DateTime lastSeen;
  final bool current;
}

/// Lỗi có thông điệp hiển thị được từ máy chủ (sai mật khẩu, email không được phép, bị khóa tạm...).
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
  CloudflareApi({HttpClient? client}) : _client = client ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  final HttpClient _client;

  /// Khóa đăng nhập dẫn xuất từ mật khẩu TÀI KHOẢN (khác passphrase của kho). Máy chủ chỉ thấy khóa này,
  /// không thấy mật khẩu. Tham số cố định vì mọi thiết bị phải ra cùng một khóa.
  static Future<String> deriveAuthKey(String email, String password, {Argon2Params params = Argon2Params.standard}) async {
    final salt = Uint8List.fromList(sha256.convert(utf8.encode('vankey-auth-v1|${email.trim().toLowerCase()}')).bytes.sublist(0, Kdf.saltLength));
    final key = await const Kdf().argon2id(passphraseBytes: Uint8List.fromList(utf8.encode(password)), salt: salt, params: params);
    return base64.encode(key);
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
      final res = await req.close().timeout(const Duration(seconds: 30));
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
      expiresAt: (now ?? DateTime.now()).add(Duration(seconds: (j['expiresIn'] as int?) ?? 900)),
      deviceId: j['deviceId'] as String,
      accountId: j['accountId'] as String,
      email: (j['email'] as String?) ?? '',
    );
  }

  Future<CloudflareSession> _auth(String baseUrl, String path, Map<String, Object?> body) async {
    final (status, resBody, _) = await send('POST', baseUrl, path, json: body);
    if (status != 200) throw _apiError(status, resBody);
    return _sessionFrom(baseUrl, resBody);
  }

  Future<CloudflareSession> register(String baseUrl, String email, String authKey, String deviceName) =>
      _auth(baseUrl, '/auth/register', {'email': email, 'authKey': authKey, 'deviceName': deviceName});

  Future<CloudflareSession> login(String baseUrl, String email, String authKey, String deviceName) =>
      _auth(baseUrl, '/auth/login', {'email': email, 'authKey': authKey, 'deviceName': deviceName});

  Future<CloudflareSession> google(String baseUrl, String idToken, String deviceName) =>
      _auth(baseUrl, '/auth/google', {'idToken': idToken, 'deviceName': deviceName});

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

  /// Gọi mỗi khi token đổi (để lưu lại refresh token mới).
  final void Function(CloudflareSession)? onSession;

  CloudflareSession get session => _session;

  @override
  String get name => 'cloudflare';

  Future<void> _ensureFresh() async {
    if (_session.expiresAt.difference(DateTime.now()) > const Duration(seconds: 30)) return;
    await _refresh();
  }

  Future<void> _refresh() async {
    _session = await api.refresh(_session);
    onSession?.call(_session);
  }

  Future<(int, Uint8List, HttpHeaders)> _authed(Future<(int, Uint8List, HttpHeaders)> Function(String token) call) async {
    await _ensureFresh();
    var r = await call(_session.accessToken);
    if (r.$1 == 401) {
      await _refresh(); // token bị từ chối dù chưa hết hạn theo đồng hồ máy: thử làm mới một lần
      r = await call(_session.accessToken);
    }
    if (r.$1 == 401 || r.$1 == 403) throw const SyncAuthException('Phiên đăng nhập không còn hiệu lực. Hãy đăng nhập lại.');
    return r;
  }

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
