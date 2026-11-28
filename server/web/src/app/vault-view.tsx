// Màn hình kho, theo bố cục bản Windows (app/lib/app/screens/desktop_home.dart):
// thanh trên (tên app, trạng thái đồng bộ, Khóa ngay), thanh bên (Tất cả, từng loại, Thẻ, Mã 2FA),
// lưới thẻ gom theo Thẻ/Loại, mục Yêu thích ở đầu, bấm thẻ mở chi tiết trong hộp thoại.
// Bản web chỉ xem: không có nút thêm, sửa, xóa.
import type { ComponentChildren } from 'preact';
import { useEffect, useMemo, useRef, useState } from 'preact/hooks';
import { otpCode } from '../core/otp.ts';
import type { OtpState } from '../core/otp.ts';
import type { Field, Item, TotpJson } from '../core/vault.ts';
import * as c from './controller.ts';
import type { State } from './controller.ts';
import { Icon, Star } from './icons.tsx';
import type { IconName } from './icons.tsx';
import { FIELD_LABELS, TYPE_LABELS, TYPE_ORDER, fold, safeUrl, tagColor } from './labels.ts';
import { Logo } from './logos.tsx';
import './vault.css';

const TYPE_ICONS: Record<string, IconName> = {
  login: 'person',
  totp: 'shield',
  key: 'key',
  crypto: 'coin',
  card: 'card',
  wifi: 'wifi',
  note: 'note',
};
const UNTAGGED = 'Chưa gắn thẻ';

type SortBy = 'name' | 'updated' | 'created';
type GroupBy = 'group' | 'type' | 'none';
/** 'all' | 'totp' | 'type:<loại>' | 'group:<thẻ>' */
type Section = string;

const hasCode = (i: Item) => !!i.totp?.secret;
/** Giống app: mục loại "Mã 2FA" có khóa chỉ hiện ở trang Mã 2FA. */
const inVault = (i: Item) => i.type !== 'totp' || !hasCode(i);
const subtitle = (i: Item) => i.fields?.find((f) => !f.secret && f.value)?.value ?? '';
const fieldLabel = (f: Field) => (f.label ? f.label : f.key ? (FIELD_LABELS[f.key] ?? f.key) : '');

// ---------- Tùy chọn hiển thị (chỉ lưu trên trình duyệt này) ----------

function usePref<T extends string>(key: string, initial: T, allowed: readonly T[]): [T, (v: T) => void] {
  const [v, setV] = useState<T>(() => {
    try {
      const s = localStorage.getItem(`vankey.${key}`) as T | null;
      return s && allowed.includes(s) ? s : initial;
    } catch {
      return initial;
    }
  });
  return [
    v,
    (n: T) => {
      setV(n);
      try {
        localStorage.setItem(`vankey.${key}`, n);
      } catch {
        // bỏ qua
      }
    },
  ];
}

// ---------- Thông báo nhỏ (đã chép...) ----------

let showToast: (text: string) => void = () => {};

function Toast() {
  const [text, setText] = useState('');
  useEffect(() => {
    let t = 0;
    showToast = (s) => {
      setText(s);
      clearTimeout(t);
      t = window.setTimeout(() => setText(''), 2200);
    };
    return () => clearTimeout(t);
  }, []);
  return (
    <div class={`toast${text ? ' show' : ''}`} role="status" aria-live="polite">
      {text}
    </div>
  );
}

async function copy(text: string, what: string, secret: boolean): Promise<void> {
  if (secret && !(await c.requestVerify())) return;
  if (await c.copySecret(text)) showToast(secret ? `${what}. Tự xóa khỏi bộ nhớ tạm sau 30 giây.` : what);
  else showToast('Trình duyệt không cho chép. Thử lại.');
}

// ---------- 2FA ----------

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
  const period = t?.period || 30;
  const slot = t ? (t.kind === 'hotp' ? 0 : Math.floor(now / 1000 / period)) : -1;
  useEffect(() => {
    if (!t) return setS(null);
    let live = true;
    otpCode(t, now)
      .then((r) => live && setS(r))
      .catch(() => live && setS(null));
    return () => {
      live = false;
    };
  }, [t, slot]);
  if (!s || !t || t.kind === 'hotp') return s;
  return { ...s, remaining: period - (Math.floor(now / 1000) % period) };
}

function Ring({ remaining, period, size = 18 }: { remaining: number; period: number; size?: number }) {
  const r = size / 2 - 2;
  const len = 2 * Math.PI * r;
  return (
    <svg class={`ring${remaining <= 5 ? ' low' : ''}`} width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-label={`còn ${remaining} giây`} role="img">
      <circle cx={size / 2} cy={size / 2} r={r} class="ring-bg" />
      <circle cx={size / 2} cy={size / 2} r={r} class="ring-fg" stroke-dasharray={len} stroke-dashoffset={len * (1 - remaining / period)} />
    </svg>
  );
}

const formatCode = (code: string) => (code.length === 6 ? `${code.slice(0, 3)} ${code.slice(3)}` : code.length === 8 ? `${code.slice(0, 4)} ${code.slice(4)}` : code);

// ---------- Thẻ trong lưới ----------

function Card({ it, codes, now, onOpen }: { it: Item; codes: boolean; now: number; onOpen: (it: Item) => void }) {
  const otp = useOtp(codes ? it.totp : null, now);
  const sub = subtitle(it);
  const title = (
    <span class="vcard-title">
      {codes && <Logo item={it} size={18} />}
      <span class="ellipsis">{it.title || '(không tên)'}</span>
      {it.favorite && <Star />}
    </span>
  );
  return (
    <button
      type="button"
      class={`vcard${codes ? ' codes' : ''}`}
      title={codes ? 'Bấm để chép mã. Chuột phải để xem chi tiết.' : undefined}
      onClick={() => (codes && otp ? void copy(otp.code, 'Đã chép mã 2FA', false) : onOpen(it))}
      onContextMenu={(e) => {
        if (!codes) return;
        e.preventDefault();
        onOpen(it);
      }}
    >
      {!codes && <Logo item={it} size={32} />}
      <span class="vcard-text">
        {title}
        {sub && <span class="vcard-sub ellipsis">{sub}</span>}
      </span>
      {codes && (
        <span class="vcard-code">
          {otp?.remaining != null && <Ring remaining={otp.remaining} period={otp.period} />}
          <span class="mono">{otp ? formatCode(otp.code) : '—'}</span>
        </span>
      )}
    </button>
  );
}

function GroupHeader({ label, count, collapsed, onToggle }: { label: string; count: number; collapsed: boolean; onToggle: () => void }) {
  return (
    <button type="button" class="group-head" onClick={onToggle} aria-expanded={!collapsed}>
      <Icon name={collapsed ? 'chevronRight' : 'chevronDown'} size={16} />
      <span class="group-label">{label}</span>
      <span class="group-count">{count}</span>
    </button>
  );
}

// ---------- Chi tiết (hộp thoại) ----------

function FieldRow({ f }: { f: Field }) {
  const [shown, setShown] = useState(false);
  const url = f.kind === 'url' || f.key === 'url' ? safeUrl(f.value) : null;
  const multiline = f.kind === 'multiline' || f.value.includes('\n');
  const label = fieldLabel(f);
  return (
    <div class="frow">
      <div class="fmain">
        <div class="flabel">{label}</div>
        <div class={`fvalue${f.secret ? ' mono' : ''}${multiline ? ' pre' : ''}`}>
          {f.secret && !shown ? (
            <span class="dim">••••••••••</span>
          ) : url ? (
            <a href={url} target="_blank" rel="noopener noreferrer">
              {f.value}
            </a>
          ) : (
            f.value
          )}
        </div>
      </div>
      <div class="factions">
        {f.secret && (
          <IconButton
            icon={shown ? 'eyeOff' : 'eye'}
            label={shown ? 'Ẩn' : 'Hiện'}
            onClick={async () => setShown(shown ? false : await c.requestVerify())}
          />
        )}
        {url && <IconLink icon="external" label="Mở trang" href={url} />}
        <IconButton icon="copy" label={`Chép ${label.toLowerCase()}`} onClick={() => void copy(f.value, `Đã chép ${label.toLowerCase()}`, !!f.secret)} />
      </div>
    </div>
  );
}

function IconButton({ icon, label, onClick }: { icon: IconName; label: string; onClick: () => void }) {
  return (
    <button type="button" class="icon-btn2" onClick={onClick} aria-label={label} title={label}>
      <Icon name={icon} size={19} />
    </button>
  );
}

function IconLink({ icon, label, href }: { icon: IconName; label: string; href: string }) {
  return (
    <a class="icon-btn2" href={href} target="_blank" rel="noopener noreferrer" aria-label={label} title={label}>
      <Icon name={icon} size={19} />
    </a>
  );
}

const dateVi = (s?: string) => (s ? new Date(s).toLocaleString('vi-VN', { dateStyle: 'medium', timeStyle: 'short' }) : '');

function DetailDialog({ it, now, onClose }: { it: Item; now: number; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const otp = useOtp(it.totp?.secret ? it.totp : null, now);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open) d.showModal();
  }, []);
  const fields = (it.fields ?? []).filter((f) => f.value !== '');
  return (
    <dialog
      ref={ref}
      class="detail-dialog"
      aria-labelledby="detail-title"
      onClose={onClose}
      onClick={(e) => {
        if (e.target === ref.current) ref.current?.close(); // bấm ra ngoài để đóng
      }}
    >
      <div class="detail-inner">
        <header class="detail-head">
          <Logo item={it} size={40} />
          <div class="detail-titles">
            <h2 id="detail-title">
              {it.title || '(không tên)'} {it.favorite && <Star size={16} />}
            </h2>
            <p class="muted">
              {TYPE_LABELS[it.type] ?? 'Ghi chú'}
              {it.group ? (
                <>
                  {' · '}
                  <span class="tag-dot" style={{ background: tagColor(it.group) }} />
                  {it.group}
                </>
              ) : null}
            </p>
          </div>
          <IconButton icon="close" label="Đóng" onClick={() => ref.current?.close()} />
        </header>

        {otp && (
          <div class="otp-box">
            <div>
              <div class="flabel">Mã 2FA</div>
              <div class="otp-big mono">{formatCode(otp.code)}</div>
            </div>
            {otp.remaining != null && <Ring remaining={otp.remaining} period={otp.period} size={30} />}
            <IconButton icon="copy" label="Chép mã 2FA" onClick={() => void copy(otp.code, 'Đã chép mã 2FA', false)} />
          </div>
        )}

        <div class="fields">
          {fields.map((f, i) => (
            <FieldRow key={`${it.id}-${i}`} f={f} />
          ))}
          {fields.length === 0 && !otp && <p class="muted">Mục này không có trường nào.</p>}
        </div>

        <footer class="detail-foot muted small">
          {it.updatedAt && <span>Sửa lần cuối {dateVi(it.updatedAt)}</span>}
          {it.createdAt && <span>Tạo {dateVi(it.createdAt)}</span>}
          <span>Sửa mục này trên app.</span>
        </footer>
      </div>
    </dialog>
  );
}

// ---------- Thanh trên, thanh bên ----------

function relTime(ms: number): string {
  if (!ms) return 'Chưa đồng bộ';
  const m = Math.round((Date.now() - ms) / 60_000);
  return m < 1 ? 'Đồng bộ vừa xong' : m < 60 ? `Đồng bộ ${m} phút trước` : `Đồng bộ lúc ${new Date(ms).toLocaleString('vi-VN')}`;
}

function TopBar({ s, onMenu }: { s: State; onMenu: () => void }) {
  const [label, tone] = !s.online
    ? ['Ngoại tuyến', 'muted']
    : s.syncing
      ? ['Đang đồng bộ…', 'warn']
      : s.signedOut
        ? ['Cần đăng nhập lại', 'warn']
        : s.unreachable
          ? ['Không kết nối được máy chủ', 'danger']
          : ['Đã đồng bộ', 'ok'];
  return (
    <header class="vtop">
      <button type="button" class="icon-btn2 menu-btn" onClick={onMenu} aria-label="Menu">
        <Icon name="menu" />
      </button>
      <div class="logo">
        <img src="/app/favicon.svg" width="30" height="30" alt="" />
        VanKey
      </div>
      <div class="vtop-right">
        <button
          type="button"
          class="sync-pill"
          title={`${relTime(s.syncedAt)}. Bấm để đồng bộ.`}
          onClick={() => (s.signedOut ? void c.forgetDevice() : void c.sync())}
          disabled={s.syncing || !s.online}
        >
          <span class={`dot ${tone}`} />
          <span class="sync-label">{label}</span>
        </button>
        <button type="button" class="top-btn" onClick={c.lock}>
          <Icon name="lock" size={18} />
          <span class="top-btn-label">Khóa ngay</span>
        </button>
      </div>
    </header>
  );
}

function NavRow(props: { selected: boolean; onClick: () => void; icon?: IconName; lead?: ComponentChildren; label: string; count?: number }) {
  return (
    <button type="button" class={`nav-row${props.selected ? ' sel' : ''}`} onClick={props.onClick} aria-current={props.selected ? 'page' : undefined}>
      <span class="nav-icon">{props.lead ?? (props.icon && <Icon name={props.icon} />)}</span>
      <span class="nav-label ellipsis">{props.label}</span>
      {props.count !== undefined && <span class="nav-count">{props.count}</span>}
    </button>
  );
}

/** Bản cài mới nhất của app (Android APK, bộ cài Windows) trên GitHub Releases. */
const LATEST_RELEASE = 'https://github.com/kivie9/VanKey/releases/latest';

function NavLink({ href, icon, label, hint }: { href: string; icon: IconName; label: string; hint: string }) {
  return (
    <a class="nav-row" href={href} target="_blank" rel="noopener noreferrer">
      <span class="nav-icon">
        <Icon name={icon} />
      </span>
      <span class="nav-label ellipsis">{label}</span>
      <span class="nav-count">{hint}</span>
      <Icon name="external" size={14} class="nav-ext" />
    </a>
  );
}

function Sidebar({ live, section, onSelect, open }: { live: Item[]; section: Section; onSelect: (s: Section) => void; open: boolean }) {
  const vault = live.filter(inVault);
  const types = TYPE_ORDER.map((t) => [t, vault.filter((i) => i.type === t).length] as const).filter(([, n]) => n > 0);
  const groupNames = [...new Set(vault.map((i) => i.group ?? '').filter(Boolean))].sort((a, b) => a.localeCompare(b, 'vi'));
  const [confirmOut, setConfirmOut] = useState(false);
  return (
    <nav class={`vside${open ? ' open' : ''}`} aria-label="Danh mục">
      <NavRow selected={section === 'all'} onClick={() => onSelect('all')} icon="grid" label="Tất cả" count={vault.length} />
      {types.map(([t, n]) => (
        <NavRow key={t} selected={section === `type:${t}`} onClick={() => onSelect(`type:${t}`)} icon={TYPE_ICONS[t] ?? 'note'} label={TYPE_LABELS[t] ?? t} count={n} />
      ))}
      {groupNames.length > 0 && <div class="nav-section">THẺ</div>}
      {groupNames.map((g) => (
        <NavRow
          key={g}
          selected={section === `group:${g}`}
          onClick={() => onSelect(`group:${g}`)}
          lead={
            <span class="tag-badge" style={{ background: tagColor(g) }}>
              {[...g.trim()][0]?.toUpperCase()}
            </span>
          }
          label={g}
          count={vault.filter((i) => i.group === g).length}
        />
      ))}
      <div class="nav-divider" />
      <NavRow selected={section === 'totp'} onClick={() => onSelect('totp')} icon="shield" label="Mã 2FA" count={live.filter(hasCode).length} />
      <div class="nav-spacer" />
      <div class="nav-section">TẢI APP</div>
      <NavLink href={LATEST_RELEASE} icon="phone" label="Android" hint="APK" />
      <NavLink href={LATEST_RELEASE} icon="desktop" label="Windows" hint="Bộ cài" />
      <div class="nav-divider" />
      {confirmOut ? (
        <div class="nav-confirm">
          <p>Đăng xuất và xóa kho đã tải khỏi trình duyệt này? Dữ liệu trên máy chủ và các thiết bị khác giữ nguyên.</p>
          <div class="row">
            <button type="button" class="btn small danger" onClick={() => void c.forgetDevice()}>
              Đăng xuất
            </button>
            <button type="button" class="btn small" onClick={() => setConfirmOut(false)}>
              Thôi
            </button>
          </div>
        </div>
      ) : (
        <NavRow selected={false} onClick={() => setConfirmOut(true)} icon="logout" label="Đăng xuất" />
      )}
      <p class="nav-note">Bản web chỉ để xem và sao chép. Thêm hoặc sửa mục trên app. Tự khóa khi đóng tab hoặc sau 15 phút không dùng.</p>
    </nav>
  );
}

// ---------- Màn hình kho ----------

function sortItems(items: Item[], by: SortBy): Item[] {
  return items.sort((a, b) =>
    by === 'updated'
      ? (b.updatedAt ?? '').localeCompare(a.updatedAt ?? '')
      : by === 'created'
        ? (b.createdAt ?? '').localeCompare(a.createdAt ?? '')
        : a.title.toLowerCase().localeCompare(b.title.toLowerCase(), 'vi'),
  );
}

function groupItems(items: Item[], by: GroupBy): [string, Item[]][] {
  if (by === 'none') return [['', items]];
  const m = new Map<string, Item[]>();
  for (const i of items) {
    const k = by === 'group' ? i.group || UNTAGGED : (TYPE_LABELS[i.type] ?? 'Ghi chú');
    m.set(k, [...(m.get(k) ?? []), i]);
  }
  return [...m.entries()].sort(([a], [b]) => (a === UNTAGGED ? 1 : b === UNTAGGED ? -1 : a.localeCompare(b, 'vi')));
}

const searchText = (i: Item) => fold([i.title, i.group ?? '', ...(i.fields ?? []).filter((f) => !f.secret).map((f) => f.value)].join(' '));

export function VaultScreen({ s }: { s: State }) {
  const [section, setSection] = useState<Section>('all');
  const [q, setQ] = useState('');
  const [sortBy, setSortBy] = usePref<SortBy>('sortBy', 'name', ['name', 'updated', 'created']);
  const [groupBy, setGroupBy] = usePref<GroupBy>('groupBy', 'group', ['group', 'type', 'none']);
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [openId, setOpenId] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [sortOpen, setSortOpen] = useState(false);
  const searchRef = useRef<HTMLInputElement>(null);

  const live = useMemo(() => (s.payload?.items ?? []).filter((i) => !i.deletedAt), [s.payload]);
  const index = useMemo(() => new Map(live.map((i) => [i.id, searchText(i)])), [live]);
  const codes = section === 'totp';

  const { favs, groups, total } = useMemo(() => {
    const src = codes
      ? live.filter(hasCode)
      : live.filter(inVault).filter((i) => (section.startsWith('type:') ? i.type === section.slice(5) : section.startsWith('group:') ? i.group === section.slice(6) : true));
    const words = fold(q.trim()).split(/\s+/).filter(Boolean);
    const items = sortItems(
      src.filter((i) => words.every((w) => index.get(i.id)!.includes(w))),
      sortBy,
    );
    return { favs: q ? [] : items.filter((i) => i.favorite), groups: groupItems(items, groupBy), total: items.length };
  }, [live, index, section, q, sortBy, groupBy, codes]);

  const now = useNow(codes || !!live.find((i) => i.id === openId)?.totp?.secret);
  const open = openId ? (live.find((i) => i.id === openId) ?? null) : null;

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const typing = document.activeElement instanceof HTMLInputElement;
      if (!typing && !openId && (e.key === '/' || (e.key.toLowerCase() === 'k' && (e.ctrlKey || e.metaKey)))) {
        e.preventDefault();
        searchRef.current?.focus();
      }
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, [openId]);

  const toggle = (k: string) =>
    setCollapsed((old) => {
      const n = new Set(old);
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });

  const grid = (list: Item[]) => (
    <div class="vgrid">
      {list.map((i) => (
        <Card key={i.id} it={i} codes={codes} now={now} onOpen={(it) => setOpenId(it.id)} />
      ))}
    </div>
  );

  const FAV = '\u0000fav';
  const sortLabels: Record<SortBy, string> = { name: 'Tên A–Z', updated: 'Mới sửa', created: 'Mới tạo' };

  return (
    <div class="vshell">
      <TopBar s={s} onMenu={() => setMenuOpen(!menuOpen)} />
      {s.notice && <p class="notice vnotice">{s.notice}</p>}
      <div class="vbody">
        <Sidebar
          live={live}
          section={section}
          open={menuOpen}
          onSelect={(x) => {
            setSection(x);
            setMenuOpen(false);
          }}
        />
        {menuOpen && <div class="vscrim" onClick={() => setMenuOpen(false)} />}
        <main class="vmain">
          <div class="vtools">
            <label class="vsearch">
              <Icon name="search" size={18} />
              <input ref={searchRef} type="search" placeholder="Tìm theo tên, tài khoản, thẻ…" value={q} onInput={(e) => setQ(e.currentTarget.value)} aria-label="Tìm kiếm" />
              {q && (
                <button type="button" class="clear" onClick={() => setQ('')} aria-label="Xóa tìm kiếm">
                  <Icon name="close" size={16} />
                </button>
              )}
            </label>
            <div class="sort-wrap">
              <button type="button" class="icon-btn2" onClick={() => setSortOpen(!sortOpen)} aria-haspopup="menu" aria-expanded={sortOpen} aria-label="Sắp xếp" title={`Sắp xếp: ${sortLabels[sortBy]}`}>
                <Icon name="sort" />
              </button>
              {sortOpen && (
                <>
                  <div class="menu-scrim" onClick={() => setSortOpen(false)} />
                  <div class="menu" role="menu">
                    {(Object.keys(sortLabels) as SortBy[]).map((k) => (
                      <button
                        key={k}
                        type="button"
                        role="menuitemradio"
                        aria-checked={sortBy === k}
                        class={sortBy === k ? 'sel' : ''}
                        onClick={() => {
                          setSortBy(k);
                          setSortOpen(false);
                        }}
                      >
                        {sortLabels[k]}
                      </button>
                    ))}
                  </div>
                </>
              )}
            </div>
            <div class="segmented" role="radiogroup" aria-label="Gom theo">
              {(
                [
                  ['group', 'Thẻ'],
                  ['type', 'Loại'],
                  ['none', 'Không gom'],
                ] as [GroupBy, string][]
              ).map(([k, label]) => (
                <button key={k} type="button" role="radio" aria-checked={groupBy === k} class={groupBy === k ? 'sel' : ''} onClick={() => setGroupBy(k)}>
                  {label}
                </button>
              ))}
            </div>
          </div>

          <div class="vscroll">
            {total === 0 ? (
              <div class="empty-state">
                <Icon name={q ? 'search' : codes ? 'shield' : 'lock'} size={40} />
                <p>{q ? 'Không tìm thấy' : codes ? 'Chưa có mã 2FA nào' : 'Kho đang trống'}</p>
                {!q && <p class="muted small">Thêm mục trên app, rồi bấm đồng bộ.</p>}
              </div>
            ) : (
              <>
                {favs.length > 0 && (
                  <section>
                    <GroupHeader label="YÊU THÍCH" count={favs.length} collapsed={collapsed.has(FAV)} onToggle={() => toggle(FAV)} />
                    {!collapsed.has(FAV) && grid(favs)}
                  </section>
                )}
                {groups.map(([name, list]) => (
                  <section key={name || '-'}>
                    {name ? <GroupHeader label={name.toUpperCase()} count={list.length} collapsed={collapsed.has(name)} onToggle={() => toggle(name)} /> : <div class="gap" />}
                    {(!name || !collapsed.has(name)) && grid(list)}
                  </section>
                ))}
              </>
            )}
          </div>
        </main>
      </div>
      {open && <DetailDialog key={open.id} it={open} now={now} onClose={() => setOpenId(null)} />}
      <Toast />
    </div>
  );
}
