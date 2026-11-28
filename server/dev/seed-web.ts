// Tạo tài khoản thử `demo.web` trên server local và tải lên file kho mẫu (app/test/vectors/web-v1.json),
// để xem bản web mà không cần app.
//   node dev/serve.ts 8787        (cửa sổ khác)
//   node dev/seed-web.ts [http://127.0.0.1:8787]
// Mật khẩu = `vault.passphraseNfd` trong file vector (dùng chung cho tài khoản và kho). Dữ liệu thử, không phải bí mật thật.
import { readFileSync } from 'node:fs';
import { argon2id } from '../web/src/core/argon2.ts';
import { deriveAuthKey } from '../web/src/core/auth.ts';

const base = process.argv[2] ?? 'http://127.0.0.1:8787';
const v = JSON.parse(readFileSync(new URL('../../app/test/vectors/web-v1.json', import.meta.url), 'utf8'));
const username = 'demo.web';
const authKey = await deriveAuthKey(username, v.vault.passphraseNfd, argon2id);

let r = await fetch(`${base}/auth/register`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ username, authKey, deviceName: 'seed', registerCode: process.env.REGISTER_CODE ?? '', termsVersion: '2026-11-27' }),
});
if (r.status !== 200) throw new Error(`đăng ký lỗi ${r.status}: ${await r.text()}`);
const s = await r.json();
r = await fetch(`${base}/vault`, {
  method: 'PUT',
  headers: { authorization: `Bearer ${s.accessToken}`, 'if-none-match': '*', 'content-type': 'application/octet-stream' },
  body: Buffer.from(v.vault.fileB64, 'base64'),
});
if (r.status !== 200) throw new Error(`tải kho lỗi ${r.status}: ${await r.text()}`);
console.log(`Đã tạo ${username} với kho mẫu. Mở ${base}/app/`);
