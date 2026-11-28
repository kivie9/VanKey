# Sổ khôi phục khẩn cấp VanKey

**Tiếng Việt** · [English](recovery-sheet.en.md)

> **Đây là bản mẫu trống.** In ra giấy rồi điền bằng tay. **Không** điền vào file này, không lưu bản đã điền trong repo, máy tính, ảnh chụp hay đám mây.
> Cất bản đã điền ở nơi an toàn ngoài nhà nếu được (két, người thân tin cậy). Có thể in 2 bản, cất 2 nơi.

Ngày lập: ____ / ____ / ________  Lần xem lại gần nhất: ____ / ____ / ________

---

## 1. Thông tin mở kho

| Mục | Ghi vào đây |
|---|---|
| Mã khôi phục (lúc tạo kho, hoặc tạo mới ở Cài đặt → Tài khoản → Mã khôi phục) | ______________________________________________ |
|  | ______________________________________________ |
| Gợi ý mật khẩu kho (chỉ gợi ý, **không** ghi mật khẩu) | ______________________________________________ |

App không cho xem lại mã cũ. Không chắc mã đang ghi còn đúng thì tạo mã mới (mã cũ hết hiệu lực) rồi ghi lại.

Mất **cả** mật khẩu kho **và** mã khôi phục thì không ai mở lại được kho, kể cả nhà phát triển.

## 2. Đồng bộ và tài khoản

| Mục | Ghi vào đây |
|---|---|
| Có dùng máy chủ VanKey không? Địa chỉ máy chủ | ☐ Có  ☐ Không   ______________________________ |
| Tên đăng nhập máy chủ (mật khẩu tài khoản: không ghi ở đây) | ______________________________ |
| Có dùng Google Drive không? Tài khoản Google nào | ☐ Có  ☐ Không   ______________________________ |
| Có dùng thư mục đồng bộ không? Đường dẫn | ☐ Có  ☐ Không   ______________________________ |

## 3. Bản sao lưu mã hóa

| Nơi cất file sao lưu (`.vkv`) | Ngày sao lưu gần nhất |
|---|---|
| 1. ______________________________ | ____ / ____ / ________ |
| 2. ______________________________ | ____ / ____ / ________ |

File sao lưu chỉ mở lại được bằng mật khẩu kho hoặc mã khôi phục. Nên sao lưu lại sau mỗi lần thêm nhiều mục 2FA.

## 4. Thiết bị đang dùng VanKey

| Thiết bị | Mở bằng sinh trắc? |
|---|---|
| ______________________________ | ☐ Vân tay  ☐ Windows Hello  ☐ Không |
| ______________________________ | ☐ Vân tay  ☐ Windows Hello  ☐ Không |
| ______________________________ | ☐ Vân tay  ☐ Windows Hello  ☐ Không |

## 5. Các tài khoản quan trọng có 2FA trong VanKey

Ghi những tài khoản mà mất 2FA thì khó lấy lại (email chính, ngân hàng, tài khoản Google, Apple, Cloudflare, GitHub...). Ghi luôn nơi cất **mã dự phòng** (backup codes) của từng dịch vụ nếu có.

| Dịch vụ | Nơi cất mã dự phòng của dịch vụ |
|---|---|
| ______________________________ | ______________________________ |
| ______________________________ | ______________________________ |
| ______________________________ | ______________________________ |
| ______________________________ | ______________________________ |
| ______________________________ | ______________________________ |

---

## Khi cần dùng

### A. Mất hoặc hỏng điện thoại, máy tính
1. Trên máy khác đang dùng VanKey: Cài đặt → Dữ liệu → Đồng bộ → Thiết bị đã đăng nhập → **gỡ thiết bị bị mất** (chỉ có khi dùng máy chủ VanKey).
2. Nếu nghi máy bị người khác cầm được: **đổi mật khẩu kho** ngay (Cài đặt → Tài khoản → Đổi mật khẩu kho).
3. Cài VanKey lên máy mới (xem mục B).
4. Đổi mật khẩu các tài khoản quan trọng ở mục 5 nếu máy cũ không có khóa màn hình.

### B. Cài lại từ đầu trên máy mới
1. Cài VanKey (Android: file APK; Windows: bộ cài từ trang phát hành).
2. Chọn một trong ba:
   - **Máy chủ VanKey:** đăng nhập bằng tên đăng nhập ở mục 2, app tải kho về.
   - **Google Drive / thư mục:** bật đồng bộ, chọn đúng tài khoản hoặc thư mục ở mục 2.
   - **File sao lưu:** mở file `.vkv` ở mục 3.
3. Mở kho bằng mật khẩu kho. Quên mật khẩu thì chọn **Quên mật khẩu? Dùng mã khôi phục** và nhập mã ở mục 1.
4. Nếu vừa dùng mã khôi phục: đặt mật khẩu kho mới, tạo mã khôi phục mới (Cài đặt → Tài khoản → Mã khôi phục) và cập nhật tờ này.
5. So vài mã 2FA với dịch vụ thật để chắc chắn đúng.

### C. Quên mật khẩu kho nhưng còn mã khôi phục
Màn mở khóa → **Quên mật khẩu? Dùng mã khôi phục** → nhập mã → đặt mật khẩu mới → tạo mã khôi phục mới → cập nhật mục 1.

### D. Mất cả mật khẩu kho lẫn mã khôi phục
Không mở được kho. Dùng **mã dự phòng của từng dịch vụ** ở mục 5 để vào lại tài khoản, rồi tạo kho mới và thêm lại 2FA.

---

## Lịch kiểm tra

- [ ] Mỗi 3 tháng: thử mở kho bằng mã khôi phục trên một máy (hoặc file sao lưu), ghi ngày ở đầu tờ.
- [ ] Mỗi lần đổi mật khẩu kho hoặc tạo mã khôi phục mới: cập nhật mục 1.
- [ ] Mỗi lần thêm hoặc bỏ thiết bị: cập nhật mục 4.
