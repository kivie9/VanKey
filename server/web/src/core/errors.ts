export type VaultErrorCode = 'corrupt' | 'unsupported' | 'weak_kdf' | 'auth' | 'invalid';

export class VaultError extends Error {
  readonly code: VaultErrorCode;
  constructor(code: VaultErrorCode, message: string) {
    super(message);
    this.code = code;
    this.name = 'VaultError';
  }
}
