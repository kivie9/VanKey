// Khóa đăng nhập Cloudflare, khớp `CloudflareApi.deriveAuthKey` trong `app/lib/core/sync/cloudflare_sync.dart`.
// Máy chủ chỉ thấy khóa này; khóa mở kho dẫn xuất riêng (salt khác, nằm trong file kho).
import { bytesEqual, normalizePassphrase, toB64, utf8, wipe } from './bytes.ts';
import { ARGON2_STANDARD, sha256 } from './crypto.ts';
import type { Argon2Fn } from './vault.ts';

async function authSalt(username: string): Promise<Uint8Array> {
  return (await sha256(utf8(`vankey-auth-v1|${username.trim().toLowerCase()}`))).subarray(0, 16);
}

async function derive(username: string, pw: Uint8Array, kdf: Argon2Fn): Promise<string> {
  const key = await kdf(pw, await authSalt(username), ARGON2_STANDARD);
  try {
    return toB64(key);
  } finally {
    wipe(key, pw);
  }
}

export const deriveAuthKey = (username: string, password: string, kdf: Argon2Fn) =>
  derive(username, normalizePassphrase(password), kdf);

/** Khóa kiểu cũ (chưa chuẩn hóa NFKC), chỉ để đăng nhập tài khoản tạo trước khi có chuẩn hóa. */
export const deriveLegacyAuthKey = (username: string, password: string, kdf: Argon2Fn) => derive(username, utf8(password), kdf);

export const hasLegacyAuthKey = (password: string) => !bytesEqual(normalizePassphrase(password), utf8(password));
