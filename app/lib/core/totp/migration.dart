import 'dart:convert';
import 'dart:typed_data';

import '../errors.dart';
import '../vault/models.dart';
import 'base32.dart';
import 'otpauth.dart';

/// Kết quả đọc một mã QR "Xuất tài khoản" của Google Authenticator (`otpauth-migration://`).
///
/// Một lần xuất có thể chia thành nhiều mã QR ([batchSize]); mỗi mã có [batchIndex] riêng.
final class MigrationPayload {
  const MigrationPayload({
    required this.entries,
    required this.skipped,
    this.version = 1,
    this.batchSize = 1,
    this.batchIndex = 0,
    this.batchId = 0,
  });

  final List<OtpAuth> entries;

  /// Số mục bị bỏ qua vì dùng thuật toán chưa hỗ trợ (ví dụ MD5).
  final int skipped;
  final int version;
  final int batchSize;
  final int batchIndex;
  final int batchId;
}

/// Đọc/ghi định dạng protobuf của Google Authenticator, viết tay để không cần thêm thư viện.
///
/// ```
/// MigrationPayload { repeated OtpParameters otp_parameters = 1; int32 version = 2;
///                    int32 batch_size = 3; int32 batch_index = 4; int32 batch_id = 5; }
/// OtpParameters    { bytes secret = 1; string name = 2; string issuer = 3;
///                    Algorithm algorithm = 4;  // 1 SHA1, 2 SHA256, 3 SHA512, 4 MD5
///                    DigitCount digits = 5;    // 1 = 6 chữ số, 2 = 8 chữ số
///                    OtpType type = 6;         // 1 HOTP, 2 TOTP
///                    int64 counter = 7; }
/// ```
abstract final class Migration {
  /// Giới hạn kích thước để chống dữ liệu độc.
  static const maxBytes = 1024 * 1024;

  static MigrationPayload parseUri(String input) {
    final Uri uri;
    try {
      uri = Uri.parse(input.trim());
    } on FormatException {
      throw const InvalidInputException('link không hợp lệ');
    }
    if (uri.scheme.toLowerCase() != 'otpauth-migration') {
      throw const InvalidInputException('không phải link otpauth-migration://');
    }
    var data = uri.queryParameters['data'];
    if (data == null || data.isEmpty) throw const InvalidInputException('link thiếu dữ liệu');
    // Dấu "+" của base64 có thể bị đọc thành khoảng trắng khi link không mã hóa %2B; và có thể là base64 URL-safe.
    data = data.replaceAll(' ', '+').replaceAll('-', '+').replaceAll('_', '/');
    while (data!.length % 4 != 0) {
      data += '=';
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(data);
    } on FormatException {
      throw const InvalidInputException('dữ liệu base64 không hợp lệ');
    }
    return parseBytes(bytes);
  }

  static MigrationPayload parseBytes(Uint8List bytes) {
    if (bytes.length > maxBytes) throw const InvalidInputException('dữ liệu quá lớn');
    final r = _Reader(bytes);
    final entries = <OtpAuth>[];
    var skipped = 0;
    var version = 1, batchSize = 1, batchIndex = 0, batchId = 0;
    while (!r.eof) {
      final tag = r.varint();
      final field = tag >> 3;
      final wire = tag & 7;
      switch ((field, wire)) {
        case (1, 2):
          final entry = _parseEntry(r.lengthDelimited());
          if (entry == null) {
            skipped++;
          } else {
            entries.add(entry);
          }
        case (2, 0):
          version = r.varint();
        case (3, 0):
          batchSize = r.varint();
        case (4, 0):
          batchIndex = r.varint();
        case (5, 0):
          batchId = r.varint();
        default:
          r.skip(wire);
      }
    }
    return MigrationPayload(
      entries: entries,
      skipped: skipped,
      version: version,
      batchSize: batchSize,
      batchIndex: batchIndex,
      batchId: batchId,
    );
  }

  /// `null` nếu mục dùng thuật toán chưa hỗ trợ (MD5) hoặc loại không rõ.
  static OtpAuth? _parseEntry(Uint8List bytes) {
    final r = _Reader(bytes);
    Uint8List secret = Uint8List(0);
    var name = '', issuer = '';
    var algorithm = 0, digits = 0, type = 0, counter = 0;
    while (!r.eof) {
      final tag = r.varint();
      final field = tag >> 3;
      final wire = tag & 7;
      switch ((field, wire)) {
        case (1, 2):
          secret = r.lengthDelimited();
        case (2, 2):
          name = utf8.decode(r.lengthDelimited(), allowMalformed: true);
        case (3, 2):
          issuer = utf8.decode(r.lengthDelimited(), allowMalformed: true);
        case (4, 0):
          algorithm = r.varint();
        case (5, 0):
          digits = r.varint();
        case (6, 0):
          type = r.varint();
        case (7, 0):
          counter = r.varint();
        default:
          r.skip(wire);
      }
    }
    if (secret.isEmpty) return null;
    final TotpAlgorithm algo;
    switch (algorithm) {
      case 0 || 1:
        algo = TotpAlgorithm.sha1;
      case 2:
        algo = TotpAlgorithm.sha256;
      case 3:
        algo = TotpAlgorithm.sha512;
      default:
        return null; // MD5 và các giá trị lạ
    }
    var account = name.trim();
    var iss = issuer.trim();
    if (iss.isEmpty && account.contains(':')) {
      final i = account.indexOf(':');
      iss = account.substring(0, i).trim();
      account = account.substring(i + 1).trim();
    } else if (iss.isNotEmpty && account.startsWith('$iss:')) {
      account = account.substring(iss.length + 1).trim();
    }
    return OtpAuth(
      type: type == 1 ? OtpType.hotp : OtpType.totp,
      secret: Base32.encode(secret),
      issuer: iss,
      account: account,
      algorithm: algo,
      digits: digits == 2 ? 8 : 6,
      counter: counter,
    );
  }

  /// Ghi các mục thành một payload (một lô). Dùng để xuất sang Google Authenticator và để test.
  static Uint8List encode(List<OtpAuth> entries, {int version = 1, int batchSize = 1, int batchIndex = 0, int batchId = 1}) {
    final w = BytesBuilder();
    for (final e in entries) {
      final inner = BytesBuilder();
      _writeBytes(inner, 1, Base32.decode(e.secret));
      _writeBytes(inner, 2, utf8.encode(e.issuer.isEmpty ? e.account : '${e.issuer}:${e.account}'));
      if (e.issuer.isNotEmpty) _writeBytes(inner, 3, utf8.encode(e.issuer));
      _writeVarintField(
        inner,
        4,
        switch (e.algorithm) {
          TotpAlgorithm.sha1 => 1,
          TotpAlgorithm.sha256 => 2,
          TotpAlgorithm.sha512 => 3,
        },
      );
      _writeVarintField(inner, 5, e.digits == 8 ? 2 : 1);
      _writeVarintField(inner, 6, e.type == OtpType.hotp ? 1 : 2);
      if (e.type == OtpType.hotp) _writeVarintField(inner, 7, e.counter);
      _writeBytes(w, 1, inner.toBytes());
    }
    _writeVarintField(w, 2, version);
    _writeVarintField(w, 3, batchSize);
    _writeVarintField(w, 4, batchIndex);
    _writeVarintField(w, 5, batchId);
    return w.toBytes();
  }

  static String encodeUri(List<OtpAuth> entries, {int batchSize = 1, int batchIndex = 0, int batchId = 1}) {
    final data = base64.encode(encode(entries, batchSize: batchSize, batchIndex: batchIndex, batchId: batchId));
    return 'otpauth-migration://offline?data=${Uri.encodeQueryComponent(data)}';
  }

  static void _writeVarint(BytesBuilder b, int value) {
    var v = value;
    while (v >= 0x80) {
      b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }

  static void _writeVarintField(BytesBuilder b, int field, int value) {
    _writeVarint(b, (field << 3) | 0);
    _writeVarint(b, value);
  }

  static void _writeBytes(BytesBuilder b, int field, List<int> value) {
    _writeVarint(b, (field << 3) | 2);
    _writeVarint(b, value.length);
    b.add(value);
  }
}

/// Bộ đọc protobuf tối thiểu, có kiểm tra biên: dữ liệu hỏng → [InvalidInputException], không bao giờ vượt biên.
final class _Reader {
  _Reader(this._b);

  final Uint8List _b;
  int _p = 0;

  bool get eof => _p >= _b.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_p >= _b.length) throw const InvalidInputException('dữ liệu protobuf bị cắt cụt');
      final byte = _b[_p++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const InvalidInputException('varint quá dài');
    }
  }

  Uint8List lengthDelimited() {
    final len = varint();
    if (len < 0 || len > _b.length - _p) throw const InvalidInputException('độ dài trường vượt quá dữ liệu');
    final out = Uint8List.sublistView(_b, _p, _p + len);
    _p += len;
    return out;
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        varint();
      case 1:
        _advance(8);
      case 2:
        lengthDelimited();
      case 5:
        _advance(4);
      default:
        throw const InvalidInputException('kiểu dữ liệu protobuf không hỗ trợ');
    }
  }

  void _advance(int n) {
    if (n > _b.length - _p) throw const InvalidInputException('dữ liệu protobuf bị cắt cụt');
    _p += n;
  }
}
