# Tình trạng hiện tại

Cập nhật: 2026-11-27. Phần Windows Hello gắn khóa phần cứng chưa commit (xem `git status`).

## Đã có và đã thử

| Phần | Trạng thái | Kiểm chứng |
|---|---|---|
| Lõi mật mã, file kho `.vkv`, gộp 3 bên | Xong (M1) | 198+ test tự động, đối chiếu libsodium |
| Tạo/mở kho bằng mật khẩu (đã bỏ chế độ "dùng ngay không mật khẩu"), mã khôi phục | Xong | Chạy trên Galaxy Note10+ (release) |
| Danh sách, 2FA có đếm ngược, thêm/sửa/xóa, thùng rác, gom nhóm, tìm kiếm bỏ dấu | Xong | Widget test + máy thật |
| Nhập: Google Authenticator, Aegis, 2FAS, Bitwarden, CSV, link otpauth | Xong | Test với dữ liệu giả; **chưa thử file thật** |
| Quét QR (camera và ảnh) | Xong | **Chưa thử trên máy thật** |
| Xuất CSV/link, sao lưu mã hóa | Xong | Test đơn vị |
| Kiểm tra bảo mật, kiểm tra rò rỉ HIBP (k-anonymity) | Xong | **Chưa thử mạng thật** |
| Tự khóa (mặc định 5 phút với kho mới), làm chậm nhập sai, FLAG_SECURE, clipboard nhạy cảm (Windows: không vào lịch sử Win+V và clipboard đám mây) | Xong | **FLAG_SECURE chưa thử tay** |
| Mở bằng vân tay (Android) gắn với khóa Keystore: chỉ cất vault key đã bọc, không cất mật khẩu | Xong | **Chưa thử tay** |
| Mở bằng Windows Hello gắn với khóa trong TPM (`windows/runner/hello_vault.cpp`) | Đang làm, chưa commit | `bio_bound_test.dart` (kênh giả lập); **chưa thử trên máy thật** |
| Nhắc nhở và thông báo cục bộ (đặt lại sau khởi động máy) | Xong | **Chưa thử thông báo hẹn giờ trên máy thật** |
| Đồng bộ: lõi, giả lập, thư mục, màn xung đột | Xong (lõi) | 14 test, gồm ghi chen, mất mạng, đổi mật khẩu |
| Giao diện sáng/tối/đen, 6 màu nhấn, Việt/Anh | Xong | Test chuỗi; chưa soát từng màn |
| Cài đặt 7 menu, Hỗ trợ, Giới thiệu, đổi/tắt mật khẩu, lọc nhóm, lưới nhiều cột | Xong | Widget test; **chưa xem trên màn máy tính thật** |
| Trường tùy ý, đổi nhóm nhanh trong chi tiết | Xong | Widget test |
| HOTP (nút mã kế tiếp) và Steam Guard | Xong | Vector Steam đối chiếu bản cài độc lập (Node); **chưa thử với dịch vụ thật** |
| Nhập KeePass XML, 1Password .1pux; xuất theo nhóm | Xong | Dữ liệu giả; **chưa thử file thật** |
| Tự đo Argon2id khi tạo kho | Xong | Test chọn tham số; đo thật trên Note10+ ra 3 vòng 64 MiB |
| **Máy chủ Cloudflare** (`server/`): đăng ký mở (có giới hạn) và đăng nhập bằng tên đăng nhập + một mật khẩu, mã mời tùy chọn, thiết bị, kho có `If-Match`, khóa khi sai nhiều lần | Xong, **chưa deploy bản này** | 40 test Node, gồm SQL thật trên SQLite; test đầu cuối Dart ↔ server thật |
| Client Cloudflare + màn đăng nhập/đăng ký, danh sách thiết bị, máy mới tải kho về | Xong | Test đầu cuối: 2 `VaultController` đồng bộ qua server thật, gỡ thiết bị |
| Quét QR từ ảnh bằng Dart thuần (cho Windows và dự phòng ML Kit) | Xong | Test vòng đi vòng lại, ảnh lớn |
| Biểu tượng chìa khóa (cổ điển + adaptive, sinh bằng `tool/make_icon.dart`), tên app VanKey | Xong | Xem ảnh docs/branding; **chưa xem trên màn hình chính điện thoại** |
| Hiện QR từng mục 2FA và QR xuất sang Google Authenticator (chia lô 6 mục) | Xong | Widget test + đọc lại mã migration; **chưa quét thử bằng Google Authenticator thật** |
| Thanh độ mạnh khi sửa mục, sắp xếp (tên/mới sửa/mới tạo), dọn thùng rác, mở link, màn Tài khoản | Xong | Widget test |
| Logo ~85 dịch vụ nổi tiếng thay chữ cái đầu (Simple Icons, CC0; phông cắt còn 26 KB), bật/tắt trong Cài đặt → Chung | Xong | Test nhận diện; **Microsoft, Amazon, LinkedIn, Slack, OpenAI không có trong bộ (đã bị gỡ theo yêu cầu chủ thương hiệu)** |
| Mã 2FA, mật khẩu, ghi chú ẩn mặc định ở màn chi tiết (tự ẩn lại sau 30 giây) và ở màn sửa | Xong | Widget test |
| Chữ hệ thống lớn (x2), danh sách 500 mục, nhãn trình đọc màn hình | Xong | Widget test ở 320 và 412 px |
| Bộ cài Windows (Inno Setup, cài cho người dùng hiện tại, kèm VC++ runtime), bản zip dùng ngay | Xong | `app/scripts/build-windows.cmd`; **chưa thử trên máy Windows sạch** |
| CI: push tag `v1.2.3` build Android, Windows, iOS (chưa ký) và tạo GitHub Release; Android ký bằng khóa phát hành | Xong | **Chưa chạy với tag thật** |
| Kiểm tra bản mới (bấm tay, hỏi GitHub Releases), trang giấy phép gồm cả phông chữ | Xong | `update_check_test.dart` |
| Đổi mật khẩu tài khoản máy chủ, xóa tài khoản (xóa cả kho trên máy chủ) | Xong | Test đầu cuối `account_e2e_test.dart` |

## Chưa làm, cần quyết định hoặc thông tin từ chủ dự án

1. **Triển khai máy chủ Cloudflare** (cần tài khoản Cloudflare của bạn): làm theo `server/README.md`, khoảng 10 phút. Mã đã xong và đã test, nhưng chưa từng chạy trên Cloudflare thật.
2. **Google Drive** (M4): cần project Google Cloud, bật Drive API, tạo OAuth client Android và Desktop.
3. **Đăng nhập Google vào máy chủ**: server đã có, app chưa có nút (cần OAuth client ID của bạn).
4. **Phát hành**: đã có khóa ký Android và bộ cài Windows. Còn thiếu chứng chỉ ký Windows (không có thì SmartScreen cảnh báo) và tài liệu công khai (xem `site/CONTENT-PLAN.md`).
5. **Rà soát độc lập** định dạng file và mã mật mã (M7).

## Giới hạn đã biết

- Mật mã chạy thuần Dart, chưa có người ngoài rà soát.
- iOS và macOS: sinh trắc vẫn chỉ là lớp chặn của app (mật khẩu cất trong Keychain), chưa gắn khóa.
- Đồng bộ qua thư mục chỉ dùng được trên máy tính (Android không đọc được thư mục SAF bằng đường dẫn).
- Làm chậm khi nhập sai chỉ nằm trong bộ nhớ (khởi động lại app là hết); sức mạnh thật nằm ở Argon2id.
- Cấu hình chuẩn Argon2id (3 vòng, 64 MiB) đo ~1,3 giây trên Note10+; máy yếu hơn có thể 3 đến 4 giây.
- Kho đồng bộ qua Cloudflare tối đa ~1,5 MB (giới hạn dòng của D1); quá thì cần chuyển sang R2.
- Lỗi đã bắt được nhờ test đầu cuối: `Isolate.run` đặt trong phương thức của VaultController kéo theo `this` (có Timer) nên bị "unsendable". Mọi phép Argon2id nay đi qua `lib/app/isolate_ops.dart`.
