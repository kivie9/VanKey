-- Ghi nhận việc đồng ý Điều khoản và Chính sách quyền riêng tư lúc đăng ký (phiên bản điều khoản và thời điểm).
-- Tài khoản tạo trước migration này để trống (terms_version = '').
ALTER TABLE users ADD COLUMN terms_version TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN terms_at INTEGER NOT NULL DEFAULT 0;
