import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Kiểm tra mật khẩu bị rò rỉ qua HaveIBeenPwned theo **k-anonymity**:
/// chỉ gửi 5 ký tự đầu của mã băm SHA-1, **không bao giờ** gửi mật khẩu hay toàn bộ mã băm.
abstract final class Hibp {
  /// Tách mã băm SHA-1 (chữ hoa) thành tiền tố 5 ký tự (gửi đi) và phần còn lại (giữ lại trên máy).
  static ({String prefix, String suffix}) split(String password) {
    final hex = sha1.convert(utf8.encode(password)).toString().toUpperCase();
    return (prefix: hex.substring(0, 5), suffix: hex.substring(5));
  }

  /// Đọc phản hồi của API `range/{prefix}` (mỗi dòng `HẬU_TỐ:SỐ_LẦN`) và trả số lần mật khẩu xuất hiện (0 nếu không thấy).
  /// Bỏ qua các dòng đệm có số lần bằng 0 (chế độ `Add-Padding`).
  static int countFromResponse(String body, String suffix) {
    final want = suffix.toUpperCase();
    for (final line in const LineSplitter().convert(body)) {
      final i = line.indexOf(':');
      if (i < 0) continue;
      if (line.substring(0, i).trim().toUpperCase() == want) {
        return int.tryParse(line.substring(i + 1).trim()) ?? 0;
      }
    }
    return 0;
  }

  /// Tra một mật khẩu. [fetchRange] do tầng mạng cung cấp: nhận tiền tố 5 ký tự, trả nội dung phản hồi.
  static Future<int> check(String password, Future<String> Function(String prefix) fetchRange) async {
    final s = split(password);
    return countFromResponse(await fetchRange(s.prefix), s.suffix);
  }
}
