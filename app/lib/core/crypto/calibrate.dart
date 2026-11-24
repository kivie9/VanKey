import 'dart:typed_data';

import 'kdf.dart';

/// Chọn tham số Argon2id vừa sức máy: thử một lần nhẹ (2 vòng, 32 MiB), suy ra tốc độ, rồi chọn cấu hình
/// MẠNH NHẤT mà thời gian mở kho vẫn trong [targetMs]. Không bao giờ thấp hơn sàn 2 vòng, 32 MiB.
///
/// Thời gian Argon2id tỉ lệ gần tuyến tính với (số vòng × bộ nhớ MiB): đo trên Galaxy Note10+ cho ~6,8 ms mỗi đơn vị.
abstract final class Argon2Calibration {
  static const _mib = 1024 * 1024;

  /// Các cấu hình từ mạnh đến yếu. Bộ nhớ giữ ≤ 64 MiB để máy ít RAM không bị hết bộ nhớ.
  static const candidates = <Argon2Params>[
    Argon2Params(opslimit: 6, memlimitBytes: 64 * _mib),
    Argon2Params(opslimit: 5, memlimitBytes: 64 * _mib),
    Argon2Params(opslimit: 4, memlimitBytes: 64 * _mib),
    Argon2Params(opslimit: 3, memlimitBytes: 64 * _mib),
    Argon2Params(opslimit: 2, memlimitBytes: 64 * _mib),
    Argon2Params(opslimit: 2, memlimitBytes: 32 * _mib),
  ];

  /// Chọn từ tốc độ đo được: [msPerUnit] = mili giây cho mỗi (vòng × MiB). Thuần túy, dễ test.
  static Argon2Params choose(double msPerUnit, {int targetMs = 1500}) {
    for (final c in candidates) {
      final units = c.opslimit * (c.memlimitBytes / _mib);
      if (msPerUnit * units <= targetMs) return c;
    }
    return candidates.last;
  }

  /// Đo thật trên máy này (mất khoảng 0,4 giây trên điện thoại tầm trung). Gọi trong isolate riêng.
  static Future<Argon2Params> calibrate({int targetMs = 1500, Kdf kdf = const Kdf()}) async {
    const probe = Argon2Params(opslimit: 2, memlimitBytes: 32 * _mib);
    final sw = Stopwatch()..start();
    await kdf.argon2id(passphraseBytes: Uint8List(8), salt: Uint8List(Kdf.saltLength), params: probe);
    sw.stop();
    final ms = sw.elapsedMilliseconds < 1 ? 1 : sw.elapsedMilliseconds;
    return choose(ms / (probe.opslimit * (probe.memlimitBytes / _mib)), targetMs: targetMs);
  }
}
