// Logo dịch vụ cho mỗi mục, cùng cách nhận diện với `brandFor` trong app (app/lib/app/brand.dart).
// Bảng logo (~35 KB gzip) được tải riêng sau khi trang đã hiện, nên không làm chậm lần mở đầu.
import { useEffect, useState } from 'preact/hooks';
import type { Item } from '../core/vault.ts';
import { fold } from './labels.ts';

type Brand = [string[], string, string];
let brands: Brand[] | null = null;
let loading: Promise<void> | null = null;
const waiters = new Set<() => void>();

function load(): void {
  loading ??= import('./brands.gen.ts')
    .then((m) => {
      brands = m.BRANDS;
      for (const w of waiters) w();
    })
    .catch(() => {
      loading = null; // mất mạng lần đầu: thử lại lần sau, tạm dùng chữ cái
    });
}

/** Render lại khi bảng logo tải xong. */
export function useBrands(): boolean {
  const [ready, setReady] = useState(brands !== null);
  useEffect(() => {
    if (brands) return;
    const w = () => setReady(true);
    waiters.add(w);
    load();
    return () => void waiters.delete(w);
  }, []);
  return ready;
}

const SKIP = new Set(['www', 'com', 'net', 'org', 'vn', 'io', 'co', 'app', 'me', 'id', 'accounts', 'login', 'auth', 'mail', 'm']);
const cache = new Map<string, Brand | null>();

function brandFor(title: string, url: string): Brand | null {
  if (!brands) return null;
  const key = `${title}\u0000${url}`;
  if (cache.has(key)) return cache.get(key)!;
  const words = new Set(fold(title).split(/[^a-z0-9]+/).filter(Boolean));
  const t = url.trim();
  if (t) {
    try {
      for (const p of new URL(t.includes('://') ? t : `https://${t}`).hostname.toLowerCase().split('.')) if (p && !SKIP.has(p)) words.add(p);
    } catch {
      // địa chỉ hỏng: chỉ dùng tên
    }
  }
  const joined = [...words].join('');
  let found: Brand | null = null;
  outer: for (const b of brands) {
    for (const a of b[0]) {
      if (words.has(a) || (a.length >= 6 && joined.includes(a))) {
        found = b;
        break outer;
      }
    }
  }
  cache.set(key, found);
  return found;
}

/**
 * Màu quá tối (GitHub, X, Apple, Visa...) thì nền tối dùng màu chữ để còn nhìn thấy.
 * Đo bằng độ tương phản WCAG với nền tối của app (#141418): dưới 1,8 thì coi là không thấy.
 */
function isDark(hex: string): boolean {
  const n = parseInt(hex, 16);
  const lin = (v: number) => {
    const c = v / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  const l = 0.2126 * lin((n >> 16) & 255) + 0.7152 * lin((n >> 8) & 255) + 0.0722 * lin(n & 255);
  return (l + 0.05) / (0.0071 + 0.05) < 1.8;
}

export function Logo({ item, size }: { item: Item; size: number }) {
  useBrands();
  const url = item.fields?.find((f) => f.key === 'url')?.value ?? '';
  const b = brandFor(item.title, url);
  if (b) {
    return (
      <svg class={`logo-svg${isDark(b[1]) ? ' dark-brand' : ''}`} width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" style={{ color: `#${b[1]}` }}>
        <path fill="currentColor" d={b[2]} />
      </svg>
    );
  }
  const ch = (item.title.trim()[0] ?? '?').toUpperCase();
  return (
    <span class="logo-letter" style={{ width: `${size}px`, height: `${size}px`, fontSize: `${Math.round(size * 0.78)}px` }} aria-hidden="true">
      {ch}
    </span>
  );
}
