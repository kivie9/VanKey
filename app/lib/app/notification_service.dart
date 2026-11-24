import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/security/reminders.dart';
import '../core/vault/models.dart';
import './i18n.dart';

/// Đặt lịch thông báo nhắc hạn bằng hệ thống (hoạt động cả khi app đóng, và được đặt lại sau khi khởi động máy).
/// Nội dung chỉ gồm tên dịch vụ và hạn, không có bí mật.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get supported => Platform.isAndroid;

  Future<void> init() async {
    if (_ready || !supported) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  /// Xin quyền thông báo (Android 13+). Trả về `true` nếu được cấp.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<bool> enabled() async {
    if (!supported) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  static String describe(ScheduledNotice n, Item item) {
    final what = switch (n.kind) {
      AlertKind.passwordExpiry => tr('mật khẩu'),
      AlertKind.cardExpiry => tr('thẻ'),
      AlertKind.keyExpiry => tr('khóa'),
    };
    return n.isDueDate ? tr('Đã đến hạn đổi {p0}: {p1}', {'p0': what, 'p1': item.title}) : tr('Sắp đến hạn {p0}: {p1}', {'p0': what, 'p1': item.title});
  }

  /// Hủy toàn bộ rồi đặt lại theo dữ liệu hiện tại.
  Future<int> reschedule(Iterable<Item> items) async {
    if (!supported) return 0;
    await init();
    await _plugin.cancelAll();
    final byId = {for (final i in items) i.id: i};
    final now = DateTime.now();
    final notices = upcomingNotices(items, now).where((n) => n.fireAt.isAfter(now)).take(60).toList();
    var id = 1;
    for (final n in notices) {
      final item = byId[n.itemId];
      if (item == null) continue;
      await _plugin.zonedSchedule(
        id: id++,
        title: 'VanKey',
        body: describe(n, item),
        scheduledDate: tz.TZDateTime.from(n.fireAt, tz.UTC),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            tr('Nhắc nhở'),
            channelDescription: tr('Nhắc đổi mật khẩu và hạn thẻ, khóa'),
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    return id - 1;
  }

  Future<void> cancelAll() async {
    if (!supported) return;
    await init();
    await _plugin.cancelAll();
  }
}
