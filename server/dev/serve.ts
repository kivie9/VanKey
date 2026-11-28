// Máy chủ chạy thử cục bộ bằng Node thuần (lưu trong bộ nhớ, tắt là mất). Dùng cho test đầu cuối và thử nhanh.
//   node dev/serve.ts [cổng]          TOKEN_SECRET="..." REGISTER_CODE="..." (tùy chọn; có giá trị mặc định cho thử nghiệm)
// Nếu đã build bản web (`npm run build:web`) thì cũng phục vụ public/ tại /app/ với cùng header như trên Cloudflare.
import { existsSync, readFileSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHandler } from '../src/handler.ts';
import { MemoryStore } from '../src/memory_store.ts';

const port = Number(process.argv[2] ?? process.env.PORT ?? 8787);
const handler = createHandler({
  store: new MemoryStore(),
  config: {
    tokenSecret: process.env.TOKEN_SECRET ?? 'dev-secret-dev-secret-dev-secret-0123456789',
    registerCode: process.env.REGISTER_CODE || undefined, // bỏ trống = ai cũng đăng ký được
  },
});

const publicDir = fileURLToPath(new URL('../public/', import.meta.url));
const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.webmanifest': 'application/manifest+json',
};

/** Đọc public/_headers (cú pháp của Cloudflare, chỉ phần cần: đường dẫn có `*` ở cuối, `! Tên` để bỏ header cha). */
function headersFor(path: string): Record<string, string> {
  const file = join(publicDir, '_headers');
  if (!existsSync(file)) return {};
  const out: Record<string, string> = {};
  let match = false;
  for (const raw of readFileSync(file, 'utf8').split('\n')) {
    if (!raw.trim() || raw.trim().startsWith('#')) continue;
    if (!/^\s/.test(raw)) {
      const p = raw.trim();
      match = p.endsWith('*') ? path.startsWith(p.slice(0, -1)) : path === p;
      continue;
    }
    if (!match) continue;
    const line = raw.trim();
    if (line.startsWith('!')) delete out[line.slice(1).trim().toLowerCase()];
    else {
      const i = line.indexOf(':');
      out[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
    }
  }
  return out;
}

/** Giống Workers Static Assets: có file thì trả file, không thì để Worker (API) xử lý. */
function serveStatic(urlPath: string): { status: number; headers: Record<string, string>; body?: Buffer } | null {
  let path = decodeURIComponent(urlPath.split('?')[0]);
  if (path === '/app') return { status: 307, headers: { location: '/app/' } };
  if (path.endsWith('/')) path += 'index.html';
  const file = normalize(join(publicDir, path));
  if (!file.startsWith(publicDir.replace(/[\\/]$/, '') + sep) || path.includes('/_headers')) return null;
  if (!existsSync(file) || !statSync(file).isFile()) return null;
  const headers = { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream', ...headersFor(urlPath.split('?')[0]) };
  return { status: 200, headers, body: readFileSync(file) };
}

const server = createServer(async (req, res) => {
  if (req.method === 'GET' || req.method === 'HEAD') {
    const s = serveStatic(req.url ?? '/');
    if (s) {
      res.writeHead(s.status, s.headers);
      res.end(req.method === 'HEAD' ? undefined : s.body);
      return;
    }
  }
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  const body = Buffer.concat(chunks);
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) if (typeof v === 'string') headers.set(k, v);
  // Chạy thử không có Cloudflare: IP lấy từ socket, ghi đè header client tự gửi (client không được giả IP).
  headers.set('cf-connecting-ip', req.socket.remoteAddress ?? '127.0.0.1');
  const request = new Request(`http://localhost:${port}${req.url}`, {
    method: req.method,
    headers,
    body: req.method === 'GET' || req.method === 'HEAD' ? undefined : body,
  });
  const response = await handler(request);
  const out: Record<string, string> = {};
  response.headers.forEach((v, k) => (out[k] = v));
  res.writeHead(response.status, out);
  res.end(Buffer.from(await response.arrayBuffer()));
});

server.listen(port, '127.0.0.1', () => {
  // Dòng này được test đầu cuối của app đọc để biết server đã sẵn sàng.
  console.log(`LISTENING ${port}`);
});
