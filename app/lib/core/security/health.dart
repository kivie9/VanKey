import '../vault/models.dart';
import 'duplicates.dart';
import 'password_strength.dart';

enum HealthLevel { good, needsWork, atRisk }

/// Báo cáo "Kiểm tra bảo mật" của kho.
final class HealthReport {
  const HealthReport({
    required this.weak,
    required this.reused,
    required this.noTotp,
    required this.leaked,
    required this.score,
  });

  /// Mục đăng nhập có mật khẩu yếu.
  final List<Item> weak;

  /// Các nhóm mục dùng chung mật khẩu.
  final List<DuplicateGroup> reused;

  /// Mục đăng nhập chưa bật 2FA.
  final List<Item> noTotp;

  /// Mục có mật khẩu xuất hiện trong dữ liệu rò rỉ (do tầng ngoài tra qua HaveIBeenPwned rồi truyền vào).
  final List<Item> leaked;

  /// 0 đến 100.
  final int score;

  int get reusedItemCount => reused.fold(0, (n, g) => n + g.items.length);
  int get issueCount => weak.length + reusedItemCount + noTotp.length + leaked.length;

  HealthLevel get level => score >= 80
      ? HealthLevel.good
      : score >= 50
          ? HealthLevel.needsWork
          : HealthLevel.atRisk;
}

/// Tính báo cáo. Điểm là **công thức tự đặt** (trừ điểm theo số vấn đề, có trần cho từng loại), chưa phải chuẩn nào.
HealthReport healthReport(Iterable<Item> all, {Set<String> leakedIds = const {}}) {
  final items = all.where((i) => !i.inTrash).toList();
  final logins = items.where((i) => i.type == ItemType.login).toList();
  final weak = [
    for (final i in logins)
      if (i.password.isNotEmpty && PasswordStrength.estimate(i.password).isWeak) i,
  ];
  final reused = findDuplicates(items).where((g) => g.kind == DuplicateKind.sharedPassword).toList();
  final noTotp = [for (final i in logins) if (i.totp == null) i];
  final leaked = [for (final i in items) if (leakedIds.contains(i.id)) i];

  final reusedCount = reused.fold<int>(0, (n, g) => n + g.items.length);
  int cap(int v, int max) => v > max ? max : v;
  final score = (100 -
          cap(weak.length * 10, 40) -
          cap(reusedCount * 5, 30) -
          cap(noTotp.length * 3, 20) -
          cap(leaked.length * 15, 40))
      .clamp(0, 100);
  return HealthReport(weak: weak, reused: reused, noTotp: noTotp, leaked: leaked, score: score);
}
