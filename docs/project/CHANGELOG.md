# Changelog

Entries are listed by version, newest first. Version numbers use the form `MAJOR.MINOR.PATCH`; a tag such as `v1.2.3` creates a GitHub Release (see `.github/workflows/build.yml`).
When releasing: change the "Unreleased" heading to the version number and date, and copy that section into the GitHub Release notes.

Groups: **Added**, **Changed**, **Fixed**, **Security**, **Removed**.

## Unreleased

No release has been made yet (no tag). The sections below summarise what exists as of 2026-11-27.

### Added
- When creating a server account, agreeing to the Terms and the Privacy Policy is required. The server records the terms version and the time of agreement (migration 0007).
- Legal pages: Privacy, Terms of Use, Delete account and data, Security and vulnerability reporting (vi and en, in `site/`). The homepage footer links to these pages.
- The About screen has a section "When data leaves the device" and links to the legal pages when `SITE_URL` is set at build time.
- `docs/SECURITY.md` on how to report vulnerabilities, `docs/guide/user-guide.md` (user guide), and `docs/operations/operations-notes.md` (includes a procedure for opening registration).
- `.vkv` vault file: Argon2id (parameters self-measured when creating a vault), XChaCha20-Poly1305, recovery code, 3-way merge during sync.
- Login, note, card, custom field, password history (last 10), trash, groups, search ignoring diacritics item types.
- 2FA: TOTP with countdown, HOTP, Steam Guard; QR scanning by camera and from images; QR display for each item; export to Google Authenticator.
- Import from Google Authenticator, Aegis, 2FAS, Bitwarden, KeePass XML, 1Password `.1pux`, CSV, `otpauth` links.
- Export CSV, links, encrypted backup, export by group.
- Security checks: weak passwords, reused passwords, breaches via HIBP (only the first 5 characters of the hash are sent).
- Reminders and local notifications.
- Sync: VanKey server (Cloudflare Worker + D1, sign-in with a username), Google Drive (the app's hidden folder), a folder on the computer.
- Server accounts: limited registration, optional invite code, device list and removal, password change, account deletion.
- Light/dark/black themes, 6 accent colours, Vietnamese and English, desktop layout, logos for about 85 services.
- Windows installer (Inno Setup) and zip; CI builds Android, Windows, iOS.
- Check for updates (manual), Support and About screens, open-source licence page.

### Security
- Auto-lock after 5 minutes by default for new vaults; slower after wrong attempts; screenshots blocked (Android).
- Fingerprint unlock tied to the Android Keystore; only the wrapped vault key is stored.
- Windows: copied secrets are kept out of the Win+V history and the cloud clipboard.
- 2FA codes, passwords and notes are hidden by default and re-hidden after 30 seconds.
- Server: accounts locked after repeated failures; limits per IP (rejects if the IP cannot be determined); detection of reused refresh tokens.
- A strong passphrase is required when creating or changing the vault password.

### In progress
- Windows Hello unlock tied to a key in the TPM.

### Removed
- Vault mode without a password.
- Service suggestion screen.
