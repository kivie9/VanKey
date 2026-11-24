import 'package:material_ui/material_ui.dart';
import 'package:simple_icons/simple_icons.dart';

import '../core/vault/search.dart';

/// Logo thương hiệu nhỏ (biểu tượng dạng phông của Simple Icons, giấy phép CC0).
///
/// Chỉ các biểu tượng được tham chiếu ở đây mới được đóng gói vào app (Flutter tự cắt phông khi build release),
/// nên tốn thêm vài chục KB chứ không phải 1,4 MB của cả bộ. Một số thương hiệu lớn (Microsoft, Amazon, LinkedIn, Slack,
/// OpenAI...) đã bị gỡ khỏi bộ biểu tượng này theo yêu cầu của chủ thương hiệu nên sẽ dùng chữ cái đầu như mục thường.
class Brand {
  const Brand(this.icon, this.color, {this.sweep, this.stops});
  final IconData icon;
  final Color color;

  /// Thương hiệu nhiều màu (Google): vẽ biểu tượng trên nền sáng với dải màu quét quanh thay vì một màu.
  final List<Color>? sweep;
  final List<double>? stops;

  bool get multicolor => sweep != null;
}

/// Bật/tắt logo (đặt từ Cài đặt). Mặc định bật.
abstract final class BrandConfig {
  static bool enabled = true;
}

class _Entry {
  const _Entry(this.aliases, this.brand);

  /// Tên gọi, đã bỏ dấu và viết thường. Tên ≤ 5 ký tự phải khớp nguyên từ; tên dài hơn khớp cả khi dính liền ("githubenterprise").
  final List<String> aliases;
  final Brand brand;
}

const _entries = <_Entry>[
  _Entry(['facebook', 'fb'], Brand(SimpleIcons.facebook, SimpleIconColors.facebook)),
  _Entry(['meta'], Brand(SimpleIcons.meta, SimpleIconColors.meta)),
  _Entry(['messenger'], Brand(SimpleIcons.messenger, SimpleIconColors.messenger)),
  // Chữ G của Google có 4 màu: xanh dương (thanh ngang bên phải), xanh lá (dưới), vàng (trái), đỏ (trên).
  _Entry(
    ['google'],
    Brand(
      SimpleIcons.google,
      SimpleIconColors.google,
      sweep: [Color(0xFF4285F4), Color(0xFF4285F4), Color(0xFF34A853), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFFEA4335)],
      stops: [0.0, 0.236, 0.236, 0.486, 0.486, 0.667, 0.667, 1.0],
    ),
  ),
  _Entry(['gmail', 'googlemail'], Brand(SimpleIcons.gmail, SimpleIconColors.gmail)),
  _Entry(['googledrive'], Brand(SimpleIcons.googledrive, SimpleIconColors.googledrive)),
  _Entry(['chrome', 'googlechrome'], Brand(SimpleIcons.googlechrome, SimpleIconColors.googlechrome)),
  _Entry(['firebase'], Brand(SimpleIcons.firebase, SimpleIconColors.firebase)),
  _Entry(['android'], Brand(SimpleIcons.android, SimpleIconColors.android)),
  _Entry(['youtube'], Brand(SimpleIcons.youtube, SimpleIconColors.youtube)),
  _Entry(['github'], Brand(SimpleIcons.github, SimpleIconColors.github)),
  _Entry(['gitlab'], Brand(SimpleIcons.gitlab, SimpleIconColors.gitlab)),
  _Entry(['bitbucket'], Brand(SimpleIcons.bitbucket, SimpleIconColors.bitbucket)),
  _Entry(['gitea'], Brand(SimpleIcons.gitea, SimpleIconColors.gitea)),
  _Entry(['apple', 'icloud'], Brand(SimpleIcons.apple, SimpleIconColors.apple)),
  _Entry(['x', 'twitter'], Brand(SimpleIcons.x, SimpleIconColors.x)),
  _Entry(['instagram'], Brand(SimpleIcons.instagram, SimpleIconColors.instagram)),
  _Entry(['discord'], Brand(SimpleIcons.discord, SimpleIconColors.discord)),
  _Entry(['telegram'], Brand(SimpleIcons.telegram, SimpleIconColors.telegram)),
  _Entry(['whatsapp'], Brand(SimpleIcons.whatsapp, SimpleIconColors.whatsapp)),
  _Entry(['zalo'], Brand(SimpleIcons.zalo, SimpleIconColors.zalo)),
  _Entry(['viber'], Brand(SimpleIcons.viber, SimpleIconColors.viber)),
  _Entry(['line'], Brand(SimpleIcons.line, SimpleIconColors.line)),
  _Entry(['wechat', 'weixin'], Brand(SimpleIcons.wechat, SimpleIconColors.wechat)),
  _Entry(['snapchat'], Brand(SimpleIcons.snapchat, SimpleIconColors.snapchat)),
  _Entry(['tiktok'], Brand(SimpleIcons.tiktok, SimpleIconColors.tiktok)),
  _Entry(['reddit'], Brand(SimpleIcons.reddit, SimpleIconColors.reddit)),
  _Entry(['pinterest'], Brand(SimpleIcons.pinterest, SimpleIconColors.pinterest)),
  _Entry(['twitch'], Brand(SimpleIcons.twitch, SimpleIconColors.twitch)),
  _Entry(['tumblr'], Brand(SimpleIcons.tumblr, SimpleIconColors.tumblr)),
  _Entry(['vk', 'vkontakte'], Brand(SimpleIcons.vk, SimpleIconColors.vk)),
  _Entry(['medium'], Brand(SimpleIcons.medium, SimpleIconColors.medium)),
  _Entry(['stackoverflow'], Brand(SimpleIcons.stackoverflow, SimpleIconColors.stackoverflow)),
  _Entry(['netflix'], Brand(SimpleIcons.netflix, SimpleIconColors.netflix)),
  _Entry(['spotify'], Brand(SimpleIcons.spotify, SimpleIconColors.spotify)),
  _Entry(['steam'], Brand(SimpleIcons.steam, SimpleIconColors.steam)),
  _Entry(['epicgames', 'epic'], Brand(SimpleIcons.epicgames, SimpleIconColors.epicgames)),
  _Entry(['playstation', 'psn'], Brand(SimpleIcons.playstation, SimpleIconColors.playstation)),
  _Entry(['paypal'], Brand(SimpleIcons.paypal, SimpleIconColors.paypal)),
  _Entry(['stripe'], Brand(SimpleIcons.stripe, SimpleIconColors.stripe)),
  _Entry(['wise'], Brand(SimpleIcons.wise, SimpleIconColors.wise)),
  _Entry(['revolut'], Brand(SimpleIcons.revolut, SimpleIconColors.revolut)),
  _Entry(['visa'], Brand(SimpleIcons.visa, SimpleIconColors.visa)),
  _Entry(['mastercard'], Brand(SimpleIcons.mastercard, SimpleIconColors.mastercard)),
  _Entry(['americanexpress', 'amex'], Brand(SimpleIcons.americanexpress, SimpleIconColors.americanexpress)),
  _Entry(['binance'], Brand(SimpleIcons.binance, SimpleIconColors.binance)),
  _Entry(['coinbase'], Brand(SimpleIcons.coinbase, SimpleIconColors.coinbase)),
  _Entry(['okx'], Brand(SimpleIcons.okx, SimpleIconColors.okx)),
  _Entry(['bitcoin', 'btc'], Brand(SimpleIcons.bitcoin, SimpleIconColors.bitcoin)),
  _Entry(['ethereum', 'eth'], Brand(SimpleIcons.ethereum, SimpleIconColors.ethereum)),
  _Entry(['dropbox'], Brand(SimpleIcons.dropbox, SimpleIconColors.dropbox)),
  _Entry(['notion'], Brand(SimpleIcons.notion, SimpleIconColors.notion)),
  _Entry(['trello'], Brand(SimpleIcons.trello, SimpleIconColors.trello)),
  _Entry(['atlassian'], Brand(SimpleIcons.atlassian, SimpleIconColors.atlassian)),
  _Entry(['jira'], Brand(SimpleIcons.jira, SimpleIconColors.jira)),
  _Entry(['zoom'], Brand(SimpleIcons.zoom, SimpleIconColors.zoom)),
  _Entry(['figma'], Brand(SimpleIcons.figma, SimpleIconColors.figma)),
  _Entry(['cloudflare'], Brand(SimpleIcons.cloudflare, SimpleIconColors.cloudflare)),
  _Entry(['digitalocean'], Brand(SimpleIcons.digitalocean, SimpleIconColors.digitalocean)),
  _Entry(['vercel'], Brand(SimpleIcons.vercel, SimpleIconColors.vercel)),
  _Entry(['netlify'], Brand(SimpleIcons.netlify, SimpleIconColors.netlify)),
  _Entry(['docker'], Brand(SimpleIcons.docker, SimpleIconColors.docker)),
  _Entry(['npm', 'npmjs'], Brand(SimpleIcons.npm, SimpleIconColors.npm)),
  _Entry(['wordpress'], Brand(SimpleIcons.wordpress, SimpleIconColors.wordpress)),
  _Entry(['shopify'], Brand(SimpleIcons.shopify, SimpleIconColors.shopify)),
  _Entry(['claude', 'anthropic'], Brand(SimpleIcons.claude, SimpleIconColors.claude)),
  _Entry(['shopee'], Brand(SimpleIcons.shopee, SimpleIconColors.shopee)),
  _Entry(['ebay'], Brand(SimpleIcons.ebay, SimpleIconColors.ebay)),
  _Entry(['aliexpress'], Brand(SimpleIcons.aliexpress, SimpleIconColors.aliexpress)),
  _Entry(['grab'], Brand(SimpleIcons.grab, SimpleIconColors.grab)),
  _Entry(['uber'], Brand(SimpleIcons.uber, SimpleIconColors.uber)),
  _Entry(['airbnb'], Brand(SimpleIcons.airbnb, SimpleIconColors.airbnb)),
  _Entry(['tripadvisor'], Brand(SimpleIcons.tripadvisor, SimpleIconColors.tripadvisor)),
  _Entry(['proton', 'protonmail'], Brand(SimpleIcons.proton, SimpleIconColors.proton)),
  _Entry(['bitwarden'], Brand(SimpleIcons.bitwarden, SimpleIconColors.bitwarden)),
  _Entry(['lastpass'], Brand(SimpleIcons.lastpass, SimpleIconColors.lastpass)),
  _Entry(['nordvpn'], Brand(SimpleIcons.nordvpn, SimpleIconColors.nordvpn)),
  _Entry(['expressvpn'], Brand(SimpleIcons.expressvpn, SimpleIconColors.expressvpn)),
  _Entry(['tailscale'], Brand(SimpleIcons.tailscale, SimpleIconColors.tailscale)),
  _Entry(['samsung'], Brand(SimpleIcons.samsung, SimpleIconColors.samsung)),
  _Entry(['xiaomi'], Brand(SimpleIcons.xiaomi, SimpleIconColors.xiaomi)),
  _Entry(['huawei'], Brand(SimpleIcons.huawei, SimpleIconColors.huawei)),
  _Entry(['patreon'], Brand(SimpleIcons.patreon, SimpleIconColors.patreon)),
  _Entry(['baidu'], Brand(SimpleIcons.baidu, SimpleIconColors.baidu)),
  _Entry(['duolingo'], Brand(SimpleIcons.duolingo, SimpleIconColors.duolingo)),
  _Entry(['coursera'], Brand(SimpleIcons.coursera, SimpleIconColors.coursera)),
  _Entry(['udemy'], Brand(SimpleIcons.udemy, SimpleIconColors.udemy)),
];

/// Các nhãn dùng để so khớp: từ trong tên mục và các phần của tên miền (bỏ www, com, vn...).
Set<String> _words(String title, String url) {
  final out = <String>{};
  for (final w in foldVietnamese(title.toLowerCase()).split(RegExp(r'[^a-z0-9]+'))) {
    if (w.isNotEmpty) out.add(w);
  }
  var host = '';
  final t = url.trim();
  if (t.isNotEmpty) {
    final u = Uri.tryParse(t.contains('://') ? t : 'https://$t');
    host = (u?.host ?? '').toLowerCase();
  }
  const skip = {'www', 'com', 'net', 'org', 'vn', 'io', 'co', 'app', 'me', 'id', 'accounts', 'login', 'auth', 'mail', 'm'};
  for (final p in host.split('.')) {
    if (p.isNotEmpty && !skip.contains(p)) out.add(p);
  }
  return out;
}

/// Tìm logo cho một mục theo tên và địa chỉ web; `null` nếu không nhận ra thương hiệu nào.
Brand? brandFor(String title, [String url = '']) {
  final words = _words(title, url);
  if (words.isEmpty) return null;
  final joined = words.join();
  for (final e in _entries) {
    for (final a in e.aliases) {
      if (words.contains(a)) return e.brand;
      if (a.length >= 6 && joined.contains(a)) return e.brand;
    }
  }
  return null;
}
