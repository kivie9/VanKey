# Operations Notes

For the people who hold the signing keys and the Cloudflare and Google Cloud accounts. Contains no secrets: all real values are stored only in their separate, secure locations.

## 1. Things that must be stored separately

| Item | Where | If lost | Where to keep it |
|---|---|---|---|
| Android signing key `.jks` and its password | `%USERPROFILE%\vankey-signing` (created by `app/scripts/create-android-signing-key.cmd`) | Updates can no longer be installed over the released app | Two places off the computer: a USB drive in a safe, and an encrypted copy in a private cloud |
| `app/android/key.properties` | On the computer, not committed to git | It has to be recreated from the key | Same place as the key |
| Worker secret `TOKEN_SECRET` | `wrangler secret put` (cannot be read back) | Every device must sign in again | Password manager |
| Worker secret `REGISTER_CODE` (if set) | `wrangler secret put` | Existing accounts are not affected | Password manager |
| Cloudflare and Google Cloud sign-in | The publisher's accounts | Cannot deploy or change OAuth | Two-factor authentication enabled |

The files `.jks`, `key.properties`, backup files `.vkv`/`.vkbackup`, or CSV exports containing passwords.

## 2. Cloudflare server

- Worker `vankey`, D1 database `vankey` (see `server/wrangler.toml`).
- Update: run `npm run db:migrate` **before** `npm run deploy`, because new migrations must exist before the new code runs.
- Changing `TOKEN_SECRET` invalidates every refresh token. Change it only if you suspect exposure, and warn users in advance.
- Back up D1 regularly. Use `npx wrangler d1 export vankey --remote --output <file>` (check the syntax with `npx wrangler d1 export --help` first, because the wrangler version may differ). The backup only contains encrypted data, but it is still personal data: store it separately and never put it in git.
- Limit: a vault can be at most about 1.5 MB per row (D1 limit). Beyond that, move to R2.
- Keep an eye on the free-plan quotas in the Cloudflare dashboard.

## 3. Google Drive

Follow [google-drive-setup.md](google-drive-setup.md). Key points:
- There are two OAuth clients (Android and Desktop). The Android client is tied to the SHA-1 fingerprint of the release key, so changing the key means adding the new SHA-1.
- The consent screen must be in the "In production" state. If it stays in "Testing", tokens expire after 7 days and only 100 test accounts can be used.
- Each signing key (debug, release, Play App Signing) needs an Android OAuth client with the matching SHA-1.

## 4. Release

- **Android:** run `app/scripts/create-android-signing-key.cmd` once, then build according to `app/README.md`. Without `key.properties`, the build is signed with the debug key and shows a warning; CI stops completely.
- **Windows:** `app/scripts/build-windows.cmd` creates the zip and the installer from `app/installer/vankey.iss` (Inno Setup). The installer has not yet been tested on a clean Windows machine.
- **CI:** `.github/workflows/build.yml` builds Android, Windows and iOS. Pushing a `vX.Y.Z` tag creates a GitHub Release. Before tagging, change "Unreleased" in [CHANGELOG.md](../project/CHANGELOG.md) to the version number and date.
- The "Check for updates" button in the app reads GitHub Releases, so the Release must be named correctly for the app to recognise it.

## 5. Not done yet

See [STATUS.md](../project/STATUS.md). Public release tasks (privacy policy, terms, LICENSE, SECURITY.md, the Data safety declaration, store listing) are not done yet because the decision to release widely has not been made.

## 6. Opening registration to others

When public registration is opened, the operator holds other people's data. Complete the steps below before opening.

### 6.1 Before opening
- [ ] Set `SITE_URL` when building the app (`--dart-define=SITE_URL=https://vankey.onigix.com`) so that the legal links appear in the app.
- [ ] Deploy the `site/` pages (Cloudflare Pages, build `npm run build`, variable `SITE_URL`). Check that the Privacy, Terms, Delete account and Security pages are current.
- [ ] Set the `REGISTER_CODE` secret if you only want to invite people you know; leave it empty to open to everyone (limited by IP and `MAX_USERS`).
- [ ] Run `npm run db:migrate` (migration 0007 records consent to the terms).
- [ ] Have a legal professional review the Terms and Policy (especially Decree 13/2023/ND-CP if there are users in Vietnam).

### 6.2 Requests from users
- **Account deletion:** users do it themselves in the app. If no device can still sign in, verify ownership as described on the Delete account page, then delete through Cloudflare D1 (delete the `users` row; the `devices` and `vaults` tables follow through ON DELETE CASCADE). Record the date and the username handled, not the vault contents.
- **Access to data:** the server only holds encrypted data. Tell the user that the server cannot read the content, and list what the server stores (see section 2 of the Privacy page).
- **Response time:** stated on the Privacy page as `5 working days`.

### 6.3 Data breach
1. Define the scope: which data, how many accounts, since when. The server only keeps encrypted data, but usernames and IP addresses are not encrypted.
2. Revoke the exposed access (change `TOKEN_SECRET` if you suspect the token-signing key was exposed; every device must sign in again).
3. Notify the affected users by their registered email or a public channel, within `72 hours`.
4. Record the incident, its cause and the measures taken in the CHANGELOG.

### 6.4 Changing content later
- **Legal page content:** `site/src/pages/…` (Vietnamese: `dieu-khoan`, `quyen-rieng-tu`, `xoa-tai-khoan`, `bao-mat`; English: `en/terms`, `en/privacy`, `en/delete-account`, `en/security`). Edit, then redeploy the site. Update the "Last updated" date on each page.
- **Changing the terms version** (when the terms change and users must agree to the new version): change these three places together:
  1. `server/src/handler.ts`: `TERMS_VERSION`.
  2. `app/lib/core/sync/cloudflare_sync.dart`: `cloudflareTermsVersion`.
  3. The Terms page (both languages): the line "Terms version".
  Then run the server and app tests. Existing accounts keep the version they agreed to; the app does not yet ask users to agree again.
- **Links in the app:** set through `SITE_URL` at build time, no code change needed. Page paths are in `app/lib/app/legal.dart`; if you change a page path, update it there and in `site/src/pages`.
- **UI strings:** Vietnamese in the code, English in `app/lib/app/i18n_en.dart`. When adding a new string, add both.
- **License:** there is no LICENSE file yet. Choose a license before publishing the source code.

### 6.5 Known code gaps
- Removed or expired device entries are not cleaned up automatically (the Privacy page states this).
- The app does not ask users to agree again when the terms version changes.
