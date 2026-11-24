import 'package:material_ui/material_ui.dart';

import '../../core/security/password_strength.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/ui.dart';
import 'cloudflare_screens.dart';
import '../widgets/common.dart';
import '../i18n.dart';

/// Lần đầu mở app: đặt cụm mật khẩu cho kho, rồi bắt xác nhận đã lưu recovery key.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _saved = false;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => CenteredPage(children: c.pendingRecovery == null ? _passphraseStep(c) : _recoveryStep(c)),
    );
  }

  List<Widget> _passphraseStep(VaultController c) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final long = _pass.text.length >= 8;
    final match = _pass.text == _confirm.text && _confirm.text.isNotEmpty;
    final ok = long && match && !c.busy;
    return [
      const Center(child: AppLogo()),
      const SizedBox(height: Gap.xl),
      Text(tr('VanKey'), textAlign: TextAlign.center, style: text.headlineLarge),
      const SizedBox(height: Gap.sm),
      Text(
        tr('Đặt mật khẩu cho kho của bạn. Dữ liệu được mã hóa trên máy, chúng tôi không thể lấy lại mật khẩu này.'),
        textAlign: TextAlign.center,
        style: text.bodyLarge?.copyWith(color: colors.muted),
      ),
      const SizedBox(height: Gap.xxl),
      TextField(
        controller: _pass,
        obscureText: !_show,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: tr('Mật khẩu kho'),
          suffixIcon: IconButton(
            tooltip: _show ? tr('Ẩn') : tr('Hiện'),
            icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      if (_pass.text.isNotEmpty) ...[
        StrengthMeter(PasswordStrength.estimate(_pass.text)),
        if (!long) Padding(padding: const EdgeInsets.only(top: Gap.sm), child: Text(tr('Cần ít nhất 8 ký tự'), style: text.bodySmall)),
      ],
      const SizedBox(height: Gap.md),
      TextField(
        controller: _confirm,
        obscureText: !_show,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: tr('Nhập lại mật khẩu'), errorText: _confirm.text.isNotEmpty && !match ? tr('Chưa khớp') : null),
        onChanged: (_) => setState(() {}),
      ),
      if (c.error != null) Padding(padding: const EdgeInsets.only(top: Gap.md), child: Notice(c.error!, tone: NoticeTone.error, icon: Icons.error_outline)),
      const SizedBox(height: Gap.xl),
      FilledButton(
        onPressed: ok ? () => c.createVault(_pass.text) : null,
        child: c.busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(tr('Tạo kho')),
      ),
      const SizedBox(height: Gap.xl),
      Row(children: [
        const Expanded(child: Divider()),
        Padding(padding: const EdgeInsets.symmetric(horizontal: Gap.md), child: Text(tr('hoặc'), style: text.bodySmall)),
        const Expanded(child: Divider()),
      ]),
      const SizedBox(height: Gap.xl),
      OutlinedButton.icon(
        onPressed: c.busy ? null : c.createQuick,
        icon: const Icon(Icons.bolt_outlined),
        label: Text(tr('Dùng ngay, không cần mật khẩu')),
      ),
      const SizedBox(height: Gap.sm),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        child: Text(
          tr('Kho vẫn được mã hóa bằng khóa riêng của điện thoại. Bạn có thể đặt mật khẩu sau trong Cài đặt.'),
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
      ),
      const SizedBox(height: Gap.lg),
      TextButton(
        onPressed: c.busy ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CloudflareLoginScreen(controller: c, join: true))),
        child: Text(tr('Đã có tài khoản máy chủ? Đăng nhập để tải kho về'), textAlign: TextAlign.center),
      ),
    ];
  }

  List<Widget> _recoveryStep(VaultController c) {
    final key = c.pendingRecovery!;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return [
      Center(child: IconBadge(Icons.key_rounded, size: 64, color: colors.warn)),
      const SizedBox(height: Gap.xl),
      Text(tr('Lưu mã khôi phục'), textAlign: TextAlign.center, style: text.headlineMedium),
      const SizedBox(height: Gap.sm),
      Text(
        tr('Nếu quên mật khẩu, đây là cách DUY NHẤT mở lại kho. Mã chỉ hiện một lần. Hãy chép và cất ở nơi an toàn, ngoài chiếc điện thoại này.'),
        textAlign: TextAlign.center,
        style: text.bodyLarge?.copyWith(color: colors.muted),
      ),
      const SizedBox(height: Gap.xl),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xl),
        decoration: BoxDecoration(color: colors.field, borderRadius: BorderRadius.circular(Radii.lg)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SelectableText(key, textAlign: TextAlign.center, style: text.titleLarge?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ),
      const SizedBox(height: Gap.md),
      OutlinedButton.icon(
        onPressed: () => copyText(context, key, what: tr('Đã chép mã khôi phục (tự xóa clipboard sau 30 giây)')),
        icon: const Icon(Icons.copy_rounded),
        label: Text(tr('Chép mã')),
      ),
      const SizedBox(height: Gap.lg),
      Card(
        child: CheckboxListTile(
          value: _saved,
          onChanged: (v) => setState(() => _saved = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(tr('Tôi đã lưu mã khôi phục ở nơi an toàn'), style: text.bodyLarge),
        ),
      ),
      const SizedBox(height: Gap.lg),
      FilledButton(onPressed: _saved ? c.confirmRecoverySaved : null, child: Text(tr('Bắt đầu dùng'))),
    ];
  }
}
