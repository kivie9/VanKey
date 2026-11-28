import { render } from 'preact';
import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import type { JSX } from 'preact';
import { otpCode } from '../core/otp.ts';
import type { OtpState } from '../core/otp.ts';
import type { Field, Item, TotpJson } from '../core/vault.ts';
import { AuthLayout } from './brand.tsx';
import * as c from './controller.ts';
import type { State } from './controller.ts';
import { warmUpKdf } from './kdf.ts';
import { FIELD_LABELS, TYPE_LABELS, fold, safeUrl } from './labels.ts';
import { applyUpdate, onUpdateReady, registerSw } from './sw-client.ts';
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

function useNow(active: boolean): number {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [active]);
  return now;
}

function useOtp(t: TotpJson | null | undefined, now: number): OtpState | null {
  const [s, setS] = useState<OtpState | null>(null);
  const slot = t ? (t.kind === 'hotp' ? 0 : Math.floor(now / 1000 / (t.period || 30))) : -1;
  useEffect(() => {
    if (!t) return setS(null);
    let live = true;
    otpCode(t, now)
      .then((r) => live && setS(r))
      .catch(() => live && setS({ code: '——————', remaining: null, period: 30 }));
    return () => {
      live = false;
    };
  }, [t, slot]);
  if (!s || !t || t.kind === 'hotp') return s;
  const period = t.period || 30;
  return { ...s, remaining: period - (Math.floor(now / 1000) % period) };
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

// ---------- Kho ----------

type Filter = 'all' | 'fav' | 'totp' | string;

const fieldLabel = (f: Field) => (f.key ? (FIELD_LABELS[f.key] ?? f.key) : (f.label ?? ''));

function subtitle(it: Item): string {
  const f = it.fields?.find((x) => !x.secret && x.value && (x.key === 'username' || x.key === 'account' || x.key === 'url' || x.key === 'ssid' || x.key === 'holder'));
  return f?.value ?? TYPE_LABELS[it.type] ?? '';
}

function searchText(it: Item): string {
  // Trường bí mật không đưa vào tìm kiếm (`vault-format.md` mục 6.2).
  return fold([it.title, it.group ?? '', ...(it.fields ?? []).filter((f) => !f.secret).map((f) => f.value)].join(' '));
}

function Avatar({ title }: { title: string }) {
  const ch = (title.trim()[0] ?? '?').toUpperCase();
  let h = 0;
  for (const x of title) h = (h * 31 + x.charCodeAt(0)) % 360;
  return (
    <span class="avatar" style={{ '--h': h } as JSX.CSSProperties} aria-hidden="true">
      {ch}
    </span>
  );
}

function Ring({ remaining, period }: { remaining: number; period: number }) {
  const r = 9;
  const len = 2 * Math.PI * r;
  return (
    <svg class={`ring${remaining <= 5 ? ' low' : ''}`} width="22" height="22" viewBox="0 0 22 22" aria-label={`${remaining} giây`}>
      <circle cx="11" cy="11" r={r} class="ring-bg" />
      <circle cx="11" cy="11" r={r} class="ring-fg" stroke-dasharray={len} stroke-dashoffset={len * (1 - remaining / period)} />
    </svg>
  );
}

function formatCode(code: string): string {
  return code.length === 6 ? `${code.slice(0, 3)} ${code.slice(3)}` : code.length === 8 ? `${code.slice(0, 4)} ${code.slice(4)}` : code;
}

function CopyButton({ text, label = 'Sao chép' }: { text: string; label?: string }) {
  const [done, setDone] = useState(false);
  return (
    <button
      type="button"
      class={`btn small${done ? ' ok' : ''}`}
      onClick={async () => {
        if (await c.copySecret(text)) {
          setDone(true);
          setTimeout(() => setDone(false), 1500);
        }
      }}
    >
      {done ? 'Đã chép' : label}
    </button>
  );
}

function OtpLine({ t, now, big }: { t: TotpJson; now: number; big?: boolean }) {
  const s = useOtp(t, now);
  if (!s) return <span class="otp muted">…</span>;
  return (
    <span class={`otp${big ? ' big' : ''}`}>
      <span class="mono">{formatCode(s.code)}</span>
      {s.remaining !== null && <Ring remaining={s.remaining} period={s.period} />}
      {big && <CopyButton text={s.code} />}
    </span>
  );
}

function FieldRow({ f }: { f: Field }) {
  const [shown, setShown] = useState(false);
  const url = f.kind === 'url' || f.key === 'url' ? safeUrl(f.value) : null;
  const multiline = f.kind === 'multiline' || f.value.includes('\n');
  return (
    <div class="frow">
      <div class="flabel">{fieldLabel(f)}</div>
      <div class="fvalue">
        {f.secret && !shown ? (
          <span class="mono dim">••••••••••</span>
        ) : url ? (
          <a href={url} target="_blank" rel="noopener noreferrer">
            {f.value}
          </a>
        ) : (
          <span class={`${f.secret ? 'mono' : ''}${multiline ? ' pre' : ''}`}>{f.value}</span>
        )}
      </div>
      <div class="factions">
        {f.secret && (
          <button type="button" class="btn small" onClick={() => setShown(!shown)}>
            {shown ? 'Ẩn' : 'Hiện'}
          </button>
        )}
        <CopyButton text={f.value} />
      </div>
    </div>
  );
}

function Detail({ it, now, onBack }: { it: Item; now: number; onBack: () => void }) {
  const fields = (it.fields ?? []).filter((f) => f.value !== '');
  return (
    <article class="detail card" aria-label={it.title}>
      <div class="detail-head">
        <button type="button" class="btn small back" onClick={onBack}>
          ← Danh sách
        </button>
        <Avatar title={it.title} />
        <div>
          <h2>{it.title || '(không tên)'}</h2>
          <p class="muted">
            {TYPE_LABELS[it.type] ?? 'Ghi chú'}
            {it.group ? ` · ${it.group}` : ''}
          </p>
        </div>
      </div>
      {it.totp?.secret && (
        <div class="frow">
          <div class="flabel">Mã 2FA</div>
          <div class="fvalue">
            <OtpLine t={it.totp} now={now} big />
          </div>
        </div>
      )}
      {fields.map((f, i) => (
        <FieldRow key={`${it.id}-${i}`} f={f} />
      ))}
      {it.updatedAt && <p class="muted small">Sửa lần cuối {new Date(it.updatedAt).toLocaleString('vi-VN')}</p>}
    </article>
  );
}

function relTime(ms: number, now: number): string {
  if (!ms) return 'chưa đồng bộ';
  const m = Math.round((now - ms) / 60_000);
  if (m < 1) return 'vừa đồng bộ';
  if (m < 60) return `đồng bộ ${m} phút trước`;
  return `đồng bộ lúc ${new Date(ms).toLocaleString('vi-VN')}`;
}

function VaultScreen({ s }: { s: State }) {
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  const [selected, setSelected] = useState<string | null>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  const items = useMemo(() => (s.payload?.items ?? []).filter((it) => !it.deletedAt), [s.payload]);
  const indexed = useMemo(() => items.map((it) => ({ it, text: searchText(it) })), [items]);
  const types = useMemo(() => [...new Set(items.map((it) => it.type))].filter((t) => TYPE_LABELS[t] && t !== 'totp'), [items]);

  const shown = useMemo(() => {
    const needle = fold(q.trim());
    return indexed
      .filter(({ it }) => (filter === 'all' ? true : filter === 'fav' ? it.favorite : filter === 'totp' ? !!it.totp?.secret : it.type === filter))
      .filter(({ text }) => !needle || needle.split(/\s+/).every((w) => text.includes(w)))
      .map(({ it }) => it)
      .sort((a, b) => Number(!!b.favorite) - Number(!!a.favorite) || a.title.localeCompare(b.title, 'vi'));
  }, [indexed, q, filter]);

  const current = items.find((it) => it.id === selected) ?? null;
  const now = useNow(shown.some((it) => it.totp?.secret) || !!current?.totp?.secret);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.key === '/' || (e.key === 'k' && (e.ctrlKey || e.metaKey))) && document.activeElement !== searchRef.current) {
        e.preventDefault();
        searchRef.current?.focus();
      }
      if (e.key === 'Escape') setSelected(null);
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, []);

  const chips: [Filter, string][] = [['all', 'Tất cả'], ['fav', 'Yêu thích'], ['totp', 'Mã 2FA'], ...types.map((t): [Filter, string] => [t, TYPE_LABELS[t]])];

  return (
    <div class={`vault${current ? ' has-detail' : ''}`}>
      <header class="topbar">
        <Logo />
        <input ref={searchRef} class="search" type="search" placeholder="Tìm kiếm  ( / )" value={q} onInput={(e) => setQ(e.currentTarget.value)} aria-label="Tìm kiếm" />
        <div class="status">
          <span class={`dot${s.online && !s.unreachable ? (s.signedOut ? ' warn' : ' on') : ''}`} aria-hidden="true" />
          <span class="muted small">{!s.online ? 'Ngoại tuyến' : s.syncing ? 'Đang đồng bộ…' : s.signedOut ? 'Cần đăng nhập lại' : s.unreachable ? 'Không kết nối được máy chủ' : relTime(s.syncedAt, now)}</span>
          {s.online && !s.signedOut && (
            <button class="btn small" onClick={() => void c.sync()} disabled={s.syncing}>
              Đồng bộ
            </button>
          )}
          {s.signedOut && s.online && (
            <button class="btn small" onClick={() => void c.forgetDevice()}>
              Đăng nhập lại
            </button>
          )}
          <button class="btn small primary" onClick={c.lock}>
            Khóa
          </button>
        </div>
      </header>
      {s.notice && <p class="notice wide">{s.notice}</p>}
      <nav class="chips" aria-label="Lọc">
        {chips.map(([k, label]) => (
          <button key={k} class={`chip${filter === k ? ' active' : ''}`} onClick={() => setFilter(k)} aria-pressed={filter === k}>
            {label}
          </button>
        ))}
      </nav>
      <div class="panes">
        <ul class="list card" aria-label="Các mục">
          {shown.length === 0 && <li class="empty muted">{items.length ? 'Không có mục nào khớp' : 'Kho chưa có mục nào'}</li>}
          {shown.map((it) => (
            <li key={it.id}>
              <button class={`row${selected === it.id ? ' sel' : ''}`} onClick={() => setSelected(it.id)}>
                <Avatar title={it.title} />
                <span class="row-text">
                  <span class="row-title">
                    {it.title || '(không tên)'}
                    {it.favorite && <span class="star" aria-label="Yêu thích"> ★</span>}
                  </span>
                  <span class="row-sub muted">{subtitle(it)}</span>
                </span>
                {it.totp?.secret && <OtpLine t={it.totp} now={now} />}
              </button>
            </li>
          ))}
        </ul>
        {current ? <Detail it={current} now={now} onBack={() => setSelected(null)} /> : <div class="placeholder muted">Chọn một mục để xem chi tiết</div>}
      </div>
      <footer class="foot muted small">Bản web chỉ để xem và sao chép. Thêm hoặc sửa mục trên app. Tự khóa sau 5 phút không dùng.</footer>
    </div>
  );
}

function App() {
  const s = useStore();
  return (
    <>
      <UpdateBanner />
      {s.phase === 'loading' ? null : s.phase === 'login' ? <LoginScreen s={s} /> : s.phase === 'locked' ? <UnlockScreen s={s} /> : <VaultScreen s={s} />}
    </>
  );
}

render(<App />, document.getElementById('app')!);
warmUpKdf();
registerSw();
void c.init();
