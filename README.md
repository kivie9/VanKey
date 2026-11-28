# VanKey

Manage passwords, keys and 2FA (TOTP) codes with end-to-end encryption. Works offline and syncs between devices.
A replacement for Google Authenticator that can import directly from it.

- Plan: [PLAN.md](docs/project/PLAN.md) · Tasks: [docs/project/TASKS.md](docs/project/TASKS.md) · Status: [docs/project/STATUS.md](docs/project/STATUS.md)
- Vault file format: [docs/technical/vault-format.md](docs/technical/vault-format.md) · Threat model: [docs/technical/threat-model.md](docs/technical/threat-model.md)
- Core library for UI developers: [docs/technical/core-api.md](docs/technical/core-api.md)
- Quick user guide: [docs/guide/huong-dan-nguoi-dung.md](docs/guide/huong-dan-nguoi-dung.md) · Operations notes: [docs/operations/van-hanh.md](docs/operations/van-hanh.md)
- Changelog: [CHANGELOG.md](docs/project/CHANGELOG.md) · Printable recovery sheet: [docs/guide/recovery-sheet.md](docs/guide/recovery-sheet.md) · Website: [site/PLAN.md](site/PLAN.md)

## Structure

```
app/lib/core/   pure Dart core (crypto, vault, TOTP, import/export, security, sync), no Flutter dependency
app/lib/app/    UI and state (VaultController, screens, Vietnamese/English localization)
app/test/       tests for core, sync, UI and translation strings
app/tool/       command-line tools (import_check: test the importer with real files; interop: cross-check against libsodium)
server/         optional Cloudflare Worker + D1 server: see server/README.md
docs/           documentation
```

## Build and run

You need Flutter (project path: `E:\code\libs\flutter`), the Android SDK, and Windows **Developer Mode** (for plugin symlinks).

```powershell
cd app
flutter test                                   # all tests
flutter analyze                                # must be clean
# end-to-end tests need Node 22.6+ (they start server/dev/serve.ts automatically); without Node they are skipped
flutter run --release -d <device id>           # install on a phone (use release: debug is much slower with Argon2id)
dart run tool/import_check.dart <file> --titles --codes   # test the importer with a real export file, print 2FA codes to compare with the old app
```

**Signing an Android release:** run `app/scripts/create-android-signing-key.cmd` once to create the key (stored in `%USERPROFILE%\vankey-signing`) and `app/android/key.properties`. Without a key, local builds are signed with the debug key (with a warning), and CI stops completely. Keep the `.jks` file and its password somewhere safe: if you lose them, you can no longer publish updates over an installed release.

Note: the project lives on a different drive from the pub cache, so `android/gradle.properties` sets `kotlin.incremental=false`.
