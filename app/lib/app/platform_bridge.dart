import 'dart:io';

import 'package:flutter/services.dart';

/// Cầu nối nhỏ tới Android (xem MainActivity.kt). Trên nền tảng khác thì không làm gì.
abstract final class PlatformBridge {
  static const _ch = MethodChannel('vankey/platform');

  /// Chặn chụp màn hình và che nội dung trong danh sách ứng dụng gần đây.
  static Future<void> setSecure({required bool on}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<void>('setSecure', {'on': on});
    } on Object {
      // Không áp dụng được cũng không làm hỏng app.
    }
  }

  /// Chép vào clipboard kèm cờ "nhạy cảm". Trả về `false` nếu không làm được (khi đó dùng cách thường).
  static Future<bool> copySensitive(String text) async {
    if (!Platform.isAndroid) return false;
    try {
      await _ch.invokeMethod<void>('copySensitive', {'text': text});
      return true;
    } on Object {
      return false;
    }
  }
}
