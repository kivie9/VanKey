// Đọc file kho `.vkv` theo `docs/technical/vault-format.md` (bản web hiện chỉ ĐỌC, chưa ghi).
import { fromB64, fromUtf8, normalizePassphrase, utf8, wipe } from './bytes.ts';
import { AEAD_NONCE, AEAD_TAG, aeadOpen, hkdfSha256, validateArgon2 } from './crypto.ts';
import type { Argon2Params } from './crypto.ts';
import { VaultError } from './errors.ts';

const MAGIC = [0x56, 0x4b, 0x56, 0x31]; // "VKV1"
const FORMAT_VERSION = 1;
const MAX_HEADER = 64 * 1024;
const MAX_FILE = 16 * 1024 * 1024;
export const SUPPORTED_SCHEMA = 1;

export interface PassphraseSlot {
  id: string;
  type: 'passphrase';
  params: Argon2Params;
  saltB64: string;
  nonce: Uint8Array;
  ct: Uint8Array;
}
export interface RecoverySlot {
  id: string;
  type: 'recovery';
  saltB64: string;
  info: string;
  nonce: Uint8Array;
  ct: Uint8Array;
}

export interface ParsedVault {
  vaultId: string;
  revision: number;
  updatedAt: string;
  passphraseSlots: PassphraseSlot[];
  recoverySlots: RecoverySlot[];
  /** Byte từ magic tới hết header: AAD của phần dữ liệu. */
  aad: Uint8Array;
  nonce: Uint8Array;
  ciphertext: Uint8Array;
}

/** Dữ liệu sau khi giải mã (`vault-format.md` mục 6). Giữ nguyên các trường lạ. */
export interface VaultPayload {
  schema: number;
  groups?: string[];
  items?: Item[];
  tombstones?: unknown[];
  [k: string]: unknown;
}
export interface Field {
  key?: string;
  label?: string;
  value: string;
  secret?: boolean;
  kind?: string;
}
export interface TotpJson {
  secret: string;
  algo?: string;
  digits?: number;
  period?: number;
  kind?: string;
  counter?: number;
}
export interface Item {
  id: string;
  type: string;
  title: string;
  fields?: Field[];
  totp?: TotpJson | null;
  group?: string;
  favorite?: boolean;
  createdAt?: string;
  updatedAt?: string;
  deletedAt?: string | null;
  hlc?: string;
  [k: string]: unknown;
}

function fail(msg: string): never {
  throw new VaultError('corrupt', msg);
}

const str = (v: unknown, what: string): string => (typeof v === 'string' ? v : fail(`${what} không hợp lệ`));
const b64 = (v: unknown, len: number, what: string): Uint8Array => {
  let out: Uint8Array;
  try {
    out = fromB64(str(v, what));
  } catch {
    fail(`${what} không phải base64`);
  }
  return out.length === len ? out : fail(`${what} sai độ dài`);
};

export function parseVault(file: Uint8Array): ParsedVault {
  if (file.length > MAX_FILE) fail('file kho quá lớn');
  if (file.length < 12) fail('file kho quá ngắn');
  for (let i = 0; i < 4; i++) if (file[i] !== MAGIC[i]) fail('không phải file kho VanKey');
  const dv = new DataView(file.buffer, file.byteOffset, file.byteLength);
  const version = dv.getUint16(4);
  const flags = dv.getUint16(6);
  if (version > FORMAT_VERSION || flags !== 0) throw new VaultError('unsupported', 'Kho được tạo bằng phiên bản mới hơn. Hãy cập nhật.');
  if (version < 1) fail('phiên bản file không hợp lệ');
  const h = dv.getUint32(8);
  if (h > MAX_HEADER) fail('header quá lớn');
  if (file.length < 12 + h + AEAD_NONCE + AEAD_TAG) fail('file kho bị cắt cụt');

  let header: Record<string, unknown>;
  try {
    header = JSON.parse(fromUtf8(file.subarray(12, 12 + h)));
  } catch {
    fail('header không đọc được');
  }
  if (typeof header !== 'object' || header === null || Array.isArray(header)) fail('header không hợp lệ');
  if (header.cipher !== undefined && header.cipher !== 'xchacha20poly1305-ietf') throw new VaultError('unsupported', 'Thuật toán mã hóa không hỗ trợ');

  const passphraseSlots: PassphraseSlot[] = [];
  const recoverySlots: RecoverySlot[] = [];
  const slots = Array.isArray(header.keyslots) ? header.keyslots : fail('thiếu keyslots');
  for (const s of slots as Record<string, unknown>[]) {
    if (typeof s !== 'object' || s === null) fail('keyslot không hợp lệ');
    const kdf = (s.kdf ?? {}) as Record<string, unknown>;
    const wrap = (s.wrap ?? {}) as Record<string, unknown>;
    if (s.type === 'passphrase') {
      if (kdf.alg !== 'argon2id13') fail('thuật toán KDF lạ');
      const params = { opslimit: kdf.opslimit as number, memlimitBytes: kdf.memlimit as number };
      validateArgon2(params); // chống hạ tham số và file độc
      const saltB64 = str(kdf.salt, 'salt');
      b64(saltB64, 16, 'salt');
      passphraseSlots.push({ id: str(s.id, 'id slot'), type: 'passphrase', params, saltB64, nonce: b64(wrap.nonce, 24, 'nonce'), ct: b64(wrap.ct, 48, 'wrap') });
    } else if (s.type === 'recovery') {
      if (kdf.alg !== 'hkdf-sha256') fail('thuật toán KDF lạ');
      const saltB64 = str(kdf.salt, 'salt');
      b64(saltB64, 16, 'salt');
      recoverySlots.push({ id: str(s.id, 'id slot'), type: 'recovery', saltB64, info: str(kdf.info, 'info'), nonce: b64(wrap.nonce, 24, 'nonce'), ct: b64(wrap.ct, 48, 'wrap') });
    }
    // Slot loại lạ (bản app mới hơn thêm vào): bỏ qua khi mở.
  }

  return {
    vaultId: str(header.vaultId, 'vaultId'),
    revision: typeof header.revision === 'number' ? header.revision : 0,
    updatedAt: typeof header.updatedAt === 'string' ? header.updatedAt : '',
    passphraseSlots,
    recoverySlots,
    aad: file.subarray(0, 12 + h),
    nonce: file.subarray(12 + h, 12 + h + AEAD_NONCE),
    ciphertext: file.subarray(12 + h + AEAD_NONCE),
  };
}

const passAad = (v: ParsedVault, s: PassphraseSlot) =>
  utf8(`vankey/wrap/v1|${v.vaultId}|${s.id}|passphrase|argon2id13|${s.params.opslimit}|${s.params.memlimitBytes}|${s.saltB64}`);
const recAad = (v: ParsedVault, s: RecoverySlot) => utf8(`vankey/wrap/v1|${v.vaultId}|${s.id}|recovery|hkdf-sha256|${s.saltB64}|${s.info}`);

export type Argon2Fn = (password: Uint8Array, salt: Uint8Array, p: Argon2Params) => Promise<Uint8Array>;

/** Mở bằng passphrase → vault key (32 byte). [kdf]: Argon2id (trong app là bản chạy trong Web Worker). */
export async function unwrapWithPassphrase(v: ParsedVault, passphrase: string, kdf: Argon2Fn): Promise<Uint8Array> {
  if (v.passphraseSlots.length === 0) throw new VaultError('auth', 'Kho này không có slot passphrase');
  const pw = normalizePassphrase(passphrase);
  try {
    for (const s of v.passphraseSlots) {
      const kek = await kdf(pw, fromB64(s.saltB64), s.params);
      try {
        return aeadOpen(kek, s.nonce, s.ct, passAad(v, s));
      } catch {
        // thử slot kế tiếp
      } finally {
        wipe(kek);
      }
    }
  } finally {
    wipe(pw);
  }
  throw new VaultError('auth', 'Sai mật khẩu');
}

const RECOVERY_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Đọc recovery key người dùng nhập (bỏ khoảng trắng, gạch ngang; không phân biệt hoa thường) → 15 byte. */
export function parseRecoveryKey(input: string): Uint8Array {
  const s = input.toUpperCase().replace(/[\s-]/g, '');
  if (s.length !== 24) throw new VaultError('invalid', 'Recovery key phải có 24 ký tự');
  let acc = 0;
  let bits = 0;
  const out: number[] = [];
  for (const ch of s) {
    const idx = RECOVERY_ALPHABET.indexOf(ch);
    if (idx < 0) throw new VaultError('invalid', 'Recovery key có ký tự không hợp lệ');
    acc = (acc << 5) | idx;
    bits += 5;
    while (bits >= 8) {
      bits -= 8;
      out.push((acc >> bits) & 0xff);
      acc &= (1 << bits) - 1;
    }
  }
  return new Uint8Array(out);
}

export async function unwrapWithRecovery(v: ParsedVault, recoveryKey: string): Promise<Uint8Array> {
  const rk = parseRecoveryKey(recoveryKey);
  try {
    for (const s of v.recoverySlots) {
      const kek = await hkdfSha256(rk, fromB64(s.saltB64), utf8(s.info));
      try {
        return aeadOpen(kek, s.nonce, s.ct, recAad(v, s));
      } catch {
        // thử slot kế tiếp
      } finally {
        wipe(kek);
      }
    }
  } finally {
    wipe(rk);
  }
  throw new VaultError('auth', 'Sai recovery key');
}

/** Giải mã phần dữ liệu bằng vault key. Sai khóa hoặc file bị sửa → lỗi `auth`. */
export function decryptPayload(v: ParsedVault, vaultKey: Uint8Array): VaultPayload {
  const plain = aeadOpen(vaultKey, v.nonce, v.ciphertext, v.aad);
  try {
    const p = JSON.parse(fromUtf8(plain)) as VaultPayload;
    if (typeof p !== 'object' || p === null || Array.isArray(p)) fail('dữ liệu kho không hợp lệ');
    const schema = typeof p.schema === 'number' ? p.schema : 1;
    if (schema > SUPPORTED_SCHEMA) throw new VaultError('unsupported', 'Kho dùng định dạng dữ liệu mới hơn. Hãy cập nhật.');
    return p;
  } catch (e) {
    if (e instanceof VaultError) throw e;
    fail('dữ liệu kho không đọc được');
  } finally {
    wipe(plain);
  }
}
