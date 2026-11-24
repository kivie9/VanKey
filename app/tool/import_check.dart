// Kiểm tra bộ đọc nhập khẩu với FILE THẬT của bạn, chưa cần giao diện.
//
//   dart run tool/import_check.dart <file> [--titles] [--codes]
//
// - Không bao giờ in mật khẩu hay khóa bí mật.
// - --titles : liệt kê tên mục, tài khoản (không bí mật) và nhóm.
// - --codes  : in MÃ 2FA hiện tại của các mục có 2FA, để bạn so với app cũ (Google Authenticator, Aegis...).
//              Mã đổi mỗi 30 giây nên hãy so ngay.
// File nhập chứa dữ liệu nhạy cảm: kiểm xong nhớ XÓA file.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:vankey/core/errors.dart';
import 'package:vankey/core/import_export/imported_item.dart';
import 'package:vankey/core/import_export/importers.dart';
import 'package:vankey/core/totp/base32.dart';
import 'package:vankey/core/totp/totp.dart';

void main(List<String> args) {
  final files = args.where((a) => !a.startsWith('--')).toList();
  if (files.isEmpty || args.contains('--help') || args.contains('-h')) {
    print('Cách dùng: dart run tool/import_check.dart <file> [--titles] [--codes]');
    exit(64);
  }
  final file = File(files.first);
  if (!file.existsSync()) {
    print('Không thấy file: ${file.path}');
    exit(66);
  }
  final titles = args.contains('--titles');
  final codes = args.contains('--codes');

  final text = file.readAsStringSync();
  final ImportResult r;
  try {
    r = Importers.auto(text);
  } on EncryptedImportException {
    print('File này đã được MÃ HÓA bởi ứng dụng nguồn. Hãy xuất lại bản không mã hóa từ ứng dụng đó.');
    exit(2);
  } on VaultException catch (e) {
    print('Không đọc được file: ${e.message}');
    exit(1);
  }

  print('Đọc được ${r.items.length} mục, ${r.warnings.length} cảnh báo.');
  final byType = <String, int>{};
  for (final i in r.items) {
    byType[i.type.name] = (byType[i.type.name] ?? 0) + 1;
  }
  byType.forEach((t, n) => print('  - $t: $n'));
  print('  - có khóa 2FA: ${r.items.where((i) => i.totp != null).length}');
  print('  - có nhóm/thư mục: ${r.items.where((i) => i.group.isNotEmpty).length}');

  if (r.warnings.isNotEmpty) {
    print('\nCảnh báo (mục bị bỏ qua hoặc không đọc hết):');
    for (final w in r.warnings) {
      print('  - ${w.code.name}${w.position == null ? '' : ' (mục/dòng ${w.position})'}${w.detail.isEmpty ? '' : ': ${w.detail}'}');
    }
  }

  if (titles) {
    print('\nDanh sách mục:');
    for (final i in r.items) {
      final who = i.username.isNotEmpty ? i.username : (i.totp?.account ?? '');
      print('  - ${i.title}${who.isEmpty ? '' : '  [$who]'}${i.group.isEmpty ? '' : '  (nhóm: ${i.group})'}');
    }
  }

  if (codes) {
    final now = DateTime.now();
    print('\nMã 2FA lúc ${now.toIso8601String()} (còn ${Otp.secondsRemaining(now)} giây trong chu kỳ 30 giây):');
    for (final i in r.items.where((i) => i.totp != null)) {
      final t = i.totp!;
      final code = Otp.totpAt(
        secret: Base32.decode(t.secret),
        unixSeconds: now.millisecondsSinceEpoch ~/ 1000,
        algorithm: t.algorithm,
        digits: t.digits,
        period: t.period,
      );
      print('  ${Otp.grouped(code).padRight(10)}  ${i.title}');
    }
  }
}
