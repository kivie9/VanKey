import type { Attempt, Device, PutResult, Store, User, VaultRow } from './store.ts';

// Phần tối thiểu của D1 mà ta dùng (tránh phụ thuộc gói kiểu của Cloudflare).
interface D1Result<T> {
  results?: T[];
  meta?: { changes?: number };
}
interface D1Statement {
  bind(...values: unknown[]): D1Statement;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<D1Result<T>>;
  run(): Promise<D1Result<unknown>>;
}
export interface D1Like {
  prepare(sql: string): D1Statement;
}

type Row = Record<string, unknown>;

function bytes(v: unknown): Uint8Array | null {
  if (v == null) return null;
  if (v instanceof Uint8Array) return v;
  if (v instanceof ArrayBuffer) return new Uint8Array(v);
  if (Array.isArray(v)) return new Uint8Array(v as number[]); // D1 trả BLOB dạng mảng số trong một số phiên bản
  return null;
}

function toUser(r: Row): User {
  return {
    id: r.id as string,
    email: r.email as string,
    salt: bytes(r.salt),
    pwHash: bytes(r.pw_hash),
    createdAt: r.created_at as number,
  };
}

function toDevice(r: Row): Device {
  return {
    id: r.id as string,
    userId: r.user_id as string,
    name: r.name as string,
    refreshHash: r.refresh_hash as string,
    createdAt: r.created_at as number,
    lastSeen: r.last_seen as number,
    expiresAt: r.expires_at as number,
    revoked: (r.revoked as number) === 1,
  };
}

/** Bản D1 của [Store]. Lược đồ ở migrations/0001_init.sql. */
export class D1Store implements Store {
  db: D1Like;

  constructor(db: D1Like) {
    this.db = db;
  }

  async userByEmail(email: string): Promise<User | null> {
    const r = await this.db.prepare('SELECT * FROM users WHERE email = ?').bind(email).first<Row>();
    return r ? toUser(r) : null;
  }

  async userById(id: string): Promise<User | null> {
    const r = await this.db.prepare('SELECT * FROM users WHERE id = ?').bind(id).first<Row>();
    return r ? toUser(r) : null;
  }

  async createUser(u: User): Promise<boolean> {
    const res = await this.db
      .prepare('INSERT OR IGNORE INTO users (id, email, salt, pw_hash, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(u.id, u.email, u.salt, u.pwHash, u.createdAt)
      .run();
    return (res.meta?.changes ?? 0) > 0;
  }

  async createDevice(d: Device): Promise<void> {
    await this.db
      .prepare('INSERT INTO devices (id, user_id, name, refresh_hash, created_at, last_seen, expires_at, revoked) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
      .bind(d.id, d.userId, d.name, d.refreshHash, d.createdAt, d.lastSeen, d.expiresAt, d.revoked ? 1 : 0)
      .run();
  }

  async deviceById(id: string): Promise<Device | null> {
    const r = await this.db.prepare('SELECT * FROM devices WHERE id = ?').bind(id).first<Row>();
    return r ? toDevice(r) : null;
  }

  async deviceByRefreshHash(hash: string): Promise<Device | null> {
    const r = await this.db.prepare('SELECT * FROM devices WHERE refresh_hash = ?').bind(hash).first<Row>();
    return r ? toDevice(r) : null;
  }

  async updateDevice(id: string, patch: Partial<Pick<Device, 'refreshHash' | 'lastSeen' | 'expiresAt' | 'revoked'>>): Promise<void> {
    const sets: string[] = [];
    const vals: unknown[] = [];
    if (patch.refreshHash !== undefined) { sets.push('refresh_hash = ?'); vals.push(patch.refreshHash); }
    if (patch.lastSeen !== undefined) { sets.push('last_seen = ?'); vals.push(patch.lastSeen); }
    if (patch.expiresAt !== undefined) { sets.push('expires_at = ?'); vals.push(patch.expiresAt); }
    if (patch.revoked !== undefined) { sets.push('revoked = ?'); vals.push(patch.revoked ? 1 : 0); }
    if (sets.length === 0) return;
    await this.db.prepare(`UPDATE devices SET ${sets.join(', ')} WHERE id = ?`).bind(...vals, id).run();
  }

  async devicesOf(userId: string): Promise<Device[]> {
    const r = await this.db.prepare('SELECT * FROM devices WHERE user_id = ? AND revoked = 0 ORDER BY created_at').bind(userId).all<Row>();
    return (r.results ?? []).map(toDevice);
  }

  async getVault(userId: string): Promise<VaultRow | null> {
    const r = await this.db.prepare('SELECT * FROM vaults WHERE user_id = ?').bind(userId).first<Row>();
    if (!r) return null;
    return { userId, version: r.version as number, blob: bytes(r.blob) ?? new Uint8Array(0), updatedAt: r.updated_at as number };
  }

  async putVault(userId: string, expected: number | null, blob: Uint8Array, now: number): Promise<PutResult> {
    if (expected === null) {
      const res = await this.db
        .prepare('INSERT OR IGNORE INTO vaults (user_id, version, blob, updated_at) VALUES (?, 1, ?, ?)')
        .bind(userId, blob, now)
        .run();
      if ((res.meta?.changes ?? 0) > 0) return { ok: true, version: 1 };
    } else {
      // Một câu UPDATE có điều kiện: chỉ ghi nếu phiên bản vẫn như ta đã đọc (nguyên tử trong D1).
      const res = await this.db
        .prepare('UPDATE vaults SET blob = ?, version = version + 1, updated_at = ? WHERE user_id = ? AND version = ?')
        .bind(blob, now, userId, expected)
        .run();
      if ((res.meta?.changes ?? 0) > 0) return { ok: true, version: expected + 1 };
    }
    const cur = await this.db.prepare('SELECT version FROM vaults WHERE user_id = ?').bind(userId).first<Row>();
    return { ok: false, current: cur ? (cur.version as number) : null };
  }

  async getAttempt(key: string): Promise<Attempt> {
    const r = await this.db.prepare('SELECT count, locked_until FROM attempts WHERE key = ?').bind(key).first<Row>();
    return r ? { count: r.count as number, lockedUntil: r.locked_until as number } : { count: 0, lockedUntil: 0 };
  }

  async setAttempt(key: string, a: Attempt): Promise<void> {
    await this.db
      .prepare('INSERT INTO attempts (key, count, locked_until) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET count = excluded.count, locked_until = excluded.locked_until')
      .bind(key, a.count, a.lockedUntil)
      .run();
  }

  async clearAttempt(key: string): Promise<void> {
    await this.db.prepare('DELETE FROM attempts WHERE key = ?').bind(key).run();
  }
}
