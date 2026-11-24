import 'package:material_ui/material_ui.dart';

import '../../core/security/duplicates.dart';
import '../../core/security/reminders.dart';
import '../i18n.dart';
import '../widgets/common.dart';
import '../theme.dart';
import '../vault_controller.dart';
import 'duplicates_screen.dart';
import 'generator_screen.dart';
import 'health_screen.dart';
import 'import_screen.dart';
import 'qr_scan_screen.dart';
import 'quick_view_screen.dart';
import 'reminders_screen.dart';
import 'settings_tab.dart';
import 'sync_screen.dart';
import 'trash_screen.dart';

/// Tab "Tiện ích": lưới ô vuông, mỗi ô là một chức năng mở rộng. Ô có huy hiệu số khi có việc cần chú ý.
class ToolsTab extends StatelessWidget {
  const ToolsTab({super.key, required this.controller});
  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    final alerts = pendingAlerts(c.data.items, DateTime.now(), snoozedUntil: c.snoozed).length;
    final dups = findDuplicates(c.data.items.where((i) => !i.inTrash)).length;
    final trashed = c.data.items.where((i) => i.inTrash).length;
    final tools = <(IconData, String, int, VoidCallback)>[
      (Icons.bolt, tr('Xem nhanh 2FA'), 0, () => pushPage(context, QuickViewScreen(controller: c))),
      (Icons.password, tr('Tạo mật khẩu'), 0, () => pushPage(context, const GeneratorScreen())),
      (Icons.health_and_safety_outlined, tr('Kiểm tra bảo mật'), 0, () => pushPage(context, HealthScreen(controller: c))),
      (Icons.notifications_none, tr('Nhắc nhở'), alerts, () => pushPage(context, RemindersScreen(controller: c))),
      (Icons.content_copy, tr('Mục trùng lặp'), dups, () => pushPage(context, DuplicatesScreen(controller: c))),
      (Icons.delete_outline, tr('Thùng rác'), trashed, () => pushPage(context, TrashScreen(controller: c))),
      (Icons.qr_code_scanner, tr('Quét QR'), 0, () => pushPage(context, QrScanScreen(controller: c))),
      (Icons.file_download_outlined, tr('Nhập dữ liệu'), 0, () => pushPage(context, ImportScreen(controller: c))),
      (Icons.sync, tr('Đồng bộ'), 0, () => pushPage(context, SyncScreen(controller: c))),
      (Icons.science_outlined, tr('Nạp dữ liệu mẫu'), 0, () => loadDemoData(context, c)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.lg, Gap.sm),
        child: Row(children: [
          SettingsButton(controller: c),
          Expanded(child: Text(tr('Tiện ích'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        ]),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, mainAxisSpacing: Gap.md, crossAxisSpacing: Gap.md, childAspectRatio: 1),
          itemCount: tools.length,
          itemBuilder: (context, i) {
            final t = tools[i];
            return Card(
              child: InkWell(
                onTap: t.$4,
                child: Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Badge(
                      isLabelVisible: t.$3 > 0,
                      label: Text('${t.$3}'),
                      child: Icon(t.$1, size: 32, color: colors.accent),
                    ),
                    const SizedBox(height: Gap.md),
                    Text(t.$2, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
