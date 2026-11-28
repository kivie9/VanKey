import type { ComponentChildren } from 'preact';

// Bố cục chia đôi cho màn đăng nhập và mở khóa: bên trái giới thiệu, bên phải là form.
// Hình vẽ là SVG nằm thẳng trong trang: không tải thêm file, hợp với CSP và chạy được khi ngoại tuyến.

const POINTS = ['Kho được giải mã ngay trên thiết bị của bạn', 'Mật khẩu của bạn không được gửi lên máy chủ', 'Mở được cả khi không có mạng'];

function Pattern() {
  return (
    <svg class="brand-pattern" aria-hidden="true">
      <defs>
        <pattern id="brand-tile" width="160" height="160" patternUnits="userSpaceOnUse" patternTransform="rotate(-12)">
          <g fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">
            {/* chìa khóa */}
            <circle cx="30" cy="34" r="13" />
            <path d="M43 34 H78 M66 34 V45 M76 34 V42" />
            {/* ổ khóa */}
            <rect x="102" y="92" width="34" height="27" rx="6" />
            <path d="M109 92 V83 a10 10 0 0 1 20 0 V92" />
            {/* dấu sao mật khẩu và nét gạch */}
            <path d="M124 22 V46 M114 28 L134 40 M134 28 L114 40" />
            <path d="M18 112 q10 -14 20 0 t20 0 M30 142 h34" />
          </g>
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill="url(#brand-tile)" />
    </svg>
  );
}

function Illustration() {
  return (
    <svg class="brand-art" viewBox="0 0 360 270" aria-hidden="true">
      <ellipse cx="180" cy="252" rx="132" ry="9" fill="#04302a" opacity="0.45" />

      {/* khiên */}
      <path d="M180 22 L272 56 V132 C272 190 233 225 180 248 C127 225 88 190 88 132 V56 Z" fill="#ffffff" stroke="#06201b" stroke-width="5" stroke-linejoin="round" />
      <path d="M180 44 L252 71 V132 C252 176 223 205 180 224 C137 205 108 176 108 132 V71 Z" fill="#d5efe9" />

      {/* ổ khóa */}
      <path d="M154 122 V104 a26 26 0 0 1 52 0 V122" fill="none" stroke="#06201b" stroke-width="10" />
      <rect x="138" y="118" width="84" height="66" rx="14" fill="#f4b740" stroke="#06201b" stroke-width="5" />
      <circle cx="180" cy="145" r="9" fill="#06201b" />
      <path d="M180 148 V164" stroke="#06201b" stroke-width="8" stroke-linecap="round" />

      {/* thẻ mật khẩu */}
      <g transform="rotate(-9 74 78)">
        <rect x="18" y="56" width="112" height="44" rx="12" fill="#ffffff" stroke="#06201b" stroke-width="4" />
        <g fill="#06201b">
          <circle cx="42" cy="78" r="6" />
          <circle cx="63" cy="78" r="6" />
          <circle cx="84" cy="78" r="6" />
          <circle cx="105" cy="78" r="6" />
        </g>
      </g>

      {/* thẻ mã 2FA */}
      <g transform="rotate(7 281 184)">
        <rect x="214" y="158" width="134" height="52" rx="13" fill="#ffffff" stroke="#06201b" stroke-width="4" />
        <text x="228" y="192" class="brand-code" fill="#0b7a6b">
          482 913
        </text>
        <circle cx="328" cy="184" r="8" fill="none" stroke="#d5efe9" stroke-width="4" />
        <path d="M328 176 a8 8 0 1 1 -8 8" fill="none" stroke="#0b7a6b" stroke-width="4" stroke-linecap="round" />
      </g>

      {/* chìa khóa */}
      <g transform="rotate(-24 66 190)" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path d="M70 190 H124 M108 190 V206 M122 190 V202" stroke="#06201b" stroke-width="15" />
        <circle cx="52" cy="190" r="20" stroke="#06201b" stroke-width="17" />
        <path d="M70 190 H124 M108 190 V206 M122 190 V202" stroke="#f4b740" stroke-width="7" />
        <circle cx="52" cy="190" r="20" stroke="#f4b740" stroke-width="9" />
      </g>
    </svg>
  );
}

export function AuthLayout({ logo, children }: { logo: ComponentChildren; children: ComponentChildren }) {
  return (
    <div class="split">
      <aside class="brand">
        <Pattern />
        <div class="brand-text">
          {logo}
          <p class="brand-title">Két an toàn cho mật khẩu và mã 2FA của bạn</p>
          <p class="brand-lead">Mã hóa đầu-cuối. Đồng bộ giữa các thiết bị.</p>
          <ul class="brand-points">
            {POINTS.map((p) => (
              <li key={p}>{p}</li>
            ))}
          </ul>
        </div>
        <Illustration />
      </aside>
      <main class="center">{children}</main>
    </div>
  );
}
