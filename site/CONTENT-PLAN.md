# Kế hoạch trang tài liệu trên site

Cập nhật: 2026-11-27. Chưa bắt đầu. Bổ sung cho [PLAN.md](PLAN.md) (trang giới thiệu): file này nói **site cần thêm những trang nào ngoài trang chủ**, mỗi trang viết gì, lấy thông tin từ đâu.

VanKey đang dùng cho cá nhân, nên chia làm hai đợt:
- **Đợt 1 (dùng riêng):** trang có ích cho chính bạn, không bắt buộc về pháp lý.
- **Đợt 2 (trước khi công khai):** trang mà Google Play, Microsoft Store hoặc người dùng lạ cần có.

## Tổng quan các trang

| Đường dẫn (vi / en) | Trang | Đợt | Ai cần | Liên kết từ app |
|---|---|---|---|---|
| `/huong-dan/` · `/en/guide/` | Hướng dẫn sử dụng | 1 | Người dùng | Hỗ trợ |
| `/huong-dan/chuyen-tu-google-authenticator/` | Chuyển từ Google Authenticator | 1 | Người dùng | Hỗ trợ, màn Nhập |
| `/huong-dan/sao-luu-va-khoi-phuc/` | Sao lưu, khôi phục, mất máy | 1 | Người dùng | Hỗ trợ, màn lưu mã khôi phục |
| `/bao-mat/` · `/en/security/` | Cách VanKey bảo vệ dữ liệu | 1 | Người dùng, người rà soát | Giới thiệu |
| `/thay-doi/` · `/en/changelog/` | Có gì mới | 1 | Người dùng | Giới thiệu, thông báo bản mới |
| `/tai-ve/` · `/en/download/` | Tải về và kiểm tra file | 1 | Người dùng | Nút "Có bản mới" |
| `/quyen-rieng-tu/` · `/en/privacy/` | Chính sách quyền riêng tư | 2 | **Bắt buộc** (Play, Store) | Giới thiệu, màn đăng ký |
| `/dieu-khoan/` · `/en/terms/` | Điều khoản sử dụng | 2 | Nên có | Giới thiệu, màn đăng ký |
| `/xoa-tai-khoan/` · `/en/delete-account/` | Xóa tài khoản và dữ liệu | 2 | **Bắt buộc** (Play, vì app có đăng ký tài khoản) | Màn Tài khoản |
| `/bao-loi-bao-mat/` · `/en/security/report/` | Báo lỗ hổng bảo mật | 2 | Nên có | Giới thiệu |
| `/.well-known/security.txt` | Liên hệ bảo mật (RFC 9116) | 2 | Nên có | Không |
| `/giay-phep/` · `/en/licenses/` | Giấy phép và ghi công | 2 | Nên có | Giới thiệu |

Footer mọi trang: Quyền riêng tư · Điều khoản · Bảo mật · Giấy phép · Có gì mới · GitHub.

---

## Đợt 1

### 1. Hướng dẫn sử dụng
Một trang mục lục, mỗi việc một trang con ngắn (mỗi trang 1 việc, có ảnh chụp thật):
- Tạo kho, đặt mật khẩu, **lưu mã khôi phục** (nói rõ app không cho xem lại mã cũ, chỉ tạo mới)
- Thêm mục 2FA: quét QR bằng camera, từ ảnh, nhập tay; HOTP, Steam Guard
- Nhập từ app khác: Google Authenticator, Aegis, 2FAS, Bitwarden, KeePass XML, 1Password `.1pux`, CSV
- Đồng bộ: máy chủ VanKey, Google Drive, thư mục (chỉ máy tính); xử lý xung đột
- Thêm máy mới, gỡ thiết bị bị mất
- Mở bằng vân tay / Windows Hello, tự khóa
- Kiểm tra bảo mật và HIBP
- Nhắc nhở
- Câu hỏi thường gặp: chép từ màn Hỗ trợ (`app/lib/app/screens/info_screens.dart`), giữ hai nơi giống nhau

**Nguồn:** `docs/STATUS.md` (chỉ viết tính năng đã thử thật), menu trong `settings_tab.dart`.

### 2. Chuyển từ Google Authenticator
Các bước có ảnh: Google Authenticator → Chuyển tài khoản → Xuất → VanKey `+` → Quét QR (có thể chụp màn hình rồi chọn ảnh). Nhắc **so vài mã với app cũ trước khi xóa app cũ**, và xóa ảnh chụp mã QR sau khi xong (link migration chứa bí mật).
Thêm chiều ngược lại: xuất từ VanKey sang Google Authenticator (QR chia lô 6 mục).

### 3. Sao lưu, khôi phục, mất máy
Bản công khai của `docs/recovery-sheet.md`: các tình huống A–D, kèm **nút tải bản PDF để in** (bản trống). Nhấn mạnh: mất mật khẩu **và** mã khôi phục là mất kho.

### 4. Cách VanKey bảo vệ dữ liệu
Viết cho người thường trước, chi tiết kỹ thuật để ở phần mở rộng:
- Sơ đồ: mật khẩu → NFKC → Argon2id (tự đo, chuẩn 64 MiB × 3 vòng) → khóa kho → XChaCha20-Poly1305 → file `.vkv`. Mã khôi phục dẫn xuất bằng HKDF-SHA256.
- Máy chủ chỉ nhận: tên đăng nhập, mã băm của khóa xác thực (client dẫn xuất, PBKDF2 ở máy chủ), refresh token đã băm, tên thiết bị và thời điểm dùng, file kho đã mã hóa. Không bao giờ thấy mật khẩu kho.
- Sinh trắc: Android Keystore / Windows Hello trong TPM bọc khóa kho; iOS, macOS mới là lớp chặn.
- **Nói thẳng:** mật mã chạy thuần Dart, **chưa được rà soát độc lập**; giới hạn trong `docs/threat-model.md` mục 3 và 5.
- Link tới đặc tả `docs/vault-format.md` và mô hình đe dọa (trên GitHub nếu repo công khai).

**Nguồn:** `docs/vault-format.md`, `docs/threat-model.md`, `server/migrations/*.sql`.

### 5. Có gì mới
Sinh tự động từ `CHANGELOG.md` ở gốc repo lúc build (Astro đọc file Markdown), không chép tay. Mỗi phiên bản có anchor (`/thay-doi/#1.0.0`) để nút "Có bản mới" trong app trỏ thẳng tới.

### 6. Tải về
- Android: APK; Windows: bộ cài `vankey-<phiên bản>-windows-setup.exe` và bản zip. Link tới GitHub Releases mới nhất (repo `kivie9/VanKey`).
- **Mã SHA-256** của từng file để kiểm tra (CI tạo sẵn khi phát hành, xem bước kỹ thuật bên dưới).
- Vân tay khóa ký APK (SHA-256 của chứng chỉ) để người dùng so khi cài.
- Giải thích cảnh báo SmartScreen (bộ cài chưa có chứng chỉ ký) và "cài từ nguồn không xác định" trên Android.
- Yêu cầu: Android 8 (API 26) trở lên, Windows 10/11 64-bit.

---

## Đợt 2 (trước khi công khai)

### 7. Chính sách quyền riêng tư (bắt buộc)
Viết đúng những gì code làm, không hứa hơn. Các mục:

| Mục | Nội dung (theo code hiện tại) |
|---|---|
| Dữ liệu trên máy | Kho mã hóa. Nhà phát triển không truy cập được |
| Máy chủ VanKey (tùy chọn) | Tên đăng nhập; mã băm của khóa xác thực; tên thiết bị, thời điểm tạo và dùng gần nhất; refresh token đã băm; file kho đã mã hóa. Bảng `attempts` giữ **địa chỉ IP** (IPv6 rút về tiền tố) và tên đăng nhập kèm số lần sai, để chống dò mật khẩu. Dòng không cập nhật quá 24 giờ bị dọn (`ATTEMPT_TTL` trong `server/src/handler.ts`) |
| Nơi đặt máy chủ | Cloudflare Workers + D1. Ghi rõ Cloudflare là bên xử lý dữ liệu, link chính sách của Cloudflare |
| Google Drive (tùy chọn) | Chỉ quyền `drive.appdata` (thư mục ẩn của app), không đọc file khác. File lưu đã mã hóa |
| HIBP | Chỉ gửi 5 ký tự đầu của mã băm SHA-1 mật khẩu tới `api.pwnedpasswords.com`, khi bạn bấm kiểm tra |
| Kiểm tra bản mới | Một yêu cầu tới `api.github.com`, chỉ khi bạn bấm |
| Không có | Quảng cáo, phân tích, báo lỗi tự động, theo dõi |
| Quyền trên Android | Camera (quét QR), thông báo và báo thức (nhắc nhở), sinh trắc |
| Thời gian giữ, xóa | Xóa tài khoản là xóa ngay cả kho trên máy chủ (đã có, `DELETE /account`). Ghi rõ bản sao lưu của Cloudflare nếu có |
| Trẻ em | Không nhắm tới người dưới 13 tuổi |
| Liên hệ | Một email riêng cho VanKey (**cần tạo**, không dùng email cá nhân) |
| Ngày hiệu lực, lịch sử sửa đổi | Có |

**Trước khi viết:** kiểm tra lại máy chủ có ghi log yêu cầu không (Workers Logs, Logpush), vì log đó cũng chứa IP.

### 8. Điều khoản sử dụng
Ngắn gọn: phần mềm cung cấp "nguyên trạng"; người dùng tự chịu trách nhiệm giữ mật khẩu và mã khôi phục; nhà phát triển không thể khôi phục kho; máy chủ miễn phí có thể ngừng hoặc giới hạn (đăng ký có giới hạn, mã mời); kho trên máy chủ tối đa khoảng 1,5 MB; cấm dùng máy chủ để lưu thứ khác. Phải khớp với giấy phép mã nguồn đã chọn.

### 9. Xóa tài khoản và dữ liệu (bắt buộc với Google Play)
Google Play yêu cầu một **trang web** (không chỉ trong app) nói cách xóa tài khoản:
- Trong app: Cài đặt → Dữ liệu → Đồng bộ → tài khoản → Xóa tài khoản (cần mật khẩu)
- Không còn máy: cách gửi yêu cầu xóa qua email (cần quy trình xác minh là chủ tài khoản)
- Xóa những gì, giữ lại gì, trong bao lâu
- Ghi chú: dữ liệu trên Google Drive và trên máy người dùng phải tự xóa

### 10. Báo lỗ hổng bảo mật
Email riêng, khóa PGP (tùy chọn), cam kết thời gian phản hồi, phạm vi (app, máy chủ, định dạng file), xin đừng công bố trước khi sửa. Kèm file `public/.well-known/security.txt` và `SECURITY.md` ở gốc repo cùng nội dung.

### 11. Giấy phép và ghi công
- Giấy phép của VanKey (**chưa chọn**, xem câu hỏi bên dưới)
- Phông chữ trong app (Inter, Space Grotesk, JetBrains Mono, OFL) và trên site (Geist, OFL)
- Simple Icons (CC0) và ghi chú: logo các dịch vụ là nhãn hiệu của chủ sở hữu, chỉ dùng để nhận diện
- Thư viện chính: Flutter, cryptography, Three.js, GSAP, Astro
- Danh sách đầy đủ xem trong app (Giới thiệu → Giấy phép mã nguồn mở)

---

## Việc kỹ thuật kèm theo

- [ ] Astro: thêm content collection `src/content/docs/{vi,en}/*.md` cho các trang trên, layout chung `Doc.astro` (mục lục bên, ngày cập nhật, link "sửa trên GitHub" nếu repo công khai)
- [ ] Đọc `../CHANGELOG.md` lúc build để dựng trang Có gì mới
- [ ] Tìm kiếm trong hướng dẫn: Pagefind (tĩnh, không cần máy chủ) nếu số trang > 15
- [ ] CI phát hành: thêm bước tạo `SHA256SUMS.txt` cho file APK, bộ cài, zip và đính vào GitHub Release
- [ ] App: thêm hằng `siteUrl` trong `app/lib/app/constants.dart`; màn Giới thiệu thêm link Quyền riêng tư, Điều khoản, Bảo mật, Có gì mới; màn Hỗ trợ thêm "Xem hướng dẫn đầy đủ"; màn đăng ký máy chủ thêm dòng "Đăng ký là đồng ý Điều khoản và Chính sách quyền riêng tư"
- [ ] Mỗi link từ app mở bằng `url_launcher` ở trình duyệt ngoài, chỉ trỏ tới tên miền của site
- [ ] Giữ FAQ trong app và trên site giống nhau: viết một lần (ví dụ file JSON chung) hoặc thêm vào checklist phát hành
- [ ] Bộ cài Windows: đổi `AppUrl` trong `app/installer/vankey.iss` từ GitHub sang site khi có tên miền

## Checklist trước khi công khai

- [ ] Có email liên hệ riêng cho VanKey
- [ ] Chọn giấy phép, thêm `LICENSE` ở gốc repo
- [ ] Trang Quyền riêng tư và Xóa tài khoản đã lên mạng, URL cố định (Play Console cần URL này)
- [ ] Điền mục **Data safety** trên Play Console khớp với trang Quyền riêng tư
- [ ] Microsoft Store (nếu lên): URL chính sách quyền riêng tư, mô tả, ảnh chụp
- [ ] Ảnh chụp và mô tả cửa hàng vi/en (dùng lại chữ của trang chủ)
- [ ] Mọi trang ghi ngày cập nhật; trang pháp lý có lịch sử thay đổi

## Câu hỏi còn mở

- **Giấy phép mã nguồn:** GPL-3.0 (người khác sửa phải công bố mã, như Bitwarden/Aegis), MIT/Apache-2.0 (tự do hơn), hay giữ riêng tư không mở mã
- **Repo công khai hay không:** ảnh hưởng tới link đặc tả, mô hình đe dọa, "sửa trên GitHub", nút kiểm tra bản mới (repo riêng tư thì `api.github.com` không trả về release cho người lạ)
- **Ai vận hành máy chủ công khai:** nếu mở cho người khác đăng ký thì bạn là bên giữ dữ liệu, cần trang Quyền riêng tư và Xóa tài khoản đầy đủ; nếu chỉ dùng riêng thì có thể ghi "máy chủ chỉ dành cho người được mời"
- **Tên miền** (chung với câu hỏi trong PLAN.md)
