# VanKey Server (Cloudflare Worker + D1)

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/kivie9/VanKey/tree/main/server)

Click the button above to create the Worker and the D1 database in your Cloudflare account. It asks for `TOKEN_SECRET` and `REGISTER_CODE` (see `.dev.vars.example`). After deploying, run `npx wrangler d1 migrations apply vankey --remote` to create the tables.

The server **only stores the encrypted vault** and sign-in information. It can never read your passwords, 2FA codes or vault content.
Runs for free on Cloudflare's free plan. One server can serve many users (200 accounts by default).

## How it works

- Sign in with a **username + password**. Usernames are 3 to 32 characters: lowercase letters, digits, dots, underscores, hyphens. The app derives a key from the password with Argon2id and sends only that key; the server hashes it again with PBKDF2 before storing it. The original password never leaves the device.
- **One password for both the account and the vault.** The key that opens the vault is derived separately on the app side (different salt, stored in the vault file), so the sign-in key kept by the server cannot open the vault.
- **Open registration:** anyone can create an account, with limits to protect the free quota: up to `MAX_USERS` accounts (default 200), each IP can register up to 10 times (then locked for 1 hour), each account can have up to 20 devices (the least recently used device is removed).
- **Invite code (optional):** set the `REGISTER_CODE` secret (at least 12 characters) and account creation requires the exact code. Use it to invite people privately, or to close registration temporarily (set a code nobody knows). A code shorter than 12 characters closes registration.
- Access tokens last 15 minutes; refresh tokens **rotate** on every use, and the server stores only their hashes. Each token lasts 90 days from sign-in and is **not extended** on rotation. Removing a device takes effect immediately.
- **Detecting a leaked token:** if an old refresh token (already replaced) is used **more than 60 seconds** later, the server removes that device and the real device must sign in again. During the first 60 seconds, a just-replaced token is still issued once more (migration `0006`): this covers a device that resends because a network response was lost, or two parallel refresh requests, so the user is not signed out.
- After 5 consecutive failed sign-ins (or wrong invite codes) from one IP, the IP is locked with increasing delays (30 seconds, doubling each time, up to 15 minutes); IPv6 is grouped by /64. Per-account limits are higher (20 attempts), but an account lock lasts at most 1 minute. Counters are updated atomically, non-existent usernames do not create new database rows, and old rows are cleaned up.
- **A real IP is required:** the server takes the IP from the `cf-connecting-ip` header. If the header is missing, registration, sign-in and password change return a 500 `misconfigured` error instead of putting everyone into one shared lock. On Cloudflare this header is always present. If you run the server behind another proxy, that proxy must set this header (and only from the outside, so clients cannot send it themselves). The local test server `dev/serve.ts` takes the IP from the socket.
- Vault writes use `If-Match`: if another device has written first, the server returns 409 and the app merges and retries automatically.

## Local testing (no Cloudflare needed)

You only need Node 22.6+ (no packages to install):

```powershell
cd server
node dev/serve.ts 8787          # stored in memory, lost when stopped
node --test test/server.test.ts test/d1.test.ts    # 40 tests, including real SQL on SQLite
```

The app points to `http://127.0.0.1:8787` (or `http://10.0.2.2:8787` from the Android emulator). The `http://` address is only accepted for local machines.
The test server allows open registration. To test with an invite code, set the `REGISTER_CODE` environment variable (at least 12 characters).

## Deploying to Cloudflare (one-time setup)

You need a Cloudflare account (free) and Node.

1. Install the tools and sign in:
   ```powershell
   cd server
   npm install
   npx wrangler login
   ```
2. Create the database and paste the printed `database_id` into `wrangler.toml`:
   ```powershell
   npx wrangler d1 create vankey
   ```
3. Create the tables (run again after each server update that includes a new migration, **before** deploying):
   ```powershell
   npm run db:migrate
   ```
4. Set the token signing secret (a random string of at least 32 characters; **store it somewhere safe**; changing it makes every device sign in again):
   ```powershell
   npx wrangler secret put TOKEN_SECRET
   ```
5. (Optional) set an invite code to restrict registration:
   ```powershell
   npx wrangler secret put REGISTER_CODE
   ```
6. Deploy:
   ```powershell
   npm run deploy
   ```
   Wrangler prints an address like `https://vankey.<your-account>.workers.dev`. Opening it in a browser should show `{"ok":true,"service":"vankey"}`.
7. In the app, on the first screen choose **Self-host (self-host)**, enter the address from step 6, then choose *Create account* (enter the invite code if you set one).
8. On a second device: choose **Self-host** again, enter the address and *Sign in* with the same username and password. The vault opens automatically.

### Alternative: deploy through Git (Workers Builds in the Cloudflare dashboard)

Use this when you want Cloudflare to build and deploy automatically on every push to GitHub, instead of running `wrangler` on your computer.

**Preparation (before clicking Deploy):**

1. Dashboard → Storage & Databases → D1 → *Create database*, name it `vankey`, copy the `database_id`.
2. Edit `wrangler.toml` in the repo: `database_id` = the id you copied. Commit and push.

**"Set up your application" screen:**

| Field | Value |
|---|---|
| Project name | `vankey` (must match `name` in `wrangler.toml`) |
| Root directory (under Advanced settings) | `server` (the Worker is in a subfolder, not the repo root) |
| Build command | leave empty |
| Deploy command | `npx wrangler d1 migrations apply vankey --remote && npx wrangler deploy` |
| Preview command | leave as `npx wrangler preview` |

The deploy command above creates the tables and then deploys; migrations that were already applied are skipped, so running it again is safe.

**After the first deployment:**

1. Workers & Pages → `vankey` → Settings → Variables and Secrets → Add, type **Secret**, name `TOKEN_SECRET`, value a random string of at least 32 characters (store it safely), then Deploy to apply. Without this secret, the server cannot sign anyone in. To use invite codes, add the `REGISTER_CODE` secret in the same way.
2. Open `https://vankey.<your-account>.workers.dev`; it should show `{"ok":true,"service":"vankey"}`.
3. Connect the app as in step 7 above.

**Common errors:** no `wrangler.toml` found means the Root directory is not set to `server`; a `database_id` error means the real id was not pasted and pushed.

### Updating from the email-based version

The old version signed in with email and an `ALLOWED_EMAILS` list. Migration `0003` renamed the `email` column to `username` and kept the data, but new usernames must follow the rules above: old accounts with an `@` in the name can no longer sign in (the app requires a valid username). If you have such an account, create a new account with a valid username and import the vault from a backup file.

### Password change, account deletion, hash iterations (migration `0004`)

- `POST /auth/password` `{authKey, newAuthKey}` (token required): changes the account password. The correct current password is required; wrong attempts are counted and locked like sign-in. All other devices of the account are removed. The app calls this API when you change the password in Settings, before changing it on the device.
- `DELETE /account` `{authKey}` (token required): permanently deletes the account, the vault and all devices. Cannot be undone. In the app: Sync → Delete account.
- New accounts hash the authKey with PBKDF2 at `5000` iterations instead of `100000` (100000 iterations exceeds the free plan's 10 ms CPU limit). The authKey has already been through Argon2id on the device, so it is not weakened. Old accounts are re-hashed automatically the next time they sign in.
- Run `npx wrangler d1 migrations apply vankey --remote` before deploying (adds the `kdf_iter` column).

## Known limitations

- D1 limits each row to about 2 MB, so a vault can be at most 1.5 MB (a few thousand items). Beyond that, the server returns 413; the future solution is R2.
- Rate limits are stored in D1 (per IP and per account); Cloudflare's rate limiting feature is not used. On the `workers.dev` domain, WAF rules are not available.
- Because registration is open, strangers can create accounts until `MAX_USERS` is reached. To block it completely, set `REGISTER_CODE`.
- The D1 part has been checked with real SQLite and the actual migration files, but has not yet been run on Cloudflare's real D1 with this open-registration version.
