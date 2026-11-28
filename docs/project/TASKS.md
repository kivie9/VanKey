# VanKey — Detailed Task List

> Companion to [`PLAN.md`](PLAN.md). PLAN.md says **what to do and why**; this file says **which specific steps to take, in what order, and when each is done**.
> Mark `[x]` when done. Each finished task with logic should have a test before it is committed.

Legend: **(P)** = has a UI sample in the prototype · **(T)** = needs tests · **(⚠)** = risk, must be verified on a real device.

---

## General rules

- [ ] Each milestone ends with a tagged commit (`m0`, `m1`, ...).
- [ ] Never commit: keys, tokens, `google-services`, keystores, `.env` files, real data. Add them to `.gitignore` from the start.
- [ ] `flutter analyze` is clean and `flutter test` passes before every commit.
- [ ] Never log passwords, keys, 2FA codes or passphrases at any log level.
- [ ] UI strings go through ARB files (vi, en), **never hard-coded** in the code.
- [ ] Settled technical decisions are recorded in `docs/technical/decisions.md` (one line per decision: what, why, date).

---

## M0 — Setup and verification (0.5–1 week)

### Environment
- [x] Install the Flutter SDK: `git clone https://github.com/flutter/flutter.git -b stable E:\code\libs\flutter`
- [x] Add `E:\code\libs\flutter\bin` to PATH, open a new terminal, run `flutter doctor`
- [x] Settle the **app name and package id**: VanKey, `com.vankey.vankey` (org `com.vankey` + project name `vankey`)
- [x] `git init` in `E:\code\project\keymanager` (branch `main`), `.gitignore` in place
- [x] Create the project: `flutter create --org com.vankey --project-name vankey --platforms=windows,android app`
- [x] Set up lint (`analysis_options.yaml`, enable `flutter_lints` and stricter rules: `avoid_print`, `prefer_final_locals`...)
- [x] Build the folder tree `lib/core/{crypto,vault,totp,import_export,sync,notify,platform}`, `lib/features`, `lib/l10n`
- [ ] First commit

### Crypto spike (⚠ decides the whole project)
- [x] Add `cryptography` 2.9.0 (pure Dart). **`sodium_libs` not tried yet** because it needs a native Windows build (needs Visual Studio); see `docs/technical/spike-m0.md`
- [x] Write the trial program: `app/test/spike/crypto_spike_test.dart` (7 tests, including the official XChaCha20-Poly1305 test vector) and `argon2_bench.dart`
- [x] Runs with `flutter test` (pure Dart, no native library needed)
- [x] Measured Argon2id with 4 parameter sets on **Windows** (AOT): 64 MiB x3 passes = 876 ms
- [ ] If an Android phone and Android SDK are available: measure on a real **Android** device (**SDK installed 2026-11-19**; still missing: a phone connected by USB and a measurement screen on the phone)
- [ ] **Acceptance threshold:** unlock ≤ ~1 second on a PC and ≤ ~1.5 seconds on a mid-range phone; Argon2id memory from 64 MiB upwards
- [x] Took the pure Dart route (`cryptography`) and **cross-checked byte-for-byte with an independent libsodium: matches**
- [x] Recorded the results in `docs/technical/spike-m0.md` and `docs/technical/decisions.md` (D4)

**Done when:** `flutter doctor` reports no errors for Windows; the spike runs; the crypto library is chosen; there is an `m0` commit.

---

## M1 — Pure Dart core (1–2 weeks)

> Everything lives in `lib/core/`, **does not import the Flutter UI**. Run tests with `flutter test`.

### 1.1 Documents (written before the encryption code)
- [x] `docs/technical/vault-format.md`: byte layout of the file, header, key slots, KDF parameters, inner JSON, version rules. **Draft v0.2, matches the code; not yet reviewed by outsiders**
- [ ] `docs/technical/vault-format.md`: **test vectors.** Primitive vectors and the file test suite exist; **no fixed `.vkv` file yet** for TypeScript to cross-read (needed when the extension/server is built)
- [x] `docs/technical/threat-model.md`: draft, to be reviewed after M3

### 1.2 Basic cryptography (`core/crypto`)
- [x] `Csprng` (`Random.secure()`), with a `RandomSource` interface so tests can use a fixed source; `uuidV4`
- [x] `Kdf.argon2id` (checks parameter bounds when reading) and `Kdf.hkdfSha256`
- [x] `Aead.seal / open` (XChaCha20-Poly1305) with AAD
- [ ] `SecureBytes`: **no dedicated class yet**; currently there is `wipe` in `RecoveryKey` and `VaultSession.close()` (best effort, Dart has a garbage collector)
- [x] (T) Official test vectors, wrong key/nonce/AAD, altered ciphertext/tag → fail correctly

### 1.3 Key slots (`core/crypto/keyslot`)
- [x] Create a random 32-byte vault key
- [x] **Passphrase** slot: Argon2id → KEK → wrap the vault key (with NFKC normalisation)
- [x] **Recovery** slot: 24-character recovery key (120 bits), KEK by HKDF-SHA256
- [ ] **Device** slot (key in the OS secure storage): done in M3, not in the sync file
- [x] Open the vault with a passphrase or recovery key; **change passphrase** = re-wrap the vault key; regenerate the recovery key; **rotate the vault key**. (No API yet to add/remove arbitrary slots.)
- [x] (T) Open with each slot type, change the passphrase then open with new/old, regenerate the recovery key and check the old one is invalid

### 1.4 Data model (`core/vault`)
- [x] `Item`, `Field`, `TotpParams`, `PwHistoryEntry`, `Reminder`, `Tombstone`, `VaultData`. **Template fields have a stable `key`** (for label translation), user-added fields have a `label`
- [x] 7 item types and field templates (`ItemTemplates`)
- [x] JSON serialisation with `schema`, keeps unknown fields and unknown item types. (No migration yet because only schema 1 exists.)
- [x] `VaultData`: add/edit (`upsert`), trash, restore, permanent delete (tombstone), **automatically empties trash items ≥ 30 days old**
- [x] `Item.subtitle`: only takes **non-secret** fields
- [x] Open/save `.vkv`: new nonce on each write; **atomic write** (`VaultStorage`: temp file, rename, keep `.bak`)
- [x] (T) Round trip, corrupt/truncated/byte-flipped files, unknown version, bad KDF parameters, unknown slots

### 1.5 Merge and conflicts (`core/vault/merge`)
- [x] **HLC** hybrid logical clock
- [x] **Three-way merge** `mergeVaults(local, remote, base)` (the `parentHlc` approach was dropped because it reported conflicts incorrectly; see `docs/technical/vault-format.md` section 7)
- [x] Conflict detection, `resolveConflict` creates a new version
- [x] (T) Property test with 500 scenarios: commutative, convergent, no item loss. **Found and fixed 1 bug** (two tombstones with different HLC). The "associative" property is not tested separately yet

### 1.6 TOTP (`core/totp`)
- [x] Base32 (tolerates spaces, hyphens, lowercase, padding)
- [x] `Otp.hotp / totpAt / code`: SHA1/256/512, 6 to 8 digits, any period
- [x] `OtpAuth.parse / toUri`; rejects bad links. **Found and fixed 1 bug** (issuer containing `:`)
- [x] `Migration.parseUri / encodeUri`: hand-written protobuf, supports batches of several codes; accepts "+" as a space and URL-safe base64
- [x] `Otp.secondsRemaining / fractionRemaining / grouped`
- [x] (T) **RFC 6238 vectors** (all 3 algorithms, 6 time points) and **RFC 4226**; public migration samples; 1,000 random inputs scanned without going out of bounds

### 1.7 Import/export (`core/import_export`)
- [x] `ImportResult` (with warnings) and `markDuplicates`
- [x] Importers: Google Authenticator (migration), multi-line `otpauth://` links, Aegis, 2FAS, Bitwarden (JSON, CSV), 1Password (CSV), KeePass (CSV), Chrome/Edge (CSV), automatic format detection
- [x] Exporters: `otpauth://` links, **Google Authenticator links** (batches of 10 entries), CSV. (The encrypted backup is the vault file itself.)
- [ ] (T) **Real samples from each source: NOT YET.** Tests use **data built from the formats I know** (Bitwarden, Aegis, 2FAS, 1Password, KeePass, Chrome), not checked against real export files. **Must try with your own real export files** before trusting. Done: empty files, wrong formats, special characters, 1,500 garbage entries do not crash it

### 1.8 Pure logic carried over from the prototype
- [x] `findDuplicates` and `mergeDuplicateGroup` (keep the newest, carry over 2FA/group/favourite, move other passwords to history)
- [x] `PasswordStrength` (entropy with penalties for sequences, repeats, common passwords; **only an estimate**)
- [x] `healthReport` (**self-defined** scoring formula)
- [x] `PasswordGenerator`: CSPRNG, no modulo bias, guarantees each character class, excludes confusing characters; uniform distribution checked
- [x] Expiry reminders: `passwordReminder`, `expiryDate` (cards, API keys), `pendingAlerts` (snooze), `upcomingNotices` (for the M6 scheduler), month addition by calendar
- [x] `Hibp.split / countFromResponse / check` (only the first 5 characters of the hash leave the function)
- [x] (T) Tests for each function, including edge cases. Added: search ignoring Vietnamese diacritics, **never searches secret fields**

- [ ] Not done (import): **1Password 1pux** and **KeePass XML**
- [ ] Not done: `SecureBytes` class, API to add/remove arbitrary slots, old-schema migration

**M1 result (2026-11-19):** 28 code files in `lib/core/` (~3,200 lines), 11 test files (~2,150 lines), **179 tests pass**, `flutter analyze` reports no issues. Property tests and garbage-input tests **found 3 real bugs** (an unknown slot reported as corrupt, two tombstones with different HLC, an issuer containing `:`), all fixed. Known limits: cryptography runs in pure Dart (not measured on Android); the file format **has not been reviewed by outsiders**; the import readers **have not been tested with real export files**.

**Done when:** all tests pass; the RFC 6238 and file format test vectors pass; `docs/technical/vault-format.md` matches the code; there is an `m1` commit.

---

## M2 — Offline app (3–4 weeks)

### 2.1 UI foundation
- [ ] Colour/text/spacing token system taken from the prototype (light, black dark, 6 accent colours, density)
- [ ] `ThemeController`: system/light/dark, accent colour, density; stored locally
- [ ] Localisation infrastructure: ARB vi/en, language switch takes effect immediately without restart
- [ ] Navigation: **Windows** side bar + multi-column grid; **Android** bottom bar with 3 tabs (Vault, 2FA, Settings); full-screen pages with a Back button and a stack that returns to the correct parent menu
- [ ] Adaptive layout: 1 column (phone) → 2, 3, 4 columns (wide window)
- [ ] Shared components: settings row, settings group, switch, segmented button, letter avatar (uniform muted tone), badge, toast, dialog, bottom sheet

### 2.2 Data and state
- [ ] `VaultRepository` (Riverpod): keeps the vault in memory, saves automatically after edits (merged within ~500 ms)
- [ ] A single TOTP `Ticker` for the whole app (every second), no timer per row
- [ ] State for filter/grouping/search/collapsed groups

### 2.3 Screens (P)
- [ ] **Vault:** list grouped by Group/Type/None, collapsible group headers, favourites at the top, 2FA codes shown with countdown (tap to copy), top bar: filter icon (choose group), search icon (opens search box)
- [ ] **Round add button:** rotates into ×, expands into 4 buttons (Enter manually, Scan QR, Import from file, Quick view)
- [ ] **Item details:** Windows = dialog; Android = page; show/hide, copy, favourite, change group, 2FA block, password history, change reminder, move to trash
- [ ] **Add item (full-screen):** choose type → fields change by type, add custom fields, Generate password button, new group, Cancel/Save bar fixed at the bottom
- [ ] **2FA tab:** thin rows, copy the whole row, grouping
- [ ] **Quick 2FA view:** large input, Check button below, shows code (not saved), Save to vault button
- [ ] **Password generator:** password coloured by character class, strength meter, length slider + −/+ buttons, character class choices
- [ ] **Trash**, **Duplicate items**, **Password history** (show/hide, copy, reuse)
- [ ] **Settings:** list of 7 menus (Account, Data, Security, Theme, General, Support, About) and sub-pages; sections with no real function show a "coming soon" state
- [ ] **Support / About:** FAQ, feedback, version, open-source licence (using `showLicensePage`)
- [ ] **First launch (onboarding):** create vault, choose **offline** or **with account**, show and require confirmation that the recovery key was saved
- [ ] Empty, error and loading states for every list

### 2.4 Quality
- [ ] Keyboard support, screen readers (labels for icon-only buttons), tap targets ≥ 44 px
- [ ] Large system text does not break the layout
- [ ] Performance: a list of 500 items scrolls smoothly, cold start < 2 seconds
- [ ] Widget tests for the add-item, trash and group-change flows; golden tests for a few main screens (light and dark)

**Done when:** usable daily on Windows and Android without network; every action in the prototype has a real implementation (except real sync/QR/notifications); there is an `m2` commit.

---

## M3 — Device security (1 week)

- [ ] Real `SecureStore`: Android Keystore, Windows Credential Manager (via `flutter_secure_storage`)
- [ ] App lock: optional master password (set, change, disable with verification), lock screen
- [ ] Biometrics (`local_auth`): the device slot requires biometric verification to open (⚠ test on a real device)
- [ ] Auto-lock: after N minutes of inactivity, when minimised/switching apps; erase keys from RAM on lock (`wipe`)
- [ ] **Slow down after repeated wrong passphrases** (increasing waiting time)
- [ ] Clipboard: cleared after 30 seconds; Android marks content as **sensitive** (a small native channel in Kotlin)
- [ ] Android `FLAG_SECURE` (blocks screenshots, hides content in the recent apps list); Windows: hide content when focus is lost if needed
- [ ] Real **Security check** screen (uses `healthReport`), HIBP breach check with k-anonymity (⚠ only the first 5 characters are sent)
- [ ] Change master password, change vault passphrase, **view/create a new recovery code** (re-authenticate before showing)
- [ ] Log review: nowhere prints sensitive data; release builds turn off detailed logs
- [ ] Manual checklist on a real device (lock, biometrics, minimising the app, screen rotation, screenshots, clipboard)

**Done when:** the security checklist passes on a real device; there is an `m3` commit.

---

## M4 — Google Drive sync (1–2 weeks)

### Preparation (by hand, once)
- [ ] Create a Google Cloud project, enable the **Drive API**
- [ ] OAuth consent screen: add the `drive.appdata` scope, **switch to "In production"** (if it stays on Testing, tokens expire after 7 days)
- [ ] Create 2 OAuth clients: **Desktop app** and **Android** (needs the SHA-1 of the debug and release keystores)

### Code
- [ ] `SyncProvider` interface and `FakeSyncProvider` (in memory, for tests)
- [ ] `DriveSync`: find/download/upload `vault.vkv` in `appDataFolder`, check version on upload
- [ ] **Windows** sign-in: open the browser, OAuth PKCE via `127.0.0.1:<port>`, store the refresh token in `SecureStore`
- [ ] **Android** sign-in: `google_sign_in`
- [ ] `SyncService`: sync when the app opens, after each edit (merged), manual sync button; download → decrypt → merge → encrypt → upload; retry on version mismatch
- [ ] Offline handling, network failure mid-sync, retry with backoff
- [ ] **Conflict screen:** shows both versions of an item to choose from
- [ ] Sync status chip (syncing, last time, error), clear error messages
- [ ] New device: Google sign-in → enter passphrase or recovery key → decrypt the vault
- [ ] (T) Tests with `FakeSyncProvider`: two devices editing at once, delete then edit, network loss mid-sync
- [ ] Manual test: edit on Windows, phone receives it and vice versa; both machines edit at the same time

**Done when:** two machines sync correctly and no data is lost on simultaneous edits; there is an `m4` commit.

---

## M5 — Cloudflare and accounts (2 weeks)

### Server (`server/`)
- [ ] Worker skeleton (TypeScript + Hono), `wrangler.toml`, dev/prod environments
- [ ] D1: tables `users`, `devices` (incl. refresh token hash, expiry, device name, last seen), `vaults` (user_id, version, blob, updated at)
- [ ] D1 migrations
- [ ] `POST /auth/google` (verifies the ID token with JWKS, checks `aud` and `exp`), `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`
- [ ] `GET /devices`, `DELETE /devices/:id` (revoke each device)
- [ ] `GET /vault`, `PUT /vault` with `If-Match` (409 on version mismatch, returns the current version)
- [ ] **Allowed-email list** (first release): reject registration outside the list
- [ ] Password hashing: the client hashes with Argon2id → the server hashes again (PBKDF2 or scrypt WASM)
- [ ] Rate limits on sign-in, temporary lock after repeated failures, limit on request body size
- [ ] Secrets configured via `wrangler secret`; HTTPS; (optional) custom domain
- [ ] (T) Tests with vitest + miniflare: sign-in, refresh, revocation, concurrent overwrite

### Client
- [ ] `CloudflareSync` (same `SyncProvider` interface)
- [ ] Sign-in/register screen (Google, email), set the vault passphrase, **must save the recovery key**, open the vault on a new device
- [ ] Account screen: signed-in devices (remote removal), sign out, change sign-in password, change vault passphrase
- [ ] Choose the sync location: Cloudflare or Drive (or switch)
- [ ] Turn an offline vault into an account vault (add recovery and passphrase key slots)

**Done when:** sync works through the server; revoking a device removes its access; there is an `m5` commit.

---

## M6 — Import/export, QR, reminders (1–2 weeks)

- [ ] **QR scanning (Android):** `mobile_scanner`, asks for camera permission, reads both normal QR codes and migration QR codes
- [ ] **QR scanning (Windows):** pick an image / paste an image (`zxing2`), (optional) capture part of the screen
- [ ] Import flow (P): choose source → choose file → preview with duplicate flags → choose target group → import
- [ ] Export flow (P): scope, format, warning about unencrypted output, passphrase required
- [ ] Real **Duplicate items** screen (merge, move to trash)
- [ ] **Reminder service:** `ReminderScheduler` computes the full schedule, cancels and reschedules when data/settings change and after each sync
- [ ] Android: `flutter_local_notifications`, notification permission (13+), exact alarm permission (12+), **reschedule after device restart**, notification channel (⚠ try Xiaomi/Samsung if available)
- [ ] Windows: scheduled notifications (MSIX) or background tray app that checks daily (choose the approach in section 13 of PLAN.md)
- [ ] Notification content **contains no secrets** (only service name and due date)
- [ ] Reminders screen (bell, overdue/expiring soon, Change password, Remind again after 7 days, Dismiss)
- [ ] Real-world test: import all your own Google Authenticator data and compare codes with the old app

**Done when:** all Google Authenticator entries are moved to the new app and the codes match; scheduled notifications show correctly on a real device; there is an `m6` commit.

---

## M7 — Packaging and release (1 week)

### Windows
- [ ] App icon, display name, version information
- [ ] **MSIX** packaging (`msix` package), signing certificate (self-signed for personal use, or buy a certificate for wide release)
- [ ] Install and uninstall on a **clean** Windows machine

### Android
- [ ] Create a **release keystore** and **back it up somewhere safe** (losing it means you cannot update the app)
- [ ] Signing config, `flutter build apk --release` / `appbundle`, review permissions in the manifest (keep only the needed ones: camera, notifications, alarms)
- [ ] Install from the APK on a real phone

### Quality and documents
- [ ] Test matrix: Windows 10/11, lowest and latest Android (API 26 and newest), small/large screens, light/dark, vi/en
- [ ] **Recovery drill:** delete the app, reinstall, sign in, open the vault with the passphrase; then with the recovery key
- [ ] **Lost-device drill:** remove the device remotely, change the passphrase
- [ ] Final security review (checklist in section 8 of PLAN.md); ask a qualified person to review the format specification and cryptographic code
- [ ] `README.md` (how to build, structure), short user guide (moving from Google Authenticator, saving the recovery key, backups)
- [ ] Set version `1.0.0`, tag `v1.0.0`

**Done when:** the installer runs on a clean machine and a real phone; there is a `v1.0.0` commit/tag.

---

## After the first release (not scheduled)

- [ ] Android Autofill Service (Kotlin)
- [ ] Browser extension (TypeScript, shares format test vectors)
- [ ] Global hotkey + small window on Windows
- [ ] Android widget showing 2FA codes
- [ ] Server push (new-device warnings, background sync)
- [ ] Encrypted file attachments
- [ ] Multi-user mode, sharing, emergency access, passkeys

---

## Dependencies between milestones

```
M0 ──> M1 ──> M2 ──> M3 ──┬──> M4 ──> M5
                          └──> M6        ──> M7
```
- M1 must be done before M2 (the UI depends on the core).
- M4 and M6 can run in parallel after M3, but M6 (reminders) should wait for M4 so the rescheduling after sync is known.
- M5 needs M4 (shares `SyncService` and the conflict screen).
