import 'dart:convert';
import 'dart:typed_data';

import '../errors.dart';
import 'aead.dart';
import 'csprng.dart';
import 'kdf.dart';
import 'passphrase.dart';
import 'recovery_key.dart';

String b64(List<int> bytes) => base64.encode(bytes);

Uint8List b64d(Object? value, {required int length, required String what}) {
  if (value is! String) throw CorruptVaultException('$what: thiếu hoặc sai kiểu');
  final Uint8List out;
  try {
    out = base64.decode(value);
  } on FormatException {
    throw CorruptVaultException('$what: base64 không hợp lệ');
  }
  if (out.length != length) throw CorruptVaultException('$what: sai độ dài');
  return out;
}

enum KeySlotType { passphrase, recovery }

/// Một "khe khóa": bọc (wrap) vault key bằng một khóa dẫn xuất từ passphrase hoặc recovery key.
///
/// Khe `device` (khóa nằm trong Keystore/Credential Manager) **không** nằm trong file đồng bộ,
/// xem `docs/technical/vault-format.md` mục 3.2.
final class KeySlot {
  const KeySlot({
    required this.id,
    required this.type,
    required this.salt,
    required this.wrapNonce,
    required this.wrapCiphertext,
    this.argon,
    this.hkdfInfo,
  });

  static const recoveryInfo = 'vankey/recovery/v1';
  static const argonAlg = 'argon2id13';
  static const hkdfAlg = 'hkdf-sha256';
  static const wrappedLength = 32 + Aead.tagLength;

  final String id;
  final KeySlotType type;
  final Uint8List salt;
  final Uint8List wrapNonce;
  final Uint8List wrapCiphertext;

  /// Chỉ có ở khe `passphrase`.
  final Argon2Params? argon;

  /// Chỉ có ở khe `recovery`.
  final String? hkdfInfo;

  /// Dữ liệu liên kết (AAD) của phép bọc: gắn khe vào đúng kho, đúng id và đúng tham số,
  /// nên không chép khe sang kho khác được và sửa tham số KDF thì mở khóa thất bại.
  Uint8List aad(String vaultId) {
    final String params;
    switch (type) {
      case KeySlotType.passphrase:
        final a = argon!;
        params = '$argonAlg|${a.opslimit}|${a.memlimitBytes}|${b64(salt)}';
      case KeySlotType.recovery:
        params = '$hkdfAlg|${b64(salt)}|$hkdfInfo';
    }
    return Uint8List.fromList(utf8.encode('vankey/wrap/v1|$vaultId|$id|${type.name}|$params'));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'kdf': switch (type) {
          KeySlotType.passphrase => {
              'alg': argonAlg,
              'opslimit': argon!.opslimit,
              'memlimit': argon!.memlimitBytes,
              'salt': b64(salt),
            },
          KeySlotType.recovery => {
              'alg': hkdfAlg,
              'salt': b64(salt),
              'info': hkdfInfo,
            },
        },
        'wrap': {'nonce': b64(wrapNonce), 'ct': b64(wrapCiphertext)},
      };

  /// Trả `null` nếu loại khe không được biết (để giữ nguyên khi ghi lại, xem `VaultHeader`).
  static KeySlot? fromJson(Map<String, dynamic> j) {
    final typeName = j['type'];
    final id = j['id'];
    if (id is! String || id.isEmpty) throw const CorruptVaultException('keyslot: thiếu id');
    // Loại khe chưa biết (do bản app mới hơn thêm vào): không phân tích, để người gọi giữ nguyên khi ghi lại.
    if (typeName != 'passphrase' && typeName != 'recovery') return null;
    final kdf = j['kdf'];
    final wrap = j['wrap'];
    if (kdf is! Map<String, dynamic> || wrap is! Map<String, dynamic>) {
      throw const CorruptVaultException('keyslot: thiếu kdf hoặc wrap');
    }
    final nonce = b64d(wrap['nonce'], length: Aead.nonceLength, what: 'keyslot.wrap.nonce');
    final ct = b64d(wrap['ct'], length: wrappedLength, what: 'keyslot.wrap.ct');
    final salt = b64d(kdf['salt'], length: Kdf.saltLength, what: 'keyslot.kdf.salt');
    switch (typeName) {
      case 'passphrase':
        if (kdf['alg'] != argonAlg) throw const CorruptVaultException('keyslot: thuật toán KDF không đúng');
        final ops = kdf['opslimit'];
        final mem = kdf['memlimit'];
        if (ops is! int || mem is! int) throw const CorruptVaultException('keyslot: tham số Argon2 sai kiểu');
        final params = Argon2Params(opslimit: ops, memlimitBytes: mem)..validate();
        return KeySlot(
          id: id,
          type: KeySlotType.passphrase,
          salt: salt,
          wrapNonce: nonce,
          wrapCiphertext: ct,
          argon: params,
        );
      case 'recovery':
        if (kdf['alg'] != hkdfAlg) throw const CorruptVaultException('keyslot: thuật toán KDF không đúng');
        final info = kdf['info'];
        if (info is! String) throw const CorruptVaultException('keyslot: thiếu info');
        return KeySlot(
          id: id,
          type: KeySlotType.recovery,
          salt: salt,
          wrapNonce: nonce,
          wrapCiphertext: ct,
          hkdfInfo: info,
        );
      default:
        return null;
    }
  }
}

/// Tạo và mở các khe khóa.
final class KeySlots {
  const KeySlots({this.kdf = const Kdf(), this._random});

  final Kdf kdf;
  final RandomSource? _random;

  RandomSource get _rnd => _random ?? _defaultRandom;
  static final RandomSource _defaultRandom = Csprng();

  Future<KeySlot> createPassphrase({
    required Uint8List vaultKey,
    required String vaultId,
    required String passphrase,
    Argon2Params params = Argon2Params.standard,
  }) async {
    final salt = _rnd.bytes(Kdf.saltLength);
    final kek = await kdf.argon2id(passphraseBytes: normalizePassphrase(passphrase), salt: salt, params: params);
    final draft = KeySlot(
      id: uuidV4(_rnd),
      type: KeySlotType.passphrase,
      salt: salt,
      wrapNonce: _rnd.bytes(Aead.nonceLength),
      wrapCiphertext: Uint8List(0),
      argon: params,
    );
    return _wrap(draft, kek, vaultKey, vaultId);
  }

  Future<KeySlot> createRecovery({
    required Uint8List vaultKey,
    required String vaultId,
    required RecoveryKey recoveryKey,
  }) async {
    final salt = _rnd.bytes(Kdf.saltLength);
    final kek = await _recoveryKek(recoveryKey, salt, KeySlot.recoveryInfo);
    final draft = KeySlot(
      id: uuidV4(_rnd),
      type: KeySlotType.recovery,
      salt: salt,
      wrapNonce: _rnd.bytes(Aead.nonceLength),
      wrapCiphertext: Uint8List(0),
      hkdfInfo: KeySlot.recoveryInfo,
    );
    return _wrap(draft, kek, vaultKey, vaultId);
  }

  Future<KeySlot> _wrap(KeySlot draft, Uint8List kek, Uint8List vaultKey, String vaultId) async {
    final ct = await Aead.seal(key: kek, nonce: draft.wrapNonce, plaintext: vaultKey, aad: draft.aad(vaultId));
    _wipe(kek);
    return KeySlot(
      id: draft.id,
      type: draft.type,
      salt: draft.salt,
      wrapNonce: draft.wrapNonce,
      wrapCiphertext: ct,
      argon: draft.argon,
      hkdfInfo: draft.hkdfInfo,
    );
  }

  /// Mở khe passphrase. Sai passphrase → [AuthenticationFailedException].
  Future<Uint8List> unwrapWithPassphrase(KeySlot slot, String vaultId, String passphrase) async {
    if (slot.type != KeySlotType.passphrase) throw const InvalidInputException('không phải khe passphrase');
    final kek = await kdf.argon2id(
      passphraseBytes: normalizePassphrase(passphrase),
      salt: slot.salt,
      params: slot.argon!,
    );
    return _open(slot, kek, vaultId);
  }

  /// Mở khe recovery. Sai recovery key → [AuthenticationFailedException].
  Future<Uint8List> unwrapWithRecovery(KeySlot slot, String vaultId, RecoveryKey key) async {
    if (slot.type != KeySlotType.recovery) throw const InvalidInputException('không phải khe recovery');
    final kek = await _recoveryKek(key, slot.salt, slot.hkdfInfo ?? KeySlot.recoveryInfo);
    return _open(slot, kek, vaultId);
  }

  Future<Uint8List> _open(KeySlot slot, Uint8List kek, String vaultId) async {
    try {
      return await Aead.open(key: kek, nonce: slot.wrapNonce, sealed: slot.wrapCiphertext, aad: slot.aad(vaultId));
    } finally {
      _wipe(kek);
    }
  }

  Future<Uint8List> _recoveryKek(RecoveryKey key, Uint8List salt, String info) => kdf.hkdfSha256(
        ikm: key.bytes,
        salt: salt,
        info: Uint8List.fromList(utf8.encode(info)),
      );

  static void _wipe(Uint8List b) => b.fillRange(0, b.length, 0);
}
