import 'dart:convert';
import 'dart:io';

/// Phiên bản của bản build này. CI truyền vào bằng `--dart-define=APP_VERSION=1.2.3` (lấy từ tag);
/// build trên máy không truyền thì là `dev` và không kiểm tra bản mới.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

const releasesRepo = 'kivie9/VanKey';
final releasesPage = Uri.https('github.com', '/$releasesRepo/releases/latest');

class ReleaseInfo {
  const ReleaseInfo(this.version, this.page);
  final String version;
  final Uri page;
}

/// Tách `v1.2.3` / `1.2.3` thành [1, 2, 3]. Không đúng dạng thì `null`.
List<int>? parseVersion(String s) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(s.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// `true` khi [latest] mới hơn [current]. Một trong hai không đúng dạng thì `false`.
bool isNewerVersion(String latest, String current) {
  final a = parseVersion(latest), b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Hỏi GitHub bản phát hành mới nhất. Chỉ gửi một yêu cầu GET tới api.github.com, không kèm gì về kho.
/// Chỉ chạy khi người dùng bấm "Kiểm tra bản mới".
Future<ReleaseInfo> fetchLatestRelease({HttpClient? client}) async {
  final c = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 10));
  try {
    final req = await c.getUrl(Uri.https('api.github.com', '/repos/$releasesRepo/releases/latest'));
    req.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'VanKey');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final j = jsonDecode(body) as Map<String, dynamic>;
    final tag = j['tag_name'] as String? ?? '';
    final url = Uri.tryParse(j['html_url'] as String? ?? '');
    return ReleaseInfo(tag.replaceFirst(RegExp('^v'), ''), url != null && url.host == 'github.com' ? url : releasesPage);
  } finally {
    if (client == null) c.close(force: true);
  }
}
