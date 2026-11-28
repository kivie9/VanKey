**[Tiếng Việt](PLAN.md)** · English

# VanKey — Implementation Plan

> Updated: 2026-11-19 · Status: **UI design locked (prototype), no code yet**

A password, API key, secure note and **2FA (TOTP) code** manager that runs on **Windows** and **Android**, syncs between devices, and uses end-to-end encryption. It replaces Google Authenticator (which does not sync between devices).

- UI prototype (interactive): <https://claude.ai/artifact/Fv4VszCjKj7kUfG4cdwRdf> (private, only the owner can open it)
- Copy stored in the project: [`docs/prototype/vankey-prototype.html`](docs/prototype/vankey-prototype.html) — open in a browser, no server needed

---

## 1. Goals and scope

### Goals
1. One place for every account, key, sensitive note and **self-generated 2FA code**, synced across computer and phone.
2. **Zero-knowledge:** the storage location (Google Drive or Cloudflare server) can never read the content.
3. Fully usable offline. Sync is optional.
4. Can move all data from Google Authenticator, Bitwarden, 1Password, KeePass, Chrome.

### Not in the first release (see section 12)
Autofill of passwords (Android Autofill), browser extension, server push notifications, file attachments, sharing between people, passkeys, emergency access.

### Design principles
- **Do not invent cryptography.** Only use algorithms and libraries that are widely reviewed.
- **One codebase** (Flutter) for both platforms; platform-specific parts are hidden behind an interface.
- **The data format is fixed early and versioned**, because the extension and server must read the same format later.
- Minimal UI, little explanatory text, safe defaults.

---

## 2. Technology

| Part | Choice | Notes |
|---|---|---|
| App | **Flutter** (Dart), stable channel | Windows + Android from one codebase |
| State | `flutter_riverpod` | |
| Cryptography | **libsodium** via `sodium_libs` (Argon2id, XChaCha20-Poly1305) | **To verify at M0**: works on both Windows and Android, Argon2id speed acceptable. Fallback: `cryptography` + `pointycastle` |
| TOTP | Written in-house (about 50 lines) on `crypto` (HMAC SHA1/256/512) | RFC 6238, checked with the official test vectors |
| Google Authenticator import | `protobuf` decoding `otpauth-migration://` | |
| QR scanning | Android: `mobile_scanner`. Windows: `zxing2` (reads images) | |
| Device key storage | `flutter_secure_storage` (Android Keystore, Windows Credential Manager) | |
| Biometrics | `local_auth` (fingerprint, face, Windows Hello) | |
| Local notifications | `flutter_local_notifications` + a separate part for Windows | See section 9 |
| Localisation | `flutter_localizations` + ARB files (**vi** default, **en**) | |
| Windows window | `window_manager`, `tray_manager` | Runs in the background in the system tray |
| Drive sync | `googleapis` (Drive v3), `googleapis_auth` (Windows), `google_sign_in` (Android) | Only the `drive.appdata` scope |
| Server (optional) | **Cloudflare Worker** (TypeScript + Hono), **D1** | Stores only encrypted blobs |
| Testing | `flutter_test`, RFC test vectors, property tests for merge | |

---

## 3. Architecture

```
keymanager/
├─ PLAN.md
├─ docs/
│  ├─ prototype/vankey-prototype.html     # UI design (exists)
│  ├─ vault-format.md                         # file format specification (written in M1)
│  └─ threat-model.md                         # threat model (written in M1)
├─ app/                                       # Flutter
│  ├─ lib/
│  │  ├─ core/
│  │  │  ├─ crypto/        # KDF, AEAD, key slots, secure memory
│  │  │  ├─ vault/         # data model, serialisation, merge
│  │  │  ├─ totp/          # code generation, otpauth parsing, protobuf migration
│  │  │  ├─ import_export/ # Bitwarden, 1Password, KeePass, CSV, otpauth
│  │  │  ├─ sync/          # SyncProvider, DriveSync, CloudflareSync, SyncService
│  │  │  ├─ notify/        # reminder schedule calculation, rescheduling
│  │  │  └─ platform/      # per-platform interfaces
│  │  ├─ features/         # vault, totp, quick_view, generator, settings, ...
│  │  └─ l10n/             # vi, en
│  └─ test/
├─ server/                                    # Cloudflare Worker (M5)
└─ extension/                                 # later
```

**Separation:** `core/` is pure Dart, **with no dependency on Flutter UI**, so it can be tested with `dart test` without a device. `features/` only calls into `core/`.

---

## 4. Security model and data format

### 4.1 Key hierarchy (key slots)
```
vault key (32 random bytes)  ──encrypts──>  all vault data
       ▲
       │ "wrapped" by one or more key slots:
       ├─ passphrase  : Argon2id(vault passphrase, salt, parameters) → KEK
       ├─ recovery    : randomly generated recovery key → KEK
       └─ device      : random key stored in the OS secure storage (fast unlock)
```
- **Changing the passphrase = re-wrapping the vault key**, not re-encrypting the whole vault.
- **Offline mode, no account:** only the `device` slot may be used. Locking the app with a password is optional.
- **Sync mode:** the `passphrase` and `recovery` slots are required. A new device must enter the passphrase or recovery key once.
- The passphrase is **never** sent anywhere. Account sign-in (Google, email) and the vault passphrase are separate things.

### 4.2 `vault.vkv` file
```
magic "VKV1" | version | keyslots[] | nonce(24) | ciphertext(JSON, XChaCha20-Poly1305)
```
- KDF: Argon2id, parameters stored in each key slot so they can be upgraded later.
- A new nonce for every write. Files are written with "write to a temporary file, then rename".
- The full specification is written in `docs/vault-format.md` **before** the encryption code is written, together with test vectors shared between Dart and TypeScript.

### 4.3 Data inside
```
Item {
  id (uuid), type: login|totp|key|crypto|card|wifi|note,
  title, fields[ {label, value, secret, kind} ],
  totp? { secret, algo, digits, period },
  group, favorite,
  pwHistory[ {value, changedAt} ],
  reminder? { months, noticeDays, lastChangedAt },
  createdAt, updatedAt, deletedAt?   // deletedAt != null  => in the trash
}
```
- Interface settings (theme, language, density) are stored **locally, not synced**.
- Secondary lines in a list **only use non-secret fields** (lesson from the prototype: recovery phrases must never be shown outside).

### 4.4 Threat model (summary, details in `docs/threat-model.md`)
| Protected against | **Not** protected against |
|---|---|
| Data leaks from Drive, the Cloudflare server, the network | Devices infected with malware or keyloggers |
| Lost phone (when the app is locked and the screen is locked) | Weak passphrases being guessed |
| Server compromise | Users losing both the passphrase and the recovery key |

Rules: no logging of sensitive data, no analytics/telemetry, keys erased from RAM when the app locks (best effort, Dart has a GC so it is not absolute), screenshots blocked (Android `FLAG_SECURE`), clipboard cleared after 30 seconds, clipboard marked sensitive on Android.

---

## 5. Sync

Common interface:
```dart
abstract class SyncProvider {
  Future<RemoteVault?> download();                       // returns blob + version
  Future<void> upload(Uint8List blob, {required String ifVersion});
}
```
- **Per-item merge:** merged by `id`, the version with the newer `updatedAt` wins. Deleted items are kept so the deletion can spread (`deletedAt`).
- Use a **hybrid logical clock (HLC)** instead of plain device time to avoid clock skew between devices. Two devices editing the same item from the same base → show a **conflict** for the user to choose (never silently overwrite).
- Upload uses a version check; on failure, download again, merge, and upload again.
- Sync happens: when the app opens, after each edit (with a short merge delay), and on the manual sync button.

### 5.1 Google Drive (`DriveSync`)
- Hidden `appDataFolder`, scope `drive.appdata` (not sensitive, so Google verification of the app is not needed).
- Windows: open the browser, OAuth type **Desktop app**, receive the code via `http://127.0.0.1:<port>`. Android: `google_sign_in`.
- **The OAuth consent screen must be set to "In production"**; if it stays on "Testing", refresh tokens expire after 7 days.

### 5.2 Cloudflare (`CloudflareSync`, M5)
- `GET /vault` → `{version, blob}`; `PUT /vault` with `If-Match`, returns 409 when the version does not match.
- Auth: short-lived access token + refresh token (stored as a hash in D1, revocable per device).
- Sign-in: **Google** (verifies the ID token with JWKS), and email + password (hashed on the client with Argon2id, then the server hashes again). Consider **Better Auth** instead of writing our own.
- First release: **only emails on the owner's list are allowed**; no email verification, no password reset, no free sign-up.
- Rate limits on sign-in, limit on body size, HTTPS required.

---

## 6. Feature list (matches the prototype)

**Vault**
- 7 item types: Login, 2FA only, API key, Crypto wallet, Card, Wi-Fi, Note. Each type has its own field template, plus custom fields and 2FA backup codes.
- Group by Group / Type / None; filter by group; favourites; search (never searches secret fields).
- Show/hide, one-tap copy; 2FA codes shown directly in the list, tap to copy.
- 30-day trash, password history, password change.

**2FA**
- List of codes with countdown, quick copy; **Quick view** using the key (not saved).
- QR scanning (Android camera, Windows reads images), pasting `otpauth://` links.
- Supports SHA1/256/512, 6 and 8 digits, 30 and 60 second periods.

**Data**
- Import: Google Authenticator (account export QR), Aegis/2FAS, Bitwarden, 1Password, KeePass, Chrome/Edge (CSV), multiple `otpauth://` links. Duplicate warnings, preview, choose target group.
- Export: encrypted backup, `otpauth://` links, CSV (with a warning; requires the passphrase).
- Find duplicate items (same 2FA code, same name + account, shared password), merge.

**Security**
- Optional app lock (master password, biometrics, auto-lock, lock when minimised).
- Security check: weak passwords, shared passwords, 2FA not enabled, leaks (checked against HaveIBeenPwned using k-anonymity, only the first 5 characters of the hash are sent).
- Recovery code (viewable after authentication, creating a new one requires confirmation), change vault passphrase, change sign-in password.

**Local notifications** — see section 9.

**Accounts and sync** — Google/email sign-in, device list (remote removal), choose Cloudflare or Drive, manual sync.

**Interface / general** — theme (system, light, dark), accent colour, list density; language vi/en; password generator (with strength meter); Support, About.

---

## 7. Roadmap (milestones)

Rough estimate for one person, not counting real-device testing.

| # | Milestone | Content | Done when | Size |
|---|---|---|---|---|
| **M0** | Setup | Install Flutter, create the project, **crypto spike** (Argon2id + XChaCha20 running on Windows and Android, measure time) | `flutter doctor` clean; spike runs on both platforms | 0.5–1 week |
| **M1** | **Core (pure Dart)** | Format specification, key slots, encryption/decryption, TOTP, `otpauth`/migration, merge, import parsers | All tests pass, including RFC 6238 test vectors and file format test vectors | 1–2 weeks |
| **M2** | Offline app | UI following the prototype: vault, details, type forms, 2FA, quick view, password generator, groups, trash, history, settings (theme, language) | Usable daily on Windows and Android without network | 3–4 weeks |
| **M3** | Device security | App lock, biometrics, auto-lock, clipboard clearing, screenshot blocking, security check | Security checklist passes on real devices | 1 week |
| **M4** | Drive sync | `DriveSync`, Google sign-in on both platforms, `SyncService`, conflict handling | Edit on computer, phone receives it; two devices editing at the same time lose no data | 1–2 weeks |
| **M5** | Cloudflare + accounts | Worker, D1, auth, device list, `CloudflareSync` | Sync through the server; device revocation works | 2 weeks |
| **M6** | Import/export, QR, reminders | QR scanning, import from all sources, export, duplicate search, expiry notifications | Successfully move all data from Google Authenticator on a real device | 1–2 weeks |
| **M7** | Packaging and release | MSIX for Windows, signed APK for Android, documentation, security review | Installer works on a clean machine | 1 week |

**Detailed task list for each milestone** (step by step, with done criteria): [`docs/TASKS.md`](docs/TASKS.md).

**Intentional order:** M1 (encryption core) comes **before the UI**, because mistakes there affect everything. M1 can start as soon as the Flutter SDK is installed; Visual Studio and Android are not needed yet.

---

## 8. Testing

- **Cryptography:** known test vectors for Argon2id and XChaCha20-Poly1305; corrupt files, wrong keys, wrong nonces must **fail cleanly**, never crash.
- **TOTP:** RFC 6238 test vectors (SHA1, SHA256, SHA512 at times 59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000). Tests for the 30-second step boundary.
- **Merge:** property tests (commutative, associative, idempotent), scenarios where two devices edit/delete at the same time.
- **Import:** real samples exported from each source (sensitive data removed).
- **Sync:** an in-memory `FakeSyncProvider` to test the flow without a network.
- **Manual on real devices:** QR scanning, biometrics, scheduled notifications, device restart, time zone change, network loss mid-sync.
- **Before release:** have a qualified expert review the format specification and the cryptographic parts.

---

## 9. Expiry reminders

Run **locally**, with no server needed. The app calculates the dates and asks the operating system to schedule them.

- Password expiry = last change date + number of months; warn N days in advance. Cards and API keys read from the expiry field.
- **Reschedule** whenever data or settings change, and after syncing down.
- **Android:** `AlarmManager`/WorkManager; request notification permission (Android 13+) and exact alarm permission (12+); **reschedule after the device restarts**; some manufacturers (Xiaomi, Oppo, Samsung) kill background apps aggressively, so notifications may be late.
- **Windows:** Windows scheduled notifications keep working when the app is closed only if packaged as **MSIX**; Flutter has no built-in scheduling for this, so a separate bridge must be written. Simpler option: the app runs in the system tray in the background and checks once a day.
- **Notification content contains no secrets:** only the service name and the due date.
- **Server push** (new-device sign-in warnings, background sync): later, only if Cloudflare sync is used. Server-less alternative: Android periodically checks in the background (a few minutes late).

---

## 10. Environment setup

The machine currently has: Git, Node, Java. **Not yet installed:** Flutter, Visual Studio, Android SDK.

**Step 1 — Flutter SDK only** (enough for M0, M1 and running tests):
```powershell
git clone https://github.com/flutter/flutter.git -b stable E:\code\libs\flutter
# add E:\code\libs\flutter\bin to PATH, open a new terminal
flutter doctor
```
**Step 2 — when working on the Windows UI (M2):** Visual Studio 2022 Community, tick **Desktop development with C++**.

**Step 3 — when working on Android (M2 onward):** Android Studio (with SDK), and ideally **a real Android phone** with USB debugging on. QR scanning, biometrics and scheduled notifications cannot be reliably tested on an emulator.

**Step 4 — when working on M4:** create a Google Cloud project, enable the Drive API, create two OAuth clients (Desktop app and Android; Android needs the keystore SHA-1), set the consent screen to "In production".

**Step 5 — when working on M5:** a Cloudflare account, install `wrangler`, create D1.

---

## 11. Risks

| Risk | Level | Mitigation |
|---|---|---|
| libsodium does not run well on one platform | High | **Spike at M0**; fallback exists |
| Format design error that must change after real data exists | High | Versioned specification, test vectors, key slots allow upgrades; review before real use |
| User loses both the passphrase and the recovery key | High | Force saving the recovery key when creating the account; backup export button; clearly state it cannot be recovered |
| Scheduled notifications unreliable (manufacturer Android, Windows when app closed) | Medium | Test on real devices; system tray fallback |
| Loss of the Cloudflare or Google account | Medium | Each device keeps a full copy; periodic backup export |
| Clock skew between devices makes merge wrong | Medium | HLC; show conflicts instead of overwriting |
| Leaks via clipboard, screenshots, logs | Medium | Clipboard clearing, `FLAG_SECURE`, no logging of sensitive data |
| Scope creep, core never finished | Medium | Follow the milestone order; additional features go to section 12 |

---

## 12. Later, after the first release

| Item | Value | Notes |
|---|---|---|
| **Android Autofill Service** | High | Almost the main reason to use a password app on a phone; written in Kotlin |
| **Browser extension** (Chrome/Edge/Firefox) | High | Separate TypeScript, reads the same file format; syncs directly with Drive or the server |
| Global hotkey on Windows | Medium | Opens a small window, type a name, copy the 2FA code |
| Android home screen widget | Medium | Shows a few frequently used 2FA codes |
| Server push | Medium | New-device warnings, background sync |
| File attachments | Low | Separate file encryption |
| Sharing, emergency access, passkeys | Low | Complex cryptography; only if really needed |

---

## 13. Decisions to confirm

| Question | Proposal |
|---|---|
| Cloudflare replaces Drive or runs alongside it? | **Alongside** (the `SyncProvider` interface is separate). Do Drive first because it needs no server |
| Only you use it, or open it to many people? | **Only you** (allowed-email list). Expand later if needed |
| How does a new device receive the key? | Enter the vault passphrase or recovery key (no QR in the first release) |
| Should Windows notify when the app is closed? | If yes: run in the system tray in the background (simple) or scheduled MSIX |
| App name, package id, icon, licence | Not yet set. Needed before M7 |
| Minimum Android | Proposed Android 8.0 (API 26) or higher |

---

## 14. Next steps

1. Install the Flutter SDK (step 1 of section 10).
2. M0: create the project in `app/`, run the crypto spike on Windows (and Android if available).
3. Write `docs/vault-format.md` and `docs/threat-model.md`.
4. M1: write and test the core.
