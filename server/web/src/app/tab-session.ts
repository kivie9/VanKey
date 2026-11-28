// Giữ trạng thái "đã mở khóa" khi tải lại trang, nhưng chỉ trong tab đó và chỉ tới khi hết thời gian tự khóa.
//
//   sessionStorage (riêng từng tab, mất khi đóng tab): vault key đã mã hóa AES-GCM + hạn dùng
//   IndexedDB: khóa AES-GCM đó, tạo với extractable = false nên JavaScript không đọc ra được byte của nó
//
// Giới hạn đã biết: trình duyệt vẫn lưu khóa này trên đĩa (không qua chip bảo mật của máy). Người lấy được cả hồ sơ
// trình duyệt (profile) trong lúc phiên còn hạn có thể mở được. Vì vậy phiên luôn có hạn ngắn (thời gian tự khóa).
import { buf, fromB64, randomBytes, toB64, utf8 } from '../core/bytes.ts';
import * as db from './db.ts';

const SS_KEY = 'vankey.unlock';
const ORPHAN_MS = 24 * 3600_000;

interface Blob {
  id: string;
  vaultId: string;
  iv: string;
  ct: string;
  expiresAt: number;
  verifiedAt: number;
}
interface KeyRecord {
  key: CryptoKey;
  createdAt: number;
}

function read(): Blob | null {
  try {
    return JSON.parse(sessionStorage.getItem(SS_KEY) ?? 'null') as Blob | null;
  } catch {
    return null;
  }
}

function write(b: Blob): void {
  try {
    sessionStorage.setItem(SS_KEY, JSON.stringify(b));
  } catch {
    // trình duyệt chặn lưu trữ: tải lại trang thì phải mở khóa lại, vẫn dùng được
  }
}

export async function save(vaultKey: Uint8Array, vaultId: string, expiresAt: number, verifiedAt: number): Promise<void> {
  await clear();
  const id = toB64(randomBytes(12));
  const key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
  const iv = randomBytes(12);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: buf(iv), additionalData: buf(utf8(vaultId)) }, key, buf(vaultKey)));
  await db.put(`tab:${id}`, { key, createdAt: Date.now() } satisfies KeyRecord);
  write({ id, vaultId, iv: toB64(iv), ct: toB64(ct), expiresAt, verifiedAt });
}

/** Gia hạn khi người dùng còn thao tác; ghi lại lần xác nhận mật khẩu gần nhất. */
export function update(patch: Partial<Pick<Blob, 'expiresAt' | 'verifiedAt'>>): void {
  const b = read();
  if (b) write({ ...b, ...patch });
}

export async function restore(): Promise<{ vaultKey: Uint8Array; vaultId: string; verifiedAt: number } | null> {
  const b = read();
  if (!b) return null;
  if (b.expiresAt <= Date.now()) {
    await clear();
    return null;
  }
  try {
    const rec = await db.get<KeyRecord>(`tab:${b.id}`);
    if (!rec) throw new Error('mất khóa');
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: buf(fromB64(b.iv)), additionalData: buf(utf8(b.vaultId)) }, rec.key, buf(fromB64(b.ct)));
    return { vaultKey: new Uint8Array(plain), vaultId: b.vaultId, verifiedAt: b.verifiedAt };
  } catch {
    await clear();
    return null;
  }
}

export async function clear(): Promise<void> {
  const b = read();
  try {
    sessionStorage.removeItem(SS_KEY);
  } catch {
    // bỏ qua
  }
  if (b) await db.del(`tab:${b.id}`).catch(() => {});
}

/** Xóa khóa của các tab đã đóng mà chưa kịp dọn (đóng tab không có sự kiện nào chắc chắn chạy). */
export async function cleanupOrphans(): Promise<void> {
  const current = read()?.id;
  for (const k of await db.keys()) {
    if (!k.startsWith('tab:') || k === `tab:${current}`) continue;
    const rec = await db.get<KeyRecord>(k);
    if (!rec || Date.now() - rec.createdAt > ORPHAN_MS) await db.del(k);
  }
}
