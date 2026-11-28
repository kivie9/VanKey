# Kế hoạch web giới thiệu VanKey

Cập nhật: 2026-11-27. Giai đoạn 1 đến 4 đã code xong, còn vài điểm kiểm chưa đạt hoặc chưa thử (ghi ở từng giai đoạn). Chưa deploy. Cách chạy: [README.md](README.md).

Trang giới thiệu tĩnh cho VanKey, đặt ở `site/` trong repo này, deploy riêng lên Cloudflare Pages.
Các trang tài liệu (hướng dẫn, bảo mật, quyền riêng tư, điều khoản...) có kế hoạch riêng ở [CONTENT-PLAN.md](CONTENT-PLAN.md).
Giai đoạn đầu chỉ chạy trên máy. Khi nào muốn công khai thì mới kết nối Cloudflare (VanKey hiện chủ yếu để dùng cá nhân).

## Quyết định đã chốt

| Việc | Chọn | Lý do |
|---|---|---|
| Vị trí | `site/` cạnh `app/` và `server/` | Dùng chung logo, màu, ảnh chụp và phiên bản. Không dùng `app/web/` vì đó là thư mục Flutter dùng để chạy app trên trình duyệt |
| Không dùng Flutter Web | Astro (HTML tĩnh) | Flutter Web nặng vài MB, mở lần đầu chậm, Google đọc kém |
| Khung | **Astro** | Mặc định không kèm JavaScript, chỉ tải JS cho phần có hiệu ứng |
| 3D | **Three.js** | Chỉ dùng cho hero, tải muộn |
| Chuyển động | **GSAP + ScrollTrigger** | Miễn phí, ổn định. Không dùng Lenis (cuộn mượt giả) |
| Ngôn ngữ | Việt (mặc định) + Anh | `/` và `/en/` |
| Deploy | Cloudflare Pages, tách khỏi Worker của server | Sửa web không đụng tới server đang giữ kho |

## Nguyên tắc thiết kế: không "AI slop"

**Không dùng:**
- Gradient tím/hồng, thẻ kính mờ, emoji làm icon
- Câu sáo rỗng kiểu "Unlock the power…", "Bảo mật tuyệt đối", "Mã hóa cấp quân sự"
- Số liệu, lời khen hay logo đối tác bịa ra; ảnh mockup giả

**Mọi thứ lấy từ chính VanKey:**
- Màu lấy từ `app/lib/app/theme.dart`: nền `#0B0B0D`, thẻ `#141418`, đường kẻ `#26262C`, chữ `#C6C9CF`, nhấn teal `#3DB5A0`. Chế độ sáng dùng `#F4F5F7` / `#15171A`.
- Logo: `docs/brand/vankey-logo.svg`, icon: `docs/branding/`
- Thuật toán đúng như `docs/vault-format.md`: Argon2id, XChaCha20-Poly1305, HKDF-SHA256 cho mã khôi phục
- Tính năng đúng như `docs/STATUS.md`. Phần nào chưa thử thật thì không quảng cáo
- Ảnh chụp màn hình thật (Android + Windows)

**Phông chữ:** Geist (sans) + Geist Mono (mã 2FA, chuỗi mã hóa, nhãn kỹ thuật). Tự host bằng `@fontsource`, không tải từ Google Fonts.

**Chuyển động:** chuyển động phải có ý nghĩa (mã hóa → khóa, mã đếm ngược thật), không đặt chỉ để trang trí. Chỉ dùng `transform`/`opacity`. Tôn trọng `prefers-reduced-motion`.

## Bố cục trang

1. **Thanh trên**: logo, Tính năng, Bảo mật, Tải về, VI/EN, GitHub
2. **Hero**: cảnh Three.js. Đám hạt ký tự lộn xộn (bản mã) hút lại thành hình chìa khóa VanKey khi cuộn. Tiêu đề ngắn, hai nút (Tải về / Cách mã hóa)
3. **Mã 2FA chạy thật**: một ô TOTP 6 số với vòng đếm ngược 30 giây, tính bằng secret mẫu (RFC 6238) ngay trên trình duyệt
4. **Tính năng** (4–6 khối, không xếp lưới thẻ đều nhau):
   - 2FA: TOTP, HOTP, Steam Guard, quét QR
   - Nhập từ Google Authenticator, Aegis, 2FAS, Bitwarden, KeePass, 1Password, CSV
   - Dùng offline, dữ liệu nằm trên máy
   - Đồng bộ mã hóa đầu cuối (Cloudflare hoặc thư mục)
   - Kiểm tra mật khẩu yếu/trùng và rò rỉ (HIBP k-anonymity)
   - Tự khóa, chặn chụp màn hình, xóa clipboard
5. **Dữ liệu của bạn đi đâu**: sơ đồ chạy theo cuộn
   `mật khẩu → NFKC → Argon2id (64 MiB, 3 vòng) → KEK → mở khóa vault key → XChaCha20-Poly1305 → file .vkv → đồng bộ (server chỉ thấy bản mã)`
6. **Nói thẳng về bảo mật**: mất mật khẩu và mã khôi phục thì không ai mở được kho; mật mã chưa được rà soát độc lập; link tới `docs/threat-model.md`
7. **Tải về**: Android (APK), Windows (bộ cài). Lúc chưa phát hành thì ghi "sắp có"
8. **Footer**: giấy phép, GitHub, ghi công Simple Icons (CC0)

## Cấu trúc thư mục

```
site/
  PLAN.md               file này
  package.json
  astro.config.mjs
  public/               favicon, og-image, ảnh chụp đã tối ưu
  src/
    styles/tokens.css   biến màu, khoảng cách, phông (sáng/tối)
    i18n/vi.ts, en.ts   chuỗi chữ
    layouts/Base.astro
    components/
      Nav.astro, Footer.astro
      Hero.astro        khung + ảnh tĩnh dự phòng
      TotpDemo.astro    mã 2FA chạy thật
      Features.astro
      CryptoFlow.astro  sơ đồ mã hóa theo cuộn
      Honesty.astro
      Download.astro
    scripts/
      hero-scene.ts     Three.js (tải muộn)
      scroll.ts         GSAP ScrollTrigger
      totp.ts           TOTP bằng Web Crypto (HMAC-SHA1)
    pages/
      index.astro       tiếng Việt
      en/index.astro    tiếng Anh
```

## Các bước

### Giai đoạn 1: khung tĩnh

- [x] 1.1 Tạo dự án Astro trong `site/` (TypeScript strict), thêm `.gitignore` (`node_modules`, `dist`, `.astro`)
- [x] 1.2 `tokens.css`: màu từ `theme.dart`, thang chữ, khoảng cách, chế độ sáng/tối theo hệ thống
- [x] 1.3 Cài phông Geist + Geist Mono qua `@fontsource`
- [x] 1.4 `Base.astro`: thẻ meta, `lang`, favicon từ `docs/branding`
- [x] 1.5 Dựng đủ các phần (chưa có hiệu ứng), chữ tiếng Việt viết thật, không dùng lorem
- [x] 1.6 i18n: `vi.ts` / `en.ts`, trang `/en/`, nút đổi ngôn ngữ
- [x] 1.7 Responsive: kiểm tra ở 360, 768, 1280, 1920 px; không cuộn ngang
- [x] 1.8 Thêm `paths-ignore: ['site/**']` vào `.github/workflows/build.yml` để sửa web không kích hoạt build app

**Xong khi:** `npm run dev` mở được trang đầy đủ nội dung, đẹp khi chưa có JS, Lighthouse ≥ 95.

Kết quả (Lighthouse 13, máy dev, bản build có header CSP):
- Desktop: cả 4 mục đạt 100.
- Mobile: Accessibility, Best Practices, SEO đạt 100. LCP 0,8 đến 0,9 s, CLS 0.
- **Chưa đạt ổn định:** Performance mobile dao động 78 đến 100, do TBT. Đo 5 lượt trang tiếng Việt: trung vị khoảng 85 khi bật hero 3D, 98 khi tắt.

### Giai đoạn 2: hero Three.js

- [x] 2.1 Lấy đường viền chìa khóa từ `vankey-logo.svg` rồi lấy mẫu thành khoảng 3–6k điểm (làm một lần lúc build, lưu thành file JSON nhỏ)
- [x] 2.2 Shader cho hạt: mỗi hạt có vị trí "lộn xộn" và vị trí "chìa khóa", trộn theo `uProgress`
- [x] 2.3 Hạt vẽ như ký tự mono mờ (texture atlas hex/base64), màu teal nhạt dần vào nền
- [x] 2.4 Gắn `uProgress` với cuộn (ScrollTrigger); chuột di chuyển thì cảnh nghiêng nhẹ
- [x] 2.5 Hiệu năng: chỉ tải `hero-scene.ts` khi hero hiện ra; giới hạn `devicePixelRatio ≤ 2`; điện thoại dùng ít hạt hơn; dừng render khi tab ẩn hoặc hero ra khỏi màn hình
- [x] 2.6 Dự phòng: không có WebGL hoặc bật `prefers-reduced-motion` thì hiện ảnh tĩnh SVG

**Xong khi:** đạt 60 fps trên laptop thường, không giật trên điện thoại tầm trung, phần JS của hero ≤ 150 KB gzip.

Kết quả: 60 fps khi cuộn trên Intel Iris Xe (95% khung hình ≤ 16,9 ms); JS của hero 144,1 KB; JS tổng 189,9 KB. **Chưa thử trên điện thoại thật.**

### Giai đoạn 3: chuyển động theo cuộn

- [x] 3.1 `totp.ts`: TOTP bằng Web Crypto, đối chiếu với vector trong RFC 6238; vòng đếm ngược SVG
- [x] 3.2 `CryptoFlow`: các bước sáng dần khi cuộn, chuỗi chữ biến thành bản mã (hiệu ứng "scramble")
- [x] 3.3 Các phần hiện dần nhẹ (chỉ dùng opacity/translate, không bật nảy)
- [x] 3.4 Kiểm tra `prefers-reduced-motion`: mọi nội dung vẫn đọc được khi không có hiệu ứng

### Giai đoạn 4: hoàn thiện

- [x] 4.1 Chụp màn hình thật của app (Android + Windows), xuất WebP/AVIF qua `astro:assets`
- [x] 4.2 SEO: title/description từng ngôn ngữ, `hreflang`, `sitemap`, `robots.txt`
- [x] 4.3 Ảnh xem trước khi chia sẻ link (`og-image` 1200×630)
- [x] 4.4 Trợ năng: tương phản ≥ 4.5:1, điều hướng bằng bàn phím, `alt` cho ảnh, canvas đặt `aria-hidden`
- [ ] 4.5 Kiểm tra trên Chrome, Firefox, Edge, Safari iOS (nếu có máy). Đã thử Chrome và Edge (thường, giảm chuyển động, tắt JS, không WebGL). **Chưa thử Firefox (máy chưa cài) và Safari iOS**

### Giai đoạn 5: deploy (khi muốn công khai)

Chưa deploy. Các bước còn lại ghi ở [README.md](README.md). Với 5.3, nút tải về đã viết sẵn, chỉ cần đổi `RELEASED` trong `src/config.ts` (chưa có Release nào).

- [ ] 5.1 Cloudflare Pages → Connect to Git → repo `VanKey`
  - Root directory: `site`
  - Build command: `npm run build`, output: `dist`
  - Build watch paths: `site/**`
- [ ] 5.2 (Tùy chọn) gắn tên miền riêng
- [ ] 5.3 Nút tải về trỏ tới GitHub Releases mới nhất
- [x] 5.4 Header bảo mật qua `public/_headers` (CSP, `X-Content-Type-Options`, `Referrer-Policy`)

Cách khác nếu không muốn kết nối repo: `npx wrangler pages deploy site/dist`.

## Ngân sách hiệu năng

| Chỉ số | Mục tiêu |
|---|---|
| HTML + CSS trang đầu | ≤ 60 KB gzip |
| JS tổng (gồm Three.js) | ≤ 200 KB gzip, tải sau khi trang hiện |
| LCP | < 1,5 giây (4G nhanh) |
| CLS | 0 |
| Lighthouse | ≥ 95 cả 4 mục |

## Khác với kế hoạch ban đầu

- **Hình hero là khiên chữ V**, không phải chìa khóa: `vankey-logo.svg` và app đã đổi sang logo này. Favicon cũng lấy từ `docs/brand`, không lấy biểu tượng chìa khóa cũ trong `docs/branding`.
- **Ảnh màn hình** được dựng từ mã giao diện thật với dữ liệu mẫu (`app/tool/site_screenshots_test.dart`), không chụp trên thiết bị, để không đụng tới kho thật.
- Thêm `Page.astro` (bố cục chung hai ngôn ngữ), `Screens.astro`, `scripts/totp-demo.ts`.
- Footer chưa ghi giấy phép vì repo chưa có file LICENSE.
- Màu chữ phụ ở chế độ sáng đậm hơn app một chút để đạt tương phản 4.5:1.
- Astro ghim 7.4.1 vì bản mới hơn cần Node 22.23.4. `npm audit` còn cảnh báo mức vừa về tên thẻ động và adapter Node, trang tĩnh này không dùng cả hai.

## Đã quyết định

- 28/11/2026: **giữ hero 3D trên điện thoại**. Chấp nhận Performance mobile có thể dưới mục tiêu 95 (đo được 78 đến 100). Xem lại nếu thử trên điện thoại thật thấy giật.

## Câu hỏi còn mở

- Tên miền: chưa có thì tạm dùng `*.pages.dev`
- Có công khai link tải APK/bộ cài khi chưa ký phát hành chính thức không
