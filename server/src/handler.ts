import type { Device, Store, User } from './store.ts';
import { signAccess, verifyAccess } from './tokens.ts';
import { fromBase64, pbkdf2, randomBytes, randomId, sha256, timingSafeEqual, toB64url, toHex, utf8 } from './util.ts';

export interface Config {
  /** Bí mật ký access token (chuỗi ngẫu nhiên dài, đặt bằng `wrangler secret`). */
  tokenSecret: string;
  /**
   * Mã mời tùy chọn (`wrangler secret put REGISTER_CODE`). Bỏ trống = ai cũng đăng ký được (có giới hạn).
   * Đã đặt thì bắt buộc phải nhập đúng mã mới tạo được tài khoản; đặt ngắn hơn 12 ký tự = đóng đăng ký.
   */
  registerCode?: string;
  /** Số tài khoản tối đa (bảo vệ hạn mức miễn phí của Cloudflare). Mặc định 200. */
  maxUsers?: number;
}

export interface Deps {
  store: Store;
  config: Config;
  /** Giây UNIX. Đưa vào để test điều khiển được thời gian. */
  now?: () => number;
}

export const ACCESS_TTL = 15 * 60;
export const REFRESH_TTL = 90 * 24 * 3600;
export const MAX_VAULT_BYTES = 1_500_000; // dưới giới hạn ~2 MB mỗi dòng của D1
export const DEFAULT_MAX_USERS = 200;
export const MIN_REGISTER_CODE = 12;
export const MAX_DEVICES = 20; // mỗi tài khoản; vượt thì thiết bị lâu không dùng nhất bị gỡ
export const REGISTER_PER_IP = 10; // số lần đăng ký tối đa mỗi IP; quá thì khóa 1 giờ
const REGISTER_LOCK = 3600;
const MAX_JSON_BYTES = 8 * 1024;
/**
 * Số vòng PBKDF2 trên máy chủ cho tài khoản mới. authKey gửi lên đã là đầu ra Argon2id (32 byte) nên không cần
 * nhiều vòng; 100000 vòng (mức cũ) tốn hơn 10 ms CPU, vượt giới hạn gói miễn phí của Cloudflare Workers.
 * Tài khoản cũ được băm lại với số vòng này ở lần đăng nhập đúng kế tiếp.
 */
export const KDF_ITERATIONS = 5000;
const MAX_FAILURES_IP = 5; // sai mật khẩu hoặc mã mời liên tiếp, theo IP
const MAX_FAILURES_USER = 20; // theo tài khoản: ngưỡng cao để người lạ khó khóa tài khoản của bạn
/** Khóa tối đa theo IP: 15 phút. */
const LOCK_MAX = 900;
/**
 * Khóa tối đa theo tài khoản: 1 phút. Kẻ phá không giữ được tài khoản bị khóa lâu;
 * chỉ vẫn còn tác dụng làm chậm việc dò mật khẩu từ nhiều IP.
 */
const ACCOUNT_LOCK_MAX = 60;
const ATTEMPT_TTL = 24 * 3600; // dòng đếm lần sai không cập nhật quá lâu thì bị dọn
const USERNAME_RE = /^[a-z0-9][a-z0-9._-]{2,31}$/;

/** Chuẩn hóa tên đăng nhập; null nếu không hợp lệ (3 đến 32 ký tự: chữ thường, số, dấu chấm, gạch dưới, gạch ngang). */
export function normalizeUsername(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const u = v.trim().toLowerCase();
  return USERNAME_RE.test(u) ? u : null;
}

/** Địa chỉ IPv6 gom theo /64 (một người dùng có cả dải rất lớn); IPv4 giữ nguyên. */
function ipKey(ip: string): string {
  if (!ip.includes(':')) return ip;
  const full = ip.split('::')[0].split(':');
  return full.slice(0, 4).join(':');
}

/**
 * IP thật của người gửi, lấy từ header do Cloudflare đặt (client không tự đặt được).
 * Trả null nếu thiếu: không đoán và không gom mọi người vào một khóa chung.
 */
function clientIp(req: Request): string | null {
  const ip = req.headers.get('cf-connecting-ip');
  return ip && ip.length > 0 && ip.length <= 100 ? ip : null;
}

const noClientIp = () => err(500, 'misconfigured', 'Máy chủ không xác định được IP của yêu cầu. Cần chạy sau Cloudflare, hoặc proxy phải đặt header cf-connecting-ip.');

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...headers } });
}

const err = (status: number, code: string, message: string, extra: Record<string, unknown> = {}) => json(status, { error: code, message, ...extra });

async function readJson(req: Request): Promise<Record<string, unknown> | null> {
  // Từ chối sớm theo content-length, không đọc cả thân yêu cầu lớn vào bộ nhớ.
  if (Number(req.headers.get('content-length') ?? '0') > MAX_JSON_BYTES) return null;
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

/** authKey dạng base64 của đúng 32 byte; null nếu sai. */
function parseKey(v: unknown): Uint8Array | null {
  const s = str(v, 100);
  if (!s) return null;
  try {
    const k = fromBase64(s);
    return k.length === 32 ? k : null;
  } catch {
    return null;
  }
}

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  const { store, config } = deps;
  const now = deps.now ?? (() => Math.floor(Date.now() / 1000));
  const secret = utf8(config.tokenSecret);
  const registerCode = config.registerCode ?? '';
  const maxUsers = config.maxUsers && config.maxUsers > 0 ? config.maxUsers : DEFAULT_MAX_USERS;

  // ---------- Giới hạn tốc độ ----------

  async function lockedFor(key: string): Promise<number> {
    const a = await store.getAttempt(key);
    return a.lockedUntil > now() ? a.lockedUntil - now() : 0;
  }

  async function recordFailure(key: string, max: number): Promise<void> {
    // Đếm nguyên tử trong một câu lệnh: gửi song song nhiều yêu cầu cũng không lách được giới hạn.
    const count = await store.bumpFailure(key, now());
    // Dòng mới: tiện thể dọn các dòng cũ (chỉ chạy khi bảng có thể lớn thêm).
    if (count === 1) await store.purgeAttempts(now() - ATTEMPT_TTL);
    // Từ lần thứ `max`: khóa 30 s, rồi gấp đôi mỗi lần, tối đa 15 phút.
    // Khóa theo tài khoản tối đa ACCOUNT_LOCK_MAX giây, theo IP tối đa LOCK_MAX giây.
    const cap = key.startsWith('login:') ? ACCOUNT_LOCK_MAX : LOCK_MAX;
    if (count >= max) await store.lockUntil(key, now() + Math.min(cap, 30 * 2 ** (count - max)));
  }

  async function lockedResponse(keys: string[]): Promise<Response | null> {
    for (const k of keys) {
      const wait = await lockedFor(k);
      if (wait > 0) return err(429, 'locked', `Quá nhiều lần thử. Thử lại sau ${wait} giây.`, { retryAfter: wait });
    }
    return null;
  }

  // ---------- Phát token ----------

  async function issueSession(user: User, deviceName: string, existing?: Device): Promise<Response> {
    const refresh = toB64url(randomBytes(32));
    const refreshHash = toHex(await sha256(utf8(refresh)));
    const t = now();
    let deviceId: string;
    if (existing) {
      deviceId = existing.id;
      // Giữ hash của token vừa bị thay để phát hiện khi có người dùng lại nó (xem refresh()).
      await store.updateDevice(existing.id, { refreshHash, lastSeen: t, expiresAt: t + REFRESH_TTL, prevRefreshHash: existing.refreshHash });
    } else {
      // Giới hạn số thiết bị: gỡ thiết bị lâu không dùng nhất để không phình bảng.
      const active = await store.devicesOf(user.id);
      if (active.length >= MAX_DEVICES) {
        const oldest = [...active].sort((a, b) => a.lastSeen - b.lastSeen)[0];
        await store.updateDevice(oldest.id, { revoked: true });
      }
      deviceId = randomId();
      await store.createDevice({ id: deviceId, userId: user.id, name: deviceName, refreshHash, createdAt: t, lastSeen: t, expiresAt: t + REFRESH_TTL, revoked: false });
    }
    const accessToken = await signAccess(secret, { sub: user.id, dev: deviceId, exp: t + ACCESS_TTL });
    return json(200, { accessToken, refreshToken: refresh, expiresIn: ACCESS_TTL, deviceId, accountId: user.id, username: user.username });
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
    return { user, device };
  }

  // ---------- Kiểm tra authKey ----------

  /** So authKey với tài khoản. Luôn chạy PBKDF2 (kể cả khi không có tài khoản) để thời gian phản hồi không lộ tên có tồn tại. */
  async function checkKey(user: User | null, key: Uint8Array | null): Promise<boolean> {
    const salt = user?.salt ?? randomBytes(16);
    const hash = await pbkdf2(key ?? new Uint8Array(32), salt, user?.kdfIter ?? KDF_ITERATIONS);
    return !!user && !!key && user.pwHash.length === 32 && timingSafeEqual(hash, user.pwHash);
  }

  async function setKey(user: User, key: Uint8Array): Promise<void> {
    const salt = randomBytes(16);
    await store.setPassword(user.id, salt, await pbkdf2(key, salt, KDF_ITERATIONS), KDF_ITERATIONS);
  }

  /**
   * Xác nhận lại mật khẩu cho thao tác nhạy cảm (đổi mật khẩu, xóa tài khoản) dù đã có token:
   * token bị lộ không đủ để chiếm hay xóa tài khoản. Sai bị đếm và khóa như đăng nhập.
   */
  async function reauth(req: Request, user: User, authKey: unknown): Promise<Response | null> {
    const ip = clientIp(req);
    if (!ip) return noClientIp();
    const checks: [string, number][] = [
      [`ip:${ipKey(ip)}`, MAX_FAILURES_IP],
      [`login:${user.username}`, MAX_FAILURES_USER],
    ];
    const locked = await lockedResponse(checks.map(([k]) => k));
    if (locked) return locked;
    if (!(await checkKey(user, parseKey(authKey)))) {
      for (const [k, max] of checks) await recordFailure(k, max);
      return err(403, 'wrong_password', 'Mật khẩu hiện tại không đúng');
    }
    for (const [k] of checks) await store.clearAttempt(k);
    return null;
  }

  // ---------- Các route ----------

  async function register(req: Request): Promise<Response> {
    const rawIp = clientIp(req);
    if (!rawIp) return noClientIp();
    const body = await readJson(req);
    const rawName = str(body?.username);
    const authKey = str(body?.authKey, 100);
    if (!rawName || !authKey) return err(400, 'bad_request', 'Thiếu tên đăng nhập hoặc authKey');
    const username = normalizeUsername(rawName);
    if (!username) return err(400, 'bad_username', 'Tên đăng nhập gồm 3 đến 32 ký tự: chữ thường, số, dấu chấm, gạch dưới hoặc gạch ngang');
    const key = parseKey(authKey);
    if (!key) return err(400, 'bad_request', 'authKey phải là base64 của 32 byte');

    const ip = ipKey(rawIp);
    // Mỗi IP chỉ được đăng ký một số lần: chặn người lạ tạo hàng loạt tài khoản.
    const regKey = `reg:${ip}`;
    const regLocked = await lockedResponse([regKey]);
    if (regLocked) return regLocked;
    const tries = await store.bumpFailure(regKey, now());
    if (tries === 1) await store.purgeAttempts(now() - ATTEMPT_TTL);
    if (tries > REGISTER_PER_IP) {
      await store.lockUntil(regKey, now() + REGISTER_LOCK);
      return err(429, 'locked', `Đăng ký quá nhiều lần từ địa chỉ này. Thử lại sau ${REGISTER_LOCK} giây.`, { retryAfter: REGISTER_LOCK });
    }

    // Có đặt mã mời thì bắt buộc phải đúng; sai nhiều lần bị khóa theo IP.
    if (registerCode) {
      const ipk = `ip:${ip}`;
      const locked = await lockedResponse([ipk]);
      if (locked) return locked;
      const given = str(body?.registerCode, 200);
      const codeOk = registerCode.length >= MIN_REGISTER_CODE && !!given && timingSafeEqual(await sha256(utf8(given)), await sha256(utf8(registerCode)));
      if (!codeOk) {
        await recordFailure(ipk, MAX_FAILURES_IP);
        return err(403, 'forbidden', 'Mã mời không đúng, hoặc máy chủ đang đóng đăng ký');
      }
    }

    if ((await store.countUsers()) >= maxUsers) return err(403, 'full', 'Máy chủ đã đủ số tài khoản cho phép');

    const salt = randomBytes(16);
    const user: User = { id: randomId(), username, salt, pwHash: await pbkdf2(key, salt, KDF_ITERATIONS), kdfIter: KDF_ITERATIONS, createdAt: now() };
    if (!(await store.createUser(user))) return err(409, 'exists', 'Tên đăng nhập đã được dùng');
    return issueSession(user, str(body?.deviceName, 80) ?? 'Thiết bị');
  }

  async function login(req: Request): Promise<Response> {
    const rawIp = clientIp(req);
    if (!rawIp) return noClientIp();
    const body = await readJson(req);
    const rawName = str(body?.username);
    const authKey = str(body?.authKey, 100);
    if (!rawName || !authKey) return err(400, 'bad_request', 'Thiếu tên đăng nhập hoặc authKey');
    const username = normalizeUsername(rawName);
    const ip = ipKey(rawIp);
    const user = username ? await store.userByUsername(username) : null;
    // Khóa theo tài khoản chỉ khi tài khoản có thật: tên tùy ý của kẻ tấn công không tạo thêm dòng trong bảng.
    const checks: [string, number][] = [[`ip:${ip}`, MAX_FAILURES_IP]];
    if (user) checks.push([`login:${user.username}`, MAX_FAILURES_USER]);
    const locked = await lockedResponse(checks.map(([k]) => k));
    if (locked) return locked;

    const key = parseKey(authKey);
    const ok = await checkKey(user, key);
    if (!ok || !user || !key) {
      for (const [k, max] of checks) await recordFailure(k, max);
      return err(401, 'invalid_credentials', 'Tên đăng nhập hoặc mật khẩu không đúng');
    }
    for (const [k] of checks) await store.clearAttempt(k);
    // Tài khoản tạo với số vòng cũ: băm lại ngay lúc biết authKey đúng.
    if (user.kdfIter !== KDF_ITERATIONS) await setKey(user, key);
    return issueSession(user, str(body?.deviceName, 80) ?? 'Thiết bị');
  }

  async function refresh(req: Request): Promise<Response> {
    const body = await readJson(req);
    const token = str(body?.refreshToken, 200);
    if (!token) return err(400, 'bad_request', 'Thiếu refreshToken');
    const hash = toHex(await sha256(utf8(token)));
    const device = await store.deviceByRefreshHash(hash);
    if (!device) {
      // Token này đã được thay bằng token mới trước đó. Có người dùng lại token cũ
      // (bị đánh cắp, hoặc máy bị lỗi và gửi lại): gỡ thiết bị để buộc đăng nhập lại.
      const stale = await store.deviceByPrevRefreshHash(hash);
      if (stale && !stale.revoked) await store.updateDevice(stale.id, { revoked: true });
      return err(401, 'invalid_refresh', 'Refresh token không hợp lệ hoặc đã hết hạn');
    }
    // Hết hạn tuyệt đối: tính từ lúc đăng nhập, không gia hạn mãi bằng cách xoay vòng.
    if (device.revoked || device.expiresAt <= now() || device.createdAt + REFRESH_TTL <= now()) {
      await store.updateDevice(device.id, { revoked: true });
      return err(401, 'invalid_refresh', 'Refresh token không hợp lệ hoặc đã hết hạn');
    }
    const user = await store.userById(device.userId);
    if (!user) return err(401, 'invalid_refresh', 'Tài khoản không còn hợp lệ');
    // Xoay vòng: token cũ không dùng lại được (và bị phát hiện nếu dùng lại).
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
      if (path === '/auth/refresh' && m === 'POST') return await refresh(req);

      // Từ đây cần đăng nhập
      if (path === '/auth/logout' || path === '/auth/password' || path === '/account' || path === '/devices' || path.startsWith('/devices/') || path === '/vault') {
        const a = await authenticate(req);
        if (a instanceof Response) return a;
        const { user, device } = a;

        if (path === '/auth/logout' && m === 'POST') {
          await store.updateDevice(device.id, { revoked: true });
          return new Response(null, { status: 204 });
        }

        // Đổi mật khẩu: {authKey: hiện tại, newAuthKey}. Gỡ các thiết bị khác (phải đăng nhập lại bằng mật khẩu mới).
        if (path === '/auth/password' && m === 'POST') {
          const body = await readJson(req);
          const next = parseKey(body?.newAuthKey);
          if (!next) return err(400, 'bad_request', 'newAuthKey phải là base64 của 32 byte');
          const denied = await reauth(req, user, body?.authKey);
          if (denied) return denied;
          await setKey(user, next);
          await store.revokeDevicesExcept(user.id, device.id);
          return new Response(null, { status: 204 });
        }

        // Xóa hẳn tài khoản, kho và mọi thiết bị: {authKey}. Không hoàn tác được.
        if (path === '/account' && m === 'DELETE') {
          const body = await readJson(req);
          const denied = await reauth(req, user, body?.authKey);
          if (denied) return denied;
          await store.deleteUser(user.id);
          await store.clearAttempt(`login:${user.username}`);
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
