// Giao diện lưu trữ. Bản D1 dùng thật; bản bộ nhớ dùng cho test và chạy thử cục bộ.

export interface User {
  id: string;
  /** Tên đăng nhập, đã chuẩn hóa (chữ thường). */
  username: string;
  salt: Uint8Array;
  pwHash: Uint8Array;
  /** Số vòng PBKDF2 đã dùng để tạo pwHash (tài khoản cũ: 100000; tự băm lại khi đăng nhập). */
  kdfIter: number;
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
  userByUsername(username: string): Promise<User | null>;
  userById(id: string): Promise<User | null>;
  countUsers(): Promise<number>;
  /** Trả về false nếu tên đăng nhập đã tồn tại. */
  createUser(u: User): Promise<boolean>;
  /** Thay thông tin đăng nhập (đổi mật khẩu hoặc băm lại với số vòng mới). */
  setPassword(userId: string, salt: Uint8Array, pwHash: Uint8Array, kdfIter: number): Promise<void>;
  /** Xóa hẳn tài khoản cùng kho và mọi thiết bị của nó. */
  deleteUser(userId: string): Promise<void>;

  createDevice(d: Device): Promise<void>;
  deviceById(id: string): Promise<Device | null>;
  deviceByRefreshHash(hash: string): Promise<Device | null>;
  updateDevice(id: string, patch: Partial<Pick<Device, 'refreshHash' | 'lastSeen' | 'expiresAt' | 'revoked'>>): Promise<void>;
  devicesOf(userId: string): Promise<Device[]>;
  /** Gỡ mọi thiết bị của tài khoản trừ `keepId`. */
  revokeDevicesExcept(userId: string, keepId: string): Promise<void>;

  getVault(userId: string): Promise<VaultRow | null>;
  /**
   * Ghi nguyên tử. `expected` = null nghĩa là "chỉ tạo mới", số nghĩa là "chỉ khi đang ở đúng phiên bản đó".
   */
  putVault(userId: string, expected: number | null, blob: Uint8Array, now: number): Promise<PutResult>;

  getAttempt(key: string): Promise<Attempt>;
  /** Tăng số lần sai thêm 1 một cách nguyên tử (tạo dòng nếu chưa có) và trả về số lần sai mới. */
  bumpFailure(key: string, now: number): Promise<number>;
  /** Đặt thời điểm hết khóa (giây UNIX). */
  lockUntil(key: string, until: number): Promise<void>;
  clearAttempt(key: string): Promise<void>;
  /** Xóa các dòng không còn cập nhật từ trước `before` (giây UNIX). */
  purgeAttempts(before: number): Promise<void>;
}
