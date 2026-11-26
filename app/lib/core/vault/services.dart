/// Nhận diện "tài khoản này thuộc dịch vụ nào" để gom nhiều tài khoản Facebook, Google... lại một chỗ.
///
/// Không lưu thêm gì vào kho: dịch vụ được **tính** từ địa chỉ web của mục, không có địa chỉ thì từ tên.
/// Chỉ dùng để gom nhóm và gợi ý trên giao diện, **không** dùng để quyết định điền mật khẩu vào đâu.
library;

import 'models.dart';
import 'search.dart';

final class KnownService {
  const KnownService(this.id, this.name, this.domains, [this.aliases = const []]);

  final String id;
  final String name;

  /// Tên miền của dịch vụ. Tên đầu tiên dùng để điền vào ô địa chỉ khi người dùng chọn dịch vụ.
  /// Tên miền con cụ thể (aws.amazon.com) được ưu tiên hơn tên miền mẹ (amazon.com).
  final List<String> domains;

  /// Tên gọi khác, đã bỏ dấu và viết thường. Chỉ dùng cho gợi ý và ô tìm dịch vụ.
  final List<String> aliases;
}

const knownServices = <KnownService>[
  KnownService('adobe', 'Adobe', ['adobe.com']),
  KnownService('amazon', 'Amazon', ['amazon.com', 'amazon.co.jp', 'amazon.co.uk']),
  KnownService('anthropic', 'Claude', ['claude.ai', 'anthropic.com'], ['anthropic']),
  KnownService('apple', 'Apple', ['apple.com', 'icloud.com'], ['icloud']),
  KnownService('aws', 'AWS', ['aws.amazon.com', 'signin.aws'], ['amazon web services']),
  KnownService('binance', 'Binance', ['binance.com']),
  KnownService('cloudflare', 'Cloudflare', ['cloudflare.com']),
  KnownService('digitalocean', 'DigitalOcean', ['digitalocean.com']),
  KnownService('discord', 'Discord', ['discord.com', 'discordapp.com']),
  KnownService('docker', 'Docker', ['docker.com']),
  KnownService('dropbox', 'Dropbox', ['dropbox.com']),
  KnownService('epicgames', 'Epic Games', ['epicgames.com']),
  KnownService('facebook', 'Facebook', ['facebook.com', 'fb.com', 'messenger.com'], ['fb']),
  KnownService('figma', 'Figma', ['figma.com']),
  KnownService('github', 'GitHub', ['github.com']),
  KnownService('gitlab', 'GitLab', ['gitlab.com']),
  KnownService('google', 'Google', ['google.com', 'gmail.com', 'youtube.com', 'google.com.vn'], ['gmail']),
  KnownService('instagram', 'Instagram', ['instagram.com']),
  KnownService('lazada', 'Lazada', ['lazada.vn', 'lazada.com']),
  KnownService('linkedin', 'LinkedIn', ['linkedin.com']),
  KnownService('mbbank', 'MB Bank', ['mbbank.com.vn'], ['mbbank']),
  KnownService('microsoft', 'Microsoft', ['microsoft.com', 'live.com', 'outlook.com', 'office.com', 'microsoftonline.com'], ['outlook', 'hotmail']),
  KnownService('momo', 'MoMo', ['momo.vn']),
  KnownService('netflix', 'Netflix', ['netflix.com']),
  KnownService('notion', 'Notion', ['notion.so', 'notion.com']),
  KnownService('okx', 'OKX', ['okx.com']),
  KnownService('openai', 'OpenAI', ['openai.com', 'chatgpt.com'], ['chatgpt']),
  KnownService('paypal', 'PayPal', ['paypal.com']),
  KnownService('pinterest', 'Pinterest', ['pinterest.com']),
  KnownService('reddit', 'Reddit', ['reddit.com']),
  KnownService('riot', 'Riot Games', ['riotgames.com']),
  KnownService('shopee', 'Shopee', ['shopee.vn', 'shopee.com']),
  KnownService('slack', 'Slack', ['slack.com']),
  KnownService('spotify', 'Spotify', ['spotify.com']),
  KnownService('steam', 'Steam', ['steampowered.com', 'steamcommunity.com']),
  KnownService('techcombank', 'Techcombank', ['techcombank.com.vn']),
  KnownService('telegram', 'Telegram', ['telegram.org', 't.me']),
  KnownService('tiki', 'Tiki', ['tiki.vn']),
  KnownService('tiktok', 'TikTok', ['tiktok.com']),
  KnownService('twitch', 'Twitch', ['twitch.tv']),
  KnownService('vercel', 'Vercel', ['vercel.com']),
  KnownService('vietcombank', 'Vietcombank', ['vietcombank.com.vn']),
  KnownService('x', 'X (Twitter)', ['x.com', 'twitter.com'], ['twitter']),
  KnownService('yahoo', 'Yahoo', ['yahoo.com']),
  KnownService('zalo', 'Zalo', ['zalo.me']),
  KnownService('zoom', 'Zoom', ['zoom.us', 'zoom.com']),
];

/// Dịch vụ của một mục.
final class ServiceRef {
  const ServiceRef(this.key, this.name, {this.domain});

  /// Khóa gom nhóm: `s:<id>` (dịch vụ biết sẵn), `d:<tên miền>` (trang khác), `t:<tên>` (không có địa chỉ).
  final String key;
  final String name;

  /// Địa chỉ để điền khi người dùng chọn dịch vụ này; `null` nếu dịch vụ không có trang web.
  final String? domain;
}

/// So tên không phân biệt hoa thường, dấu tiếng Việt và khoảng trắng thừa.
String normalizeName(String s) => foldVietnamese(s).trim().replaceAll(RegExp(r'\s+'), ' ');

/// Tên máy chủ của địa chỉ web. `null` nếu không phải địa chỉ web (chữ thường, link ứng dụng Android...).
String? hostOf(String url) {
  var t = url.trim();
  if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
  final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(t)?.group(1)?.toLowerCase();
  if (scheme == null) {
    t = 'https://$t';
  } else if (scheme != 'http' && scheme != 'https') {
    return null;
  }
  var host = Uri.tryParse(t)?.host.toLowerCase() ?? '';
  while (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  return host.contains('.') || host == 'localhost' ? host : null;
}

/// Đuôi dùng chung: mỗi tên đứng trước là một chủ khác nhau, không được gom chung.
const _sharedSuffixes = {
  'github.io', 'gitlab.io', 'pages.dev', 'workers.dev', 'vercel.app', 'netlify.app', 'web.app', 'firebaseapp.com',
  'appspot.com', 'herokuapp.com', 'onrender.com', 'azurewebsites.net', 'cloudfront.net', 'amazonaws.com', 'blogspot.com',
};

/// Phần thứ hai thường gặp trong đuôi hai tầng theo quốc gia (com.vn, co.jp...).
const _secondLevel = {'com', 'net', 'org', 'edu', 'gov', 'co', 'ac', 'or', 'ne', 'id', 'name', 'biz', 'info'};

/// Tên miền chính (phần có người đăng ký): `login.trang.com.vn` → `trang.com.vn`.
/// Không dùng danh sách đuôi đầy đủ nên đây là ước lượng, đủ cho việc gom nhóm.
String baseDomain(String host) {
  final p = host.split('.');
  if (p.length <= 2 || RegExp(r'^[0-9.]+$').hasMatch(host) || host.contains(':')) return host;
  var keep = 2;
  final lastTwo = '${p[p.length - 2]}.${p.last}';
  if (_sharedSuffixes.contains(lastTwo) || (p.last.length == 2 && _secondLevel.contains(p[p.length - 2]))) keep = 3;
  return p.sublist(p.length - keep).join('.');
}

/// Dịch vụ biết sẵn của một tên máy chủ. Chỉ khớp **đúng tên miền hoặc tên miền con** của nó:
/// `facebook.com.trang-la.ru` thuộc trang-la.ru, không phải Facebook.
KnownService? serviceOfHost(String host) {
  final parts = host.split('.');
  // Từ cụ thể nhất đến chung nhất.
  for (var i = 0; i < parts.length - 1; i++) {
    final suffix = parts.sublist(i).join('.');
    for (final s in knownServices) {
      if (s.domains.contains(suffix)) return s;
    }
  }
  return null;
}

/// Dịch vụ biết sẵn có tên (hoặc tên gọi khác) trùng **cả chuỗi** [name].
KnownService? serviceNamed(String name) {
  final n = normalizeName(name);
  if (n.isEmpty) return null;
  for (final s in knownServices) {
    if (normalizeName(s.name) == n || s.id == n || s.aliases.contains(n)) return s;
  }
  return null;
}

ServiceRef _known(KnownService s) => ServiceRef('s:${s.id}', s.name, domain: s.domains.first);

/// Chỉ tài khoản đăng nhập, mã 2FA và mục có địa chỉ web mới được gom theo dịch vụ.
ServiceRef? serviceOf(Item item) {
  final url = item.valueOf('url') ?? '';
  final host = hostOf(url);
  if (host != null) {
    final s = serviceOfHost(host);
    if (s != null) return _known(s);
    final base = baseDomain(host);
    return ServiceRef('d:$base', base, domain: base);
  }
  if (item.type != ItemType.login && item.type != ItemType.totp) return null;
  final s = serviceNamed(item.title);
  if (s != null) return _known(s);
  final n = normalizeName(item.title);
  return n.isEmpty ? null : ServiceRef('t:$n', item.title.trim());
}

/// Một dòng trong danh sách gom theo dịch vụ: một mục lẻ, hoặc nhiều tài khoản xếp chồng.
final class ServiceStack {
  ServiceStack(this.key, this.name);
  final String key;
  final String name;
  final items = <Item>[];

  bool get isStack => items.length > 1;
}

/// Gom [items] (đã sắp xếp) theo dịch vụ, giữ thứ tự bên trong mỗi nhóm.
/// [byName]: xếp các dòng theo tên hiển thị; ngược lại giữ thứ tự mục đầu tiên của mỗi nhóm.
List<ServiceStack> stackByService(List<Item> items, {required bool byName}) {
  final out = <String, ServiceStack>{};
  for (final i in items) {
    final ref = serviceOf(i);
    final key = ref?.key ?? 'i:${i.id}';
    (out[key] ??= ServiceStack(key, ref?.name ?? i.title)).items.add(i);
  }
  final list = out.values.toList();
  if (byName) {
    String label(ServiceStack s) => normalizeName(s.isStack ? s.name : s.items.first.title);
    list.sort((a, b) => label(a).compareTo(label(b)));
  }
  return list;
}
