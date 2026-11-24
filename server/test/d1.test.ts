// Chạy cùng các kiểm tra trên D1Store thật với SQLite thật (node:sqlite) và đúng file migration, để bắt lỗi SQL.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { D1Store } from '../src/d1_store.ts';
import type { D1Like } from '../src/d1_store.ts';
import { createHandler } from '../src/handler.ts';
import { toBase64 } from '../src/util.ts';

function sqliteD1(): D1Like {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  db.exec(readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8'));
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

const EMAIL = 'me@example.com';
const key = (n = 1) => toBase64(new Uint8Array(32).fill(n));

function setup() {
  const store = new D1Store(sqliteD1());
  let t = 1_700_000_000;
  const handler = createHandler({ store, config: { allowedEmails: EMAIL, tokenSecret: 'x'.repeat(40) }, now: () => t });
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
  const a = (await (await s.call('POST', '/auth/register', { body: { email: EMAIL, authKey: key(), deviceName: 'A' } })).json()) as any;
  assert.ok(a.accessToken);
  assert.equal((await s.call('POST', '/auth/register', { body: { email: EMAIL, authKey: key() } })).status, 409);

  const b = (await (await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: key(), deviceName: 'B' } })).json()) as any;
  assert.equal((await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: key(9) } })).status, 401);

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
  const a = (await (await s.call('POST', '/auth/register', { body: { email: EMAIL, authKey: key() } })).json()) as any;
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
  await s.call('POST', '/auth/register', { body: { email: EMAIL, authKey: key() } });
  for (let i = 0; i < 5; i++) await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: key(9) } });
  assert.equal((await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: key() } })).status, 429);
  const row = await s.store.getAttempt(`login:${EMAIL}`);
  assert.equal(row.count, 5);
  s.advance(31);
  assert.equal((await s.call('POST', '/auth/login', { body: { email: EMAIL, authKey: key() } })).status, 200);
  assert.equal((await s.store.getAttempt(`login:${EMAIL}`)).count, 0);
});

test('D1: xóa người dùng kéo theo thiết bị và kho (ON DELETE CASCADE)', async () => {
  const s = setup();
  const a = (await (await s.call('POST', '/auth/register', { body: { email: EMAIL, authKey: key() } })).json()) as any;
  await s.call('PUT', '/vault', { token: a.accessToken, headers: { 'if-none-match': '*' }, raw: new Uint8Array(64) });
  const db = (s.store as any).db as D1Like;
  await db.prepare('DELETE FROM users WHERE id = ?').bind(a.accountId).run();
  assert.equal(await s.store.getVault(a.accountId), null);
  assert.equal(await s.store.deviceById(a.deviceId), null);
});
