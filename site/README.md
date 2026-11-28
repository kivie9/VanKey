# Web giới thiệu VanKey

Trang tĩnh viết bằng Astro, tiếng Việt ở `/`, tiếng Anh ở `/en/`. Kế hoạch và tiến độ: [PLAN.md](PLAN.md).

## Chạy trên máy

Cần Node 22.22 trở lên.

```powershell
npm install
```

```powershell
npm run dev
```

| Lệnh | Việc |
|---|---|
| `npm run build` | Kiểm kiểu (`astro check`) rồi build ra `dist/` |
| `npm run preview` | Xem bản đã build |
| `npm test` | TOTP đối chiếu vector RFC 6238 |
| `npm run budget` | Kiểm ngân sách dung lượng gzip (chạy sau build) |
| `npm run gen` | Sinh lại điểm cho hero, favicon, ảnh chia sẻ link (khi logo hoặc tiêu đề đổi) |

Kết quả của `npm run gen` được commit, nên lúc build không cần chạy lại. Hình hero lấy từ hai đường nét trong `docs/brand/vankey-logo.svg`.

## Ảnh chụp màn hình

Ảnh được dựng từ mã giao diện thật của app với dữ liệu mẫu (giao diện tối, màu xanh ngọc), không đụng tới kho thật. Chạy trong `app/`:

```powershell
flutter test tool/site_screenshots_test.dart
```

## Sửa nội dung

- Chữ ở trang chủ: `src/i18n/vi.ts` và `src/i18n/en.ts` (thiếu khóa thì `astro check` báo lỗi).
- Chỉ quảng cáo tính năng theo `docs/STATUS.md`. Phần chưa thử thật phải có ghi chú. Khi đã thử xong thì bỏ ghi chú ở khối tính năng **và** ở mục "Đã viết nhưng chưa thử thật".
- Trang mới có hai ngôn ngữ: thêm cặp đường dẫn vào `PAGE_PAIRS` trong `src/config.ts` để canonical, hreflang và nút đổi ngôn ngữ đúng.
- Phiên bản hiển thị lấy từ `app/pubspec.yaml`.

## Deploy (khi muốn công khai)

Trước khi công khai: điền hết chỗ `[điền: ...]` / `[fill: ...]` trong các trang pháp lý.

1. Cloudflare → Workers & Pages → tạo dự án Pages → Connect to Git → repo `VanKey`.
2. Root directory `site`, build command `npm run build`, output `dist`.
3. Build watch paths: `site/**`. Web còn đọc `docs/brand/vankey-logo.svg` và `app/pubspec.yaml`, nên đổi logo hoặc phiên bản thì bấm build lại, hoặc thêm hai đường dẫn đó.
4. Biến môi trường:
   - `SITE_URL`: địa chỉ thật, ví dụ địa chỉ `*.pages.dev` được cấp hoặc tên miền riêng. Dùng cho canonical, sitemap và ảnh chia sẻ. Thiếu biến này thì web dùng `CF_PAGES_URL`, là địa chỉ riêng của từng lần deploy.
   - `NODE_VERSION`: `22`.
5. (Tùy chọn) Custom domains → gắn tên miền riêng, rồi cập nhật `SITE_URL`.
6. Khi đã có GitHub Release: đổi `RELEASED` thành `true` trong `src/config.ts` và sửa câu mô tả nếu cần. Nút tải về sẽ trỏ tới `releases/latest`.

Không muốn nối repo: build trên máy rồi chạy `npx wrangler pages deploy dist` trong `site/`.

Header bảo mật (CSP...) nằm ở `public/_headers`. CSP không cho script hay style viết thẳng trong HTML, nên đừng thêm thuộc tính `style="..."` hoặc `<script is:inline>`.
