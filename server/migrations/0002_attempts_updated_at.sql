-- Thêm thời điểm cập nhật cho bảng attempts để dọn các dòng cũ (chống làm đầy bảng bằng đăng nhập sai).
ALTER TABLE attempts ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS attempts_updated ON attempts(updated_at);
