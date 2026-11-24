import 'dart:isolate';
import 'dart:typed_data';

import '../core/crypto/calibrate.dart';
import '../core/crypto/kdf.dart';
import '../core/crypto/recovery_key.dart';
import '../core/sync/cloudflare_sync.dart';
import '../core/vault/vault_session.dart';

// Các phép tính nặng (Argon2id, ~1 giây) chạy trong isolate riêng để giao diện không đứng.
//
// QUAN TRỌNG: mỗi hàm ở đây là hàm cấp cao nhất và chỉ truyền giá trị đơn giản vào isolate. Nếu để lệnh
// `Isolate.run` nằm trong một phương thức của lớp có trạng thái (VaultController), closure có thể vô tình
// kéo theo cả `this` (gồm Timer, luồng...) và Dart sẽ báo "object is unsendable". Lỗi này đã bắt được bằng test đầu cuối.

Future<(VaultSession, RecoveryKey)> isoCreateCalibrated(String passphrase) => Isolate.run(() async {
      final params = await Argon2Calibration.calibrate();
      return VaultSession.create(passphrase: passphrase, params: params);
    });

Future<(VaultSession, RecoveryKey)> isoCreateWith(String passphrase, Argon2Params params) =>
    Isolate.run(() => VaultSession.create(passphrase: passphrase, params: params));

Future<VaultSession> isoOpenPassphrase(Uint8List bytes, String passphrase) =>
    Isolate.run(() => VaultSession.openWithPassphrase(bytes, passphrase));

Future<VaultSession> isoOpenRecovery(Uint8List bytes, RecoveryKey key) =>
    Isolate.run(() => VaultSession.openWithRecoveryKey(bytes, key));

/// Đặt passphrase mới cho phiên (trả về bản phiên đã cập nhật; phiên cũ nên đóng).
Future<VaultSession> isoRewrap(VaultSession session, String passphrase, Argon2Params params) => Isolate.run(() async {
      await session.changePassphrase(passphrase, params: params);
      return session;
    });

Future<String> isoAuthKey(String email, String password) => Isolate.run(() => CloudflareApi.deriveAuthKey(email, password));
