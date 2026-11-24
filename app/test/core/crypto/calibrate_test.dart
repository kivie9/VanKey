import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/core/crypto/calibrate.dart';
import 'package:vankey/core/crypto/kdf.dart';

void main() {
  group('chọn tham số theo tốc độ', () {
    test('máy rất nhanh (0,5 ms/đơn vị): chọn cấu hình mạnh nhất', () {
      final p = Argon2Calibration.choose(0.5);
      expect(p.opslimit, 6);
      expect(p.memlimitBytes, 64 * 1024 * 1024);
    });

    test('Note10+ (6,8 ms/đơn vị, đích 1,5 giây): chọn đúng 3 vòng 64 MiB', () {
      final p = Argon2Calibration.choose(6.8);
      expect(p, Argon2Params.standard);
    });

    test('máy chậm gấp 3 (20 ms/đơn vị): hạ xuống nhưng không dưới sàn', () {
      final p = Argon2Calibration.choose(20);
      expect(p.opslimit, 2);
      expect(p.memlimitBytes, 32 * 1024 * 1024);
    });

    test('máy cực chậm: vẫn trả về sàn (2 vòng, 32 MiB), không bao giờ thấp hơn', () {
      final p = Argon2Calibration.choose(1000);
      expect(p, Argon2Calibration.candidates.last);
      p.validate();
    });

    test('mọi ứng viên đều hợp lệ và xếp từ mạnh đến yếu', () {
      var prev = double.infinity;
      for (final c in Argon2Calibration.candidates) {
        c.validate();
        final cost = c.opslimit * c.memlimitBytes / (1024 * 1024);
        expect(cost, lessThanOrEqualTo(prev));
        prev = cost;
      }
    });

    test('đích thời gian lớn hơn cho phép chọn mạnh hơn', () {
      final a = Argon2Calibration.choose(6.8, targetMs: 1000);
      final b = Argon2Calibration.choose(6.8, targetMs: 3000);
      expect(b.opslimit * b.memlimitBytes, greaterThanOrEqualTo(a.opslimit * a.memlimitBytes));
    });
  });

  test('đo thật trên máy chạy test: kết quả hợp lệ và dùng được để tạo khe khóa', () async {
    final p = await Argon2Calibration.calibrate();
    p.validate();
    expect(p.opslimit, inInclusiveRange(2, 6));
  });
}
