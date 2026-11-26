# Mô hình đe dọa — bản nháp v0.1

> Trạng thái: **NHÁP**, viết trước khi có code để làm thước đo cho các quyết định bảo mật. Cần xem lại sau M3 (bảo mật thiết bị) và trước khi phát hành.

---

## 1. Tài sản cần bảo vệ

| Tài sản | Mức nhạy cảm |
|---|---|
| Mật khẩu, khóa API, cụm từ khôi phục ví, số thẻ | Rất cao |
| **Khóa 2FA (secret TOTP)** | Rất cao (ai có là tạo được mã 2FA của bạn) |
| Vault passphrase, recovery key | Rất cao (mở được toàn bộ kho) |
| Mã khôi phục/backup codes của dịch vụ khác | Rất cao |
| Tên dịch vụ, số lượng mục, thời điểm sửa (siêu dữ liệu) | Thấp đến trung bình |

---

## 2. Kẻ tấn công và mức bảo vệ

| # | Kẻ tấn công / tình huống | Có bảo vệ không | Bằng cách nào |
|---|---|---|---|
| A1 | **Nghe lén mạng** (Wi-Fi công cộng, MITM) | Có | HTTPS; dữ liệu đã mã hóa từ trước khi rời máy |
| A2 | **Nơi lưu trữ bị xâm nhập** (Google Drive, Cloudflare D1, lộ cơ sở dữ liệu) | Có | Chỉ lưu blob mã hóa; không có khóa nào ở server |
| A3 | **Quản trị server/Google xem dữ liệu** | Có | Như A2 (zero-knowledge) |
| A4 | **Tài khoản Google/đăng nhập của bạn bị chiếm** | Một phần | Kẻ tấn công lấy được blob mã hóa nhưng không giải mã được. Họ có thể **xóa hoặc phá** blob; mỗi thiết bị giữ bản đầy đủ nên mất mát được giảm |
| A5 | **Đoán passphrase ngoại tuyến** (có file kho) | Phụ thuộc passphrase | Argon2id chống đoán hàng loạt. **Passphrase yếu vẫn bị đoán được.** App phải đo độ mạnh khi đặt |
| A6 | **Mất điện thoại/laptop (đang khóa)** | Có | Khóa màn hình + khóa app; khóa nằm trong Keystore/Credential Manager; sinh trắc |
| A7 | **Thiết bị bị lấy khi đang mở khóa** | Hạn chế | Tự khóa sau N phút; xóa khóa khỏi RAM khi khóa. Không chống được người đang cầm máy đã mở |
| A8 | **Nhìn trộm, chụp màn hình, ghi màn hình** | Một phần | `FLAG_SECURE` (Android), ẩn khi chuyển app, ẩn mật khẩu mặc định |
| A9 | **Clipboard bị đọc bởi app khác** | Giảm | Tự xóa sau 30 giây; đánh dấu nhạy cảm (Android) |
| A10 | **Thông báo/log lộ bí mật** | Có | Thông báo chỉ ghi tên dịch vụ và hạn; không log dữ liệu nhạy cảm |
| A11 | **Thư viện bên thứ ba bị cài mã độc** (chuỗi cung ứng) | Giảm | Ghim phiên bản, ít phụ thuộc, rà soát khi cập nhật, ưu tiên thư viện được dùng rộng rãi |
| A12 | **Lừa đảo/social engineering** (trang giả đòi passphrase) | Một phần | App không bao giờ đòi passphrase qua web; chỉ nhập trong app |
| A13 | **Người dùng làm mất cả passphrase lẫn recovery key** | **Không** | Không thể khôi phục. Phải nói rõ và ép lưu recovery key lúc tạo |

---

## 3. Ngoài phạm vi (không bảo vệ được)

- **Thiết bị đã nhiễm mã độc, keylogger, trình ghi màn hình, root/jailbreak có chủ đích.** Mã độc có quyền cao đọc được bộ nhớ khi kho đang mở.
- **Kẻ tấn công cầm thiết bị đã mở khóa và hiểu app.**
- **Bắt buộc pháp lý/ép buộc người dùng** (xem 5).
- **Tấn công kênh phụ phần cứng** (đo điện, nhiệt...).
- **Passphrase yếu hoặc dùng lại ở nơi khác.**

---

## 4. Tính chất bảo mật cần đạt

1. **Zero-knowledge:** không bao giờ gửi passphrase, recovery key, vault key, hay bản rõ ra khỏi thiết bị.
2. **Toàn vẹn:** sửa bất kỳ byte nào của file kho thì giải mã thất bại, không trả dữ liệu sai.
3. **Chống hạ cấp:** không chấp nhận tham số KDF yếu hơn cận dưới; không chấp nhận file version thấp rồi ghi đè kho version cao.
4. **Tách đăng nhập khỏi khóa:** đăng nhập Google/email chỉ cho biết bạn là ai; không đủ để giải mã.
5. **Thu hồi thiết bị:** gỡ thiết bị khỏi tài khoản làm thiết bị đó mất quyền tải/ghi trên server. (Không xóa được dữ liệu đã tải về máy đó, xem 6.)

---

## 5. Giả định và hạn chế cần nói thẳng với người dùng

- Quên cả passphrase lẫn recovery key = **mất dữ liệu vĩnh viễn**.
- Gỡ một thiết bị **không** thu hồi được bản sao dữ liệu đã nằm trên thiết bị đó. Nếu nghi thiết bị đã bị lộ, phải **đổi vault passphrase và xoay vault key**, rồi đổi mật khẩu của các dịch vụ quan trọng.
- Siêu dữ liệu lộ ra ngoài: kích thước file (đã đệm theo bội số 4 KiB), thời điểm cập nhật, số thiết bị, địa chỉ IP kết nối tới server.
- Google Drive/Cloudflare có thể **xóa hoặc không trả** file của bạn. Mỗi thiết bị giữ bản đầy đủ và có xuất sao lưu để giảm rủi ro.

---

## 5b. Bề mặt tấn công theo thành phần

| Thành phần | Rủi ro chính | Biện pháp |
|---|---|---|
| App (Dart) | Dữ liệu còn trong RAM sau khi khóa; GC không xóa được ngay | Xóa/ghi đè bộ đệm khóa khi khóa; giữ thời gian sống của bản rõ ngắn nhất có thể (**giới hạn đã biết**: Dart không bảo đảm xóa tuyệt đối) |
| Lưu cục bộ | Đọc trực tiếp file | File luôn mã hóa; khóa thiết bị trong Keystore/Credential Manager |
| Đồng bộ Drive | Token OAuth bị lấy | Token lưu trong kho an toàn của OS; scope tối thiểu `drive.appdata` |
| Server Cloudflare | Tấn công đăng nhập, spam, chiếm slot lưu trữ | Giới hạn tốc độ theo IP và tài khoản, giới hạn số tài khoản, số lần đăng ký mỗi IP và số thiết bị, mã mời tùy chọn, băm mật khẩu hai lớp, refresh token lưu dạng băm và thu hồi được |
| Nhập/xuất | File CSV/JSON không mã hóa nằm lại trên ổ đĩa | Cảnh báo rõ, yêu cầu passphrase, nhắc xóa file sau khi dùng |
| Kiểm tra rò rỉ (HIBP) | Gửi mật khẩu ra ngoài | Chỉ gửi **5 ký tự đầu của mã băm SHA-1** (k-anonymity), không bao giờ gửi mật khẩu |
| Thông báo | Lộ bí mật trên màn hình khóa | Chỉ ghi tên dịch vụ và hạn |
| Cập nhật app | Bị thay bản cài | Ký bản phát hành; phân phối qua kênh có kiểm soát |

---

## 6. Việc cần làm để đáp ứng (liên kết sang TASKS.md)

- [ ] Đặc tả định dạng và test vector (`vault-format.md`, M1)
- [ ] Đo độ mạnh passphrase khi đặt, từ chối passphrase quá yếu (M2/M3)
- [ ] Làm chậm khi nhập sai nhiều lần (M3)
- [ ] Không log dữ liệu nhạy cảm; rà soát log trước khi phát hành (M3)
- [ ] Thông báo không chứa bí mật (M6)
- [ ] Diễn tập khôi phục và diễn tập mất thiết bị (M7)
- [ ] Nhờ người có chuyên môn rà soát đặc tả và phần mật mã trước khi dùng thật (M7)

---

## 7. Cần xem lại khi

- Thêm extension trình duyệt hoặc Autofill (bề mặt mới: trang web độc hại, ứng dụng giả mạo).
- Thêm chia sẻ giữa người dùng hoặc truy cập khẩn cấp (mô hình khóa thay đổi lớn).
- Thêm push từ server (thêm tiết lộ siêu dữ liệu qua Google FCM / Microsoft WNS).
- Mở đăng ký cho nhiều người dùng (thêm lạm dụng, thêm trách nhiệm lưu trữ).
