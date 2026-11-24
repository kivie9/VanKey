// Giao diện lưu trữ. Bản D1 dùng thật; bản bộ nhớ dùng cho test và chạy thử cục bộ.

export interface User {
  id: string;
  email: string;
  /** null nếu tài khoản chỉ đăng nhập bằng Google. */
  salt: Uint8Array | null;
  pwHash: Uint8Array | null;
  createdAt: number;
}

export interface Device {
  id: string;
  userId: string;
  name: string;
  /** SHA-256 (hex) của refresh token hiện hành. Server không giữ bản gốc. */
  refreshHash: string;
  createdAt: number;
  lastSeen: number;
  expiresAt: number;
  revoked: boolean;
}

export interface VaultRow {
  userId: string;
  version: number;
  blob: Uint8Array;
  updatedAt: number;
}

export interface Attempt {
  count: number;
  /** Giây UNIX; 0 nếu không bị khóa. */
  lockedUntil: number;
}

export type PutResult = { ok: true; version: number } | { ok: false; current: number | null };

export interface Store {
  userByEmail(email: string): Promise<User | null>;
  userById(id: string): Promise<User | null>;
  /** Trả về false nếu email đã tồn tại. */
  createUser(u: User): Promise<boolean>;

  createDevice(d: Device): Promise<void>;
  deviceById(id: string): Promise<Device | null>;
  deviceByRefreshHash(hash: string): Promise<Device | null>;
  updateDevice(id: string, patch: Partial<Pick<Device, 'refreshHash' | 'lastSeen' | 'expiresAt' | 'revoked'>>): Promise<void>;
  devicesOf(userId: string): Promise<Device[]>;

  getVault(userId: string): Promise<VaultRow | null>;
  /**
   * Ghi nguyên tử. `expected` = null nghĩa là "chỉ tạo mới", số nghĩa là "chỉ khi đang ở đúng phiên bản đó".
   */
  putVault(userId: string, expected: number | null, blob: Uint8Array, now: number): Promise<PutResult>;

  getAttempt(key: string): Promise<Attempt>;
  setAttempt(key: string, a: Attempt): Promise<void>;
  clearAttempt(key: string): Promise<void>;
}
