import 'dart:convert';
import 'dart:typed_data';

import '../crypto/aead.dart';
import '../crypto/csprng.dart';
import '../crypto/keyslot.dart';
import '../errors.dart';

/// Header của file kho (JSON, nằm ngoài phần mã hóa nhưng được xác thực bằng AAD).
final class VaultHeader {
  VaultHeader({
    required this.vaultId,
    required this.revision,
    required this.updatedAt,
    required this.slots,
    this.unknownSlots = const [],
    this.extra = const {},
    this.cipher = cipherName,
  });

  static const cipherName = 'xchacha20poly1305-ietf';

  final String vaultId;
  final int revision;
  final DateTime updatedAt;
  final String cipher;
  final List<KeySlot> slots;

  /// Khe thuộc loại chưa biết: giữ nguyên khi ghi lại để bản app cũ không làm mất khe của bản mới.
  final List<Map<String, dynamic>> unknownSlots;

  /// Các trường lạ ở mức header, cũng giữ nguyên khi ghi lại.
  final Map<String, dynamic> extra;

  /// Số lần các khe khóa (mật khẩu, mã khôi phục) bị đổi. Khi đồng bộ, bên có số lớn hơn thắng.
  int get slotsRev => (extra['slotsRev'] is int) ? extra['slotsRev'] as int : 0;

  VaultHeader copyWith({int? revision, DateTime? updatedAt, List<KeySlot>? slots, List<Map<String, dynamic>>? unknownSlots, Map<String, dynamic>? extra}) => VaultHeader(
        vaultId: vaultId,
        revision: revision ?? this.revision,
        updatedAt: updatedAt ?? this.updatedAt,
        slots: slots ?? this.slots,
        unknownSlots: unknownSlots ?? this.unknownSlots,
        extra: extra ?? this.extra,
        cipher: cipher,
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'vaultId': vaultId,
        'revision': revision,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'cipher': cipher,
        'keyslots': [...slots.map((s) => s.toJson()), ...unknownSlots],
      };

  factory VaultHeader.fromJson(Map<String, dynamic> j) {
    final vaultId = j['vaultId'];
    final revision = j['revision'];
    final updatedAt = j['updatedAt'];
    final cipher = j['cipher'];
    final rawSlots = j['keyslots'];
    if (vaultId is! String || vaultId.isEmpty) throw const CorruptVaultException('header: thiếu vaultId');
    if (revision is! int || revision < 0) throw const CorruptVaultException('header: revision không hợp lệ');
    if (updatedAt is! String) throw const CorruptVaultException('header: thiếu updatedAt');
    if (cipher != cipherName) throw const UnsupportedVersionException('header: thuật toán mã hóa không được hỗ trợ');
    if (rawSlots is! List) throw const CorruptVaultException('header: thiếu keyslots');
    final DateTime when;
    try {
      when = DateTime.parse(updatedAt).toUtc();
    } on FormatException {
      throw const CorruptVaultException('header: updatedAt không hợp lệ');
    }
    final slots = <KeySlot>[];
    final unknown = <Map<String, dynamic>>[];
    for (final s in rawSlots) {
      if (s is! Map<String, dynamic>) throw const CorruptVaultException('header: keyslot sai kiểu');
      final parsed = KeySlot.fromJson(s);
      if (parsed == null) {
        unknown.add(s);
      } else {
        slots.add(parsed);
      }
    }
    const known = {'vaultId', 'revision', 'updatedAt', 'cipher', 'keyslots'};
    return VaultHeader(
      vaultId: vaultId,
      revision: revision,
      updatedAt: when,
      slots: slots,
      unknownSlots: unknown,
      extra: {
        for (final e in j.entries)
          if (!known.contains(e.key)) e.key: e.value,
      },
    );
  }
}

/// File kho đã tách các phần nhưng **chưa giải mã**.
final class ParsedVaultFile {
  const ParsedVaultFile({required this.header, required this.aad, required this.nonce, required this.sealed});

  final VaultHeader header;

  /// Toàn bộ byte từ magic đến hết header; dùng làm AAD khi giải mã dữ liệu.
  final Uint8List aad;
  final Uint8List nonce;

  /// Bản mã || tag.
  final Uint8List sealed;
}

/// Mã hóa/giải mã định dạng `.vkv`. Đặc tả: `docs/technical/vault-format.md`.
abstract final class VaultFileCodec {
  static const magic = [0x56, 0x4B, 0x56, 0x31]; // "VKV1"
  static const formatVersion = 1;
  static const maxHeaderBytes = 64 * 1024;
  static const maxFileBytes = 16 * 1024 * 1024;

  /// Đệm bản rõ đến bội số của khối này (giảm lộ số lượng mục qua kích thước file).
  static const paddingBlock = 4096;

  static Future<Uint8List> encode({
    required VaultHeader header,
    required Uint8List vaultKey,
    required Map<String, dynamic> payload,
    RandomSource? random,
  }) async {
    final headerBytes = Uint8List.fromList(utf8.encode(jsonEncode(header.toJson())));
    if (headerBytes.length > maxHeaderBytes) throw const InvalidInputException('header quá lớn');

    var plain = utf8.encode(jsonEncode(payload));
    final padded = ((plain.length + paddingBlock - 1) ~/ paddingBlock) * paddingBlock;
    final withPad = Uint8List(padded == 0 ? paddingBlock : padded)..fillRange(0, padded == 0 ? paddingBlock : padded, 0x20);
    withPad.setRange(0, plain.length, plain);
    plain = withPad;

    final prefix = BytesBuilder()
      ..add(magic)
      ..add(_u16(formatVersion))
      ..add(_u16(0))
      ..add(_u32(headerBytes.length))
      ..add(headerBytes);
    final aad = prefix.toBytes();

    final nonce = (random ?? Csprng()).bytes(Aead.nonceLength);
    final sealed = await Aead.seal(key: vaultKey, nonce: nonce, plaintext: Uint8List.fromList(plain), aad: aad);

    final out = BytesBuilder()
      ..add(aad)
      ..add(nonce)
      ..add(sealed);
    final bytes = out.toBytes();
    if (bytes.length > maxFileBytes) throw const InvalidInputException('kho vượt quá kích thước tối đa');
    return bytes;
  }

  /// Tách và kiểm tra cấu trúc file, **không** cần khóa.
  static ParsedVaultFile parse(Uint8List bytes) {
    if (bytes.length > maxFileBytes) throw const CorruptVaultException('file quá lớn');
    const fixed = 4 + 2 + 2 + 4;
    if (bytes.length < fixed + Aead.nonceLength + Aead.tagLength) {
      throw const CorruptVaultException('file quá ngắn');
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) throw const CorruptVaultException('không phải file VanKey (sai magic)');
    }
    final view = ByteData.sublistView(bytes);
    final version = view.getUint16(4);
    final flags = view.getUint16(6);
    final headerLen = view.getUint32(8);
    if (version < 1) throw const CorruptVaultException('version không hợp lệ');
    if (version > formatVersion) {
      throw const UnsupportedVersionException('kho được tạo bởi phiên bản VanKey mới hơn, hãy cập nhật ứng dụng');
    }
    if (flags != 0) throw const UnsupportedVersionException('kho dùng tính năng chưa được hỗ trợ');
    if (headerLen == 0 || headerLen > maxHeaderBytes) throw const CorruptVaultException('độ dài header không hợp lệ');
    final headerEnd = fixed + headerLen;
    if (bytes.length < headerEnd + Aead.nonceLength + Aead.tagLength) {
      throw const CorruptVaultException('file bị cắt cụt');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(Uint8List.sublistView(bytes, fixed, headerEnd)));
    } on FormatException {
      throw const CorruptVaultException('header không phải JSON hợp lệ');
    }
    if (decoded is! Map<String, dynamic>) throw const CorruptVaultException('header sai cấu trúc');

    return ParsedVaultFile(
      header: VaultHeader.fromJson(decoded),
      aad: Uint8List.fromList(Uint8List.sublistView(bytes, 0, headerEnd)),
      nonce: Uint8List.fromList(Uint8List.sublistView(bytes, headerEnd, headerEnd + Aead.nonceLength)),
      sealed: Uint8List.fromList(Uint8List.sublistView(bytes, headerEnd + Aead.nonceLength)),
    );
  }

  /// Giải mã dữ liệu. Sai khóa hoặc file bị sửa → [AuthenticationFailedException].
  static Future<Map<String, dynamic>> decrypt(ParsedVaultFile file, Uint8List vaultKey) async {
    final plain = await Aead.open(key: vaultKey, nonce: file.nonce, sealed: file.sealed, aad: file.aad);
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plain));
    } on FormatException {
      throw const CorruptVaultException('dữ liệu sau khi giải mã không phải JSON hợp lệ');
    }
    if (decoded is! Map<String, dynamic>) throw const CorruptVaultException('dữ liệu sai cấu trúc');
    return decoded;
  }

  static Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v);
  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);
}
