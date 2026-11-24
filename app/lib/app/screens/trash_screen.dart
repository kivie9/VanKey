import 'package:material_ui/material_ui.dart';

import '../vault_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import '../i18n.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final items = controller.data.items.where((i) => i.inTrash).toList();
          return Scaffold(
            appBar: AppBar(
              title: Text(tr('Thùng rác')),
              actions: [
                if (items.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(tr('Dọn sạch thùng rác?')),
                          content: Text(tr('{p0} mục sẽ bị xóa vĩnh viễn, không thể hoàn tác.', {'p0': items.length})),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xóa hết'))),
                          ],
                        ),
                      );
                      if (ok == true) controller.emptyTrash();
                    },
                    child: Text(tr('Dọn sạch')),
                  ),
              ],
            ),
            body: items.isEmpty
                ? EmptyState(icon: Icons.delete_outline_rounded, title: tr('Thùng rác trống'), message: tr('Mục đã xóa nằm ở đây 30 ngày rồi tự xóa hẳn.'))
                : ListView(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl), children: [
                    CardList(children: [
                    for (final i in items)
                      ListTile(
                        leading: Avatar.forItem(i),
                        title: Text(i.title),
                        subtitle: Text(i.subtitle),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: tr('Khôi phục'), icon: const Icon(Icons.restore), onPressed: () => controller.restore(i)),
                          IconButton(
                            tooltip: tr('Xóa vĩnh viễn'),
                            icon: const Icon(Icons.delete_forever_outlined),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(tr('Xóa vĩnh viễn "{p0}"?', {'p0': i.title})),
                                  content: Text(tr('Không thể hoàn tác.')),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
                                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xóa'))),
                                  ],
                                ),
                              );
                              if (ok == true) controller.purge(i);
                            },
                          ),
                        ]),
                      ),
                    ]),
                  ]),
          );
        },
      );
}
