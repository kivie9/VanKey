import type { Argon2Params } from '../core/crypto.ts';
import type { Argon2Fn } from '../core/vault.ts';

declare const __KDF_WORKER__: string;

let worker: Worker | null = null;
let seq = 0;
const pending = new Map<number, { resolve: (k: Uint8Array) => void; reject: (e: Error) => void }>();

function getWorker(): Worker {
  if (worker) return worker;
  worker = new Worker(__KDF_WORKER__);
  worker.onmessage = (e: MessageEvent<{ id: number; key?: Uint8Array; error?: string }>) => {
    const p = pending.get(e.data.id);
    if (!p) return;
    pending.delete(e.data.id);
    if (e.data.key) p.resolve(e.data.key);
    else p.reject(new Error(e.data.error ?? 'Argon2id lỗi'));
  };
  return worker;
}

/** Argon2id qua Web Worker. Mật khẩu được chép sang worker rồi bị xóa ở cả hai phía. */
export const workerArgon2: Argon2Fn = (password: Uint8Array, salt: Uint8Array, params: Argon2Params) =>
  new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, reject });
    const pw = password.slice();
    getWorker().postMessage({ id, password: pw, salt, params }, [pw.buffer]);
  });

/** Nạp sẵn worker (và WASM bên trong) để lần mở kho đầu tiên không phải chờ. */
export function warmUpKdf(): void {
  getWorker();
}
