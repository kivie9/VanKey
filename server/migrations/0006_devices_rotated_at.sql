-- Thời điểm refresh token được xoay vòng gần nhất. Token ngay trước đó còn dùng lại được trong một khoảng ngắn
-- (máy gửi lại khi mất phản hồi, hoặc hai yêu cầu làm mới chạy song song) mà không bị coi là lộ token (xem handler.ts, refresh).
ALTER TABLE devices ADD COLUMN rotated_at INTEGER NOT NULL DEFAULT 0;
