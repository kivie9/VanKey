// Tiện ích byte dùng chung. Không phụ thuộc DOM nên chạy được cả trong trình duyệt, Web Worker và Node (test).

export const utf8 = (s: string): Uint8Array => new TextEncoder().encode(s);
export const fromUtf8 = (b: Uint8Array): string => new TextDecoder('utf-8', { fatal: true }).decode(b);

/** Base64 chuẩn, có padding (đúng như `vault-format.md` mục 5). */
export function toB64(b: Uint8Array): string {
  let s = '';
  for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000));
  return btoa(s);
}

export function fromB64(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

/** Ghi đè 0 (mức cố gắng tối đa: JS không bảo đảm xóa hết bản sao trong bộ nhớ). */
export function wipe(...arrs: (Uint8Array | null | undefined)[]): void {
  for (const a of arrs) a?.fill(0);
}

export function randomBytes(n: number): Uint8Array {
  const out = new Uint8Array(n);
  crypto.getRandomValues(out);
  return out;
}

/** Chuẩn hóa passphrase: Unicode NFKC rồi UTF-8 (`vault-format.md` mục 3.1). */
export const normalizePassphrase = (p: string): Uint8Array => utf8(p.normalize('NFKC'));

export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

/** WebCrypto đòi `BufferSource` gắn với ArrayBuffer thường; bản sao này tránh lỗi kiểu với SharedArrayBuffer. */
export const buf = (b: Uint8Array): Uint8Array<ArrayBuffer> => new Uint8Array(b);
