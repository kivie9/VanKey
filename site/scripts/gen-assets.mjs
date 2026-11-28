// Sinh tài nguyên tĩnh từ logo của app. Kết quả được commit, chỉ chạy lại khi logo hoặc chữ đổi:
//   npm run gen
// Ghi: src/data/hero-points.json, public/{favicon.svg, favicon-32.png, apple-touch-icon.png, og-vi.png, og-en.png}
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const root = new URL('../', import.meta.url);
const at = (p) => fileURLToPath(new URL(p, root));
const logo = await readFile(at('../docs/brand/vankey-logo.svg'), 'utf8');

const [shield, v] = [...logo.matchAll(/<path d="([^"]+)"/g)].map((m) => m[1]);
if (!shield || !v) throw new Error('vankey-logo.svg phải có hai path: khiên và chữ V');

await mkdir(at('src/data'), { recursive: true });
await mkdir(at('public'), { recursive: true });

// ---- Điểm cho hero -------------------------------------------------------
// Vẽ mặt nạ (khiên trắng, chữ V khoét đen) rồi lấy mẫu: một phần bám đường viền, phần còn lại phủ ruột.
const BOX = { x: 55, y: 46, w: 70, h: 90 };
const SCALE = 10;
const W = BOX.w * SCALE;
const H = BOX.h * SCALE;
const mask = await sharp(
  Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="${BOX.x} ${BOX.y} ${BOX.w} ${BOX.h}">` +
      `<rect x="${BOX.x}" y="${BOX.y}" width="${BOX.w}" height="${BOX.h}" fill="#000"/>` +
      `<path d="${shield}" fill="#fff"/>` +
      `<path d="${v}" fill="none" stroke="#000" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  ),
)
  .extractChannel(0)
  .raw()
  .toBuffer();

const inside = (x, y) => x >= 0 && y >= 0 && x < W && y < H && mask[y * W + x] > 127;

// Số ngẫu nhiên có hạt giống để lần sinh nào cũng ra cùng một file.
let seed = 0x564b5631;
const random = () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const shuffle = (list) => {
  for (let i = list.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [list[i], list[j]] = [list[j], list[i]];
  }
  return list;
};

/** Lấy tối đa mỗi ô lưới một điểm để không bị vón cục. */
function sample(isCandidate, cell, count) {
  const picked = [];
  for (let gy = 0; gy < H; gy += cell) {
    for (let gx = 0; gx < W; gx += cell) {
      for (let attempt = 0; attempt < 6; attempt++) {
        const x = gx + Math.floor(random() * cell);
        const y = gy + Math.floor(random() * cell);
        if (isCandidate(x, y)) {
          picked.push([x, y]);
          break;
        }
      }
    }
  }
  return shuffle(picked).slice(0, count);
}

const isEdge = (x, y) =>
  inside(x, y) && [[6, 0], [-6, 0], [0, 6], [0, -6]].some(([dx, dy]) => !inside(x + dx, y + dy));

const edge = sample(isEdge, 6, 1500);
const fill = sample(inside, 9, 3300);
// Trộn đều để lấy N điểm đầu (điện thoại) vẫn ra đúng hình.
const points = shuffle([...edge, ...fill]).flatMap(([x, y]) => [
  Math.round(((x - W / 2) / (H / 2)) * 1000),
  Math.round(((H / 2 - y) / (H / 2)) * 1000),
]);
await writeFile(at('src/data/hero-points.json'), JSON.stringify(points));
console.log(`hero-points.json: ${points.length / 2} điểm`);

// ---- Biểu tượng ----------------------------------------------------------
await writeFile(at('public/favicon.svg'), logo);
for (const [name, size] of [['favicon-32.png', 32], ['apple-touch-icon.png', 180]]) {
  await sharp(Buffer.from(logo), { density: 300 }).resize(size, size).png().toFile(at(`public/${name}`));
}

// ---- Ảnh xem trước khi chia sẻ (1200x630) --------------------------------
const fontfile = at('../app/assets/fonts/Inter-700.ttf');
const text = (value, size, color, width) =>
  sharp({
    text: {
      text: `<span foreground="${color}">${value}</span>`,
      font: `Inter Bold ${size}`,
      fontfile,
      width,
      dpi: 72,
      rgba: true,
      spacing: Math.round(size * 0.12),
    },
  })
    .png()
    .toBuffer();

const mark = await sharp(Buffer.from(logo), { density: 600 }).resize(300, 300).png().toBuffer();
for (const [lang, title] of [
  ['vi', 'Mật khẩu và mã 2FA,\nkhóa ngay trên máy bạn.'],
  ['en', 'Passwords and 2FA codes,\nlocked on your own device.'],
]) {
  await sharp({ create: { width: 1200, height: 630, channels: 4, background: '#0b0b0d' } })
    .composite([
      { input: mark, left: 820, top: 165 },
      { input: await text('VanKey', 40, '#3db5a0', 680), left: 80, top: 170 },
      { input: await text(title, 54, '#e4e6ea', 720), left: 80, top: 260 },
      { input: await text('Android · Windows', 28, '#8f929b', 680), left: 80, top: 440 },
    ])
    .png({ compressionLevel: 9 })
    .toFile(at(`public/og-${lang}.png`));
}
console.log('favicon và og-image: xong');
