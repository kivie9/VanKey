// Gọi API của chính Worker này (cùng origin, nên không cần CORS). Khớp `server/src/handler.ts`.

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly retryAfter?: number;
  constructor(status: number, code: string, message: string, retryAfter?: number) {
    super(message);
    this.status = status;
    this.code = code;
    this.retryAfter = retryAfter;
  }
}

export class NetworkError extends Error {}

export interface Session {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  deviceId: string;
  accountId: string;
  username: string;
}

const TIMEOUT_MS = 20_000;

async function call(path: string, init: RequestInit): Promise<Response> {
  try {
    return await fetch(path, { ...init, cache: 'no-store', credentials: 'omit', signal: AbortSignal.timeout(TIMEOUT_MS) });
  } catch {
    throw new NetworkError('Không kết nối được máy chủ');
  }
}

async function toError(res: Response): Promise<ApiError> {
  try {
    const j = await res.json();
    return new ApiError(res.status, String(j.error ?? 'error'), String(j.message ?? `Máy chủ trả về lỗi ${res.status}`), j.retryAfter);
  } catch {
    return new ApiError(res.status, 'error', `Máy chủ trả về lỗi ${res.status}`);
  }
}

async function postJson<T>(path: string, body: unknown, token?: string): Promise<T> {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await call(path, { method: 'POST', headers, body: JSON.stringify(body) });
  if (!res.ok) throw await toError(res);
  return (res.status === 204 ? undefined : await res.json()) as T;
}

export const login = (username: string, authKey: string, deviceName: string) =>
  postJson<Session>('/auth/login', { username, authKey, deviceName });

export const refresh = (refreshToken: string) => postJson<Session>('/auth/refresh', { refreshToken });

export const logout = (accessToken: string) => postJson<void>('/auth/logout', {}, accessToken);

export type VaultFetch = { status: 'ok'; bytes: Uint8Array; etag: string } | { status: 'unchanged' } | { status: 'none' };

export async function getVault(accessToken: string, etag?: string): Promise<VaultFetch> {
  const headers: Record<string, string> = { authorization: `Bearer ${accessToken}` };
  if (etag) headers['if-none-match'] = etag;
  const res = await call('/vault', { method: 'GET', headers });
  if (res.status === 304) return { status: 'unchanged' };
  if (res.status === 404) return { status: 'none' };
  if (!res.ok) throw await toError(res);
  return { status: 'ok', bytes: new Uint8Array(await res.arrayBuffer()), etag: res.headers.get('etag') ?? '' };
}

/** Tên thiết bị hiện trong danh sách thiết bị của tài khoản. */
export function deviceName(): string {
  const ua = navigator.userAgent;
  const browser = /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox' : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : 'Trình duyệt';
  const os = /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS' : /Windows/.test(ua) ? 'Windows' : /Mac OS/.test(ua) ? 'macOS' : /Linux/.test(ua) ? 'Linux' : '';
  return `Web · ${browser}${os ? ` · ${os}` : ''}`;
}
