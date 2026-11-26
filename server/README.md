# Máy chủ VanKey (Cloudflare Worker + D1)

Máy chủ **chỉ giữ bản mã hóa** của kho và thông tin đăng nhập. Nó không bao giờ đọc được mật khẩu, mã 2FA hay nội dung kho của bạn.
Chạy miễn phí trên gói free của Cloudflare. Một máy chủ phục vụ được nhiều người dùng (mặc định tối đa 200 tài khoản).

## Cách hoạt động

- Đăng nhập bằng **tên đăng nhập + mật khẩu**. Tên đăng nhập gồm 3 đến 32 ký tự: chữ thường, số, dấu chấm, gạch dưới, gạch ngang. App dẫn xuất một khóa từ mật khẩu bằng Argon2id rồi chỉ gửi khóa đó; máy chủ băm thêm bằng PBKDF2 trước khi lưu. Mật khẩu gốc không rời khỏi máy.
- **Một mật khẩu cho cả tài khoản và kho.** Khóa mở kho được dẫn xuất riêng ở phía app (salt khác, nằm trong file kho), nên khóa đăng nhập máy chủ giữ không mở được kho.
- **Đăng ký mở**: ai cũng tạo được tài khoản, có giới hạn để bảo vệ hạn mức miễn phí: tối đa `MAX_USERS` tài khoản (mặc định 200), mỗi IP tối đa 10 lần đăng ký (quá thì khóa 1 giờ), mỗi tài khoản tối đa 20 thiết bị (thiết bị lâu không dùng nhất bị gỡ).
- **Mã mời (tùy chọn)**: đặt secret `REGISTER_CODE` (từ 12 ký tự) thì tạo tài khoản phải nhập đúng mã. Dùng khi muốn mời riêng hoặc tạm đóng đăng ký (đặt một mã không ai biết). Đặt ngắn hơn 12 ký tự = đóng đăng ký.
- Access token sống 15 phút; refresh token 90 ngày, **xoay vòng** mỗi lần dùng, máy chủ chỉ lưu mã băm. Gỡ một thiết bị có hiệu lực ngay.
- Đăng nhập sai (hoặc nhập sai mã mời) 5 lần liên tiếp theo IP thì bị khóa tăng dần (30 giây, gấp đôi mỗi lần, tối đa 15 phút); IPv6 gom theo /64. Theo tài khoản có ngưỡng cao hơn (20 lần) để người lạ khó khóa tài khoản của bạn. Bộ đếm cập nhật nguyên tử, tên không có thật không tạo thêm dòng trong cơ sở dữ liệu, và dòng cũ được dọn.
- Ghi kho dùng `If-Match`: nếu máy khác đã ghi trước, máy chủ trả 409 và app tự gộp rồi thử lại.

## Thử cục bộ (không cần Cloudflare)

Chỉ cần Node 22.6+ (không cài gói nào):

```powershell
cd server
node dev/serve.ts 8787          # lưu trong bộ nhớ, tắt là mất
node --test test/server.test.ts test/d1.test.ts    # 40 test, gồm SQL thật trên SQLite
```

App trỏ vào `http://127.0.0.1:8787` (hoặc `http://10.0.2.2:8787` từ trình giả lập Android). Địa chỉ `http://` chỉ được chấp nhận cho máy cục bộ.
Máy chủ thử cho đăng ký mở. Muốn thử có mã mời: đặt biến môi trường `REGISTER_CODE` (từ 12 ký tự).

## Triển khai lên Cloudflare (làm một lần)

Cần tài khoản Cloudflare (miễn phí) và Node.

1. Cài công cụ và đăng nhập:
   ```powershell
   cd server
   npm install
   npx wrangler login
   ```
2. Tạo cơ sở dữ liệu và dán `database_id` in ra vào `wrangler.toml`:
   ```powershell
   npx wrangler d1 create vankey
   ```
3. Tạo bảng (chạy lại sau mỗi lần cập nhật máy chủ có migration mới, **trước khi** deploy):
   ```powershell
   npm run db:migrate
   ```
4. Đặt bí mật ký token (chuỗi ngẫu nhiên từ 32 ký tự; **cất lại ở nơi an toàn**, đổi nó là mọi thiết bị phải đăng nhập lại):
   ```powershell
   npx wrangler secret put TOKEN_SECRET
   ```
5. (Tùy chọn) đặt mã mời nếu không muốn cho mọi người đăng ký:
   ```powershell
   npx wrangler secret put REGISTER_CODE
   ```
6. Triển khai:
   ```powershell
   npm run deploy
   ```
   Wrangler in địa chỉ dạng `https://vankey.<tài-khoản>.workers.dev`. Mở địa chỉ đó trong trình duyệt phải thấy `{"ok":true,"service":"vankey"}`.
7. Trong app, ở màn đầu chọn **Tự dựng máy chủ (self-host)**, nhập địa chỉ ở bước 6, rồi chọn *Tạo tài khoản* (nhập mã mời nếu bạn có đặt).
8. Trên máy thứ hai: chọn lại **Tự dựng máy chủ**, nhập địa chỉ và *Đăng nhập* bằng cùng tên đăng nhập và mật khẩu. Kho tự mở.

### Cách khác: triển khai qua Git (Workers Builds trên dashboard Cloudflare)

Dùng khi bạn muốn Cloudflare tự build và deploy mỗi lần push lên GitHub, thay vì chạy `wrangler` trên máy.

**Chuẩn bị (trước khi bấm Deploy):**

1. Dashboard → Storage & Databases → D1 → *Create database*, đặt tên `vankey`, copy `database_id`.
2. Sửa `wrangler.toml` trong repo: `database_id` = id vừa copy. Commit và push.

**Màn hình "Set up your application":**

| Ô | Giá trị |
|---|---|
| Project name | `vankey` (phải trùng `name` trong `wrangler.toml`) |
| Root directory (mục Advanced settings) | `server` (Worker nằm trong thư mục con, không phải gốc repo) |
| Build command | để trống |
| Deploy command | `npx wrangler d1 migrations apply vankey --remote && npx wrangler deploy` |
| Preview command | để nguyên `npx wrangler preview` |

Deploy command ở trên tạo bảng rồi mới deploy; migration đã áp dụng thì được bỏ qua nên chạy lại an toàn.

**Sau lần deploy đầu:**

1. Workers & Pages → `vankey` → Settings → Variables and Secrets → Add, loại **Secret**, tên `TOKEN_SECRET`, giá trị là chuỗi ngẫu nhiên từ 32 ký tự (cất lại ở nơi an toàn), rồi Deploy để áp dụng. Chưa có secret này thì máy chủ không đăng nhập được. Muốn đăng ký theo mã mời thì thêm tương tự secret `REGISTER_CODE`.
2. Mở `https://vankey.<tài-khoản>.workers.dev`, phải thấy `{"ok":true,"service":"vankey"}`.
3. Nối app như bước 7 ở trên.

**Lỗi thường gặp:** không thấy `wrangler.toml` thì chưa đặt Root directory là `server`; lỗi `database_id` thì chưa dán id thật và push lên.

### Cập nhật từ bản dùng email

Bản cũ đăng nhập bằng email và danh sách `ALLOWED_EMAILS`. Migration `0003` đổi tên cột `email` thành `username` và giữ nguyên dữ liệu, nhưng tên đăng nhập mới phải theo quy tắc ở trên: tài khoản cũ có dấu `@` sẽ không đăng nhập được nữa (app yêu cầu tên đăng nhập đúng quy tắc). Nếu đã có tài khoản như vậy, hãy tạo tài khoản mới bằng tên đăng nhập hợp lệ rồi nhập kho từ file sao lưu.

### Đổi mật khẩu, xóa tài khoản, số vòng băm (migration `0004`)

- `POST /auth/password` `{authKey, newAuthKey}` (cần token): đổi mật khẩu tài khoản. Phải gửi đúng mật khẩu hiện tại; sai bị đếm và khóa như đăng nhập. Các thiết bị khác của tài khoản bị gỡ. App gọi API này khi đổi mật khẩu trong Cài đặt, trước khi đổi trên máy.
- `DELETE /account` `{authKey}` (cần token): xóa hẳn tài khoản, kho và mọi thiết bị. Không hoàn tác được. Trong app: Đồng bộ → Xóa tài khoản.
- Tài khoản mới băm authKey bằng PBKDF2 `5000` vòng thay cho `100000` (100000 vòng vượt giới hạn CPU 10 ms của gói miễn phí). authKey đã qua Argon2id trên máy nên không yếu đi. Tài khoản cũ tự được băm lại ở lần đăng nhập đúng kế tiếp.
- Nhớ chạy `npx wrangler d1 migrations apply vankey --remote` trước khi deploy (thêm cột `kdf_iter`).

## Giới hạn đã biết

- D1 giới hạn khoảng 2 MB mỗi dòng, nên kho tối đa 1,5 MB (khoảng vài nghìn mục). Quá thì máy chủ trả 413; hướng xử lý sau này là chuyển sang R2.
- Giới hạn tốc độ nằm trong D1 (theo IP và theo tài khoản), chưa dùng tính năng rate limiting của Cloudflare. Trên tên miền `workers.dev` không dùng được quy tắc WAF.
- Đăng ký mở nên người lạ có thể tạo tài khoản cho tới khi đạt `MAX_USERS`. Muốn chặn hẳn, đặt `REGISTER_CODE`.
- Phần D1 đã được kiểm với SQLite thật và đúng các file migration, nhưng chưa chạy trên D1 thật của Cloudflare với bản đăng ký mở này.
