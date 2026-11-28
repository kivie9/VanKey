// Argon2id bằng hash-wasm (WASM), parallelism = 1. Tách riêng để chỉ worker phải tải WASM này.
import { argon2id as hwArgon2id } from 'hash-wasm';
import { validateArgon2 } from './crypto.ts';
import type { Argon2Params } from './crypto.ts';
import { VaultError } from './errors.ts';

export async function argon2id(password: Uint8Array, salt: Uint8Array, p: Argon2Params): Promise<Uint8Array> {
  validateArgon2(p);
  if (salt.length !== 16) throw new VaultError('invalid', 'salt phải dài 16 byte');
  return hwArgon2id({
    password,
    salt,
    parallelism: 1,
    iterations: p.opslimit,
    memorySize: p.memlimitBytes / 1024,
    hashLength: 32,
    outputType: 'binary',
  });
}
