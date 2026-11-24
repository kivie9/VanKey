import { fromB64url, hmacSha256, timingSafeEqual, toB64url, utf8 } from './util.ts';

export interface AccessClaims {
  /** id người dùng */
  sub: string;
  /** id thiết bị */
  dev: string;
  /** hạn dùng, giây UNIX */
  exp: number;
}

/** Access token ngắn hạn: `payload.chữ_ký`, ký HMAC-SHA256 bằng bí mật của server. */
export async function signAccess(secret: Uint8Array, claims: AccessClaims): Promise<string> {
  const payload = toB64url(utf8(JSON.stringify(claims)));
  const sig = toB64url(await hmacSha256(secret, utf8(payload)));
  return `${payload}.${sig}`;
}

export async function verifyAccess(secret: Uint8Array, token: string, now: number): Promise<AccessClaims | null> {
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [payload, sig] = parts;
  let given: Uint8Array;
  try {
    given = fromB64url(sig);
  } catch {
    return null;
  }
  const expected = await hmacSha256(secret, utf8(payload));
  if (!timingSafeEqual(given, expected)) return null;
  try {
    const claims = JSON.parse(new TextDecoder().decode(fromB64url(payload))) as AccessClaims;
    if (typeof claims.sub !== 'string' || typeof claims.dev !== 'string' || typeof claims.exp !== 'number') return null;
    if (claims.exp <= now) return null;
    return claims;
  } catch {
    return null;
  }
}
