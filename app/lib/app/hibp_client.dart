import 'dart:convert';
import 'dart:io';

/// Gọi `api.pwnedpasswords.com/range/{5 ký tự}`. Chỉ tiền tố 5 ký tự của mã băm SHA-1 rời khỏi máy.
Future<String> fetchHibpRange(String prefix) async {
  if (!RegExp(r'^[0-9A-F]{5}$').hasMatch(prefix)) throw ArgumentError('tiền tố không hợp lệ');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.https('api.pwnedpasswords.com', '/range/$prefix'));
    req.headers
      ..set('Add-Padding', 'true')
      ..set(HttpHeaders.userAgentHeader, 'VanKey');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}
