# Cài đặt đồng bộ Google Drive (làm một lần, bởi người phát hành app)

Đồng bộ qua Google Drive cho người dùng **không muốn dùng máy chủ**. Họ chỉ bấm "Đăng nhập Google". Phần dưới là việc **bạn (người phát hành app)** phải làm một lần để app đăng nhập Google được. Người dùng không phải đăng ký gì.

Hiện chỉ có trên **Android**. Kho được lưu dạng đã mã hóa thành một file `vankey.vkv` trong thư mục ẩn `appDataFolder` của app trên Drive của người dùng. App chỉ xin quyền `drive.appdata` (không đọc, không thấy file nào khác trong Drive). Google không đọc được nội dung vì file đã mã hóa từ máy.

> Chưa kiểm tra trên điện thoại thật: toàn bộ phần gọi Drive đã được kiểm thử với một máy chủ Drive giả, nhưng bước đăng nhập Google cần thông tin Google Cloud của bạn nên chưa chạy được ở đây. Hãy thử theo mục 6 sau khi cấu hình xong.

## 1. Tạo project và bật Drive API

1. Vào <https://console.cloud.google.com/>, tạo project mới (ví dụ `vankey`).
2. APIs & Services → Library → tìm **Google Drive API** → Enable.

## 2. Màn hình xin quyền (OAuth consent screen)

1. APIs & Services → OAuth consent screen (hoặc Google Auth Platform).
2. User type: **External**. Điền tên app (`VanKey`), email hỗ trợ, và **link chính sách riêng tư** (bắt buộc khi công khai; có thể là một trang GitHub Pages ngắn nói app chỉ lưu bản mã hóa và chỉ dùng `drive.appdata`).
3. Scopes: thêm `https://www.googleapis.com/auth/drive.appdata`. Đây là quyền không nhạy cảm nên **không cần Google xét duyệt app**.
4. **Chuyển Publishing status sang "In production".** Nếu để ở "Testing" thì token đăng nhập hết hạn sau 7 ngày (người dùng phải đăng nhập lại liên tục) và chỉ 100 tài khoản thử được dùng.

## 3. Tạo OAuth client (hai cái)

APIs & Services → Credentials → Create credentials → OAuth client ID:

1. **Android**
   - Package name: `com.vankey.vankey`
   - SHA-1 certificate fingerprint: của khóa ký APK (xem mục 5).
2. **Web application** (không cần Authorized redirect URI)
   - Copy **Client ID** của cái này. Đây là `GOOGLE_SERVER_CLIENT_ID`.

Mỗi khóa ký khác nhau (khóa debug, khóa release) cần một OAuth client Android riêng với SHA-1 tương ứng. Có thể tạo nhiều client Android trong cùng project.

## 4. Build app với Client ID

```powershell
cd app
flutter build apk --release --split-per-abi --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

Client ID không phải bí mật (nằm trong APK), nhưng được truyền lúc build nên **không ghi cứng trong mã nguồn công khai**. Build không có biến này thì app vẫn chạy bình thường, lựa chọn Google Drive hiện lỗi "chưa cấu hình".

## 5. Khóa ký APK và SHA-1

Android đối chiếu đăng nhập Google với SHA-1 của khóa ký APK. Sai SHA-1 thì Google chỉ báo "canceled".

**Khóa debug (để thử trên máy của bạn).** Bản build hiện tại ký bằng khóa debug của máy bạn. SHA-1 của nó:

```powershell
& "C:\Program Files\Java\jdk-21\bin\keytool.exe" -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

Trên máy phát triển này, SHA-1 của khóa debug là `0D:BE:13:7B:63:96:CF:32:29:DD:72:34:14:9C:1C:59:38:7A:56:9F`. Khóa debug **khác nhau trên mỗi máy** và không dùng để phát hành.

**Khóa release (để phát hành).** Tạo một lần và cất ở nơi an toàn:

```powershell
& "C:\Program Files\Java\jdk-21\bin\keytool.exe" -genkeypair -v -keystore vankey-release.jks -alias vankey -keyalg RSA -keysize 2048 -validity 10000
```

- **Sao lưu file `.jks` và mật khẩu của nó** (ví dụ vào trình quản lý mật khẩu). Mất khóa này thì không thể phát hành bản cập nhật cho người đã cài.
- Đừng commit file này (đã có trong `.gitignore`: `*.jks`, `key.properties`).
- Lấy SHA-1 của nó bằng `keytool -list -v -keystore vankey-release.jks -alias vankey` rồi tạo thêm một OAuth client Android với SHA-1 đó.
- **Đổi khóa ký làm các bản đã cài không cập nhật đè được** (Android báo xung đột chữ ký, phải gỡ bản cũ và mất dữ liệu trong máy). Hãy đổi khóa trước khi có người dùng thật.
- Nếu sau này đưa lên Google Play với Play App Signing, Google ký lại app bằng khóa của họ: thêm SHA-1 của khóa đó (xem trong Play Console → App integrity) vào một OAuth client Android nữa.

## 6. Thử

1. Cài bản build có `GOOGLE_SERVER_CLIENT_ID` lên điện thoại có tài khoản Google.
2. Xóa dữ liệu app (hoặc cài mới) để thấy màn đầu → chọn **Dùng Google Drive của bạn** → *Đăng nhập Google* → chọn tài khoản → cho phép.
3. Drive chưa có kho: đặt mật khẩu (từ 8 ký tự), lưu mã khôi phục, vào app, thêm một mục.
4. Trên máy thứ hai (hoặc sau khi xóa dữ liệu máy này): chọn Google Drive, đăng nhập cùng tài khoản → app báo Drive đã có kho → nhập mật khẩu → thấy mục đã thêm.
5. Kiểm tra: Google Drive (web) → Manage apps → VanKey sẽ có mục "Hidden app data". Người dùng có thể xóa dữ liệu này tại đó.

## Xử lý lỗi thường gặp

| Triệu chứng | Nguyên nhân thường gặp |
|---|---|
| "Đã hủy đăng nhập Google" ngay sau khi chọn tài khoản | Sai SHA-1, sai package name, hoặc thiếu/sai `GOOGLE_SERVER_CLIENT_ID`. Kiểm tra từng cái; build debug và release cần SHA-1 khác nhau. |
| "Cấu hình đăng nhập Google chưa đúng" | `GOOGLE_SERVER_CLIENT_ID` không phải client loại **Web application**, hoặc chưa bật Drive API. |
| Đăng nhập lại sau 7 ngày | Consent screen vẫn ở "Testing": chuyển sang "In production". |
| "Chưa được cấp quyền dùng Google Drive" | Người dùng bỏ chọn quyền ở màn xin quyền: đăng nhập lại và cho phép. |
| Lúc mạng yếu báo giới hạn tốc độ | Drive tạm giới hạn; app tự thử lại, không mất dữ liệu. |

## Giới hạn đã biết

- Drive **không có ghi có điều kiện**, nên hai máy ghi gần như cùng một lúc có thể ghi đè nhau trong một khoảng hở rất ngắn. App kiểm tra phiên bản ngay trước khi ghi và gộp lại ở lần đồng bộ sau, nên kết quả hội tụ mà không mất mục nào (có test mô phỏng đúng tình huống này), nhưng không chặt như máy chủ Cloudflare.
- Chỉ Android. Máy tính dùng được đồng bộ qua thư mục (Drive for Desktop) hoặc máy chủ Cloudflare.
- Đồng bộ liên tục không gây quá hạn mức: app chỉ đồng bộ khi quay lại app và 3 giây sau mỗi lần sửa, không thăm dò liên tục.
