# Nhật ký thay đổi

Ghi theo từng phiên bản, mới nhất ở trên. Số phiên bản theo dạng `MAJOR.MINOR.PATCH`, tag `v1.2.3` sẽ tạo GitHub Release (xem `.github/workflows/build.yml`).
Khi phát hành: đổi tiêu đề "Chưa phát hành" thành số phiên bản và ngày, chép phần đó vào ghi chú của GitHub Release.

Nhóm mục: **Thêm**, **Đổi**, **Sửa**, **Bảo mật**, **Bỏ**.

## Chưa phát hành

Chưa có bản phát hành nào (chưa có tag). Phần dưới tóm tắt những gì đã có tới 2026-11-27.

### Thêm
- Khi tạo tài khoản máy chủ, phải đồng ý Điều khoản và Chính sách quyền riêng tư. Máy chủ ghi nhận phiên bản điều khoản và thời điểm đồng ý (migration 0007).
- Trang pháp lý: Quyền riêng tư, Điều khoản sử dụng, Xóa tài khoản và dữ liệu, Bảo mật và báo lỗ hổng (vi và en, trong `site/`). Footer của trang chủ có link tới các trang này.
- Giới thiệu có mục "Dữ liệu rời khỏi máy khi nào" và link tới các trang pháp lý khi đặt `SITE_URL` lúc build.
- `SECURITY.md` cách báo lỗ hổng, `docs/huong-dan-nguoi-dung.md`, và `docs/van-hanh.md` (có quy trình khi mở đăng ký).
- Kho mã hóa `.vkv`: Argon2id (tự đo tham số khi tạo kho), XChaCha20-Poly1305, mã khôi phục, gộp 3 bên khi đồng bộ.
- Mục đăng nhập, ghi chú, thẻ, trường tùy ý, lịch sử mật khẩu (10 bản gần nhất), thùng rác, nhóm, tìm kiếm bỏ dấu.
- 2FA: TOTP có đếm ngược, HOTP, Steam Guard; quét QR bằng camera và từ ảnh; hiện QR từng mục; xuất sang Google Authenticator.
- Nhập từ Google Authenticator, Aegis, 2FAS, Bitwarden, KeePass XML, 1Password `.1pux`, CSV, link `otpauth`.
- Xuất CSV, link, sao lưu mã hóa, xuất theo nhóm.
- Kiểm tra bảo mật: mật khẩu yếu, trùng, rò rỉ qua HIBP (chỉ gửi 5 ký tự đầu của mã băm).
- Nhắc nhở và thông báo cục bộ.
- Đồng bộ: máy chủ VanKey (Cloudflare Worker + D1, đăng nhập bằng tên đăng nhập), Google Drive (thư mục ẩn của app), thư mục trên máy tính.
- Tài khoản máy chủ: đăng ký có giới hạn, mã mời tùy chọn, danh sách và gỡ thiết bị, đổi mật khẩu, xóa tài khoản.
- Giao diện sáng/tối/đen, 6 màu nhấn, tiếng Việt và tiếng Anh, bố cục máy tính, logo khoảng 85 dịch vụ.
- Bộ cài Windows (Inno Setup) và bản zip; CI build Android, Windows, iOS.
- Kiểm tra bản mới (bấm tay), màn Hỗ trợ và Giới thiệu, trang giấy phép mã nguồn mở.

### Bảo mật
- Tự khóa mặc định 5 phút với kho mới; làm chậm khi nhập sai; chặn chụp màn hình (Android).
- Mở bằng vân tay gắn với khóa Android Keystore, chỉ cất vault key đã bọc.
- Windows: sao chép bí mật không vào lịch sử Win+V và clipboard đám mây.
- Mã 2FA, mật khẩu, ghi chú ẩn mặc định và tự ẩn lại sau 30 giây.
- Máy chủ: khóa tài khoản khi sai nhiều lần, giới hạn theo IP (từ chối nếu không xác định được IP), phát hiện dùng lại refresh token.
- Bắt buộc mật khẩu mạnh khi đặt hoặc đổi mật khẩu kho.

### Đang làm
- Mở bằng Windows Hello gắn với khóa trong TPM.

### Bỏ
- Chế độ dùng kho không có mật khẩu.
- Màn gợi ý dịch vụ.
