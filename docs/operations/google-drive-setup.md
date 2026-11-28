# Google Drive Sync Setup (one-time, by the app publisher)

Google Drive sync is for users who **do not want to use a server**. They only tap "Sign in with Google". The sections below are what **you (the app publisher)** must do once so that the app can sign in with Google. Users do not need to register anything.

Currently available on **Android** only. The vault is stored as one encrypted file, `vankey.vkv`, in the app's hidden `appDataFolder` on the user's Drive. The app only asks for the `drive.appdata` permission (it cannot read or see any other file in Drive). Google cannot read the content, because the file is encrypted on the device before upload.

> Not yet tested on a real phone: all Drive calls have been tested against a fake Drive server, but the Google sign-in step needs your Google Cloud settings, so it cannot run here yet. Try it by following section 6 after the setup is complete.

## 1. Create a project and enable the Drive API

1. Go to <https://console.cloud.google.com/> and create a new project (for example `vankey`).
2. APIs & Services → Library → search for **Google Drive API** → Enable.

## 2. OAuth consent screen

1. APIs & Services → OAuth consent screen (or Google Auth Platform).
2. User type: **External**. Enter the app name (`VanKey`), a support email, and a **privacy policy link** (required for public release; it can be a short GitHub Pages page saying the app only stores encrypted data and only uses `drive.appdata`).
3. Scopes: add `https://www.googleapis.com/auth/drive.appdata`. This is a non-sensitive permission, so **Google does not need to review the app**.
4. **Change Publishing status to "In production".** If it stays on "Testing", sign-in tokens expire after 7 days (users must keep signing in again) and only 100 test accounts can be used.

## 3. Create two OAuth clients

APIs & Services → Credentials → Create credentials → OAuth client ID:

1. **Android**
   - Package name: `com.vankey.vankey`
   - SHA-1 certificate fingerprint: of the APK signing key (see section 5).
2. **Web application** (no Authorized redirect URI needed)
   - Copy the **Client ID** of this one. This is `GOOGLE_SERVER_CLIENT_ID`.

Each different signing key (debug key, release key) needs its own Android OAuth client with the matching SHA-1. You can create several Android clients in the same project.

## 4. Build the app with the Client ID

```powershell
cd app
flutter build apk --release --split-per-abi --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

The Client ID is not a secret (it is inside the APK), but it is passed at build time, so it is **not hard-coded in the public source code**. A build without this variable still runs normally; the Google Drive option shows a "not configured" error.

## 5. Signing key and SHA-1

Android checks the Google sign-in against the SHA-1 of the APK signing key. A wrong SHA-1 makes Google report "canceled".

**Debug key (for testing on your machine).** The current build is signed with your machine's debug key. Its SHA-1:

```powershell
& "C:\Program Files\Java\jdk-21\bin\keytool.exe" -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

On this development machine, the SHA-1 of the debug key is `0D:BE:13:7B:63:96:CF:32:29:DD:72:34:14:9C:1C:59:38:7A:56:9F`. The debug key **is different on every machine** and is not used for release.

**Release key (for publishing).** Create it once and store it safely:

```powershell
& "C:\Program Files\Java\jdk-21\bin\keytool.exe" -genkeypair -v -keystore vankey-release.jks -alias vankey -keyalg RSA -keysize 2048 -validity 10000
```

- **Back up the `.jks` file and its password** (for example in a password manager). If you lose this key, you cannot publish updates for people who already installed the app.
- This file is not committed (it is already in `.gitignore`: `*.jks`, `key.properties`).
- Get its SHA-1 with `keytool -list -v -keystore vankey-release.jks -alias vankey`, then create one more Android OAuth client with that SHA-1.
- **Changing the signing key means already-installed versions cannot be updated over** (Android reports a signature conflict; the old app must be uninstalled, which deletes the data on the device). Change the key before there are real users.
- If you later publish on Google Play with Play App Signing, Google re-signs the app with its own key: add that key's SHA-1 (shown in Play Console → App integrity) to one more Android OAuth client.

## 6. Testing

1. Install the build that has `GOOGLE_SERVER_CLIENT_ID` on a phone with a Google account.
2. Clear the app's data (or reinstall) so the first screen appears → choose **Use my Google Drive** → *Sign in with Google* → choose the account → allow.
3. Drive has no vault yet: set a password (at least 8 characters), save the recovery code, open the app, add an item.
4. On a second device (or after clearing data on this one): choose Google Drive, sign in with the same account → the app reports that Drive already has a vault → enter the password → the added item appears.
5. Check: Google Drive (web) → Manage apps → VanKey will show a "Hidden app data" entry. Users can delete this data there.

## Common errors

| Symptom | Common cause |
|---|---|
| "Google sign-in canceled" right after choosing an account | Wrong SHA-1, wrong package name, or missing/wrong `GOOGLE_SERVER_CLIENT_ID`. Check each; debug and release builds need different SHA-1 values. |
| "Google sign-in is not configured correctly" | `GOOGLE_SERVER_CLIENT_ID` is not a **Web application** client, or the Drive API is not enabled. |
| Must sign in again after 7 days | The consent screen is still on "Testing": switch to "In production". |
| "Not granted permission to use Google Drive" | The user unchecked the permission on the consent screen: sign in again and allow it. |
| Rate-limit message on a weak network | Drive has temporarily limited requests; the app retries automatically and no data is lost. |

## Known limitations

- Drive has **no conditional write**, so two devices writing at almost the same moment can overwrite each other in a very short window. The app checks the version right before writing and merges on the next sync, so the result converges without losing any item (a test simulates exactly this situation), but it is not as strict as the Cloudflare server.
- Android only. Desktop can sync through a folder (Drive for Desktop) or the Cloudflare server.
- Sync does not run continuously, so it does not exceed quotas: the app only syncs when you return to the app and 3 seconds after each edit; it does not poll.
