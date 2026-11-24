-- Lược đồ D1 cho máy chủ VanKey. Máy chủ chỉ giữ dữ liệu đã mã hóa và thông tin đăng nhập.
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  salt BLOB,            -- null nếu chỉ đăng nhập bằng Google
  pw_hash BLOB,         -- PBKDF2(authKey do client dẫn xuất, salt); không bao giờ là mật khẩu gốc
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  refresh_hash TEXT NOT NULL,   -- SHA-256 (hex) của refresh token; không lưu bản gốc
  created_at INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS devices_refresh ON devices(refresh_hash);
CREATE INDEX IF NOT EXISTS devices_user ON devices(user_id);

CREATE TABLE IF NOT EXISTS vaults (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  blob BLOB NOT NULL,           -- file .vkv đã mã hóa
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS attempts (
  key TEXT PRIMARY KEY,         -- "login:<email>" hoặc "ip:<địa chỉ>"
  count INTEGER NOT NULL,
  locked_until INTEGER NOT NULL
);
