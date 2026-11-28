// Tạo test vector cho bản web (TypeScript trong `server/web/`): một file kho `.vkv` hoàn chỉnh, khóa đăng nhập
// Cloudflare và mã TOTP/HOTP/Steam. Bản TS phải đọc đúng y hệt trước khi được đụng vào kho thật.
//
//   dart run tool/make_web_vectors.dart            → ghi test/vectors/web-v1.json
//
// Dữ liệu thử nghiệm, KHÔNG phải bí mật thật. Chạy lại sẽ ra file khác (salt, nonce ngẫu nhiên) nhưng vẫn hợp lệ.
import 'dart:convert';
import 'dart:io';

import 'package:vankey/core/crypto/kdf.dart';
import 'package:vankey/core/sync/cloudflare_sync.dart';
import 'package:vankey/core/totp/base32.dart';
import 'package:vankey/core/totp/totp.dart';
import 'package:vankey/core/vault/models.dart';
import 'package:vankey/core/vault/vault_session.dart';

Future<void> main() async {
  // Passphrase ở dạng tổ hợp (NFD): bản TS phải chuẩn hóa NFKC mới mở được.
  const passphraseNfc = 'Kho thử nghiệm Việt Nam 2026!';
  final passphraseNfd = _nfd(passphraseNfc);

  final payload = <String, dynamic>{
    'schema': 1,
    'groups': ['Cá nhân', 'Công việc'],
    'items': [
      {
        'id': '11111111-1111-4111-8111-111111111111',
        'type': 'login',
        'title': 'GitHub',
        'fields': [
          {'key': 'username', 'value': 'vankey-test', 'secret': false, 'kind': 'text'},
          {'key': 'password', 'value': 'mật-khẩu-giả-123', 'secret': true, 'kind': 'text'},
          {'key': 'url', 'value': 'https://github.com', 'secret': false, 'kind': 'url'},
          {'label': 'Câu hỏi bảo mật', 'value': 'Con mèo', 'secret': true, 'kind': 'text'},
        ],
        'totp': {'secret': 'JBSWY3DPEHPK3PXP', 'algo': 'SHA1', 'digits': 6, 'period': 30},
        'group': 'Công việc',
        'favorite': true,
        'createdAt': '2026-11-01T08:00:00.000Z',
        'updatedAt': '2026-11-02T09:30:00.000Z',
        'deletedAt': null,
        'hlc': '1793000000000:0:devA',
        'futureField': {'x': 1},
      },
      {
        'id': '22222222-2222-4222-8222-222222222222',
        'type': 'note',
        'title': 'Ghi chú',
        'fields': [
          {'key': 'content', 'value': 'Dòng 1\nDòng 2', 'secret': true, 'kind': 'multiline'},
        ],
        'group': '',
        'favorite': false,
        'createdAt': '2026-11-03T08:00:00.000Z',
        'updatedAt': '2026-11-03T08:00:00.000Z',
        'deletedAt': '2026-11-20T08:00:00.000Z',
        'hlc': '1793000000001:2:devB',
      },
    ],
    'tombstones': [
      {'id': '33333333-3333-4333-8333-333333333333', 'deletedAt': '2026-11-10T00:00:00.000Z', 'hlc': '1793000000002:0:devA'},
    ],
  };

  final (session, recovery) = await VaultSession.create(
    passphrase: passphraseNfc,
    initialPayload: payload,
    params: Argon2Params.standard,
  );
  final file = await session.save();

  const username = 'Van.Test';
  const password = 'Mật khẩu đăng nhập 1';
  final passwordNfd = _nfd(password);

  final secret = Base32.decode('JBSWY3DPEHPK3PXP');
  final secret256 = Base32.decode('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA');
  final times = [59, 1111111109, 1793000000];
  final otp = [
    for (final t in times) ...[
      {'secret': 'JBSWY3DPEHPK3PXP', 'algo': 'SHA1', 'digits': 6, 'period': 30, 'time': t, 'code': Otp.totpAt(secret: secret, unixSeconds: t)},
      {
        'secret': 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA',
        'algo': 'SHA256',
        'digits': 8,
        'period': 60,
        'time': t,
        'code': Otp.totpAt(secret: secret256, unixSeconds: t, algorithm: TotpAlgorithm.sha256, digits: 8, period: 60),
      },
      {
        'secret': 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA',
        'algo': 'SHA512',
        'digits': 7,
        'period': 30,
        'time': t,
        'code': Otp.totpAt(secret: secret256, unixSeconds: t, algorithm: TotpAlgorithm.sha512, digits: 7),
      },
      {'kind': 'steam', 'secret': 'JBSWY3DPEHPK3PXP', 'period': 30, 'time': t, 'code': Otp.steamAt(secret: secret, unixSeconds: t)},
    ],
    {'kind': 'hotp', 'secret': 'JBSWY3DPEHPK3PXP', 'algo': 'SHA1', 'digits': 6, 'counter': 7, 'code': Otp.hotp(secret: secret, counter: 7)},
  ];

  final out = {
    '_comment': 'Test vector cho bản web (server/web). Tạo bởi app/tool/make_web_vectors.dart. Dữ liệu thử nghiệm, KHÔNG phải bí mật thật.',
    'vault': {
      'passphraseNfd': passphraseNfd,
      'recoveryKey': recovery.formatted,
      'vaultId': session.vaultId,
      'fileB64': base64.encode(file),
      'payload': payload,
    },
    'auth': {
      'username': username,
      'passwordNfd': passwordNfd,
      'authKey': await CloudflareApi.deriveAuthKey(username, passwordNfd),
      'legacyAuthKey': await CloudflareApi.deriveLegacyAuthKey(username, passwordNfd),
    },
    'otp': otp,
  };
  session.close();
  final path = 'test/vectors/web-v1.json';
  File(path).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  stdout.writeln('Đã ghi $path (${file.length} byte kho)');
}

/// Tách chữ tiếng Việt dựng sẵn thành chữ gốc + dấu rời (đủ cho các chữ dùng ở trên).
String _nfd(String s) {
  const map = {
    'ử': 'ử', 'ệ': 'ệ', 'ậ': 'ậ', 'ẩ': 'ẩ', 'ă': 'ă',
    'ẫ': 'ẫ', 'đ': 'đ', 'á': 'á', 'ê': 'ê', 'ạ': 'ạ', 'ắ': 'ắ',
    'ư': 'ư', 'ơ': 'ơ', 'ở': 'ở', 'ấ': 'ấ', 'ầ': 'ầ',
    'ằ': 'ằ', 'ằ': 'ằ', 'ọ': 'ọ', 'ố': 'ố', 'ớ': 'ớ',
  };
  final sb = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    sb.write(map[ch] ?? ch);
  }
  return sb.toString();
}
