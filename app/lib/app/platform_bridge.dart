import 'dart:io';

import 'package:flutter/services.dart';

/// Lỗi vân tay từ phía Android. [code]: `canceled` (người dùng hủy), `invalidated` (vân tay trên máy đã đổi, khóa
/// mất hiệu lực), `unavailable`, `failed`, `corrupt`.
final class BioException implements Exception {
  const BioException(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => 'BioException($code: $message)';
}

/// Cầu nối nhỏ tới Android (MainActivity.kt) và Windows (windows/runner/flutter_window.cpp). Nền tảng khác thì không làm gì.
abstract final class PlatformBridge {
  static const _ch = MethodChannel('vankey/platform');

  /// Có khóa sinh trắc gắn với phần cứng: Android Keystore (BiometricVault.kt) hoặc Windows Hello (hello_vault.cpp).
  static bool get bioBound => Platform.isAndroid || Platform.isWindows;

  /// Chặn chụp màn hình và che nội dung trong danh sách ứng dụng gần đây.
  static Future<void> setSecure({required bool on}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<void>('setSecure', {'on': on});
    } on Object {
      // Không áp dụng được cũng không làm hỏng app.
    }
  }

  // ---- Vân tay gắn khóa Keystore (BiometricVault.kt) / Windows Hello (hello_vault.cpp) ----

  /// Máy có sinh trắc mạnh đã đăng ký và dùng được cho khóa Keystore.
  static Future<bool> bioAvailable() async {
    if (!bioBound) return false;
    try {
      return await _ch.invokeMethod<bool>('bioAvailable') ?? false;
    } on Object {
      return false;
    }
  }

  /// Tạo khóa Keystore mới, hỏi vân tay rồi mã hóa [data]. Ném [BioException] nếu không làm được.
  static Future<Uint8List> bioEncrypt(Uint8List data, {required String title, required String cancel}) =>
      _bioCall('bioEncrypt', data, title, cancel);

  /// Hỏi vân tay rồi giải mã dữ liệu do [bioEncrypt] tạo. Ném [BioException] nếu không làm được.
  static Future<Uint8List> bioDecrypt(Uint8List data, {required String title, required String cancel}) =>
      _bioCall('bioDecrypt', data, title, cancel);

  /// Xóa khóa Keystore của vân tay (dữ liệu đã mã hóa bằng nó không mở được nữa).
  static Future<void> bioDelete() async {
    if (!bioBound) return;
    try {
      await _ch.invokeMethod<void>('bioDelete');
    } on Object {
      // bỏ qua
    }
  }

  static Future<Uint8List> _bioCall(String method, Uint8List data, String title, String cancel) async {
    if (!bioBound) throw const BioException('unavailable');
    try {
      final out = await _ch.invokeMethod<Uint8List>(method, {'data': data, 'title': title, 'cancel': cancel});
      if (out == null) throw const BioException('failed');
      return out;
    } on PlatformException catch (e) {
      throw BioException(e.code, e.message);
    } on MissingPluginException {
      throw const BioException('unavailable');
    }
  }

  /// Chép vào clipboard kèm cờ "nhạy cảm". Trả về `false` nếu không làm được (khi đó dùng cách thường).
  /// Android: ẩn nội dung ở thông báo "đã chép". Windows (flutter_window.cpp): không vào lịch sử clipboard (Win+V)
  /// và không đồng bộ lên clipboard đám mây.
  static Future<bool> copySensitive(String text) async {
    if (!Platform.isAndroid && !Platform.isWindows) return false;
    try {
      await _ch.invokeMethod<void>('copySensitive', {'text': text});
      return true;
    } on Object {
      return false;
    }
  }
}
