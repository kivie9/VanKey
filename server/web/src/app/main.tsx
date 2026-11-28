import { render } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import { AuthLayout } from './brand.tsx';
import * as c from './controller.ts';
import type { State } from './controller.ts';
import { warmUpKdf } from './kdf.ts';
import { applyUpdate, onUpdateReady, registerSw } from './sw-client.ts';
import { VaultScreen } from './vault-view.tsx';
import './styles.css';

function useStore(): State {
  const [s, setS] = useState(c.getState());
  useEffect(() => {
    const off = c.subscribe(() => setS(c.getState()));
    setS(c.getState()); // trạng thái có thể đã đổi trước khi effect này chạy
    return off;
  }, []);
  return s;
}

// ---------- Khung chung ----------

function Logo() {
  return (
    <div class="logo">
      <img src="/app/favicon.svg" width="28" height="28" alt="" />
      VanKey
    </div>
  );
}

function UpdateBanner() {
  const [ready, setReady] = useState(false);
  useEffect(() => onUpdateReady(() => setReady(true)), []);
  if (!ready) return null;
  return (
    <div class="banner" role="status">
      <span>Có phiên bản mới của VanKey web.</span>
      <button class="btn small" onClick={applyUpdate}>
        Cập nhật
      </button>
    </div>
  );
}

function ErrorText({ text }: { text: string }) {
  return text ? (
    <p class="error" role="alert">
      {text}
    </p>
  ) : null;
}

function PasswordInput(props: { value: string; onInput: (v: string) => void; label: string; autoFocus?: boolean; autocomplete: string }) {
  const [show, setShow] = useState(false);
  return (
    <label class="field">
      <span>{props.label}</span>
      <div class="input-row">
        <input
          type={show ? 'text' : 'password'}
          value={props.value}
          onInput={(e) => props.onInput(e.currentTarget.value)}
          autoFocus={props.autoFocus}
          autocomplete={props.autocomplete}
          spellcheck={false}
          required
        />
        <button type="button" class="icon-btn" onClick={() => setShow(!show)} aria-label={show ? 'Ẩn' : 'Hiện'}>
          {show ? 'Ẩn' : 'Hiện'}
        </button>
      </div>
    </label>
  );
}

// ---------- Đăng nhập lần đầu ----------

function LoginScreen({ s }: { s: State }) {
  const [username, setUsername] = useState(s.username);
  const [password, setPassword] = useState('');
  const submit = (e: Event) => {
    e.preventDefault();
    void c.signIn(username, password).then(() => setPassword(''));
  };
  return (
    <AuthLayout logo={<Logo />}>
      <form class="auth" onSubmit={submit}>
        <Logo />
        <h1>Đăng nhập</h1>
        <p class="muted">Dùng tài khoản đồng bộ Cloudflare của app. Kho được tải về và giải mã ngay trên trình duyệt này.</p>
        <label class="field">
          <span>Tên đăng nhập</span>
          <input value={username} onInput={(e) => setUsername(e.currentTarget.value)} autocomplete="username" autoFocus={!username} spellcheck={false} autocapitalize="none" required />
        </label>
        <PasswordInput label="Mật khẩu" value={password} onInput={setPassword} autoFocus={!!username} autocomplete="current-password" />
        <ErrorText text={s.error} />
        <button class="btn primary" disabled={s.busy || !s.online}>
          {s.busy ? 'Đang mở…' : s.online ? 'Đăng nhập' : 'Không có mạng'}
        </button>
      </form>
    </AuthLayout>
  );
}

// ---------- Mở khóa ----------

function UnlockScreen({ s }: { s: State }) {
  const [mode, setMode] = useState<'password' | 'recovery'>('password');
  const [value, setValue] = useState('');
  const [confirmForget, setConfirmForget] = useState(false);
  const submit = (e: Event) => {
    e.preventDefault();
    const v = value;
    setValue('');
    void (mode === 'password' ? c.unlockWithPassword(v) : c.unlockWithRecovery(v));
  };
  return (
    <AuthLayout logo={<Logo />}>
      <form class="auth" onSubmit={submit}>
        <Logo />
        <h1>Kho đang khóa</h1>
        {s.username && <p class="muted">Tài khoản {s.username}</p>}
        {s.notice && <p class="notice">{s.notice}</p>}
        {mode === 'password' ? (
          <PasswordInput label="Mật khẩu kho" value={value} onInput={setValue} autoFocus autocomplete="current-password" />
        ) : (
          <label class="field">
            <span>Recovery key</span>
            <input class="mono" value={value} onInput={(e) => setValue(e.currentTarget.value)} placeholder="XXXX-XXXX-XXXX-XXXX-XXXX-XXXX" autoFocus spellcheck={false} autocomplete="off" required />
          </label>
        )}
        <ErrorText text={s.error} />
        <button class="btn primary" disabled={s.busy}>
          {s.busy ? 'Đang mở…' : 'Mở khóa'}
        </button>
        <button type="button" class="btn link" onClick={() => setMode(mode === 'password' ? 'recovery' : 'password')}>
          {mode === 'password' ? 'Dùng recovery key' : 'Dùng mật khẩu'}
        </button>
        <div class="divider" />
        {confirmForget ? (
          <div class="confirm">
            <p>Xóa kho đã tải và đăng xuất trên trình duyệt này? Kho trên máy chủ và trên các thiết bị khác không bị ảnh hưởng.</p>
            <div class="row">
              <button type="button" class="btn danger" onClick={() => void c.forgetDevice()}>
                Xóa khỏi trình duyệt
              </button>
              <button type="button" class="btn" onClick={() => setConfirmForget(false)}>
                Thôi
              </button>
            </div>
          </div>
        ) : (
          <button type="button" class="btn link muted" onClick={() => setConfirmForget(true)}>
            Đăng nhập tài khoản khác
          </button>
        )}
      </form>
    </AuthLayout>
  );
}

/** Hỏi lại mật khẩu trước khi xem hoặc chép mật khẩu (khi đã quá 2 phút kể từ lần nhập gần nhất). */
function VerifyDialog({ s }: { s: State }) {
  const [value, setValue] = useState('');
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open) d.showModal();
    return () => setValue('');
  }, []);
  const submit = (e: Event) => {
    e.preventDefault();
    const v = value;
    setValue('');
    void c.submitVerify(v);
  };
  return (
    <dialog
      ref={ref}
      class="card verify"
      aria-labelledby="verify-title"
      onCancel={(e) => {
        e.preventDefault();
        c.cancelVerify();
      }}
    >
      <form onSubmit={submit}>
        <h2 id="verify-title">Nhập mật khẩu để xem</h2>
        <p class="muted small">Xác nhận lại trước khi hiện hoặc sao chép mật khẩu. Sau đó 2 phút không hỏi lại.</p>
        <PasswordInput label="Mật khẩu kho" value={value} onInput={setValue} autoFocus autocomplete="current-password" />
        <ErrorText text={s.verifyError} />
        <div class="row end">
          <button type="button" class="btn" onClick={c.cancelVerify}>
            Thôi
          </button>
          <button class="btn primary" disabled={s.verifyBusy || !value}>
            {s.verifyBusy ? 'Đang kiểm tra…' : 'Xác nhận'}
          </button>
        </div>
      </form>
    </dialog>
  );
}

function App() {
  const s = useStore();
  return (
    <>
      <UpdateBanner />
      {s.phase === 'loading' ? null : s.phase === 'login' ? <LoginScreen s={s} /> : s.phase === 'locked' ? <UnlockScreen s={s} /> : <VaultScreen s={s} />}
      {s.phase === 'unlocked' && s.verifying && <VerifyDialog s={s} />}
    </>
  );
}

render(<App />, document.getElementById('app')!);
warmUpKdf();
registerSw();
void c.init();
