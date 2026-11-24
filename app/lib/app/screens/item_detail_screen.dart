import 'dart:async';

import '../constants.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/vault/models.dart';
import '../item_actions.dart';
import '../labels.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'item_editor_screen.dart';
import 'qr_show_screen.dart';
import '../group_actions.dart';
import '../i18n.dart';

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({super.key, required this.controller, required this.itemId});
  final VaultController controller;
  final String itemId;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final _revealed = <int>{};
  Timer? _hideTimer;

  /// Mọi thứ đã hiện ra tự ẩn lại sau 30 giây (và luôn ẩn khi vừa mở màn chi tiết).
  void _armAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(Timing.autoHideSecrets, () {
      if (mounted) {
        setState(() {
          _revealed.clear();
        });
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final item = c.data.byId(widget.itemId);
        if (item == null || item.inTrash) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text(tr('Mục không còn tồn tại'))));
        }
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: item.favorite ? tr('Bỏ yêu thích') : tr('Yêu thích'),
                icon: Icon(item.favorite ? Icons.star : Icons.star_border),
                onPressed: () => c.toggleFavorite(item),
              ),
              if (item.totp != null && item.totp!.secret.isNotEmpty)
                IconButton(
                  tooltip: tr('Hiện mã QR'),
                  icon: const Icon(Icons.qr_code_2),
                  onPressed: () => pushPage(context, QrShowScreen.forItem(item)),
                ),
              IconButton(
                tooltip: tr('Sửa'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ItemEditorScreen(controller: c, existing: item)),
                ),
              ),
              IconButton(
                tooltip: tr('Xóa vào thùng rác'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await confirmDialog(
                    context,
                    title: tr('Chuyển "{p0}" vào thùng rác?', {'p0': item.title}),
                    message: tr('Mục sẽ nằm trong thùng rác 30 ngày, bạn có thể khôi phục trong thời gian đó.'),
                    confirmLabel: tr('Chuyển vào thùng rác'),
                    danger: true,
                  );
                  if (!ok || !context.mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  c.trash(item);
                  Navigator.of(context).pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text(tr('Đã chuyển "{p0}" vào thùng rác', {'p0': item.title})), action: SnackBarAction(label: tr('Hoàn tác'), onPressed: () => c.restore(c.data.byId(item.id)!))),
                  );
                },
              ),
            ],
          ),
          body: Clock(
            builder: (context, now) {
              final colors = AppColors.of(context);
              final text = Theme.of(context).textTheme;
              final hasTotp = item.totp != null && item.totp!.secret.isNotEmpty;
              final shown = [for (var i = 0; i < item.fields.length; i++) if (item.fields[i].value.isNotEmpty) i];
              return ListView(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl), children: [
                // Phần đầu: tên, loại, nhóm
                Row(children: [
                  Avatar.forItem(item, size: 60),
                  const SizedBox(width: Gap.lg),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.title, style: text.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Gap.sm),
                      Wrap(spacing: Gap.sm, runSpacing: Gap.xs, children: [
                        _Tag(icon: L.typeIcons[item.type] ?? Icons.label_outline, label: L.type(item.type)),
                        _Tag(
                          icon: Icons.folder_outlined,
                          label: item.group.isEmpty ? tr('Chưa gắn thẻ') : item.group,
                          onTap: () => _changeGroup(item),
                          trailing: Icons.arrow_drop_down,
                        ),
                      ]),
                    ]),
                  ),
                ]),
                const SizedBox(height: Gap.lg),
                if (hasTotp) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.lg),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('Mã 2FA').toUpperCase(), style: text.labelSmall?.copyWith(letterSpacing: 0.9)),
                        const SizedBox(height: Gap.md),
                        Row(children: [
                          // FittedBox: màn hẹp hoặc chữ hệ thống lớn thì mã tự thu nhỏ thay vì tràn.
                          Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: TotpChip(big: true, params: item.totp!, now: now, onNext: item.totp!.isHotp ? () => c.hotpNext(item) : null)))),
                        ]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                ],
                if (shown.isNotEmpty) SectionCard(children: [for (final i in shown) _fieldRow(item.fields[i], i)]),
                if (item.pwHistory.isNotEmpty) ...[const SizedBox(height: Gap.md), _history(item)],
                if (shown.isEmpty && !hasTotp)
                  Padding(padding: const EdgeInsets.all(Gap.xl), child: Center(child: Text(tr('Mục này chưa có thông tin nào.'), style: text.bodyMedium?.copyWith(color: colors.muted)))),
              ]);
            },
          ),
        );
      },
    );
  }

  Future<void> _changeGroup(Item item) async {
    final c = widget.controller;
    final picked = await pickGroup(context, c, current: item.group);
    if (picked != null && picked != item.group) c.upsert(item.edit(clock: c.clock, group: picked));
  }

  Widget _history(Item item) => Card(
        child: ExpansionTile(
          title: Text(tr('Lịch sử mật khẩu ({p0})', {'p0': item.pwHistory.length}), style: Theme.of(context).textTheme.titleMedium),
          children: [
            for (var n = 0; n < item.pwHistory.length; n++) ...[
              const Divider(),
              ListTile(
                dense: true,
                title: Text(_revealed.contains(Mask.historyRevealBase + n) ? item.pwHistory[n].value : Mask.dots),
                subtitle: Text(item.pwHistory[n].changedAt.toLocal().toString().split('.').first),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: tr('Hiện/ẩn'),
                    icon: Icon(_revealed.contains(Mask.historyRevealBase + n) ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () {
                      final show = !_revealed.contains(Mask.historyRevealBase + n);
                      setState(() => show ? _revealed.add(Mask.historyRevealBase + n) : _revealed.remove(Mask.historyRevealBase + n));
                      if (show) _armAutoHide();
                    },
                  ),
                  IconButton(tooltip: tr('Chép'), icon: const Icon(Icons.copy_rounded), onPressed: () => copyText(context, item.pwHistory[n].value, what: tr('Đã chép mật khẩu cũ'))),
                  IconButton(tooltip: tr('Dùng lại'), icon: const Icon(Icons.history), onPressed: () => widget.controller.changePassword(item, item.pwHistory[n].value)),
                ]),
              ),
            ],
          ],
        ),
      );

  Widget _fieldRow(Field f, int index) {
    final hidden = f.secret && !_revealed.contains(index);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L.field(f), style: text.labelSmall?.copyWith(letterSpacing: 0.3)),
            const SizedBox(height: 3),
            SelectableText(hidden ? Mask.dots : f.value, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500, color: colors.fg, letterSpacing: hidden ? Mask.letterSpacing : 0)),
          ]),
        ),
        if (f.secret)
          IconButton(
            tooltip: hidden ? tr('Hiện') : tr('Ẩn'),
            icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () {
              setState(() => hidden ? _revealed.add(index) : _revealed.remove(index));
              if (hidden) _armAutoHide();
            },
          ),
        if (f.kind == 'url' || f.key == 'url') IconButton(tooltip: tr('Mở link'), icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openExternalUrl(context, widget.controller, f.value)),
        IconButton(
          tooltip: tr('Chép'),
          icon: const Icon(Icons.copy_rounded),
          onPressed: () => copyText(context, f.value, what: tr('Đã chép {p0}', {'p0': L.field(f).toLowerCase()})),
        ),
      ]),
    );
  }
}

/// Nhãn nhỏ dạng viên thuốc (loại mục, nhóm).
class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, this.onTap, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: onTap == null ? c.field : c.accentSoft,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: onTap == null ? c.muted : c.accent),
            const SizedBox(width: 6),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: onTap == null ? c.muted : c.accent))),
            if (trailing != null) Icon(trailing, size: 16, color: c.accent),
          ]),
        ),
      ),
    );
  }
}
