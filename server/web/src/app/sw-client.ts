// Đăng ký service worker. Bản mới KHÔNG tự thay bản đang chạy: nó chờ tới khi người dùng bấm "Cập nhật".
// Nhờ vậy code đang chạy trên máy chỉ đổi khi bạn đồng ý, và app vẫn mở được khi không có mạng.

let waiting: ServiceWorker | null = null;
const readyListeners = new Set<() => void>();

function announce(w: ServiceWorker): void {
  waiting = w;
  for (const l of readyListeners) l();
}

export function onUpdateReady(fn: () => void): () => void {
  readyListeners.add(fn);
  if (waiting) fn();
  return () => readyListeners.delete(fn);
}

export function applyUpdate(): void {
  waiting?.postMessage('skip-waiting');
}

export function registerSw(): void {
  if (!('serviceWorker' in navigator)) return;
  const hadController = !!navigator.serviceWorker.controller;
  let reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    // Lần cài đầu tiên không cần tải lại; chỉ tải lại khi người dùng chọn cập nhật.
    if (!hadController || reloading) return;
    reloading = true;
    location.reload();
  });
  navigator.serviceWorker
    .register('/app/sw.js', { scope: '/app/', updateViaCache: 'none' })
    .then((reg) => {
      if (reg.waiting && navigator.serviceWorker.controller) announce(reg.waiting);
      reg.addEventListener('updatefound', () => {
        const w = reg.installing;
        w?.addEventListener('statechange', () => {
          if (w.state === 'installed' && navigator.serviceWorker.controller) announce(w);
        });
      });
      // Kiểm tra bản mới mỗi giờ khi trang còn mở.
      setInterval(() => void reg.update().catch(() => {}), 60 * 60_000);
    })
    .catch(() => {
      // Không có service worker thì app vẫn chạy khi có mạng.
    });
}
