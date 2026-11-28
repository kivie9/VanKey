import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Địa chỉ công khai của web (canonical, hreflang, sitemap, og:image).
// Mặc định là domain thật, kể cả khi build trên máy hay bản preview của Cloudflare Pages.
// Đặt biến SITE_URL nếu cần đổi sang địa chỉ khác.
const site = process.env.SITE_URL || 'https://vankey.onigix.com';

export default defineConfig({
  site,
  // Không nhúng CSS/JS vào HTML để CSP trong public/_headers không cần 'unsafe-inline'.
  build: { inlineStylesheets: 'never' },
  vite: { build: { assetsInlineLimit: 0 } },
  devToolbar: { enabled: false },
  integrations: [sitemap({ i18n: { defaultLocale: 'vi', locales: { vi: 'vi', en: 'en' } } })],
});
