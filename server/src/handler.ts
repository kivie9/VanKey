import { fetchGoogleJwks, verifyGoogleIdToken } from './google.ts';
import type { JwksFetcher } from './google.ts';
import type { Device, Store, User } from './store.ts';
import { signAccess, verifyAccess } from './tokens.ts';
import { fromBase64, pbkdf2, randomBytes, randomId, sha256, timingSafeEqual, toB64url, toHex, utf8 } from './util.ts';

export interface Config {
  /** Email được phép đăng ký/đăng nhập, ngăn cách bằng dấu phẩy. Rỗng = từ chối tất cả (an toàn mặc định). */
  allowedEmails: string;
  /** Bí mật ký access token (chuỗi ngẫu nhiên dài, đặt bằng `wrangler secret`). */
  tokenSecret: string;
  /** Client ID Google, nhiều giá trị ngăn cách bằng dấu phẩy. Rỗng = tắt đăng nhập Google. */
  googleClientIds?: string;
}

export interface Deps {
  store: Store;
  config: Config;
  /** Giây UNIX. Đưa vào để test điều khiển được thời gian. */
  now?: () => number;
  jwks?: JwksFetcher;
}

export const ACCESS_TTL = 15 * 60;
export const REFRESH_TTL = 90 * 24 * 3600;
export const MAX_VAULT_BYTES = 1_500_000; // dưới giới hạn ~2 MB mỗi dòng của D1
const MAX_JSON_BYTES = 8 * 1024;
const MAX_FAILURES = 5;

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...headers } });
}

const err = (status: number, code: string, message: string, extra: Record<string, unknown> = {}) => json(status, { error: code, message, ...extra });

async function readJson(req: Request): Promise<Record<string, unknown> | null> {
  const buf = new Uint8Array(await req.arrayBuffer());
  if (buf.length > MAX_JSON_BYTES) return null;
  try {
    const v = JSON.parse(new TextDecoder().decode(buf));
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const str = (v: unknown, max = 200): string | null => (typeof v === 'string' && v.length > 0 && v.length <= max ? v : null);

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  const { store, config } = deps;
  const now = deps.now ?? (() => Math.floor(Date.now() / 1000));
  const secret = utf8(config.tokenSecret);
  const allowed = new Set(config.allowedEmails.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean));
  const googleAud = (config.googleClientIds ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  const jwks = deps.jwks ?? fetchGoogleJwks;

  // ---------- Giới hạn tốc độ đăng nhập ----------

  async function lockedFor(key: string): Promise<number> {
    const a = await store.getAttempt(key);
    return a.lockedUntil > now() ? a.lockedUntil - now() : 0;
  }

  async function recordFailure(key: string): Promise<void> {
    const a = await store.getAttempt(key);
    const count = a.count + 1;
    // Từ lần thứ 5: khóa 30 s, rồi gấp đôi mỗi lần, tối đa 15 phút.
    const lock = count >= MAX_FAILURES ? Math.min(900, 30 * 2 ** (count - MAX_FAILURES)) : 0;
    await store.setAttempt(key, { count, lockedUntil: lock ? now() + lock : 0 });
  }

  // ---------- Phát token ----------

  async function issueSession(user: User, deviceName: string, existing?: Device): Promise<Response> {
    const refresh = toB64url(randomBytes(32));
    const refreshHash = toHex(await sha256(utf8(refresh)));
    const t = now();
    let deviceId: string;
    if (existing) {
      deviceId = existing.id;
      await store.updateDevice(existing.id, { refreshHash, lastSeen: t, expiresAt: t + REFRESH_TTL });
    } else {
      deviceId = randomId();
      await store.createDevice({ id: deviceId, userId: user.id, name: deviceName, refreshHash, createdAt: t, lastSeen: t, expiresAt: t + REFRESH_TTL, revoked: false });
    }
    const accessToken = await signAccess(secret, { sub: user.id, dev: deviceId, exp: t + ACCESS_TTL });
    return json(200, { accessToken, refreshToken: refresh, expiresIn: ACCESS_TTL, deviceId, accountId: user.id, email: user.email });
  }

  async function authenticate(req: Request): Promise<{ user: User; device: Device } | Response> {
    const h = req.headers.get('authorization') ?? '';
    if (!h.startsWith('Bearer ')) return err(401, 'unauthorized', 'Thiếu token');
    const claims = await verifyAccess(secret, h.slice(7), now());
    if (!claims) return err(401, 'unauthorized', 'Token không hợp lệ hoặc đã hết hạn');
    const device = await store.deviceById(claims.dev);
    // Kiểm tra thiết bị mỗi lần: thu hồi có hiệu lực ngay, không phải chờ token hết hạn.
    if (!device || device.revoked || device.userId !== claims.sub) return err(401, 'revoked', 'Thiết bị đã bị gỡ');
    const user = await store.userById(claims.sub);
    if (!user) return err(401, 'unauthorized', 'Tài khoản không tồn tại');
    if (!allowed.has(user.email)) return err(403, 'forbidden', 'Email này không còn được phép dùng máy chủ');
    return { user, device };
  }

  // ---------- Các route ----------

  async function register(req: Request): Promise<Response> {
    const body = await readJson(req);
    const email = str(body?.email)?.trim().toLowerCase() ?? null;
    const authKey = str(body?.authKey, 100);
    if (!email || !authKey) return err(400, 'bad_request', 'Thiếu email hoặc authKey');
    let key: Uint8Array;
    try {
      key = fromBase64(authKey);
    } catch {
      return err(400, 'bad_request', 'authKey không hợp lệ');
    }
    if (key.length !== 32) return err(400, 'bad_request', 'authKey phải dài 32 byte');
    if (!allowed.has(email)) return err(403, 'forbidden', 'Email này không được phép đăng ký');

    const salt = randomBytes(16);
    const user: User = { id: randomId(), email, salt, pwHash: await pbkdf2(key, salt), createdAt: now() };
    if (!(await store.createUser(user))) return err(409, 'exists', 'Email đã được đăng ký');
    return issueSession(user, str(body?.deviceName, 80) ?? 'Thiết bị');
  }

  async function login(req: Request): Promise<Response> {
    const body = await readJson(req);
    const email = str(body?.email)?.trim().toLowerCase() ?? null;
    const authKey = str(body?.authKey, 100);
    if (!email || !authKey) return err(400, 'bad_request', 'Thiếu email hoặc authKey');
    const ip = req.headers.get('cf-connecting-ip') ?? 'unknown';
    const keys = [`login:${email}`, `ip:${ip}`];
    for (const k of keys) {
      const wait = await lockedFor(k);
      if (wait > 0) return err(429, 'locked', `Đăng nhập sai nhiều lần. Thử lại sau ${wait} giây.`, { retryAfter: wait });
    }

    let key: Uint8Array | null = null;
    try {
      key = fromBase64(authKey);
    } catch {
      key = null;
    }
    const user = allowed.has(email) ? await store.userByEmail(email) : null;
    // Luôn chạy PBKDF2 để thời gian phản hồi không lộ email có tồn tại hay không.
    const salt = user?.salt ?? randomBytes(16);
    const hash = key && key.length === 32 ? await pbkdf2(key, salt) : await pbkdf2(new Uint8Array(32), salt);
    const ok = !!user && !!user.pwHash && !!key && key.length === 32 && timingSafeEqual(hash, user.pwHash);
    if (!ok || !user) {
      for (const k of keys) await recordFailure(k);
      return err(401, 'invalid_credentials', 'Email hoặc mật khẩu không đúng');
    }
    for (const k of keys) await store.clearAttempt(k);
    return issueSession(user, str(body?.deviceName, 80) ?? 'Thiết bị');
  }

  async function google(req: Request): Promise<Response> {
    if (googleAud.length === 0) return err(404, 'disabled', 'Đăng nhập Google chưa được bật trên máy chủ này');
    const body = await readJson(req);
    const idToken = str(body?.idToken, 4096);
    if (!idToken) return err(400, 'bad_request', 'Thiếu idToken');
    const id = await verifyGoogleIdToken(idToken, { audiences: googleAud, now: now(), jwks });
    if (!id) return err(401, 'invalid_credentials', 'Google token không hợp lệ');
    if (!allowed.has(id.email)) return err(403, 'forbidden', 'Email này không được phép dùng máy chủ');
    let user = await store.userByEmail(id.email);
    if (!user) {
      user = { id: randomId(), email: id.email, salt: null, pwHash: null, createdAt: now() };
      if (!(await store.createUser(user))) user = await store.userByEmail(id.email);
      if (!user) return err(500, 'internal', 'Không tạo được tài khoản');
    }
    return issueSession(user, str(body?.deviceName, 80) ?? 'Thiết bị');
  }

  async function refresh(req: Request): Promise<Response> {
    const body = await readJson(req);
    const token = str(body?.refreshToken, 200);
    if (!token) return err(400, 'bad_request', 'Thiếu refreshToken');
    const hash = toHex(await sha256(utf8(token)));
    const device = await store.deviceByRefreshHash(hash);
    if (!device || device.revoked || device.expiresAt <= now()) return err(401, 'invalid_refresh', 'Refresh token không hợp lệ hoặc đã hết hạn');
    const user = await store.userById(device.userId);
    if (!user || !allowed.has(user.email)) return err(401, 'invalid_refresh', 'Tài khoản không còn hợp lệ');
    // Xoay vòng: token cũ không dùng lại được.
    return issueSession(user, device.name, device);
  }

  return async function handle(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';
    const m = req.method.toUpperCase();
    try {
      if (path === '/' && m === 'GET') return json(200, { ok: true, service: 'vankey' });

      if (path === '/auth/register' && m === 'POST') return await register(req);
      if (path === '/auth/login' && m === 'POST') return await login(req);
      if (path === '/auth/google' && m === 'POST') return await google(req);
      if (path === '/auth/refresh' && m === 'POST') return await refresh(req);

      // Từ đây cần đăng nhập
      if (path === '/auth/logout' || path === '/devices' || path.startsWith('/devices/') || path === '/vault') {
        const a = await authenticate(req);
        if (a instanceof Response) return a;
        const { user, device } = a;

        if (path === '/auth/logout' && m === 'POST') {
          await store.updateDevice(device.id, { revoked: true });
          return new Response(null, { status: 204 });
        }

        if (path === '/devices' && m === 'GET') {
          const list = await store.devicesOf(user.id);
          return json(200, { devices: list.map((d) => ({ id: d.id, name: d.name, createdAt: d.createdAt, lastSeen: d.lastSeen, current: d.id === device.id })) });
        }

        if (path.startsWith('/devices/') && m === 'DELETE') {
          const id = decodeURIComponent(path.slice('/devices/'.length));
          const target = await store.deviceById(id);
          // Chỉ gỡ được thiết bị của chính mình; trả 404 chung để không lộ id của người khác.
          if (!target || target.userId !== user.id || target.revoked) return err(404, 'not_found', 'Không thấy thiết bị');
          await store.updateDevice(id, { revoked: true });
          return new Response(null, { status: 204 });
        }

        if (path === '/vault' && m === 'GET') {
          const v = await store.getVault(user.id);
          if (!v) return err(404, 'no_vault', 'Chưa có kho trên máy chủ');
          const etag = `"v${v.version}"`;
          if (req.headers.get('if-none-match') === etag) return new Response(null, { status: 304, headers: { etag } });
          return new Response(v.blob as BufferSource, { status: 200, headers: { 'content-type': 'application/octet-stream', etag, 'cache-control': 'no-store' } });
        }

        if (path === '/vault' && m === 'PUT') {
          const ifMatch = req.headers.get('if-match');
          const ifNone = req.headers.get('if-none-match');
          let expected: number | null;
          if (ifNone === '*') expected = null;
          else if (ifMatch && /^"v\d+"$/.test(ifMatch)) expected = Number(ifMatch.slice(2, -1));
          else return err(428, 'precondition_required', 'Cần If-Match hoặc If-None-Match: *');

          const len = Number(req.headers.get('content-length') ?? '0');
          if (len > MAX_VAULT_BYTES) return err(413, 'too_large', 'Kho quá lớn');
          const body = new Uint8Array(await req.arrayBuffer());
          if (body.length > MAX_VAULT_BYTES) return err(413, 'too_large', 'Kho quá lớn');
          if (body.length < 32) return err(400, 'bad_request', 'Nội dung quá ngắn');

          const r = await store.putVault(user.id, expected, body, now());
          if (!r.ok) {
            return json(409, { error: 'conflict', message: 'Kho đã bị thay đổi ở nơi khác', version: r.current }, r.current === null ? {} : { etag: `"v${r.current}"` });
          }
          return json(200, { version: r.version }, { etag: `"v${r.version}"` });
        }
      }

      return err(404, 'not_found', 'Không có đường dẫn này');
    } catch (e) {
      // Không bao giờ trả chi tiết lỗi nội bộ ra ngoài.
      console.error('lỗi xử lý', e instanceof Error ? e.message : 'unknown');
      return err(500, 'internal', 'Lỗi máy chủ');
    }
  };
}
