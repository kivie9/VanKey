# Ghi chú vận hành

Dành cho người giữ khóa ký, tài khoản Cloudflare và Google Cloud. Không chứa bí mật: mọi giá trị thật chỉ nằm trong nơi cất giữ riêng.

## 1. Những thứ phải cất giữ riêng

| Thứ | Ở đâu | Mất thì sao | Cất ở đâu |
|---|---|---|---|
| Khóa ký Android `.jks` và mật khẩu | `%USERPROFILE%\vankey-signing` (tạo bằng `app/scripts/create-android-signing-key.cmd`) | Không cập nhật đè được bản đã cài | Hai nơi ngoài máy: ổ USB để két, và bản mã hóa trên đám mây riêng |
| `app/android/key.properties` | Trong máy, không đưa lên git | Phải tạo lại từ khóa | Cùng nơi với khóa |
| Secret `TOKEN_SECRET` của Worker | `wrangler secret put` (không đọc lại được) | Mọi thiết bị phải đăng nhập lại | Trình quản lý mật khẩu |
| Secret `REGISTER_CODE` (nếu đặt) | `wrangler secret put` | Không ảnh hưởng tài khoản cũ | Trình quản lý mật khẩu |
| Đăng nhập Cloudflare và Google Cloud | Tài khoản của người phát hành | Không deploy hay đổi OAuth được | Có bật xác thực hai lớp |

Không bao giờ commit `.jks`, `key.properties`, file sao lưu `.vkv`/`.vkbackup`, hay bản xuất CSV có mật khẩu.

## 2. Máy chủ Cloudflare

- Worker `vankey`, cơ sở dữ liệu D1 `vankey` (xem `server/wrangler.toml`).
- Cập nhật: chạy `npm run db:migrate` **trước** `npm run deploy`, vì migration mới phải có mặt trước khi code mới chạy.
- Đổi `TOKEN_SECRET` làm mọi refresh token mất hiệu lực. Chỉ đổi khi nghi lộ, và báo trước cho người dùng.
- Sao lưu D1 định kỳ. Dùng `npx wrangler d1 export vankey --remote --output <file>` (kiểm tra cú pháp với `npx wrangler d1 export --help` trước vì phiên bản wrangler có thể khác). Bản sao chỉ chứa dữ liệu đã mã hóa, nhưng vẫn là dữ liệu cá nhân: cất riêng, không đưa lên git.
- Giới hạn: kho tối đa khoảng 1,5 MB mỗi dòng (giới hạn D1). Quá thì cần chuyển sang R2.
- Theo dõi hạn mức gói miễn phí trong bảng điều khiển Cloudflare.

## 3. Google Drive

Làm theo [google-drive-setup.md](google-drive-setup.md). Điểm cần nhớ:
- Có hai OAuth client (Android và Desktop). Client Android gắn với chữ ký SHA-1 của khóa phát hành, nên đổi khóa là phải thêm SHA-1 mới.
- Màn xin quyền phải ở trạng thái "In production". Nếu để "Testing" thì token hết hạn sau 7 ngày và chỉ 100 tài khoản thử được dùng.
- Mỗi khóa ký (debug, phát hành, Play App Signing) cần một OAuth client Android với SHA-1 tương ứng.

## 4. Phát hành

- **Android:** `app/scripts/create-android-signing-key.cmd` một lần, rồi build theo `app/README.md`. Nếu không có `key.properties` thì build ký bằng khóa debug và có cảnh báo; CI thì dừng hẳn.
- **Windows:** `app/scripts/build-windows.cmd` tạo bản zip và bộ cài `app/installer/vankey.iss` (Inno Setup). Bộ cài chưa thử trên máy Windows sạch.
- **CI:** `.github/workflows/build.yml` build Android, Windows và iOS. Gắn tag `vX.Y.Z` sẽ tạo GitHub Release. Trước khi tag, đổi "Chưa phát hành" trong [CHANGELOG.md](../CHANGELOG.md) thành số phiên bản và ngày.
- Nút "Kiểm tra bản mới" trong app đọc GitHub Releases, nên Release phải được tạo đúng tên để app nhận ra.

## 5. Những việc chưa làm

Theo [STATUS.md](STATUS.md). Các việc phát hành công khai (chính sách quyền riêng tư, điều khoản, LICENSE, SECURITY.md, khai báo Data safety, trang cửa hàng) chưa làm vì chưa quyết định phát hành rộng.

## 6. Mở đăng ký cho người khác

Khi mở đăng ký công khai, người vận hành giữ dữ liệu của người khác. Làm theo các bước dưới đây trước khi mở.

### 6.1 Trước khi mở
- [ ] Đặt `SITE_URL` khi build app (`--dart-define=SITE_URL=https://...`), để các link pháp lý hiện trong app.
- [ ] Deploy trang `site/` (Cloudflare Pages, build `npm run build`, biến `SITE_URL`). Điền các chỗ `[điền: …]` trong trang Quyền riêng tư, Điều khoản, Xóa tài khoản, Bảo mật.
- [ ] Đặt secret `REGISTER_CODE` nếu chỉ muốn mời người quen; để trống nếu mở cho mọi người (có giới hạn theo IP và `MAX_USERS`).
- [ ] Đã chạy `npm run db:migrate` (có migration 0007 ghi nhận đồng ý điều khoản).
- [ ] Cần người có chuyên môn pháp lý xem lại Điều khoản và Chính sách (đặc biệt Nghị định 13/2023/NĐ-CP nếu có người dùng ở Việt Nam).

### 6.2 Yêu cầu từ người dùng
- **Xóa tài khoản:** người dùng tự làm trong app. Nếu không còn máy nào đăng nhập được, xác minh quyền sở hữu theo cách đã ghi trong trang Xóa tài khoản, rồi xóa qua Cloudflare D1 (xóa dòng `users`, các bảng `devices` và `vaults` đi theo nhờ ON DELETE CASCADE). Ghi lại ngày và tên đăng nhập đã xử lý, không ghi nội dung kho.
- **Xem dữ liệu:** máy chủ chỉ có bản mã hóa. Trả lời người dùng rằng server không đọc được nội dung, và liệt kê những gì server có (xem mục 2 trang Quyền riêng tư).
- **Thời hạn trả lời:** ghi rõ trong trang Quyền riêng tư và điền ở đây: `5 ngày làm việc`.

### 6.3 Sự cố lộ dữ liệu
1. Xác định phạm vi: dữ liệu nào, của bao nhiêu tài khoản, từ khi nào. Máy chủ chỉ giữ bản mã hóa, nhưng tên đăng nhập và IP thì không.
2. Thu hồi quyền truy cập bị lộ (đổi `TOKEN_SECRET` nếu nghi lộ khóa ký token; mọi thiết bị phải đăng nhập lại).
3. Thông báo cho người dùng bị ảnh hưởng qua email đăng ký hoặc kênh công khai, trong `72 giờ`.
4. Ghi lại sự cố, nguyên nhân, và biện pháp vào CHANGELOG.

### 6.4 Cách sửa nội dung sau này
- **Nội dung trang pháp lý:** `site/src/pages/…` (tiếng Việt: `dieu-khoan`, `quyen-rieng-tu`, `xoa-tai-khoan`, `bao-mat`; tiếng Anh: `en/terms`, `en/privacy`, `en/delete-account`, `en/security`). Sửa rồi deploy lại site. Đổi ngày "Cập nhật lần cuối" ở mỗi trang.
- **Đổi phiên bản điều khoản** (khi nội dung điều khoản thay đổi và cần người dùng mới đồng ý bản mới): đổi đồng thời ba chỗ:
  1. `server/src/handler.ts`: `TERMS_VERSION`.
  2. `app/lib/core/sync/cloudflare_sync.dart`: `cloudflareTermsVersion`.
  3. Trang Điều khoản (cả hai ngôn ngữ): dòng "Phiên bản điều khoản".
  Sau đó chạy test server và test app. Tài khoản cũ giữ phiên bản đã đồng ý; app hiện chưa có chức năng hỏi đồng ý lại.
- **Link trong app:** đặt bằng `SITE_URL` lúc build, không cần sửa code. Đường dẫn trang nằm trong `app/lib/app/legal.dart`; đổi đường dẫn trang thì sửa ở đó và ở `site/src/pages`.
- **Chuỗi giao diện:** tiếng Việt trong code, tiếng Anh trong `app/lib/app/i18n_en.dart`. Thêm chuỗi mới thì thêm cả hai.
- **Giấy phép:** chưa có file LICENSE. Chọn giấy phép trước khi mở mã nguồn công khai.

### 6.5 Việc chưa làm trong code (đã biết)
- Dòng thiết bị đã gỡ hoặc hết hạn chưa được dọn tự động (trang Quyền riêng tư nói rõ điều này).
- App chưa hỏi người dùng đồng ý lại khi điều khoản đổi phiên bản.
