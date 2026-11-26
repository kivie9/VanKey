/// Bố cục máy tính theo docs/prototype/vankey-prototype.html (chế độ "Máy tính (Windows)"):
/// thanh trên, cột menu bên trái, lưới thẻ ở giữa; chi tiết mục mở trong hộp thoại.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/security/reminders.dart';
import '../../core/totp/totp.dart';
import '../../core/vault/models.dart';
import '../../core/vault/search.dart';
import '../i18n.dart';
import '../item_actions.dart';
import '../item_list.dart';
import '../labels.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/common.dart';
import '../widgets/speed_dial.dart';
import '../widgets/tag_badge.dart';
import '../widgets/ui.dart';
import 'import_screen.dart';
import 'item_detail_screen.dart';
import 'item_editor_screen.dart';
import 'qr_scan_screen.dart';
import 'quick_view_screen.dart';
import 'reminders_screen.dart';
import 'settings_tab.dart';
import 'sync_screen.dart';
import 'tools_tab.dart';

/// Hai lớp nền của bố cục máy tính: [main] cho vùng danh sách, [side] cho thanh bên, thanh trên và thẻ mục.
({Color main, Color side}) _surfaces(BuildContext context) {
  final c = AppColors.of(context);
  return Theme.of(context).brightness == Brightness.light
      ? (main: c.card, side: c.page)
      : (main: c.page, side: c.card);
}

/// Mục đang chọn ở thanh bên.
sealed class _Section {
  const _Section();
}

/// Một danh sách mục của Kho, có thể lọc theo loại hoặc theo thẻ.
final class _Vault extends _Section {
  const _Vault({this.type, this.group});
  final ItemType? type;
  final String? group;

  @override
  bool operator ==(Object other) =>
      other is _Vault && other.type == type && other.group == group;

  @override
  int get hashCode => Object.hash(type, group);
}

enum _Page { totp, tools, settings }

final class _Fixed extends _Section {
  const _Fixed(this.page);
  final _Page page;

  @override
  bool operator ==(Object other) => other is _Fixed && other.page == page;

  @override
  int get hashCode => page.hashCode;
}

class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key, required this.controller});
  final VaultController controller;

  /// Cửa sổ hẹp hơn mức này dùng bố cục điện thoại.
  static const minWidth = 840.0;

  static const sidebarWidth = 200.0;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  _Section _section = const _Vault();
  bool _dialOpen = false;
  bool _searching = false;
  final _q = TextEditingController();
  final _collapsed = <String>{};

  VaultController get _c => widget.controller;

  bool get _isList =>
      _section is _Vault || _section == const _Fixed(_Page.totp);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _select(_Section s) => setState(() {
    _section = s;
    _dialOpen = false;
  });

  void _openDetail(Item item) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: Builder(
            builder: (context) {
              // Chi tiết dùng nền hộp thoại; các thẻ bên trong dùng nền trang để vẫn tách khỏi nền.
              final theme = Theme.of(context);
              final s = _surfaces(context);
              return Theme(
                data: theme.copyWith(
                  scaffoldBackgroundColor: s.main,
                  appBarTheme: theme.appBarTheme.copyWith(
                    backgroundColor: s.main,
                  ),
                  cardTheme: theme.cardTheme.copyWith(color: s.side),
                ),
                child: ItemDetailScreen(
                  controller: _c,
                  itemId: item.id,
                  inDialog: true,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final s = _surfaces(context);
      final live = _c.data.items.where((i) => !i.inTrash).toList();
      // Xóa hết mục của một loại hoặc thẻ đang xem thì quay về "Tất cả".
      final section = _section;
      if (section is _Vault && section != const _Vault()) {
        final left = live
            .where(inVault)
            .any(
              (i) =>
                  (section.type == null || i.type == section.type) &&
                  (section.group == null || i.group == section.group),
            );
        if (!left) _section = const _Vault();
      }
      return Scaffold(
        backgroundColor: s.main,
        floatingActionButton: _isList ? _dial() : null,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _TopBar(controller: _c),
                  const Divider(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: DesktopHome.sidebarWidth,
                          child: _sidebar(live),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _main(live)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_dialOpen && _isList)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _dialOpen = false),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _dial() {
    final section = _section;
    final startType = section == const _Fixed(_Page.totp)
        ? ItemType.totp
        : (section is _Vault && section.type != null
              ? section.type
              : (_c.lastType == ItemType.totp ? null : _c.lastType));
    return SpeedDial(
      open: _dialOpen,
      onOpenChanged: (v) => setState(() => _dialOpen = v),
      onManual: () => pushPage(
        context,
        ItemEditorScreen(controller: _c, startType: startType),
        full: true,
      ),
      onScan: () => pushPage(context, QrScanScreen(controller: _c)),
      onImport: () => pushPage(context, ImportScreen(controller: _c)),
    );
  }

  Widget _sidebar(List<Item> live) {
    final vault = live.where(inVault).toList();
    final types = [
      for (final t in ItemType.values)
        (t, vault.where((i) => i.type == t).length),
    ].where((e) => e.$2 > 0);
    // Thẻ mới tạo chưa có mục nào vẫn hiện trong menu để còn sửa, xóa.
    final groups = [
      for (final g in _c.groups) (g, vault.where((i) => i.group == g).length),
    ];

    Widget nav(
      _Section s,
      IconData? icon,
      String label, [
      int? count,
      Widget? leading,
    ]) => _NavRow(
      icon: icon,
      leading: leading,
      label: label,
      count: count,
      selected: _section == s,
      onTap: () => _select(s),
    );

    return Material(
      color: _surfaces(context).side,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.md, Gap.sm, Gap.md),
        children: [
          nav(
            const _Vault(),
            Icons.grid_view_rounded,
            tr('Tất cả'),
            vault.length,
          ),
          for (final (t, n) in types)
            nav(
              _Vault(type: t),
              L.typeIcons[t] ?? Icons.label_outline,
              L.type(t),
              n,
            ),
          if (groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, Gap.md, 10, Gap.xs),
              child: Text(
                tr('Thẻ').toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          for (final (g, n) in groups)
            nav(
              _Vault(group: g),
              null,
              g,
              n,
              TagBadge(name: g, color: _c.tagColor(g), size: 20),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Gap.xs, vertical: Gap.sm),
            child: Divider(),
          ),
          nav(
            const _Fixed(_Page.totp),
            Icons.shield_outlined,
            tr('Mã 2FA'),
            live.where(hasCode).length,
          ),
          nav(const _Fixed(_Page.tools), Icons.apps_outlined, tr('Tiện ích')),
          nav(
            const _Fixed(_Page.settings),
            Icons.settings_outlined,
            tr('Cài đặt'),
          ),
        ],
      ),
    );
  }

  Widget _main(List<Item> live) {
    final section = _section;
    switch (section) {
      case _Fixed(page: _Page.tools):
        return ColoredBox(
          color: AppColors.of(context).page,
          child: ToolsTab(controller: _c, showSettings: false),
        );
      case _Fixed(page: _Page.settings):
        return ColoredBox(
          color: AppColors.of(context).page,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.xl,
                      Gap.xl,
                      Gap.lg,
                      0,
                    ),
                    child: Text(
                      tr('Cài đặt'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Expanded(child: SettingsTab(controller: _c)),
                ],
              ),
            ),
          ),
        );
      case _Fixed(page: _Page.totp):
        return _list(live.where(hasCode), codes: true);
      case _Vault(:final type, :final group):
        return _list(
          live
              .where(inVault)
              .where(
                (i) =>
                    (type == null || i.type == type) &&
                    (group == null || i.group == group),
              ),
          codes: false,
        );
    }
  }

  Widget _list(Iterable<Item> source, {required bool codes}) {
    final items = source.where((i) => matchesQuery(i, _q.text)).toList();
    sortItems(items, _c.sortBy);
    final favs = items.where((i) => i.favorite).toList();
    final groups = groupItems(items, _c.groupBy);

    return Column(
      children: [
        _toolbar(),
        Expanded(
          child: items.isEmpty
              ? EmptyState(
                  icon: _q.text.isNotEmpty
                      ? Icons.search_off_rounded
                      : (codes
                            ? Icons.shield_outlined
                            : Icons.lock_outline_rounded),
                  title: _q.text.isNotEmpty
                      ? tr('Không tìm thấy')
                      : (codes
                            ? tr('Chưa có mã 2FA nào')
                            : tr('Kho đang trống')),
                  message: _q.text.isNotEmpty
                      ? null
                      : tr('Bấm dấu + để thêm mục đầu tiên'),
                )
              : Clock(
                  builder: (context, now) => LayoutBuilder(
                    builder: (context, box) {
                      const gap = 10.0, side = 14.0;
                      final columns = math.max(
                        1,
                        (box.maxWidth - side * 2 + gap) ~/ (300 + gap),
                      );
                      // Chiều cao thẻ tăng theo cỡ chữ hệ thống để không bị tràn.
                      // Tối thiểu 68 px: thẻ 2FA (logo + mã + vòng đếm) cần chiều cao này.
                      final height = math.max(
                        68.0,
                        MediaQuery.textScalerOf(context).scale(44) + 16,
                      );

                      Widget grid(List<Item> list) => SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: side),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisExtent: height,
                                mainAxisSpacing: Gap.sm,
                                crossAxisSpacing: gap,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _card(list[i], now, codes),
                            childCount: list.length,
                          ),
                        ),
                      );

                      Widget header(String key, String label, int count) =>
                          SliverToBoxAdapter(
                            child: _GroupHeader(
                              label,
                              count: count,
                              collapsed: _collapsed.contains(key),
                              onTap: () => setState(
                                () => _collapsed.contains(key)
                                    ? _collapsed.remove(key)
                                    : _collapsed.add(key),
                              ),
                            ),
                          );

                      // Khóa thu gọn riêng cho "Yêu thích" để không trùng với thẻ cùng tên.
                      const favKey = '\u0000fav';
                      return CustomScrollView(
                        slivers: [
                          if (favs.isNotEmpty && _q.text.isEmpty) ...[
                            header(favKey, tr('Yêu thích'), favs.length),
                            if (!_collapsed.contains(favKey)) grid(favs),
                          ],
                          for (final (n, list) in groups) ...[
                            if (n.isNotEmpty)
                              header(n, n, list.length)
                            else
                              const SliverToBoxAdapter(
                                child: SizedBox(height: Gap.md),
                              ),
                            if (n.isEmpty || !_collapsed.contains(n))
                              grid(list),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 96)),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _toolbar() {
    final colors = AppColors.of(context);
    final side = _surfaces(context).side;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            IconButton(
              tooltip: _searching ? tr('Đóng tìm kiếm') : tr('Tìm kiếm'),
              icon: Icon(_searching ? Icons.close : Icons.search, size: 20),
              style: IconButton.styleFrom(backgroundColor: side),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _q.clear();
              }),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _searching
                  ? TextField(
                      controller: _q,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: tr('Tìm theo tên, tài khoản, thẻ…'),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: Gap.md,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: Gap.sm),
            PopupMenuButton<SortBy>(
              tooltip: tr('Sắp xếp'),
              icon: Icon(Icons.sort, size: 20, color: colors.muted),
              initialValue: _c.sortBy,
              onSelected: _c.setSortBy,
              itemBuilder: (_) => [
                PopupMenuItem(value: SortBy.name, child: Text(tr('Tên A–Z'))),
                PopupMenuItem(
                  value: SortBy.updated,
                  child: Text(tr('Mới sửa')),
                ),
                PopupMenuItem(
                  value: SortBy.created,
                  child: Text(tr('Mới tạo')),
                ),
              ],
            ),
            const SizedBox(width: Gap.sm),
            _Segmented<GroupBy>(
              label: tr('Gom theo'),
              options: [
                (GroupBy.group, tr('Thẻ')),
                (GroupBy.type, tr('Loại')),
                (GroupBy.none, tr('Không gom')),
              ],
              value: _c.groupBy,
              onChanged: _c.setGroupBy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    Item item,
    DateTime now,
    bool codes, {
    (String, String)? labels,
  }) {
    final (title, subtitle) = labels ?? (item.title, item.subtitle);
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    String? code;
    if (codes) {
      try {
        code = Otp.code(item.totp!, now);
      } on Object {
        code = null; // khóa lỗi: bấm thì mở mục như thường
      }
    }
    final current = code;
    void actions() => showItemActions(
      context,
      _c,
      item,
      onOpen: codes ? () => _openDetail(item) : null,
    );
    return Material(
      color: _surfaces(context).side,
      borderRadius: BorderRadius.circular(Radii.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        // Mục 2FA: bấm là chép mã (giống tab 2FA trên điện thoại). Chuột phải hoặc nhấn giữ: thao tác nhanh.
        onTap: current != null
            ? () => copyText(context, current, what: tr('Đã chép mã 2FA'))
            : () => _openDetail(item),
        onLongPress: actions,
        onSecondaryTap: actions,
        // Đậm hơn hẳn nền thẻ, nếu không thì di chuột vào không thấy gì.
        hoverColor: colors.accent.withValues(alpha: 0.18),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          child: Row(
            children: [
              // Mục thường: logo bên trái. Mục 2FA: giống tab 2FA trên điện thoại, logo nhỏ phía trên mã.
              if (!codes) ...[
                // Chỉ logo, không nền, không viền (theo yêu cầu).
                Avatar.forItem(item, size: 32, plain: true),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  // Thẻ 2FA: tên nằm sát trên, nhỏ hơn; tài khoản nằm ngay dưới.
                  mainAxisAlignment: codes
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (codes) ...[
                          Avatar.forItem(
                            item,
                            size: 18,
                            plain: true,
                          ), // logo đứng trước tên dịch vụ
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (codes ? text.labelLarge : text.bodyMedium)
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (item.favorite)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: colors.warn,
                            ),
                          ),
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                  ],
                ),
              ),
              if (codes) ...[
                const SizedBox(width: Gap.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TotpRing(params: item.totp!, now: now, size: 18),
                    const SizedBox(height: 6),
                    TotpCode(
                      showRing: false,
                      params: item.totp!,
                      now: now,
                      onNext: item.totp!.isHotp
                          ? () => _c.hotpNext(item)
                          : null,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Thanh trên: tên app, trạng thái đồng bộ, nhắc nhở, xem nhanh 2FA, khóa.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});
  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final (syncLabel, dot) = switch (c.syncStatus) {
      SyncStatus.off => (tr('Chỉ trên máy này'), colors.muted),
      SyncStatus.syncing => (tr('Đang đồng bộ…'), colors.warn),
      SyncStatus.error => (tr('Lỗi đồng bộ'), colors.danger),
      SyncStatus.idle =>
        c.conflicts.isEmpty
            ? (tr('Đã đồng bộ'), colors.success)
            : (tr('Có xung đột'), colors.warn),
    };
    final compact = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: Gap.md),
      ),
      foregroundColor: WidgetStatePropertyAll(colors.muted),
      textStyle: WidgetStatePropertyAll(text.labelMedium),
    );
    return Container(
      height: 48,
      color: _surfaces(context).side,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const AppLogo(size: 22),
          const SizedBox(width: 10),
          Text(
            'VanKey',
            style: text.titleMedium?.copyWith(fontFamily: Fonts.head),
          ),
          const Spacer(),
          TextButton.icon(
            style: compact,
            icon: Icon(Icons.circle, size: 9, color: dot),
            label: Text(syncLabel),
            onPressed: () => pushPage(context, SyncScreen(controller: c)),
          ),
          Clock(
            builder: (context, now) {
              final n = pendingAlerts(
                c.data.items,
                now,
                snoozedUntil: c.snoozed,
              ).length;
              return IconButton(
                tooltip: tr('Nhắc nhở'),
                icon: Badge(
                  isLabelVisible: n > 0,
                  label: Text('$n'),
                  child: const Icon(Icons.notifications_none, size: 20),
                ),
                onPressed: () =>
                    pushPage(context, RemindersScreen(controller: c)),
              );
            },
          ),
          TextButton.icon(
            style: compact,
            icon: const Icon(Icons.bolt, size: 18),
            label: Text(tr('Xem nhanh 2FA')),
            onPressed: () => pushPage(context, QuickViewScreen(controller: c)),
          ),
          // Không đặt mật khẩu thì khóa cũng vô nghĩa (VaultController.lock bỏ qua).
          if (!c.noPassword)
            TextButton.icon(
              style: compact,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: Text(tr('Khóa ngay')),
              onPressed: c.lock,
            ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    this.icon,
    this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final IconData? icon;

  /// Logo thay cho icon (ví dụ logo chữ cái của thẻ).
  final Widget? leading;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final color = selected ? c.accent : c.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected
              ? c.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(Radii.sm),
            hoverColor: c.accent.withValues(alpha: 0.08),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  leading ?? Icon(icon, size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (count != null) Text('$count', style: text.labelSmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiêu đề nhóm trong lưới: mũi tên thu gọn, tên chữ hoa, số mục ở cuối dòng.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(
    this.label, {
    required this.count,
    required this.collapsed,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 16,
              color: c.muted,
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(letterSpacing: 0.9),
              ),
            ),
            Text('$count', style: text.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// Nhóm nút chọn một, kiểu gọn của prototype.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: label,
      child: Material(
        color: _surfaces(context).side,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (v, name) in options)
                Semantics(
                  selected: v == value,
                  button: true,
                  child: InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => onChanged(v),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: v == value
                            ? c.accent.withValues(alpha: 0.12)
                            : null,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: 7,
                      ),
                      child: Text(
                        name,
                        style: text.labelMedium?.copyWith(
                          color: v == value ? c.accent : c.muted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
