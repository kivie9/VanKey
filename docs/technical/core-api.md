# `lib/core/` — Overview for UI developers (M2)

Everything is **pure Dart, does not import Flutter**. The UI only calls into this layer and never implements cryptography itself.
Format specification: [`vault-format.md`](vault-format.md). Task list: [`TASKS.md`](../project/TASKS.md).

## Main flow

```dart
// 1) Create a new vault (first time). Returns the session and the recovery key (shown ONCE for the user to save).
final (session, recovery) = await VaultSession.create(passphrase: 'the user's passphrase');
print(recovery.formatted);                      // XXXX-XXXX-XXXX-XXXX-XXXX-XXXX

// 2) Work with data: VaultData is immutable; every change returns a new version.
final clock = HlcClock(node: deviceId);          // deviceId: letters/digits/-/_ , generated once per device
var data = VaultData.fromJson(session.payload);
final item = Item.create(type: ItemType.login, title: 'GitHub', clock: clock,
    values: {'username': 'van', 'password': 'p@ss'}, group: 'Dev');
data = data.upsert(item);
session.payload = data.toJson();

// 3) Save to disk (atomic write, keeps .bak).
await VaultStorage.writeAtomic(File(path), await session.save());

// 4) Open again.
final bytes = await VaultStorage.read(File(path));
final opened = await VaultSession.openWithPassphrase(bytes!, 'passphrase');   // or openWithRecoveryKey
// ... when the app locks:
opened.close();                                  // overwrites the vault key in RAM
```

> **Argon2id takes about 1 second** with standard parameters: call `create`/`open*`/`changePassphrase` in a **separate isolate**
> (for example `Isolate.run`) so the UI does not freeze.

## Modules

| Folder | What it does | Entry points |
|---|---|---|
| `crypto/` | Cryptographic primitives, key slots, recovery key | `Kdf`, `Aead`, `KeySlots`, `RecoveryKey`, `normalizePassphrase` |
| `vault/` | Data model, vault file, session, merge, search | `VaultData`, `Item`, `VaultSession`, `mergeVaults`, `matchesQuery` |
| `totp/` | 2FA codes, `otpauth://` links, Google Authenticator | `Otp.code`, `OtpAuth.parse`, `Migration.parseUri` |
| `import_export/` | Import from other apps, export | `Importers.auto`, `Exporters.csv/otpauthLines/googleMigrationUris` |
| `security/` | Strength, password generation, duplicates, security checks, reminders, HIBP | `PasswordStrength`, `PasswordGenerator`, `findDuplicates`, `healthReport`, `pendingAlerts` |

## Showing 2FA codes

```dart
final code = Otp.code(item.totp!, DateTime.now());      // '123456'
Otp.grouped(code);                                      // '123 456'
Otp.secondsRemaining(DateTime.now());                   // 1..30 (for the countdown)
```
Use **one** timer for the whole app (every second) and recalculate all codes; no timer is created per row.

## Sync (M4)

```dart
final r = mergeVaults(local: localData, remote: remoteData, base: lastSyncedData);
// r.merged           -> data after merging
// r.changesLocal     -> must be saved locally
// r.changesRemote    -> must be uploaded
// r.conflicts        -> the UI asks the user; resolveConflict(...) creates a new version
```
After every successful sync, **`base` is saved** (the common version just synced).

## Rules of use

- **Never** print, log or put in a notification: passwords, 2FA keys, passphrases, recovery keys, fields with `secret: true`.
- For secondary lines in a list: use `Item.subtitle` (it omits secret fields).
- Search: use `matchesQuery` (never searches secret fields; ignores Vietnamese diacritics).
- All core errors are `VaultException`; catch by subtype (`AuthenticationFailedException` = wrong passphrase or file was modified,
  `UnsupportedVersionException` = the app needs an update, `EncryptedImportException` = the import file was encrypted by the source app...).
- Field labels: use `Field.key` to look up translations; only user-added fields have `Field.label`.

## Known limitations

- Cryptography runs in **pure Dart**: not yet measured on Android, no guarantee against side-channel attacks, and erasing keys from RAM is best-effort only.
- The file format **has not been reviewed by outsiders**.
- The import readers **have not been tested with real export files** from every application.
- HOTP/Steam are not supported in this layer, there is no `device` slot (biometrics) yet, and there is no `SecureBytes`.
