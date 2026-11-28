// Build bản web vào server/public/ (Workers Static Assets phục vụ thư mục này, cùng Worker với API).
//   node web/build.mjs            (wrangler tự chạy qua [build] trong wrangler.toml)
// Kết quả: public/app/ (index.html, sw.js, assets/*-[hash].js|css, icon, manifest) và public/_headers.
import { createHash } from 'node:crypto';
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', 'public');
const app = join(out, 'app');
const assets = join(app, 'assets');

rmSync(out, { recursive: true, force: true });
mkdirSync(assets, { recursive: true });

const common = {
  bundle: true,
  minify: true,
  sourcemap: false,
  target: ['es2022', 'chrome111', 'firefox115', 'safari16'],
  legalComments: 'none',
  logLevel: 'warning',
  metafile: true,
  write: true,
};

const outputsOf = (r) => Object.keys(r.metafile.outputs).filter((p) => !p.endsWith('.map'));
const url = (p) => `/${relative(out, p).replaceAll('\\', '/')}`;

// 1) Worker cho Argon2id (hash-wasm nằm gọn trong file này).
const worker = await esbuild.build({ ...common, entryPoints: [join(here, 'src/kdf.worker.ts')], outdir: assets, entryNames: 'kdf-[hash]', format: 'iife' });
const workerUrl = url(join(here, '..', outputsOf(worker)[0]));

// 2) App chính (Preact + CSS).
const main = await esbuild.build({
  ...common,
  entryPoints: [join(here, 'src/app/main.tsx')],
  outdir: assets,
  entryNames: 'main-[hash]',
  // Bảng logo dịch vụ được tách thành file riêng, tải sau khi trang đã hiện.
  splitting: true,
  chunkNames: 'chunk-[hash]',
  format: 'esm',
  jsx: 'automatic',
  jsxImportSource: 'preact',
  define: { __KDF_WORKER__: JSON.stringify(workerUrl) },
});
const mainOut = outputsOf(main).map((p) => join(here, '..', p));
const js = mainOut.find((p) => /main-[^\/]+.js$/.test(p));
const chunks = mainOut.filter((p) => p.endsWith('.js') && p !== js);
const css = mainOut.find((p) => p.endsWith('.css'));

// 3) File tĩnh: icon, manifest.
cpSync(join(here, 'static'), app, { recursive: true });

// 4) index.html với Subresource Integrity: trình duyệt từ chối chạy nếu file JS/CSS khác hash đã ghi.
const sri = (p) => `sha384-${createHash('sha384').update(readFileSync(p)).digest('base64')}`;
const html = `<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="referrer" content="no-referrer">
<meta name="robots" content="noindex">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#f4f5f7" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0b0b0d" media="(prefers-color-scheme: dark)">
<title>VanKey</title>
<link rel="icon" href="/app/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/app/apple-touch-icon.png">
<link rel="manifest" href="/app/manifest.webmanifest">
<link rel="stylesheet" href="${url(css)}" integrity="${sri(css)}">
<script type="module" src="${url(js)}" integrity="${sri(js)}"></script>
</head>
<body>
<div id="app"></div>
<noscript>VanKey web cần bật JavaScript.</noscript>
</body>
</html>
`;
writeFileSync(join(app, 'index.html'), html);

// 5) Service worker: danh sách file cần lưu sẵn + phiên bản = hash của toàn bộ nội dung.
const precache = ['/app/', url(js), url(css), ...chunks.map(url), workerUrl, '/app/favicon.svg', '/app/apple-touch-icon.png', '/app/manifest.webmanifest'];
const version = createHash('sha256')
  .update(html)
  .update(precache.join('\n'))
  .digest('hex')
  .slice(0, 16);
await esbuild.build({
  ...common,
  metafile: false,
  entryPoints: [join(here, 'src/sw.ts')],
  outfile: join(app, 'sw.js'),
  format: 'iife',
  define: { __PRECACHE__: JSON.stringify(precache), __VERSION__: JSON.stringify(version) },
});

// 6) Header bảo mật cho phần web. 'wasm-unsafe-eval' chỉ cho phép biên dịch WebAssembly (Argon2id), không cho eval JS.
const csp = [
  "default-src 'none'",
  "script-src 'self' 'wasm-unsafe-eval'",
  "worker-src 'self'",
  "style-src 'self'",
  "img-src 'self'",
  "connect-src 'self'",
  "manifest-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join('; ');
const security = [
  `Content-Security-Policy: ${csp}`,
  'X-Content-Type-Options: nosniff',
  'Referrer-Policy: no-referrer',
  'Cross-Origin-Opener-Policy: same-origin',
  'Cross-Origin-Resource-Policy: same-origin',
  'Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()',
  'Strict-Transport-Security: max-age=31536000; includeSubDomains',
  'X-Frame-Options: DENY',
];
const headers = `# Tạo bởi web/build.mjs, đừng sửa tay.
/app/*
${security.map((h) => `  ${h}`).join('\n')}
  Cache-Control: no-cache

/app/assets/*
  ! Cache-Control
  Cache-Control: public, max-age=31536000, immutable
`;
writeFileSync(join(out, '_headers'), headers);

const size = (p) => readFileSync(p).length;
const gz = async (p) => (await import('node:zlib')).gzipSync(readFileSync(p), { level: 9 }).length;
const kb = (n) => `${(n / 1024).toFixed(1)} KB`;
for (const p of [js, css, join(here, '..', outputsOf(worker)[0]), join(app, 'sw.js')]) {
  console.log(`${basename(p).padEnd(28)} ${kb(size(p)).padStart(9)}  gzip ${kb(await gz(p)).padStart(9)}`);
}
console.log(`web build ${version} → ${relative(process.cwd(), out)}`);
