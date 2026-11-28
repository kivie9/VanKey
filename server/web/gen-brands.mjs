// Sinh web/src/app/brands.gen.ts: logo thương hiệu (Simple Icons, giấy phép CC0) cho đúng các dịch vụ app nhận ra
// (danh sách giữ khớp với app/lib/app/brand.dart). Chỉ những logo này được đóng gói, không phải cả bộ ~3500 cái.
//   node web/gen-brands.mjs
import { writeFileSync } from 'node:fs';
import * as si from 'simple-icons';

// [bí danh..., slug Simple Icons]. Thứ tự quan trọng: mục trước được ưu tiên.
const entries = [
  [['facebook', 'fb'], 'facebook'],
  [['meta'], 'meta'],
  [['messenger'], 'messenger'],
  [['google'], 'google'],
  [['gmail', 'googlemail'], 'gmail'],
  [['googledrive'], 'googledrive'],
  [['chrome', 'googlechrome'], 'googlechrome'],
  [['firebase'], 'firebase'],
  [['android'], 'android'],
  [['youtube'], 'youtube'],
  [['github'], 'github'],
  [['gitlab'], 'gitlab'],
  [['bitbucket'], 'bitbucket'],
  [['gitea'], 'gitea'],
  [['apple', 'icloud'], 'apple'],
  [['x', 'twitter'], 'x'],
  [['instagram'], 'instagram'],
  [['discord'], 'discord'],
  [['telegram'], 'telegram'],
  [['whatsapp'], 'whatsapp'],
  [['zalo'], 'zalo'],
  [['viber'], 'viber'],
  [['line'], 'line'],
  [['wechat', 'weixin'], 'wechat'],
  [['snapchat'], 'snapchat'],
  [['tiktok'], 'tiktok'],
  [['reddit'], 'reddit'],
  [['pinterest'], 'pinterest'],
  [['twitch'], 'twitch'],
  [['tumblr'], 'tumblr'],
  [['vk', 'vkontakte'], 'vk'],
  [['medium'], 'medium'],
  [['stackoverflow'], 'stackoverflow'],
  [['netflix'], 'netflix'],
  [['spotify'], 'spotify'],
  [['steam'], 'steam'],
  [['epicgames', 'epic'], 'epicgames'],
  [['playstation', 'psn'], 'playstation'],
  [['paypal'], 'paypal'],
  [['stripe'], 'stripe'],
  [['wise'], 'wise'],
  [['revolut'], 'revolut'],
  [['visa'], 'visa'],
  [['mastercard'], 'mastercard'],
  [['americanexpress', 'amex'], 'americanexpress'],
  [['binance'], 'binance'],
  [['coinbase'], 'coinbase'],
  [['okx'], 'okx'],
  [['bitcoin', 'btc'], 'bitcoin'],
  [['ethereum', 'eth'], 'ethereum'],
  [['dropbox'], 'dropbox'],
  [['notion'], 'notion'],
  [['trello'], 'trello'],
  [['atlassian'], 'atlassian'],
  [['jira'], 'jira'],
  [['zoom'], 'zoom'],
  [['figma'], 'figma'],
  [['cloudflare'], 'cloudflare'],
  [['digitalocean'], 'digitalocean'],
  [['vercel'], 'vercel'],
  [['netlify'], 'netlify'],
  [['docker'], 'docker'],
  [['npm', 'npmjs'], 'npm'],
  [['wordpress'], 'wordpress'],
  [['shopify'], 'shopify'],
  [['claude', 'anthropic'], 'claude'],
  [['shopee'], 'shopee'],
  [['ebay'], 'ebay'],
  [['aliexpress'], 'aliexpress'],
  [['grab'], 'grab'],
  [['uber'], 'uber'],
  [['airbnb'], 'airbnb'],
  [['tripadvisor'], 'tripadvisor'],
  [['proton', 'protonmail'], 'proton'],
  [['bitwarden'], 'bitwarden'],
  [['lastpass'], 'lastpass'],
  [['nordvpn'], 'nordvpn'],
  [['expressvpn'], 'expressvpn'],
  [['tailscale'], 'tailscale'],
  [['samsung'], 'samsung'],
  [['xiaomi'], 'xiaomi'],
  [['huawei'], 'huawei'],
  [['patreon'], 'patreon'],
  [['baidu'], 'baidu'],
  [['duolingo'], 'duolingo'],
  [['coursera'], 'coursera'],
  [['udemy'], 'udemy'],
];

const exportName = (slug) => `si${slug[0].toUpperCase()}${slug.slice(1)}`;
const rows = [];
const missing = [];
for (const [aliases, slug] of entries) {
  const icon = si[exportName(slug)];
  if (!icon) {
    missing.push(slug);
    continue;
  }
  rows.push(`  [${JSON.stringify(aliases)}, '${icon.hex}', '${icon.path}'],`);
}
const out = `// Tạo bởi web/gen-brands.mjs từ simple-icons (CC0). Đừng sửa tay.
// [bí danh (đã bỏ dấu, chữ thường), màu hex, đường vẽ SVG 24x24]
export const BRANDS: [string[], string, string][] = [
${rows.join('\n')}
];
`;
writeFileSync(new URL('./src/app/brands.gen.ts', import.meta.url), out);
console.log(`${rows.length} logo${missing.length ? `, không có trong simple-icons: ${missing.join(', ')}` : ''}`);
