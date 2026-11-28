import 'package:material_ui/material_ui.dart';

import '../../core/security/reminders.dart';
import '../notification_service.dart';
import '../vault_controller.dart';
import '../widgets/common.dart';
import '../widgets/form_layout.dart';
import 'item_detail_screen.dart';
import 'item_editor_screen.dart';
import '../i18n.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key, required this.controller});
  final VaultController controller;

  static String _kind(AlertKind k) => switch (k) {
        AlertKind.passwordExpiry => tr('Đổi mật khẩu'),
        AlertKind.cardExpiry => tr('Thẻ hết hạn'),
        AlertKind.keyExpiry => tr('Khóa hết hạn'),
      };

  static String _when(int days) => days < 0 ? tr('quá hạn {p0} ngày', {'p0': -days}) : (days == 0 ? tr('hôm nay') : tr('còn {p0} ngày', {'p0': days}));

  // Compact, light buttons: one tonal primary action, the rest as muted text links.
  static const _compact = ButtonStyle(
    visualDensity: VisualDensity.compact,
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
  );

  static ButtonStyle get _quiet => TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        foregroundColor: const Color(0xFF6B7280),
      );

  Future<void> _enableNotifications(BuildContext context) async {
    final ok = await NotificationService.instance.requestPermission();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? tr('Đã bật thông báo nhắc nhở') : tr('Chưa được cấp quyền thông báo. Bật trong cài đặt điện thoại.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final alerts = pendingAlerts(controller.data.items, DateTime.now(), snoozedUntil: controller.snoozed);
          return Scaffold(
            appBar: AppBar(title: Text(tr('Nhắc nhở'))),
            body: ListView(padding: formPadding(MediaQuery.sizeOf(context).width, EdgeInsets.zero), children: [
              if (NotificationService.instance.supported)
                FutureBuilder<bool>(
                  future: NotificationService.instance.enabled(),
                  builder: (context, snap) => snap.data == false
                      ? ListTile(
                          leading: const Icon(Icons.notifications_off_outlined),
                          title: Text(tr('Thông báo đang tắt')),
                          subtitle: Text(tr('Bật để nhận nhắc nhở khi app đóng')),
                          trailing: FilledButton(onPressed: () => _enableNotifications(context), child: Text(tr('Bật'))),
                        )
                      : const SizedBox.shrink(),
                ),
              if (alerts.isEmpty)
                Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text(tr('Chưa có nhắc nhở nào.\nĐặt hạn đổi mật khẩu khi thêm hoặc sửa mục.'), textAlign: TextAlign.center)),
                ),
              for (final a in alerts)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Avatar.forItem(a.item, size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${_kind(a.kind)} · ${_when(a.status.daysLeft)}', style: TextStyle(color: a.status.daysLeft < 0 ? Colors.red : Colors.orange)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Wrap(spacing: 4, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (a.kind == AlertKind.passwordExpiry)
                          FilledButton.tonal(
                            style: _compact,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ItemEditorScreen(controller: controller, existing: a.item)),
                            ),
                            child: Text(tr('Đổi mật khẩu')),
                          ),
                        TextButton(
                          style: _quiet,
                          onPressed: () => controller.snooze(a.snoozeKey, 7),
                          child: Text(tr('Nhắc lại sau 7 ngày')),
                        ),
                        TextButton(
                          style: _quiet,
                          onPressed: () => controller.snooze(a.snoozeKey, 365),
                          child: Text(tr('Bỏ qua')),
                        ),
                        TextButton(
                          style: _quiet,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => ItemDetailScreen(controller: controller, itemId: a.item.id)),
                          ),
                          child: Text(tr('Mở')),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ]),
          );
        },
      );
}
