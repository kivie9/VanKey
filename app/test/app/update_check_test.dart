import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/update_check.dart';

void main() {
  test('parseVersion: nhận v1.2.3 và 1.2.3, bỏ dạng khác', () {
    expect(parseVersion('v1.2.3'), [1, 2, 3]);
    expect(parseVersion('10.0.1'), [10, 0, 1]);
    expect(parseVersion('dev'), isNull);
    expect(parseVersion('v0'), isNull);
    expect(parseVersion('1.2.3-beta'), isNull);
  });

  test('isNewerVersion so từng phần theo số, không theo chữ', () {
    expect(isNewerVersion('1.0.10', '1.0.9'), isTrue);
    expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    // Bản build trên máy (dev) hoặc tag lạ: không báo có bản mới.
    expect(isNewerVersion('1.0.0', 'dev'), isFalse);
    expect(isNewerVersion('latest', '1.0.0'), isFalse);
  });
}
