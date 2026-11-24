# Máy chủ VanKey (Cloudflare Worker + D1)

Máy chủ **chỉ giữ bản mã hóa** của kho và thông tin đăng nhập. Nó không bao giờ đọc được mật khẩu, mã 2FA hay mật khẩu kho của bạn.
Chạy miễn phí trên gói free của Cloudflare với một người dùng.

## Cách hoạt động

- Đăng nhập bằng **email + mật khẩu tài khoản**. App dẫn xuất một khóa từ mật khẩu bằng Argon2id rồi chỉ gửi khóa đó; máy chủ băm thêm bằng PBKDF2 trước khi lưu. Mật khẩu gốc không rời khỏi máy.
- (Tùy chọn) đăng nhập bằng **Google** (xác minh ID token bằng JWKS, kiểm `aud`, `iss`, `exp`).
- Chỉ các email trong `ALLOWED_EMAILS` đăng ký được. Danh sách rỗng = từ chối tất cả.
- Access token sống 15 phút; refresh token 90 ngày, **xoay vòng** mỗi lần dùng, máy chủ chỉ lưu mã băm. Gỡ một thiết bị có hiệu lực ngay.
- Đăng nhập sai 5 lần liên tiếp thì bị khóa tăng dần (30 giây, gấp đôi mỗi lần, tối đa 15 phút), tính theo email và theo địa chỉ IP.
- Ghi kho dùng `If-Match`: nếu máy khác đã ghi trước, máy chủ trả 409 và app tự gộp rồi thử lại.

## Thử cục bộ (không cần Cloudflare)

Chỉ cần Node 22.6+ (không cài gói nào):

```powershell
cd server
node dev/serve.ts 8787          # lưu trong bộ nhớ, tắt là mất
node --test test/server.test.ts test/d1.test.ts    # 34 test, gồm SQL thật trên SQLite
```

App trỏ vào `http://127.0.0.1:8787` (hoặc `http://10.0.2.2:8787` từ trình giả lập Android). Địa chỉ `http://` chỉ được chấp nhận cho máy cục bộ.
Email thử mặc định: `test@example.com` (đổi bằng biến môi trường `ALLOWED_EMAILS`).

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
3. Sửa `ALLOWED_EMAILS` trong `wrangler.toml` thành email của bạn (nhiều email ngăn cách bằng dấu phẩy).
4. Tạo bảng:
   ```powershell
   npm run db:migrate
   ```
5. Đặt bí mật ký token (chuỗi ngẫu nhiên từ 32 ký tự; **cất lại ở nơi an toàn**, đổi nó là mọi thiết bị phải đăng nhập lại):
   ```powershell
   npx wrangler secret put TOKEN_SECRET
   ```
6. Triển khai:
   ```powershell
   npm run deploy
   ```
   Wrangler in địa chỉ dạng `https://vankey.<tài-khoản>.workers.dev`. Mở địa chỉ đó trong trình duyệt phải thấy `{"ok":true,"service":"vankey"}`.
7. Trong app: Cài đặt → Dữ liệu → Đồng bộ → *Đồng bộ qua máy chủ Cloudflare của bạn*, nhập địa chỉ, email, mật khẩu tài khoản và bật **Tạo tài khoản mới**.
8. Trên máy thứ hai: ở màn đầu tiên chọn *Đã có tài khoản máy chủ? Đăng nhập để tải kho về*, nhập thêm **mật khẩu của kho** (hoặc mã khôi phục).

### Cách khác: triển khai qua Git (Workers Builds trên dashboard Cloudflare)

Dùng khi bạn muốn Cloudflare tự build và deploy mỗi lần push lên GitHub, thay vì chạy `wrangler` trên máy.

**Chuẩn bị (trước khi bấm Deploy):**

1. Dashboard → Storage & Databases → D1 → *Create database*, đặt tên `vankey`, copy `database_id`.
2. Sửa `wrangler.toml` trong repo: `database_id` = id vừa copy, `ALLOWED_EMAILS` = email của bạn. Commit và push.

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

1. Workers & Pages → `vankey` → Settings → Variables and Secrets → Add, loại **Secret**, tên `TOKEN_SECRET`, giá trị là chuỗi ngẫu nhiên từ 32 ký tự (cất lại ở nơi an toàn), rồi Deploy để áp dụng. Chưa có secret này thì máy chủ không đăng nhập được.
2. Mở `https://vankey.<tài-khoản>.workers.dev`, phải thấy `{"ok":true,"service":"vankey"}`.
3. Nối app như bước 7 ở trên.

**Lỗi thường gặp:** không thấy `wrangler.toml` thì chưa đặt Root directory là `server`; lỗi `database_id` thì chưa dán id thật và push lên.

### Bật đăng nhập Google (tùy chọn)

Cần tạo OAuth client trong Google Cloud, rồi bỏ comment `GOOGLE_CLIENT_IDS` trong `wrangler.toml` và deploy lại. Phía app chưa có nút Google (cần client ID của bạn).

## Giới hạn đã biết

- D1 giới hạn khoảng 2 MB mỗi dòng, nên kho tối đa 1,5 MB (khoảng vài nghìn mục). Quá thì máy chủ trả 413; hướng xử lý sau này là chuyển sang R2.
- Giới hạn tốc độ nằm trong D1, chưa dùng tính năng rate limiting của Cloudflare.
- Chưa có đổi mật khẩu tài khoản (đổi mật khẩu **kho** thì có).
- Phần D1 đã được kiểm với SQLite thật và đúng file migration, nhưng chưa chạy trên D1 thật của Cloudflare.
