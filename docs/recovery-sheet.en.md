**[Tiếng Việt](recovery-sheet.md)** · English

# VanKey Emergency Recovery Sheet

> **This is a blank template.** Print it and fill it in by hand. **Do not** fill in this file, and do not save a filled-in copy in the repo, on a computer, in a photo, or in the cloud.
> If possible, store the filled-in copy outside your home (a safe, or a trusted relative). You can print 2 copies and keep them in 2 places.

Date created: ____ / ____ / ________  Last reviewed: ____ / ____ / ________

---

## 1. Vault access

| Item | Write here |
|---|---|
| Recovery code (shown when the vault was created, or created anew in Settings → Account → Recovery code) | ______________________________________________ |
|  | ______________________________________________ |
| Vault password hint (a hint only, do **not** write the password itself) | ______________________________________________ |

The app does not let you view an old code again. If you are not sure the code you wrote down is still valid, create a new one (the old code stops working) and write it down again.

Without **both** the vault password **and** the recovery code, nobody can open the vault, not even the developer.

## 2. Sync and accounts

| Item | Write here |
|---|---|
| Do you use a VanKey server? Server address | ☐ Yes  ☐ No   ______________________________ |
| Server username (account password: do not write it here) | ______________________________ |
| Do you use Google Drive? Which Google account | ☐ Yes  ☐ No   ______________________________ |
| Do you use a sync folder? Path | ☐ Yes  ☐ No   ______________________________ |

## 3. Encrypted backups

| Where the backup file (`.vkv`) is kept | Date of last backup |
|---|---|
| 1. ______________________________ | ____ / ____ / ________ |
| 2. ______________________________ | ____ / ____ / ________ |

A backup file can only be opened with the vault password or the recovery code. Back up again after adding many 2FA entries.

## 4. Devices using VanKey

| Device | Biometric unlock? |
|---|---|
| ______________________________ | ☐ Fingerprint  ☐ Windows Hello  ☐ None |
| ______________________________ | ☐ Fingerprint  ☐ Windows Hello  ☐ None |
| ______________________________ | ☐ Fingerprint  ☐ Windows Hello  ☐ None |

## 5. Important accounts with 2FA in VanKey

List the accounts that would be hard to recover if you lost 2FA (main email, bank, Google, Apple, Cloudflare, GitHub, etc.). Also note where the **backup codes** for each service are kept, if you have them.

| Service | Where its backup codes are kept |
|---|---|
| ______________________________ | ______________________________ |
| ______________________________ | ______________________________ |
| ______________________________ | ______________________________ |
| ______________________________ | ______________________________ |
| ______________________________ | ______________________________ |

---

## When you need it

### A. Phone or computer lost or broken
1. On another device that uses VanKey: Settings → Data → Sync → Signed-in devices → **remove the lost device** (only available when using a VanKey server).
2. If you suspect someone else can access the lost device: **change the vault password** right away (Settings → Account → Change vault password).
3. Install VanKey on the new device (see section B).
4. Change the passwords of the important accounts in section 5 if the old device had no screen lock.

### B. Reinstall from scratch on a new device
1. Install VanKey (Android: APK file; Windows: installer from the release page).
2. Choose one of the three options:
   - **VanKey server:** sign in with the username from section 2, and the app downloads your vault.
   - **Google Drive / folder:** turn on sync and choose the correct account or folder from section 2.
   - **Backup file:** open the `.vkv` file from section 3.
3. Open the vault with the vault password. If you forgot it, choose **Forgot password? Use recovery code** and enter the code from section 1.
4. If you used the recovery code: set a new vault password, create a new recovery code (Settings → Account → Recovery code), and update this sheet.
5. Compare a few 2FA codes with the real service to make sure they are correct.

### C. Forgot the vault password but still have the recovery code
Unlock screen → **Forgot password? Use recovery code** → enter the code → set a new password → create a new recovery code → update section 1.

### D. Lost both the vault password and the recovery code
You cannot open the vault. Use the **backup codes for each service** in section 5 to get back into those accounts, then create a new vault and add the 2FA entries again.

---

## Checklist

- [ ] Every 3 months: try opening the vault with the recovery code on one device (or with a backup file), and write the date at the top of this sheet.
- [ ] Every time you change the vault password or create a new recovery code: update section 1.
- [ ] Every time you add or remove a device: update section 4.
