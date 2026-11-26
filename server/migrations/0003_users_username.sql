-- Đăng nhập bằng tên đăng nhập thay cho email (cột cũ `email` đổi tên, dữ liệu giữ nguyên).
ALTER TABLE users RENAME COLUMN email TO username;
