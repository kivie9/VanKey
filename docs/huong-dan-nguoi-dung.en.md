**[Tiếng Việt](huong-dan-nguoi-dung.md)** · English

# VanKey Quick Guide

Read this once before you start. The sections below are in order of importance.

## 1. Three things to remember

1. **The vault password and the recovery code are the only two things that can open the vault.** Nobody can recover them for you, not even the developer. If you lose both, you lose your data.
2. **Keep the recovery code outside your phone.** When you create a vault, the app shows the code only once. Copy it and store it in the recovery sheet (see [recovery-sheet.en.md](recovery-sheet.en.md)). Do not keep it only in a screenshot or a note on the device.
3. **Back up regularly, with encryption.** Settings → Data → Export and backup → Encrypted backup. This file can only be opened with the vault password or the recovery code.

## 2. Creating a vault for the first time

1. Open VanKey and choose how you want to use it: a VanKey server, Google Drive, or this device only.
2. Set a vault password. Choose a long password that you can remember and that you do not use anywhere else.
3. Copy the recovery code that appears. Tick the box "I have saved the recovery code", then tap **Start using VanKey** (the button is only enabled after you tick the box).
4. Write the code into the recovery sheet and store the sheet somewhere safe.

## 3. Switching from Google Authenticator

1. In Google Authenticator, choose **Export accounts** and select the entries you want to move.
2. In VanKey tap **+ → Scan QR**. You can take a screenshot of the QR code and then pick the image.
3. Compare a few 2FA codes with the old app. Only delete the old app once they match.
4. **Delete the export links and QR screenshots** after you finish. They contain your 2FA secrets.

## 4. Syncing between devices

- Turn it on in **Settings → Data → Sync**. Choose a VanKey server, Google Drive, or a folder.
- New device: sign in to the server, or choose the same Google Drive account or folder, then enter the vault password.
- When two devices edit the same entry, the app shows a conflict screen so you can choose which version to keep.
- Lost your phone: on another device still signed in, go to **Settings → Data → Sync → Signed-in devices** and remove the lost device. Then change your vault password if you suspect it was exposed.

## 5. Unlocking and protection

- Fingerprint or Windows Hello is only a quick way in. You still need the vault password when fingerprints are changed on the device.
- Turn on **auto-lock** (default 5 minutes). Do not leave the vault open when you hand your device to someone else.
- Forgot the vault password: on the unlock screen tap **Forgot password? Use recovery code**, enter the code, then set a new password and **create a new recovery code**. The old code no longer works.

## 6. What to do when you forget or lose something

| Situation | What to do |
|---|---|
| Forgot the vault password, still have the recovery code | On the unlock screen use the recovery code, set a new password, create a new recovery code |
| Forgot both | You cannot open the vault. Sign in to each service with that service's backup codes, then create a new vault |
| Lost your phone | Remove that device under Signed-in devices, change the vault password |
| Want to delete your server account | Settings → Data → Sync → Delete account (cannot be undone) |

## 7. Suggested schedule

- **Every 3 months:** try opening the vault with the recovery code or a backup file, and write the date on the recovery sheet.
- **Every time you change the vault password:** update the recovery sheet.
- **Before you uninstall the app or change devices:** export an encrypted backup and check that the file opens.

## 8. What the app does not do

- It does not send your password or vault data anywhere unless sync is turned on.
- There is no automatic analytics or crash reporting.
- Checking for leaked passwords only sends the first 5 characters of the password's hash to HaveIBeenPwned.

A fuller list of questions is in **Settings → Support**.
