import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/import_export/exporters.dart';
import '../constants.dart';
import '../i18n.dart';
import '../widgets/common.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../vault_controller.dart';
import 'duplicates_screen.dart';
import 'generator_screen.dart';
import 'health_screen.dart';
import 'import_screen.dart';
import 'info_screens.dart';
import 'qr_show_screen.dart';
import 'reminders_screen.dart';
import 'sync_screen.dart';
import 'theme_screen.dart';
import 'trash_screen.dart';

Future<void> loadDemoData(BuildContext context, VaultController controller) async {
  final ok = await confirmDialog(
    context,
    title: tr('Nạp dữ liệu mẫu?'),
    message: tr('Thêm khoảng 30 mục giả (đủ loại, logo, 2FA, nhắc nhở, thẻ) vào kho này để xem giao diện. Đừng nạp vào kho thật bạn đang dùng.'),
    confirmLabel: tr('Nạp'),
  );
  if (!ok || !context.mounted) return;
  final n = controller.addDemoData();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Đã thêm {p0} mục mẫu', {'p0': n}))));
}

Future<void> removeDemoData(BuildContext context, VaultController controller) async {
  final count = controller.demoItems.length;
  if (count == 0) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Không còn mục mẫu nào'))));
    return;
  }
  final ok = await confirmDialog(
    context,
    title: tr('Xóa dữ liệu mẫu?'),
    message: tr('Xóa hẳn {p0} mục mẫu (kể cả trên máy khác khi đồng bộ). Mục mẫu bạn đã sửa và mục của bạn được giữ nguyên.', {'p0': count}),
    confirmLabel: tr('Xóa'),
    danger: true,
  );
  if (!ok || !context.mounted) return;
  final n = controller.removeDemoData();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Đã xóa {p0} mục mẫu', {'p0': n}))));
}

/// Nút bánh răng (góc trên trái) mở trang Cài đặt.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.controller});
  final VaultController controller;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tr('Cài đặt'),
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.of(context).push(PageRouteBuilder<void>(
          // Trượt từ trái sang (bánh răng nằm ở góc trái); thoát thì trượt về bên trái.
          transitionDuration: Timing.pageIn,
          reverseTransitionDuration: Timing.pageOut,
          pageBuilder: (_, _, _) => SettingsScreen(controller: controller),
          transitionsBuilder: (_, anim, _, child) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
            child: child,
          ),
        )),
      );
}

/// Trang Cài đặt (mở từ bánh răng).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(tr('Cài đặt'))), body: SettingsTab(controller: controller));
}

/// Cài đặt gom thành 7 menu: Tài khoản, Dữ liệu, Bảo mật, Chủ đề, Chung, Hỗ trợ, Giới thiệu.
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, required this.controller});
  final VaultController controller;

  /// Nhãn của một mức tự khóa (giây). Các mức nằm ở [LockPolicy.autoLockChoices].
  static String _lockLabel(int seconds) => switch (seconds) {
        LockPolicy.never => tr('Không tự khóa'),
        0 => tr('Ngay khi thoát app'),
        < 60 => tr('Sau {p0} giây', {'p0': seconds}),
        60 => tr('Sau 1 phút'),
        _ => tr('Sau {p0} phút', {'p0': seconds ~/ 60}),
      };

  static List<(int, String)> get _lockChoices => [for (final s in LockPolicy.autoLockChoices) (s, _lockLabel(s))];

  /// Trang con: dựng lại mỗi khi trạng thái đổi.
  void _sub(BuildContext context, String title, List<Widget> Function(BuildContext) children) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ListenableBuilder(
        listenable: controller,
        builder: (ctx, _) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl), children: [CardList(children: children(ctx))]),
        ),
      ),
    ));
  }

  // ---------- Hộp thoại ----------

  Future<void> _pickLanguage(BuildContext context) async {
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Ngôn ngữ')),
        children: [
          for (final c in [('system', tr('Hệ thống')), ('vi', 'Tiếng Việt'), ('en', 'English')])
            ListTile(title: Text(c.$2), trailing: controller.language == c.$1 ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(ctx, c.$1)),
        ],
      ),
    );
    if (v != null) await controller.setLanguage(v);
  }

  Future<void> _pickLock(BuildContext context) async {
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Tự khóa')),
        children: [
          for (final c in _lockChoices)
            ListTile(title: Text(c.$2), trailing: controller.lockAfterSeconds == c.$1 ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(ctx, c.$1)),
        ],
      ),
    );
    if (v == null || !context.mounted) return;
    if (v == LockPolicy.never && controller.lockAfterSeconds != LockPolicy.never) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text(tr('Tắt tự khóa?')),
          content: Text(tr(
              'Khóa mở kho sẽ được cất trên máy này để mở app là vào thẳng, không hỏi mật khẩu. Ai cầm được điện thoại đang mở khóa màn hình là xem được toàn bộ mật khẩu và mã 2FA của bạn. Chỉ nên chọn nếu điện thoại luôn có khóa màn hình và không ai khác dùng.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Giữ tự khóa'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Vẫn tắt'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    await controller.setLockAfter(v);
  }

  Future<String?> _askPassword(BuildContext context, String title, {String? hint}) async {
    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (hint != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(hint)),
          TextField(controller: ctrl, obscureText: true, autofocus: true, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: tr('Mật khẩu kho'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('Tiếp tục'))),
        ],
      ),
    );
    // Không dispose ngay: hộp thoại còn đang chạy hiệu ứng đóng và vẫn dùng controller này.
    return (pw == null || pw.isEmpty) ? null : pw;
  }

  Future<void> _enableBio(BuildContext context) async {
    final pw = await _askPassword(context, tr('Nhập mật khẩu để bật vân tay'));
    if (pw == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final err = await controller.enableBiometric(pw);
    messenger.showSnackBar(SnackBar(content: Text(err ?? tr('Đã bật mở khóa bằng vân tay'))));
  }

  Future<void> _setPassword(BuildContext context) async {
    final pw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _NewPasswordDialog()));
    if (pw == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await controller.setPassword(pw);
    messenger.showSnackBar(SnackBar(content: Text(tr('Đã đặt mật khẩu. Từ giờ app sẽ hỏi mật khẩu khi mở.'))));
  }

  Future<void> _changePassword(BuildContext context) async {
    final r = await Navigator.of(context).push<(String, String)>(MaterialPageRoute(builder: (_) => const _ChangePasswordDialog()));
    if (r == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final err = await controller.changeVaultPassword(r.$1, r.$2);
    messenger.showSnackBar(SnackBar(content: Text(err ?? tr('Đã đổi mật khẩu'))));
  }

  Future<void> _recovery(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Tạo mã khôi phục mới?')),
        content: Text(tr('Mã cũ (nếu có) sẽ không dùng được nữa. Mã mới chỉ hiện một lần.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Tạo'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final key = await controller.newRecoveryKey();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Mã khôi phục')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Cất ở nơi an toàn, ngoài chiếc điện thoại này. Đây là cách duy nhất mở lại kho khi quên mật khẩu hoặc mất máy.')),
          const SizedBox(height: 12),
          SelectableText(key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: Fonts.mono)),
        ]),
        actions: [
          TextButton(onPressed: () => copyText(ctx, key, what: tr('Đã chép mã khôi phục')), child: Text(tr('Chép'))),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Tôi đã lưu'))),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, String name, Uint8List bytes, String mime) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = await controller.external(() => FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime));
      messenger.showSnackBar(SnackBar(content: Text(uri == null ? tr('Đã hủy') : tr('Đã lưu {p0}', {'p0': name}))));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr('Không lưu được: {p0}', {'p0': e}))));
    }
  }

  Future<void> _export(BuildContext context) async {
    final groups = controller.data.items.where((i) => !i.inTrash && i.group.isNotEmpty).map((i) => i.group).toSet().toList()..sort();
    final choice = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(tr('Sao lưu mã hóa (.vkv)')),
              subtitle: Text(controller.noPassword ? tr('Chỉ mở lại được bằng mã khôi phục: hãy tạo mã trước.') : tr('An toàn. Chỉ VanKey mở được, cần mật khẩu hoặc mã khôi phục.')),
              onTap: () => Navigator.pop(ctx, 0),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: Text(tr('Mã QR cho Google Authenticator')),
              subtitle: Text(tr('Hiện lần lượt các mã QR để nhập sang app khác.')),
              onTap: () => Navigator.pop(ctx, 3),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              title: Text(tr('Xuất CSV không mã hóa')),
              subtitle: Text(tr('Chứa mật khẩu và khóa 2FA dạng chữ thường.')),
              onTap: () => Navigator.pop(ctx, 1),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              title: Text(tr('Xuất danh sách link 2FA không mã hóa')),
              subtitle: Text(tr('Để chuyển sang app 2FA khác.')),
              onTap: () => Navigator.pop(ctx, 2),
            ),
          ]),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 0) {
      final bytes = await controller.backupBytes();
      if (context.mounted) await _save(context, Storage.backupFileName, bytes, Storage.backupMime);
      return;
    }

    if (choice == 3) {
      final items = controller.data.items.where((i) => !i.inTrash).toList();
      unawaited(pushPage(context, QrShowScreen.forGoogleAuthenticator(items)));
      return;
    }

    // Phạm vi: toàn bộ hoặc một nhóm.
    String? scope;
    if (groups.isNotEmpty && context.mounted) {
      scope = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(tr('Xuất phạm vi nào?')),
          children: [
            ListTile(title: Text(tr('Toàn bộ kho')), onTap: () => Navigator.pop(ctx, '')),
            for (final g in groups) ListTile(title: Text(tr('Thẻ: {p0}', {'p0': g})), onTap: () => Navigator.pop(ctx, g)),
          ],
        ),
      );
      if (scope == null) return;
    }
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xuất không mã hóa?')),
        content: Text(tr('File sẽ chứa bí mật của bạn ở dạng đọc được. Hãy xóa file ngay sau khi dùng xong và không gửi qua kênh không an toàn.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Vẫn xuất'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final items = [for (final i in controller.data.items) if (scope == null || scope.isEmpty || i.group == scope) i];
    if (choice == 1) {
      await _save(context, 'vankey-export.csv', Uint8List.fromList(utf8.encode(Exporters.csv(items))), 'text/csv');
    } else {
      await _save(context, 'vankey-2fa.txt', Uint8List.fromList(utf8.encode(Exporters.otpauthLines(items))), 'text/plain');
    }
  }

  // ---------- Các trang con ----------

  Future<void> _account(BuildContext context) async {
    // Không để màn chờ mãi nếu hệ thống không trả lời về vân tay.
    final bio = !controller.noPassword && await controller.biometricAvailable().timeout(Timing.biometricProbe, onTimeout: () => false);
    if (!context.mounted) return;
    _sub(context, tr('Tài khoản'), (ctx) => [
        ListTile(
          leading: Icon(controller.cfSession != null ? Icons.cloud_done_outlined : Icons.phone_android),
          title: Text(controller.cfSession != null ? controller.cfSession!.username : tr('Chỉ lưu trên máy này')),
          subtitle: Text(controller.syncLabel),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => pushPage(ctx, SyncScreen(controller: controller)),
        ),
        if (controller.noPassword)
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(tr('Đặt mật khẩu')),
            subtitle: Text(tr('Hiện app mở thẳng, không hỏi gì. Đặt mật khẩu để bảo vệ kho.')),
            onTap: () => _setPassword(ctx),
          )
        else ...[
          ListTile(leading: const Icon(Icons.password), title: Text(tr('Đổi mật khẩu kho')), onTap: () => _changePassword(ctx)),
          if (bio)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: Text(tr('Mở khóa bằng vân tay')),
              subtitle: Text(tr('Vẫn dùng được mật khẩu khi vân tay không nhận')),
              value: controller.biometricEnabled,
              onChanged: (v) => v ? _enableBio(ctx) : controller.disableBiometric(),
            ),
        ],
        ListTile(
          leading: const Icon(Icons.key),
          title: Text(tr('Mã khôi phục')),
          subtitle: Text(tr('Tạo mã mới (mã cũ sẽ hết hiệu lực)')),
          onTap: () => _recovery(ctx),
        ),
      ]);
  }

  Future<void> _demo(BuildContext context) => loadDemoData(context, controller);

  void _data(BuildContext context) => _sub(context, tr('Dữ liệu'), (ctx) {
        final trashed = controller.data.items.where((i) => i.inTrash).length;
        return [
          ListTile(leading: const Icon(Icons.sync), title: Text(tr('Đồng bộ')), subtitle: Text(controller.syncLabel), onTap: () => pushPage(ctx, SyncScreen(controller: controller))),
          ListTile(leading: const Icon(Icons.file_download_outlined), title: Text(tr('Nhập dữ liệu')), onTap: () => pushPage(ctx, ImportScreen(controller: controller))),
          ListTile(leading: const Icon(Icons.file_upload_outlined), title: Text(tr('Xuất và sao lưu')), onTap: () => _export(ctx)),
          ListTile(leading: const Icon(Icons.science_outlined), title: Text(tr('Nạp dữ liệu mẫu')), subtitle: Text(tr('Thêm các mục giả để xem giao diện')), onTap: () => _demo(ctx)),
          ListTile(leading: const Icon(Icons.layers_clear_outlined), title: Text(tr('Xóa dữ liệu mẫu')), subtitle: Text(tr('Chỉ xóa các mục giả đã nạp, không đụng mục của bạn')), onTap: () => removeDemoData(ctx, controller)),
          ListTile(leading: const Icon(Icons.content_copy), title: Text(tr('Mục trùng lặp')), onTap: () => pushPage(ctx, DuplicatesScreen(controller: controller))),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('Thùng rác')),
            subtitle: Text(tr('Tự xóa vĩnh viễn sau 30 ngày')),
            trailing: trashed > 0 ? Text('$trashed') : null,
            onTap: () => pushPage(ctx, TrashScreen(controller: controller)),
          ),
        ];
      });

  void _security(BuildContext context) => _sub(context, tr('Bảo mật'), (ctx) {
        final lockLabel = _lockChoices.firstWhere((c) => c.$1 == controller.lockAfterSeconds, orElse: () => (controller.lockAfterSeconds, tr('{p0} giây', {'p0': controller.lockAfterSeconds}))).$2;
        return [
          if (!controller.noPassword) ...[
            ListTile(leading: const Icon(Icons.lock_clock), title: Text(tr('Khóa ngay')), onTap: () {
              Navigator.of(ctx).popUntil((r) => r.isFirst);
              controller.lock();
            }),
            ListTile(leading: const Icon(Icons.timer_outlined), title: Text(tr('Tự khóa')), subtitle: Text(lockLabel), onTap: () => _pickLock(ctx)),
            if (controller.lockAfterSeconds == LockPolicy.never)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
                child: Notice(tr('Đang không tự khóa: ai cầm điện thoại đang mở là vào được kho. Nên chọn một mức tự khóa, nhất là khi đã bật mở bằng vân tay.'), tone: NoticeTone.warn, icon: Icons.warning_amber_rounded),
              ),
          ],
          if (Platform.isAndroid)
            SwitchListTile(
              secondary: const Icon(Icons.screenshot_monitor),
              title: Text(tr('Chặn chụp màn hình')),
              subtitle: Text(tr('Cũng che nội dung khi xem danh sách ứng dụng gần đây')),
              value: controller.blockScreenshots,
              onChanged: controller.setBlockScreenshots,
            ),
          ListTile(leading: const Icon(Icons.health_and_safety_outlined), title: Text(tr('Kiểm tra bảo mật')), onTap: () => pushPage(ctx, HealthScreen(controller: controller))),
          ListTile(leading: const Icon(Icons.notifications_none), title: Text(tr('Nhắc nhở')), onTap: () => pushPage(ctx, RemindersScreen(controller: controller))),
        ];
      });

  void _general(BuildContext context) => _sub(context, tr('Chung'), (ctx) => [
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(tr('Ngôn ngữ')),
          subtitle: Text(controller.language == 'vi' ? 'Tiếng Việt' : (controller.language == 'en' ? 'English' : tr('Hệ thống'))),
          onTap: () => _pickLanguage(ctx),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.apps_rounded),
          title: Text(tr('Hiện logo dịch vụ')),
          subtitle: Text(tr('Facebook, Google, GitHub... hiện logo thay cho chữ cái đầu')),
          value: controller.showLogos,
          onChanged: controller.setShowLogos,
        ),
        ListTile(leading: const Icon(Icons.password), title: Text(tr('Tạo mật khẩu')), onTap: () => pushPage(ctx, const GeneratorScreen())),
      ]);

  @override
  Widget build(BuildContext context) {
    final menu = <(IconData, String, String, VoidCallback)>[
      (Icons.person_outline, tr('Tài khoản'), controller.noPassword ? tr('Không mật khẩu') : tr('Có mật khẩu'), () => _account(context)),
      (Icons.storage_outlined, tr('Dữ liệu'), tr('Đồng bộ, nhập, xuất, thùng rác'), () => _data(context)),
      (Icons.shield_outlined, tr('Bảo mật'), tr('Tự khóa, kiểm tra, nhắc nhở'), () => _security(context)),
      (Icons.palette_outlined, tr('Chủ đề'), tr('Sáng, tối, màu nhấn'), () => pushPage(context, ThemeScreen(controller: controller))),
      (Icons.tune, tr('Chung'), tr('Ngôn ngữ, logo, tạo mật khẩu'), () => _general(context)),
      (Icons.help_outline, tr('Hỗ trợ'), tr('Câu hỏi thường gặp'), () => pushPage(context, const HelpScreen())),
      (Icons.info_outline, tr('Giới thiệu'), tr('Phiên bản {p0}', {'p0': appVersion}), () => pushPage(context, const AboutScreen())),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl), children: [
      CardList(children: [
        for (final m in menu)
          ListTile(
            leading: IconBadge(m.$1),
            title: Text(m.$2),
            subtitle: Text(m.$3),
            trailing: const Icon(Icons.chevron_right_rounded),
            minVerticalPadding: Gap.md,
            onTap: m.$4,
          ),
      ]),
    ]);
  }
}

class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog();

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _a.text.length >= AccountPolicy.minPasswordLength && _a.text == _b.text;
    return _PasswordPage(
      title: tr('Đặt mật khẩu'),
      note: tr('Từ giờ app sẽ hỏi mật khẩu này mỗi khi mở. Hãy nhớ kỹ: quên mật khẩu thì chỉ mở lại được bằng mã khôi phục.'),
      confirmLabel: tr('Đặt'),
      onConfirm: ok ? () => Navigator.pop(context, _a.text) : null,
      children: [
        _pwField(_a, tr('Mật khẩu (từ {p0} ký tự)', {'p0': AccountPolicy.minPasswordLength}), () => setState(() {})),
        _pwField(_b, tr('Nhập lại'), () => setState(() {})),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _cur = TextEditingController();
  final _a = TextEditingController();
  final _b = TextEditingController();

  @override
  void dispose() {
    _cur.dispose();
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController c, String label) =>
      _pwField(c, label, () => setState(() {}));

  @override
  Widget build(BuildContext context) {
    final ok = _cur.text.isNotEmpty && _a.text.length >= AccountPolicy.minPasswordLength && _a.text == _b.text;
    return _PasswordPage(
      title: tr('Đổi mật khẩu kho'),
      confirmLabel: tr('Đổi'),
      onConfirm: ok ? () => Navigator.pop(context, (_cur.text, _a.text)) : null,
      children: [
        _field(_cur, tr('Mật khẩu hiện tại')),
        _field(_a, tr('Mật khẩu mới (từ {p0} ký tự)', {'p0': AccountPolicy.minPasswordLength})),
        _field(_b, tr('Nhập lại mật khẩu mới')),
      ],
    );
  }
}

Widget _pwField(TextEditingController c, String label, VoidCallback onChanged) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: TextField(controller: c, obscureText: true, autocorrect: false, enableSuggestions: false, onChanged: (_) => onChanged(), decoration: InputDecoration(labelText: label)),
    );

/// Trang riêng cho việc đặt/đổi mật khẩu: các ô nhập ở trên, nút xác nhận dính đáy.
class _PasswordPage extends StatelessWidget {
  const _PasswordPage({required this.title, required this.children, required this.confirmLabel, required this.onConfirm, this.note});
  final String title;
  final String? note;
  final List<Widget> children;
  final String confirmLabel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(Gap.lg), children: [
        if (note != null) Padding(padding: const EdgeInsets.only(bottom: Gap.xl), child: Text(note!, style: TextStyle(color: colors.muted))),
        ...children,
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy')))),
            const SizedBox(width: Gap.md),
            Expanded(flex: 2, child: FilledButton(onPressed: onConfirm, child: Text(confirmLabel))),
          ]),
        ),
      ),
    );
  }
}
