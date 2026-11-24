import '../totp/migration.dart';
import '../totp/otpauth.dart';
import '../vault/models.dart';
import 'csv.dart';

/// Xuất dữ liệu **không mã hóa** ra các định dạng thông dụng. Bản sao lưu mã hóa là chính file kho (`.vkv`).
/// Giao diện phải cảnh báo và yêu cầu xác thực lại trước khi gọi các hàm này.
abstract final class Exporters {
  static Iterable<Item> _live(Iterable<Item> items, bool includeTrash) => includeTrash ? items : items.where((i) => !i.inTrash);

  /// Chuyển mục có 2FA thành [OtpAuth]; `null` nếu mục không có khóa 2FA.
  static OtpAuth? otpAuthOf(Item i) {
    final t = i.totp;
    if (t == null || t.secret.isEmpty) return null;
    final account = i.valueOf('username') ?? i.valueOf('account') ?? i.subtitle;
    return OtpAuth(
      type: t.isHotp ? OtpType.hotp : OtpType.totp,
      counter: t.counter,
      steam: t.isSteam,
      secret: t.secret,
      issuer: i.title,
      account: account,
      algorithm: t.algorithm,
      digits: t.digits,
      period: t.period,
    );
  }

  /// Mỗi dòng một link `otpauth://`, chỉ gồm các mục có 2FA.
  static String otpauthLines(Iterable<Item> items, {bool includeTrash = false}) =>
      [for (final i in _live(items, includeTrash)) if (otpAuthOf(i) != null) otpAuthOf(i)!.toUri()].join('\n');

  /// Các link `otpauth-migration://` (mỗi link tối đa [perBatch] mục) để quét bằng Google Authenticator.
  static List<String> googleMigrationUris(Iterable<Item> items, {int perBatch = 10, bool includeTrash = false}) {
    // Steam Guard không có trong định dạng của Google Authenticator nên không xuất được.
    final all = [for (final i in _live(items, includeTrash)) if (otpAuthOf(i) != null && !otpAuthOf(i)!.steam) otpAuthOf(i)!];
    if (all.isEmpty) return const [];
    final batches = <List<OtpAuth>>[
      for (var s = 0; s < all.length; s += perBatch) all.sublist(s, (s + perBatch) > all.length ? all.length : s + perBatch),
    ];
    return [for (var b = 0; b < batches.length; b++) Migration.encodeUri(batches[b], batchSize: batches.length, batchIndex: b, batchId: 1)];
  }

  static const csvHeader = ['title', 'group', 'type', 'username', 'password', 'url', 'notes', 'totp', 'favorite'];

  /// CSV: các trường chính ra cột riêng; mọi trường còn lại gom vào cột `notes` dạng `nhãn: giá trị`
  /// để không mất dữ liệu (số thẻ, cụm từ khôi phục, trường tùy chỉnh...).
  static String csv(Iterable<Item> items, {bool includeTrash = false}) {
    final rows = <List<String>>[csvHeader];
    for (final i in _live(items, includeTrash)) {
      final used = <String>{};
      String take(String key) {
        used.add(key);
        return i.valueOf(key) ?? '';
      }

      final username = i.type == ItemType.totp ? take('account') : take('username');
      final password = take('password');
      final url = take('url');
      final notes = <String>[];
      if (i.type == ItemType.note) {
        notes.add(take('content'));
      } else {
        final own = take('notes');
        if (own.isNotEmpty) notes.add(own);
      }
      for (final f in i.fields) {
        if (f.key != null && used.contains(f.key)) continue;
        if (f.value.isEmpty) continue;
        notes.add('${f.label ?? f.key}: ${f.value}');
      }
      rows.add([
        i.title,
        i.group,
        i.typeName,
        username,
        password,
        url,
        notes.join('\n'),
        otpAuthOf(i)?.toUri() ?? '',
        i.favorite ? '1' : '0',
      ]);
    }
    return writeCsv(rows);
  }
}
