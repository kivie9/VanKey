/// Mọi hằng số của lớp giao diện/ứng dụng ở một chỗ (không rải số "ma thuật" trong code).
/// Tham số mật mã nằm riêng trong `core/crypto`. Không có khóa hay bí mật nào được ghi cứng.
library;

import '../core/security/password_strength.dart';
import 'i18n.dart';

/// Thời gian tự động (ẩn/xóa dữ liệu nhạy cảm, chờ, đệm).
abstract final class Timing {
  /// Chép vào clipboard xong thì tự xóa sau chừng này (chỉ khi clipboard còn đúng nội dung đó).
  static const clipboardClear = Duration(seconds: 30);

  /// Thông báo "Đã chép".
  static const copiedSnack = Duration(seconds: 2);

  /// Mọi thứ đã hiện ra ở màn chi tiết tự ẩn lại sau chừng này.
  static const autoHideSecrets = Duration(seconds: 30);

  /// Gộp nhiều thay đổi liên tiếp rồi mới ghi file kho.
  static const saveDebounce = Duration(milliseconds: 500);

  /// Gộp thay đổi rồi mới đồng bộ.
  static const syncDebounce = Duration(seconds: 3);

  /// Gộp thay đổi rồi mới đặt lại thông báo nhắc nhở.
  static const notifyDebounce = Duration(seconds: 2);

  /// Nhịp cập nhật mã 2FA.
  static const clockTick = Duration(seconds: 1);

  /// Hỏi sinh trắc học quá lâu thì coi như không có.
  static const biometricProbe = Duration(milliseconds: 400);

  /// Hoạt ảnh.
  static const fast = Duration(milliseconds: 180);
  static const pageIn = Duration(milliseconds: 280);
  static const pageOut = Duration(milliseconds: 240);

  /// Hỏi dịch vụ kiểm tra mật khẩu bị lộ.
  static const hibpConnect = Duration(seconds: 10);
  static const hibpResponse = Duration(seconds: 15);
}

/// Khóa kho và chống đoán mật khẩu.
abstract final class LockPolicy {
  /// Giá trị hợp lệ lớn nhất của "tự khóa sau" (giây) khi đọc từ settings.json.
  static const maxAutoLockSeconds = 3600;

  /// Các mức người dùng được chọn (giây). 0 = khóa ngay khi thoát app.
  static const autoLockChoices = [never, 0, 30, 60, 300, 900];

  /// Không tự khóa khi chuyển app (vẫn phải mở khóa sau khi tắt hẳn app).
  static const never = -1;

  /// Từ lần sai thứ mấy thì bắt đầu bắt chờ.
  static const freeAttempts = 3;

  /// Thời gian chờ ban đầu, nhân đôi sau mỗi lần sai, tối đa [maxWaitSeconds].
  static const baseWaitSeconds = 5;
  static const maxWaitSeconds = 300;

  /// Số lần nhân đôi tối đa (để không tràn số).
  static const maxDoublings = 6;

  /// Thời gian chờ (giây) sau [failures] lần sai liên tiếp; 0 nếu chưa phải chờ.
  static int waitSecondsAfter(int failures) {
    if (failures < freeAttempts) return 0;
    final doublings = (failures - freeAttempts).clamp(0, maxDoublings);
    return (baseWaitSeconds * (1 << doublings)).clamp(baseWaitSeconds, maxWaitSeconds);
  }
}

/// Vì sao mật khẩu mới bị từ chối.
enum PasswordIssue { tooShort, tooWeak }

/// Quy tắc cho mật khẩu và tên đăng nhập khi tạo mới (khớp quy tắc phía máy chủ trong server/src/handler.ts).
abstract final class AccountPolicy {
  /// Một mật khẩu bảo vệ cả tài khoản lẫn kho, và ai có file kho cũng đoán ngoại tuyến được: phải đủ dài **và** đủ khó.
  /// Chỉ áp dụng khi đặt hoặc đổi mật khẩu; kho cũ có mật khẩu yếu hơn vẫn mở được.
  static const minPasswordLength = 10;

  /// Độ mạnh tối thiểu (bit ước lượng, xem [PasswordStrength]): 40 bit = mức "khá". Với Argon2id ~1 giây mỗi lần
  /// thử trên điện thoại, đoán hết 2^40 khả năng tốn hàng chục năm GPU.
  static const minPasswordBits = 40.0;

  /// Lý do mật khẩu mới chưa đạt, hoặc `null` nếu đạt.
  static PasswordIssue? checkNewPassword(String password) {
    if (password.runes.length < minPasswordLength) return PasswordIssue.tooShort;
    if (PasswordStrength.estimate(password).bits < minPasswordBits) return PasswordIssue.tooWeak;
    return null;
  }

  /// Lời báo (đã dịch) nếu [password] chưa đạt để làm mật khẩu mới, hoặc `null` nếu đạt.
  static String? newPasswordError(String password) => switch (checkNewPassword(password)) {
        PasswordIssue.tooShort => tr('Mật khẩu cần ít nhất {p0} ký tự', {'p0': minPasswordLength}),
        PasswordIssue.tooWeak => tr('Mật khẩu quá dễ đoán. Hãy dài hơn, hoặc ghép vài từ không liên quan.'),
        null => null,
      };
  static final _username = RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$');

  /// Chuẩn hóa tên đăng nhập (bỏ khoảng trắng đầu cuối, chữ thường); null nếu không hợp lệ.
  static String? normalizeUsername(String raw) {
    final u = raw.trim().toLowerCase();
    return _username.hasMatch(u) ? u : null;
  }
}

/// Máy chủ đồng bộ: chỉ cho http với các host phát triển (máy này, máy ảo Android).
/// Bản MVP: màn đầu chỉ có đăng nhập / đăng ký trên máy chủ VanKey ([ServerPolicy.defaultUrl]).
/// Tự dựng máy chủ, Google Drive và mã mời bị ẩn. Đặt `false` để hiện lại màn chọn đầy đủ.
abstract final class Mvp {
  static const serverOnly = true;
}

abstract final class ServerPolicy {
  static const secureScheme = 'https';
  static const devScheme = 'http';
  static const devHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

  /// Máy chủ mặc định điền sẵn ở màn đăng nhập (người dùng vẫn sửa được).
  static const defaultUrl = 'https://vankey.devcloudly.workers.dev';
}

/// Tên file và khóa JSON lưu cục bộ.
abstract final class Storage {
  static const settingsFile = 'settings.json';
  static const backupFileName = 'vankey-backup.vkv';
  static const backupMime = 'application/octet-stream';
}

/// Khóa trong settings.json.
abstract final class SettingsKey {
  static const lockAfter = 'lockAfter';
  static const theme = 'theme';
  static const language = 'language';
  static const accent = 'accent';
  static const groupBy = 'groupBy';
  static const sortBy = 'sortBy';
  static const blockScreenshots = 'blockScreenshots';
  static const showLogos = 'showLogos';
  static const lastType = 'lastType';
  static const snooze = 'snooze';
  static const dismissedServices = 'dismissedServices';
  static const sync = 'sync';
}

/// Giá trị ngôn ngữ.
abstract final class LangCode {
  static const vi = 'vi';
  static const en = 'en';
  static const system = 'system';
}

/// Hiển thị giá trị bí mật khi đang ẩn.
abstract final class Mask {
  static const dots = '••••••••••';
  static const dotsLong = '••••••••••••';
  static const letterSpacing = 2.0;

  /// Mục lịch sử mật khẩu dùng chung bộ nhớ "đã hiện" với trường thường: cộng thêm số này để không đụng chỉ số.
  static const historyRevealBase = 1000;
}

/// Kích thước dùng lại.
abstract final class Sizes {
  static const qrCode = 300.0;
  static const healthGauge = 120.0;
}
