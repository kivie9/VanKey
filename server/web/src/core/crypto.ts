// Nguyên thủy mật mã, khớp byte-đối-byte với bản Dart (`app/lib/core/crypto/`) và libsodium.
//   Argon2id  : argon2.ts (hash-wasm), chạy trong Web Worker
//   AEAD      : XChaCha20-Poly1305-IETF, @noble/ciphers (đã được audit độc lập)
//   HKDF/SHA  : WebCrypto có sẵn của trình duyệt
import { xchacha20poly1305 } from '@noble/ciphers/chacha.js';
import { buf } from './bytes.ts';
import { VaultError } from './errors.ts';

export interface Argon2Params {
  opslimit: number;
  memlimitBytes: number;
}

export const ARGON2_STANDARD: Argon2Params = { opslimit: 3, memlimitBytes: 64 * 1024 * 1024 };
const MIN_OPS = 2;
const MAX_OPS = 20;
const MIN_MEM = 32 * 1024 * 1024;
const MAX_MEM = 1024 * 1024 * 1024;

export function validateArgon2(p: Argon2Params): void {
  const okOps = Number.isInteger(p.opslimit) && p.opslimit >= MIN_OPS && p.opslimit <= MAX_OPS;
  const okMem = Number.isInteger(p.memlimitBytes) && p.memlimitBytes >= MIN_MEM && p.memlimitBytes <= MAX_MEM && p.memlimitBytes % 1024 === 0;
  if (!okOps || !okMem) throw new VaultError('weak_kdf', 'Tham số Argon2id nằm ngoài khoảng cho phép');
}

export const AEAD_NONCE = 24;
export const AEAD_TAG = 16;

export function aeadSeal(key: Uint8Array, nonce: Uint8Array, plaintext: Uint8Array, aad?: Uint8Array): Uint8Array {
  if (key.length !== 32 || nonce.length !== AEAD_NONCE) throw new VaultError('invalid', 'khóa hoặc nonce sai độ dài');
  return xchacha20poly1305(key, nonce, aad).encrypt(plaintext);
}

/** Giải mã và xác thực. Sai bất cứ thứ gì → lỗi `auth`, không bao giờ trả dữ liệu một phần. */
export function aeadOpen(key: Uint8Array, nonce: Uint8Array, sealed: Uint8Array, aad?: Uint8Array): Uint8Array {
  if (key.length !== 32 || nonce.length !== AEAD_NONCE) throw new VaultError('invalid', 'khóa hoặc nonce sai độ dài');
  if (sealed.length < AEAD_TAG) throw new VaultError('corrupt', 'dữ liệu mã hóa quá ngắn');
  try {
    return xchacha20poly1305(key, nonce, aad).decrypt(sealed);
  } catch {
    throw new VaultError('auth', 'Sai khóa hoặc dữ liệu đã bị sửa');
  }
}

export async function hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array, length = 32): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey('raw', buf(ikm), 'HKDF', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: buf(salt), info: buf(info) }, k, length * 8);
  return new Uint8Array(bits);
}

export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', buf(data)));
}
