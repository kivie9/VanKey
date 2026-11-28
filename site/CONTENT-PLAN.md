# Documentation Pages Plan for the Site

Updated: 2026-11-27. Not started yet. This supplements [PLAN.md](../docs/project/PLAN.md) (the introduction page): this file says **which pages the site needs beyond the homepage, what each page says, and where its information comes from**.

VanKey is currently used personally, so the work is split into two waves:
- **Wave 1 (personal use):** pages useful to you, not legally required.
- **Wave 2 (before going public):** pages that Google Play, Microsoft Store or unknown users need.

## Overview of pages

| Path (vi / en) | Page | Wave | Who needs it | Linked from the app |
|---|---|---|---|---|
| `/huong-dan/` · `/en/guide/` | User guide | 1 | Users | Support |
| `/huong-dan/chuyen-tu-google-authenticator/` | Moving from Google Authenticator | 1 | Users | Support, Import screen |
| `/huong-dan/sao-luu-va-khoi-phuc/` | Backup, recovery, lost device | 1 | Users | Support, recovery code screen |
| `/bao-mat/` · `/en/security/` | How VanKey protects data | 1 | Users, reviewers | About |
| `/thay-doi/` · `/en/changelog/` | What's new | 1 | Users | About, new-version notice |
| `/tai-ve/` · `/en/download/` | Download and verify the file | 1 | Users | "New version available" button |
| `/quyen-rieng-tu/` · `/en/privacy/` | Privacy policy | 2 | **Required** (Play, Store) | About, sign-up screen |
| `/dieu-khoan/` · `/en/terms/` | Terms of use | 2 | Should have | About, sign-up screen |
| `/xoa-tai-khoan/` · `/en/delete-account/` | Delete account and data | 2 | **Required** (Play, because the app has account sign-up) | Account screen |
| `/bao-loi-bao-mat/` · `/en/security/report/` | Report a security vulnerability | 2 | Should have | About |
| `/.well-known/security.txt` | Security contact (RFC 9116) | 2 | Should have | None |
| `/giay-phep/` · `/en/licenses/` | Licences and credits | 2 | Should have | About |

Footer on every page: Privacy · Terms · Security · Licences · What's new · GitHub.

---

## Wave 1

### 1. User guide
A table of contents page, with a short sub-page for each task (one task per page, with real screenshots):
- Create the vault, set a password, **save the recovery code** (state clearly that the app does not show an old code again; it can only create a new one)
- Add 2FA items: scan QR with the camera, from an image, enter manually; HOTP, Steam Guard
- Import from other apps: Google Authenticator, Aegis, 2FAS, Bitwarden, KeePass XML, 1Password `.1pux`, CSV
- Sync: VanKey server, Google Drive, a folder (desktop only); handling conflicts
- Add a new device, remove a lost device
- Unlock with fingerprint / Windows Hello, auto-lock
- Security check and HIBP
- Reminders
- FAQ: copied from the Support screen (`app/lib/app/screens/info_screens.dart`); keep both in sync

**Source:** `docs/project/STATUS.md` (only describe features that have really been tested), the menu in `settings_tab.dart`.

### 2. Moving from Google Authenticator
Steps with images: Google Authenticator → Transfer accounts → Export → VanKey `+` → Scan QR (you can take a screenshot and then pick the image). Remind users to **compare a few codes with the old app before deleting it**, and to delete the QR screenshots afterwards (the migration link contains secrets).
Also cover the reverse direction: export from VanKey to Google Authenticator (QR in batches of 6 entries).

### 3. Backup, recovery, lost device
A public version of `docs/guide/recovery-sheet.md`: scenarios A–D, with a **button to download a printable PDF** (the blank template). Emphasise: losing both the password **and** the recovery code means losing the vault.

### 4. How VanKey protects data
Written for ordinary people first; technical details go in an extended section:
- Diagram: password → NFKC → Argon2id (auto-measured, standard 64 MiB × 3 passes) → vault key → XChaCha20-Poly1305 → `.vkv` file. The recovery code is derived with HKDF-SHA256.
- The server only receives: username, hash of the authentication key (derived by the client, PBKDF2 on the server), hashed refresh tokens, device name and last-used time, the encrypted vault file. It never sees the vault password.
- Biometrics: Android Keystore / Windows Hello in the TPM wraps the vault key; on iOS and macOS biometrics is only an app-level lock.
- **Plain talk:** the cryptography runs in pure Dart and **has not been independently reviewed**; the limits are in `docs/technical/threat-model.md` sections 3 and 5.
- Links to the specification `docs/technical/vault-format.md` and the threat model (on GitHub if the repo is public).

**Source:** `docs/technical/vault-format.md`, `docs/technical/threat-model.md`, `server/migrations/*.sql`.

### 5. What's new
Generated automatically from `docs/project/CHANGELOG.md` at build time (Astro reads the Markdown file), not copied by hand. Each version has an anchor (`/changelog/#1.0.0`) so the "New version available" button in the app links straight to it.

### 6. Download
- Android: APK; Windows: installer `vankey-<version>-windows-setup.exe` and a zip. Links to the latest GitHub Releases (repo `kivie9/VanKey`).
- **SHA-256 hash** of each file for verification (created by CI at release time; see the technical steps below).
- Fingerprint of the APK signing key (SHA-256 of the certificate) so users can compare it when installing.
- Explanation of the SmartScreen warning (the installer has no signing certificate yet) and of "install from unknown sources" on Android.
- Requirements: Android 8 (API 26) or newer, Windows 10/11 64-bit.

---

## Wave 2 (before going public)

### 7. Privacy policy (required)
Describe exactly what the code does, and promise nothing more. Sections:

| Section | Content (per current code) |
|---|---|
| Data on the device | Encrypted vault. The developer cannot access it |
| VanKey server (optional) | Username; hash of the authentication key; device name, creation time and last-used time; hashed refresh tokens; the encrypted vault file. The `attempts` table keeps **IP addresses** (IPv6 reduced to its prefix) and usernames with failure counts, to prevent password guessing. Rows not updated for more than 24 hours are deleted (`ATTEMPT_TTL` in `server/src/handler.ts`) |
| Where the server runs | Cloudflare Workers + D1. State that Cloudflare is a data processor, with a link to Cloudflare's policy |
| Google Drive (optional) | Only the `drive.appdata` permission (the app's hidden folder), no other files are read. The stored file is encrypted |
| HIBP | Only the first 5 characters of the SHA-1 hash of the password are sent to `api.pwnedpasswords.com`, and only when you press check |
| Update check | One request to `api.github.com`, only when you press the button |
| Not collected | Advertising, analytics, automatic crash reporting, tracking |
| Android permissions | Camera (QR scanning), notifications and alarms (reminders), biometrics |
| Retention and deletion | Deleting the account immediately deletes the server copy of the vault (already exists: `DELETE /account`). State any Cloudflare backups if they exist |
| Children | Not aimed at people under 13 |
| Contact | A dedicated email for VanKey (**needs to be created**; not a personal email) |
| Effective date, change history | Included |

**Before writing:** check whether the server logs requests (Workers Logs, Logpush), because those logs also contain IP addresses.

### 8. Terms of use
Short: the software is provided "as is"; users are responsible for keeping their password and recovery code; the developer cannot recover a vault; the free server may be stopped or limited (limited registration, invite codes); vaults on the server are at most about 1.5 MB; the server must not be used to store other things. Must match the licence chosen for the source code.

### 9. Delete account and data (required by Google Play)
Google Play requires a **web page** (not only inside the app) that explains how to delete an account:
- In the app: Settings → Data → Sync → account → Delete account (requires the password)
- No longer have the device: how to request deletion by email (needs a verification process confirming the account owner)
- What is deleted, what is kept, and for how long
- Note: data on Google Drive and on users' devices must be deleted by the user

### 10. Report a security vulnerability
A dedicated email, optional PGP key, response time commitment, scope (app, server, file format), and a request not to publish before a fix. Include the file `public/.well-known/security.txt` and `docs/SECURITY.md` with the same content.

### 11. Licences and credits
- VanKey's own licence (**not chosen yet**, see the questions below)
- Fonts in the app (Inter, Space Grotesk, JetBrains Mono, OFL) and on the site (Geist, OFL)
- Simple Icons (CC0) and a note: service logos are trademarks of their owners and are used only for recognition
- Main libraries: Flutter, cryptography, Three.js, GSAP, Astro
- The full list is in the app (About → Open-source licences)

---

## Related technical work

- [ ] Astro: add a content collection `src/content/docs/{vi,en}/*.md` for the pages above, a shared layout `Doc.astro` (side table of contents, last-updated date, an "edit on GitHub" link if the repo is public)
- [ ] Read `../docs/project/CHANGELOG.md` at build time to build the What's new page
- [ ] Search within the guide: Pagefind (static, no server needed) if there are more than 15 pages
- [ ] Release CI: add a step that creates `SHA256SUMS.txt` for the APK, installer and zip, and attaches it to the GitHub Release
- [ ] App: add a `siteUrl` constant in `app/lib/app/constants.dart`; the About screen gets links to Privacy, Terms, Security, What's new; the Support screen gets "View the full guide"; the server sign-up screen gets the line "Signing up means you agree to the Terms and the Privacy Policy"
- [ ] Every link from the app opens in the external browser via `url_launcher`, and only points to the site's domain
- [ ] Keep the FAQ in the app and on the site identical: write it once (for example a shared JSON file) or add a check to the release checklist
- [ ] Windows installer: change `AppUrl` in `app/installer/vankey.iss` from GitHub to the site once a domain exists

## Checklist before going public

- [ ] A dedicated contact email for VanKey
- [ ] Choose a licence, add `LICENSE` in the repo root
- [ ] Privacy and Delete account pages are live at fixed URLs (Play Console needs these URLs)
- [ ] Fill in the **Data safety** section in Play Console to match the Privacy page
- [ ] Microsoft Store (if published): privacy policy URL, description, screenshots
- [ ] Store screenshots and descriptions in vi/en (reuse the homepage text)
- [ ] Every page shows a last-updated date; legal pages keep a change history

## Open questions

- **Source licence:** GPL-3.0 (others who modify it must publish their code, like Bitwarden/Aegis), MIT/Apache-2.0 (more freedom), or keep it private and not open source
- **Public repo or not:** affects links to the specification and threat model, "edit on GitHub", and the update-check button (with a private repo, `api.github.com` does not return releases to strangers)
- **Who runs the public server:** if you open registration to others, you are the holder of their data and need full Privacy and Delete account pages; if only for personal use, you can state that "the server is only for invited people"
- **Domain:** https://vankey.onigix.com (decided)
