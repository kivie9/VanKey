import 'package:url_launcher/url_launcher.dart';

import 'i18n.dart';

/// Các trang pháp lý công khai (Điều khoản, Quyền riêng tư, Xóa tài khoản, Bảo mật).
///
/// Địa chỉ trang đặt lúc build: `--dart-define=SITE_URL=https://vankey.onigix.com`.
/// Không đặt thì các link ẩn đi và app vẫn chạy bình thường.
abstract final class Legal {
  static const siteUrl = String.fromEnvironment('SITE_URL');

  /// Đường dẫn trang theo ngôn ngữ đang dùng. Khớp với site/src/pages.
  static const _paths = {
    'terms': ['/dieu-khoan/', '/en/terms/'],
    'privacy': ['/quyen-rieng-tu/', '/en/privacy/'],
    'delete': ['/xoa-tai-khoan/', '/en/delete-account/'],
    'security': ['/bao-mat/', '/en/security/'],
  };

  /// Link tới trang [key] (terms, privacy, delete, security), hoặc null nếu chưa đặt SITE_URL.
  static Uri? page(String key) {
    if (siteUrl.isEmpty) return null;
    final pair = _paths[key];
    if (pair == null) return null;
    final path = Lang.current == 'en' ? pair[1] : pair[0];
    return Uri.parse(siteUrl.replaceAll(RegExp(r'/+$'), '') + path);
  }

  static Future<void> open(String key) async {
    final uri = page(key);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
