// Đo ngân sách trong PLAN.md trên bản đã build (gzip). Chạy sau `npm run build`:  npm run budget
import { readdir, readFile } from 'node:fs/promises';
import { gzipSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';

const dist = fileURLToPath(new URL('../dist/', import.meta.url));
const files = (await readdir(dist, { recursive: true })).map((f) => f.replaceAll('\\', '/'));
const size = async (f) => gzipSync(await readFile(dist + f), { level: 9 }).length;
const sum = async (list) => (await Promise.all(list.map(size))).reduce((a, b) => a + b, 0);

const css = files.filter((f) => f.endsWith('.css'));
const js = files.filter((f) => f.endsWith('.js'));
const hero = js.filter((f) => /\/hero-scene\./.test(f));
if (!hero.length) throw new Error('Không tìm thấy chunk hero-scene trong dist/');

for (const f of js) console.log(`  ${f}: ${((await size(f)) / 1024).toFixed(1)} KB`);

let failed = false;
for (const [name, bytes, limit] of [
  ['HTML + CSS trang đầu', (await sum(css)) + (await size('index.html')), 60],
  ['JS của hero', await sum(hero), 150],
  ['JS tổng', await sum(js), 200],
]) {
  const kb = bytes / 1024;
  const ok = kb <= limit;
  failed ||= !ok;
  console.log(`${ok ? 'ĐẠT ' : 'VƯỢT'} ${name}: ${kb.toFixed(1)} / ${limit} KB gzip`);
}
process.exit(failed ? 1 : 0);
