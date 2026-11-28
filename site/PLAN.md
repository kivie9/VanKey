# VanKey Introduction Website Plan

Updated: 2026-11-27. Phases 1 to 4 are coded; a few checks have not passed or have not been tried yet (noted in each phase). Not deployed yet. How to run: [README.md](README.md).

A static introduction site for VanKey, located in `site/` in this repo and deployed separately to Cloudflare Pages.
Documentation pages (guide, security, privacy, terms, etc.) have their own plan in [CONTENT-PLAN.md](CONTENT-PLAN.md).
The first phase runs locally only. The site will only be connected to Cloudflare when it goes public (VanKey is currently mainly for personal use).

## Decisions made

| Item | Choice | Reason |
|---|---|---|
| Location | `site/` next to `app/` and `server/` | Shares the logo, colours, screenshots and version. Not `app/web/`, because that folder is used by Flutter to run the app in a browser |
| Not Flutter Web | Astro (static HTML) | Flutter Web is several MB, slow to open the first time, and poorly read by Google |
| Framework | **Astro** | No JavaScript by default; JS is only loaded for parts that have effects |
| 3D | **Three.js** | Used only for the hero, loaded late |
| Motion | **GSAP + ScrollTrigger** | Free, stable. Lenis (fake smooth scroll) is not used |
| Languages | Vietnamese (default) + English | `/` and `/en/` |
| Deploy | Cloudflare Pages, separate from the server Worker | Editing the website does not touch the server that holds the vaults |

## Design principle: no "AI slop"

**Do not use:**
- Purple/pink gradients, frosted-glass cards, emoji as icons
- Empty slogans such as "Unlock the power…", "Absolute security", "Military-grade encryption"
- Invented numbers, invented testimonials or partner logos; fake mockup images

**Everything comes from VanKey itself:**
- Colours from `app/lib/app/theme.dart`: background `#0B0B0D`, cards `#141418`, dividers `#26262C`, text `#C6C9CF`, teal accent `#3DB5A0`. The light mode uses `#F4F5F7` / `#15171A`.
- Logo: `docs/brand/vankey-logo.svg`, icons: `docs/branding/`
- Algorithms exactly as in `docs/technical/vault-format.md`: Argon2id, XChaCha20-Poly1305, HKDF-SHA256 for the recovery code
- Features exactly as in `docs/project/STATUS.md`. Anything not really tested is not advertised
- Real screenshots of the app (Android + Windows)

**Fonts:** Geist (sans) + Geist Mono (2FA codes, encrypted strings, technical labels). Self-hosted with `@fontsource`, not loaded from Google Fonts.

**Motion:** motion must have meaning (encryption → lock, real countdown codes), not be decoration. Only `transform`/`opacity` are animated. `prefers-reduced-motion` is respected.

## Page layout

1. **Top bar**: logo, Features, Security, Download, VI/EN, GitHub
2. **Hero**: a Three.js scene. A cloud of scrambled characters (ciphertext) is pulled into the VanKey key shape as the user scrolls. Short headline, two buttons (Download / How it is encrypted)
3. **Live 2FA code**: a 6-digit TOTP box with a 30-second countdown, calculated in the browser from a sample secret (RFC 6238)
4. **Features** (4–6 blocks, not an evenly spaced grid of cards):
   - 2FA: TOTP, HOTP, Steam Guard, QR scanning
   - Import from Google Authenticator, Aegis, 2FAS, Bitwarden, KeePass, 1Password, CSV
   - Works offline, data stays on the device
   - End-to-end encrypted sync (Cloudflare or a folder)
   - Weak and reused password check, and breach check (HIBP k-anonymity)
   - Auto-lock, screenshot blocking, clipboard clearing
5. **Where your data goes**: a diagram that plays as you scroll
   `password → NFKC → Argon2id (64 MiB, 3 passes) → KEK → unlock vault key → XChaCha20-Poly1305 → .vkv file → sync (the server only sees ciphertext)`
6. **Plain talk about security**: if you lose the password and the recovery code, nobody can open the vault; the cryptography has not been independently reviewed; link to `docs/technical/threat-model.md`
7. **Download**: Android (APK), Windows (installer). Before release, it says "coming soon"
8. **Footer**: licence, GitHub, credit to Simple Icons (CC0)

## Folder structure

```
site/
  PLAN.md               this file
  package.json
  astro.config.mjs
  public/               favicon, og-image, optimised screenshots
  src/
    styles/tokens.css   colour, spacing, font variables (light/dark)
    i18n/vi.ts, en.ts   text strings
    layouts/Base.astro
    components/
      Nav.astro, Footer.astro
      Hero.astro        frame + static fallback image
      TotpDemo.astro    live 2FA code
      Features.astro
      CryptoFlow.astro  scroll-driven encryption diagram
      Honesty.astro
      Download.astro
    scripts/
      hero-scene.ts     Three.js (loaded late)
      scroll.ts         GSAP ScrollTrigger
      totp.ts           TOTP with Web Crypto (HMAC-SHA1)
    pages/
      index.astro       Vietnamese
      en/index.astro    English
```

## Steps

### Phase 1: static frame

- [x] 1.1 Create the Astro project in `site/` (TypeScript strict), add `.gitignore` (`node_modules`, `dist`, `.astro`)
- [x] 1.2 `tokens.css`: colours from `theme.dart`, text scale, spacing, light/dark mode following the system
- [x] 1.3 Install Geist + Geist Mono via `@fontsource`
- [x] 1.4 `Base.astro`: meta tags, `lang`, favicon from `docs/branding`
- [x] 1.5 Build all sections (no effects yet), with real Vietnamese text, no lorem ipsum
- [x] 1.6 i18n: `vi.ts` / `en.ts`, the `/en/` page, a language switch button
- [x] 1.7 Responsive: checked at 360, 768, 1280, 1920 px; no horizontal scrolling
- [x] 1.8 Add `paths-ignore: ['site/**']` to `.github/workflows/build.yml` so website edits do not trigger the app build

**Done when:** `npm run dev` shows the full page, it looks right without JS, and Lighthouse ≥ 95.

Result (Lighthouse 13, dev machine, build with CSP header):
- Desktop: all 4 categories score 100.
- Mobile: Accessibility, Best Practices, SEO score 100. LCP 0.8 to 0.9 s, CLS 0.
- **Not yet stable:** mobile Performance varies between 78 and 100, because of TBT. Over 5 runs of the Vietnamese page: median about 85 with the 3D hero on, 98 with it off.

### Phase 2: Three.js hero

- [x] 2.1 Take the outline of the key from `vankey-logo.svg` and sample it into about 3–6k points (done once at build time, saved as a small JSON file)
- [x] 2.2 Particle shader: each particle has a "scrambled" position and a "key" position, blended by `uProgress`
- [x] 2.3 Particles drawn as faint mono characters (texture atlas of hex/base64), colour fading into the background
- [x] 2.4 Bind `uProgress` to scrolling (ScrollTrigger); the scene tilts slightly with mouse movement
- [x] 2.5 Performance: `hero-scene.ts` loaded only when the hero appears; `devicePixelRatio ≤ 2`; phones use fewer particles; rendering stops when the tab is hidden or the hero is off screen
- [x] 2.6 Fallback: without WebGL or with `prefers-reduced-motion`, a static SVG image is shown

**Done when:** 60 fps on an ordinary laptop, no stutter on a mid-range phone, hero JS ≤ 150 KB gzip.

Result: 60 fps while scrolling on Intel Iris Xe (95% of frames ≤ 16.9 ms); hero JS 144.1 KB; total JS 189.9 KB. **Not yet tested on a real phone.**

### Phase 3: scroll motion

- [x] 3.1 `totp.ts`: TOTP with Web Crypto, checked against the RFC 6238 vectors; SVG countdown ring
- [x] 3.2 `CryptoFlow`: steps brighten as you scroll; text turns into ciphertext (a "scramble" effect)
- [x] 3.3 Sections fade in gently (opacity/translate only, no bounce)
- [x] 3.4 `prefers-reduced-motion` check: all content is still readable without effects

### Phase 4: finishing

- [x] 4.1 Real screenshots of the app (Android + Windows), exported to WebP/AVIF via `astro:assets`
- [x] 4.2 SEO: title/description per language, `hreflang`, `sitemap`, `robots.txt`
- [x] 4.3 Share preview image (`og-image` 1200×630)
- [x] 4.4 Accessibility: contrast ≥ 4.5:1, keyboard navigation, `alt` on images, canvas marked `aria-hidden`
- [ ] 4.5 Test on Chrome, Firefox, Edge, Safari iOS (if a device is available). Chrome and Edge tested (normal, reduced motion, JS off, no WebGL). **Firefox not tested (not installed on the machine) and Safari iOS not tested**

### Phase 5: deploy (when going public)

Not deployed yet. The remaining steps are in [README.md](README.md). For 5.3, the download button is already written; you only need to change `RELEASED` in `src/config.ts` (no Release exists yet).

- [ ] 5.1 Cloudflare Pages → Connect to Git → repo `VanKey`
  - Root directory: `site`
  - Build command: `npm run build`, output: `dist`
  - Build watch paths: `site/**`
- [ ] 5.2 (Optional) attach a custom domain
- [ ] 5.3 Download button points to the latest GitHub Releases
- [x] 5.4 Security headers via `public/_headers` (CSP, `X-Content-Type-Options`, `Referrer-Policy`)

Alternative if you do not want to connect the repo: `npx wrangler pages deploy site/dist`.

## Performance budget

| Metric | Target |
|---|---|
| HTML + CSS of the first page | ≤ 60 KB gzip |
| Total JS (including Three.js) | ≤ 200 KB gzip, loaded after the page shows |
| LCP | < 1.5 seconds (fast 4G) |
| CLS | 0 |
| Lighthouse | ≥ 95 in all 4 categories |

## Differences from the original plan

- **The hero shape is the V-shield**, not the key: `vankey-logo.svg` and the app have switched to this logo. The favicon also comes from `docs/brand`, not the old key icon in `docs/branding`.
- **Screenshots** are built from the app's real UI code with sample data (`app/tool/site_screenshots_test.dart`), not captured on a device, so the real vault is never touched.
- Added `Page.astro` (shared layout for both languages), `Screens.astro`, `scripts/totp-demo.ts`.
- The footer does not show a licence yet because the repo has no LICENSE file.
- Secondary text colour in light mode is slightly darker than in the app, to reach 4.5:1 contrast.
- Astro is pinned to 7.4.1 because newer versions need Node 22.23.4. `npm audit` still reports a moderate warning about dynamic route names and the Node adapter; this static site uses neither.

## Decisions taken

- 28/11/2026: **keep the 3D hero on phones**. Accepting that mobile Performance may fall below the target of 95 (measured between 78 and 100). Review if it stutters on a real phone.

## Open questions

- Domain: until one exists, use `*.pages.dev`
- Whether to publish links to the APK/installer before the official signed release
