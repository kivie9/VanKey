// TOTP (RFC 6238) trên nền HOTP (RFC 4226), HMAC-SHA1 bằng Web Crypto.

const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Decode(text: string): Uint8Array<ArrayBuffer> {
  const clean = text.toUpperCase().replace(/[\s=-]/g, '');
  const out = new Uint8Array(Math.floor((clean.length * 5) / 8));
  let buffer = 0;
  let bits = 0;
  let i = 0;
  for (const ch of clean) {
    const value = BASE32.indexOf(ch);
    if (value < 0) throw new Error(`Ký tự base32 không hợp lệ: ${ch}`);
    buffer = ((buffer << 5) | value) & 0xfff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out[i++] = (buffer >> bits) & 0xff;
    }
  }
  return out;
}

export async function totp(
  secret: Uint8Array<ArrayBuffer>,
  unixSeconds: number,
  digits = 6,
  period = 30,
): Promise<string> {
  const counter = new DataView(new ArrayBuffer(8));
  counter.setBigUint64(0, BigInt(Math.floor(unixSeconds / period)));
  const key = await crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, counter.buffer));
  const offset = mac[mac.length - 1]! & 0x0f;
  const binary = new DataView(mac.buffer).getUint32(offset) & 0x7fffffff;
  return String(binary % 10 ** digits).padStart(digits, '0');
}

/** Số giây còn lại của mã hiện tại (1..period). */
export const secondsLeft = (unixSeconds: number, period = 30): number =>
  period - (Math.floor(unixSeconds) % period);
