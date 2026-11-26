// Chạy cùng các kiểm tra trên D1Store thật với SQLite thật (node:sqlite) và đúng file migration, để bắt lỗi SQL.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { D1Store } from '../src/d1_store.ts';
import type { D1Like } from '../src/d1_store.ts';
import { createHandler, KDF_ITERATIONS } from '../src/handler.ts';
import { pbkdf2, toBase64 } from '../src/util.ts';

function sqliteD1(): D1Like {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (const f of ['0001_init.sql', '0002_attempts_updated_at.sql', '0003_users_username.sql', '0004_users_kdf_iter.sql']) db.exec(readFileSync(new URL(`../migrations/${f}`, import.meta.url), 'utf8'));
  return {
    prepare(sql: string) {
      const stmt = db.prepare(sql);
      let params: unknown[] = [];
      const api = {
        bind(...v: unknown[]) {
          params = v.map((x) => (x === undefined ? null : x));
          return api;
        },
        async first<T>() {
          return (stmt.get(...(params as any[])) as T) ?? null;
        },
        async all<T>() {
          return { results: stmt.all(...(params as any[])) as T[] };
        },
        async run() {
          const r = stmt.run(...(params as any[]));
          return { meta: { changes: Number(r.changes) } };
        },
      };
      return api as any;
    },
  };
}

const USER = 'minh.van';
const key = (n = 1) => toBase64(new Uint8Array(32).fill(n));

function setup() {
  const store = new D1Store(sqliteD1());
  let t = 1_700_000_000;
  const handler = createHandler({ store, config: { tokenSecret: 'x'.repeat(40) }, now: () => t });
  const call = (method: string, path: string, o: { body?: unknown; token?: string; headers?: Record<string, string>; raw?: Uint8Array } = {}) => {
    const headers: Record<string, string> = { ...(o.headers ?? {}) };
    if (o.token) headers.authorization = `Bearer ${o.token}`;
    let body: BodyInit | undefined;
    if (o.raw) body = o.raw as BodyInit;
    else if (o.body !== undefined) body = JSON.stringify(o.body);
    return handler(new Request(`http://x${path}`, { method, headers, body }));
  };
  return { store, call, advance: (s: number) => (t += s) };
}

test('D1: đăng ký, đăng nhập, refresh xoay vòng, thu hồi thiết bị', async () => {
  const s = setup();
  const a = (await (await s.call('POST', '/auth/register', { body: { username: USER, authKey: key(), deviceName: 'A' } })).json()) as any;
  assert.ok(a.accessToken);
  assert.equal((await s.call('POST', '/auth/register', { body: { username: USER, authKey: key() } })).status, 409);

  const b = (await (await s.call('POST', '/auth/login', { body: { username: USER, authKey: key(), deviceName: 'B' } })).json()) as any;
  assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: key(9) } })).status, 401);

  const r = await s.call('POST', '/auth/refresh', { body: { refreshToken: b.refreshToken } });
  assert.equal(r.status, 200);
  assert.equal((await s.call('POST', '/auth/refresh', { body: { refreshToken: b.refreshToken } })).status, 401);

  const list = ((await (await s.call('GET', '/devices', { token: a.accessToken })).json()) as any).devices;
  assert.equal(list.length, 2);
  assert.equal((await s.call('DELETE', `/devices/${b.deviceId}`, { token: a.accessToken })).status, 204);
  assert.equal(((await (await s.call('GET', '/devices', { token: a.accessToken })).json()) as any).devices.length, 1);
});

test('D1: kho với If-Match/If-None-Match, 409 khi lệch, byte nhị phân nguyên vẹn', async () => {
  const s = setup();
  const a = (await (await s.call('POST', '/auth/register', { body: { username: USER, authKey: key() } })).json()) as any;
  const blob = new Uint8Array(300).map((_, i) => i % 256); // có đủ các giá trị byte, kể cả 0
  assert.equal((await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: blob })).status, 200);
  assert.equal((await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: blob })).status, 409);

  const got = await s.call('GET', '/vault', { token: a.accessToken });
  assert.equal(got.headers.get('etag'), '"v1"');
  assert.deepEqual(new Uint8Array(await got.arrayBuffer()), blob);

  const next = new Uint8Array(64).fill(9);
  const ok = await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-match': '"v1"' }, raw: next });
  assert.equal(ok.status, 200);
  const stale = await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-match': '"v1"' }, raw: blob });
  assert.equal(stale.status, 409);
  assert.equal(((await stale.json()) as any).version, 2);
  assert.deepEqual(new Uint8Array(await (await s.call('GET', '/vault', { token: a.accessToken })).arrayBuffer()), next);
});

test('D1: khóa đăng nhập sai lưu bền trong bảng attempts và hết hạn đúng giờ', async () => {
  const s = setup();
  await s.call('POST', '/auth/register', { body: { username: USER, authKey: key() } });
  for (let i = 0; i < 5; i++) await s.call('POST', '/auth/login', { body: { username: USER, authKey: key(9) } });
  assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: key() } })).status, 429);
  const row = await s.store.getAttempt(`login:${USER}`);
  assert.equal(row.count, 5);
  s.advance(31);
  assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: key() } })).status, 200);
  assert.equal((await s.store.getAttempt(`login:${USER}`)).count, 0);
});

test('D1: xóa người dùng kéo theo thiết bị và kho (ON DELETE CASCADE)', async () => {
  const s = setup();
  const a = (await (await s.call('POST', '/auth/register', { body: { username: USER, authKey: key() } })).json()) as any;
  await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: new Uint8Array(64) });
  const db = (s.store as any).db as D1Like;
  await db.prepare('DELETE FROM users WHERE id = ?').bind(a.accountId).run();
  assert.equal(await s.store.getVault(a.accountId), null);
  assert.equal(await s.store.deviceById(a.deviceId), null);
});

test('D1: đếm lần sai nguyên tử khi gửi song song, mỗi yêu cầu nhận một số khác nhau', async () => {
  const s = setup();
  const counts = await Promise.all(Array.from({ length: 12 }, () => s.store.bumpFailure('login:x', 1_700_000_000)));
  assert.deepEqual([...counts].sort((a, b) => a - b), Array.from({ length: 12 }, (_, i) => i + 1));
  assert.equal((await s.store.getAttempt('login:x')).count, 12);
});

test('D1: tên không có thật đăng nhập sai không tạo dòng login:<tên>; chỉ tính theo IP', async () => {
  const s = setup();
  const db = (s.store as any).db as D1Like;
  for (let i = 0; i < 20; i++) {
    await s.call('POST', '/auth/login', { body: { username: `la.${i}x`, authKey: key(9) }, headers: { 'cf-connecting-ip': '203.0.113.7' } });
  }
  const rows = (await db.prepare('SELECT key FROM attempts').all<{ key: string }>()).results ?? [];
  assert.deepEqual(rows.map((r) => r.key), ['ip:203.0.113.7']);
});

test('D1: dòng đếm cũ bị dọn khi có dòng mới', async () => {
  const s = setup();
  const db = (s.store as any).db as D1Like;
  await s.store.bumpFailure('ip:1.1.1.1', 1_700_000_000);
  s.advance(2 * 24 * 3600);
  await s.call('POST', '/auth/login', { body: { username: USER, authKey: key(9) }, headers: { 'cf-connecting-ip': '2.2.2.2' } });
  const rows = ((await db.prepare('SELECT key FROM attempts').all<{ key: string }>()).results ?? []).map((r) => r.key).sort();
  assert.deepEqual(rows, ['ip:2.2.2.2']);
});

test('D1: migration 0003 đổi tên cột email thành username và giữ nguyên dữ liệu', async () => {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8'));
  db.prepare('INSERT INTO users (id, email, salt, pw_hash, created_at) VALUES (?, ?, ?, ?, ?)').run('u1', 'cu@example.com', new Uint8Array(16), new Uint8Array(32), 1);
  db.exec(readFileSync(new URL('../migrations/0002_attempts_updated_at.sql', import.meta.url), 'utf8'));
  db.exec(readFileSync(new URL('../migrations/0003_users_username.sql', import.meta.url), 'utf8'));
  const row = db.prepare('SELECT username FROM users WHERE id = ?').get('u1') as { username: string };
  assert.equal(row.username, 'cu@example.com');
});

test('D1: đổi mật khẩu, băm lại tài khoản cũ, xóa tài khoản xóa sạch các bảng', async () => {
  const s = setup();
  const a = (await (await s.call('POST', '/auth/register', { body: { username: USER, authKey: key(), deviceName: 'A' } })).json()) as any;
  const b = (await (await s.call('POST', '/auth/login', { body: { username: USER, authKey: key(), deviceName: 'B' } })).json()) as any;

  assert.equal((await s.call('POST', '/auth/password', { token: a.accessToken, body: { authKey: key(), newAuthKey: key(2) } })).status, 204);
  assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: key() } })).status, 401);
  assert.equal((await s.call('GET', '/devices', { token: b.accessToken })).status, 401, 'thiết bị B bị gỡ');

  // Tài khoản cũ (cột kdf_iter mặc định 100000 sau migration) vẫn đăng nhập được và được băm lại.
  const salt = new Uint8Array(16).fill(3);
  await s.store.setPassword(a.accountId, salt, await pbkdf2(new Uint8Array(32).fill(2), salt, 100000), 100000);
  assert.equal((await s.call('POST', '/auth/login', { body: { username: USER, authKey: key(2) } })).status, 200);
  assert.equal((await s.store.userById(a.accountId))!.kdfIter, KDF_ITERATIONS);

  await s.call('PUT', '/vault', { token: a.accessToken, raw: new Uint8Array(64).fill(1), headers: { 'if-none-match': '*' } });
  assert.equal((await s.call('DELETE', '/account', { token: a.accessToken, body: { authKey: key(2) } })).status, 204);
  assert.equal(await s.store.countUsers(), 0);
  assert.equal(await s.store.getVault(a.accountId), null);
  assert.equal((await s.store.devicesOf(a.accountId)).length, 0);
  assert.equal(await s.store.deviceById(a.deviceId), null);
});

test('D1: migration 0004 cho tài khoản cũ kdf_iter = 100000', async () => {
  const db = new DatabaseSync(':memory:');
  for (const f of ['0001_init.sql', '0002_attempts_updated_at.sql', '0003_users_username.sql']) db.exec(readFileSync(new URL(`../migrations/${f}`, import.meta.url), 'utf8'));
  db.prepare('INSERT INTO users (id, username, salt, pw_hash, created_at) VALUES (?, ?, ?, ?, ?)').run('u1', 'cu', new Uint8Array(16), new Uint8Array(32), 1);
  db.exec(readFileSync(new URL('../migrations/0004_users_kdf_iter.sql', import.meta.url), 'utf8'));
  assert.equal((db.prepare('SELECT kdf_iter FROM users').get() as { kdf_iter: number }).kdf_iter, 100000);
});
