# VanKey — Danh sách việc chi tiết

> Đi kèm [`PLAN.md`](../PLAN.md). PLAN.md nói **làm gì và vì sao**; file này nói **làm từng việc cụ thể nào, theo thứ tự nào, xong khi nào**.
> Đánh dấu `[x]` khi xong. Mỗi việc xong nên có test (nếu có logic) rồi mới commit.

Ký hiệu: **(P)** = có mẫu giao diện trong prototype · **(T)** = cần test · **(⚠)** = rủi ro, cần kiểm chứng trên máy thật.

---

## Quy ước chung

- [ ] Mỗi milestone kết thúc bằng một commit có tag (`m0`, `m1`, ...).
- [ ] Không commit: khóa, token, `google-services`, keystore, file `.env`, dữ liệu thật. Thêm vào `.gitignore` từ đầu.
- [ ] `flutter analyze` sạch và `flutter test` qua trước mỗi commit.
- [ ] Không ghi log mật khẩu, khóa, mã 2FA, passphrase ở bất kỳ mức log nào.
- [ ] Chuỗi giao diện đi qua file ARB (vi, en), **không viết cứng** trong code.
- [ ] Quyết định kỹ thuật đã chốt ghi vào `docs/decisions.md` (một dòng mỗi quyết định: gì, vì sao, ngày).

---

## M0 — Thiết lập và kiểm chứng (0,5–1 tuần)

### Môi trường
- [x] Cài Flutter SDK: `git clone https://github.com/flutter/flutter.git -b stable E:\code\libs\flutter`
- [x] Thêm `E:\code\libs\flutter\bin` vào PATH, mở terminal mới, chạy `flutter doctor`
- [x] Chốt **tên app, package id**: VanKey, `com.vankey.vankey` (org `com.vankey` + tên project `vankey`)
- [x] `git init` trong `E:\code\project\keymanager` (nhánh `main`), đã có `.gitignore`
- [x] Tạo project: `flutter create --org com.vankey --project-name vankey --platforms=windows,android app`
- [x] Thiết lập lint (`analysis_options.yaml`, bật `flutter_lints` và các luật nghiêm hơn: `avoid_print`, `prefer_final_locals`...)
- [x] Dựng cây thư mục `lib/core/{crypto,vault,totp,import_export,sync,notify,platform}`, `lib/features`, `lib/l10n`
- [ ] Commit đầu tiên

### Spike mật mã (⚠ quyết định toàn dự án)
- [x] Thêm `cryptography` 2.9.0 (thuần Dart). **`sodium_libs` chưa thử** vì cần build bản Windows gốc (cần Visual Studio); xem `docs/spike-m0.md`
- [x] Viết chương trình thử: `app/test/spike/crypto_spike_test.dart` (7 test, gồm test vector chính thức XChaCha20-Poly1305) và `argon2_bench.dart`
- [x] Chạy được bằng `flutter test` (thuần Dart, không cần thư viện gốc)
- [x] Đo Argon2id 4 bộ tham số trên **Windows** (AOT): 64 MiB x3 vòng = 876 ms
- [ ] Nếu đã có điện thoại Android và Android SDK: đo trên **Android** thật (**SDK đã cài xong 2026-11-19**; còn thiếu điện thoại cắm USB + màn hình đo trên điện thoại)
- [ ] **Ngưỡng chấp nhận:** mở khóa ≤ ~1 giây trên PC và ≤ ~1,5 giây trên điện thoại tầm trung; bộ nhớ Argon2id từ 64 MiB trở lên
- [x] Đã đi theo phương án thuần Dart (`cryptography`) và **đối chiếu byte-cho-byte với libsodium độc lập: khớp**
- [x] Ghi kết quả vào `docs/spike-m0.md` và `docs/decisions.md` (D4)

**Xong khi:** `flutter doctor` không báo lỗi cho Windows; spike chạy được; đã chốt thư viện mật mã; có commit `m0`.

---

## M1 — Lõi Dart thuần (1–2 tuần)

> Toàn bộ nằm trong `lib/core/`, **không import Flutter UI**. Chạy test bằng `flutter test`.

### 1.1 Tài liệu (làm trước khi viết code mã hóa)
- [x] `docs/vault-format.md`: bố cục byte của file, header, keyslot, tham số KDF, JSON bên trong, quy tắc version. **Bản nháp v0.2, khớp với mã; chưa có người ngoài rà soát**
- [ ] `docs/vault-format.md`: **test vector.** Đã có vector nguyên thủy và bộ test file; **chưa có một file `.vkv` cố định** để TypeScript đọc chéo (cần khi làm extension/server)
- [x] `docs/threat-model.md`: bản nháp, cần xem lại sau M3

### 1.2 Mật mã cơ bản (`core/crypto`)
- [x] `Csprng` (`Random.secure()`), có giao diện `RandomSource` để test thay bằng nguồn cố định; `uuidV4`
- [x] `Kdf.argon2id` (kiểm cận tham số khi đọc) và `Kdf.hkdfSha256`
- [x] `Aead.seal / open` (XChaCha20-Poly1305) có AAD
- [ ] `SecureBytes`: **chưa làm lớp riêng**; hiện có `wipe` ở `RecoveryKey` và `VaultSession.close()` (mức cố gắng tối đa, Dart có bộ thu gom rác)
- [x] (T) Test vector chính thức, sai khóa/nonce/AAD, sửa bản mã/tag → lỗi đúng cách

### 1.3 Keyslot (`core/crypto/keyslot`)
- [x] Tạo vault key ngẫu nhiên 32 byte
- [x] Keyslot **passphrase**: Argon2id → KEK → bọc vault key (có chuẩn hóa NFKC)
- [x] Keyslot **recovery**: recovery key 24 ký tự (120 bit), KEK bằng HKDF-SHA256
- [ ] Keyslot **device** (khóa trong kho an toàn của OS): làm ở M3, không nằm trong file đồng bộ
- [x] Mở kho bằng passphrase hoặc recovery key; **đổi passphrase** = bọc lại vault key; tạo lại recovery key; **xoay vault key**. (Chưa có API thêm/xóa khe tùy ý.)
- [x] (T) Mở bằng từng loại khe, đổi passphrase rồi mở bằng mới/cũ, tạo lại recovery key rồi khóa cũ vô hiệu

### 1.4 Mô hình dữ liệu (`core/vault`)
- [x] `Item`, `Field`, `TotpParams`, `PwHistoryEntry`, `Reminder`, `Tombstone`, `VaultData`. **Trường theo mẫu có `key` ổn định** (để dịch nhãn), trường tự thêm có `label`
- [x] 7 loại mục và mẫu trường (`ItemTemplates`)
- [x] Serialize JSON có `schema`, giữ nguyên trường lạ và loại mục lạ. (Chưa có migration vì mới có schema 1.)
- [x] `VaultData`: thêm/sửa (`upsert`), thùng rác, khôi phục, xóa vĩnh viễn (tombstone), **tự dọn thùng rác ≥ 30 ngày**
- [x] `Item.subtitle`: chỉ lấy trường **không bí mật**
- [x] Mở/lưu `.vkv`: nonce mới mỗi lần ghi; **ghi nguyên tử** (`VaultStorage`: file tạm, đổi tên, giữ `.bak`)
- [x] (T) Vòng đi vòng lại, file hỏng/cắt cụt/sửa từng byte, version lạ, tham số KDF xấu, khe lạ

### 1.5 Merge và xung đột (`core/vault/merge`)
- [x] Đồng hồ lai **HLC**
- [x] **Gộp ba chiều** `mergeVaults(local, remote, base)` (đã bỏ cách `parentHlc` vì báo xung đột sai, xem `vault-format.md` mục 7)
- [x] Phát hiện xung đột, `resolveConflict` tạo phiên bản mới
- [x] (T) Property test 500 kịch bản: giao hoán, hội tụ, không mất mục. **Tìm ra và sửa 1 lỗi** (hai tombstone khác HLC). Tính "kết hợp" chưa kiểm riêng

### 1.6 TOTP (`core/totp`)
- [x] Base32 (chịu khoảng trắng, gạch ngang, chữ thường, padding)
- [x] `Otp.hotp / totpAt / code`: SHA1/256/512, 6 đến 8 chữ số, chu kỳ tùy ý
- [x] `OtpAuth.parse / toUri`; từ chối link sai. **Tìm ra và sửa 1 lỗi** (nhà phát hành chứa dấu `:`)
- [x] `Migration.parseUri / encodeUri`: protobuf viết tay, hỗ trợ lô nhiều mã; chịu "+" thành khoảng trắng và base64 URL-safe
- [x] `Otp.secondsRemaining / fractionRemaining / grouped`
- [x] (T) **Vector RFC 6238** (cả 3 thuật toán, 6 mốc) và **RFC 4226**; mẫu migration công khai; quét 1.000 dữ liệu ngẫu nhiên không vượt biên

### 1.7 Nhập/xuất (`core/import_export`)
- [x] `ImportResult` (kèm cảnh báo) và `markDuplicates`
- [x] Importer: Google Authenticator (migration), link `otpauth://` nhiều dòng, Aegis, 2FAS, Bitwarden (JSON, CSV), 1Password (CSV), KeePass (CSV), Chrome/Edge (CSV), tự nhận diện định dạng
- [x] Exporter: link `otpauth://`, **link Google Authenticator** (chia lô 10 mục), CSV. (Sao lưu mã hóa chính là file kho.)
- [ ] (T) **Mẫu thật từng nguồn: CHƯA.** Test dùng dữ liệu **tự dựng theo định dạng tôi biết** (Bitwarden, Aegis, 2FAS, 1Password, KeePass, Chrome), chưa đối chiếu với file xuất thật. **Cần thử với file xuất thật của chính bạn** trước khi tin. Đã có: file rỗng/sai định dạng, ký tự đặc biệt, 1.500 dữ liệu rác không làm sập

### 1.8 Logic thuần chuyển từ prototype
- [x] `findDuplicates` và `mergeDuplicateGroup` (giữ bản mới nhất, mang theo 2FA/nhóm/yêu thích, cất mật khẩu khác vào lịch sử)
- [x] `PasswordStrength` (entropy có phạt dãy, lặp, mật khẩu thông dụng; **chỉ là ước lượng**)
- [x] `healthReport` (công thức điểm **tự đặt**)
- [x] `PasswordGenerator`: CSPRNG, không thiên lệch modulo, đảm bảo đủ loại ký tự, bỏ ký tự dễ nhầm; kiểm phân phối đều
- [x] Nhắc hạn: `passwordReminder`, `expiryDate` (thẻ, API key), `pendingAlerts` (hẹn lại), `upcomingNotices` (cho bộ lập lịch M6), cộng tháng theo lịch
- [x] `Hibp.split / countFromResponse / check` (chỉ 5 ký tự đầu mã băm rời khỏi hàm)
- [x] (T) Test từng hàm, gồm các trường hợp biên. Thêm: tìm kiếm bỏ dấu tiếng Việt, **không tìm trong trường bí mật**

- [ ] Chưa làm (nhập): **1Password 1pux** và **KeePass XML**
- [ ] Chưa làm: lớp `SecureBytes`, API thêm/xóa khe tùy ý, migration lược đồ cũ

**Kết quả M1 (2026-11-19):** 28 tệp mã trong `lib/core/` (~3.200 dòng), 11 tệp test (~2.150 dòng), **179 test qua**, `flutter analyze` không có vấn đề. Property test và thử dữ liệu rác đã **tìm ra 3 lỗi thật** (khe lạ bị báo hỏng, hai tombstone khác HLC, nhà phát hành chứa dấu `:`), đều đã sửa. Giới hạn đã biết: mật mã chạy thuần Dart (chưa đo trên Android); định dạng file **chưa có người ngoài rà soát**; bộ đọc nhập khẩu **chưa thử với file xuất thật**.

**Xong khi:** toàn bộ test qua; test vector RFC 6238 và test vector định dạng file qua; `vault-format.md` khớp với code; có commit `m1`.

---

## M2 — App offline (3–4 tuần)

### 2.1 Nền tảng giao diện
- [ ] Hệ token màu/chữ/khoảng cách lấy từ prototype (sáng, tối đen, 6 màu nhấn, mật độ)
- [ ] `ThemeController`: hệ thống/sáng/tối, màu nhấn, mật độ; lưu cục bộ
- [ ] Hạ tầng đa ngôn ngữ: ARB vi/en, đổi ngôn ngữ ngay không cần khởi động lại
- [ ] Điều hướng: **Windows** thanh bên + lưới nhiều cột; **Android** thanh dưới 3 tab (Kho, 2FA, Cài đặt); màn full-screen có nút Quay lại và ngăn xếp quay về đúng menu cha
- [ ] Bố cục thích ứng: 1 cột (điện thoại) → 2, 3, 4 cột (cửa sổ rộng)
- [ ] Các thành phần dùng chung: dòng cài đặt, nhóm cài đặt, công tắc, nút chọn đoạn, avatar chữ cái (tông trầm đồng nhất), huy hiệu, toast, hộp thoại, bottom sheet

### 2.2 Dữ liệu và trạng thái
- [ ] `VaultRepository` (Riverpod): giữ kho trong bộ nhớ, tự lưu sau khi sửa (gộp trong ~500 ms)
- [ ] Một `Ticker` TOTP duy nhất cho toàn app (mỗi giây), không tạo timer cho từng dòng
- [ ] Trạng thái bộ lọc/gom/tìm kiếm/thu gọn nhóm

### 2.3 Màn hình (P)
- [ ] **Kho:** danh sách gom theo Nhóm/Loại/Không, tiêu đề nhóm thu gọn được, mục Yêu thích ở đầu, mã 2FA hiện sẵn kèm vòng đếm ngược (bấm để copy), thanh trên: icon bộ lọc (chọn nhóm), icon tìm kiếm (mở ô tìm)
- [ ] **Nút tròn dấu cộng:** xoay thành ×, bung 4 nút (Nhập tay, Quét QR, Nhập từ file, Xem nhanh)
- [ ] **Chi tiết mục:** Windows = hộp thoại; Android = trang; hiện/ẩn, copy, sao yêu thích, đổi nhóm, khối 2FA, lịch sử mật khẩu, nhắc đổi, xóa vào thùng rác
- [ ] **Thêm mục (full-screen):** chọn loại → trường đổi theo loại, thêm trường tùy ý, nút Tạo mật khẩu, nhóm mới, thanh Hủy/Lưu dính đáy
- [ ] **Tab 2FA:** danh sách dòng mỏng, copy cả dòng, gom nhóm
- [ ] **Xem nhanh 2FA:** ô nhập lớn, nút Kiểm tra bên dưới, hiện mã (không lưu), nút Lưu vào kho
- [ ] **Tạo mật khẩu:** mật khẩu tô màu theo loại ký tự, thanh độ mạnh, độ dài kéo + nút −/+, chọn loại ký tự
- [ ] **Thùng rác**, **Mục trùng lặp**, **Lịch sử mật khẩu** (hiện/ẩn, copy, dùng lại)
- [ ] **Cài đặt:** danh sách 7 menu (Tài khoản, Dữ liệu, Bảo mật, Chủ đề, Chung, Hỗ trợ, Giới thiệu) và các trang con; phần chưa có chức năng thật để trạng thái "sắp có"
- [ ] **Hỗ trợ / Giới thiệu:** FAQ, góp ý, phiên bản, giấy phép mã nguồn mở (dùng `showLicensePage`)
- [ ] **Lần đầu mở app (onboarding):** tạo kho, chọn **offline** hay **có tài khoản**, hiện và bắt xác nhận đã lưu recovery key
- [ ] Trạng thái rỗng, trạng thái lỗi, trạng thái đang tải cho mọi danh sách

### 2.4 Chất lượng
- [ ] Hỗ trợ bàn phím, trình đọc màn hình (nhãn cho icon-only), vùng bấm ≥ 44 px
- [ ] Cỡ chữ hệ thống lớn không vỡ bố cục
- [ ] Hiệu năng: danh sách 500 mục cuộn mượt, khởi động lạnh < 2 giây
- [ ] Widget test cho luồng thêm mục, thùng rác, đổi nhóm; golden test cho vài màn chính (sáng và tối)

**Xong khi:** dùng được hằng ngày trên Windows và Android, không cần mạng; mọi thao tác trong prototype có bản thật (trừ đồng bộ/QR/thông báo thật); có commit `m2`.

---

## M3 — Bảo mật thiết bị (1 tuần)

- [ ] `SecureStore` thật: Android Keystore, Windows Credential Manager (qua `flutter_secure_storage`)
- [ ] Khóa app: master password tùy chọn (đặt, đổi, tắt có xác thực), màn khóa
- [ ] Sinh trắc (`local_auth`): khóa device slot cần xác thực sinh trắc mới mở được (⚠ thử máy thật)
- [ ] Tự khóa: sau N phút không dùng, khi thu nhỏ/chuyển app; xóa khóa khỏi RAM khi khóa (`wipe`)
- [ ] **Làm chậm khi nhập sai** passphrase liên tiếp (tăng dần thời gian chờ)
- [ ] Clipboard: tự xóa sau 30 giây; Android đánh dấu nội dung là **nhạy cảm** (kênh nền tảng nhỏ bằng Kotlin)
- [ ] Android `FLAG_SECURE` (chặn chụp màn hình, che nội dung trong danh sách ứng dụng gần đây); Windows: ẩn nội dung khi mất tiêu điểm nếu cần
- [ ] Màn **Kiểm tra bảo mật** thật (dùng `healthReport`), kiểm tra rò rỉ HIBP kiểu k-anonymity (⚠ chỉ gửi 5 ký tự đầu)
- [ ] Đổi master password, đổi vault passphrase, **xem/tạo mã khôi phục mới** (xác thực lại trước khi hiện)
- [ ] Rà log: không chỗ nào in dữ liệu nhạy cảm; build release tắt log chi tiết
- [ ] Checklist thủ công trên máy thật (khóa, sinh trắc, thu nhỏ app, xoay màn hình, chụp màn hình, clipboard)

**Xong khi:** checklist bảo mật qua trên máy thật; có commit `m3`.

---

## M4 — Đồng bộ Google Drive (1–2 tuần)

### Chuẩn bị (làm tay, một lần)
- [ ] Tạo project Google Cloud, bật **Drive API**
- [ ] OAuth consent screen: thêm scope `drive.appdata`, **chuyển sang "In production"** (nếu để Testing thì token hết hạn sau 7 ngày)
- [ ] Tạo 2 OAuth client: **Desktop app** và **Android** (cần SHA-1 của keystore debug và release)

### Code
- [ ] Giao diện `SyncProvider` và `FakeSyncProvider` (trong bộ nhớ, để test)
- [ ] `DriveSync`: tìm/tải/tải lên `vault.vkv` trong `appDataFolder`, kiểm tra version khi tải lên
- [ ] Đăng nhập **Windows**: mở trình duyệt, OAuth PKCE qua `127.0.0.1:<port>`, lưu refresh token vào `SecureStore`
- [ ] Đăng nhập **Android**: `google_sign_in`
- [ ] `SyncService`: đồng bộ khi mở app, sau mỗi lần sửa (gộp), nút đồng bộ tay; tải → giải mã → merge → mã hóa → tải lên; thất bại do lệch version thì lặp lại
- [ ] Xử lý offline, lỗi mạng giữa chừng, thử lại có lùi dần
- [ ] **Màn xung đột:** hiện hai bản của một mục để chọn
- [ ] Chip trạng thái đồng bộ (đang đồng bộ, lần cuối, lỗi), thông báo lỗi dễ hiểu
- [ ] Thiết bị mới: đăng nhập Google → nhập passphrase hoặc recovery key → giải mã kho
- [ ] (T) Test với `FakeSyncProvider`: hai thiết bị sửa cùng lúc, xóa rồi sửa, mất mạng giữa chừng
- [ ] Thử thủ công: sửa trên Windows, điện thoại nhận được và ngược lại; hai máy cùng sửa

**Xong khi:** hai máy đồng bộ đúng, không mất dữ liệu khi sửa đồng thời; có commit `m4`.

---

## M5 — Cloudflare và tài khoản (2 tuần)

### Server (`server/`)
- [ ] Khung Worker (TypeScript + Hono), `wrangler.toml`, môi trường dev/prod
- [ ] D1: bảng `users`, `devices` (gồm hash refresh token, hạn, tên thiết bị, lần cuối), `vaults` (user_id, version, blob, cập nhật lúc)
- [ ] Migration cho D1
- [ ] `POST /auth/google` (xác minh ID token bằng JWKS, kiểm `aud` và `exp`), `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`
- [ ] `GET /devices`, `DELETE /devices/:id` (thu hồi từng thiết bị)
- [ ] `GET /vault`, `PUT /vault` với `If-Match` (409 khi lệch version, trả bản hiện tại)
- [ ] **Danh sách email cho phép** (bản đầu): từ chối đăng ký ngoài danh sách
- [ ] Băm mật khẩu: client băm Argon2id → server băm thêm (PBKDF2 hoặc scrypt WASM)
- [ ] Giới hạn tốc độ đăng nhập, khóa tạm khi sai nhiều lần, giới hạn kích thước body
- [ ] Bí mật cấu hình qua `wrangler secret`; HTTPS; (tùy chọn) tên miền riêng
- [ ] (T) Test với vitest + miniflare: đăng nhập, refresh, thu hồi, ghi đè đồng thời

### Client
- [ ] `CloudflareSync` (cùng giao diện `SyncProvider`)
- [ ] Màn đăng nhập/đăng ký (Google, email), đặt vault passphrase, **bắt lưu recovery key**, mở kho trên máy mới
- [ ] Màn tài khoản: thiết bị đã đăng nhập (gỡ từ xa), đăng xuất, đổi mật khẩu đăng nhập, đổi vault passphrase
- [ ] Chọn nơi đồng bộ: Cloudflare hoặc Drive (hoặc chuyển đổi)
- [ ] Chuyển kho offline thành kho có tài khoản (thêm keyslot recovery và passphrase)

**Xong khi:** đồng bộ qua server; thu hồi thiết bị làm thiết bị đó mất quyền; có commit `m5`.

---

## M6 — Nhập/xuất, QR, nhắc nhở (1–2 tuần)

- [ ] **Quét QR (Android):** `mobile_scanner`, xin quyền camera, đọc cả QR thường và QR migration
- [ ] **Quét QR (Windows):** chọn ảnh/dán ảnh (`zxing2`), (tùy chọn) chụp vùng màn hình
- [ ] Luồng nhập (P): chọn nguồn → chọn file → xem trước có cờ trùng → chọn nhóm đích → nhập
- [ ] Luồng xuất (P): phạm vi, định dạng, cảnh báo bản không mã hóa, yêu cầu passphrase
- [ ] Màn **Mục trùng lặp** thật (gộp, xóa vào thùng rác)
- [ ] **Dịch vụ nhắc nhở:** `ReminderScheduler` tính toàn bộ lịch, hủy và đặt lại khi dữ liệu/cài đặt đổi và sau mỗi lần đồng bộ
- [ ] Android: `flutter_local_notifications`, quyền thông báo (13+), quyền báo thức chính xác (12+), **đặt lại lịch sau khi khởi động máy**, kênh thông báo (⚠ thử Xiaomi/Samsung nếu có)
- [ ] Windows: thông báo hẹn giờ (MSIX) hoặc chạy nền ở khay hệ thống kiểm tra mỗi ngày (chốt phương án ở mục 13 PLAN.md)
- [ ] Nội dung thông báo **không chứa bí mật** (chỉ tên dịch vụ và hạn)
- [ ] Màn Nhắc nhở (chuông, quá hạn/sắp hết hạn, Đổi mật khẩu, Nhắc lại sau 7 ngày, Bỏ qua)
- [ ] Thử thực tế: nhập hết dữ liệu từ Google Authenticator của chính bạn, so mã với app cũ

**Xong khi:** chuyển hết Google Authenticator sang app mới thành công, mã khớp; thông báo hẹn giờ hiện đúng trên máy thật; có commit `m6`.

---

## M7 — Đóng gói và phát hành (1 tuần)

### Windows
- [ ] Biểu tượng app, tên hiển thị, thông tin phiên bản
- [ ] Đóng gói **MSIX** (gói `msix`), chứng chỉ ký (tự ký cho dùng cá nhân, hoặc mua chứng chỉ nếu phát hành rộng)
- [ ] Thử cài và gỡ trên máy Windows **sạch**

### Android
- [ ] Tạo **keystore phát hành** và **sao lưu nó ở nơi an toàn** (mất là không cập nhật được app)
- [ ] Cấu hình ký, `flutter build apk --release` / `appbundle`, rà quyền trong manifest (chỉ giữ quyền cần: camera, thông báo, báo thức)
- [ ] Thử cài trên điện thoại thật từ APK

### Chất lượng và tài liệu
- [ ] Ma trận thử: Windows 10/11, Android thấp nhất (API 26) và mới nhất, màn hình nhỏ/lớn, sáng/tối, vi/en
- [ ] **Diễn tập khôi phục:** xóa app, cài lại, đăng nhập, mở kho bằng passphrase; rồi bằng recovery key
- [ ] **Diễn tập mất thiết bị:** gỡ thiết bị từ xa, đổi passphrase
- [ ] Rà soát bảo mật cuối (checklist mục 8 PLAN.md); nhờ người có chuyên môn xem lại đặc tả định dạng và mã mật mã
- [ ] `README.md` (cách build, cấu trúc), hướng dẫn người dùng ngắn (chuyển từ Google Authenticator, lưu recovery key, sao lưu)
- [ ] Gắn phiên bản `1.0.0`, tag `v1.0.0`

**Xong khi:** bản cài chạy được trên máy sạch và điện thoại thật; có commit/tag `v1.0.0`.

---

## Sau bản đầu (chưa lên lịch)

- [ ] Android Autofill Service (Kotlin)
- [ ] Extension trình duyệt (TypeScript, dùng chung test vector định dạng)
- [ ] Phím tắt toàn cục + cửa sổ nhỏ trên Windows
- [ ] Widget Android hiện mã 2FA
- [ ] Push từ server (cảnh báo thiết bị mới, đồng bộ nền)
- [ ] Tệp đính kèm mã hóa
- [ ] Chế độ nhiều người dùng, chia sẻ, truy cập khẩn cấp, passkey

---

## Phụ thuộc giữa các milestone

```
M0 ──> M1 ──> M2 ──> M3 ──┬──> M4 ──> M5
                          └──> M6        ──> M7
```
- M1 phải xong trước M2 (giao diện dựa trên lõi).
- M4 và M6 có thể song song sau M3, nhưng M6 (nhắc nhở) nên chờ M4 để biết cách đặt lại lịch sau đồng bộ.
- M5 cần M4 (dùng chung `SyncService` và màn xung đột).
