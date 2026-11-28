import 'package:material_ui/material_ui.dart';

import '../constants.dart';
import '../../core/security/health.dart';
import '../../core/security/hibp.dart';
import '../../core/vault/models.dart';
import '../hibp_client.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'item_detail_screen.dart';
import '../i18n.dart';

/// Kiểm tra bảo mật: mật khẩu yếu, dùng chung, chưa bật 2FA, và (tùy chọn) bị lộ trên mạng.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  final _leaked = <String>{};
  bool _checking = false;
  bool _checked = false;
  String? _error;

  void _open(Item i) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ItemDetailScreen(controller: widget.controller, itemId: i.id)),
      );

  Future<void> _checkLeaks() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Kiểm tra rò rỉ trên mạng?')),
        content: Text(
          tr('App chỉ gửi 5 ký tự đầu của mã băm SHA-1 của mỗi mật khẩu tới dịch vụ Have I Been Pwned. Mật khẩu và phần còn lại của mã băm không bao giờ rời khỏi máy, nên dịch vụ không biết mật khẩu của bạn.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Kiểm tra'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final cache = <String, String>{};
      final found = <String>{};
      for (final i in widget.controller.data.items.where((i) => !i.inTrash && i.password.isNotEmpty)) {
        final n = await Hibp.check(i.password, (prefix) async => cache[prefix] ??= await fetchHibpRange(prefix));
        if (n > 0) found.add(i.id);
      }
      setState(() {
        _leaked
          ..clear()
          ..addAll(found);
        _checked = true;
      });
    } on Object {
      setState(() => _error = tr('Không kết nối được dịch vụ kiểm tra. Thử lại khi có mạng.'));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final r = healthReport(widget.controller.data.items, leakedIds: _leaked);
          final colors = AppColors.of(context);
          final (label, color) = switch (r.level) {
            HealthLevel.good => (tr('Tốt'), colors.success),
            HealthLevel.needsWork => (tr('Cần cải thiện'), colors.warn),
            HealthLevel.atRisk => (tr('Nhiều rủi ro'), colors.danger),
          };
          Widget section(String title, List<Item> items) => items.isEmpty
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SectionHeader(title, count: items.length, padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xl, Gap.xs, Gap.sm)),
                  CardList(children: [
                    for (final i in items) ListTile(leading: Avatar.forItem(i), title: Text(i.title), subtitle: Text(i.subtitle), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _open(i)),
                  ]),
                ]);
          return Scaffold(
            appBar: AppBar(title: Text(tr('Kiểm tra bảo mật'))),
            body: ListView(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Gap.xl),
                  child: Column(children: [
                    SizedBox(
                      width: Sizes.healthGauge,
                      height: Sizes.healthGauge,
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox.expand(child: CircularProgressIndicator(value: r.score / 100, strokeWidth: 10, strokeCap: StrokeCap.round, color: color)),
                        Text('${r.score}', style: Theme.of(context).textTheme.displaySmall),
                      ]),
                    ),
                    const SizedBox(height: Gap.lg),
                    Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
                    const SizedBox(height: Gap.xs),
                    Text(r.issueCount == 0 ? tr('Không phát hiện vấn đề') : tr('{p0} điểm cần xem lại', {'p0': r.issueCount}), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted)),
                    const SizedBox(height: Gap.lg),
                    OutlinedButton.icon(
                      onPressed: _checking ? null : _checkLeaks,
                      icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore),
                      label: Text(_checking ? tr('Đang kiểm tra…') : (_checked ? tr('Kiểm tra lại rò rỉ') : tr('Kiểm tra rò rỉ trên mạng'))),
                    ),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: Gap.md), child: Notice(_error!, tone: NoticeTone.error, icon: Icons.error_outline)),
                    if (_checked && _leaked.isEmpty && _error == null)
                      Padding(padding: const EdgeInsets.only(top: Gap.md), child: Notice(tr('Không mật khẩu nào có trong dữ liệu rò rỉ đã biết.'), tone: NoticeTone.info, icon: Icons.check_circle_outline)),
                  ]),
                ),
              ),
              section(tr('Mật khẩu đã bị lộ, đổi ngay'), r.leaked),
              section(tr('Mật khẩu yếu'), r.weak),
              for (final g in r.reused) section(tr('Dùng chung một mật khẩu'), g.items),
              section(tr('Chưa bật 2FA'), r.noTotp),
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(tr('Điểm là công thức tự đặt của VanKey, chỉ mang tính tham khảo.'), style: TextStyle(fontSize: 12)),
              ),
            ]),
          );
        },
      );
}
