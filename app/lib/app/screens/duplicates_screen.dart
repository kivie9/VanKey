import 'package:material_ui/material_ui.dart';

import '../../core/security/duplicates.dart';
import '../vault_controller.dart';
import '../widgets/common.dart';
import '../i18n.dart';

class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({super.key, required this.controller});
  final VaultController controller;

  static String _kind(DuplicateKind k) => switch (k) {
        DuplicateKind.sameTotp => tr('Cùng khóa 2FA'),
        DuplicateKind.sameTitleAccount => tr('Cùng tên và tài khoản'),
        DuplicateKind.sharedPassword => tr('Dùng chung một mật khẩu'),
      };

  void _merge(BuildContext context, DuplicateGroup g) {
    final out = mergeDuplicateGroup(g, clock: controller.clock);
    controller.mutate((d) {
      var r = d.upsert(out.kept);
      for (final t in out.trashed) {
        r = r.upsert(t);
      }
      return r;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Đã gộp {p0} mục (các bản cũ nằm trong thùng rác)', {'p0': out.trashed.length + 1}))),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final groups = findDuplicates(controller.data.items);
          return Scaffold(
            appBar: AppBar(title: Text(tr('Mục trùng lặp'))),
            body: groups.isEmpty
                ? Center(child: Text(tr('Không có mục trùng lặp')))
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final g in groups)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_kind(g.kind), style: Theme.of(context).textTheme.labelLarge),
                            for (final i in g.items)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Avatar.forItem(i, size: 32),
                                title: Text(i.title),
                                subtitle: Text(i.subtitle),
                              ),
                            if (g.canMerge)
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonal(onPressed: () => _merge(context, g), child: Text(tr('Gộp, giữ bản mới nhất'))),
                              )
                            else
                              Text(tr('Chỉ cảnh báo: đổi mật khẩu để mỗi tài khoản một mật khẩu riêng.')),
                          ]),
                        ),
                      ),
                  ]),
          );
        },
      );
}
