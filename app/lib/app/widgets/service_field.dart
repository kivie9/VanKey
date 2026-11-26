import 'package:material_ui/material_ui.dart';

import '../../core/vault/models.dart';
import '../../core/vault/services.dart';
import '../i18n.dart';
import '../theme.dart';
import 'common.dart';

/// Một dòng gợi ý của ô "Dịch vụ".
final class ServiceOption {
  const ServiceOption({required this.key, required this.name, this.domain, this.count = 0, this.isNew = false});
  final String key;
  final String name;
  final String? domain;

  /// Số tài khoản đã có trong kho.
  final int count;

  /// Dòng "Thêm dịch vụ ..." cho trang app chưa biết.
  final bool isNew;
}

/// Gợi ý cho [query]: dịch vụ đã có trong kho đứng trước (nhiều tài khoản nhất lên đầu), rồi tới dịch vụ app biết sẵn.
/// Chưa gõ gì thì chỉ hiện dịch vụ đã có.
List<ServiceOption> serviceOptions(String query, Iterable<Item> items, {int limit = 8}) {
  final counts = <String, int>{};
  final refs = <String, ServiceRef>{};
  for (final i in items) {
    if (i.inTrash) continue;
    final r = serviceOf(i);
    if (r == null) continue;
    refs.putIfAbsent(r.key, () => r);
    counts[r.key] = (counts[r.key] ?? 0) + 1;
  }
  final q = normalizeName(query);
  bool hit(String key, String name, String? domain) {
    if (q.isEmpty || normalizeName(name).contains(q) || (domain ?? '').contains(q)) return true;
    return knownServices.any((s) => 's:${s.id}' == key && s.aliases.any((a) => a.startsWith(q)));
  }

  final mine = [
    for (final r in refs.values)
      if (hit(r.key, r.name, r.domain)) ServiceOption(key: r.key, name: r.name, domain: r.domain, count: counts[r.key]!),
  ]..sort((a, b) => a.count != b.count ? b.count - a.count : normalizeName(a.name).compareTo(normalizeName(b.name)));
  final others = [
    if (q.isNotEmpty)
      for (final s in knownServices)
        if (!refs.containsKey('s:${s.id}') && hit('s:${s.id}', s.name, s.domains.first)) ServiceOption(key: 's:${s.id}', name: s.name, domain: s.domains.first),
  ];
  final out = [...mine, ...others].take(limit).toList();
  if (q.isNotEmpty && !out.any((o) => normalizeName(o.name) == q)) {
    final text = query.trim();
    final host = hostOf(text);
    final known = host == null ? serviceNamed(text) : serviceOfHost(host);
    if (known == null) {
      out.add(ServiceOption(key: host == null ? 't:$q' : 'd:${baseDomain(host)}', name: text, domain: host, isNew: true));
    }
  }
  return out;
}

/// Ô chọn dịch vụ: gõ vài chữ rồi chọn, hoặc thêm dịch vụ mới.
class ServiceField extends StatelessWidget {
  const ServiceField({super.key, required this.controller, required this.focusNode, required this.items, required this.onSelected});
  final TextEditingController controller;
  final FocusNode focusNode;
  final Iterable<Item> items;
  final ValueChanged<ServiceOption> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => RawAutocomplete<ServiceOption>(
          textEditingController: controller,
          focusNode: focusNode,
          displayStringForOption: (o) => o.name,
          optionsBuilder: (v) => serviceOptions(v.text, items),
          onSelected: onSelected,
          fieldViewBuilder: (context, ctrl, focus, submit) => TextField(
            controller: ctrl,
            focusNode: focus,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(labelText: tr('Dịch vụ'), hintText: tr('Chọn hoặc gõ, ví dụ Facebook'), prefixIcon: const Icon(Icons.apps_outlined)),
          ),
          optionsViewBuilder: (context, select, options) {
            final c = AppColors.of(context);
            final text = Theme.of(context).textTheme;
            final highlighted = AutocompleteHighlightedOption.of(context);
            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: Material(
                  color: c.card,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(Radii.md),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth, maxHeight: 264),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final (i, o) in options.indexed)
                          ListTile(
                            dense: true,
                            selected: i == highlighted,
                            selectedTileColor: c.accentSoft,
                            leading: o.isNew ? Icon(Icons.add, color: c.accent) : Avatar(o.name, size: 28, url: o.domain ?? ''),
                            title: Text(o.isNew ? tr('Thêm dịch vụ "{p0}"', {'p0': o.name}) : o.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: o.count > 0 ? Text(tr('{p0} tài khoản', {'p0': o.count}), style: text.bodySmall) : null,
                            onTap: () => select(o),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
}
