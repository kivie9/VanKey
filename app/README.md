# VanKey: app Flutter

App Android, Windows (và iOS chưa ký) của VanKey. Tổng quan dự án ở [README gốc](../README.md).

## Cấu trúc

```
lib/main.dart          điểm vào: khởi tạo, đăng ký giấy phép phông chữ, chọn màn đầu
lib/core/              lõi Dart thuần, không phụ thuộc Flutter (xem docs/core-api.md)
  crypto/ vault/       mật mã, file kho .vkv, gộp 3 bên
  totp/                2FA (TOTP, HOTP, Steam Guard)
  import_export/       nhập từ app khác, xuất CSV/link/QR
  security/            sinh mật khẩu, độ mạnh, trùng lặp, HIBP, nhắc nhở
  sync/                đồng bộ Cloudflare, Google Drive, thư mục
  notify/ platform/    lịch nhắc nhở, giao tiếp với hệ điều hành
lib/app/               giao diện và trạng thái
  vault_controller.dart  trạng thái kho, khóa/mở, đồng bộ
  isolate_ops.dart       mọi phép Argon2id chạy ở isolate riêng
  platform_bridge.dart   gọi mã gốc (FLAG_SECURE, Windows Hello...)
  i18n.dart, i18n_en.dart  chuỗi tiếng Việt là khóa, bản dịch tiếng Anh
  screens/ widgets/      màn hình và thành phần dùng chung
test/                  test lõi, giao diện, đầu cuối (e2e), vector đối chiếu
tool/                  import_check (thử nhập file thật), make_icon, interop (đối chiếu libsodium)
scripts/               build và cài đặt bấm đúp trên Windows
installer/vankey.iss   bộ cài Windows (Inno Setup 6)
```

## Lệnh hay dùng

```powershell
flutter test                      # toàn bộ test (e2e cần Node 22.6+, không có thì tự bỏ qua)
flutter analyze                   # phải sạch
flutter run --release -d <máy>    # bản debug chậm rất nhiều với Argon2id
dart run tool/import_check.dart <file> --titles --codes
```

## Build và cài

| Việc | Cách |
|---|---|
| Cài lên điện thoại đang cắm USB, giữ dữ liệu | `scripts\install-android.cmd` |
| Build Windows, tạo bộ cài và cài đè | `scripts\build-windows.cmd` (cần Inno Setup 6) |
| Tạo khóa ký Android (một lần) | `scripts\create-android-signing-key.cmd` |
| Bản phát hành cả 3 nền tảng | push tag `v1.2.3`, CI ở `.github/workflows/build.yml` tạo GitHub Release |

Số phiên bản hiện trong app lấy từ `--dart-define=APP_VERSION=...` (CI tự đặt theo tag). Build tay không đặt thì app ghi `dev`.

## Nơi lưu dữ liệu

- Windows: kho ở `%APPDATA%\com.vankey\vankey`, app cài ở `%LOCALAPPDATA%\Programs\VanKey`. Gỡ app không xóa kho.
- Android: thư mục dữ liệu riêng của app. Gỡ app là mất kho, nên sao lưu trước.

## Quy tắc khi sửa

- Chuỗi giao diện viết bằng tiếng Việt trong `tr('...')` và thêm bản tiếng Anh vào `i18n_en.dart` (test `i18n_test.dart` bắt chuỗi thiếu).
- Không gọi Argon2id trực tiếp trong `VaultController`, đi qua `isolate_ops.dart`.
- Đổi định dạng file kho thì cập nhật `docs/vault-format.md` và vector trong `test/vectors/`.
