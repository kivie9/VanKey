import { fromB64url } from './util.ts';

export interface Jwk {
  kid: string;
  kty: string;
  alg?: string;
  n: string;
  e: string;
}

export interface GoogleIdentity {
  email: string;
  sub: string;
}

/** Tải bộ khóa công khai của Google. Đưa vào từ ngoài để test không cần mạng. */
export type JwksFetcher = () => Promise<Jwk[]>;

export const GOOGLE_JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

export async function fetchGoogleJwks(): Promise<Jwk[]> {
  const res = await fetch(GOOGLE_JWKS_URL);
  if (!res.ok) throw new Error(`jwks ${res.status}`);
  const body = (await res.json()) as { keys: Jwk[] };
  return body.keys;
}

function part(s: string): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(fromB64url(s))) as Record<string, unknown>;
}

/**
 * Xác minh ID token của Google: chữ ký RS256 theo JWKS, `iss`, `aud` (phải là client ID của ta), `exp`, `email_verified`.
 * Trả về null nếu bất kỳ điều kiện nào không đạt.
 */
export async function verifyGoogleIdToken(
  idToken: string,
  opts: { audiences: string[]; now: number; jwks: JwksFetcher },
): Promise<GoogleIdentity | null> {
  try {
    const [h, p, s] = idToken.split('.');
    if (!h || !p || !s) return null;
    const header = part(h);
    const claims = part(p);
    if (header.alg !== 'RS256' || typeof header.kid !== 'string') return null;

    const keys = await opts.jwks();
    const jwk = keys.find((k) => k.kid === header.kid);
    if (!jwk || jwk.kty !== 'RSA') return null;
    const key = await crypto.subtle.importKey(
      'jwk',
      { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    const data = new TextEncoder().encode(`${h}.${p}`);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, fromB64url(s) as BufferSource, data as BufferSource);
    if (!ok) return null;

    if (claims.iss !== 'accounts.google.com' && claims.iss !== 'https://accounts.google.com') return null;
    if (typeof claims.aud !== 'string' || !opts.audiences.includes(claims.aud)) return null;
    if (typeof claims.exp !== 'number' || claims.exp <= opts.now) return null;
    if (claims.email_verified !== true && claims.email_verified !== 'true') return null;
    if (typeof claims.email !== 'string' || typeof claims.sub !== 'string') return null;
    return { email: claims.email.trim().toLowerCase(), sub: claims.sub };
  } catch {
    return null;
  }
}
