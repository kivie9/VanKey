import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import '../core/sync/drive_sync.dart';
import '../core/sync/sync_provider.dart';
import 'i18n.dart';

/// Cấu hình đăng nhập Google, đưa vào lúc build (không ghi cứng trong code):
/// `flutter build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=<Web client ID>.apps.googleusercontent.com`
/// Hướng dẫn tạo project và OAuth client: docs/operations/google-drive-setup.md.
abstract final class GoogleConfig {
  static const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Đồng bộ Google Drive hiện chỉ có trên Android.
  static bool get supported => Platform.isAndroid;

  /// Bản build này đã được cấu hình để đăng nhập Google.
  static bool get configured => supported && serverClientId.isNotEmpty;
}

/// Tài khoản Drive đã đăng nhập: cấp token, đăng nhập tương tác, đăng xuất. Tách thành giao diện để test thay được.
abstract interface class DriveAccountAuth implements AccessTokenSource {
  /// Email tài khoản (để hiển thị); có sau khi đăng nhập hoặc khôi phục phiên.
  String? get email;

  /// Đăng nhập tương tác và xin quyền. Trả về lỗi hiển thị được, hoặc null nếu thành công.
  Future<String?> signIn();

  Future<void> signOut();
}

/// Lấy access token Drive từ tài khoản Google đã đăng nhập trên máy (qua `google_sign_in`).
/// Chỉ xin quyền `drive.appdata`: thư mục ẩn của riêng app, không đụng tới file khác trong Drive.
final class GoogleDriveAuth implements DriveAccountAuth {
  static Future<void>? _initialized;

  static Future<void> _ensureInit() => _initialized ??= GoogleSignIn.instance.initialize(serverClientId: GoogleConfig.serverClientId);

  GoogleSignInAccount? _account;
  String? _lastToken;

  /// Email tài khoản Google đang dùng (để hiển thị).
  @override
  String? email;

  @override
  Future<String?> signIn() async {
    if (!GoogleConfig.configured) return tr('Bản này chưa được cấu hình đăng nhập Google (thiếu GOOGLE_SERVER_CLIENT_ID khi build). Xem docs/operations/google-drive-setup.md.');
    try {
      await _ensureInit();
      final account = await GoogleSignIn.instance.authenticate(scopeHint: [DriveSync.scope]);
      final authz = await account.authorizationClient.authorizeScopes([DriveSync.scope]);
      _lastToken = authz.accessToken;
      _account = account;
      email = account.email;
      return null;
    } on GoogleSignInException catch (e) {
      return switch (e.code) {
        GoogleSignInExceptionCode.canceled => tr('Đã hủy đăng nhập Google, hoặc cấu hình đăng nhập chưa đúng (kiểm tra SHA-1 và tên gói trong Google Cloud).'),
        GoogleSignInExceptionCode.clientConfigurationError => tr('Cấu hình đăng nhập Google chưa đúng. Xem docs/operations/google-drive-setup.md.'),
        GoogleSignInExceptionCode.uiUnavailable => tr('Không mở được màn đăng nhập Google. Hãy thử lại khi app đang ở phía trước.'),
        _ => tr('Không đăng nhập được Google: {p0}', {'p0': e.description ?? e.code.name}),
      };
    } on Object catch (e) {
      return tr('Không đăng nhập được Google: {p0}', {'p0': e});
    }
  }

  /// Khôi phục phiên đã đăng nhập từ lần trước (không hiện giao diện). `false` nếu không còn phiên.
  Future<bool> restore() async {
    if (!GoogleConfig.configured) return false;
    try {
      await _ensureInit();
      final pending = GoogleSignIn.instance.attemptLightweightAuthentication();
      final account = pending == null ? null : await pending;
      if (account == null) return false;
      _account = account;
      email = account.email;
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<String> token({bool forceRefresh = false}) async {
    if (_account == null && !await restore()) throw SyncAuthException(tr('Cần đăng nhập lại Google.'));
    final client = _account!.authorizationClient;
    final stale = _lastToken;
    if (forceRefresh && stale != null) {
      try {
        await client.clearAuthorizationToken(accessToken: stale);
      } on Object {
        // Không xóa được bộ nhớ đệm thì vẫn thử xin token mới.
      }
    }
    try {
      // Ở nền không được hiện giao diện: chỉ lấy token khi quyền đã cấp từ trước.
      final authz = await client.authorizationForScopes([DriveSync.scope]);
      if (authz == null) throw SyncAuthException(tr('Cần cấp lại quyền Google Drive. Hãy bật lại đồng bộ trong Cài đặt.'));
      _lastToken = authz.accessToken;
      return authz.accessToken;
    } on GoogleSignInException catch (e) {
      throw SyncAuthException(tr('Cần đăng nhập lại Google: {p0}', {'p0': e.description ?? e.code.name}));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _ensureInit();
      await GoogleSignIn.instance.signOut();
    } on Object {
      // bỏ qua: đăng xuất cục bộ vẫn tiếp tục
    }
  }
}
