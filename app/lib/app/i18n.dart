import 'i18n_en.dart';

/// Ngôn ngữ đang dùng ('vi' hoặc 'en'). Đổi qua [Lang.set]; MaterialApp được dựng lại khi đổi.
abstract final class Lang {
  static String current = 'vi';

  static void set(String code) => current = code == 'en' ? 'en' : 'vi';

  /// 'system' → theo ngôn ngữ của điện thoại, mặc định tiếng Việt nếu không phải tiếng Anh.
  static String resolve(String setting, String systemLanguageCode) =>
      setting == 'en' || setting == 'vi' ? setting : (systemLanguageCode == 'en' ? 'en' : 'vi');
}

/// Dịch một chuỗi gốc tiếng Việt. Không có bản dịch thì giữ nguyên (không bao giờ làm app vỡ).
/// Chỗ cần chèn giá trị: `tr('Đã nhập {n} mục', {'n': 3})`.
String tr(String vi, [Map<String, Object>? args]) {
  var out = Lang.current == 'en' ? (enStrings[vi] ?? vi) : vi;
  if (args != null) {
    for (final e in args.entries) {
      out = out.replaceAll('{${e.key}}', '${e.value}');
    }
  }
  return out;
}
