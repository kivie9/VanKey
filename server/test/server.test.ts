import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHandler, ACCESS_TTL, MAX_VAULT_BYTES } from '../src/handler.ts';
import type { Config } from '../src/handler.ts';
import { MemoryStore } from '../src/memory_store.ts';
import { toBase64, randomBytes } from '../src/util.ts';

const SECRET = 'test-secret-test-secret-test-secret-0123456789';
const USER = 'minh.van';
const CODE = 'ma-moi-thu-nghiem-1';

function setup(over: Partial<Config> = {}) {
  const store = new MemoryStore();
  let t = 1_700_000_000;
  const clock = { advance: (s: number) => (t += s) };
  const handler = createHandler({
    store,
    config: { tokenSecret: SECRET, ...over },
    now: () => t,
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

async function register(s: ReturnType<typeof setup>, username = USER, key = authKey()) {
  const r = await s.call('POST', '/auth/register', { body: { username, authKey: key, deviceName: 'Điện thoại' } });
  return { res: r, body: r.status === 200 ? ((await r.json()) as any) : null };
}

test('đăng ký rồi đăng nhập thêm thiết bị thứ hai', async () => {
  const s = setup();
  const a = await register(s);
  assert.equal(a.res.status, 200);
  assert.ok(a.body.accessToken && a.body.refreshToken && a.body.deviceId);

  const l = await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(), deviceName: 'Máy tính' } });
  assert.equal(l.status, 200);
  const b = (await l.json()) as any;
  assert.notEqual(b.deviceId, a.body.deviceId);
  assert.equal(b.accountId, a.body.accountId);

  const d = await s.call('GET', '/devices', { token: b.accessToken });
  const devices = ((await d.json()) as any).devices;
  assert.equal(devices.length, 2);
  assert.equal(devices.filter((x: any) => x.current).length, 1);
});

test('tên đăng nhập không phân biệt hoa thường; đăng ký trùng bị từ chối', async () => {
  const s = setup();
  assert.equal((await register(s, 'MINH.Van')).res.status, 200);
  assert.equal((await register(s, USER)).res.status, 409);
});

test('sai mật khẩu và tên không tồn tại cho cùng một thông báo (không lộ tên nào có tài khoản)', async () => {
  const s = setup();
  await register(s);
  const wrong = await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(9) } });
  const nobody = await s.call('POST', '/auth/login', { body: { username: 'khong.co', authKey: authKey() } });
  assert.equal(wrong.status, 401);
  assert.equal(nobody.status, 401);
  assert.deepEqual(await wrong.json(), await nobody.json());
});

test('đăng nhập sai liên tiếp bị khóa tăng dần; đúng thì mở và đếm lại từ đầu', async () => {
  const s = setup();
  await register(s);
  for (let i = 0; i < 4; i++) assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(9) } })).status, 401);
  assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(9) } })).status, 401); // lần 5: bắt đầu khóa
  const locked = await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey() } });
  assert.equal(locked.status, 429, 'đang khóa thì ngay cả mật khẩu đúng cũng phải chờ');
  assert.ok(((await locked.json()) as any).retryAfter > 0);

  s.clock.advance(31);
  const ok = await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey() } });
  assert.equal(ok.status, 200);
  // Đã xóa bộ đếm: sai một lần không bị khóa ngay.
  assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(9) } })).status, 401);
  assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey() } })).status, 200);
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
  const b = (await (await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(), deviceName: 'Máy khác' } })).json()) as any;

  const del = await s.call('DELETE', `/devices/${b.deviceId}`, { token: a.accessToken });
  assert.equal(del.status, 204);

  assert.equal((await s.call('GET', '/vault', { token: b.accessToken })).status, 401);
  assert.equal((await s.call('POST', '/auth/refresh', { body: { refreshToken: b.refreshToken } })).status, 401);
  assert.equal((await s.call('GET', '/devices', { token: a.accessToken })).status, 200);
});

test('không gỡ được thiết bị của người khác; gỡ id lạ cho 404', async () => {
  const s = setup();
  const a = (await register(s)).body;
  const other = (await register(s, 'kia.nguyen', authKey(2))).body;
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
  const s = setup();
  const a = (await register(s)).body;
  const b = (await register(s, 'kia.nguyen', authKey(2))).body;
  await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: vaultBytes(64, 1) });
  assert.equal((await s.call('GET', '/vault', { token: b.accessToken })).status, 404);
});

test('đầu vào rác không làm sập: JSON hỏng, thiếu trường, authKey sai độ dài, đường dẫn lạ', async () => {
  const s = setup();
  const bad = await s.call('POST', '/auth/register', { raw: new TextEncoder().encode('{không phải json'), headers: { 'content-type': 'application/json' } });
  assert.equal(bad.status, 400);
  assert.equal((await s.call('POST', '/auth/register', { body: { username: USER } })).status, 400);
  assert.equal((await s.call('POST', '/auth/register', { body: { username: USER, authKey: 'abc' } })).status, 400);
  assert.equal((await s.call('POST', '/auth/register', { body: { username: USER, authKey: '***không-phải-base64***' } })).status, 400);
  assert.equal((await s.call('POST', '/auth/login', { body: { username: 123, authKey: [] } })).status, 400);
  assert.equal((await s.call('GET', '/khong-co')).status, 404);
  assert.equal((await s.call('GET', '/')).status, 200);
});

test('mật khẩu gốc/authKey không bao giờ nằm trong dữ liệu lưu (chỉ có hash)', async () => {
  const s = setup();
  const key = authKey(42);
  await register(s, USER, key);
  const u = [...s.store.users.values()][0];
  const dump = JSON.stringify([...u.pwHash!]) + JSON.stringify([...u.salt!]);
  assert.ok(!dump.includes(JSON.stringify([...new Uint8Array(32).fill(42)])), 'authKey gốc xuất hiện trong dữ liệu lưu');
  assert.equal(u.pwHash!.length, 32);
  const d = [...s.store.devices.values()][0];
  assert.ok(/^[0-9a-f]{64}$/.test(d.refreshHash), 'chỉ lưu hash của refresh token');
});

test('MemoryStore nguyên tử: tạo kho đồng thời chỉ một bên thành công', async () => {
  const store = new MemoryStore();
  const [a, b] = await Promise.all([store.putVault('u', null, randomBytes(40), 1), store.putVault('u', null, randomBytes(40), 1)]);
  assert.equal([a, b].filter((r) => r.ok).length, 1);
});

// ---------------- Đăng ký mở, có giới hạn ----------------

const reg = (s: ReturnType<typeof setup>, body: Record<string, unknown>, ip = '203.0.113.1') =>
  s.call('POST', '/auth/register', { body: { authKey: authKey(), ...body }, headers: { 'cf-connecting-ip': ip } });

test('ai cũng đăng ký được khi không đặt mã mời; tên đăng nhập được chuẩn hóa', async () => {
  const s = setup();
  const r = await reg(s, { username: '  Nguoi.Moi_01 ' });
  assert.equal(r.status, 200);
  assert.equal(((await r.json()) as any).username, 'nguoi.moi_01');
  assert.equal((await reg(s, { username: 'NGUOI.MOI_01' })).status, 409);
});

test('tên đăng nhập sai quy tắc bị từ chối bằng 400', async () => {
  const s = setup();
  for (const bad of ['ab', 'a'.repeat(33), 'có dấu', 'user name', 'x@y.com', '-bat-dau', '.bat-dau', 'a/b/c', '<script>']) {
    const r = await reg(s, { username: bad });
    assert.equal(r.status, 400, bad);
  }
  assert.equal(s.store.users.size, 0);
  assert.equal((await reg(s, { username: 'a-b_c.d9' })).status, 200);
});

test('đặt mã mời thì bắt buộc: thiếu hoặc sai bị từ chối và không tạo tài khoản', async () => {
  const s = setup({ registerCode: CODE });
  assert.equal((await reg(s, { username: 'an' + 'h1' })).status, 403);
  assert.equal((await reg(s, { username: 'anh1', registerCode: 'sai-ma-moi-nhe-xxx' })).status, 403);
  assert.equal(s.store.users.size, 0);
  assert.equal((await reg(s, { username: 'anh1', registerCode: CODE })).status, 200);
});

test('mã mời đặt quá ngắn thì đóng đăng ký, kể cả khi gửi đúng mã đó', async () => {
  const s = setup({ registerCode: 'ngan' });
  assert.equal((await reg(s, { username: 'anh1', registerCode: 'ngan' })).status, 403);
  assert.equal(s.store.users.size, 0);
});

test('mã mời sai nhiều lần bị khóa theo IP; đúng mã cũng phải chờ', async () => {
  const s = setup({ registerCode: CODE });
  for (let i = 0; i < 5; i++) assert.equal((await reg(s, { username: 'anh1', registerCode: `doan-sai-so-${i}-xxxx` }, '198.51.100.9')).status, 403);
  assert.equal((await reg(s, { username: 'anh1', registerCode: CODE }, '198.51.100.9')).status, 429);
  s.clock.advance(31);
  assert.equal((await reg(s, { username: 'anh1', registerCode: CODE }, '198.51.100.9')).status, 200);
});

test('mỗi IP chỉ đăng ký được một số lần, quá thì khóa 1 giờ; IP khác không bị ảnh hưởng', async () => {
  const s = setup();
  for (let i = 0; i < 10; i++) assert.equal((await reg(s, { username: `nguoi${i}` }, '192.0.2.50')).status, 200);
  const blocked = await reg(s, { username: 'nguoi-11' }, '192.0.2.50');
  assert.equal(blocked.status, 429);
  assert.equal(((await blocked.json()) as any).retryAfter, 3600);
  assert.equal((await reg(s, { username: 'nguoi-11' }, '192.0.2.50')).status, 429);
  assert.equal((await reg(s, { username: 'nguoi-11' }, '192.0.2.51')).status, 200);
  s.clock.advance(3601);
  assert.equal(s.store.users.size, 11);
});

test('đạt số tài khoản tối đa thì ngừng nhận đăng ký mới nhưng người cũ vẫn đăng nhập được', async () => {
  const s = setup({ maxUsers: 2 });
  assert.equal((await reg(s, { username: 'mot' }, '10.0.0.1')).status, 200);
  assert.equal((await reg(s, { username: 'hai' }, '10.0.0.2')).status, 200);
  const full = await reg(s, { username: 'bon' }, '10.0.0.3');
  assert.equal(full.status, 403);
  assert.equal(((await full.json()) as any).error, 'full');
  assert.equal((await s.call('POST', '/auth/login', { body: { username: 'mot', authKey: authKey() } })).status, 200);
});

test('mỗi tài khoản có tối đa 20 thiết bị; thiết bị lâu không dùng nhất bị gỡ', async () => {
  const s = setup();
  const first = (await register(s)).body;
  for (let i = 0; i < 19; i++) {
    s.clock.advance(1);
    assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(), deviceName: `M${i}` } })).status, 200);
  }
  assert.equal(s.store.devices.size, 20);
  s.clock.advance(1);
  const extra = (await (await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(), deviceName: 'Máy 21' } })).json()) as any;
  const active = [...s.store.devices.values()].filter((d) => !d.revoked);
  assert.equal(active.length, 20);
  assert.equal(s.store.devices.get(first.deviceId)!.revoked, true, 'máy cũ nhất bị gỡ');
  assert.equal(s.store.devices.get(extra.deviceId)!.revoked, false);
});

test('đăng nhập sai bằng tên không có thật không tạo dòng theo tên, chỉ theo IP', async () => {
  const s = setup();
  const ip = { 'cf-connecting-ip': '203.0.113.5' };
  for (let i = 0; i < 30; i++) await s.call('POST', '/auth/login', { body: { username: `ngau-nhien-${i}`, authKey: authKey(9) }, headers: ip });
  assert.deepEqual([...s.store.attempts.keys()], ['ip:203.0.113.5']);
});

test('khóa theo tài khoản có ngưỡng cao: vài lần sai từ nhiều IP không khóa chủ tài khoản', async () => {
  const s = setup();
  await register(s);
  for (let i = 0; i < 15; i++) {
    await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(9) }, headers: { 'cf-connecting-ip': `198.51.100.${i + 1}` } });
  }
  const r = await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey() }, headers: { 'cf-connecting-ip': '203.0.113.200' } });
  assert.equal(r.status, 200);
});

test('khóa theo tài khoản vẫn có tác dụng khi bị dò từ rất nhiều IP (từ lần thứ 20)', async () => {
  const s = setup();
  await register(s);
  for (let i = 0; i < 20; i++) {
    await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey(9) }, headers: { 'cf-connecting-ip': `198.51.100.${i + 1}` } });
  }
  const r = await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey() }, headers: { 'cf-connecting-ip': '203.0.113.201' } });
  assert.equal(r.status, 429);
});

test('địa chỉ IPv6 trong cùng một dải /64 dùng chung giới hạn', async () => {
  const s = setup();
  for (let i = 0; i < 5; i++) {
    await s.call('POST', '/auth/login', { body: { username: 'la.hoac', authKey: authKey(9) }, headers: { 'cf-connecting-ip': `2001:db8:1:2::${i + 1}` } });
  }
  const r = await s.call('POST', '/auth/login', { body: { username: 'la.hoac', authKey: authKey(9) }, headers: { 'cf-connecting-ip': '2001:db8:1:2:aaaa:bbbb:cccc:dddd' } });
  assert.equal(r.status, 429);
  const other = await s.call('POST', '/auth/login', { body: { username: 'la.hoac', authKey: authKey(9) }, headers: { 'cf-connecting-ip': '2001:db8:1:3::1' } });
  assert.equal(other.status, 401);
});

test('MemoryStore: đếm lần sai song song và dọn dòng cũ', async () => {
  const s = new MemoryStore();
  const counts = await Promise.all(Array.from({ length: 10 }, () => s.bumpFailure('k', 100)));
  assert.deepEqual([...counts].sort((a, b) => a - b), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  await s.purgeAttempts(101);
  assert.equal(s.attempts.size, 0);
});

// ---------- Đổi mật khẩu, xóa tài khoản, số vòng PBKDF2 ----------

import { KDF_ITERATIONS } from '../src/handler.ts';
import { pbkdf2 } from '../src/util.ts';

const login = (s: ReturnType<typeof setup>, key: string, deviceName = 'Máy khác') =>
  s.call('POST', '/auth/login', { body: { username: USER, authKey: key, deviceName } });

test('đổi mật khẩu: cần đúng mật khẩu hiện tại; sau đó chỉ mật khẩu mới đăng nhập được; thiết bị khác bị gỡ, thiết bị này vẫn dùng tiếp', async () => {
  const s = setup();
  const a = (await register(s)).body;
  const other = (await (await login(s, authKey())).json()) as any;

  const bad = await s.call('POST', '/auth/password', { token: a.accessToken, body: { authKey: authKey(9), newAuthKey: authKey(2) } });
  assert.equal(bad.status, 403);
  assert.equal((await login(s, authKey())).status, 200, 'sai mật khẩu hiện tại thì không đổi gì');

  const ok = await s.call('POST', '/auth/password', { token: a.accessToken, body: { authKey: authKey(), newAuthKey: authKey(2) } });
  assert.equal(ok.status, 204);
  assert.equal((await login(s, authKey())).status, 401);
  assert.equal((await login(s, authKey(2))).status, 200);
  assert.equal((await s.call('GET', '/vault', { token: other.accessToken })).status, 401, 'thiết bị khác bị gỡ ngay');
  assert.equal((await s.call('GET', '/vault', { token: a.accessToken })).status, 404, 'thiết bị đang đổi vẫn dùng được (chưa có kho → 404)');
});

test('đổi mật khẩu: thiếu token → 401; newAuthKey sai độ dài → 400; sai mật khẩu nhiều lần bị khóa', async () => {
  const s = setup();
  const a = (await register(s)).body;
  assert.equal((await s.call('POST', '/auth/password', { body: { authKey: authKey(), newAuthKey: authKey(2) } })).status, 401);
  assert.equal((await s.call('POST', '/auth/password', { token: a.accessToken, body: { authKey: authKey(), newAuthKey: 'YWJj' } })).status, 400);
  for (let i = 0; i < 5; i++) await s.call('POST', '/auth/password', { token: a.accessToken, body: { authKey: authKey(9), newAuthKey: authKey(2) } });
  const locked = await s.call('POST', '/auth/password', { token: a.accessToken, body: { authKey: authKey(), newAuthKey: authKey(2) } });
  assert.equal(locked.status, 429, 'token bị lộ cũng không dò được mật khẩu');
});

test('xóa tài khoản: cần đúng mật khẩu; xóa hẳn kho, thiết bị, tài khoản; tên đăng nhập dùng lại được', async () => {
  const s = setup();
  const a = (await register(s)).body;
  await s.call('PUT', '/vault', { token: a.accessToken, raw: vaultBytes(), headers: { 'if-none-match': '*' } });

  assert.equal((await s.call('DELETE', '/account', { token: a.accessToken, body: { authKey: authKey(9) } })).status, 403);
  assert.equal(s.store.users.size, 1);

  assert.equal((await s.call('DELETE', '/account', { token: a.accessToken, body: { authKey: authKey() } })).status, 204);
  assert.equal(s.store.users.size, 0);
  assert.equal(s.store.vaults.size, 0);
  assert.equal(s.store.devices.size, 0);
  assert.equal((await s.call('GET', '/vault', { token: a.accessToken })).status, 401);
  assert.equal((await login(s, authKey())).status, 401);
  assert.equal((await register(s)).res.status, 200, 'tên đã giải phóng');
});

test('tài khoản mới dùng số vòng PBKDF2 nhỏ; tài khoản cũ 100000 vòng được băm lại khi đăng nhập đúng', async () => {
  const s = setup();
  const a = (await register(s)).body;
  assert.equal(s.store.users.get(a.accountId)!.kdfIter, KDF_ITERATIONS);
  assert.ok(KDF_ITERATIONS <= 10000);

  // Giả lập tài khoản tạo trước khi đổi: 100000 vòng.
  const u = s.store.users.get(a.accountId)!;
  const salt = randomBytes(16);
  u.salt = salt;
  u.pwHash = await pbkdf2(new Uint8Array(32).fill(1), salt, 100000);
  u.kdfIter = 100000;

  assert.equal((await login(s, authKey(9))).status, 401);
  assert.equal(u.kdfIter, 100000, 'sai mật khẩu thì không băm lại');
  assert.equal((await login(s, authKey())).status, 200, 'tài khoản cũ vẫn đăng nhập được');
  assert.equal(s.store.users.get(a.accountId)!.kdfIter, KDF_ITERATIONS);
  assert.equal((await login(s, authKey())).status, 200, 'sau khi băm lại vẫn đăng nhập được');
});

test('thân JSON khai báo quá lớn bị từ chối mà không đọc', async () => {
  const s = setup();
  const r = await s.call('POST', '/auth/login', { body: { username: USER, authKey: authKey() }, headers: { 'content-length': '999999' } });
  assert.equal(r.status, 400);
});
