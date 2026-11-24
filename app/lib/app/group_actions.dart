import 'package:material_ui/material_ui.dart';

import 'i18n.dart';
import 'theme.dart';
import 'vault_controller.dart';
import 'widgets/ui.dart';

/// Hộp nhập tên nhóm (tạo mới hoặc đổi tên). Trả về tên đã cắt khoảng trắng, hoặc null nếu hủy.
Future<String?> askGroupName(BuildContext context, {String initial = '', required String title, required String confirmLabel}) =>
    showDialog<String>(context: context, builder: (_) => _NameDialog(initial: initial, title: title, confirmLabel: confirmLabel));

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial, required this.title, required this.confirmLabel});
  final String initial;
  final String title;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isNotEmpty) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Tên thẻ')),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
          FilledButton(onPressed: _ctrl.text.trim().isEmpty ? null : _submit, child: Text(widget.confirmLabel)),
        ],
      );
}

/// Chọn nhóm: một bảng duy nhất, chạm là chọn. Trả về tên nhóm, '' = không nhóm, null = đóng bảng.
Future<String?> pickGroup(BuildContext context, VaultController c, {required String current}) {
  final colors = AppColors.of(context);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final groups = c.groups;
      // Nhóm vừa gõ ở form nhưng chưa có mục nào dùng vẫn phải hiện để còn thấy là đang chọn.
      final all = {...groups, if (current.isNotEmpty) current}.toList()..sort();
      Widget row(IconData icon, String label, bool selected, VoidCallback onTap, {String? trailing}) => ListTile(
            leading: Icon(icon, color: selected ? colors.accent : colors.muted),
            title: Text(label, style: TextStyle(color: selected ? colors.accent : colors.fg, fontWeight: selected ? FontWeight.w600 : null)),
            trailing: selected ? Icon(Icons.check_rounded, color: colors.accent) : (trailing == null ? null : Text(trailing, style: TextStyle(color: colors.muted))),
            onTap: onTap,
          );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.sm, Gap.sm),
              child: Row(children: [
                Expanded(child: Text(tr('Chọn thẻ'), style: Theme.of(ctx).textTheme.titleLarge)),
                TextButton.icon(
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(tr('Quản lý')),
                  onPressed: () async {
                    await manageGroups(ctx, c);
                    if (ctx.mounted) Navigator.pop(ctx, current.isNotEmpty && !c.groups.contains(current) ? '' : null);
                  },
                ),
              ]),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                row(Icons.folder_off_outlined, tr('Không có thẻ'), current.isEmpty, () => Navigator.pop(ctx, '')),
                for (final g in all) row(Icons.folder_outlined, g, g == current, () => Navigator.pop(ctx, g), trailing: '${c.countInGroup(g)}'),
                row(Icons.create_new_folder_outlined, tr('Thẻ mới…'), false, () async {
                  final name = await askGroupName(ctx, title: tr('Thẻ mới'), confirmLabel: tr('Tạo'));
                  if (name != null && ctx.mounted) Navigator.pop(ctx, name);
                }),
              ]),
            ),
          ]),
        ),
      );
    },
  );
}

/// Quản lý nhóm: đổi tên và xóa. Xóa nhóm KHÔNG xóa mục, chỉ bỏ các mục ra khỏi nhóm.
Future<void> manageGroups(BuildContext context, VaultController c) {
  final colors = AppColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final groups = c.groups;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.sm),
                child: Text(tr('Quản lý thẻ'), style: Theme.of(ctx).textTheme.titleLarge),
              ),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Gap.xl),
                  child: Text(tr('Chưa có thẻ nào. Thẻ được tạo khi bạn gắn cho một mục.'), style: TextStyle(color: colors.muted)),
                )
              else
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final g in groups)
                      ListTile(
                        leading: Icon(Icons.folder_outlined, color: colors.muted),
                        title: Text(g),
                        subtitle: Text(tr('{p0} mục', {'p0': c.countInGroup(g)})),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: tr('Đổi tên'),
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final name = await askGroupName(ctx, initial: g, title: tr('Đổi tên thẻ'), confirmLabel: tr('Lưu'));
                              if (name != null && name != g) c.renameGroup(g, name);
                            },
                          ),
                          IconButton(
                            tooltip: tr('Xóa thẻ'),
                            icon: Icon(Icons.delete_outline_rounded, color: colors.danger),
                            onPressed: () async {
                              final ok = await confirmDialog(
                                ctx,
                                title: tr('Xóa thẻ "{p0}"?', {'p0': g}),
                                message: tr('Các mục có thẻ này không bị xóa, chỉ chuyển sang "Không có thẻ".'),
                                confirmLabel: tr('Xóa thẻ'),
                                danger: true,
                              );
                              if (ok) c.deleteGroup(g);
                            },
                          ),
                        ]),
                      ),
                  ]),
                ),
              const SizedBox(height: Gap.sm),
            ]),
          ),
        );
      },
    ),
  );
}
