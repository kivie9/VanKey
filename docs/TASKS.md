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
- [x] Cài Flutter SDK: `git clone https://github.com/flutter/flutter.git -b stable E:\code\flutter`
- [x] Thêm `E:\code\flutter\bin` vào PATH, mở terminal mới, chạy `flutter doctor`
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
- [ ] Nếu đã có điện thoại Android và Android SDK: đo trên **Android** thật
- [ ] **Ngưỡng chấp nhận:** mở khóa ≤ ~1 giây trên PC và ≤ ~1,5 giây trên điện thoại tầm trung; bộ nhớ Argon2id từ 64 MiB trở lên
- [x] Đã đi theo phương án thuần Dart (`cryptography`) và **đối chiếu byte-cho-byte với libsodium độc lập: khớp**
- [x] Ghi kết quả vào `docs/spike-m0.md` và `docs/decisions.md` (D4)

**Xong khi:** `flutter doctor` không báo lỗi cho Windows; spike chạy được; đã chốt thư viện mật mã; có commit `m0`.

---

## M1 — Lõi Dart thuần (1–2 tuần)

> Toàn bộ nằm trong `lib/core/`, **không import Flutter UI**. Chạy test bằng `flutter test`.

### 1.1 Tài liệu (làm trước khi viết code mã hóa)
- [ ] `docs/vault-format.md`: bố cục byte của file, trường header, keyslot, tham số KDF, JSON bên trong, quy tắc version và nâng cấp
- [ ] `docs/vault-format.md`: **test vector** (khóa, nonce, bản rõ, bản mã mong đợi) để dùng chung với Dart và TypeScript sau này
- [ ] `docs/threat-model.md`: tài sản cần bảo vệ, kẻ tấn công, cái bảo vệ được và không bảo vệ được

### 1.2 Mật mã cơ bản (`core/crypto`)
- [ ] `Csprng`: sinh byte ngẫu nhiên an toàn
- [ ] `Kdf.argon2id(passphrase, salt, params)` trả khóa 32 byte
- [ ] `Aead.encrypt / decrypt` (XChaCha20-Poly1305) với dữ liệu liên kết (AAD) là header
- [ ] `SecureBytes`: bọc khóa, có `wipe()` (ghi đè số 0 khi khóa app)
- [ ] (T) Test vector, sai khóa, sai nonce, bản mã bị sửa 1 byte → phải **lỗi đúng cách**, không crash, không trả dữ liệu sai

### 1.3 Keyslot (`core/crypto/keyslot`)
- [ ] Tạo vault key ngẫu nhiên 32 byte
- [ ] Keyslot **passphrase**: Argon2id → KEK → bọc vault key
- [ ] Keyslot **recovery**: sinh recovery key (24 ký tự, 6 nhóm 4, bảng chữ dễ đọc), KEK dẫn xuất bằng HKDF (đủ entropy, không cần Argon2)
- [ ] Keyslot **device**: khóa ngẫu nhiên lưu trong kho an toàn của OS (giao diện `SecureStore`, cài đặt thật ở M3)
- [ ] Mở kho bằng bất kỳ keyslot nào; **đổi passphrase** = bọc lại vault key; thêm/xóa keyslot
- [ ] (T) Mở bằng từng loại slot, đổi passphrase rồi mở lại bằng passphrase mới/cũ, xóa slot rồi không mở được

### 1.4 Mô hình dữ liệu (`core/vault`)
- [ ] `Item`, `Field`, `TotpParams`, `PwHistoryEntry`, `Reminder` theo PLAN.md mục 4.3
- [ ] 7 loại mục và **mẫu trường** cho từng loại (khớp prototype: Đăng nhập có Mã dự phòng, Thẻ có CVV/PIN...)
- [ ] Serialize JSON có `schemaVersion`; đọc được phiên bản cũ (chuẩn bị migration)
- [ ] `Vault`: danh sách mục, nhóm, thùng rác (`deletedAt`), CRUD, chuyển vào/khôi phục khỏi thùng rác, dọn thùng rác > 30 ngày
- [ ] Hàm `subtitle(item)`: chỉ lấy trường **không bí mật** đầu tiên
- [ ] Mở/lưu file `.vkv`: **ghi nguyên tử** (ghi ra file tạm rồi đổi tên), nonce mới mỗi lần ghi
- [ ] (T) Vòng đi vòng lại (lưu → mở) cho mọi loại mục; file hỏng, file cắt cụt, version lạ

### 1.5 Merge và xung đột (`core/vault/merge`)
- [ ] Đồng hồ lai **HLC** (timestamp + bộ đếm + id thiết bị)
- [ ] `merge(local, remote)` theo từng mục: bản mới hơn thắng, giữ `deletedAt`
- [ ] Phát hiện **xung đột** (cùng mục, cả hai sửa từ cùng một bản gốc) → trả danh sách để giao diện hỏi, không ghi đè
- [ ] (T) Property test: giao hoán, kết hợp, lũy đẳng; kịch bản sửa/xóa đồng thời; lệch giờ giữa hai máy

### 1.6 TOTP (`core/totp`)
- [ ] Base32 mã hóa/giải mã (chịu được khoảng trắng, gạch ngang, chữ thường, padding)
- [ ] `Totp.generate(secret, time, algo, digits, period)` — SHA1/256/512, 6 và 8 chữ số, chu kỳ 30 và 60 giây
- [ ] `parseOtpauth(link)` và `buildOtpauth(...)`; từ chối link sai định dạng
- [ ] `parseMigration(link)`: giải mã `otpauth-migration://offline?data=...` (base64 → protobuf `MigrationPayload`), hỗ trợ lô nhiều mã
- [ ] Hàm tính thời gian còn lại của chu kỳ (cho vòng đếm ngược)
- [ ] (T) **Test vector RFC 6238** (SHA1/256/512 tại 59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000); mẫu migration thật; link lỗi

### 1.7 Nhập/xuất (`core/import_export`)
- [ ] Giao diện `Importer` → danh sách `ImportedItem` (kèm cờ trùng)
- [ ] Importer: Google Authenticator (migration), link `otpauth://` nhiều dòng, Aegis/2FAS (JSON), Bitwarden (JSON, CSV), 1Password (CSV), KeePass (CSV, XML), Chrome/Edge (CSV)
- [ ] Exporter: sao lưu mã hóa (chính là file kho), link `otpauth://`, CSV (có hàm escape đúng chuẩn)
- [ ] (T) Mẫu thật từng nguồn (đã xóa dữ liệu nhạy cảm), file rỗng, file sai định dạng, dòng có ký tự đặc biệt/xuống dòng trong ô

### 1.8 Logic thuần chuyển từ prototype
- [ ] `findDuplicates`: trùng mã 2FA, trùng tên + tài khoản, dùng chung mật khẩu; `mergeDuplicates` (giữ bản mới nhất, mang theo 2FA nếu thiếu)
- [ ] `passwordStrength` (entropy) và `isWeak`
- [ ] `healthReport`: yếu, dùng chung, chưa bật 2FA, rò rỉ → điểm
- [ ] `generatePassword`: dùng CSPRNG, **tránh thiên lệch modulo**, loại ký tự dễ nhầm (0/O, 1/l)
- [ ] `reminder`: tính ngày hết hạn, trạng thái (ok, sắp, quá hạn), hẹn lại, bỏ qua; đọc hạn thẻ (MM/YY) và hạn API key
- [ ] `hibpPrefix`: băm SHA-1 mật khẩu, tách 5 ký tự đầu để tra
- [ ] (T) Test cho từng hàm, gồm các trường hợp biên

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
