import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../errors.dart';
import '../totp/base32.dart';
import '../totp/otpauth.dart';
import '../vault/models.dart';
import 'imported_item.dart';

/// Bộ đọc thêm: KeePass XML (2.x) và 1Password `.1pux` (file zip).
abstract final class ExtraImporters {
  static OtpAuth? _totp(String raw, String title, List<ImportWarning> warnings, int pos) {
    try {
      final s = raw.trim();
      if (s.isEmpty) return null;
      if (s.toLowerCase().startsWith('otpauth://')) {
        final o = OtpAuth.parse(s);
        return OtpAuth(type: o.type, counter: o.counter, steam: o.steam, secret: o.secret, issuer: o.issuer.isEmpty ? title : o.issuer, account: o.account, algorithm: o.algorithm, digits: o.digits, period: o.period);
      }
      final secret = Base32.normalize(s);
      if (secret.length < 8) throw const InvalidInputException('khóa quá ngắn');
      Base32.decode(secret);
      return OtpAuth(type: OtpType.totp, secret: secret, issuer: title);
    } on InvalidInputException catch (e) {
      warnings.add(ImportWarning(ImportWarningCode.invalidTotp, position: pos, detail: e.message));
      return null;
    }
  }

  // ------------------------------------------------------------------ KeePass XML

  static bool looksLikeKeePassXml(String t) => t.contains('<KeePassFile');

  /// KeePass 2.x → "KeePass XML (2.x)". Nhóm lồng nhau thành tên nhóm dạng `Cha / Con`; bỏ thùng rác của KeePass.
  static ImportResult keepassXml(String text) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(text);
    } on XmlException {
      throw const InvalidInputException('XML không hợp lệ');
    }
    final root = doc.findAllElements('Root').firstOrNull;
    if (root == null) throw const InvalidInputException('không thấy <Root> trong file KeePass');
    final items = <ImportedItem>[];
    final warnings = <ImportWarning>[];
    var n = 0;

    String field(XmlElement entry, String key) {
      for (final s in entry.findElements('String')) {
        if (s.getElement('Key')?.innerText == key) return s.getElement('Value')?.innerText ?? '';
      }
      return '';
    }

    void walk(XmlElement group, List<String> path, {bool isRoot = false}) {
      final name = group.getElement('Name')?.innerText ?? '';
      if (!isRoot && (name == 'Recycle Bin' || name == 'Thùng rác')) return;
      // Nhóm gốc (thường tên "Database"/"Root") không đưa vào tên nhóm.
      final here = isRoot ? path : [...path, if (name.isNotEmpty) name];
      for (final e in group.findElements('Entry')) {
        n++;
        final title = field(e, 'Title');
        final user = field(e, 'UserName');
        final pass = field(e, 'Password');
        final url = field(e, 'URL');
        if (title.isEmpty && user.isEmpty && pass.isEmpty) {
          warnings.add(ImportWarning(ImportWarningCode.emptyEntry, position: n));
          continue;
        }
        final otp = field(e, 'otp').isNotEmpty ? field(e, 'otp') : (field(e, 'TOTP Seed').isNotEmpty ? field(e, 'TOTP Seed') : field(e, 'TimeOtp-Secret-Base32'));
        items.add(ImportedItem(
          title: title.isEmpty ? (user.isEmpty ? url : user) : title,
          username: user,
          password: pass,
          url: url,
          notes: field(e, 'Notes'),
          totp: otp.isEmpty ? null : _totp(otp, title, warnings, n),
          group: here.join(' / '),
        ));
      }
      for (final g in group.findElements('Group')) {
        walk(g, here);
      }
    }

    for (final top in root.findElements('Group')) {
      walk(top, const [], isRoot: true);
    }
    return ImportResult(items: items, warnings: warnings);
  }

  // ------------------------------------------------------------------ 1Password 1pux

  static bool isZip(Uint8List b) => b.length > 4 && b[0] == 0x50 && b[1] == 0x4B;

  /// `.1pux` là file zip chứa `export.data` (JSON). Đọc đăng nhập, mật khẩu, ghi chú; bỏ qua loại khác.
  static ImportResult onePux(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const InvalidInputException('không đọc được file zip .1pux');
    }
    final entry = zip.findFile('export.data');
    if (entry == null) throw const InvalidInputException('không thấy export.data trong file .1pux');
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(entry.content as List<int>));
    } on FormatException {
      throw const InvalidInputException('export.data không phải JSON hợp lệ');
    }
    if (root is! Map<String, dynamic>) throw const InvalidInputException('export.data sai cấu trúc');

    final items = <ImportedItem>[];
    final warnings = <ImportWarning>[];
    var n = 0;
    for (final acc in (root['accounts'] as List? ?? const [])) {
      if (acc is! Map<String, dynamic>) continue;
      for (final v in (acc['vaults'] as List? ?? const [])) {
        if (v is! Map<String, dynamic>) continue;
        final vaultName = ((v['attrs'] as Map?)?['name'] ?? '').toString();
        for (final it in (v['items'] as List? ?? const [])) {
          n++;
          if (it is! Map<String, dynamic>) {
            warnings.add(ImportWarning(ImportWarningCode.invalidLine, position: n));
            continue;
          }
          final item = (it['item'] is Map<String, dynamic>) ? it['item'] as Map<String, dynamic> : it;
          final overview = (item['overview'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
          final details = (item['details'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
          final cat = '${item['categoryUuid'] ?? it['categoryUuid'] ?? ''}';
          final title = '${overview['title'] ?? ''}';
          final fav = (overview['favIndex'] ?? 0) == 1 || it['favIndex'] == 1;
          final notes = '${details['notesPlain'] ?? ''}';

          var user = '';
          var pass = '${details['password'] ?? ''}';
          for (final f in (details['loginFields'] as List? ?? const [])) {
            if (f is! Map) continue;
            if (f['designation'] == 'username') user = '${f['value'] ?? ''}';
            if (f['designation'] == 'password') pass = '${f['value'] ?? ''}';
          }
          String totpRaw = '';
          for (final s in (details['sections'] as List? ?? const [])) {
            if (s is! Map) continue;
            for (final f in (s['fields'] as List? ?? const [])) {
              if (f is! Map) continue;
              final value = f['value'];
              if (value is Map && value['totp'] != null) totpRaw = '${value['totp']}';
            }
          }
          switch (cat) {
            case '001': // đăng nhập
            case '005': // mật khẩu
              items.add(ImportedItem(
                title: title,
                username: user,
                password: pass,
                url: '${overview['url'] ?? ''}',
                notes: notes,
                totp: totpRaw.isEmpty ? null : _totp(totpRaw, title, warnings, n),
                group: vaultName,
                favorite: fav,
              ));
            case '003': // ghi chú bảo mật
              items.add(ImportedItem(title: title, type: ItemType.note, notes: notes, group: vaultName, favorite: fav));
            default:
              warnings.add(ImportWarning(ImportWarningCode.skippedUnsupported, position: n, detail: 'category $cat'));
          }
        }
      }
    }
    return ImportResult(items: items, warnings: warnings);
  }
}
