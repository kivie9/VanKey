import 'dart:math';

enum StrengthLevel { weak, fair, strong, veryStrong }

/// Ước lượng độ mạnh mật khẩu bằng entropy **có phạt** các mẫu dễ đoán.
///
/// Đây là **ước lượng gần đúng** để hướng dẫn người dùng, không phải bảo đảm an toàn.
/// Phạt: ký tự lặp, dãy liên tiếp (`abc`, `1234`), dãy phím (`qwerty`), và mật khẩu thông dụng
/// (kể cả dạng thay chữ như `p@ssw0rd`).
final class PasswordStrength {
  const PasswordStrength(this.bits, this.level);

  final double bits;
  final StrengthLevel level;

  bool get isWeak => level == StrengthLevel.weak;

  static const _common = {
    'password', 'passw0rd', 'matkhau', 'matkhau123', '123456', '1234567', '12345678', '123456789', '1234567890',
    'qwerty', 'qwertyuiop', 'abc123', 'abcdef', 'letmein', 'welcome', 'monkey', 'dragon', 'iloveyou', 'admin',
    'administrator', 'login', 'master', 'sunshine', 'princess', 'football', 'baseball', 'superman', 'trustno1',
    'whatever', 'shadow', 'michael', 'jordan', 'hello', 'freedom', 'charlie', 'secret', 'summer', 'winter',
    'vietnam', 'hanoi', 'saigon', 'yeuem', 'anhyeuem', 'yeuanh', 'caothu', 'user', 'guest', 'root', 'test',
    'default', 'changeme', 'asdf', 'asdfgh', 'asdfghjkl', 'zxcvbn', 'zxcvbnm', '111111', '000000', '121212',
  };

  static const _rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm', '1234567890'];

  static PasswordStrength estimate(String password) {
    if (password.isEmpty) return const PasswordStrength(0, StrengthLevel.weak);
    final runes = password.runes.toList();

    var lower = false, upper = false, digit = false, symbol = false, other = false;
    for (final r in runes) {
      if (r >= 0x61 && r <= 0x7a) {
        lower = true;
      } else if (r >= 0x41 && r <= 0x5a) {
        upper = true;
      } else if (r >= 0x30 && r <= 0x39) {
        digit = true;
      } else if (r < 0x80) {
        symbol = true; // dấu câu, ký hiệu, khoảng trắng
      } else {
        other = true; // chữ có dấu, CJK, emoji...
      }
    }
    final pool = (lower ? 26 : 0) + (upper ? 26 : 0) + (digit ? 10 : 0) + (symbol ? 33 : 0) + (other ? 100 : 0);
    final perChar = log(pool) / ln2;

    // Ký tự lặp chỉ đóng góp một phần nhỏ.
    final unique = runes.toSet().length;
    final effectiveLength = unique + (runes.length - unique) * 0.25;
    var bits = effectiveLength * perChar;

    // Dãy tăng/giảm liên tiếp (abc, 321...): các ký tự sau hai ký tự đầu gần như đoán được.
    var predictable = 0;
    for (var i = 2; i < runes.length; i++) {
      final d1 = runes[i] - runes[i - 1];
      final d2 = runes[i - 1] - runes[i - 2];
      if (d1 == d2 && (d1 == 1 || d1 == -1)) predictable++;
    }
    bits -= predictable * perChar;

    // Dãy phím (qwerty, asdf...): ít nhất 4 ký tự liên tiếp theo hàng phím, xuôi hoặc ngược.
    final lowerPw = password.toLowerCase();
    final covered = List<bool>.filled(lowerPw.length, false);
    for (final row in _rows) {
      for (final seq in [row, row.split('').reversed.join()]) {
        for (var start = 0; start + 4 <= seq.length; start++) {
          final window = seq.substring(start, start + 4);
          var from = lowerPw.indexOf(window);
          while (from >= 0) {
            for (var k = from; k < from + 4; k++) {
              covered[k] = true;
            }
            from = lowerPw.indexOf(window, from + 1);
          }
        }
      }
    }
    final coveredCount = covered.where((c) => c).length;
    if (coveredCount > 0) bits -= (coveredCount - 1) * perChar * 0.9;

    if (_isCommon(lowerPw)) bits = min(bits, 15);
    bits = max(0, bits);

    final level = bits < 40
        ? StrengthLevel.weak
        : bits < 60
            ? StrengthLevel.fair
            : bits < 80
                ? StrengthLevel.strong
                : StrengthLevel.veryStrong;
    return PasswordStrength(bits, level);
  }

  /// Mật khẩu thông dụng, kể cả khi thay chữ bằng ký hiệu (`@`→a, `0`→o...) và thêm số/ký hiệu ở cuối.
  static bool _isCommon(String lowerPw) {
    if (_common.contains(lowerPw)) return true;
    const leet = {'@': 'a', '0': 'o', '1': 'l', '3': 'e', r'$': 's', '5': 's', '7': 't', '!': 'i'};
    final buf = StringBuffer();
    for (final ch in lowerPw.split('')) {
      buf.write(leet[ch] ?? ch);
    }
    final unleeted = buf.toString();
    final stripped = lowerPw.replaceFirst(RegExp(r'[^a-z]+$'), '');
    final strippedLeet = unleeted.replaceFirst(RegExp(r'[^a-z]+$'), '');
    return _common.contains(unleeted) || _common.contains(stripped) || _common.contains(strippedLeet);
  }
}
