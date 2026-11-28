# Hướng dẫn nhanh VanKey

Đọc một lần trước khi bắt đầu. Các mục ở dưới đi theo thứ tự quan trọng nhất trước.

## 1. Ba điều phải nhớ

1. **Mật khẩu kho và mã khôi phục là hai thứ duy nhất mở được kho.** Không ai lấy lại được, kể cả nhà phát triển. Mất cả hai là mất dữ liệu.
2. **Lưu mã khôi phục ngoài điện thoại.** Lúc tạo kho app chỉ hiện mã một lần. Chép mã rồi cất vào sổ khôi phục (xem [recovery-sheet.md](recovery-sheet.md)), không lưu trong ảnh chụp hay ghi chú trên máy.
3. **Sao lưu mã hóa định kỳ.** Cài đặt → Dữ liệu → Xuất và sao lưu → Sao lưu mã hóa. File này chỉ mở lại được bằng mật khẩu hoặc mã khôi phục.

## 2. Tạo kho lần đầu

1. Mở VanKey, chọn cách dùng: máy chủ VanKey, Google Drive, hoặc chỉ trên máy này.
2. Đặt mật khẩu kho. Chọn một mật khẩu dài, nhớ được, và không dùng ở nơi khác.
3. Chép mã khôi phục hiện ra. Đánh dấu ô "Tôi đã lưu mã khôi phục" rồi bấm **Bắt đầu dùng** (nút chỉ bật sau khi đánh dấu).
4. Ghi mã vào sổ khôi phục và cất sổ ở nơi an toàn.

## 3. Chuyển từ Google Authenticator

1. Trong Google Authenticator chọn **Xuất tài khoản**, chọn các mục cần chuyển.
2. Trong VanKey bấm **+ → Quét QR**. Có thể chụp màn hình mã QR rồi chọn ảnh.
3. So vài mã 2FA với app cũ. Khi đã khớp, mới xóa app cũ.
4. **Xóa link và ảnh chụp mã QR xuất ra** sau khi xong. Chúng chứa bí mật 2FA.

## 4. Đồng bộ giữa các máy

- Bật trong **Cài đặt → Dữ liệu → Đồng bộ**. Chọn máy chủ VanKey, Google Drive hoặc một thư mục.
- Máy mới: đăng nhập vào máy chủ hoặc chọn đúng Google Drive/thư mục, rồi nhập mật khẩu kho.
- Khi hai máy sửa cùng một mục, app hiện màn xung đột để bạn chọn bản giữ lại.
- Mất điện thoại: trên máy còn lại vào **Cài đặt → Dữ liệu → Đồng bộ → Thiết bị đã đăng nhập** và gỡ máy bị mất. Sau đó đổi mật khẩu kho nếu nghi bị lộ.

## 5. Mở khóa và bảo vệ

- Mở bằng vân tay hoặc Windows Hello chỉ là lối vào nhanh. Vẫn cần mật khẩu kho khi đổi vân tay trên máy.
- Bật **tự khóa** (mặc định 5 phút). Không để kho mở khi đưa máy cho người khác.
- Quên mật khẩu kho: ở màn mở khóa bấm **Quên mật khẩu? Dùng mã khôi phục**, nhập mã, rồi đặt mật khẩu mới và **tạo mã khôi phục mới**. Mã cũ không dùng lại được.

## 6. Mục khi quên hoặc mất thiết bị

| Tình huống | Việc cần làm |
|---|---|
| Quên mật khẩu kho, còn mã khôi phục | Dùng mã khôi phục ở màn mở khóa, đặt mật khẩu mới, tạo mã khôi phục mới |
| Quên cả hai | Không mở được kho. Vào lại từng dịch vụ bằng mã dự phòng của dịch vụ đó, rồi tạo kho mới |
| Mất điện thoại | Gỡ máy đó trong Thiết bị đã đăng nhập, đổi mật khẩu kho |
| Muốn xóa tài khoản máy chủ | Cài đặt → Dữ liệu → Đồng bộ → Xóa tài khoản (không hoàn tác được) |

## 7. Lịch nên làm

- **Mỗi 3 tháng:** thử mở kho bằng mã khôi phục hoặc file sao lưu, ghi ngày vào sổ khôi phục.
- **Mỗi lần đổi mật khẩu kho:** cập nhật sổ khôi phục.
- **Trước khi xóa app hoặc đổi máy:** xuất sao lưu mã hóa và kiểm tra file mở được.

## 8. Những điều app không làm

- Không gửi mật khẩu hay dữ liệu kho ra ngoài khi không bật đồng bộ.
- Không có phân tích hay báo lỗi tự động.
- Kiểm tra mật khẩu rò rỉ chỉ gửi 5 ký tự đầu của mã băm tới HaveIBeenPwned.

Câu hỏi thường gặp đầy đủ hơn nằm trong màn **Cài đặt → Hỗ trợ**.
