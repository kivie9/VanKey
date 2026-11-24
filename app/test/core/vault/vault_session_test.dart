import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/crypto/aead.dart';
import 'package:vankey/core/crypto/kdf.dart';
import 'package:vankey/core/crypto/keyslot.dart';
import 'package:vankey/core/crypto/recovery_key.dart';
import 'package:vankey/core/errors.dart';
import 'package:vankey/core/vault/vault_file.dart';
import 'package:vankey/core/vault/vault_session.dart';

import '../../helpers/helpers.dart';

// Tham số nhẹ nhất được phép, để test chạy nhanh. Bản thật dùng Argon2Params.standard.
const fast = Argon2Params(opslimit: 2, memlimitBytes: 32 * 1024 * 1024);

Map<String, dynamic> sample() => {
      'schema': 1,
      'items': [
        {'id': 'a', 'title': 'Ngân hàng Vietcombank', 'pw': 'Đặng Thị Ngọc ✓'},
        {'id': 'b', 'title': '日本語のテスト', 'pw': 'p@ss'},
      ],
    };

void main() {
  late VaultSession session;
  late RecoveryKey recovery;
  late Uint8List file;

  setUp(() async {
    final (s, r) = await VaultSession.create(
      passphrase: 'mật khẩu Việt Nam 123',
      initialPayload: sample(),
      params: fast,
      random: SeededRandom(1),
    );
    session = s;
    recovery = r;
    file = await session.save();
  });

  group('tạo, lưu, mở', () {
    test('mở bằng passphrase trả đúng dữ liệu (cả tiếng Việt, tiếng Nhật)', () async {
      final opened = await VaultSession.openWithPassphrase(file, 'mật khẩu Việt Nam 123');
      expect(opened.payload, sample());
      expect(opened.vaultId, session.vaultId);
    });

    test('mở bằng recovery key', () async {
      final opened = await VaultSession.openWithRecoveryKey(file, recovery);
      expect(opened.payload, sample());
    });

    test('passphrase dạng tổ hợp Unicode vẫn mở được (NFKC)', () async {
      const composed = 'Việt';
      const decomposed = 'Việt';
      final (s, _) = await VaultSession.create(passphrase: composed, params: fast, random: SeededRandom(2));
      final f = await s.save();
      expect((await VaultSession.openWithPassphrase(f, decomposed)).vaultId, s.vaultId);
    });

    test('kho mới có đúng 1 khe passphrase và 1 khe recovery', () {
      expect(session.header.slots.map((s) => s.type), [KeySlotType.passphrase, KeySlotType.recovery]);
    });

    test('mỗi lần lưu: revision tăng, nonce mới nên byte khác nhau dù dữ liệu y hệt', () async {
      final r1 = session.header.revision;
      final a = await session.save();
      final b = await session.save();
      expect(session.header.revision, r1 + 2);
      expect(a, isNot(b));
    });
  });

  group('sai khóa', () {
    test('sai passphrase → lỗi xác thực', () async {
      await expectLater(VaultSession.openWithPassphrase(file, 'sai mat khau'), throwsA(isA<AuthenticationFailedException>()));
    });

    test('sai recovery key → lỗi xác thực', () async {
      await expectLater(
          VaultSession.openWithRecoveryKey(file, RecoveryKey.generate(SeededRandom(99))), throwsA(isA<AuthenticationFailedException>()));
    });

    test('khác biệt hoa thường và khoảng trắng đều làm sai', () async {
      await expectLater(VaultSession.openWithPassphrase(file, 'Mật khẩu Việt Nam 123'), throwsA(isA<AuthenticationFailedException>()));
      await expectLater(VaultSession.openWithPassphrase(file, 'mật khẩu Việt Nam 123 '), throwsA(isA<AuthenticationFailedException>()));
    });
  });

  group('đổi passphrase và recovery key', () {
    test('đổi passphrase: mới mở được, cũ không, recovery key vẫn mở được', () async {
      await session.changePassphrase('passphrase mới 456', params: fast);
      final f2 = await session.save();
      expect((await VaultSession.openWithPassphrase(f2, 'passphrase mới 456')).payload, sample());
      await expectLater(VaultSession.openWithPassphrase(f2, 'mật khẩu Việt Nam 123'), throwsA(isA<AuthenticationFailedException>()));
      expect((await VaultSession.openWithRecoveryKey(f2, recovery)).payload, sample());
    });

    test('tạo recovery key mới: khóa cũ mất hiệu lực, khóa mới và passphrase mở được', () async {
      final newRec = await session.regenerateRecoveryKey();
      final f2 = await session.save();
      await expectLater(VaultSession.openWithRecoveryKey(f2, recovery), throwsA(isA<AuthenticationFailedException>()));
      expect((await VaultSession.openWithRecoveryKey(f2, newRec)).payload, sample());
      expect((await VaultSession.openWithPassphrase(f2, 'mật khẩu Việt Nam 123')).payload, sample());
    });

    test('xoay vault key: khóa cũ bị vô hiệu, dữ liệu nguyên vẹn, file cũ không còn giải mã bằng khóa mới', () async {
      final oldFile = file;
      final newRec = await session.rotateVaultKey(passphrase: 'passphrase mới 456', params: fast);
      final f2 = await session.save();
      expect((await VaultSession.openWithPassphrase(f2, 'passphrase mới 456')).payload, sample());
      expect((await VaultSession.openWithRecoveryKey(f2, newRec)).payload, sample());
      await expectLater(VaultSession.openWithRecoveryKey(f2, recovery), throwsA(isA<AuthenticationFailedException>()));
      // File cũ vẫn mở được bằng thông tin cũ (nó là bản sao cũ, không bị đụng tới).
      expect((await VaultSession.openWithPassphrase(oldFile, 'mật khẩu Việt Nam 123')).payload, sample());
    });

    test('đóng phiên: không lưu/đổi khóa được nữa', () async {
      session.close();
      expect(session.isClosed, isTrue);
      await expectLater(session.save(), throwsA(isA<InvalidInputException>()));
      await expectLater(session.changePassphrase('x', params: fast), throwsA(isA<InvalidInputException>()));
    });
  });

  group('file hỏng hoặc bị sửa', () {
    test('sai magic → CorruptVaultException', () {
      final bad = Uint8List.fromList(file)..[0] ^= 1;
      expect(() => VaultFileCodec.parse(bad), throwsA(isA<CorruptVaultException>()));
    });

    test('quá ngắn, cắt cụt → CorruptVaultException', () {
      expect(() => VaultFileCodec.parse(Uint8List(10)), throwsA(isA<CorruptVaultException>()));
      expect(() => VaultFileCodec.parse(Uint8List.sublistView(file, 0, 40)), throwsA(isA<CorruptVaultException>()));
    });

    test('version cao hơn hoặc cờ lạ → UnsupportedVersionException', () {
      final v2 = Uint8List.fromList(file)..[5] = 2;
      expect(() => VaultFileCodec.parse(v2), throwsA(isA<UnsupportedVersionException>()));
      final flags = Uint8List.fromList(file)..[7] = 1;
      expect(() => VaultFileCodec.parse(flags), throwsA(isA<UnsupportedVersionException>()));
    });

    test('sửa 1 byte bất kỳ trong header hoặc dữ liệu → không bao giờ mở được', () async {
      // Quét một số vị trí rải khắp file: mỗi lần sửa phải thất bại (lỗi xác thực/hỏng/thiếu hỗ trợ), không trả dữ liệu.
      final positions = <int>{
        for (var i = 8; i < 60; i += 5) i,
        file.length ~/ 3,
        file.length ~/ 2,
        file.length - 20,
        file.length - 1,
      };
      for (final pos in positions) {
        final bad = Uint8List.fromList(file)..[pos] ^= 0x01;
        await expectLater(
          VaultSession.openWithPassphrase(bad, 'mật khẩu Việt Nam 123'),
          throwsA(isA<VaultException>()),
          reason: 'sửa byte $pos phải bị phát hiện',
        );
      }
    });

    test('file là JSON rác sau magic hợp lệ → CorruptVaultException', () {
      final headerJunk = utf8.encode('{not json');
      final b = BytesBuilder()
        ..add(VaultFileCodec.magic)
        ..add([0, 1, 0, 0])
        ..add([0, 0, 0, headerJunk.length])
        ..add(headerJunk)
        ..add(Uint8List(24 + 16));
      expect(() => VaultFileCodec.parse(b.toBytes()), throwsA(isA<CorruptVaultException>()));
    });

    test('header chứa tham số KDF quá yếu/quá nặng → WeakKdfParametersException khi đọc', () async {
      final rnd = SeededRandom(5);
      final key = rnd.bytes(32);
      final good = session.header.slots.first;
      for (final bad in const [
        Argon2Params(opslimit: 1, memlimitBytes: 64 * 1024 * 1024),
        Argon2Params(opslimit: 3, memlimitBytes: 2 * 1024 * 1024 * 1024),
      ]) {
        final slot = KeySlot(
          id: good.id,
          type: KeySlotType.passphrase,
          salt: good.salt,
          wrapNonce: good.wrapNonce,
          wrapCiphertext: good.wrapCiphertext,
          argon: bad,
        );
        final f = await VaultFileCodec.encode(
          header: VaultHeader(vaultId: 'v', revision: 1, updatedAt: DateTime.now(), slots: [slot]),
          vaultKey: key,
          payload: {},
        );
        expect(() => VaultFileCodec.parse(f), throwsA(isA<WeakKdfParametersException>()));
      }
    });

    test('chép khe sang kho khác (vaultId khác) → không mở được (AAD gắn vaultId)', () async {
      final parsed = VaultFileCodec.parse(file);
      final key = SeededRandom(8).bytes(32);
      final moved = await VaultFileCodec.encode(
        header: VaultHeader(vaultId: 'kho-khac', revision: 1, updatedAt: DateTime.now(), slots: parsed.header.slots),
        vaultKey: key,
        payload: {},
      );
      await expectLater(VaultSession.openWithPassphrase(moved, 'mật khẩu Việt Nam 123'), throwsA(isA<AuthenticationFailedException>()));
    });
  });

  group('định dạng', () {
    test('kích thước phần mã hóa luôn là bội số của 4096 + 16 (đệm)', () async {
      for (final n in [0, 1, 100, 4000, 5000]) {
        final (s, _) = await VaultSession.create(
          passphrase: 'x',
          initialPayload: {'pad': 'a' * n},
          params: fast,
          random: SeededRandom(n),
        );
        final f = await s.save();
        final parsed = VaultFileCodec.parse(f);
        expect((parsed.sealed.length - Aead.tagLength) % VaultFileCodec.paddingBlock, 0, reason: 'n=$n');
      }
    });

    test('hai kho nhỏ khác nội dung có cùng kích thước bản mã', () async {
      final (a, _) = await VaultSession.create(passphrase: 'x', initialPayload: {'k': 'aaa'}, params: fast, random: SeededRandom(1));
      final (b, _) = await VaultSession.create(passphrase: 'x', initialPayload: {'k': 'bbbbbbbbbb'}, params: fast, random: SeededRandom(2));
      expect(VaultFileCodec.parse(await a.save()).sealed.length, VaultFileCodec.parse(await b.save()).sealed.length);
    });

    test('giữ nguyên khe lạ và trường header lạ khi mở rồi ghi lại', () async {
      final parsed = VaultFileCodec.parse(file);
      final withUnknown = VaultHeader(
        vaultId: parsed.header.vaultId,
        revision: 5,
        updatedAt: DateTime.now(),
        slots: parsed.header.slots,
        unknownSlots: [
          {'id': 'future', 'type': 'hardware-key', 'blob': 'xyz'},
        ],
        extra: {'futureField': 42},
      );
      // Cần vault key thật để ghi lại: lấy từ một phiên mở.
      final opened = await VaultSession.openWithPassphrase(file, 'mật khẩu Việt Nam 123');
      final bytes = await VaultFileCodec.encode(
        header: withUnknown,
        vaultKey: await _vaultKeyOf(opened, file),
        payload: opened.payload,
      );
      final reparsed = VaultFileCodec.parse(bytes).header;
      expect(reparsed.unknownSlots.single['type'], 'hardware-key');
      expect(reparsed.extra['futureField'], 42);
      // Vẫn mở được bình thường dù có khe lạ.
      expect((await VaultSession.openWithPassphrase(bytes, 'mật khẩu Việt Nam 123')).payload, sample());
    });
  });

  test('Argon2id tham số chuẩn (64 MiB, 3 vòng) tạo và mở kho đúng', () async {
    final (s, r) = await VaultSession.create(passphrase: 'chuẩn', initialPayload: sample(), random: SeededRandom(11));
    final f = await s.save();
    expect((await VaultSession.openWithPassphrase(f, 'chuẩn')).payload, sample());
    expect((await VaultSession.openWithRecoveryKey(f, r)).payload, sample());
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Lấy lại vault key của một phiên đã mở (chỉ dùng trong test) bằng cách mở khe passphrase lần nữa.
Future<Uint8List> _vaultKeyOf(VaultSession s, Uint8List fileBytes) async {
  final parsed = VaultFileCodec.parse(fileBytes);
  final slot = parsed.header.slots.firstWhere((x) => x.type == KeySlotType.passphrase);
  return const KeySlots().unwrapWithPassphrase(slot, parsed.header.vaultId, 'mật khẩu Việt Nam 123');
}
