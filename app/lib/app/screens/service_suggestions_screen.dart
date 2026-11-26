import 'package:material_ui/material_ui.dart';

import '../../core/vault/models.dart';
import '../../core/vault/services.dart';
import '../i18n.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/ui.dart';

/// Câu hỏi "mục này có phải của dịch vụ X không?". App chỉ sửa khi người dùng bấm "Đúng".
class ServiceSuggestionCard extends StatelessWidget {
  const ServiceSuggestionCard({super.key, required this.controller, required this.item, required this.service});
  final VaultController controller;
  final Item item;
  final KnownService service;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('"{p0}" có phải là {p1}?', {'p0': item.title, 'p1': service.name}), style: text.titleMedium),
          const SizedBox(height: Gap.xs),
          Text(
            [if (item.subtitle.isNotEmpty) item.subtitle, tr('Bấm "Đúng" sẽ điền địa chỉ {p0}, tên giữ nguyên.', {'p0': service.domains.first})].join('\n'),
            style: text.bodySmall,
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => controller.dismissServiceSuggestion(item, service), child: Text(tr('Không'))),
            TextButton(onPressed: () => controller.applyService(item, service), child: Text(tr('Đúng'))),
          ]),
        ]),
      ),
    );
  }
}

/// Danh sách các mục cũ chưa có địa chỉ web mà app đoán được dịch vụ.
class ServiceSuggestionsScreen extends StatelessWidget {
  const ServiceSuggestionsScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Gợi ý dịch vụ'))),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final list = controller.serviceSuggestions;
            if (list.isEmpty) {
              return EmptyState(icon: Icons.check_circle_outline, title: tr('Không còn gợi ý nào'), message: tr('Mục chưa có địa chỉ web mà tên giống một dịch vụ sẽ hiện ở đây.'));
            }
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView.separated(
                  padding: const EdgeInsets.all(Gap.lg),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
                  itemBuilder: (_, i) => ServiceSuggestionCard(key: ValueKey(list[i].$1.id), controller: controller, item: list[i].$1, service: list[i].$2),
                ),
              ),
            );
          },
        ),
      );
}
