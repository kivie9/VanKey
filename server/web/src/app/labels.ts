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
  address: 'Địa chỉ',
  seedPhrase: 'Cụm từ khôi phục',
  holder: 'Chủ thẻ',
  number: 'Số thẻ',
  cvv: 'CVV',
  pin: 'PIN',
  ssid: 'Tên Wi-Fi',
  security: 'Bảo mật',
  content: 'Nội dung',
  notes: 'Ghi chú',
};

export const TYPE_LABELS: Record<string, string> = {
  login: 'Đăng nhập',
  totp: 'Mã 2FA',
  key: 'Khóa API',
  crypto: 'Ví crypto',
  card: 'Thẻ',
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
