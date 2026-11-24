import 'package:material_ui/material_ui.dart';

import '../constants.dart';
import '../../core/security/reminders.dart';
import '../../core/vault/models.dart';
import '../../core/vault/search.dart';
import '../labels.dart';
import '../vault_controller.dart';
import '../item_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'item_detail_screen.dart';
import 'import_screen.dart';
import 'item_editor_screen.dart';
import 'qr_scan_screen.dart';
import 'reminders_screen.dart';
import 'settings_tab.dart';
import 'sync_screen.dart';
import '../group_actions.dart';
import 'tools_tab.dart';
import '../i18n.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _dialOpen = false; // menu dấu cộng đang mở: làm mờ phần còn lại

  Widget _scrim() => Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _dialOpen = false),
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        ),
      );

  void _push(Widget page, {bool full = false}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: full, builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 840;
      final body = ListenableBuilder(
        listenable: c,
        builder: (context, _) => IndexedStack(index: _tab, children: [
          _ItemsTab(controller: c, onlyTotp: false),
          _ItemsTab(controller: c, onlyTotp: true),
          ToolsTab(controller: c),
        ]),
      );
      final dests = [
        (Icons.lock_outline, Icons.lock, tr('Kho')),
        (Icons.shield_outlined, Icons.shield, '2FA'),
        (Icons.apps_outlined, Icons.apps, tr('Tiện ích')),
      ];
      return Scaffold(
        floatingActionButton: _tab == 2
            ? null
            : _SpeedDial(
                open: _dialOpen,
                onOpenChanged: (v) => setState(() => _dialOpen = v),
                // Tab 2FA mở sẵn loại "Mã 2FA"; tab Kho không mở sẵn loại 2FA dù lần trước vừa tạo mã.
                onManual: () => _push(
                  ItemEditorScreen(
                    controller: c,
                    startType: _tab == 1 ? ItemType.totp : (c.lastType == ItemType.totp ? ItemType.login : null),
                  ),
                  full: true,
                ),
                onScan: () => _push(QrScanScreen(controller: c)),
                onImport: () => _push(ImportScreen(controller: c)),
              ),
        bottomNavigationBar: wide
            ? null
            : Stack(children: [
                NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
                ),
                if (_dialOpen && _tab != 2) _scrim(),
              ]),
        body: Stack(children: [
          SafeArea(
          child: wide
              ? Row(children: [
                  NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ])
              : body,
        ),
          if (_dialOpen && _tab != 2) _scrim(),
        ]),
      );
    });
  }
}

/// Mục có mã 2FA: tab 2FA chỉ hiện các mục này.
bool _hasCode(Item i) => i.totp != null && i.totp!.secret.isNotEmpty;

/// Tab Kho không hiện mục loại "Mã 2FA" (đã có tab riêng). Mục loại 2FA hỏng, không có khóa, vẫn hiện ở Kho để không bị ẩn mất.
bool _inVault(Item i) => i.type != ItemType.totp || !_hasCode(i);

/// Tab Kho (mật khẩu, thẻ, ghi chú...; không hiện mã) hoặc tab 2FA (chỉ mục có mã).
class _ItemsTab extends StatefulWidget {
  const _ItemsTab({required this.controller, required this.onlyTotp});
  final VaultController controller;
  final bool onlyTotp;

  @override
  State<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<_ItemsTab> {
  bool _searching = false;
  final _q = TextEditingController();
  final _collapsed = <String>{};
  String _groupFilter = ''; // rỗng = mọi nhóm

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// Bảng "Sắp xếp và lọc": mọi lựa chọn là chip bấm một lần, đổi là áp dụng ngay.
  Future<void> _openFilter() async {
    final c = widget.controller;
    final groups = c.data.items.where((i) => !i.inTrash && i.group.isNotEmpty).map((i) => i.group).toSet().toList()..sort();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget label(String t) => Padding(
                padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
                child: Text(t, style: Theme.of(ctx).textTheme.titleSmall),
              );
          Widget chips<T>(List<(T, String)> options, T current, void Function(T) onPick) => Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
                for (final o in options)
                  ChoiceChip(
                    label: Text(o.$2),
                    selected: o.$1 == current,
                    onSelected: (_) {
                      onPick(o.$1);
                      setSheet(() {});
                    },
                  ),
              ]);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(tr('Sắp xếp và lọc'), style: Theme.of(ctx).textTheme.titleLarge)),
                  TextButton(
                    onPressed: () {
                      c.setGroupBy(GroupBy.group);
                      c.setSortBy(SortBy.name);
                      setState(() => _groupFilter = '');
                      setSheet(() {});
                    },
                    child: Text(tr('Đặt lại')),
                  ),
                ]),
                label(tr('Gom theo')),
                chips<GroupBy>([(GroupBy.group, tr('Thẻ')), (GroupBy.type, tr('Loại')), (GroupBy.none, tr('Không gom'))], c.groupBy, c.setGroupBy),
                label(tr('Sắp xếp')),
                chips<SortBy>([(SortBy.name, tr('Tên A–Z')), (SortBy.updated, tr('Mới sửa')), (SortBy.created, tr('Mới tạo'))], c.sortBy, c.setSortBy),
                if (groups.isNotEmpty) ...[
                  label(tr('Lọc theo thẻ')),
                  chips<String>([('', tr('Tất cả')), for (final g in groups) (g, g)], _groupFilter, (v) => setState(() => _groupFilter = v)),
                ],
                const SizedBox(height: Gap.md),
                TextButton.icon(
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(tr('Quản lý thẻ (đổi tên, xóa)')),
                  onPressed: () async {
                    await manageGroups(ctx, c);
                    if (_groupFilter.isNotEmpty && !c.groups.contains(_groupFilter)) setState(() => _groupFilter = '');
                    setSheet(() {});
                  },
                ),
                const SizedBox(height: Gap.xl),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Xong')))),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _open(Item i) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ItemDetailScreen(controller: widget.controller, itemId: i.id)),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final items = c.data.items
        .where((i) => !i.inTrash)
        .where((i) => widget.onlyTotp ? _hasCode(i) : _inVault(i))
        .where((i) => matchesQuery(i, _q.text))
        .where((i) => _groupFilter.isEmpty || i.group == _groupFilter)
        .toList()
      ..sort((a, b) => switch (c.sortBy) {
            SortBy.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            SortBy.updated => b.updatedAt.compareTo(a.updatedAt),
            SortBy.created => b.createdAt.compareTo(a.createdAt),
          });

    final groups = <String, List<Item>>{};
    final favs = items.where((i) => i.favorite).toList();
    for (final i in items) {
      final key = switch (c.groupBy) {
        GroupBy.group => i.group.isEmpty ? tr('Chưa gắn thẻ') : i.group,
        GroupBy.type => L.type(i.type),
        GroupBy.none => '',
      };
      groups.putIfAbsent(key, () => []).add(i);
    }
    final names = groups.keys.toList()
      ..sort((a, b) => a == tr('Chưa gắn thẻ') ? 1 : (b == tr('Chưa gắn thẻ') ? -1 : a.compareTo(b)));

    final title = widget.onlyTotp ? tr('Mã 2FA') : tr('Kho');
    return Clock(
      builder: (context, now) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: SizedBox(
            height: 56,
            child: Row(children: [
              SettingsButton(controller: c),
              Expanded(
                child: _searching
                    ? TextField(
                        controller: _q,
                        autofocus: true,
                        decoration: InputDecoration(hintText: tr('Tìm theo tên, tài khoản, thẻ…'), border: InputBorder.none),
                        onChanged: (_) => setState(() {}),
                      )
                    : Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (!_searching) Builder(builder: (context) {
                final n = pendingAlerts(c.data.items, now, snoozedUntil: c.snoozed).length;
                return IconButton(
                  tooltip: tr('Nhắc nhở'),
                  icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.notifications_none)),
                  onPressed: () => pushPage(context, RemindersScreen(controller: c)),
                );
              }),
              if (!_searching && c.syncStatus != SyncStatus.off)
                IconButton(
                  tooltip: tr('Đồng bộ'),
                  icon: switch (c.syncStatus) {
                    SyncStatus.syncing => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    SyncStatus.error => const Icon(Icons.cloud_off, color: Colors.orange),
                    _ => Icon(c.conflicts.isEmpty ? Icons.cloud_done_outlined : Icons.merge_type),
                  },
                  onPressed: () => pushPage(context, SyncScreen(controller: c)),
                ),
              if (!_searching) IconButton(
                tooltip: tr('Sắp xếp và lọc'),
                icon: Badge(
                  isLabelVisible: _groupFilter.isNotEmpty || c.groupBy != GroupBy.group || c.sortBy != SortBy.name,
                  smallSize: 8,
                  child: const Icon(Icons.filter_list),
                ),
                onPressed: _openFilter,
              ),
              IconButton(
                tooltip: _searching ? tr('Đóng tìm kiếm') : tr('Tìm kiếm'),
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _q.clear();
                }),
              ),
            ]),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _Empty(searching: _q.text.isNotEmpty || _groupFilter.isNotEmpty, onlyTotp: widget.onlyTotp)
              : LayoutBuilder(builder: (context, box) {
                  // Màn rộng: nhiều cột (tối đa ~440 px mỗi cột); điện thoại: một cột.
                  final wide = box.maxWidth >= 640;
                  Widget tile(List<Item> list, int i) => ItemTile(
                        item: list[i],
                        now: now,
                        showCode: widget.onlyTotp,
                        onTap: () => _open(list[i]),
                        onLongPress: () => showItemActions(this.context, widget.controller, list[i]),
                        onNext: list[i].totp?.isHotp == true ? () => widget.controller.hotpNext(list[i]) : null,
                      );
                  Widget tiles(List<Item> list) => wide
                      ? SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 440, mainAxisExtent: 76, mainAxisSpacing: Gap.sm, crossAxisSpacing: Gap.sm),
                            delegate: SliverChildBuilderDelegate(
                              (c, i) => Card(child: Center(child: tile(list, i))),
                              childCount: list.length,
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (c, i) => Padding(padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm), child: Card(child: tile(list, i))),
                            childCount: list.length,
                          ),
                        );
                  return CustomScrollView(slivers: [
                    if (favs.isNotEmpty && _q.text.isEmpty) ...[
                      SliverToBoxAdapter(child: _Header(tr('Yêu thích'))),
                      tiles(favs),
                    ],
                    for (final n in names) ...[
                      if (n.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _Header(
                            n,
                            count: groups[n]!.length,
                            collapsed: _collapsed.contains(n),
                            onTap: () => setState(() => _collapsed.contains(n) ? _collapsed.remove(n) : _collapsed.add(n)),
                          ),
                        ),
                      if (n.isEmpty || !_collapsed.contains(n)) tiles(groups[n]!),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ]);
                }),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.count, this.collapsed = false, this.onTap});
  final String text;
  final int? count;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SectionHeader(text, count: count, collapsed: onTap == null ? null : collapsed, onTap: onTap);
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching, required this.onlyTotp});
  final bool searching;
  final bool onlyTotp;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: searching ? Icons.search_off_rounded : (onlyTotp ? Icons.shield_outlined : Icons.lock_outline_rounded),
        title: searching ? tr('Không tìm thấy') : (onlyTotp ? tr('Chưa có mã 2FA nào') : tr('Kho đang trống')),
        message: searching ? null : tr('Bấm dấu + để thêm mục đầu tiên'),
      );
}

/// Nút tròn dấu cộng: xoay thành × và bung các lựa chọn thêm mục.
class _SpeedDial extends StatefulWidget {
  const _SpeedDial({required this.open, required this.onOpenChanged, required this.onManual, required this.onScan, required this.onImport});
  final bool open;
  final ValueChanged<bool> onOpenChanged;
  final VoidCallback onManual;
  final VoidCallback onScan;
  final VoidCallback onImport;

  @override
  State<_SpeedDial> createState() => _SpeedDialState();
}

class _SpeedDialState extends State<_SpeedDial> {
  bool get _open => widget.open;

  void _run(VoidCallback f) {
    widget.onOpenChanged(false);
    f();
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.edit_outlined, tr('Nhập tay'), widget.onManual),
      (Icons.qr_code_scanner, tr('Quét QR'), widget.onScan),
      (Icons.file_download_outlined, tr('Nhập từ file'), widget.onImport),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final a in actions.reversed)
          AnimatedSize(
            duration: Timing.fast,
            curve: Curves.easeOut,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // Nhãn cũng bấm được (không chỉ icon tròn).
                      // Nền được làm mờ khi menu mở, nên menu dùng màu thẻ bình thường là đủ nổi.
                      Material(
                        color: AppColors.of(context).card,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm + 2)),
                        child: InkWell(
                          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm + 2)),
                          onTap: () => _run(a.$3),
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 10), child: Text(a.$2, style: Theme.of(context).textTheme.labelLarge)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FloatingActionButton.small(heroTag: a.$2, tooltip: a.$2, backgroundColor: AppColors.of(context).card, foregroundColor: AppColors.of(context).accent, onPressed: () => _run(a.$3), child: Icon(a.$1)),
                    ]),
                  )
                : const SizedBox(width: 0, height: 0),
          ),
        DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.of(context).accent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))]),
          child: FloatingActionButton(
            heroTag: 'main',
            tooltip: _open ? tr('Đóng') : tr('Thêm mục'),
            onPressed: () => widget.onOpenChanged(!_open),
            child: AnimatedRotation(turns: _open ? 0.125 : 0, duration: Timing.fast, child: const Icon(Icons.add)),
          ),
        ),
      ],
    );
  }
}
