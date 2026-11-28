// Nhãn tiếng Việt cho trường theo mẫu (khớp `ItemTemplates` trong `app/lib/core/vault/models.dart`).
export const FIELD_LABELS: Record<string, string> = {
  username: 'Tên đăng nhập',
  password: 'Mật khẩu',
  url: 'Địa chỉ web',
  backupCodes: 'Mã dự phòng',
  account: 'Tài khoản',
  service: 'Dịch vụ',
  key: 'Khóa',
  expiry: 'Hết hạn',
  wallet: 'Ví',
  address: 'Địa chỉ ví',
  seedPhrase: 'Cụm từ khôi phục',
  holder: 'Chủ thẻ',
  number: 'Số thẻ',
  cvv: 'CVV',
  pin: 'PIN',
  ssid: 'Tên mạng',
  security: 'Bảo mật',
  content: 'Nội dung',
  notes: 'Ghi chú',
};

export const TYPE_LABELS: Record<string, string> = {
  login: 'Tài khoản',
  totp: 'Mã 2FA',
  key: 'Khóa/API',
  crypto: 'Ví tiền mã hóa',
  card: 'Thẻ ngân hàng',
  wifi: 'Wi-Fi',
  note: 'Ghi chú',
};

/** Bỏ dấu tiếng Việt để tìm "dang nhap" vẫn ra "Đăng nhập". */
export const fold = (s: string): string =>
  s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D')
    .toLowerCase();

/** Chỉ mở liên kết http(s); chặn `javascript:` và các scheme lạ lấy từ dữ liệu kho. */
export function safeUrl(v: string): string | null {
  const s = v.trim();
  const withScheme = /^[a-z][a-z0-9+.-]*:/i.test(s) ? s : `https://${s}`;
  try {
    const u = new URL(withScheme);
    return u.protocol === 'https:' || u.protocol === 'http:' ? u.href : null;
  } catch {
    return null;
  }
}

/** Thứ tự loại trong thanh bên, giống app. */
export const TYPE_ORDER = ['login', 'totp', 'key', 'crypto', 'card', 'wifi', 'note'];

/** Màu mặc định của thẻ (nhóm), cùng công thức với `TagPalette.defaultFor` trong app. */
const TAG_COLORS = ['#4F6BED', '#16A34A', '#EA580C', '#DB2777', '#0891B2', '#7C3AED', '#CA8A04', '#475569'];
export function tagColor(name: string): string {
  const t = name.trim();
  if (!t) return '#94A3B8';
  let h = 0;
  for (const ch of t) h = (h * 31 + ch.codePointAt(0)!) & 0x7fffffff;
  return TAG_COLORS[h % TAG_COLORS.length];
}
