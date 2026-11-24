# Nhật ký quyết định

Mỗi dòng: **quyết định, lý do, ngày, trạng thái.** Trạng thái: `chốt` (đã quyết), `đề xuất` (chưa được xác nhận), `chờ M0` (chờ kết quả đo/thử).

| # | Quyết định | Lý do | Ngày | Trạng thái |
|---|---|---|---|---|
| D1 | Dùng **Flutter** (Dart), một codebase cho Windows và Android | Giảm một nửa công sức; giao diện giống nhau; phần riêng nền tảng nhỏ | 2026-11-19 | chốt |
| D2 | **Mã hóa đầu-cuối, zero-knowledge** (nơi lưu trữ không đọc được) | Yêu cầu cốt lõi của app quản lý mật khẩu | 2026-11-19 | chốt |
| D3 | Dùng **keyslot**: vault key ngẫu nhiên, bọc bởi passphrase / recovery / device | Đổi passphrase không mã hóa lại cả kho; nhiều cách mở | 2026-11-19 | đề xuất |
| D4 | **Argon2id + XChaCha20-Poly1305**. Dùng package **`cryptography` (thuần Dart)** đặt sau giao diện `Kdf`/`Aead` của dự án; libsodium gốc (`sodium_libs`) là phương án nâng cấp về sau, cùng thuật toán nên không đổi định dạng | Spike M0: 7 test qua (gồm test vector chính thức), **khớp byte-cho-byte với libsodium độc lập**; chạy được bằng `flutter test`; Argon2id 64 MiB x3 = 0,88 s trên PC | 2026-11-19 | chốt tạm (đã kiểm chứng trên Windows; **Android chưa đo**, xem `spike-m0.md`) |
| D5 | Đồng bộ **Google Drive trước**, Cloudflare làm song song sau | Drive không cần server riêng; giao diện `SyncProvider` đã tách | 2026-11-19 | đề xuất |
| D6 | Giai đoạn đầu **chỉ cho phép email trong danh sách của chủ** (không đăng ký tự do) | Bỏ phần xác minh email, quên mật khẩu, chống spam; giảm bề mặt tấn công | 2026-11-19 | đề xuất |
| D7 | **Vault passphrase tách khỏi mật khẩu đăng nhập**; đăng nhập Google/email không đủ để giải mã | Server bị lộ hay tài khoản bị chiếm vẫn không lộ dữ liệu | 2026-11-19 | chốt |
| D8 | Nhắc hết hạn bằng **thông báo cục bộ**, chưa dùng push từ server | Máy tự tính được; server không biết ngày hết hạn do mã hóa | 2026-11-19 | chốt cho bản đầu |
| D9 | Prototype HTML là **nguồn sự thật của giao diện** | Đã được duyệt qua nhiều vòng; nằm trong `docs/prototype/` | 2026-11-19 | chốt |
| D10 | Ngôn ngữ: **tiếng Việt mặc định, tiếng Anh**, dùng file ARB | Người dùng đầu tiên là người Việt | 2026-11-19 | chốt |
| D11 | Xóa mục = **chuyển vào thùng rác 30 ngày**; xóa vĩnh viễn để lại tombstone | Xóa nhầm mã 2FA là mất quyền vào tài khoản | 2026-11-19 | chốt |
| D12 | Chuẩn hóa passphrase **NFKC** trước khi băm | Tiếng Việt có chữ tổ hợp; tránh mở được ở máy này mà không mở được ở máy kia | 2026-11-19 | đề xuất |
| D13 | Cài đặt giao diện (chủ đề, ngôn ngữ, mật độ) **chỉ lưu cục bộ**, không đồng bộ | Mỗi thiết bị có nhu cầu khác nhau; giữ kho nhỏ | 2026-11-19 | đề xuất |
| D14 | Tên app: **VanKey** (thay tên làm việc KeyManager) | Chủ dự án chọn | 2026-11-19 | chốt |
| D15 | Package id: `com.vankey.vankey`; định dạng kho đổi theo tên: đuôi `.vkv`, magic `VKV1`, xuất sao lưu `.vkbackup` | Không chứa thông tin cá nhân; định dạng còn ở bản nháp nên đổi tên được tự do trước khi có dữ liệu thật | 2026-11-19 | đề xuất (đổi được đến lúc phát hành lên cửa hàng) |
| D16 | **Gộp ba chiều** (local, remote, bản chung đã đồng bộ) thay cho `parentHlc` | `parentHlc` báo xung đột sai khi một máy sửa nhiều lần liên tiếp rồi mới đồng bộ | 2026-11-19 | chốt (đã cài đặt và kiểm bằng property test) |
| D17 | Trường mục có **`key` ổn định** cho trường theo mẫu, `label` chỉ cho trường tự thêm | Giao diện dịch nhãn theo ngôn ngữ; prototype lưu nhãn tiếng Việt cứng nên không đa ngôn ngữ được | 2026-11-19 | chốt |
| D18 | v1 chỉ hỗ trợ **TOTP**; HOTP và Steam bị bỏ qua khi nhập, có cảnh báo | Hiếm gặp; tránh phải đồng bộ bộ đếm giữa các máy | 2026-11-19 | đề xuất |
| D19 | Protobuf của Google Authenticator **viết tay** (không dùng thư viện `protobuf`) | Chỉ cần đọc/ghi 2 thông điệp nhỏ; ít phụ thuộc; có kiểm biên | 2026-11-19 | chốt |
| D20 | Tìm kiếm **không bao giờ** xét trường bí mật; so khớp bỏ dấu tiếng Việt | Kết quả khớp có thể làm lộ nội dung bí mật | 2026-11-19 | chốt |
| D21 | Xuất CSV giữ **nguyên văn** dữ liệu, không thêm ký tự chống công thức Excel | Thêm ký tự sẽ làm đổi mật khẩu; thay vào đó giao diện cảnh báo file không mã hóa | 2026-11-19 | đề xuất |

## Chưa quyết định

| Câu hỏi | Đề xuất | Cần trước |
|---|---|---|
| Xác nhận package id `com.vankey.vankey` | Dùng như đề xuất D15 | M0 (đổi sau khi phát hành lên cửa hàng là không thể) |
| Tra tên **VanKey** (cửa hàng ứng dụng, tên miền, thương hiệu) nếu định phát hành rộng | Chưa tra | M7 |
| Android tối thiểu | API 26 (Android 8.0) | M2 |
| Windows có cần thông báo khi đóng hẳn app? | Chạy nền ở khay hệ thống, hoặc MSIX hẹn giờ | M6 |
| Tham số Argon2id cuối cùng | Dự kiến 3 vòng, 64 MiB; chốt theo đo | M0 |
| Cloudflare thay hẳn hay song song Drive | Song song | M4 |
| Giấy phép mã nguồn | Chưa chọn | M7 |
| Phân phối Windows: MSIX tự ký hay Microsoft Store | Tự ký cho dùng cá nhân | M7 |

## Môi trường đã cài

| Thành phần | Phiên bản / vị trí | Ngày | Ghi chú |
|---|---|---|---|
| Flutter SDK | 3.50.0 stable, Dart 3.14.0, tại `E:\code\libs\flutter` | 2026-11-19 | `flutter doctor`: Flutter OK, Windows OK, Chrome OK |
| Android SDK (bản nhẹ, không Android Studio, không máy ảo) | `cmdline-tools` 23.0 (Android CLI 1.1), `platform-tools` 37.0.1, `platforms;android-36`, `build-tools;36.0.0`, tại `E:\code\libs\android-sdk`. NDK 28.2 sẽ do Gradle tải khi build cần | 2026-11-19 | `flutter doctor`: Android toolchain OK, "All Android licenses accepted". `ANDROID_HOME` đã đặt. Flutter 3.50 mặc định `minSdk 24`, `compileSdk 36`; kế hoạch dùng API 26 (chỉnh ở M2) |
| Visual Studio (C++ desktop) | **chưa cài** | | Cần để build app Windows (M2) |
| ffmpeg | 6.1.1 full build (gyan.dev) tại `E:\code\libs\ffmpeg` | 2026-11-19 | Không thuộc dự án VanKey; chỉ ghi vị trí. **Không** nằm trong PATH |

Quy ước thư mục công cụ: mọi công cụ dùng chung nằm dưới `E:\code\libs\` (hiện có `flutter`, `ffmpeg`, `android-sdk`).