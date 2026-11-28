# Vault File Format Specification (`.vkv`) — draft v0.1

> Status: **draft v0.2, with a reference Dart implementation (M1)**. This specification matches the code in `app/lib/core/`. Not yet reviewed by outsiders: **do not use for real data until it has been reviewed (see `docs/project/TASKS.md` M7)**.
> Every implementation (Dart, and TypeScript for future extensions/server) must read and write **byte-for-byte identically** according to this document.

---

## 1. Goals

1. Storage locations (Google Drive, Cloudflare server, disk) **cannot read the content** and cannot modify it without detection.
2. Can be opened in **several ways** (passphrase, recovery key) without re-encrypting the whole vault.
3. **Cheap passphrase change** (only re-wraps the key, does not re-encrypt the data).
4. Has a **version** so it can be upgraded later without breaking old vaults.
5. Can be **merged** between several devices.

Out of scope: hiding the fact that this is a VanKey file (the magic number makes it obvious), hiding the exact number of entries (size padding, see 6.3).

---

## 2. Algorithms

| Purpose | Algorithm | Notes |
|---|---|---|
| Deriving a key from the passphrase | **Argon2id** (libsodium `crypto_pwhash`, `ALG_ARGON2ID13`) | Parameters stored in each key slot |
| Authenticated encryption | **XChaCha20-Poly1305-IETF** (libsodium `crypto_aead_xchacha20poly1305_ietf`) | Random 24-byte nonce, 16-byte tag |
| Deriving a key from the recovery key | **HKDF-SHA256** (RFC 5869) | The recovery key has enough entropy, so Argon2 is not needed |
| Random generation | OS CSPRNG / libsodium (`randombytes_buf`) | Not the language's `Random()` |
| Comparing secrets | Constant-time comparison | |

If spike M0 shows that `sodium_libs` does not work on one platform, a replacement library must be chosen, **but the algorithms above stay the same** so that the format does not change.

---

## 3. Key hierarchy

```
vault key (32 random bytes, created once)
   │  encrypts all data (XChaCha20-Poly1305)
   │
   └── "wrapped" separately in each key slot:
         ├─ passphrase : KEK = Argon2id(NFKC(passphrase), salt, parameters)
         ├─ recovery   : KEK = HKDF-SHA256(recovery_bytes, salt, "vankey/recovery/v1")
         └─ device     : KEK = random key stored in the OS secure storage
                          (NOT in the sync file, see 3.2)
```

- `wrap = AEAD(KEK, nonce, vault_key, aad = vaultId || slotId)`. `vaultId` and `slotId` are bound in the AAD so that a key slot cannot be copied into another vault.
- **Changing the passphrase:** open the vault, compute a new KEK, re-wrap the vault key into the passphrase slot. The data does not change.
- **Rotating the vault key** (when exposure is suspected): generate a new vault key, re-encrypt all data, wrap it into every key slot again. Other devices must reopen the vault with the passphrase or recovery key.

### 3.1 Passphrase normalisation
Before feeding the passphrase to Argon2id: **apply Unicode NFKC normalisation**, then UTF-8. This is required, because Vietnamese has combining characters (for example `ệ` can be one character or `e` plus diacritics), and keyboards and operating systems produce different forms. Without normalisation, the same passphrase could open the vault on one machine but not another.
> Dart does not include NFKC in its standard library; a package (for example `unorm_dart`) is needed, with separate tests using Vietnamese strings.

### 3.2 The `device` key slot is not in the sync file
The `device` slot is tied to **one specific device** (the key lives in Keystore/Credential Manager). If it were in the sync file, one device would overwrite another device's slot.
- **Sync file** (`vault.vkv` on Drive/Cloudflare) contains only the `passphrase` and `recovery` slots.
- **Local copy** on a device = the sync file + a small `local.json` containing the wrap of the `device` slot (and local settings). Fast biometric unlock uses this slot.
- **Offline mode, no account:** the local file may have no `passphrase`/`recovery` slot yet, only `device`. When sync is turned on, `passphrase` and `recovery` **must** be added before uploading.

---

## 4. File layout

Multi-byte integers use **big-endian**.

```
offset      size         field
0           4            magic = 0x56 0x4B 0x56 0x31  ("VKV1")
4           2            format_version (u16) = 1
6           2            flags (u16) = 0, reserved
8           4            header_len H (u32)
12          H            header: UTF-8 JSON (see 5)
12+H        24           nonce (XChaCha20-Poly1305)
36+H        C            ciphertext || tag(16)
```

- **AAD of the data encryption step** = all bytes from offset 0 up to the end of the header (`0 .. 12+H`). Changing the magic, version or header makes decryption fail.
- Limits: `H ≤ 64 KiB`, whole file `≤ 16 MiB` (reject if exceeded; protects against malicious files that exhaust memory).
- Readers **reject** a `format_version` higher than they support (the message says the app must be updated), and **never overwrite** a vault with a higher version.

---

## 5. Header (JSON)

```json
{
  "vaultId": "7f3c...-uuid",
  "revision": 42,
  "updatedAt": "2026-11-19T10:15:30Z",
  "cipher": "xchacha20poly1305-ietf",
  "keyslots": [
    {
      "id": "slot-uuid",
      "type": "passphrase",
      "kdf": { "alg": "argon2id13", "opslimit": 3, "memlimit": 67108864, "salt": "<b64 16B>" },
      "wrap": { "nonce": "<b64 24B>", "ct": "<b64 48B>" }
    },
    {
      "id": "slot-uuid",
      "type": "recovery",
      "kdf": { "alg": "hkdf-sha256", "salt": "<b64 16B>", "info": "vankey/recovery/v1" },
      "wrap": { "nonce": "<b64 24B>", "ct": "<b64 48B>" }
    }
  ]
}
```

- Binary values inside the JSON use **standard base64 with padding**.
- `revision` increases by 1 on each write (for diagnostics; **not** used as the sync mechanism, the sync version is managed by the storage location).
- `opslimit`/`memlimit` default to **[M0]**: expected `opslimit=3`, `memlimit=64 MiB`, adjusted after real measurements (see docs/project/TASKS.md M0). They are stored in each slot, so they can be upgraded later.
- **Mandatory lower bounds when reading:** reject `memlimit < 32 MiB` or `opslimit < 2` (protects against parameter downgrade). The parameters are part of the AAD of `wrap`, so changing them makes unlocking fail.
- The header contains **no** item names, item counts, or any other information about the data.

### 5.1 Recovery key
- 24 characters from the alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (32 symbols; `0 O 1 I` are excluded to avoid confusion) → **120 bits of entropy**.
- Displayed in groups: `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`. When entered: spaces and hyphens are removed, and case is ignored.
- `recovery_bytes` = the 24 symbols decoded into 15 bytes. KEK = `HKDF-SHA256(ikm = recovery_bytes, salt, info)`.

### 5.2 AAD of the key wrap
`wrap.ct = XChaCha20-Poly1305(KEK, wrap.nonce, vault_key, aad)` where `aad` is the UTF-8 string:

```
passphrase : vankey/wrap/v1|<vaultId>|<slotId>|passphrase|argon2id13|<opslimit>|<memlimit>|<salt base64>
recovery   : vankey/wrap/v1|<vaultId>|<slotId>|recovery|hkdf-sha256|<salt base64>|<info>
```

This means a slot **cannot be copied into another vault** (different `vaultId`), and **editing the KDF parameters in the header makes unlocking fail**.

### 5.3 Unknown slots
A slot with an unknown `type` (added by a newer app version) is **ignored when opening and preserved when writing back**; it does not need valid `kdf`/`wrap`. Unknown fields at the top level of the header are also preserved.

---

## 6. Data inside (after decryption)

### 6.1 Format
UTF-8 JSON:

```json
{
  "schema": 1,
  "groups": ["Personal", "Work"],
  "items": [ /* Item, see 6.2 */ ],
  "tombstones": [ { "id": "item-uuid", "deletedAt": "...", "hlc": "..." } ]
}
```

### 6.2 `Item`
```json
{
  "id": "uuid",
  "type": "login|totp|key|crypto|card|wifi|note",
  "title": "GitHub",
  "fields": [
    { "key": "username", "value": "...", "secret": false, "kind": "text" },
    { "label": "Security question", "value": "...", "secret": true, "kind": "text" }
  ],
  "totp": { "secret": "<base32>", "algo": "SHA1", "digits": 6, "period": 30 },
  "group": "Dev",
  "favorite": true,
  "pwHistory": [ { "value": "...", "changedAt": "..." } ],
  "reminder": { "months": 3, "noticeDays": 7, "lastChangedAt": "..." },
  "createdAt": "...",
  "updatedAt": "...",
  "deletedAt": null,
  "hlc": "<wallclockMs>:<counter>:<deviceId>"
}
```
- **Template fields have a stable `key`** (`username`, `password`, `url`, `backupCodes`, `account`, `service`, `key`, `expiry`, `wallet`, `address`, `seedPhrase`, `holder`, `number`, `cvv`, `pin`, `ssid`, `security`, `content`, `notes`), so the UI can translate labels per language; **user-added fields** use `label` instead of `key`. Templates are defined in `ItemTemplates` (`app/lib/core/vault/models.dart`).
- `deletedAt != null` means **in the trash** (restorable for 30 days; after that it is deleted permanently). Permanent deletion → removed from `items` and added to `tombstones` so the deletion spreads to other devices.
- A field with `secret: true` must not be used as a secondary line in a list, must not be included in search, and must not be shown until the user taps.
- Unknown fields in the JSON must be **preserved when writing back** (both at item level and vault level). An unknown `type` is temporarily shown as `note` but is **written back with its original value**.
- A `schema` higher than the app understands → refuse to open (the app must be updated).

### 6.3 Size padding
Before encryption, **pad the JSON with spaces (0x20) up to a multiple of 4096 bytes**. Trailing spaces are valid JSON, so no unpadding mechanism is needed. This reduces exposure of the exact number of items through file size.

### 6.4 Compression
No compression in v1 (simpler, avoids compression attacks). The header has room to add `compression` in a later version.

---

## 7. Merge

> **Change from draft v0.1:** the draft used a `parentHlc` field to detect conflicts. That approach **reports conflicts incorrectly** when one device edits an item several times in a row before syncing (the other device sees the latest version but not the intermediate ones). It has been replaced by a **three-way merge**, and `parentHlc` was removed.

**Hybrid logical clock (HLC):** `hlc = <wallclockMs>:<counter>:<deviceId>`; `deviceId` contains only letters, digits, `-`, `_`. Comparison is by `(wallclockMs, counter, deviceId)`: a **total order**, so every device picks the same winner regardless of clock skew. Every time an item is edited (including moving to the trash or restoring), the device generates an HLC **greater than** every HLC it has generated or seen. A malformed HLC string is treated as the oldest.

**Three-way merge** `merge(local, remote, base)`: `base` is the latest common version that was successfully synced (saved by the device after each sync; `null` if it has never synced). For each `id` (state: item present / permanently deleted / absent):

| Situation | Result |
|---|---|
| `local` and `remote` are the same version (same `hlc`, or both tombstones) | keep it (two tombstones with different `hlc` → take the larger `hlc`, so the result does not depend on order) |
| `base` exists, only one side changed compared with `base` | take the side that changed, **no conflict** (even if that side changed several times) |
| `base` exists, both sides changed | the version with the larger `hlc` wins; if both are existing items, **record a conflict** so the UI can ask the user |
| No `base`, one side is missing | take the side that has it |
| No `base`, both exist and differ | larger `hlc` wins, record a conflict |
| Tombstone against an edit | larger `hlc` wins (an edit after a deletion keeps the edit), **no** conflict recorded |

- **Resolving a conflict:** the user chooses to keep their own version or the server's; the result is a **new version** (HLC greater than both) so that on the next sync every device receives it.
- `groups`: union of both sides (deleting groups is not tracked yet).
- **Properties verified by random testing** (500 scenarios, `test/core/vault/merge_test.dart`): commutativity (swapping local/remote gives the same result and the same conflict set), convergence (merging the result again with either side changes nothing), and no item loss when there is no newer tombstone.
- Found by random testing and fixed: when both devices permanently deleted the same item, the result depended on order unless tombstones were chosen by `hlc`.

---

## 8. Write and read procedures

**Write:**
1. Increase `revision`, set `updatedAt`.
2. Pad the JSON (6.3), generate a **new** random 24-byte nonce.
3. Build the bytes from the magic up to the end of the header, use them as the AAD.
4. Encrypt with the vault key.
5. Write to a **temporary file in the same folder** (`<name>.tmp`), `flush`, keep the previous version as `<name>.bak`, then **rename** over the old file (atomic write; a half-written vault is never left behind). Implementation: `VaultStorage.writeAtomic`.

**Read:**
1. Check magic, version, length (limits in section 4).
2. Parse the header, check the lower bounds of the KDF parameters.
3. Try the key slots in order; opening one slot gives the vault key.
4. Decrypt the data with the AAD; **failure = treat the file as corrupt or tampered**, never return partial data.
5. Erase the intermediate key (KEK) and plaintext from memory as soon as finished (best effort).

---

## 9. Test vectors and testing

Test vectors shared with TypeScript later are in `app/test/vectors/`. Existing tests (Dart):

- [x] Argon2id: Vietnamese passphrase + salt + parameters → 32-byte key, **checked against libsodium** (`primitives-v0.json`, `test/core/crypto/primitives_test.dart`)
- [x] XChaCha20-Poly1305: official vectors from draft-irtf-cfrg-xchacha A.3.1, and a vector with Vietnamese text checked against libsodium
- [x] HKDF-SHA256: RFC 5869 vectors (test cases 1 and 3)
- [x] NFKC: a Vietnamese passphrase in composed and precomposed form opens the same vault
- [x] Corrupt file: wrong magic, truncated, garbage header JSON → `CorruptVaultException`; flipping individual bytes throughout the file → never opens
- [x] `format_version` higher, or unknown flags → `UnsupportedVersionException`
- [x] KDF parameters too weak or too heavy in the header → `WeakKdfParametersException`
- [x] Copying a slot into another vault (different `vaultId`) → cannot open
- [x] Unknown slot and unknown header fields are preserved when opened and written back
- [x] Size padding: the encrypted part is always a multiple of 4096 (+ 16-byte tag)
- [ ] **A fixed complete `.vkv` file** (with passphrase and recovery key) for **cross-reading by TypeScript**. Not created yet; needed when the extension/server is built. Cross-checking Dart ↔ libsodium for the primitives has been done (see `docs/technical/spike-m0.md`), but **there is no cross-check yet for the whole file format**.

---

## 10. Open questions

| # | Question | Status |
|---|---|---|
| 1 | Final Argon2id parameters | Default **3 passes, 64 MiB** (0.88 s on PC); to be confirmed after measuring on Android (see `spike-m0.md`) |
| 2 | HKDF | **Decided:** use HKDF from the `cryptography` library (matches RFC 5869 vectors) |
| 3 | Server authentication key derived from the vault key (Cloudflare sign-in) | Kept separate from this format; to decide at M5 |
| 4 | Field names / enum values of `kind` | Currently free strings (`text`, `multiline`, `url`); standardise when needed |
| 5 | Are `settings` synced inside the vault? | No, settings are local only |
| 6 | `device` slot (fast biometric unlock) | The UI will be built in M3; **not** in the sync file (section 3.2) |
| 7 | Tracking group deletion during merge | Not yet; groups are only unioned |
| 8 | HOTP (counter) | Not supported in v1: `totp` only has TOTP; HOTP links during import are skipped with a warning |

---

## 11. Reference implementation

| Part | File |
|---|---|
| Cryptographic primitives | `lib/core/crypto/{aead,kdf,csprng,passphrase,recovery_key}.dart` |
| Key slots | `lib/core/crypto/keyslot.dart` |
| Vault file, header | `lib/core/vault/vault_file.dart` |
| Session (create, open, change passphrase, rotate key) | `lib/core/vault/vault_session.dart` |
| Data model | `lib/core/vault/models.dart` |
| HLC and merge | `lib/core/vault/{hlc,merge}.dart` |
| Atomic write | `lib/core/vault/vault_storage.dart` |
