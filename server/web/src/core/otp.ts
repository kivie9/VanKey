// TOTP (RFC 6238), HOTP (RFC 4226) và Steam Guard, khớp `app/lib/core/totp/totp.dart`. HMAC chạy bằng WebCrypto.
import { buf } from './bytes.ts';
import type { TotpJson } from './vault.ts';

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const STEAM = '23456789BCDFGHJKMNPQRTVWXY';

export function base32Decode(input: string): Uint8Array {
  const s = input.toUpperCase().replace(/[\s=-]/g, '');
  if (!s) throw new Error('khóa rỗng');
  let acc = 0;
  let bits = 0;
  const out: number[] = [];
  for (const ch of s) {
    const idx = B32.indexOf(ch);
    if (idx < 0) throw new Error('khóa có ký tự không hợp lệ');
    acc = (acc << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((acc >> bits) & 0xff);
      acc &= (1 << bits) - 1;
    }
  }
  return new Uint8Array(out);
}

const HASH: Record<string, string> = { SHA1: 'SHA-1', SHA256: 'SHA-256', SHA512: 'SHA-512' };

async function hmacTruncate(secret: Uint8Array, counter: number, algo: string): Promise<number> {
  const msg = new Uint8Array(8);
  new DataView(msg.buffer).setBigUint64(0, BigInt(counter));
  const key = await crypto.subtle.importKey('raw', buf(secret), { name: 'HMAC', hash: HASH[algo] ?? 'SHA-1' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, msg));
  const off = mac[mac.length - 1] & 0x0f;
  return ((mac[off] & 0x7f) << 24) | (mac[off + 1] << 16) | (mac[off + 2] << 8) | mac[off + 3];
}

export interface OtpState {
  code: string;
  /** Giây còn lại của chu kỳ (TOTP/Steam); HOTP thì `null`. */
  remaining: number | null;
  period: number;
}

/** Mã hiện tại của một mục. [nowMs] = Date.now(). */
export async function otpCode(t: TotpJson, nowMs: number): Promise<OtpState> {
  const secret = base32Decode(t.secret);
  const algo = (t.algo ?? 'SHA1').toUpperCase();
  const digits = Math.min(8, Math.max(6, t.digits ?? 6));
  const period = t.period && t.period >= 1 && t.period <= 3600 ? t.period : 30;
  const seconds = Math.floor(nowMs / 1000);
  try {
    if (t.kind === 'hotp') {
      const bin = await hmacTruncate(secret, t.counter ?? 0, algo);
      return { code: String(bin % 10 ** digits).padStart(digits, '0'), remaining: null, period };
    }
    const counter = Math.floor(seconds / period);
    const remaining = period - (seconds % period);
    if (t.kind === 'steam') {
      let bin = await hmacTruncate(secret, counter, 'SHA1');
      let code = '';
      for (let i = 0; i < 5; i++) {
        code += STEAM[bin % STEAM.length];
        bin = Math.floor(bin / STEAM.length);
      }
      return { code, remaining, period };
    }
    const bin = await hmacTruncate(secret, counter, algo);
    return { code: String(bin % 10 ** digits).padStart(digits, '0'), remaining, period };
  } finally {
    secret.fill(0);
  }
}
