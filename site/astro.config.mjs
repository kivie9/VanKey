import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Địa chỉ công khai của web (canonical, hreflang, sitemap, og:image).
// Khi deploy thì đặt biến SITE_URL trong Cloudflare Pages; chạy trên máy thì dùng localhost.
const site = process.env.SITE_URL || process.env.CF_PAGES_URL || 'http://localhost:4321';

export default defineConfig({
  site,
  // Không nhúng CSS/JS vào HTML để CSP trong public/_headers không cần 'unsafe-inline'.
  build: { inlineStylesheets: 'never' },
  vite: { build: { assetsInlineLimit: 0 } },
  devToolbar: { enabled: false },
  integrations: [sitemap({ i18n: { defaultLocale: 'vi', locales: { vi: 'vi', en: 'en' } } })],
});
