import assert from 'node:assert/strict';
import { generateKeyPairSync, createSign } from 'node:crypto';
import { test } from 'node:test';
import { createHandler, ACCESS_TTL, MAX_VAULT_BYTES } from '../src/handler.ts';
import type { Config } from '../src/handler.ts';
import { MemoryStore } from '../src/memory_store.ts';
import { toBase64, randomBytes } from '../src/util.ts';

const SECRET = 'test-secret-test-secret-test-secret-0123456789';
const EMAIL = 'me@example.com';

function setup(over: Partial<Config> = {}, jwks?: () => Promise<any[]>) {
  const store = new MemoryStore();
  let t = 1_700_000_000;
  const clock = { advance: (s: number) => (t += s) };
  const handler = createHandler({
    store,
    config: { allowedEmails: EMAIL, tokenSecret: SECRET, ...over },
    now: () => t,
    jwks,
  });
  async function call(method: string, path: string, opts: { body?: unknown; token?: string; headers?: Record<string, string>; raw?: Uint8Array } = {}) {
    const headers: Record<string, string> = { ...(opts.headers ?? {}) };
    if (opts.token) headers.authorization = `Bearer ${opts.token}`;
    let body: BodyInit | undefined;
    if (opts.raw) body = opts.raw as BodyInit;
    else if (opts.body !== undefined) {
      headers['content-type'] = 'application/json';
      body = JSON.stringify(opts.body);
    }
    return handler(new Request(`http://x${path}`, { method, headers, body }));
  }
  return { store, call, clock };
}

const authKey = (seed = 1) => toBase64(new Uint8Array(32).fill(seed));
const vaultBytes = (n = 100, fill = 7) => new Uint8Array(n).fill(fill);

async function register(s: ReturnType<typeof setup>, email = EMAIL, key = authKey()) {
  const r = await s.call('POST', '/auth/register', { body: { email, authKey: key, deviceName: 'Điện thoại' } });
  return { res: r, body: r.status === 200 ? ((await r.json()) as any) : null };
}

test('đăng ký rồi đăng nhập thêm thiết bị thứ hai', async () => {
  const s = setup();
  const a = await register(s);
  assert.equal(a.res.status, 200);
  assert.ok(a.body.accessToken && a.body.refreshToken && a.body.deviceId);

  const l = await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey(), deviceName: 'Máy tính' } });
  assert.equal(l.status, 200);
  const b = (await l.json()) as any;
  assert.notEqual(b.deviceId, a.body.deviceId);
  assert.equal(b.accountId, a.body.accountId);

  const d = await s.call('GET', '/devices', { token: b.accessToken });
  const devices = ((await d.json()) as any).devices;
  assert.equal(devices.length, 2);
  assert.equal(devices.filter((x: any) => x.current).length, 1);
});

test('email ngoài danh sách cho phép bị từ chối; danh sách rỗng từ chối tất cả', async () => {
  const s = setup();
  assert.equal((await register(s, 'khac@example.com')).res.status, 403);
  const closed = setup({ allowedEmails: '' });
  assert.equal((await register(closed)).res.status, 403);
});

test('email không phân biệt hoa thường; đăng ký trùng bị từ chối', async () => {
  const s = setup();
  assert.equal((await register(s, 'ME@Example.com')).res.status, 200);
  assert.equal((await register(s, EMAIL)).res.status, 409);
});

test('sai mật khẩu và email không tồn tại cho cùng một thông báo (không lộ email nào có tài khoản)', async () => {
  const s = setup();
  await register(s);
  const wrong = await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey(9) } });
  const nobody = await s.call('POST', '/auth/login', { body: { email: 'khong-co@example.com', authKey: authKey() } });
  assert.equal(wrong.status, 401);
  assert.equal(nobody.status, 401);
  assert.deepEqual(await wrong.json(), await nobody.json());
});

test('đăng nhập sai liên tiếp bị khóa tăng dần; đúng thì mở và đếm lại từ đầu', async () => {
  const s = setup();
  await register(s);
  for (let i = 0; i < 4; i++) assert.equal((await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey(9) } })).status, 401);
  assert.equal((await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey(9) } })).status, 401); // lần 5: bắt đầu khóa
  const locked = await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey() } });
  assert.equal(locked.status, 429, 'đang khóa thì ngay cả mật khẩu đúng cũng phải chờ');
  assert.ok(((await locked.json()) as any).retryAfter > 0);

  s.clock.advance(31);
  const ok = await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey() } });
  assert.equal(ok.status, 200);
  // Đã xóa bộ đếm: sai một lần không bị khóa ngay.
  assert.equal((await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey(9) } })).status, 401);
  assert.equal((await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey() } })).status, 200);
});

test('refresh xoay vòng: token cũ không dùng lại được', async () => {
  const s = setup();
  const { body } = await register(s);
  const r1 = await s.call('POST', '/auth/refresh', { body: { refreshToken: body.refreshToken } });
  assert.equal(r1.status, 200);
  const n = (await r1.json()) as any;
  assert.notEqual(n.refreshToken, body.refreshToken);
  assert.equal(n.deviceId, body.deviceId);

  const reuse = await s.call('POST', '/auth/refresh', { body: { refreshToken: body.refreshToken } });
  assert.equal(reuse.status, 401);
  assert.equal((await s.call('POST', '/auth/refresh', { body: { refreshToken: n.refreshToken } })).status, 200);
});

test('access token hết hạn bị từ chối, refresh cấp token mới', async () => {
  const s = setup();
  const { body } = await register(s);
  assert.equal((await s.call('GET', '/devices', { token: body.accessToken })).status, 200);
  s.clock.advance(ACCESS_TTL + 1);
  assert.equal((await s.call('GET', '/devices', { token: body.accessToken })).status, 401);
  const r = (await (await s.call('POST', '/auth/refresh', { body: { refreshToken: body.refreshToken } })).json()) as any;
  assert.equal((await s.call('GET', '/devices', { token: r.accessToken })).status, 200);
});

test('refresh token hết hạn (90 ngày) bị từ chối', async () => {
  const s = setup();
  const { body } = await register(s);
  s.clock.advance(91 * 24 * 3600);
  assert.equal((await s.call('POST', '/auth/refresh', { body: { refreshToken: body.refreshToken } })).status, 401);
});

test('token giả hoặc bị sửa bị từ chối', async () => {
  const s = setup();
  const { body } = await register(s);
  const [p, sig] = body.accessToken.split('.');
  assert.equal((await s.call('GET', '/devices', { token: `${p}.${sig.slice(0, -2)}AA` })).status, 401);
  assert.equal((await s.call('GET', '/devices', { token: 'abc.def' })).status, 401);
  assert.equal((await s.call('GET', '/devices')).status, 401);
});

test('thu hồi thiết bị: thiết bị đó mất quyền NGAY, kể cả access token còn hạn và refresh token', async () => {
  const s = setup();
  const a = (await register(s)).body;
  const b = (await (await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey(), deviceName: 'Máy khác' } })).json()) as any;

  const del = await s.call('DELETE', `/devices/${b.deviceId}`, { token: a.accessToken });
  assert.equal(del.status, 204);

  assert.equal((await s.call('GET', '/vault', { token: b.accessToken })).status, 401);
  assert.equal((await s.call('POST', '/auth/refresh', { body: { refreshToken: b.refreshToken } })).status, 401);
  assert.equal((await s.call('GET', '/devices', { token: a.accessToken })).status, 200);
});

test('không gỡ được thiết bị của người khác; gỡ id lạ cho 404', async () => {
  const s = setup({ allowedEmails: `${EMAIL},kia@example.com` });
  const a = (await register(s)).body;
  const other = (await register(s, 'kia@example.com', authKey(2))).body;
  assert.equal((await s.call('DELETE', `/devices/${other.deviceId}`, { token: a.accessToken })).status, 404);
  assert.equal((await s.call('DELETE', '/devices/khong-co', { token: a.accessToken })).status, 404);
  assert.equal((await s.call('GET', '/devices', { token: other.accessToken })).status, 200);
});

test('đăng xuất thu hồi thiết bị hiện tại', async () => {
  const s = setup();
  const a = (await register(s)).body;
  assert.equal((await s.call('POST', '/auth/logout', { token: a.accessToken })).status, 204);
  assert.equal((await s.call('GET', '/devices', { token: a.accessToken })).status, 401);
});

test('email bị bỏ khỏi danh sách cho phép: token cũ cũng hết hiệu lực', async () => {
  const s = setup();
  const a = (await register(s)).body;
  const h = createHandler({ store: s.store, config: { allowedEmails: 'nguoi-khac@example.com', tokenSecret: SECRET }, now: () => 1_700_000_000 });
  const r = await h(new Request('http://x/devices', { headers: { authorization: `Bearer ${a.accessToken}` } }));
  assert.equal(r.status, 403);
});

test('kho: chưa có → 404; tạo mới → v1; đọc lại đúng byte và ETag', async () => {
  const s = setup();
  const a = (await register(s)).body;
  assert.equal((await s.call('GET', '/vault', { token: a.accessToken })).status, 404);

  const put = await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: vaultBytes(100, 5) });
  assert.equal(put.status, 200);
  assert.equal(put.headers.get('etag'), '"v1"');

  const get = await s.call('GET', '/vault', { token: a.accessToken });
  assert.equal(get.status, 200);
  assert.equal(get.headers.get('etag'), '"v1"');
  assert.deepEqual(new Uint8Array(await get.arrayBuffer()), vaultBytes(100, 5));

  const cached = await s.call('GET', '/vault', { token: a.accessToken, headers: { 'if-none-match': '"v1"' } });
  assert.equal(cached.status, 304);
});

test('kho: If-Match đúng → tăng phiên bản; lệch → 409 kèm phiên bản hiện tại và không ghi đè', async () => {
  const s = setup();
  const a = (await register(s)).body;
  await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: vaultBytes(64, 1) });

  const ok = await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-match': '"v1"' }, raw: vaultBytes(64, 2) });
  assert.equal(ok.status, 200);
  assert.equal(((await ok.json()) as any).version, 2);

  const stale = await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-match': '"v1"' }, raw: vaultBytes(64, 3) });
  assert.equal(stale.status, 409);
  assert.equal(((await stale.json()) as any).version, 2);

  const now = await s.call('GET', '/vault', { token: a.accessToken });
  assert.deepEqual(new Uint8Array(await now.arrayBuffer()), vaultBytes(64, 2));
});

test('kho: tạo mới khi đã có → 409; thiếu điều kiện → 428; quá lớn → 413; quá ngắn → 400', async () => {
  const s = setup();
  const a = (await register(s)).body;
  await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: vaultBytes(64) });
  assert.equal((await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: vaultBytes(64) })).status, 409);
  assert.equal((await s.call('PUT', '/vault', { token: a.accessToken, raw: vaultBytes(64) })).status, 428);
  assert.equal((await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-match': '"v1"' }, raw: vaultBytes(MAX_VAULT_BYTES + 1) })).status, 413);
  assert.equal((await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-match': '"v1"' }, raw: vaultBytes(5) })).status, 400);
});

test('hai máy ghi cùng lúc: đúng một máy thắng, máy kia nhận 409', async () => {
  const s = setup();
  const a = (await register(s)).body;
  await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: vaultBytes(64, 1) });
  const [x, y] = await Promise.all([
    s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-match': '"v1"' }, raw: vaultBytes(64, 2) }),
    s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-match': '"v1"' }, raw: vaultBytes(64, 3) }),
  ]);
  assert.deepEqual([x.status, y.status].sort(), [200, 409]);
});

test('kho của mỗi tài khoản tách biệt', async () => {
  const s = setup({ allowedEmails: `${EMAIL},kia@example.com` });
  const a = (await register(s)).body;
  const b = (await register(s, 'kia@example.com', authKey(2))).body;
  await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: vaultBytes(64, 1) });
  assert.equal((await s.call('GET', '/vault', { token: b.accessToken })).status, 404);
});

test('đầu vào rác không làm sập: JSON hỏng, thiếu trường, authKey sai độ dài, đường dẫn lạ', async () => {
  const s = setup();
  const bad = await s.call('POST', '/auth/register', { raw: new TextEncoder().encode('{không phải json'), headers: { 'content-type': 'application/json' } });
  assert.equal(bad.status, 400);
  assert.equal((await s.call('POST', '/auth/register', { body: { email: EMAIL } })).status, 400);
  assert.equal((await s.call('POST', '/auth/register', { body: { email: EMAIL, authKey: 'abc' } })).status, 400);
  assert.equal((await s.call('POST', '/auth/register', { body: { email: EMAIL, authKey: '***không-phải-base64***' } })).status, 400);
  assert.equal((await s.call('POST', '/auth/login', { body: { email: 123, authKey: [] } })).status, 400);
  assert.equal((await s.call('GET', '/khong-co')).status, 404);
  assert.equal((await s.call('GET', '/')).status, 200);
});

test('mật khẩu gốc/authKey không bao giờ nằm trong dữ liệu lưu (chỉ có hash)', async () => {
  const s = setup();
  const key = authKey(42);
  await register(s, EMAIL, key);
  const u = [...s.store.users.values()][0];
  const dump = JSON.stringify([...u.pwHash!]) + JSON.stringify([...u.salt!]);
  assert.ok(!dump.includes(JSON.stringify([...new Uint8Array(32).fill(42)])), 'authKey gốc xuất hiện trong dữ liệu lưu');
  assert.equal(u.pwHash!.length, 32);
  const d = [...s.store.devices.values()][0];
  assert.ok(/^[0-9a-f]{64}$/.test(d.refreshHash), 'chỉ lưu hash của refresh token');
});

// ---------------- Đăng nhập Google ----------------

function makeGoogle(claims: Record<string, unknown>, opts: { kid?: string; tamper?: boolean } = {}) {
  const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = publicKey.export({ format: 'jwk' }) as { n: string; e: string };
  const kid = opts.kid ?? 'k1';
  const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const header = b64({ alg: 'RS256', kid, typ: 'JWT' });
  const payload = b64(claims);
  const sig = createSign('RSA-SHA256').update(`${header}.${payload}`).sign(privateKey).toString('base64url');
  const token = `${header}.${opts.tamper ? b64({ ...claims, email: 'ke-gian@example.com' }) : payload}.${sig}`;
  return { token, jwks: async () => [{ kid, kty: 'RSA', alg: 'RS256', n: jwk.n, e: jwk.e }] };
}

const AUD = 'my-client.apps.googleusercontent.com';
const goodClaims = (now = 1_700_000_000) => ({ iss: 'https://accounts.google.com', aud: AUD, sub: 'g-123', email: EMAIL, email_verified: true, exp: now + 3600 });

test('Google: token hợp lệ tạo tài khoản và phát phiên', async () => {
  const g = makeGoogle(goodClaims());
  const s = setup({ googleClientIds: AUD }, g.jwks);
  const r = await s.call('POST', '/auth/google', { body: { idToken: g.token, deviceName: 'Android' } });
  assert.equal(r.status, 200);
  const b = (await r.json()) as any;
  assert.equal(b.email, EMAIL);
  assert.equal((await s.call('GET', '/devices', { token: b.accessToken })).status, 200);
  // lần sau cùng tài khoản
  const r2 = (await (await s.call('POST', '/auth/google', { body: { idToken: g.token } })).json()) as any;
  assert.equal(r2.accountId, b.accountId);
});

for (const [name, claims, opts] of [
  ['sai aud', { ...goodClaims(), aud: 'client-cua-nguoi-khac' }, {}],
  ['sai iss', { ...goodClaims(), iss: 'https://evil.example.com' }, {}],
  ['đã hết hạn', { ...goodClaims(), exp: 1_699_999_000 }, {}],
  ['email chưa xác minh', { ...goodClaims(), email_verified: false }, {}],
  ['payload bị sửa sau khi ký', goodClaims(), { tamper: true }],
  ['kid không có trong JWKS', goodClaims(), { kid: 'k-la' }],
] as const) {
  test(`Google: từ chối token ${name}`, async () => {
    const g = makeGoogle(claims as Record<string, unknown>, opts as { kid?: string; tamper?: boolean });
    const s = setup({ googleClientIds: AUD }, opts.kid ? async () => [{ kid: 'k1', kty: 'RSA', n: 'x', e: 'AQAB' }] : g.jwks);
    const r = await s.call('POST', '/auth/google', { body: { idToken: g.token } });
    assert.equal(r.status, 401);
  });
}

test('Google: email ngoài danh sách cho phép bị từ chối dù token hợp lệ; tắt khi chưa cấu hình', async () => {
  const g = makeGoogle({ ...goodClaims(), email: 'la@example.com' });
  const s = setup({ googleClientIds: AUD }, g.jwks);
  assert.equal((await s.call('POST', '/auth/google', { body: { idToken: g.token } })).status, 403);
  const off = setup({}, g.jwks);
  assert.equal((await off.call('POST', '/auth/google', { body: { idToken: g.token } })).status, 404);
});

test('tài khoản chỉ đăng nhập Google không đăng nhập được bằng mật khẩu', async () => {
  const g = makeGoogle(goodClaims());
  const s = setup({ googleClientIds: AUD }, g.jwks);
  await s.call('POST', '/auth/google', { body: { idToken: g.token } });
  assert.equal((await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: authKey() } })).status, 401);
});

test('MemoryStore nguyên tử: tạo kho đồng thời chỉ một bên thành công', async () => {
  const store = new MemoryStore();
  const [a, b] = await Promise.all([store.putVault('u', null, randomBytes(40), 1), store.putVault('u', null, randomBytes(40), 1)]);
  assert.equal([a, b].filter((r) => r.ok).length, 1);
});
