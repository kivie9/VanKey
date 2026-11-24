import '../crypto/csprng.dart';
import '../errors.dart';

/// Tạo mật khẩu ngẫu nhiên bằng nguồn ngẫu nhiên an toàn mật mã, **không thiên lệch modulo**.
abstract final class PasswordGenerator {
  static const minLength = 4;
  static const maxLength = 128;

  // Bộ ký tự bỏ các ký tự dễ nhầm (I O l 0 1) khi [avoidAmbiguous].
  static const _upperClear = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const _lowerClear = 'abcdefghijkmnopqrstuvwxyz';
  static const _digitsClear = '23456789';
  static const _symbolsClear = r'!@#$%^&*-_=+?';

  static const _upperFull = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _lowerFull = 'abcdefghijklmnopqrstuvwxyz';
  static const _digitsFull = '0123456789';
  static const _symbolsFull = r'!@#$%^&*()-_=+[]{};:,.<>?/';

  /// Sinh mật khẩu dài [length], đảm bảo **có ít nhất một ký tự** của mỗi loại được bật.
  static String generate({
    int length = 20,
    bool useUpper = true,
    bool useLower = true,
    bool useDigits = true,
    bool useSymbols = true,
    bool avoidAmbiguous = true,
    RandomSource? random,
  }) {
    final rnd = random ?? Csprng();
    final classes = <String>[
      if (useUpper) avoidAmbiguous ? _upperClear : _upperFull,
      if (useLower) avoidAmbiguous ? _lowerClear : _lowerFull,
      if (useDigits) avoidAmbiguous ? _digitsClear : _digitsFull,
      if (useSymbols) avoidAmbiguous ? _symbolsClear : _symbolsFull,
    ];
    if (classes.isEmpty) throw const InvalidInputException('phải bật ít nhất một loại ký tự');
    if (length < classes.length || length < minLength) {
      throw InvalidInputException('độ dài tối thiểu là ${classes.length < minLength ? minLength : classes.length}');
    }
    if (length > maxLength) throw const InvalidInputException('độ dài tối đa là $maxLength');

    final all = classes.join();
    final chars = <String>[
      for (final c in classes) c[rnd.nextInt(c.length)],
      for (var i = classes.length; i < length; i++) all[rnd.nextInt(all.length)],
    ];
    // Xáo trộn Fisher-Yates để ký tự đảm bảo không luôn nằm ở đầu.
    for (var i = chars.length - 1; i > 0; i--) {
      final j = rnd.nextInt(i + 1);
      final t = chars[i];
      chars[i] = chars[j];
      chars[j] = t;
    }
    return chars.join();
  }
}
