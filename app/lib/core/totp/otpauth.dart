import '../errors.dart';
import '../vault/models.dart';
import 'base32.dart';
import 'totp.dart';

enum OtpType { totp, hotp }

/// Một tài khoản 2FA đọc từ link `otpauth://` (hoặc từ dữ liệu nhập khẩu).
final class OtpAuth {
  const OtpAuth({
    required this.type,
    required this.secret,
    this.issuer = '',
    this.account = '',
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.counter = 0,
    this.steam = false,
  });

  final OtpType type;

  /// Base32 chuẩn hóa.
  final String secret;
  final String issuer;
  final String account;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;
  final int counter;

  /// Steam Guard (`encoder=steam`): mã 5 ký tự, chỉ với TOTP.
  final bool steam;

  /// Tên hiển thị gợi ý: nhà phát hành, hoặc tài khoản nếu không có.
  String get title => issuer.isNotEmpty ? issuer : account;

  TotpParams toParams() => TotpParams(
        secret: secret,
        algorithm: algorithm,
        digits: steam ? 5 : digits,
        period: period,
        kind: type == OtpType.hotp ? 'hotp' : (steam ? 'steam' : 'totp'),
        counter: counter,
      );

  /// Đọc link `otpauth://totp/...` hoặc `otpauth://hotp/...`.
  factory OtpAuth.parse(String input) {
    final Uri uri;
    try {
      uri = Uri.parse(input.trim());
    } on FormatException {
      throw const InvalidInputException('link không hợp lệ');
    }
    if (uri.scheme.toLowerCase() != 'otpauth') throw const InvalidInputException('không phải link otpauth://');
    final OtpType type;
    switch (uri.host.toLowerCase()) {
      case 'totp':
        type = OtpType.totp;
      case 'hotp':
        type = OtpType.hotp;
      default:
        throw const InvalidInputException('loại otpauth không được hỗ trợ (chỉ totp và hotp)');
    }

    final q = uri.queryParameters;
    final secretRaw = q['secret'];
    if (secretRaw == null || secretRaw.isEmpty) throw const InvalidInputException('link thiếu secret');
    final secret = Base32.normalize(secretRaw);
    if (secret.length < 8) throw const InvalidInputException('secret quá ngắn');

    // Nhãn: "Nhà phát hành:tài khoản" hoặc chỉ "tài khoản"; tham số issuer ưu tiên hơn tiền tố trong nhãn.
    String decode(String s) {
      try {
        return Uri.decodeComponent(s);
      } on FormatException {
        return s; // mã hóa phần trăm hỏng: giữ nguyên chuỗi gốc
      }
    }

    // Tách ở dấu ":" THẬT trước khi giải mã phần trăm (để nhà phát hành có thể chứa ":" dưới dạng %3A).
    // Nếu không có ":" thật thì mới coi "%3A" là dấu ngăn cách (một số trình tạo link làm vậy).
    final rawLabel = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    var prefix = '';
    String account;
    final literal = rawLabel.indexOf(':');
    if (literal >= 0) {
      prefix = decode(rawLabel.substring(0, literal)).trim();
      account = decode(rawLabel.substring(literal + 1)).trim();
    } else {
      final decoded = decode(rawLabel);
      final colon = decoded.indexOf(':');
      if (colon >= 0) {
        prefix = decoded.substring(0, colon).trim();
        account = decoded.substring(colon + 1).trim();
      } else {
        account = decoded.trim();
      }
    }
    var issuer = (q['issuer'] ?? '').trim();
    if (issuer.isEmpty) issuer = prefix;

    final TotpAlgorithm algo;
    switch ((q['algorithm'] ?? 'SHA1').toUpperCase()) {
      case 'SHA1':
        algo = TotpAlgorithm.sha1;
      case 'SHA256':
        algo = TotpAlgorithm.sha256;
      case 'SHA512':
        algo = TotpAlgorithm.sha512;
      default:
        throw const InvalidInputException('thuật toán không được hỗ trợ (chỉ SHA1, SHA256, SHA512)');
    }

    final digits = int.tryParse(q['digits'] ?? '6');
    if (digits == null || digits < Otp.minDigits || digits > Otp.maxDigits) {
      throw const InvalidInputException('số chữ số phải từ 6 đến 8');
    }
    final period = int.tryParse(q['period'] ?? '30');
    if (period == null || period < 1 || period > 3600) throw const InvalidInputException('chu kỳ không hợp lệ');

    var counter = 0;
    if (type == OtpType.hotp) {
      final c = int.tryParse(q['counter'] ?? '');
      if (c == null || c < 0) throw const InvalidInputException('link hotp thiếu counter');
      counter = c;
    }

    return OtpAuth(
      type: type,
      secret: secret,
      issuer: issuer,
      account: account,
      algorithm: algo,
      digits: digits,
      period: period,
      counter: counter,
      steam: type == OtpType.totp && (q['encoder'] ?? '').toLowerCase() == 'steam',
    );
  }

  /// Dựng lại link `otpauth://`.
  String toUri() {
    final label = issuer.isNotEmpty
        ? '${Uri.encodeComponent(issuer)}:${Uri.encodeComponent(account)}'
        : Uri.encodeComponent(account);
    final params = <String>[
      'secret=$secret',
      if (issuer.isNotEmpty) 'issuer=${Uri.encodeComponent(issuer)}',
      'algorithm=${algorithm.name.toUpperCase()}',
      'digits=$digits',
      if (type == OtpType.totp) 'period=$period' else 'counter=$counter',
      if (steam) 'encoder=steam',
    ];
    return 'otpauth://${type.name}/$label?${params.join('&')}';
  }

  @override
  bool operator ==(Object other) =>
      other is OtpAuth &&
      other.type == type &&
      other.secret == secret &&
      other.issuer == issuer &&
      other.account == account &&
      other.algorithm == algorithm &&
      other.digits == digits &&
      other.period == period &&
      other.counter == counter &&
      other.steam == steam;

  @override
  int get hashCode => Object.hash(type, secret, issuer, account, algorithm, digits, period, counter, steam);
}
