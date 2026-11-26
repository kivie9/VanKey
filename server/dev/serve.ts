// Máy chủ chạy thử cục bộ bằng Node thuần (lưu trong bộ nhớ, tắt là mất). Dùng cho test đầu cuối và thử nhanh.
//   node dev/serve.ts [cổng]          TOKEN_SECRET="..." REGISTER_CODE="..." (tùy chọn; có giá trị mặc định cho thử nghiệm)
import { createServer } from 'node:http';
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

const server = createServer(async (req, res) => {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  const body = Buffer.concat(chunks);
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) if (typeof v === 'string') headers.set(k, v);
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
