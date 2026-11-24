# VanKey

Quản lý mật khẩu, khóa và mã 2FA (TOTP), mã hóa đầu cuối, dùng được khi không có mạng, đồng bộ giữa các thiết bị.
Thay cho Google Authenticator và có thể nhập thẳng từ đó.

- Kế hoạch: [PLAN.md](PLAN.md) · Việc cần làm: [docs/TASKS.md](docs/TASKS.md) · Tình trạng: [docs/STATUS.md](docs/STATUS.md)
- Định dạng file kho: [docs/vault-format.md](docs/vault-format.md) · Mô hình đe dọa: [docs/threat-model.md](docs/threat-model.md)
- Lõi cho người viết giao diện: [docs/core-api.md](docs/core-api.md)

## Cấu trúc

```
app/lib/core/   lõi Dart thuần (mật mã, kho, TOTP, nhập/xuất, bảo mật, đồng bộ), không phụ thuộc Flutter
app/lib/app/    giao diện và trạng thái (VaultController, màn hình, đa ngôn ngữ vi/en)
app/test/       test lõi, đồng bộ, giao diện, chuỗi dịch
app/tool/       công cụ dòng lệnh (import_check: thử bộ nhập với file thật; interop: đối chiếu libsodium)
server/         máy chủ Cloudflare Worker + D1 (tùy chọn): xem server/README.md
docs/           tài liệu
```

## Build và chạy

Cần Flutter (đường dẫn dự án: `E:\code\libs\flutter`), Android SDK, và **Chế độ nhà phát triển** của Windows (cho symlink plugin).

```powershell
cd app
flutter test                                   # toàn bộ test
flutter analyze                                # phải sạch
# test đầu cuối cần Node 22.6+ (tự chạy server/dev/serve.ts); không có Node thì tự bỏ qua
flutter run --release -d <mã thiết bị>         # cài lên điện thoại (dùng release, bản debug chậm rất nhiều với Argon2id)
dart run tool/import_check.dart <file> --titles --codes   # thử nhập file xuất thật, in mã 2FA để so với app cũ
```

Lưu ý: dự án ở ổ khác với pub cache nên `android/gradle.properties` đặt `kotlin.incremental=false`.

## Bảo mật: điều cần nhớ

- Mất mật khẩu **và** mã khôi phục thì không ai mở lại được kho, kể cả nhà phát triển.
- File xuất không mã hóa và link migration của Google Authenticator chứa bí mật: xóa sau khi dùng, không dán lên web.
- Định dạng file chưa được người ngoài rà soát.
