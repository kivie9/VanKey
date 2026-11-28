# VanKey Introduction Website

A static site written in Astro: Vietnamese at `/`, English at `/en/`. Plan and progress: [PLAN.md](PLAN.md).

## Running on your machine

Requires Node 22.22 or newer.

```powershell
npm install
```

```powershell
npm run dev
```

| Command | Purpose |
|---|---|
| `npm run build` | Type-check (`astro check`), then build into `dist/` |
| `npm run preview` | Preview the built site |
| `npm test` | TOTP checked against the RFC 6238 vectors |
| `npm run budget` | Check the gzip size budget (run after build) |
| `npm run gen` | Regenerate the points for the hero, favicon and share image (when the logo or title changes) |

The output of `npm run gen` is committed, so the build does not need to run it again. The hero shape comes from two strokes in `docs/brand/vankey-logo.svg`.

## Screenshots

The images are built from the app's real UI code with sample data (dark mode, teal accent), so the real vault is never touched. Run inside `app/`:

```powershell
flutter test tool/site_screenshots_test.dart
```

## Editing content

- Text on the homepage: `src/i18n/vi.ts` and `src/i18n/en.ts` (a missing key makes `astro check` report an error).
- Only advertise features that are in `docs/project/STATUS.md`. Features not yet really tested must carry a note. Once tested, remove the note both in the feature block **and** in the "Written but not yet tested" item.
- New pages have two languages: add the path pair to `PAGE_PAIRS` in `src/config.ts` so the canonical link, hreflang and language switch are correct.
- The displayed version comes from `app/pubspec.yaml`.

## Deploy (when going public)

Before going public: fill in every `[điền: ...]` / `[fill: ...]` placeholder in the legal pages.

1. Cloudflare → Workers & Pages → create a Pages project → Connect to Git → repo `VanKey`.
2. Root directory `site`, build command `npm run build`, output `dist`.
3. Build watch paths: `site/**`. The site also reads `docs/brand/vankey-logo.svg` and `app/pubspec.yaml`, so rebuild when the logo or version changes, or add those two paths to the watch list.
4. Environment variables:
   - `SITE_URL`: the real address, for example the `*.pages.dev` address assigned or a custom domain. Used for the canonical link, the sitemap and share images. Without it, the site uses `CF_PAGES_URL`, the per-deployment address.
   - `NODE_VERSION`: `22`.
5. (Optional) Custom domains → attach a custom domain, then update `SITE_URL`.
6. Once a GitHub Release exists: change `RELEASED` to `true` in `src/config.ts` and adjust the description if needed. The download button will then point to `releases/latest`.

If you do not want to connect the repo: build locally and run `npx wrangler pages deploy dist` inside `site/`.

Security headers (CSP, etc.) are in `public/_headers`. The CSP does not allow scripts or styles written inline in HTML, so inline `style="..."` attributes and `<script is:inline>` tags are not used.
