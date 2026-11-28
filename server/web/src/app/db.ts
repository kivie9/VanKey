// Lưu trên máy bằng IndexedDB. Chỉ có dữ liệu đã mã hóa:
//   vault   : file kho `.vkv` nguyên vẹn (đã mã hóa) + etag lần đồng bộ gần nhất
//   session : refresh token, được niêm phong bằng khóa dẫn xuất từ vault key, nên không mở kho thì cũng không dùng được
//   profile : tên đăng nhập (để điền sẵn), không bí mật
//   tab:*   : khóa AES không xuất ra được, giữ phiên mở khóa của từng tab khi tải lại trang (xem tab-session.ts)
const DB_NAME = 'vankey';
const STORE = 'kv';

export interface StoredVault {
  bytes: Uint8Array;
  etag: string;
  syncedAt: number;
}
export interface StoredSession {
  vaultId: string;
  nonce: Uint8Array;
  sealed: Uint8Array;
}
export interface Profile {
  username: string;
}

let dbp: Promise<IDBDatabase> | null = null;

function open(): Promise<IDBDatabase> {
  dbp ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbp;
}

async function tx<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T> | void): Promise<T | undefined> {
  const db = await open();
  return new Promise((resolve, reject) => {
    const t = db.transaction(STORE, mode);
    const r = fn(t.objectStore(STORE));
    t.oncomplete = () => resolve(r ? r.result : undefined);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}

export const get = <T>(key: string) => tx<T>('readonly', (s) => s.get(key) as IDBRequest<T>);
export const put = (key: string, value: unknown) => tx('readwrite', (s) => void s.put(value, key));
export const del = (key: string) => tx('readwrite', (s) => void s.delete(key));
export const clearAll = () => tx('readwrite', (s) => void s.clear());
export const keys = async (): Promise<string[]> => ((await tx('readonly', (s) => s.getAllKeys())) ?? []).map(String);

/** Xin trình duyệt giữ dữ liệu lâu dài (không tự xóa khi thiếu chỗ). Safari vẫn có thể xóa nếu lâu không mở. */
export async function requestPersist(): Promise<boolean> {
  try {
    return (await navigator.storage?.persisted?.()) || ((await navigator.storage?.persist?.()) ?? false);
  } catch {
    return false;
  }
}
