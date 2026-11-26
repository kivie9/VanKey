# Hệ thiết kế VanKey

Toàn bộ giao diện lấy từ **một nơi**: `app/lib/app/theme.dart`. Màn hình không viết mã màu hay kiểu rời.
Không dùng thư viện giao diện bên ngoài: dùng bộ thành phần Material của Flutter, nhưng được tùy biến đầy đủ qua theme.

## Màu (lấy từ prototype)

| Vai trò | Sáng | Tối (nền đen thật) |
|---|---|---|
| `page` nền trang | `#F4F5F7` | `#000000` |
| `card` thẻ, hộp thoại, thanh dưới | `#FFFFFF` | `#0F0F11` |
| `field` ô nhập | `#FFFFFF` | `#131315` |
| `line` đường kẻ mảnh | `#E3E6EA` | `#232327` |
| `fg` / `muted` chữ | `#15171A` / `#6B7280` | `#F2F2F5` / `#9A9AA3` |
| `accent` màu nhấn | xanh ngọc `#0B7A6B` (đổi được 6 màu) | `#4BC6B0` (sáng hơn để đủ tương phản) |
| `warn` / `danger` / `success` | `#B45309` / `#B42318` / `#15803D` | `#F5A54A` / `#FF8A7A` / `#5FD38D` |

Lấy màu trong code: `AppColors.of(context)` hoặc `Theme.of(context).colorScheme`.

## Khoảng cách và bo góc

`Gap` (4, 8, 12, 16, 24, 32) và `Radii` (8, 12, 16, 20). Thẻ bo 16, ô nhập và nút bo 12, hộp thoại bo 20.

## Thành phần

- **Ô nhập:** nền `field`, viền mảnh `line` bo 12, khi chọn viền màu nhấn 1,6 px, nhãn nổi màu nhấn. Màn hình **không** tự đặt `border`.
- **Nút:** `FilledButton` (nhấn), `OutlinedButton` (phụ, nền thẻ), `TextButton` (chữ màu nhấn); cao 50, bo 12.
- **Thẻ nhóm:** `SectionCard` (nhiều dòng, đường kẻ mảnh giữa các dòng), `GroupedRow` (cho danh sách dài, lười).
- **Khác:** `SectionHeader`, `IconBadge`, `Notice` (thông tin, cảnh báo, lỗi), `EmptyState`, `StrengthMeter`, `AppLogo`, `TotpChip`. Nằm ở `lib/app/widgets/`.
- **Menu, hộp thoại, bottom sheet, snackbar, chip, công tắc, thanh điều hướng:** đều có theme riêng trong `theme.dart`.

## Bố cục máy tính

Cửa sổ rộng từ 840 px dùng `screens/desktop_home.dart`, theo chế độ "Máy tính (Windows)" của prototype: thanh trên, cột menu 200 px (Tất cả, từng loại, thẻ, Mã 2FA, Tiện ích, Cài đặt), lưới thẻ rộng tối thiểu 300 px, chi tiết mục mở trong hộp thoại. Hẹp hơn thì dùng bố cục điện thoại. Khác prototype có chủ ý: danh sách Kho không hiện mục và mã 2FA (đã có mục riêng), và có thêm mục "Tiện ích".

## Gom theo dịch vụ

Kiểu gom "Dịch vụ" (cạnh Thẻ, Loại, Không gom): dịch vụ có từ hai tài khoản xếp thành một thẻ, bấm để mở; đang tìm kiếm thì mở sẵn. Trong nhóm, mục trùng tên dịch vụ hiện tên đăng nhập ở dòng chính.

- Dịch vụ được **tính**, không lưu vào kho (`lib/core/vault/services.dart`): theo tên miền của địa chỉ web; không có địa chỉ thì theo cả tên mục.
- Chỉ khớp đúng tên miền hoặc tên miền con: `facebook.com.trang-la.ru` không phải Facebook. Không dùng `brandFor` (đoán logo) để gom.
- Ô "Dịch vụ" trong form chỉ là cách chọn nhanh, nó điền địa chỉ web và tên.
- Mục đăng nhập cũ chưa có địa chỉ mà tên gần giống dịch vụ: hỏi ở màn chi tiết và ở Tiện ích → Gợi ý dịch vụ. App chỉ sửa khi bấm "Đúng"; câu trả lời "Không" lưu trong cài đặt của máy.

## Xem giao diện khi chỉnh

Không cần mở điện thoại. Test chụp ảnh các màn chính (sáng và tối) ra `app/build/screens/`:

```powershell
cd app
flutter test test/tool/screenshots_test.dart --dart-define=VK_SHOTS=true
```

Test này nạp đúng các phông của app, nên chữ hiển thị đúng. Ảnh bố cục máy tính có tên `2x_may_tinh_*`. Bình thường (`flutter test`) nó tự bỏ qua.

## Lưu ý kỹ thuật

- Đổ bóng (`elevation`) không dùng cho thẻ, menu, hộp thoại: viền mảnh thay cho bóng. Chỉ nút tròn dấu cộng có quầng sáng màu nhấn.
- Phông đóng gói sẵn trong `app/assets/fonts` (giấy phép OFL, kèm trong thư mục), giống nhau trên Windows và Android. Tên họ phông lấy qua `Fonts` trong `theme.dart`: `body` (Inter) cho chữ thường, `head` (Space Grotesk, tối đa đậm 700) cho tiêu đề, `mono` (JetBrains Mono) cho mã 2FA, mật khẩu, khóa.
