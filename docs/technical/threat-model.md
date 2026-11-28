# Threat Model — draft v0.1

> Status: **DRAFT**, written before the code existed, as a yardstick for security decisions. Must be reviewed after M3 (device security) and before release.

---

## 1. Assets to protect

| Asset | Sensitivity |
|---|---|
| Passwords, API keys, crypto wallet recovery phrases, card numbers | Very high |
| **2FA keys (TOTP secrets)** | Very high (anyone who has them can generate your 2FA codes) |
| Vault passphrase, recovery key | Very high (opens the whole vault) |
| Recovery codes / backup codes for other services | Very high |
| Service names, number of entries, edit times (metadata) | Low to medium |

---

## 2. Attackers and protection level

| # | Attacker / situation | Protected? | How |
|---|---|---|---|
| A1 | **Network eavesdropping** (public Wi-Fi, MITM) | Yes | HTTPS; data is encrypted before it leaves the device |
| A2 | **Storage compromised** (Google Drive, Cloudflare D1, database leak) | Yes | Only encrypted blobs are stored; no keys on the server |
| A3 | **Server or Google administrators read the data** | Yes | As A2 (zero-knowledge) |
| A4 | **Your Google account or login is taken over** | Partly | The attacker gets the encrypted blob but cannot decrypt it. They can **delete or corrupt** the blob; each device keeps a full copy, which reduces the loss |
| A5 | **Offline guessing of the passphrase** (with the vault file) | Depends on the passphrase | Argon2id makes mass guessing hard. **A weak passphrase can still be guessed.** The app must measure strength when it is set |
| A6 | **Phone or laptop lost (locked)** | Yes | Screen lock + app lock; key stored in Keystore/Credential Manager; biometrics |
| A7 | **Device taken while unlocked** | Limited | Auto-lock after N minutes; keys removed from RAM on lock. Cannot stop someone holding an unlocked device |
| A8 | **Shoulder surfing, screenshots, screen recording** | Partly | `FLAG_SECURE` (Android), hide when switching apps, passwords hidden by default |
| A9 | **Clipboard read by another app** | Reduced | Cleared automatically after 30 seconds; marked sensitive (Android) |
| A10 | **Notifications or logs leak secrets** | Yes | Notifications only show service name and due date; no sensitive data logged |
| A11 | **Malware in a third-party library** (supply chain) | Reduced | Pinned versions, few dependencies, review on update, prefer widely used libraries |
| A12 | **Phishing / social engineering** (fake page asking for the passphrase) | Partly | The passphrase is only entered in the app and in the read-only web app served by your own server at `/app/`. Check the address before typing it |
| A14 | **Server or deploy pipeline (Cloudflare, GitHub) compromised and serves malicious web code** | Partly (web app only) | The installed apps are not affected. The web app: the service worker keeps the installed version until you press "Update"; Subresource Integrity on scripts; strict CSP (`connect-src 'self'`, no third-party code). A fresh browser with no service worker yet trusts whatever the server sends. Protect the Cloudflare and GitHub accounts with strong 2FA |
| A13 | **User loses both the passphrase and the recovery key** | **No** | Cannot be recovered. This must be stated clearly and the recovery key must be saved when created |

---

## 3. Out of scope (cannot be protected)

- **Devices already infected with malware, keyloggers, screen recorders, or deliberately rooted/jailbroken devices.** High-privilege malware can read memory while the vault is open.
- **An attacker holding an unlocked device who understands the app.**
- **Legal compulsion or coercion of the user** (see 5).
- **Hardware side-channel attacks** (power, heat measurements, etc.).
- **Weak passphrases or passphrases reused elsewhere.**

---

## 4. Required security properties

1. **Zero-knowledge:** the passphrase, recovery key, vault key or plaintext never leave the device.
2. **Integrity:** changing any byte of the vault file makes decryption fail; wrong data is never returned.
3. **No downgrade:** weaker KDF parameters than the minimum are rejected; an older file version cannot overwrite a newer vault.
4. **Separate login from keys:** signing in with Google or email only says who you are; it is not enough to decrypt.
5. **Device revocation:** removing a device from the account stops it from downloading or uploading on the server. (It cannot delete data already downloaded to that device; see 6.)

---

## 5. Assumptions and limitations to state plainly to users

- Forgetting both the passphrase and the recovery key = **permanent data loss**.
- Removing a device does **not** revoke copies of data already on that device. If you suspect a device was exposed, changing the vault passphrase and rotating the vault key is required, then change the passwords of important services.
- Metadata that is visible: file size (padded to multiples of 4 KiB), update time, number of devices, IP addresses used to connect to the server.
- Google Drive or Cloudflare may **delete or fail to return** your files. Each device keeps a full copy, and encrypted export is available to reduce the risk.

---

## 5b. Attack surface by component

| Component | Main risk | Mitigation |
|---|---|---|
| App (Dart) | Data still in RAM after locking; the GC cannot erase it immediately | Erase/overwrite key buffers on lock; keep plaintext lifetime as short as possible (**known limit**: Dart does not guarantee complete erasure) |
| Web app (`server/web`, read-only) | Malicious code served by a compromised server; browser extensions read the page; keys left in browser memory; the browser deletes stored data | Read-only (never uploads a vault); Argon2id in a Web Worker; vault key in memory while open; reloading keeps it for that tab only (encrypted in sessionStorage with a non-extractable AES key in IndexedDB, which a copy of the whole browser profile could still use while the session lasts); locks on tab close, after 15 minutes idle or with the Lock button; showing or copying a secret field asks for the password again after 2 minutes (protects an unattended open screen, not against malware); IndexedDB holds only the encrypted vault and a refresh token sealed with a key derived from the vault key; clipboard cleared after 30 seconds when the page has focus; only http(s) links are opened. Extensions with page access are out of scope (like malware) |
| Local storage | Files read directly | Files are always encrypted; device key in Keystore/Credential Manager |
| Drive sync | OAuth token stolen | Token stored in the OS secure store; minimum scope `drive.appdata` |
| Cloudflare server | Sign-in attacks, spam, filling storage slots | Rate limits per IP and per account, limits on number of accounts, registrations per IP and devices, optional invite code, two-layer password hashing, refresh tokens stored hashed and revocable |
| Import/export | Unencrypted CSV/JSON files left on disk | Clear warnings, passphrase required, reminder to delete the file after use |
| Breach check (HIBP) | Sending passwords out | Only the **first 5 characters of the SHA-1 hash** are sent (k-anonymity); the password is never sent |
| Notifications | Secrets shown on the lock screen | Only service name and due date are shown |
| App updates | Replaced installer | Signed releases; distribution through controlled channels |

---

## 6. Action items (linked to docs/project/TASKS.md)

- [ ] Vault format specification and test vectors (`vault-format.md`, M1)
- [ ] Measure passphrase strength when set; reject passphrases that are too weak (M2/M3)
- [ ] Slow down after many wrong attempts (M3)
- [ ] Sensitive data is not logged; logs are reviewed before release (M3)
- [ ] Notifications contain no secrets (M6)
- [ ] Rehearse recovery and lost-device scenarios (M7)
- [ ] Have a qualified expert review the specification and cryptographic parts before real use (M7)

---

## 7. Review again when

- A browser extension or Autofill is added (new surface: malicious websites, fake apps).
- Sharing between users or emergency access is added (the key model changes significantly).
- Server push is added (more metadata disclosed through Google FCM / Microsoft WNS).
- Registration is opened to many users (more abuse, more storage responsibility).
