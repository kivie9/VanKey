import 'dart:io';

import 'cloudflare_screens.dart';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/vault/merge.dart';
import '../google_drive_auth.dart';
import '../../core/vault/models.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/ui.dart';
import '../i18n.dart';
import '../widgets/common.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key, required this.controller});
  final VaultController controller;

  static bool get _folderSupported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static String ago(DateTime? t) {
    if (t == null) return tr('chưa lần nào');
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return tr('vừa xong');
    if (d.inMinutes < 60) return tr('{p0} phút trước', {'p0': d.inMinutes});
    if (d.inHours < 24) return tr('{p0} giờ trước', {'p0': d.inHours});
    return tr('{p0} ngày trước', {'p0': d.inDays});
  }

  Future<void> _pickFolder(BuildContext context) async {
    final uri = await controller.external(() => FilePicker.pickDirectory(dialogTitle: tr('Chọn thư mục đồng bộ')));
    if (uri != null) await controller.setFolderSync(uri.toFilePath());
  }

  Future<void> _enableDrive(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final err = await controller.enableDriveSync();
    messenger.showSnackBar(SnackBar(content: Text(err ?? tr('Đã bật đồng bộ Google Drive'))));
  }

  /// Xóa tài khoản máy chủ: xác nhận, nhập mật khẩu, rồi xóa trên máy chủ và trên máy này.
  Future<void> _deleteAccount(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: tr('Xóa tài khoản?'),
      message: tr('Tài khoản {p0}, kho trên máy chủ và kho trên máy này sẽ bị xóa vĩnh viễn. Các thiết bị khác bị đăng xuất. Không thể hoàn tác. Hãy xuất bản sao lưu trước nếu còn cần dữ liệu.', {'p0': controller.cfSession?.username ?? ''}),
      confirmLabel: tr('Tiếp tục'),
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Nhập mật khẩu để xóa tài khoản')),
        content: TextField(controller: ctrl, obscureText: true, autofocus: true, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: tr('Mật khẩu'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.of(ctx).danger),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(tr('Xóa vĩnh viễn')),
          ),
        ],
      ),
    );
    if (pw == null || pw.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final err = await controller.deleteServerAccount(pw);
    if (err != null) {
      messenger.showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    nav.popUntil((r) => r.isFirst);
    messenger.showSnackBar(SnackBar(content: Text(tr('Đã xóa tài khoản'))));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final on = controller.provider != null;
          final syncing = controller.syncStatus == SyncStatus.syncing;
          return Scaffold(
            appBar: AppBar(title: Text(tr('Đồng bộ'))),
            body: ListView(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl), children: [
              if (!on) ...[
                Notice(tr('Đồng bộ giữa các thiết bị bằng bản đã mã hóa. Nơi lưu chỉ thấy dữ liệu không đọc được.'), icon: Icons.lock_outline_rounded),
                const SizedBox(height: Gap.lg),
                CardList(children: [
                  if (GoogleConfig.configured)
                    ListTile(
                      leading: const IconBadge(Icons.add_to_drive_outlined),
                      title: Text(tr('Đồng bộ qua Google Drive')),
                      subtitle: Text(tr('Dùng tài khoản Google của bạn, không cần máy chủ')),
                      trailing: controller.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.chevron_right_rounded),
                      minVerticalPadding: Gap.md,
                      enabled: !controller.busy,
                      onTap: controller.busy ? null : () => _enableDrive(context),
                    ),
                  ListTile(
                    leading: const IconBadge(Icons.cloud_outlined),
                    title: Text(tr('Đồng bộ qua máy chủ Cloudflare của bạn')),
                    subtitle: Text(tr('Điện thoại và máy tính dùng chung một kho')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    minVerticalPadding: Gap.md,
                    onTap: () => pushPage(context, CloudflareLoginScreen(controller: controller)),
                  ),
                  ListTile(
                    leading: const IconBadge(Icons.folder_outlined),
                    title: Text(tr('Đồng bộ qua thư mục (OneDrive, Dropbox...)')),
                    subtitle: Text(_folderSupported ? tr('Chọn một thư mục được đồng bộ sẵn') : tr('Đồng bộ qua thư mục chỉ dùng được trên máy tính.')),
                    trailing: _folderSupported ? const Icon(Icons.chevron_right_rounded) : null,
                    enabled: _folderSupported,
                    minVerticalPadding: Gap.md,
                    onTap: _folderSupported ? () => _pickFolder(context) : null,
                  ),
                ]),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.lg),
                    child: Row(children: [
                      IconBadge(
                        syncing ? Icons.sync : (controller.syncStatus == SyncStatus.error ? Icons.cloud_off_outlined : Icons.cloud_done_outlined),
                        size: 46,
                        color: controller.syncStatus == SyncStatus.error ? AppColors.of(context).warn : null,
                      ),
                      const SizedBox(width: Gap.lg),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            syncing ? tr('Đang đồng bộ…') : (controller.syncStatus == SyncStatus.error ? tr('Lỗi đồng bộ') : tr('Đã đồng bộ')),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(tr('{p0}\nLần cuối: {p1}', {'p0': controller.syncLabel, 'p1': ago(controller.lastSync)}), style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                      if (syncing) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    ]),
                  ),
                ),
                if (controller.syncError != null) Padding(padding: const EdgeInsets.only(top: Gap.md), child: Notice(controller.syncError!, tone: NoticeTone.error, icon: Icons.error_outline)),
                const SizedBox(height: Gap.md),
                FilledButton.icon(onPressed: syncing ? null : controller.syncNow, icon: const Icon(Icons.sync), label: Text(tr('Đồng bộ ngay'))),
                if (controller.conflicts.isNotEmpty || controller.cfSession != null) ...[
                  const SizedBox(height: Gap.lg),
                  CardList(children: [
                    if (controller.conflicts.isNotEmpty)
                      ListTile(
                        leading: IconBadge(Icons.merge_type, color: AppColors.of(context).warn),
                        title: Text(tr('{p0} mục sửa ở cả hai máy', {'p0': controller.conflicts.length})),
                        subtitle: Text(tr('Đã tự chọn bản mới hơn. Bấm để xem và đổi.')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => pushPage(context, ConflictsScreen(controller: controller)),
                      ),
                    if (controller.cfSession != null)
                      ListTile(
                        leading: const IconBadge(Icons.devices),
                        title: Text(tr('Thiết bị đã đăng nhập')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => pushPage(context, CloudflareDevicesScreen(controller: controller)),
                      ),
                  ]),
                ],
                const SizedBox(height: Gap.lg),
                TextButton(
                  onPressed: syncing
                      ? null
                      : () async {
                          final signOut = controller.cfSession != null;
                          final ok = await confirmDialog(
                            context,
                            title: signOut ? tr('Đăng xuất khỏi máy chủ?') : tr('Tắt đồng bộ?'),
                            message: tr('Dữ liệu trên máy này vẫn giữ nguyên. Máy này sẽ không còn đồng bộ với các máy khác.'),
                            confirmLabel: signOut ? tr('Đăng xuất') : tr('Tắt đồng bộ'),
                            danger: true,
                          );
                          if (ok) await (signOut ? controller.signOutCloudflare() : controller.disableSync());
                        },
                  style: TextButton.styleFrom(foregroundColor: AppColors.of(context).danger),
                  child: Text(controller.cfSession != null ? tr('Đăng xuất khỏi máy chủ (giữ nguyên dữ liệu trên máy)') : tr('Tắt đồng bộ (giữ nguyên dữ liệu trên máy)'), textAlign: TextAlign.center),
                ),
                if (controller.cfSession != null)
                  TextButton(
                    onPressed: syncing ? null : () => _deleteAccount(context),
                    style: TextButton.styleFrom(foregroundColor: AppColors.of(context).danger),
                    child: Text(tr('Xóa tài khoản')),
                  ),
              ],
            ]),
          );
        },
      );
}

/// Hai bản của cùng một mục: chọn bản giữ lại.
class ConflictsScreen extends StatelessWidget {
  const ConflictsScreen({super.key, required this.controller});
  final VaultController controller;

  Widget _side(BuildContext context, String label, Item i, bool isWinner, VoidCallback onKeep) => Expanded(
        child: Card(
          color: isWinner ? Theme.of(context).colorScheme.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(i.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (i.subtitle.isNotEmpty) Text(i.subtitle),
              Text('Sửa: ${i.updatedAt.toLocal().toString().split('.').first}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onKeep, child: Text(tr('Giữ bản này'))),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(tr('Mục xung đột'))),
          body: controller.conflicts.isEmpty
              ? EmptyState(icon: Icons.check_circle_outline_rounded, title: tr('Không còn xung đột'))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final c in controller.conflicts)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _side(context, tr('Máy này'), c.local, c.winner.id == c.local.id && c.winner.hlc == c.local.hlc, () => controller.resolveConflictChoice(c, ConflictChoice.keepLocal)),
                      _side(context, tr('Máy kia'), c.remote, c.winner.hlc == c.remote.hlc, () => controller.resolveConflictChoice(c, ConflictChoice.keepRemote)),
                    ]),
                ]),
        ),
      );
}
