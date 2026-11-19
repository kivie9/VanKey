# VanKey — Kế hoạch triển khai

> Cập nhật: 2026-11-19 · Trạng thái: **đã chốt thiết kế giao diện (prototype), chưa có code**

App quản lý mật khẩu, khóa API, ghi chú bảo mật và **mã 2FA (TOTP)**, chạy trên **Windows** và **Android**, đồng bộ giữa các thiết bị, mã hóa đầu-cuối. Thay thế Google Authenticator (hiện không đồng bộ giữa các máy).

- Prototype giao diện (tương tác được): <https://claude.ai/artifact/Fv4VszCjKj7kUfG4cdwRdf> (riêng tư, chỉ chủ sở hữu mở được)
- Bản lưu trong dự án: [`docs/prototype/vankey-prototype.html`](docs/prototype/vankey-prototype.html) — mở bằng trình duyệt, không cần server

---

## 1. Mục tiêu và phạm vi

### Mục tiêu
1. Một nơi lưu mọi tài khoản, khóa, ghi chú nhạy cảm, **mã 2FA tự sinh**, đồng bộ trên máy tính và điện thoại.
2. **Zero-knowledge:** nơi lưu trữ (Google Drive hoặc server Cloudflare) không bao giờ đọc được nội dung.
3. Dùng offline đầy đủ. Đồng bộ là tùy chọn.
4. Chuyển được hết dữ liệu từ Google Authenticator, Bitwarden, 1Password, KeePass, Chrome.

### Không nằm trong bản đầu (xem mục 12)
Tự điền mật khẩu (Android Autofill), extension trình duyệt, push notification từ server, tệp đính kèm, chia sẻ giữa nhiều người, passkey, truy cập khẩn cấp.

### Nguyên tắc thiết kế
- **Không tự chế mật mã.** Chỉ dùng thuật toán và thư viện đã được kiểm chứng rộng rãi.
- **Một codebase** (Flutter) cho cả hai nền tảng; phần riêng từng nền tảng được che sau interface.
- **Định dạng dữ liệu chốt sớm và có version**, vì extension và server sau này phải đọc cùng định dạng.
- Giao diện tối giản, ít chữ giải thích, mặc định an toàn.

---

## 2. Công nghệ

| Phần | Lựa chọn | Ghi chú |
|---|---|---|
| App | **Flutter** (Dart), kênh stable | Windows + Android từ một codebase |
| State | `flutter_riverpod` | |
| Mật mã | **libsodium** qua `sodium_libs` (Argon2id, XChaCha20-Poly1305) | **Cần kiểm chứng ở M0**: chạy được trên cả Windows và Android, tốc độ Argon2id chấp nhận được. Phương án dự phòng: `cryptography` + `pointycastle` |
| TOTP | Tự viết (khoảng 50 dòng) trên `crypto` (HMAC SHA1/256/512) | RFC 6238, kiểm bằng test vector chính thức |
| Import Google Authenticator | `protobuf` giải mã `otpauth-migration://` | |
| Quét QR | Android: `mobile_scanner`. Windows: `zxing2` (đọc ảnh) | |
| Lưu khóa thiết bị | `flutter_secure_storage` (Android Keystore, Windows Credential Manager) | |
| Sinh trắc | `local_auth` (vân tay, khuôn mặt, Windows Hello) | |
| Thông báo cục bộ | `flutter_local_notifications` + phần riêng cho Windows | Xem mục 9 |
| Đa ngôn ngữ | `flutter_localizations` + file ARB (**vi** mặc định, **en**) | |
| Cửa sổ Windows | `window_manager`, `tray_manager` | Chạy nền ở khay hệ thống |
| Đồng bộ Drive | `googleapis` (Drive v3), `googleapis_auth` (Windows), `google_sign_in` (Android) | Chỉ scope `drive.appdata` |
| Server (tùy chọn) | **Cloudflare Worker** (TypeScript + Hono), **D1** | Chỉ lưu blob đã mã hóa |
| Test | `flutter_test`, test vector RFC, property test cho merge | |

---

## 3. Kiến trúc

```
keymanager/
├─ PLAN.md
├─ docs/
│  ├─ prototype/vankey-prototype.html     # thiết kế giao diện (đã có)
│  ├─ vault-format.md                         # đặc tả định dạng file (viết ở M1)
│  └─ threat-model.md                         # mô hình đe dọa (viết ở M1)
├─ app/                                       # Flutter
│  ├─ lib/
│  │  ├─ core/
│  │  │  ├─ crypto/        # KDF, AEAD, keyslot, bộ nhớ an toàn
│  │  │  ├─ vault/         # mô hình dữ liệu, serialize, merge
│  │  │  ├─ totp/          # sinh mã, parse otpauth, migration protobuf
│  │  │  ├─ import_export/ # Bitwarden, 1Password, KeePass, CSV, otpauth
│  │  │  ├─ sync/          # SyncProvider, DriveSync, CloudflareSync, SyncService
│  │  │  ├─ notify/        # tính lịch nhắc, đặt lại lịch
│  │  │  └─ platform/      # interface riêng từng nền tảng
│  │  ├─ features/         # vault, totp, quick_view, generator, settings, ...
│  │  └─ l10n/             # vi, en
│  └─ test/
├─ server/                                    # Cloudflare Worker (M5)
└─ extension/                                 # sau này
```

**Lớp tách biệt:** `core/` là Dart thuần, **không phụ thuộc Flutter UI**, nên test được bằng `dart test` mà không cần thiết bị. `features/` chỉ gọi vào `core/`.

---

## 4. Mô hình bảo mật và định dạng dữ liệu

### 4.1 Phân cấp khóa (keyslot)
```
vault key (32 byte ngẫu nhiên)  ──mã hóa──>  toàn bộ dữ liệu kho
       ▲
       │ được "bọc" (wrap) bởi một hoặc nhiều keyslot:
       ├─ passphrase  : Argon2id(vault passphrase, salt, tham số) → KEK
       ├─ recovery    : khóa khôi phục sinh ngẫu nhiên → KEK
       └─ device      : khóa ngẫu nhiên cất trong kho an toàn của OS (mở nhanh)
```
- **Đổi passphrase = bọc lại vault key**, không phải mã hóa lại cả kho.
- Chế độ **offline, không tài khoản:** có thể chỉ dùng keyslot `device`. Khóa app bằng mật khẩu là tùy chọn.
- Chế độ **đồng bộ:** bắt buộc có keyslot `passphrase` và `recovery`. Thiết bị mới đăng nhập phải nhập passphrase hoặc recovery key một lần.
- Passphrase **không bao giờ** gửi đi. Đăng nhập tài khoản (Google, email) và vault passphrase là hai thứ tách biệt.

### 4.2 File `vault.vkv`
```
magic "VKV1" | version | keyslots[] | nonce(24) | ciphertext(JSON, XChaCha20-Poly1305)
```
- KDF: Argon2id, tham số lưu trong từng keyslot để nâng cấp sau.
- Nonce mới cho mỗi lần ghi. Ghi file theo kiểu "ghi ra file tạm rồi đổi tên".
- Đặc tả đầy đủ viết trong `docs/vault-format.md` **trước khi** viết code mã hóa, kèm test vector dùng chung cho Dart và TypeScript.

### 4.3 Dữ liệu bên trong
```
Item {
  id (uuid), type: login|totp|key|crypto|card|wifi|note,
  title, fields[ {label, value, secret, kind} ],
  totp? { secret, algo, digits, period },
  group, favorite,
  pwHistory[ {value, changedAt} ],
  reminder? { months, noticeDays, lastChangedAt },
  createdAt, updatedAt, deletedAt?   // deletedAt != null  => trong thùng rác
}
```
- Cài đặt giao diện (chủ đề, ngôn ngữ, mật độ) lưu **cục bộ, không đồng bộ**.
- Dòng phụ trong danh sách **chỉ lấy trường không bí mật** (bài học từ prototype: không được hiện cụm từ khôi phục ra ngoài).

### 4.4 Mô hình đe dọa (tóm tắt, chi tiết ở `docs/threat-model.md`)
| Bảo vệ được | **Không** bảo vệ được |
|---|---|
| Lộ dữ liệu từ Drive, server Cloudflare, mạng | Máy đã nhiễm mã độc, keylogger |
| Mất điện thoại (khi khóa app + khóa màn hình) | Passphrase yếu bị đoán |
| Server bị xâm nhập | Người dùng mất cả passphrase lẫn recovery key |

Quy tắc: không ghi log dữ liệu nhạy cảm, không analytics/telemetry, xóa khóa khỏi RAM khi khóa app (cố gắng tối đa, Dart có GC nên không tuyệt đối), chặn chụp màn hình (Android `FLAG_SECURE`), xóa clipboard sau 30 giây, đánh dấu clipboard là nhạy cảm trên Android.

---

## 5. Đồng bộ

Giao diện chung:
```dart
abstract class SyncProvider {
  Future<RemoteVault?> download();                       // trả về blob + version
  Future<void> upload(Uint8List blob, {required String ifVersion});
}
```
- **Merge theo từng mục:** gộp theo `id`, bản có `updatedAt` mới hơn thắng. Mục bị xóa giữ lại để lan truyền việc xóa (`deletedAt`).
- Dùng **đồng hồ lai (HLC)** thay vì giờ máy thuần để tránh lệch giờ giữa các thiết bị. Hai thiết bị cùng sửa một mục từ cùng một bản gốc → hiện **xung đột** cho người dùng chọn (không ghi đè âm thầm).
- Upload dùng kiểm tra phiên bản; thất bại thì tải lại, merge, upload lại.
- Đồng bộ khi: mở app, sau mỗi lần sửa (có trễ gộp), nút đồng bộ tay.

### 5.1 Google Drive (`DriveSync`)
- Thư mục ẩn `appDataFolder`, scope `drive.appdata` (không nhạy cảm nên không cần Google xác minh app).
- Windows: mở trình duyệt, OAuth loại **Desktop app**, nhận mã qua `http://127.0.0.1:<port>`. Android: `google_sign_in`.
- **Phải đưa OAuth consent screen sang "In production"**, nếu để "Testing" thì refresh token hết hạn sau 7 ngày.

### 5.2 Cloudflare (`CloudflareSync`, M5)
- `GET /vault` → `{version, blob}`; `PUT /vault` kèm `If-Match`, trả 409 khi lệch phiên bản.
- Auth: access token ngắn hạn + refresh token (lưu hash trong D1, thu hồi từng thiết bị).
- Đăng nhập: **Google** (xác minh ID token bằng JWKS), và email + mật khẩu (băm phía client bằng Argon2id rồi server băm lần nữa). Cân nhắc **Better Auth** thay vì tự viết.
- Bản đầu: **chỉ cho phép email trong danh sách của chủ**, bỏ xác minh email, quên mật khẩu, đăng ký tự do.
- Giới hạn tốc độ đăng nhập, giới hạn kích thước body, bắt buộc HTTPS.

---

## 6. Danh sách chức năng (khớp với prototype)

**Kho**
- 7 loại mục: Đăng nhập, Chỉ 2FA, API key, Ví crypto, Thẻ, Wi-Fi, Ghi chú. Mỗi loại có mẫu trường riêng, thêm trường tùy ý, mã dự phòng 2FA.
- Gom theo Nhóm / Loại / Không; lọc theo nhóm; yêu thích; tìm kiếm (không tìm trong trường bí mật).
- Hiện/ẩn, copy một chạm; mã 2FA hiện ngay trong danh sách, bấm để copy.
- Thùng rác 30 ngày, lịch sử mật khẩu, đổi mật khẩu.

**2FA**
- Danh sách mã có đếm ngược, copy nhanh; **Xem nhanh** bằng key (không lưu).
- Quét QR (Android camera, Windows đọc ảnh), dán link `otpauth://`.
- Hỗ trợ SHA1/256/512, 6 và 8 chữ số, chu kỳ 30 và 60 giây.

**Dữ liệu**
- Nhập: Google Authenticator (QR xuất tài khoản), Aegis/2FAS, Bitwarden, 1Password, KeePass, Chrome/Edge (CSV), nhiều link `otpauth://`. Cảnh báo trùng, xem trước, chọn nhóm đích.
- Xuất: sao lưu mã hóa, link `otpauth://`, CSV (có cảnh báo, bắt nhập passphrase).
- Tìm mục trùng lặp (trùng mã 2FA, trùng tên + tài khoản, dùng chung mật khẩu), gộp.

**Bảo mật**
- Khóa app tùy chọn (master password, sinh trắc, tự khóa, khóa khi thu nhỏ).
- Kiểm tra bảo mật: mật khẩu yếu, dùng chung, chưa bật 2FA, rò rỉ (tra HaveIBeenPwned kiểu k-anonymity, chỉ gửi 5 ký tự đầu mã băm).
- Mã khôi phục (xem sau khi xác thực, tạo mới có xác nhận), đổi vault passphrase, đổi mật khẩu đăng nhập.

**Thông báo cục bộ** — xem mục 9.

**Tài khoản và đồng bộ** — đăng nhập Google/email, danh sách thiết bị (gỡ từ xa), chọn Cloudflare hoặc Drive, đồng bộ tay.

**Giao diện / chung** — chủ đề (hệ thống, sáng, tối), màu nhấn, mật độ danh sách; ngôn ngữ vi/en; tạo mật khẩu (có thanh đo độ mạnh); Hỗ trợ, Giới thiệu.

---

## 7. Lộ trình (milestone)

Ước lượng **thô** cho một người làm, chưa tính thời gian thử trên máy thật.

| # | Milestone | Nội dung | Tiêu chí hoàn thành | Cỡ |
|---|---|---|---|---|
| **M0** | Thiết lập | Cài Flutter, dựng project, **spike mật mã** (Argon2id + XChaCha20 chạy trên Windows và Android, đo thời gian) | `flutter doctor` sạch; spike chạy trên cả hai nền tảng | 0,5–1 tuần |
| **M1** | **Lõi (Dart thuần)** | Đặc tả định dạng, keyslot, mã hóa/giải mã, TOTP, `otpauth`/migration, merge, parser import | Toàn bộ test qua, gồm test vector RFC 6238 và test vector định dạng file | 1–2 tuần |
| **M2** | App offline | Giao diện theo prototype: kho, chi tiết, form theo loại, 2FA, Xem nhanh, tạo mật khẩu, nhóm, thùng rác, lịch sử, cài đặt (chủ đề, ngôn ngữ) | Dùng được hằng ngày trên Windows và Android, không cần mạng | 3–4 tuần |
| **M3** | Bảo mật thiết bị | Khóa app, sinh trắc, tự khóa, xóa clipboard, chặn chụp màn hình, kiểm tra bảo mật | Checklist bảo mật qua trên máy thật | 1 tuần |
| **M4** | Đồng bộ Drive | `DriveSync`, đăng nhập Google hai nền tảng, `SyncService`, xử lý xung đột | Sửa trên máy tính, điện thoại nhận được; hai máy sửa cùng lúc không mất dữ liệu | 1–2 tuần |
| **M5** | Cloudflare + tài khoản | Worker, D1, auth, danh sách thiết bị, `CloudflareSync` | Đồng bộ qua server; thu hồi thiết bị hoạt động | 2 tuần |
| **M6** | Nhập/xuất, QR, nhắc nhở | Quét QR, nhập mọi nguồn, xuất, tìm trùng, thông báo hết hạn | Chuyển hết dữ liệu từ Google Authenticator thành công trên máy thật | 1–2 tuần |
| **M7** | Đóng gói và phát hành | MSIX cho Windows, APK ký cho Android, tài liệu, rà soát bảo mật | Bản cài được trên máy sạch | 1 tuần |

**Danh sách việc chi tiết cho từng milestone** (từng bước, kèm tiêu chí xong): [`docs/TASKS.md`](docs/TASKS.md).

**Thứ tự có chủ ý:** M1 (lõi mã hóa) làm **trước giao diện**, vì sai ở đây là sai toàn bộ. Có thể bắt đầu M1 ngay khi cài xong Flutter SDK, chưa cần Visual Studio hay Android.

---

## 8. Kiểm thử

- **Mật mã:** test vector đã biết cho Argon2id, XChaCha20-Poly1305; thử file hỏng, sai khóa, sai nonce phải **thất bại đúng cách**, không crash.
- **TOTP:** test vector RFC 6238 (SHA1, SHA256, SHA512 tại các mốc 59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000). Test chuyển bước 30 giây.
- **Merge:** property test (giao hoán, kết hợp, lũy đẳng), kịch bản hai thiết bị sửa/xóa đồng thời.
- **Import:** mẫu thật xuất từ từng nguồn (đã xóa dữ liệu nhạy cảm).
- **Đồng bộ:** `FakeSyncProvider` trong bộ nhớ để test luồng mà không cần mạng.
- **Thủ công trên máy thật:** quét QR, sinh trắc, thông báo hẹn giờ, khởi động lại máy, đổi múi giờ, mất mạng giữa chừng.
- **Trước phát hành:** nhờ người có chuyên môn rà soát đặc tả định dạng và phần mật mã.

---

## 9. Thông báo nhắc hết hạn

Chạy **cục bộ**, không cần server. App tính ngày rồi nhờ hệ điều hành hẹn giờ.

- Hạn mật khẩu = ngày đổi gần nhất + số tháng; báo trước N ngày. Thẻ và API key đọc từ trường hạn.
- **Đặt lại lịch** mỗi khi dữ liệu hoặc cài đặt đổi, và sau khi đồng bộ về.
- **Android:** `AlarmManager`/WorkManager; xin quyền thông báo (Android 13+), quyền báo thức chính xác (12+); **đặt lại lịch sau khi khởi động máy**; một số hãng (Xiaomi, Oppo, Samsung) tắt app nền mạnh nên có thể trễ.
- **Windows:** thông báo hẹn giờ của Windows chạy khi app đóng nếu đóng gói **MSIX**; Flutter chưa hỗ trợ sẵn phần hẹn giờ nên cần viết một đoạn kết nối riêng. Phương án đơn giản hơn: app chạy nền ở khay hệ thống và kiểm tra mỗi ngày.
- **Nội dung thông báo không chứa bí mật:** chỉ tên dịch vụ và hạn.
- **Push từ server** (cảnh báo đăng nhập thiết bị mới, đồng bộ nền): để sau, chỉ khi dùng đồng bộ Cloudflare. Phương án thay thế không cần server: Android tự kiểm tra định kỳ trong nền (chậm vài phút).

---

## 10. Thiết lập môi trường

Máy hiện có: Git, Node, Java. **Chưa có:** Flutter, Visual Studio, Android SDK.

**Bước 1 — chỉ Flutter SDK** (đủ để làm M0, M1 và chạy test):
```powershell
git clone https://github.com/flutter/flutter.git -b stable E:\code\flutter
# thêm E:\code\flutter\bin vào PATH, mở terminal mới
flutter doctor
```
**Bước 2 — khi làm giao diện Windows (M2):** Visual Studio 2022 Community, tick **Desktop development with C++**.

**Bước 3 — khi làm Android (M2 trở đi):** Android Studio (kèm SDK), và nên có **một điện thoại Android thật** bật gỡ lỗi USB. Quét QR, sinh trắc và thông báo hẹn giờ không thử đáng tin trên máy giả lập.

**Bước 4 — khi làm M4:** tạo project Google Cloud, bật Drive API, tạo hai OAuth client (Desktop app và Android; Android cần SHA-1 của keystore), đưa consent screen sang "In production".

**Bước 5 — khi làm M5:** tài khoản Cloudflare, cài `wrangler`, tạo D1.

---

## 11. Rủi ro

| Rủi ro | Mức | Cách giảm |
|---|---|---|
| Thư viện libsodium không chạy tốt trên một nền tảng | Cao | **Spike ở M0**; có phương án dự phòng |
| Lỗi thiết kế định dạng, phải đổi sau khi đã có dữ liệu | Cao | Đặc tả có version, test vector, keyslot cho phép nâng cấp; rà soát trước khi dùng thật |
| Người dùng mất passphrase và recovery key | Cao | Ép lưu recovery key khi tạo tài khoản; nút xuất sao lưu; nói rõ không thể khôi phục |
| Thông báo hẹn giờ không đáng tin (Android hãng, Windows khi đóng app) | Trung bình | Thử máy thật; có phương án khay hệ thống |
| Mất tài khoản Cloudflare hoặc Google | Trung bình | Mỗi máy giữ bản đầy đủ; xuất sao lưu định kỳ |
| Lệch giờ giữa các thiết bị làm merge sai | Trung bình | HLC, hiện xung đột thay vì ghi đè |
| Rò rỉ qua clipboard, ảnh chụp màn hình, log | Trung bình | Xóa clipboard, `FLAG_SECURE`, không log dữ liệu nhạy cảm |
| Phạm vi lan rộng, mãi không xong lõi | Trung bình | Làm đúng thứ tự milestone; tính năng thêm vào mục 12 |

---

## 12. Để sau bản đầu

| Việc | Giá trị | Ghi chú |
|---|---|---|
| **Android Autofill Service** | Cao | Gần như là lý do chính để dùng app mật khẩu trên điện thoại; viết bằng Kotlin |
| **Extension trình duyệt** (Chrome/Edge/Firefox) | Cao | TypeScript riêng, đọc cùng định dạng file; đồng bộ trực tiếp với Drive hoặc server |
| Phím tắt toàn cục trên Windows | Trung bình | Bật cửa sổ nhỏ, gõ tên, copy mã 2FA |
| Widget màn hình chính Android | Trung bình | Hiện vài mã 2FA hay dùng |
| Push từ server | Trung bình | Cảnh báo thiết bị mới, đồng bộ nền |
| Tệp đính kèm | Thấp | Mã hóa file riêng |
| Chia sẻ, truy cập khẩn cấp, passkey | Thấp | Phức tạp về mật mã, chỉ làm nếu thật cần |

---

## 13. Quyết định cần chốt

| Câu hỏi | Đề xuất |
|---|---|
| Cloudflare thay Drive hay chạy song song? | **Song song** (giao diện `SyncProvider` đã tách). Làm Drive trước vì không cần server |
| Chỉ mình bạn dùng hay mở cho nhiều người? | **Chỉ bạn** (danh sách email cho phép). Mở rộng sau nếu cần |
| Thiết bị mới nhận khóa bằng gì? | Nhập vault passphrase hoặc recovery key (không dùng QR ở bản đầu) |
| Windows khi đóng app có cần thông báo? | Nếu có: chạy nền ở khay hệ thống (đơn giản) hoặc MSIX hẹn giờ |
| Tên app, package id, biểu tượng, giấy phép | Chưa đặt. Cần trước M7 |
| Android tối thiểu | Đề xuất Android 8.0 (API 26) trở lên |

---

## 14. Việc tiếp theo

1. Cài Flutter SDK (bước 1 mục 10).
2. M0: dựng project trong `app/`, chạy spike mật mã trên Windows (và Android nếu đã có).
3. Viết `docs/vault-format.md` và `docs/threat-model.md`.
4. M1: viết và test lõi.
