# VanKey: Flutter app

The VanKey Android, Windows (and unsigned iOS) app. Project overview in the [main README](../README.md).

## Structure

```
lib/main.dart          entry point: initialisation, font licence registration, choice of first screen
lib/core/              pure Dart core, no Flutter dependency (see docs/technical/core-api.md)
  crypto/ vault/       cryptography, .vkv vault file, 3-way merge
  totp/                2FA (TOTP, HOTP, Steam Guard)
  import_export/       import from other apps, export to CSV/links/QR
  security/            password generation, strength, duplicates, HIBP, reminders
  sync/                Cloudflare sync, Google Drive, folder
  notify/ platform/    reminder schedule, communication with the operating system
lib/app/               UI and state
  vault_controller.dart  vault state, lock/unlock, sync
  isolate_ops.dart       all Argon2id operations run in a separate isolate
  platform_bridge.dart   calls to native code (FLAG_SECURE, Windows Hello...)
  i18n.dart, i18n_en.dart  Vietnamese strings are the keys, English translations
  screens/ widgets/      screens and shared components
test/                  tests for core, UI, end-to-end (e2e), reference vectors
tool/                  import_check (test import with real files), make_icon, interop (checks against libsodium)
scripts/               one-click build and install scripts for Windows
installer/vankey.iss   Windows installer (Inno Setup 6)
```

## Common commands

```powershell
flutter test                      # all tests (e2e needs Node 22.6+, skipped automatically without it)
flutter analyze                   # must be clean
flutter run --release -d <device> # debug builds are very slow with Argon2id
dart run tool/import_check.dart <file> --titles --codes
```

## Build and install

| Task | How |
|---|---|
| Install on a phone connected by USB, keep data | `scripts\install-android.cmd` |
| Build Windows, create installer and install over existing | `scripts\build-windows.cmd` (needs Inno Setup 6) |
| Create the Android signing key (once) | `scripts\create-android-signing-key.cmd` |
| Release for all 3 platforms | push tag `v1.2.3`; CI in `.github/workflows/build.yml` creates a GitHub Release |

The version shown in the app comes from `--dart-define=APP_VERSION=...` (CI sets it from the tag). A manual build without it shows `dev`.

## Where data is stored

- Windows: the vault is at `%APPDATA%\com.vankey\vankey`; the app is installed at `%LOCALAPPDATA%\Programs\VanKey`. Uninstalling the app does not delete the vault.
- Android: the app's own data folder. Uninstalling the app deletes the vault, so back up first.

## Rules when editing

- UI strings are written in Vietnamese inside `tr('...')`; add the English translation to `i18n_en.dart` (the `i18n_test.dart` test catches missing strings).
- Argon2id is not called directly from `VaultController`; calls go through `isolate_ops.dart`.
- If you change the vault file format, update `docs/technical/vault-format.md` and the vectors in `test/vectors/`.
