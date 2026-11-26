import 'dart:typed_data';

import '../crypto/csprng.dart';
import '../crypto/kdf.dart';
import '../crypto/keyslot.dart';
import '../crypto/recovery_key.dart';
import '../errors.dart';
import 'vault_file.dart';

/// Phiên làm việc với một kho đã mở: giữ vault key trong bộ nhớ và cho phép lưu lại.
///
/// Dữ liệu ([payload]) ở dạng JSON thô; lớp kiểu (`VaultData`) bọc bên ngoài.
/// Gọi [close] khi khóa app để ghi đè vault key (mức cố gắng tối đa, Dart có bộ thu gom rác).
final class VaultSession {
  VaultSession._(this._header, this._vaultKey, this.payload, this._slots, this._random);

  VaultHeader _header;
  final Uint8List _vaultKey;
  final KeySlots _slots;
  final RandomSource? _random;
  bool _closed = false;

  /// Dữ liệu kho (JSON). Người gọi sửa trực tiếp rồi gọi [save].
  Map<String, dynamic> payload;

  VaultHeader get header => _header;
  String get vaultId => _header.vaultId;
  bool get isClosed => _closed;

  static KeySlots _makeSlots(Kdf kdf, RandomSource? random) => KeySlots(kdf: kdf, random: random);

  /// Tạo kho mới. Trả về phiên và **recovery key** (hiển thị đúng một lần cho người dùng lưu lại).
  static Future<(VaultSession, RecoveryKey)> create({
    required String passphrase,
    Map<String, dynamic>? initialPayload,
    Argon2Params params = Argon2Params.standard,
    Kdf kdf = const Kdf(),
    RandomSource? random,
  }) async {
    final rnd = random ?? Csprng();
    final slots = _makeSlots(kdf, rnd);
    final vaultKey = rnd.bytes(32);
    final vaultId = uuidV4(rnd);
    final recovery = RecoveryKey.generate(rnd);
    final passSlot = await slots.createPassphrase(vaultKey: vaultKey, vaultId: vaultId, passphrase: passphrase, params: params);
    final recSlot = await slots.createRecovery(vaultKey: vaultKey, vaultId: vaultId, recoveryKey: recovery);
    final header = VaultHeader(
      vaultId: vaultId,
      revision: 0,
      updatedAt: DateTime.now().toUtc(),
      slots: [passSlot, recSlot],
    );
    return (VaultSession._(header, vaultKey, initialPayload ?? <String, dynamic>{}, slots, rnd), recovery);
  }

  static Future<VaultSession> openWithPassphrase(
    Uint8List fileBytes,
    String passphrase, {
    Kdf kdf = const Kdf(),
    RandomSource? random,
  }) async {
    final file = VaultFileCodec.parse(fileBytes);
    final slots = _makeSlots(kdf, random);
    Uint8List? key;
    for (final s in file.header.slots.where((s) => s.type == KeySlotType.passphrase)) {
      try {
        key = await slots.unwrapWithPassphrase(s, file.header.vaultId, passphrase);
        break;
      } on AuthenticationFailedException {
        continue;
      }
    }
    if (key == null) throw const AuthenticationFailedException();
    return _finishOpen(file, key, slots, random);
  }

  static Future<VaultSession> openWithRecoveryKey(
    Uint8List fileBytes,
    RecoveryKey recoveryKey, {
    Kdf kdf = const Kdf(),
    RandomSource? random,
  }) async {
    final file = VaultFileCodec.parse(fileBytes);
    final slots = _makeSlots(kdf, random);
    Uint8List? key;
    for (final s in file.header.slots.where((s) => s.type == KeySlotType.recovery)) {
      try {
        key = await slots.unwrapWithRecovery(s, file.header.vaultId, recoveryKey);
        break;
      } on AuthenticationFailedException {
        continue;
      }
    }
    if (key == null) throw const AuthenticationFailedException();
    return _finishOpen(file, key, slots, random);
  }

  /// Mở bằng vault key đã có sẵn (đã cất trong Keystore ở chế độ "Không tự khóa"): bỏ qua Argon2id nên mở gần như tức thì.
  /// Khóa không khớp (kho đã xoay khóa) → [AuthenticationFailedException].
  static Future<VaultSession> openWithKey(Uint8List fileBytes, Uint8List vaultKey, {Kdf kdf = const Kdf(), RandomSource? random}) async {
    if (vaultKey.length != 32) throw const AuthenticationFailedException();
    final file = VaultFileCodec.parse(fileBytes);
    return _finishOpen(file, Uint8List.fromList(vaultKey), _makeSlots(kdf, random), random);
  }

  /// Bản sao vault key để cất vào kho khóa của hệ điều hành. Người gọi tự xóa bản sao khi dùng xong.
  Uint8List exportKey() {
    _ensureOpen();
    return Uint8List.fromList(_vaultKey);
  }

  static Future<VaultSession> _finishOpen(ParsedVaultFile file, Uint8List key, KeySlots slots, RandomSource? random) async {
    try {
      final payload = await VaultFileCodec.decrypt(file, key);
      return VaultSession._(file.header, key, payload, slots, random);
    } catch (_) {
      key.fillRange(0, key.length, 0);
      rethrow;
    }
  }

  Map<String, dynamic> _bumped() => {..._header.extra, 'slotsRev': _header.slotsRev + 1};

  /// Giải mã bản kho từ máy khác (cùng kho) bằng khóa đang giữ. Dùng khi đồng bộ.
  /// Sai kho → [CorruptVaultException]; khóa đã bị xoay hoặc file bị sửa → [AuthenticationFailedException].
  Future<(VaultHeader, Map<String, dynamic>)> decryptRemote(Uint8List fileBytes) async {
    _ensureOpen();
    final file = VaultFileCodec.parse(fileBytes);
    if (file.header.vaultId != vaultId) throw const CorruptVaultException('bản trên máy chủ thuộc kho khác');
    return (file.header, await VaultFileCodec.decrypt(file, _vaultKey));
  }

  /// Nhận các khe khóa từ bản từ xa nếu chúng mới hơn (đã đổi mật khẩu/mã khôi phục ở máy khác).
  void adoptSlotsFrom(VaultHeader remote) {
    _ensureOpen();
    if (remote.slotsRev > _header.slotsRev) {
      _header = _header.copyWith(slots: remote.slots, unknownSlots: remote.unknownSlots, extra: {..._header.extra, 'slotsRev': remote.slotsRev});
    }
  }

  int get slotsRev => _header.slotsRev;

  void _ensureOpen() {
    if (_closed) throw const InvalidInputException('phiên đã đóng');
  }

  /// Mã hóa và trả về byte của file kho. Tăng `revision`, nonce luôn mới.
  Future<Uint8List> save() async {
    _ensureOpen();
    _header = _header.copyWith(revision: _header.revision + 1, updatedAt: DateTime.now().toUtc());
    return VaultFileCodec.encode(header: _header, vaultKey: _vaultKey, payload: payload, random: _random);
  }

  /// Đổi passphrase: chỉ bọc lại vault key, không mã hóa lại dữ liệu.
  Future<void> changePassphrase(String newPassphrase, {Argon2Params params = Argon2Params.standard}) async {
    _ensureOpen();
    final fresh = await _slots.createPassphrase(
      vaultKey: _vaultKey,
      vaultId: vaultId,
      passphrase: newPassphrase,
      params: params,
    );
    _header = _header.copyWith(
      slots: [
        for (final s in _header.slots)
          if (s.type != KeySlotType.passphrase) s,
        fresh,
      ],
      extra: _bumped(),
    );
  }

  /// Tạo recovery key mới và **vô hiệu** recovery key cũ.
  Future<RecoveryKey> regenerateRecoveryKey() async {
    _ensureOpen();
    final rec = RecoveryKey.generate(_random);
    final fresh = await _slots.createRecovery(vaultKey: _vaultKey, vaultId: vaultId, recoveryKey: rec);
    _header = _header.copyWith(
      slots: [
        for (final s in _header.slots)
          if (s.type != KeySlotType.recovery) s,
        fresh,
      ],
      extra: _bumped(),
    );
    return rec;
  }

  /// Xoay vault key (khi nghi lộ): sinh khóa mới, bọc lại bằng [passphrase] (có thể đổi sang passphrase mới)
  /// và một recovery key mới. Các khe và recovery key cũ **mất hiệu lực**; khi [save] dữ liệu được mã hóa bằng khóa mới.
  /// Thiết bị khác phải mở lại kho bằng passphrase hoặc recovery key mới.
  Future<RecoveryKey> rotateVaultKey({required String passphrase, Argon2Params params = Argon2Params.standard}) async {
    _ensureOpen();
    final fresh = (_random ?? Csprng()).bytes(32);
    final passSlot = await _slots.createPassphrase(vaultKey: fresh, vaultId: vaultId, passphrase: passphrase, params: params);
    final rec = RecoveryKey.generate(_random);
    final recSlot = await _slots.createRecovery(vaultKey: fresh, vaultId: vaultId, recoveryKey: rec);
    _vaultKey.setAll(0, fresh);
    fresh.fillRange(0, fresh.length, 0);
    _header = _header.copyWith(slots: [passSlot, recSlot], extra: _bumped());
    return rec;
  }

  /// Ghi đè vault key và đánh dấu phiên đã đóng.
  void close() {
    _vaultKey.fillRange(0, _vaultKey.length, 0);
    _closed = true;
  }
}
