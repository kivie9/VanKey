// Trạng thái của bản web: đăng nhập, mở khóa, đồng bộ (chỉ tải về) và tự khóa.
// Bản web hiện CHỈ ĐỌC: không bao giờ ghi kho lên máy chủ, nên không thể làm hỏng dữ liệu của các thiết bị khác.
import { bytesEqual, fromUtf8, randomBytes, utf8, wipe } from '../core/bytes.ts';
import { aeadOpen, aeadSeal, hkdfSha256 } from '../core/crypto.ts';
import { deriveAuthKey, deriveLegacyAuthKey, hasLegacyAuthKey } from '../core/auth.ts';
import { VaultError } from '../core/errors.ts';
import { decryptPayload, parseVault, unwrapWithPassphrase, unwrapWithRecovery } from '../core/vault.ts';
import type { ParsedVault, VaultPayload } from '../core/vault.ts';
import { ApiError, NetworkError, deviceName, getVault, login, logout, refresh } from './api.ts';
import type { Session } from './api.ts';
import * as db from './db.ts';
import type { Profile, StoredSession, StoredVault } from './db.ts';
import { workerArgon2 } from './kdf.ts';
import * as tabSession from './tab-session.ts';

export type Phase = 'loading' | 'login' | 'locked' | 'unlocked';

export interface State {
  phase: Phase;
  username: string;
  busy: boolean;
  error: string;
  notice: string;
  payload: VaultPayload | null;
  syncing: boolean;
  syncedAt: number;
  online: boolean;
  /** Phiên đăng nhập đã hết hoặc thiết bị bị gỡ: dữ liệu trên máy vẫn mở được, nhưng không đồng bộ được nữa. */
  signedOut: boolean;
  /** Lần đồng bộ gần nhất không gọi được máy chủ (mất mạng hoặc máy chủ không trả lời). */
  unreachable: boolean;
  /** Đang hỏi lại mật khẩu trước khi xem hoặc sao chép mật khẩu. */
  verifying: boolean;
  verifyBusy: boolean;
  verifyError: string;
}

interface Tokens {
  deviceId: string;
  refreshToken: string;
  accessToken: string;
  expiresAt: number;
}

const SESSION_INFO = utf8('vankey/web/session/v1');
/** Không thao tác chừng này thì khóa (kể cả khi tải lại trang). Đóng tab thì khóa ngay. */
export const IDLE_LOCK_MS = 15 * 60_000;
/** Xem hoặc sao chép mật khẩu: đã nhập mật khẩu trong chừng này thì không hỏi lại. */
const REVERIFY_MS = 2 * 60_000;

let state: State = {
  phase: 'loading',
  username: '',
  busy: false,
  error: '',
  notice: '',
  payload: null,
  syncing: false,
  syncedAt: 0,
  online: navigator.onLine,
  signedOut: false,
  unreachable: false,
  verifying: false,
  verifyBusy: false,
  verifyError: '',
};
const listeners = new Set<() => void>();

export const getState = () => state;
export function subscribe(fn: () => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
function set(patch: Partial<State>): void {
  state = { ...state, ...patch };
  for (const l of listeners) l();
}

// Khóa đang mở: chỉ nằm trong bộ nhớ, bị ghi đè 0 khi khóa.
let vaultKey: Uint8Array | null = null;
let vaultId = '';
/** Phiên vừa đăng nhập nhưng mật khẩu kho khác mật khẩu tài khoản: giữ tạm trong bộ nhớ tới khi mở được kho. */
let pendingTokens: Tokens | null = null;
/** Lần gần nhất người dùng nhập đúng mật khẩu (hoặc recovery key). */
let verifiedAt = 0;
let lastActivity = 0;

function message(e: unknown): string {
  if (e instanceof VaultError) return e.message;
  if (e instanceof ApiError) {
    if (e.code === 'locked' || e.status === 429) return `Thử quá nhiều lần. Đợi ${e.retryAfter ?? 30} giây rồi thử lại.`;
    if (e.status === 401) return 'Sai tên đăng nhập hoặc mật khẩu';
    return e.message;
  }
  if (e instanceof NetworkError) return `Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại. (${e.message})`;
  return `Có lỗi xảy ra (${e instanceof Error ? `${e.name}: ${e.message}` : String(e)})`;
}

// ---------- Phiên đăng nhập, niêm phong bằng khóa dẫn xuất từ vault key ----------

async function sessionKey(key: Uint8Array, id: string): Promise<Uint8Array> {
  return hkdfSha256(key, utf8(id), SESSION_INFO);
}

async function sealTokens(t: Tokens): Promise<void> {
  if (!vaultKey) return;
  const k = await sessionKey(vaultKey, vaultId);
  const nonce = randomBytes(24);
  try {
    const sealed = aeadSeal(k, nonce, utf8(JSON.stringify(t)), utf8(vaultId));
    await db.put('session', { vaultId, nonce, sealed } satisfies StoredSession);
  } finally {
    wipe(k);
  }
}

async function unsealTokens(): Promise<Tokens | null> {
  const s = await db.get<StoredSession>('session');
  if (!s || !vaultKey || s.vaultId !== vaultId) return null;
  const k = await sessionKey(vaultKey, vaultId);
  try {
    return JSON.parse(fromUtf8(aeadOpen(k, s.nonce, s.sealed, utf8(vaultId)))) as Tokens;
  } catch {
    return null;
  } finally {
    wipe(k);
  }
}

const tokensFrom = (s: Session): Tokens => ({ deviceId: s.deviceId, refreshToken: s.refreshToken, accessToken: s.accessToken, expiresAt: Date.now() + s.expiresIn * 1000 });

/**
 * Access token còn hạn, hoặc làm mới. Chạy trong Web Lock để nhiều tab không cùng xoay vòng một refresh token
 * (máy chủ coi việc dùng lại token cũ quá 60 giây là bị lộ và gỡ thiết bị).
 */
async function accessToken(): Promise<string | null> {
  const run = async (): Promise<string | null> => {
    const t = await unsealTokens();
    if (!t) return null;
    if (t.expiresAt - Date.now() > 30_000) return t.accessToken;
    const s = await refresh(t.refreshToken);
    const next = tokensFrom(s);
    await sealTokens(next);
    return next.accessToken;
  };
  return navigator.locks ? navigator.locks.request('vankey-session', run) : run();
}

// ---------- Vòng đời ----------

export async function init(): Promise<void> {
  const [vault, profile] = await Promise.all([db.get<StoredVault>('vault'), db.get<Profile>('profile')]);
  set({ username: profile?.username ?? '', syncedAt: vault?.syncedAt ?? 0 });
  addEventListener('online', () => set({ online: true }));
  addEventListener('offline', () => set({ online: false }));
  setupAutoLock();
  if (vault && (await restoreTab(vault))) void sync();
  else set({ phase: vault ? 'locked' : 'login' });
  void tabSession.cleanupOrphans().catch(() => {});
}

/** Tải lại trang trong lúc phiên còn hạn: mở lại bằng khóa đã giữ trong tab, không hỏi mật khẩu. */
async function restoreTab(vault: StoredVault): Promise<boolean> {
  const r = await tabSession.restore();
  if (!r) return false;
  try {
    const parsed = parseVault(vault.bytes);
    if (parsed.vaultId !== r.vaultId) throw new Error('khác kho');
    const payload = decryptPayload(parsed, r.vaultKey);
    vaultKey = r.vaultKey;
    vaultId = parsed.vaultId;
    verifiedAt = r.verifiedAt;
    set({ phase: 'unlocked', payload });
    touch();
    return true;
  } catch {
    wipe(r.vaultKey);
    await tabSession.clear();
    return false;
  }
}

/** Lần đầu trên trình duyệt này: đăng nhập, tải kho về, mở bằng cùng mật khẩu. */
export async function signIn(username: string, password: string): Promise<void> {
  set({ busy: true, error: '', notice: '' });
  try {
    const name = username.trim().toLowerCase();
    let s: Session;
    try {
      s = await login(name, await deriveAuthKey(name, password, workerArgon2), deviceName());
    } catch (e) {
      if (!(e instanceof ApiError && e.status === 401 && hasLegacyAuthKey(password))) throw e;
      s = await login(name, await deriveLegacyAuthKey(name, password, workerArgon2), deviceName());
    }
    const r = await getVault(s.accessToken);
    if (r.status !== 'ok') {
      await logout(s.accessToken).catch(() => {});
      set({ busy: false, error: 'Tài khoản này chưa có kho trên máy chủ. Hãy bật đồng bộ Cloudflare trong app trước.' });
      return;
    }
    parseVault(r.bytes); // file hỏng thì dừng ở đây, không lưu
    await db.put('vault', { bytes: r.bytes, etag: r.etag, syncedAt: Date.now() } satisfies StoredVault);
    await db.put('profile', { username: name } satisfies Profile);
    void db.requestPersist();
    pendingTokens = tokensFrom(s);
    set({ username: name, syncedAt: Date.now(), signedOut: false });
    try {
      await openLocal((p) => unwrapWithPassphrase(p, password, workerArgon2));
    } catch (e) {
      if (!(e instanceof VaultError && e.code === 'auth')) throw e;
      set({ phase: 'locked', busy: false, error: '', notice: 'Đã tải kho về. Mật khẩu kho khác mật khẩu đăng nhập: nhập mật khẩu kho để mở.' });
    }
  } catch (e) {
    set({ busy: false, error: message(e) });
  }
}

async function openLocal(unwrap: (p: ParsedVault) => Promise<Uint8Array>): Promise<void> {
  const v = await db.get<StoredVault>('vault');
  if (!v) throw new VaultError('corrupt', 'Không thấy kho trên máy');
  const parsed = parseVault(v.bytes);
  const key = await unwrap(parsed);
  const payload = decryptPayload(parsed, key);
  vaultKey = key;
  vaultId = parsed.vaultId;
  verifiedAt = Date.now();
  await tabSession.save(key, vaultId, Date.now() + IDLE_LOCK_MS, verifiedAt).catch(() => {});
  if (pendingTokens) {
    await sealTokens(pendingTokens);
    pendingTokens = null;
  }
  set({ phase: 'unlocked', busy: false, error: '', notice: '', payload });
  touch();
}

export async function unlockWithPassword(password: string): Promise<void> {
  set({ busy: true, error: '' });
  try {
    await openLocal((p) => unwrapWithPassphrase(p, password, workerArgon2));
    void sync(password);
  } catch (e) {
    set({ busy: false, error: message(e) });
  }
}

export async function unlockWithRecovery(recoveryKey: string): Promise<void> {
  set({ busy: true, error: '' });
  try {
    await openLocal((p) => unwrapWithRecovery(p, recoveryKey));
    void sync();
  } catch (e) {
    set({ busy: false, error: message(e) });
  }
}

/**
 * Tải bản mới nhất từ máy chủ (nếu có). [password] chỉ dùng khi kho trên máy chủ đã đổi vault key
 * (ví dụ vừa xoay khóa trên app); không có thì báo cần mở khóa lại.
 */
export async function sync(password?: string): Promise<void> {
  if (!vaultKey || state.syncing) return;
  set({ syncing: true });
  try {
    const token = await accessToken();
    if (!token) {
      set({ signedOut: true });
      return;
    }
    const local = await db.get<StoredVault>('vault');
    const r = await getVault(token, local?.etag);
    if (r.status === 'ok') {
      const parsed = parseVault(r.bytes);
      let payload: VaultPayload;
      try {
        payload = decryptPayload(parsed, vaultKey);
      } catch (e) {
        if (!(e instanceof VaultError && e.code === 'auth')) throw e;
        if (!password) {
          set({ notice: 'Kho trên máy chủ đã đổi khóa. Khóa rồi mở lại bằng mật khẩu để tải bản mới.' });
          return;
        }
        const key = await unwrapWithPassphrase(parsed, password, workerArgon2);
        payload = decryptPayload(parsed, key);
        const old = await unsealTokens();
        wipe(vaultKey);
        vaultKey = key;
        vaultId = parsed.vaultId;
        if (old) await sealTokens(old);
        await tabSession.save(key, vaultId, Date.now() + IDLE_LOCK_MS, verifiedAt).catch(() => {});
      }
      await db.put('vault', { bytes: r.bytes, etag: r.etag, syncedAt: Date.now() } satisfies StoredVault);
      if (state.phase === 'unlocked') set({ payload });
    } else if (local) {
      await db.put('vault', { ...local, syncedAt: Date.now() });
    }
    set({ syncedAt: Date.now(), signedOut: false, unreachable: false });
  } catch (e) {
    if (e instanceof ApiError && (e.status === 401 || e.status === 403)) {
      await db.del('session');
      set({ signedOut: true });
    } else if (e instanceof NetworkError) {
      set({ unreachable: true });
    } else {
      set({ notice: message(e) });
    }
  } finally {
    set({ syncing: false });
  }
}

export function lock(): void {
  wipe(vaultKey);
  vaultKey = null;
  verifiedAt = 0;
  void tabSession.clear();
  verifyResolve?.(false);
  verifyResolve = null;
  set({ phase: 'locked', payload: null, error: '', notice: '', busy: false, verifying: false, verifyBusy: false, verifyError: '' });
  void clearClipboardNow();
}

/** Đăng xuất và xóa mọi dữ liệu của VanKey trên trình duyệt này. */
export async function forgetDevice(): Promise<void> {
  try {
    const t = vaultKey ? await accessToken() : null;
    if (t) await logout(t);
  } catch {
    // vẫn xóa dữ liệu trên máy
  }
  wipe(vaultKey);
  vaultKey = null;
  pendingTokens = null;
  await tabSession.clear();
  await db.clearAll();
  set({ phase: 'login', payload: null, error: '', notice: '', signedOut: false, syncedAt: 0 });
}

export function backToLogin(): void {
  set({ phase: 'login', error: '', notice: '' });
}

// ---------- Tự khóa ----------

let idleTimer = 0;
let savedExpiry = 0;

function touch(): void {
  if (state.phase !== 'unlocked') return;
  lastActivity = Date.now();
  clearTimeout(idleTimer);
  idleTimer = window.setTimeout(lock, IDLE_LOCK_MS);
  // Gia hạn phiên của tab, ghi tối đa 15 giây một lần.
  if (lastActivity - savedExpiry > 15_000) {
    savedExpiry = lastActivity;
    tabSession.update({ expiresAt: lastActivity + IDLE_LOCK_MS });
  }
}

function setupAutoLock(): void {
  for (const ev of ['pointerdown', 'keydown', 'wheel', 'touchstart']) addEventListener(ev, touch, { passive: true });
  // Tab ở nền thì trình duyệt có thể làm chậm bộ hẹn giờ: quay lại thì kiểm tra theo đồng hồ.
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && state.phase === 'unlocked' && Date.now() - lastActivity >= IDLE_LOCK_MS) lock();
  });
}

// ---------- Hỏi lại mật khẩu trước khi xem hoặc sao chép mật khẩu ----------

let verifyResolve: ((ok: boolean) => void) | null = null;

/** `true` nếu được phép xem: vừa nhập mật khẩu gần đây, hoặc người dùng nhập lại đúng. */
export function requestVerify(): Promise<boolean> {
  if (state.phase !== 'unlocked') return Promise.resolve(false);
  if (Date.now() - verifiedAt < REVERIFY_MS) return Promise.resolve(true);
  verifyResolve?.(false);
  set({ verifying: true, verifyBusy: false, verifyError: '' });
  return new Promise((resolve) => {
    verifyResolve = resolve;
  });
}

export async function submitVerify(secret: string): Promise<void> {
  if (!vaultKey) return;
  set({ verifyBusy: true, verifyError: '' });
  let key: Uint8Array | null = null;
  try {
    const v = await db.get<StoredVault>('vault');
    if (!v) throw new VaultError('corrupt', 'Không thấy kho trên máy');
    const parsed = parseVault(v.bytes);
    try {
      key = await unwrapWithPassphrase(parsed, secret, workerArgon2);
    } catch (e) {
      // Người mở bằng recovery key có thể xác nhận lại bằng chính recovery key.
      if (!(e instanceof VaultError && e.code === 'auth') || secret.replace(/[\s-]/g, '').length !== 24) throw e;
      key = await unwrapWithRecovery(parsed, secret);
    }
    if (!vaultKey || !bytesEqual(key, vaultKey)) throw new VaultError('auth', 'Sai mật khẩu');
    verifiedAt = Date.now();
    tabSession.update({ verifiedAt });
    set({ verifying: false, verifyBusy: false });
    verifyResolve?.(true);
    verifyResolve = null;
  } catch (e) {
    set({ verifyBusy: false, verifyError: e instanceof VaultError && e.code === 'auth' ? 'Sai mật khẩu' : message(e) });
  } finally {
    wipe(key);
  }
}

export function cancelVerify(): void {
  set({ verifying: false, verifyBusy: false, verifyError: '' });
  verifyResolve?.(false);
  verifyResolve = null;
}

// ---------- Clipboard ----------

let clipTimer = 0;
let copiedAt = 0;

export async function copySecret(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    return false;
  }
  copiedAt = Date.now();
  clearTimeout(clipTimer);
  clipTimer = window.setTimeout(clearClipboardNow, 30_000);
  return true;
}

async function clearClipboardNow(): Promise<void> {
  if (!copiedAt) return;
  copiedAt = 0;
  clearTimeout(clipTimer);
  try {
    // Trình duyệt chỉ cho ghi clipboard khi trang đang được focus; không được thì đành bỏ qua.
    await navigator.clipboard.writeText('');
  } catch {
    // bỏ qua
  }
}
