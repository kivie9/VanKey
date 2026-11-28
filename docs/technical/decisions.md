# Decision Log

Each line: **decision, reason, date, status.** Status: `locked` (decided), `proposed` (not yet confirmed), `waiting for M0` (waiting for a measurement or test).

| # | Decision | Reason | Date | Status |
|---|---|---|---|---|
| D1 | Use **Flutter** (Dart), one codebase for Windows and Android | Halves the effort; identical UI; small platform-specific parts | 2026-11-19 | locked |
| D2 | **End-to-end, zero-knowledge encryption** (storage cannot read the data) | Core requirement of a password manager | 2026-11-19 | locked |
| D3 | Use **key slots**: a random vault key, wrapped by passphrase / recovery / device | Changing the passphrase does not re-encrypt the whole vault; several ways to open | 2026-11-19 | proposed |
| D4 | **Argon2id + XChaCha20-Poly1305**. Use the **`cryptography` package (pure Dart)** behind the project's `Kdf`/`Aead` interface; native libsodium (`sodium_libs`) is a later upgrade path with the same algorithms, so the format does not change | Spike M0: 7 tests pass (including official test vectors), **matches byte-for-byte with an independent libsodium**; runs with `flutter test`; Argon2id 64 MiB x3 = 0.88 s on PC | 2026-11-19 | provisionally locked (verified on Windows; **Android not yet measured**, see `spike-m0.md`) |
| D5 | **Google Drive sync first**, Cloudflare in parallel later | Drive needs no separate server; the `SyncProvider` interface is already separated | 2026-11-19 | proposed |
| D6 | In the early phase, **only emails on the owner's list are allowed** (no free sign-up) | Removes email verification, password reset, anti-spam; reduces the attack surface | 2026-11-19 | proposed |
| D7 | **Vault passphrase separate from the login password**; signing in with Google/email is not enough to decrypt | Even if the server is exposed or an account is taken over, data is not exposed | 2026-11-19 | locked |
| D8 | Expiry reminders by **local notifications**, no server push yet | The device can calculate them itself; the server cannot know expiry dates because data is encrypted | 2026-11-19 | locked for the first release |
| D9 | The HTML prototype is the **source of truth for the UI** | Reviewed over several rounds; stored in `docs/prototype/` | 2026-11-19 | locked |
| D10 | Languages: **Vietnamese by default, English**, using ARB files | The first users are Vietnamese | 2026-11-19 | locked |
| D11 | Deleting an entry = **moves to a 30-day trash**; permanent deletion leaves a tombstone | Accidentally deleting a 2FA entry means losing access to the account | 2026-11-19 | locked |
| D12 | **NFKC** normalisation of the passphrase before hashing | Vietnamese has combining characters; avoids a vault that opens on one machine but not another | 2026-11-19 | proposed |
| D13 | Interface settings (theme, language, density) are **stored locally only**, not synced | Each device has different needs; keeps the vault small | 2026-11-19 | proposed |
| D14 | App name: **VanKey** (replacing the working name KeyManager) | Chosen by the project owner | 2026-11-19 | locked |
| D15 | Package id: `com.vankey.vankey`; vault format names: extension `.vkv`, magic `VKV1`, backup export `.vkbackup` | Contains no personal information; the format is still a draft, so it can be renamed freely before real data exists | 2026-11-19 | proposed (can change until the store release) |
| D16 | **Three-way merge** (local, remote, last synced common version) instead of `parentHlc` | `parentHlc` reports conflicts incorrectly when one device edits several times in a row before syncing | 2026-11-19 | locked (implemented and checked with property tests) |
| D17 | Item fields from templates have a **stable `key`**; `label` only for user-added fields | The UI translates labels per language; the prototype hard-coded Vietnamese labels so it could not be multilingual | 2026-11-19 | locked |
| D18 | v1 supports **TOTP** only; HOTP and Steam are skipped during import with a warning | Rare; avoids having to sync counters between devices | 2026-11-19 | proposed |
| D19 | Google Authenticator's protobuf is **hand-written** (no `protobuf` library) | Only two small messages need reading/writing; fewer dependencies; bounds-checked | 2026-11-19 | locked |
| D20 | Search **never** looks at secret fields; matching ignores Vietnamese diacritics | Matching results could reveal secret content | 2026-11-19 | locked |
| D21 | CSV export keeps the data **verbatim**, with no added protection against Excel formula injection | Adding characters would change passwords; instead the UI warns that the file is not encrypted | 2026-11-19 | proposed |

## Not yet decided

| Question | Proposal | Needed before |
|---|---|---|
| Confirm the package id `com.vankey.vankey` | Use as proposed in D15 | M0 (cannot be changed after the store release) |
| Check the name **VanKey** (app stores, domain, trademarks) if a wide release is planned | Not checked yet | M7 |
| Minimum Android | API 26 (Android 8.0) | M2 |
| Does Windows need a notification when the app is fully closed? | Run in the background in the system tray, or a scheduled MSIX | M6 |
| Final Argon2id parameters | Expected 3 passes, 64 MiB; confirm by measurement | M0 |
| Cloudflare replaces Drive or runs alongside it | Alongside | M4 |
| Source code license | Not chosen | M7 |
| Windows distribution: self-signed MSIX or Microsoft Store | Self-signed for personal use | M7 |

## Installed environment

| Component | Version / location | Date | Notes |
|---|---|---|---|
| Flutter SDK | 3.50.0 stable, Dart 3.14.0, at `E:\code\libs\flutter` | 2026-11-19 | `flutter doctor`: Flutter OK, Windows OK, Chrome OK |
| Android SDK (lightweight, no Android Studio, no emulator) | `cmdline-tools` 23.0 (Android CLI 1.1), `platform-tools` 37.0.1, `platforms;android-36`, `build-tools;36.0.0`, at `E:\code\libs\android-sdk`. NDK 28.2 will be downloaded by Gradle when a build needs it | 2026-11-19 | `flutter doctor`: Android toolchain OK, "All Android licenses accepted". `ANDROID_HOME` is set. Flutter 3.50 defaults to `minSdk 24`, `compileSdk 36`; the plan uses API 26 (changed in M2) |
| Visual Studio (C++ desktop) | **not installed** | | Needed to build the Windows app (M2) |
| ffmpeg | 6.1.1 full build (gyan.dev) at `E:\code\libs\ffmpeg` | 2026-11-19 | Not part of the VanKey project; location recorded only. **Not** in PATH |

Tool folder convention: all shared tools live under `E:\code\libs\` (currently `flutter`, `ffmpeg`, `android-sdk`).
