/// <reference lib="webworker" />
// Service worker của VanKey web: lưu sẵn toàn bộ app (HTML, JS, CSS, WASM) để mở được khi không có mạng.
// - Chỉ phục vụ file tĩnh trong /app/. Không bao giờ chặn hay lưu yêu cầu API (/auth, /vault...).
// - Bản mới chờ ở trạng thái "waiting" cho tới khi người dùng bấm Cập nhật (không tự skipWaiting).
declare const __PRECACHE__: string[];
declare const __VERSION__: string;

const sw = self as unknown as ServiceWorkerGlobalScope;
const CACHE = `vankey-app-${__VERSION__}`;
const SHELL = '/app/';

sw.addEventListener('install', (e) => {
  e.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      // cache: 'reload' để không lấy nhầm bản cũ trong HTTP cache.
      await cache.addAll(__PRECACHE__.map((u) => new Request(u, { cache: 'reload' })));
    })(),
  );
});

sw.addEventListener('activate', (e) => {
  e.waitUntil(
    (async () => {
      for (const k of await caches.keys()) if (k.startsWith('vankey-app-') && k !== CACHE) await caches.delete(k);
      await sw.clients.claim();
    })(),
  );
});

sw.addEventListener('message', (e) => {
  if (e.data === 'skip-waiting') void sw.skipWaiting();
});

sw.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin || !url.pathname.startsWith('/app/')) return;
  if (url.pathname === '/app/sw.js') return;
  e.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      if (req.mode === 'navigate') return (await cache.match(SHELL)) ?? fetch(req);
      return (await cache.match(req, { ignoreSearch: true })) ?? fetch(req);
    })(),
  );
});
