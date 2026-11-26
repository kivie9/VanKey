-- Số vòng PBKDF2 theo từng tài khoản. Tài khoản cũ giữ 100000 và được băm lại với số vòng mới ở lần đăng nhập kế tiếp.
-- authKey gửi lên đã qua Argon2id trên máy, nên số vòng trên máy chủ chỉ cần nhỏ (vừa giới hạn CPU gói miễn phí của Cloudflare).
ALTER TABLE users ADD COLUMN kdf_iter INTEGER NOT NULL DEFAULT 100000;
