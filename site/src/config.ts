import pubspec from '../../app/pubspec.yaml?raw';

export const REPO = 'https://github.com/kivie9/VanKey';
// Docs moved into docs/technical/ (and other subfolders); map each name to its current path.
const DOC_PATHS: Record<string, string> = {
  'threat-model.md': 'technical/threat-model.md',
  'vault-format.md': 'technical/vault-format.md',
};
export const doc = (name: string) => `${REPO}/blob/main/docs/${DOC_PATHS[name] ?? name}`;

/** Đổi thành true khi đã có GitHub Release: nút tải về sẽ trỏ tới bản mới nhất. */
export const RELEASED: boolean = true;
export const LATEST_RELEASE = `${REPO}/releases/latest`;

/** Phiên bản lấy thẳng từ app/pubspec.yaml để không phải sửa hai nơi. */
export const APP_VERSION = /^version:\s*([0-9.]+)/m.exec(pubspec)?.[1] ?? '';

/** Các cặp trang cùng nội dung ở hai ngôn ngữ [vi, en], dùng cho canonical, hreflang và nút đổi ngôn ngữ. */
const PAGE_PAIRS: [string, string][] = [
  ['/', '/en/'],
  ['/dieu-khoan/', '/en/terms/'],
  ['/quyen-rieng-tu/', '/en/privacy/'],
  ['/xoa-tai-khoan/', '/en/delete-account/'],
  ['/bao-mat/', '/en/security/'],
];

export function pagePair(pathname: string): { vi: string; en: string } {
  const path = pathname.endsWith('/') ? pathname : `${pathname}/`;
  const [vi, en] = PAGE_PAIRS.find((pair) => pair.includes(path)) ?? PAGE_PAIRS[0]!;
  return { vi, en };
}
