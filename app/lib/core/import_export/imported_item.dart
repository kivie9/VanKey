import '../crypto/csprng.dart';
import '../totp/otpauth.dart';
import '../vault/hlc.dart';
import '../vault/models.dart';

enum ImportWarningCode {
  /// Mục bị bỏ qua vì loại chưa hỗ trợ (Steam, danh tính, MD5...).
  skippedUnsupported,

  /// Khóa 2FA không hợp lệ nên chỉ nhập phần còn lại.
  invalidTotp,

  /// Dòng/mục không có dữ liệu dùng được.
  emptyEntry,

  /// Dòng không đọc được.
  invalidLine,
}

final class ImportWarning {
  const ImportWarning(this.code, {this.position, this.detail = ''});

  final ImportWarningCode code;

  /// Số thứ tự dòng hoặc mục (bắt đầu từ 1) nếu biết.
  final int? position;
  final String detail;

  @override
  String toString() => 'ImportWarning($code${position == null ? '' : ' #$position'}${detail.isEmpty ? '' : ': $detail'})';
}

/// Một mục đọc được từ nguồn ngoài, chưa phải [Item] của kho.
final class ImportedItem {
  const ImportedItem({
    required this.title,
    this.type = ItemType.login,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.totp,
    this.group = '',
    this.favorite = false,
    this.extraValues = const {},
    this.extraFields = const [],
  });

  final String title;
  final ItemType type;
  final String username;
  final String password;
  final String url;
  final String notes;
  final OtpAuth? totp;
  final String group;
  final bool favorite;

  /// Giá trị cho các trường theo mẫu của [type] ngoài username/password/url (ví dụ thẻ: `holder`, `number`).
  final Map<String, String> extraValues;

  /// Trường người dùng tự thêm (ví dụ trường tùy chỉnh của Bitwarden).
  final List<Field> extraFields;

  /// Giá trị dùng để phát hiện trùng với mục đã có: tên (không phân biệt hoa thường) và tài khoản.
  String get dedupeKey => '${title.trim().toLowerCase()}|${(username.isNotEmpty ? username : (totp?.account ?? '')).trim().toLowerCase()}';

  Item toItem({required HlcClock clock, String? groupOverride, DateTime? now, RandomSource? random}) {
    final values = <String, String>{};
    final custom = <Field>[...extraFields];
    var itemType = type;

    // Nguồn chỉ có 2FA (không mật khẩu): dùng loại "Chỉ 2FA".
    final onlyTotp = type == ItemType.login && totp != null && username.isEmpty && password.isEmpty && url.isEmpty;
    if (onlyTotp) itemType = ItemType.totp;

    switch (itemType) {
      case ItemType.login:
        values['username'] = username;
        values['password'] = password;
        values['url'] = url;
      case ItemType.totp:
        values['account'] = totp?.account.isNotEmpty == true ? totp!.account : username;
      case ItemType.note:
        values['content'] = notes;
      default:
        values.addAll(extraValues);
        if (username.isNotEmpty && itemType == ItemType.wifi) values['ssid'] = username;
        if (password.isNotEmpty && itemType == ItemType.wifi) values['password'] = password;
    }
    if (notes.isNotEmpty && itemType != ItemType.note) {
      custom.add(Field(key: 'notes', value: notes, secret: true, kind: 'multiline'));
    }

    return Item.create(
      type: itemType,
      title: title.isEmpty ? (totp?.title ?? url) : title,
      clock: clock,
      values: values,
      customFields: custom,
      totp: totp?.toParams(),
      group: groupOverride ?? group,
      favorite: favorite,
      now: now,
      random: random,
    );
  }
}

final class ImportResult {
  const ImportResult({required this.items, this.warnings = const []});

  final List<ImportedItem> items;
  final List<ImportWarning> warnings;

  /// Đánh dấu mục trùng với mục đã có trong kho (cùng tên và tài khoản).
  List<({ImportedItem item, bool duplicate})> markDuplicates(Iterable<Item> existing) {
    final keys = {
      for (final e in existing)
        '${e.title.trim().toLowerCase()}|${(e.valueOf('username') ?? e.valueOf('account') ?? '').trim().toLowerCase()}',
    };
    return [for (final i in items) (item: i, duplicate: keys.contains(i.dedupeKey))];
  }
}
