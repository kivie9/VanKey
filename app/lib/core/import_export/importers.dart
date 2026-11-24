import 'dart:convert';
import 'dart:typed_data';

import '../errors.dart';
import '../totp/base32.dart';
import '../totp/migration.dart';
import '../totp/otpauth.dart';
import '../vault/models.dart';
import 'csv.dart';
import 'extra_importers.dart';
import 'imported_item.dart';

/// Các bộ đọc dữ liệu từ ứng dụng khác. Mỗi hàm nhận **toàn bộ nội dung file dạng chuỗi** và trả về
/// [ImportResult] (kèm cảnh báo cho các mục bị bỏ qua). Không hàm nào ném lỗi vì một dòng hỏng; chỉ ném
/// [InvalidInputException] khi cả file sai định dạng, và [EncryptedImportException] khi file đã mã hóa.
abstract final class Importers {
  // ---------------------------------------------------------------- tự nhận diện

  /// Tự đoán định dạng: JSON (Bitwarden, Aegis, 2FAS), danh sách link `otpauth://`, hoặc CSV.
  static ImportResult auto(String text) {
    final t = text.trimLeft().replaceFirst('﻿', '');
    if (t.isEmpty) throw const InvalidInputException('file rỗng');
    if (t.startsWith('{')) {
      final Object? root;
      try {
        root = jsonDecode(t);
      } on FormatException {
        throw const InvalidInputException('JSON không hợp lệ');
      }
      if (root is! Map<String, dynamic>) throw const InvalidInputException('JSON sai cấu trúc');
      if (root.containsKey('db')) return aegis(t);
      if (root.containsKey('services') || root.containsKey('servicesEncrypted')) return twoFas(t);
      if (root.containsKey('items')) return bitwardenJson(t);
      throw const InvalidInputException('không nhận ra định dạng JSON này');
    }
    if (t.startsWith('<') && ExtraImporters.looksLikeKeePassXml(t)) return ExtraImporters.keepassXml(t);
    final firstLine = t.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (firstLine.startsWith('otpauth://') || firstLine.startsWith('otpauth-migration://')) return otpauthLines(t);
    return csv(t);
  }

  /// Như [auto] nhưng nhận byte, để đọc cả file zip (1Password .1pux).
  static ImportResult autoBytes(Uint8List bytes) {
    if (ExtraImporters.isZip(bytes)) return ExtraImporters.onePux(bytes);
    return auto(utf8.decode(bytes, allowMalformed: true));
  }

  // ---------------------------------------------------------------- link otpauth

  /// Mỗi dòng một link `otpauth://` hoặc `otpauth-migration://` (mã QR của Google Authenticator).
  static ImportResult otpauthLines(String text) {
    final items = <ImportedItem>[];
    final warnings = <ImportWarning>[];
    var n = 0;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      n++;
      try {
        if (line.startsWith('otpauth-migration://')) {
          final p = Migration.parseUri(line);
          for (final e in p.entries) {
            _addOtp(e, items, warnings, n);
          }
          for (var i = 0; i < p.skipped; i++) {
            warnings.add(ImportWarning(ImportWarningCode.skippedUnsupported, position: n, detail: 'mục dùng thuật toán chưa hỗ trợ'));
          }
        } else if (line.startsWith('otpauth://')) {
          _addOtp(OtpAuth.parse(line), items, warnings, n);
        } else {
          warnings.add(ImportWarning(ImportWarningCode.invalidLine, position: n));
        }
      } on InvalidInputException catch (e) {
        warnings.add(ImportWarning(ImportWarningCode.invalidLine, position: n, detail: e.message));
      }
    }
    return ImportResult(items: items, warnings: warnings);
  }

  static void _addOtp(OtpAuth o, List<ImportedItem> items, List<ImportWarning> warnings, int pos, {String group = ''}) {
    items.add(ImportedItem(title: o.title, totp: o, group: group));
  }

  // ---------------------------------------------------------------- Aegis

  static ImportResult aegis(String text) {
    final root = _jsonMap(text);
    final db = root['db'];
    if (db is String) throw const EncryptedImportException();
    if (db is! Map<String, dynamic>) throw const InvalidInputException('Aegis: thiếu phần db');
    final groups = {
      for (final g in (db['groups'] as List? ?? const []))
        if (g is Map<String, dynamic>) '${g['uuid']}': '${g['name'] ?? ''}',
    };
    final items = <ImportedItem>[];
    final warnings = <ImportWarning>[];
    var n = 0;
    for (final e in (db['entries'] as List? ?? const [])) {
      n++;
      if (e is! Map<String, dynamic>) {
        warnings.add(ImportWarning(ImportWarningCode.invalidLine, position: n));
        continue;
      }
      final type = '${e['type']}'.toLowerCase();
      final info = e['info'];
      if (!const {'totp', 'hotp', 'steam'}.contains(type) || info is! Map<String, dynamic>) {
        warnings.add(ImportWarning(ImportWarningCode.skippedUnsupported, position: n, detail: type));
        continue;
      }
      var group = '${e['group'] ?? ''}';
      final gl = e['groups'];
      if (group.isEmpty && gl is List && gl.isNotEmpty) group = groups['${gl.first}'] ?? '';
      final o = _otpFrom(
        secret: '${info['secret']}',
        issuer: '${e['issuer'] ?? ''}',
        account: '${e['name'] ?? ''}',
        algo: '${info['algo'] ?? 'SHA1'}',
        digits: info['digits'],
        period: info['period'],
        kind: type,
        counter: info['counter'],
        warnings: warnings,
        pos: n,
      );
      if (o != null) items.add(ImportedItem(title: o.title, totp: o, group: group));
    }
    return ImportResult(items: items, warnings: warnings);
  }

  // ---------------------------------------------------------------- 2FAS

  static ImportResult twoFas(String text) {
    final root = _jsonMap(text);
    final services = root['services'];
    if ((services is! List || services.isEmpty) && root['servicesEncrypted'] is String) {
      throw const EncryptedImportException();
    }
    final groups = {
      for (final g in (root['groups'] as List? ?? const []))
        if (g is Map<String, dynamic>) '${g['id']}': '${g['name'] ?? ''}',
    };
    final items = <ImportedItem>[];
    final warnings = <ImportWarning>[];
    var n = 0;
    for (final s in (services as List? ?? const [])) {
      n++;
      if (s is! Map<String, dynamic>) {
        warnings.add(ImportWarning(ImportWarningCode.invalidLine, position: n));
        continue;
      }
      final otp = s['otp'] is Map<String, dynamic> ? s['otp'] as Map<String, dynamic> : const <String, dynamic>{};
      final tokenType = '${otp['tokenType'] ?? 'TOTP'}'.toUpperCase();
      if (!const {'TOTP', 'HOTP', 'STEAM'}.contains(tokenType)) {
        warnings.add(ImportWarning(ImportWarningCode.skippedUnsupported, position: n, detail: tokenType));
        continue;
      }
      final o = _otpFrom(
        secret: '${s['secret']}',
        issuer: '${otp['issuer'] ?? s['name'] ?? ''}',
        account: '${otp['account'] ?? ''}',
        algo: '${otp['algorithm'] ?? 'SHA1'}',
        digits: otp['digits'],
        period: otp['period'],
        kind: tokenType.toLowerCase(),
        counter: otp['counter'],
        warnings: warnings,
        pos: n,
      );
      if (o != null) items.add(ImportedItem(title: '${s['name'] ?? o.title}', totp: o, group: groups['${s['group']}'] ?? ''));
    }
    return ImportResult(items: items, warnings: warnings);
  }

  static OtpAuth? _otpFrom({
    required String secret,
    required String issuer,
    required String account,
    required String algo,
    required Object? digits,
    required Object? period,
    required List<ImportWarning> warnings,
    required int pos,
    String kind = 'totp',
    Object? counter,
  }) {
    try {
      final a = switch (algo.toUpperCase()) {
        'SHA1' => TotpAlgorithm.sha1,
        'SHA256' => TotpAlgorithm.sha256,
        'SHA512' => TotpAlgorithm.sha512,
        _ => throw const InvalidInputException('thuật toán chưa hỗ trợ'),
      };
      final steam = kind == 'steam';
      final d = steam ? 5 : (digits is int ? digits : 6);
      final p = period is int ? period : 30;
      if ((!steam && (d < 6 || d > 8)) || p < 1 || p > 3600) throw const InvalidInputException('tham số không hợp lệ');
      final c = counter is int && counter >= 0 ? counter : 0;
      return OtpAuth(
        type: kind == 'hotp' ? OtpType.hotp : OtpType.totp,
        secret: Base32.normalize(secret),
        issuer: issuer.trim(),
        account: account.trim(),
        algorithm: a,
        digits: d,
        period: p,
        counter: c,
        steam: steam,
      );
    } on InvalidInputException catch (e) {
      warnings.add(ImportWarning(ImportWarningCode.skippedUnsupported, position: pos, detail: e.message));
      return null;
    }
  }

  // ---------------------------------------------------------------- Bitwarden JSON

  static ImportResult bitwardenJson(String text) {
    final root = _jsonMap(text);
    if (root['encrypted'] == true) throw const EncryptedImportException();
    final folders = {
      for (final f in (root['folders'] as List? ?? const []))
        if (f is Map<String, dynamic>) '${f['id']}': '${f['name'] ?? ''}',
    };
    final items = <ImportedItem>[];
    final warnings = <ImportWarning>[];
    var n = 0;
    for (final e in (root['items'] as List? ?? const [])) {
      n++;
      if (e is! Map<String, dynamic>) {
        warnings.add(ImportWarning(ImportWarningCode.invalidLine, position: n));
        continue;
      }
      final name = '${e['name'] ?? ''}';
      final notes = '${e['notes'] ?? ''}';
      final group = folders['${e['folderId']}'] ?? '';
      final fav = e['favorite'] == true;
      final custom = <Field>[
        for (final f in (e['fields'] as List? ?? const []))
          if (f is Map<String, dynamic> && '${f['name'] ?? ''}'.isNotEmpty)
            Field(label: '${f['name']}', value: '${f['value'] ?? ''}', secret: f['type'] == 1),
      ];
      switch (e['type']) {
        case 1: // đăng nhập
          final login = e['login'] is Map<String, dynamic> ? e['login'] as Map<String, dynamic> : const <String, dynamic>{};
          final uris = login['uris'];
          final url = uris is List && uris.isNotEmpty && uris.first is Map ? '${(uris.first as Map)['uri'] ?? ''}' : '';
          final totpRaw = '${login['totp'] ?? ''}';
          items.add(ImportedItem(
            title: name,
            username: '${login['username'] ?? ''}',
            password: '${login['password'] ?? ''}',
            url: url,
            notes: notes,
            totp: totpRaw.isEmpty ? null : _totpFromString(totpRaw, name, warnings, n),
            group: group,
            favorite: fav,
            extraFields: custom,
          ));
        case 2: // ghi chú bảo mật
          items.add(ImportedItem(title: name, type: ItemType.note, notes: notes, group: group, favorite: fav, extraFields: custom));
        case 3: // thẻ
          final c = e['card'] is Map<String, dynamic> ? e['card'] as Map<String, dynamic> : const <String, dynamic>{};
          final mm = '${c['expMonth'] ?? ''}'.padLeft(2, '0');
          final yy = '${c['expYear'] ?? ''}';
          items.add(ImportedItem(
            title: name,
            type: ItemType.card,
            notes: notes,
            group: group,
            favorite: fav,
            extraValues: {
              'holder': '${c['cardholderName'] ?? ''}',
              'number': '${c['number'] ?? ''}',
              'expiry': yy.isEmpty ? '' : '$mm/${yy.length > 2 ? yy.substring(yy.length - 2) : yy}',
              'cvv': '${c['code'] ?? ''}',
            },
            extraFields: custom,
          ));
        default: // danh tính và loại lạ
          warnings.add(ImportWarning(ImportWarningCode.skippedUnsupported, position: n, detail: 'type ${e['type']}'));
      }
    }
    return ImportResult(items: items, warnings: warnings);
  }

  // ---------------------------------------------------------------- CSV chung

  static const _title = ['title', 'name', 'account', 'item name'];
  static const _user = ['username', 'login_username', 'login name', 'user name', 'user', 'login', 'email'];
  static const _pass = ['password', 'login_password', 'pass'];
  static const _url = ['url', 'login_uri', 'website', 'web site', 'login uri', 'address', 'uri'];
  static const _notes = ['notes', 'note', 'comments', 'comment', 'extra'];
  static const _totp = ['totp', 'login_totp', 'otpauth', 'one-time password', 'otp', 'otp secret', 'totp secret', 'authenticator key'];
  static const _group = ['folder', 'group', 'grouping', 'category', 'vault', 'tags'];
  static const _fav = ['favorite', 'favourite'];

  /// CSV của Bitwarden, 1Password, KeePass, Chrome/Edge và nhiều app khác: nhận diện cột theo tên tiêu đề.
  static ImportResult csv(String text) {
    final rows = parseCsv(text);
    if (rows.isEmpty) throw const InvalidInputException('file CSV rỗng');
    final header = [for (final h in rows.first) h.trim().toLowerCase()];
    int col(List<String> names) {
      for (final n in names) {
        final i = header.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    final iTitle = col(_title), iUser = col(_user), iPass = col(_pass), iUrl = col(_url);
    final iNotes = col(_notes), iTotp = col(_totp), iGroup = col(_group), iFav = col(_fav);
    // "category" vừa có thể là nhóm vừa là loại: ưu tiên cột "type" cho loại.
    final iType = header.indexOf('type');
    if (iTitle < 0 && iUrl < 0) throw const InvalidInputException('không nhận ra định dạng CSV (thiếu cột tên hoặc địa chỉ)');
    if (iUser < 0 && iPass < 0 && iTotp < 0 && iNotes < 0) {
      throw const InvalidInputException('không nhận ra định dạng CSV (thiếu cột tài khoản, mật khẩu hoặc ghi chú)');
    }

    final items = <ImportedItem>[];
    final warnings = <ImportWarning>[];
    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      String cell(int i) => i >= 0 && i < row.length ? row[i].trim() : '';
      String raw(int i) => i >= 0 && i < row.length ? row[i] : '';
      final user = cell(iUser), pass = raw(iPass), url = cell(iUrl), notes = raw(iNotes).trim(), totpRaw = cell(iTotp);
      var title = cell(iTitle);
      if (title.isEmpty && user.isEmpty && pass.isEmpty && url.isEmpty && notes.isEmpty && totpRaw.isEmpty) {
        warnings.add(ImportWarning(ImportWarningCode.emptyEntry, position: r));
        continue;
      }
      if (title.isEmpty) title = _hostOf(url).isNotEmpty ? _hostOf(url) : user;

      var type = ItemType.login;
      if (iType >= 0) {
        final t = cell(iType).toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
        if (t == 'note' || t == 'securenote') {
          type = ItemType.note;
        } else if (t == 'creditcard' || t == 'card' || t == 'identity' || t == 'bankaccount' || t == 'driverlicense' || t == 'passport') {
          warnings.add(ImportWarning(ImportWarningCode.skippedUnsupported, position: r, detail: cell(iType)));
          continue;
        }
      }
      final fav = const {'1', 'true', 'yes', 'y', 'x'}.contains(cell(iFav).toLowerCase());
      items.add(ImportedItem(
        title: title,
        type: type,
        username: user,
        password: pass,
        url: url,
        notes: notes,
        totp: totpRaw.isEmpty ? null : _totpFromString(totpRaw, title, warnings, r),
        group: iGroup >= 0 && iGroup != iType ? cell(iGroup) : '',
        favorite: fav,
      ));
    }
    return ImportResult(items: items, warnings: warnings);
  }

  // ---------------------------------------------------------------- tiện ích

  /// Khóa 2FA từ ô văn bản: link `otpauth://` hoặc chuỗi Base32 thuần.
  static OtpAuth? _totpFromString(String raw, String title, List<ImportWarning> warnings, int pos) {
    try {
      final s = raw.trim();
      if (s.toLowerCase().startsWith('otpauth://')) {
        final o = OtpAuth.parse(s);
        return OtpAuth(
          type: o.type,
          counter: o.counter,
          steam: o.steam,
          secret: o.secret,
          issuer: o.issuer.isEmpty ? title : o.issuer,
          account: o.account,
          algorithm: o.algorithm,
          digits: o.digits,
          period: o.period,
        );
      }
      final secret = Base32.normalize(s);
      if (secret.length < 8) throw const InvalidInputException('khóa quá ngắn');
      return OtpAuth(type: OtpType.totp, secret: secret, issuer: title);
    } on InvalidInputException catch (e) {
      warnings.add(ImportWarning(ImportWarningCode.invalidTotp, position: pos, detail: e.message));
      return null;
    }
  }

  static String _hostOf(String url) {
    final u = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    final h = u?.host ?? '';
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  static Map<String, dynamic> _jsonMap(String text) {
    final Object? root;
    try {
      root = jsonDecode(text.replaceFirst('﻿', ''));
    } on FormatException {
      throw const InvalidInputException('JSON không hợp lệ');
    }
    if (root is! Map<String, dynamic>) throw const InvalidInputException('JSON sai cấu trúc');
    return root;
  }
}
