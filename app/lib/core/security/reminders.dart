import '../vault/models.dart';

enum ReminderState { ok, soon, overdue }

enum AlertKind { passwordExpiry, cardExpiry, keyExpiry }

/// Cộng [months] tháng theo lịch (31/1 + 1 tháng = 28/2 hoặc 29/2), giữ nguyên giờ.
DateTime addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  final year = d.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = d.day > lastDay ? lastDay : d.day;
  return d.isUtc
      ? DateTime.utc(year, month, day, d.hour, d.minute, d.second, d.millisecond)
      : DateTime(year, month, day, d.hour, d.minute, d.second, d.millisecond);
}

final class ReminderStatus {
  const ReminderStatus({required this.due, required this.daysLeft, required this.noticeDays});

  final DateTime due;

  /// Âm nghĩa là đã quá hạn.
  final int daysLeft;
  final int noticeDays;

  ReminderState get state => daysLeft < 0
      ? ReminderState.overdue
      : daysLeft <= noticeDays
          ? ReminderState.soon
          : ReminderState.ok;
}

int _daysLeft(DateTime due, DateTime now) => (due.difference(now).inMilliseconds / Duration.millisecondsPerDay).ceil();

/// Trạng thái nhắc đổi mật khẩu, hoặc `null` nếu mục không đặt nhắc.
ReminderStatus? passwordReminder(Item item, DateTime now) {
  final r = item.reminder;
  if (r == null || r.months <= 0) return null;
  final due = addMonths(r.lastChangedAt.toUtc(), r.months);
  return ReminderStatus(due: due, daysLeft: _daysLeft(due, now.toUtc()), noticeDays: r.noticeDays);
}

/// Hạn của **thẻ** (trường `expiry` dạng `MM/YY` hoặc `MM/YYYY`, hết hạn vào cuối tháng đó)
/// hoặc **API key** (`expiry` dạng `dd/mm/yyyy` hoặc `yyyy-mm-dd`). `null` nếu không có hoặc không đọc được.
DateTime? expiryDate(Item item) {
  final raw = (item.valueOf('expiry') ?? '').trim();
  if (raw.isEmpty) return null;
  if (item.type == ItemType.card) {
    final m = RegExp(r'^(\d{1,2})\s*/\s*(\d{2}|\d{4})$').firstMatch(raw);
    if (m == null) return null;
    final month = int.parse(m.group(1)!);
    var year = int.parse(m.group(2)!);
    if (year < 100) year += 2000;
    if (month < 1 || month > 12) return null;
    return DateTime.utc(year, month + 1, 0, 23, 59, 59);
  }
  if (item.type == ItemType.key) {
    final dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(raw);
    final ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(raw);
    int y, mo, d;
    if (dmy != null) {
      d = int.parse(dmy.group(1)!);
      mo = int.parse(dmy.group(2)!);
      y = int.parse(dmy.group(3)!);
    } else if (ymd != null) {
      y = int.parse(ymd.group(1)!);
      mo = int.parse(ymd.group(2)!);
      d = int.parse(ymd.group(3)!);
    } else {
      return null;
    }
    if (mo < 1 || mo > 12 || d < 1 || d > DateTime.utc(y, mo + 1, 0).day) return null;
    return DateTime.utc(y, mo, d, 23, 59, 59);
  }
  return null;
}

ReminderStatus? expiryReminder(Item item, DateTime now, {int noticeDays = 30}) {
  final due = expiryDate(item);
  if (due == null) return null;
  return ReminderStatus(due: due, daysLeft: _daysLeft(due, now.toUtc()), noticeDays: noticeDays);
}

/// Một nhắc nhở đang cần hiển thị.
final class Alert {
  const Alert({required this.item, required this.kind, required this.status});

  final Item item;
  final AlertKind kind;
  final ReminderStatus status;

  /// Khóa để hẹn lại hoặc bỏ qua riêng từng nhắc nhở.
  String get snoozeKey => '${item.id}:${kind.name}';
}

/// Các nhắc nhở sắp đến hạn hoặc quá hạn, sắp theo số ngày còn lại tăng dần.
/// [snoozedUntil]: khóa nhắc nhở → thời điểm hết hẹn; còn trong thời gian hẹn thì bỏ qua.
List<Alert> pendingAlerts(
  Iterable<Item> items,
  DateTime now, {
  Map<String, DateTime> snoozedUntil = const {},
  int expiryNoticeDays = 30,
}) {
  final out = <Alert>[];
  void add(Item i, AlertKind kind, ReminderStatus? s) {
    if (s == null || s.state == ReminderState.ok) return;
    final a = Alert(item: i, kind: kind, status: s);
    final until = snoozedUntil[a.snoozeKey];
    if (until != null && until.isAfter(now)) return;
    out.add(a);
  }

  for (final i in items) {
    if (i.inTrash) continue;
    add(i, AlertKind.passwordExpiry, passwordReminder(i, now));
    final kind = switch (i.type) {
      ItemType.card => AlertKind.cardExpiry,
      ItemType.key => AlertKind.keyExpiry,
      _ => null,
    };
    if (kind != null) add(i, kind, expiryReminder(i, now, noticeDays: expiryNoticeDays));
  }
  out.sort((a, b) => a.status.daysLeft.compareTo(b.status.daysLeft));
  return out;
}

/// Một lần hẹn thông báo cho bộ lập lịch của hệ điều hành.
final class ScheduledNotice {
  const ScheduledNotice({required this.itemId, required this.kind, required this.fireAt, required this.isDueDate});

  final String itemId;
  final AlertKind kind;
  final DateTime fireAt;

  /// `true`: thông báo đúng ngày hết hạn; `false`: thông báo báo trước.
  final bool isDueDate;
}

/// Các thông báo cần hẹn trong tương lai (đến [horizonDays] ngày tới): báo trước và đúng ngày hết hạn.
/// Mục đã quá hạn không có thông báo hẹn (đã hiển thị ngay trong [pendingAlerts]).
List<ScheduledNotice> upcomingNotices(Iterable<Item> items, DateTime now, {int horizonDays = 400, int expiryNoticeDays = 30}) {
  final out = <ScheduledNotice>[];
  final limit = now.toUtc().add(Duration(days: horizonDays));
  void add(Item i, AlertKind kind, ReminderStatus? s) {
    if (s == null) return;
    final notice = s.due.subtract(Duration(days: s.noticeDays));
    if (notice.isAfter(now.toUtc()) && notice.isBefore(limit)) {
      out.add(ScheduledNotice(itemId: i.id, kind: kind, fireAt: notice, isDueDate: false));
    }
    if (s.due.isAfter(now.toUtc()) && s.due.isBefore(limit)) {
      out.add(ScheduledNotice(itemId: i.id, kind: kind, fireAt: s.due, isDueDate: true));
    }
  }

  for (final i in items) {
    if (i.inTrash) continue;
    add(i, AlertKind.passwordExpiry, passwordReminder(i, now));
    final kind = switch (i.type) {
      ItemType.card => AlertKind.cardExpiry,
      ItemType.key => AlertKind.keyExpiry,
      _ => null,
    };
    if (kind != null) add(i, kind, expiryReminder(i, now, noticeDays: expiryNoticeDays));
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out;
}
