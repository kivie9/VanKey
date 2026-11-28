// Argon2id chạy trong Web Worker riêng để giao diện không bị đứng (khoảng 0,3 giây với 64 MiB trên PC).
import { argon2id } from './core/argon2.ts';
import type { Argon2Params } from './core/crypto.ts';

interface Req {
  id: number;
  password: Uint8Array;
  salt: Uint8Array;
  params: Argon2Params;
}

self.onmessage = async (e: MessageEvent<Req>) => {
  const { id, password, salt, params } = e.data;
  try {
    const key = await argon2id(password, salt, params);
    (self as unknown as Worker).postMessage({ id, key }, [key.buffer]);
  } catch (err) {
    (self as unknown as Worker).postMessage({ id, error: err instanceof Error ? err.message : 'lỗi' });
  } finally {
    password.fill(0);
  }
};
