import 'package:material_ui/material_ui.dart';

import 'i18n.dart';

import '../core/vault/models.dart';

/// Nhãn tiếng Việt. Hạ tầng đa ngôn ngữ (ARB vi/en) làm ở bước sau; mọi chữ tập trung ở đây để dễ chuyển.
abstract final class L {
  static const types = {
    ItemType.login: 'Tài khoản',
    ItemType.totp: 'Mã 2FA',
    ItemType.key: 'Khóa/API',
    ItemType.crypto: 'Ví tiền mã hóa',
    ItemType.card: 'Thẻ ngân hàng',
    ItemType.wifi: 'Wi-Fi',
    ItemType.note: 'Ghi chú',
  };

  static const typeIcons = {
    ItemType.login: Icons.person_outline,
    ItemType.totp: Icons.shield_outlined,
    ItemType.key: Icons.vpn_key_outlined,
    ItemType.crypto: Icons.currency_bitcoin,
    ItemType.card: Icons.credit_card,
    ItemType.wifi: Icons.wifi,
    ItemType.note: Icons.sticky_note_2_outlined,
  };

  static const fields = {
    'username': 'Tên đăng nhập',
    'password': 'Mật khẩu',
    'url': 'Địa chỉ web',
    'backupCodes': 'Mã dự phòng',
    'account': 'Tài khoản',
    'service': 'Dịch vụ',
    'key': 'Khóa',
    'expiry': 'Hết hạn',
    'wallet': 'Ví',
    'address': 'Địa chỉ ví',
    'seedPhrase': 'Cụm từ khôi phục',
    'holder': 'Chủ thẻ',
    'number': 'Số thẻ',
    'cvv': 'CVV',
    'pin': 'PIN',
    'ssid': 'Tên mạng',
    'security': 'Bảo mật',
    'content': 'Nội dung',
    'notes': 'Ghi chú',
  };

  static String field(Field f) => f.label?.isNotEmpty == true ? f.label! : (fields[f.key] != null ? tr(fields[f.key]!) : (f.key ?? ''));
  static String fieldKey(String key) => fields[key] != null ? tr(fields[key]!) : key;
  static String type(ItemType t) => types[t] != null ? tr(types[t]!) : t.name;
}
