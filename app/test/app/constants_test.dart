import 'package:flutter_test/flutter_test.dart';
import 'package:vankey/app/constants.dart';

void main() {
  test('chờ sau khi nhập sai: 3 lần đầu miễn phí, rồi 5s nhân đôi, tối đa 300s', () {
    expect([for (var n = 0; n <= 4; n++) LockPolicy.waitSecondsAfter(n)], [0, 0, 0, 5, 10]);
    expect(LockPolicy.waitSecondsAfter(9), 300);
    expect(LockPolicy.waitSecondsAfter(500), 300);
  });

  test('chỉ cho http với host phát triển', () {
    expect(ServerPolicy.devHosts, {'localhost', '127.0.0.1', '10.0.2.2'});
  });

  test('mọi mức tự khóa nằm trong giới hạn hợp lệ', () {
    for (final s in LockPolicy.autoLockChoices) {
      expect(s, inInclusiveRange(LockPolicy.never, LockPolicy.maxAutoLockSeconds));
    }
  });

  test('mật khẩu mới: đủ dài và đủ khó; mật khẩu thông dụng hay dãy phím bị từ chối dù đủ dài', () {
    expect(AccountPolicy.checkNewPassword('Ab1!xyz'), PasswordIssue.tooShort);
    expect(AccountPolicy.checkNewPassword('password123'), PasswordIssue.tooWeak);
    expect(AccountPolicy.checkNewPassword('qwertyuiop'), PasswordIssue.tooWeak);
    expect(AccountPolicy.checkNewPassword('1234567890'), PasswordIssue.tooWeak);
    expect(AccountPolicy.checkNewPassword('aaaaaaaaaaaa'), PasswordIssue.tooWeak);
    expect(AccountPolicy.checkNewPassword('ngựa vằn ăn phở lúc 3 giờ'), isNull);
    expect(AccountPolicy.checkNewPassword('mat-khau-dung-123'), isNull);
    expect(AccountPolicy.newPasswordError('mat-khau-dung-123'), isNull);
    expect(AccountPolicy.newPasswordError('ngan'), isNotNull);
  });
}
