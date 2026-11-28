import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/ui.dart';
import '../i18n.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _text = TextEditingController();
  bool _show = false;
  bool _recovery = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.controller.unlockWithBiometric());
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = widget.controller;
    if (_text.text.isEmpty || c.busy) return;
    final ok = _recovery ? await c.unlockWithRecovery(_text.text) : await c.unlockWithPassphrase(_text.text);
    if (ok) _text.clear();
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa toàn bộ kho?')),
        content: Text(tr('Mọi mật khẩu, mã 2FA và ghi chú trong kho này sẽ mất vĩnh viễn, không khôi phục được. Chỉ làm khi bạn chắc chắn không cần dữ liệu đó.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xóa hết'))),
        ],
      ),
    );
    if (ok == true) await widget.controller.resetVault();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => CenteredPage(maxWidth: 420, children: [
        const Center(child: AppLogo()),
        const SizedBox(height: Gap.xl),
        Text(tr('VanKey'), textAlign: TextAlign.center, style: text.headlineLarge),
        const SizedBox(height: Gap.xxl),
        TextField(
          controller: _text,
          autofocus: true,
          obscureText: !_show && !_recovery,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: _recovery ? TextCapitalization.characters : TextCapitalization.none,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: _recovery ? tr('Mã khôi phục') : tr('Mật khẩu kho'),
            suffixIcon: _recovery
                ? null
                : IconButton(
                    tooltip: _show ? tr('Ẩn') : tr('Hiện'),
                    icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _show = !_show),
                  ),
          ),
        ),
        if (c.error != null) Padding(padding: const EdgeInsets.only(top: Gap.md), child: Notice(c.error!, tone: NoticeTone.error, icon: Icons.error_outline)),
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: c.busy ? null : _submit,
          child: c.busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(tr('Mở khóa')),
        ),
        if (c.bioNeedsReenable && !c.biometricEnabled)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: Notice(tr('Mở khóa bằng {p0} đã được nâng cấp để an toàn hơn. Sau khi mở bằng mật khẩu, hãy bật lại trong Cài đặt > Tài khoản.', {'p0': VaultController.bioName}), tone: NoticeTone.info, icon: Icons.fingerprint),
          ),
        if (c.biometricEnabled) ...[
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(onPressed: c.busy ? null : c.unlockWithBiometric, icon: const Icon(Icons.fingerprint), label: Text(tr('Mở bằng {p0}', {'p0': VaultController.bioName}))),
        ],
        const SizedBox(height: Gap.lg),
        TextButton(
          onPressed: c.busy
              ? null
              : () => setState(() {
                    _recovery = !_recovery;
                    _text.clear();
                    c.error = null;
                  }),
          child: Text(_recovery ? tr('Dùng mật khẩu') : tr('Quên mật khẩu? Dùng mã khôi phục')),
        ),
        TextButton(
          onPressed: c.busy ? null : () => _reset(context),
          style: TextButton.styleFrom(foregroundColor: colors.danger),
          child: Text(tr('Xóa kho và bắt đầu lại')),
        ),
      ]),
    );
  }
}
