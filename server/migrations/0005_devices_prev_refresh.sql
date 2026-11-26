-- Lưu hash của refresh token trước đó để phát hiện khi token cũ bị dùng lại (xem handler.ts, refresh).
ALTER TABLE devices ADD COLUMN prev_refresh_hash TEXT;
CREATE INDEX IF NOT EXISTS devices_prev_refresh ON devices(prev_refresh_hash);
