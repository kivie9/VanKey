import type { Attempt, Device, PutResult, Store, User, VaultRow } from './store.ts';

/** Lưu trong bộ nhớ: cho test và chạy thử cục bộ. Mọi thay đổi chạy đồng bộ nên tự nhiên là nguyên tử. */
export class MemoryStore implements Store {
  users = new Map<string, User>();
  devices = new Map<string, Device>();
  vaults = new Map<string, VaultRow>();
  attempts = new Map<string, Attempt>();

  async userByEmail(email: string): Promise<User | null> {
    for (const u of this.users.values()) if (u.email === email) return u;
    return null;
  }

  async userById(id: string): Promise<User | null> {
    return this.users.get(id) ?? null;
  }

  async createUser(u: User): Promise<boolean> {
    if (await this.userByEmail(u.email)) return false;
    this.users.set(u.id, u);
    return true;
  }

  async createDevice(d: Device): Promise<void> {
    this.devices.set(d.id, { ...d });
  }

  async deviceById(id: string): Promise<Device | null> {
    const d = this.devices.get(id);
    return d ? { ...d } : null;
  }

  async deviceByRefreshHash(hash: string): Promise<Device | null> {
    for (const d of this.devices.values()) if (d.refreshHash === hash) return { ...d };
    return null;
  }

  async updateDevice(id: string, patch: Partial<Pick<Device, 'refreshHash' | 'lastSeen' | 'expiresAt' | 'revoked'>>): Promise<void> {
    const d = this.devices.get(id);
    if (d) Object.assign(d, patch);
  }

  async devicesOf(userId: string): Promise<Device[]> {
    return [...this.devices.values()].filter((d) => d.userId === userId && !d.revoked).map((d) => ({ ...d }));
  }

  async getVault(userId: string): Promise<VaultRow | null> {
    const v = this.vaults.get(userId);
    return v ? { ...v, blob: new Uint8Array(v.blob) } : null;
  }

  async putVault(userId: string, expected: number | null, blob: Uint8Array, now: number): Promise<PutResult> {
    const cur = this.vaults.get(userId);
    if (expected === null) {
      if (cur) return { ok: false, current: cur.version };
      this.vaults.set(userId, { userId, version: 1, blob: new Uint8Array(blob), updatedAt: now });
      return { ok: true, version: 1 };
    }
    if (!cur || cur.version !== expected) return { ok: false, current: cur?.version ?? null };
    const version = cur.version + 1;
    this.vaults.set(userId, { userId, version, blob: new Uint8Array(blob), updatedAt: now });
    return { ok: true, version };
  }

  async getAttempt(key: string): Promise<Attempt> {
    return this.attempts.get(key) ?? { count: 0, lockedUntil: 0 };
  }

  async setAttempt(key: string, a: Attempt): Promise<void> {
    this.attempts.set(key, { ...a });
  }

  async clearAttempt(key: string): Promise<void> {
    this.attempts.delete(key);
  }
}
