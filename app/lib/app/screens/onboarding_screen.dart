import 'package:material_ui/material_ui.dart';

import '../../core/security/password_strength.dart';
import '../constants.dart';
import '../google_drive_auth.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/ui.dart';
import 'cloudflare_screens.dart';
import '../widgets/common.dart';
import '../i18n.dart';

/// Các bước của màn đầu tiên.
enum _Step { choose, server, drive }

/// Lần đầu mở app: chọn nơi lưu (máy chủ VanKey, máy chủ tự dựng, hoặc chỉ trên máy này),
/// đăng nhập hoặc tạo tài khoản bằng tên đăng nhập và mật khẩu, rồi bắt xác nhận đã lưu mã khôi phục.
class OnboardingScreen extends StatefulWidget {
  /// [driveAvailable]: có hiện lựa chọn Google Drive không (mặc định: chỉ khi bản build đã có GOOGLE_SERVER_CLIENT_ID).
  /// [serverOnly]: chỉ đăng nhập / đăng ký trên máy chủ VanKey, không có màn chọn (mặc định: [Mvp.serverOnly]).
  OnboardingScreen({super.key, required this.controller, bool? driveAvailable, bool? serverOnly})
      : driveAvailable = driveAvailable ?? GoogleConfig.configured,
        serverOnly = serverOnly ?? Mvp.serverOnly;
  final VaultController controller;
  final bool driveAvailable;
  final bool serverOnly;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  late _Step _step = widget.serverOnly ? _Step.server : _Step.choose;
  bool _selfHost = false;
  bool _register = false;
  bool _show = false;
  bool _saved = false;
  String? _error;
  bool _vaultMismatch = false;
  bool? _driveHasVault; // null: chưa đăng nhập Google; true: Drive đã có kho (mở); false: chưa có (tạo)

  @override
  void dispose() {
    for (final t in [_url, _user, _pass, _confirm, _code]) {
      t.dispose();
    }
    super.dispose();
  }

  void _go(_Step step, {bool selfHost = false}) {
    widget.controller.error = null;
    setState(() {
      _step = step;
      _selfHost = selfHost;
      _register = false;
      _error = null;
      _vaultMismatch = false;
      _driveHasVault = null;
      for (final t in [_pass, _confirm, _code]) {
        t.clear();
      }
      if (selfHost && _url.text.isEmpty) _url.text = 'https://';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => CenteredPage(
        children: c.pendingRecovery != null
            ? _recoveryStep(c)
            : switch (_step) {
                _Step.choose => _chooseStep(c),
                _Step.server => _serverStep(c),
                _Step.drive => _driveStep(c),
              },
      ),
    );
  }

  // ---- Bước 1: chọn nơi lưu ----

  List<Widget> _chooseStep(VaultController c) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    Widget option(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
          margin: const EdgeInsets.only(bottom: Gap.md),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
            leading: IconBadge(icon, size: 44, color: colors.accent),
            title: Text(title, style: text.titleMedium),
            subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle)),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        );
    return [
      const Center(child: AppLogo()),
      const SizedBox(height: Gap.xl),
      Text(tr('VanKey'), textAlign: TextAlign.center, style: text.headlineLarge),
      const SizedBox(height: Gap.sm),
      Text(
        tr('Mật khẩu, khóa và mã 2FA của bạn, mã hóa trên máy. Máy chủ chỉ giữ bản đã mã hóa, không đọc được.'),
        textAlign: TextAlign.center,
        style: text.bodyLarge?.copyWith(color: colors.muted),
      ),
      const SizedBox(height: Gap.xxl),
      option(
        Icons.cloud_outlined,
        tr('Dùng máy chủ VanKey'),
        tr('Đăng nhập hoặc tạo tài khoản. Đồng bộ giữa các thiết bị.'),
        () => _go(_Step.server),
      ),
      option(
        Icons.dns_outlined,
        tr('Tự dựng máy chủ (self-host)'),
        tr('Dùng máy chủ Cloudflare của riêng bạn. Bạn nhập địa chỉ máy chủ.'),
        () => _go(_Step.server, selfHost: true),
      ),
      if (widget.driveAvailable)
        option(
          Icons.add_to_drive_outlined,
          tr('Dùng Google Drive của bạn'),
          tr('Không cần máy chủ. Dùng tài khoản Google để đồng bộ giữa các thiết bị.'),
          () => _go(_Step.drive),
        ),
    ];
  }

  // ---- Bước 2a: đăng nhập / tạo tài khoản trên máy chủ ----

  bool get _passLongEnough => _pass.text.length >= AccountPolicy.minPasswordLength;
  bool get _passMatch => _pass.text == _confirm.text && _confirm.text.isNotEmpty;

  bool _serverValid(VaultController c) {
    if (c.busy) return false;
    if (_selfHost && !VaultController.isAllowedServerUrl(_url.text)) return false;
    if (AccountPolicy.normalizeUsername(_user.text) == null) return false;
    if (_register) return _passLongEnough && _passMatch;
    return _pass.text.isNotEmpty;
  }

  Future<void> _submitServer(VaultController c) async {
    setState(() {
      _error = null;
      _vaultMismatch = false;
    });
    final url = _selfHost ? _url.text : ServerPolicy.defaultUrl;
    if (_register) {
      final err = await c.signUpWithServer(url: url, username: _user.text, password: _pass.text, registerCode: _code.text);
      if (mounted) setState(() => _error = err);
    } else {
      final r = await c.signInWithServer(url: url, username: _user.text, password: _pass.text);
      if (mounted) {
        setState(() {
          _error = r.error;
          _vaultMismatch = r.vaultMismatch;
        });
      }
    }
  }

  Widget _backButton() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: widget.controller.busy ? null : () => _go(_Step.choose),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: Text(tr('Quay lại')),
        ),
      );

  Widget _passwordField(TextEditingController ctl, String label, {String? errorText}) => TextField(
        controller: ctl,
        obscureText: !_show,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          suffixIcon: IconButton(
            tooltip: _show ? tr('Ẩn') : tr('Hiện'),
            icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
        onChanged: (_) => setState(() {}),
      );

  /// Ô mật khẩu mới kèm thanh độ mạnh và lời nhắc độ dài (dùng cho tạo tài khoản và tạo kho trên máy).
  /// Phần độ mạnh nằm trong MỘT widget cố định để các ô bên dưới không bị dựng lại (mất tiêu điểm) khi bắt đầu gõ.
  List<Widget> _newPasswordFields(String label) {
    final text = Theme.of(context).textTheme;
    return [
      _passwordField(_pass, label),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_pass.text.isNotEmpty) ...[
          StrengthMeter(PasswordStrength.estimate(_pass.text)),
          if (!_passLongEnough)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(tr('Cần ít nhất {p0} ký tự', {'p0': AccountPolicy.minPasswordLength}), style: text.bodySmall),
            ),
        ],
      ]),
      const SizedBox(height: Gap.md),
      _passwordField(_confirm, tr('Nhập lại mật khẩu'), errorText: _confirm.text.isNotEmpty && !_passMatch ? tr('Chưa khớp') : null),
    ];
  }

  List<Widget> _serverStep(VaultController c) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return [
      if (widget.serverOnly) ...[
        const Center(child: AppLogo()),
        const SizedBox(height: Gap.lg),
      ] else ...[
        _backButton(),
        const SizedBox(height: Gap.md),
      ],
      Text(_selfHost ? tr('Máy chủ của bạn') : (widget.serverOnly ? tr('VanKey') : tr('Máy chủ VanKey')), textAlign: TextAlign.center, style: text.headlineMedium),
      const SizedBox(height: Gap.sm),
      Text(
        _register
            ? tr('Một mật khẩu dùng cho cả tài khoản và kho. Nếu quên, chỉ mã khôi phục mở lại được kho.')
            : tr('Đăng nhập để tải kho của bạn về máy này.'),
        textAlign: TextAlign.center,
        style: text.bodyMedium?.copyWith(color: colors.muted),
      ),
      const SizedBox(height: Gap.xl),
      Center(
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(tr('Đăng nhập'))),
            ButtonSegment(value: true, label: Text(tr('Tạo tài khoản'))),
          ],
          selected: {_register},
          onSelectionChanged: c.busy
              ? null
              : (v) => setState(() {
                    _register = v.first;
                    _error = null;
                    _vaultMismatch = false;
                  }),
        ),
      ),
      const SizedBox(height: Gap.xl),
      if (_selfHost) ...[
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: tr('Địa chỉ máy chủ'), helperText: tr('Ví dụ: https://vankey.ten-ban.workers.dev')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Gap.md),
      ],
      TextField(
        controller: _user,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: tr('Tên đăng nhập'),
          helperText: _register ? tr('3 đến 32 ký tự: chữ thường, số, dấu chấm, gạch dưới hoặc gạch ngang') : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Gap.md),
      if (_register) ..._newPasswordFields(tr('Mật khẩu')) else _passwordField(_pass, tr('Mật khẩu')),
      if (_register && !widget.serverOnly) ...[
        const SizedBox(height: Gap.md),
        TextField(
          controller: _code,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: tr('Mã mời (nếu máy chủ yêu cầu)'), helperText: tr('Chủ máy chủ đặt mã này. Bỏ trống nếu không có.')),
          onChanged: (_) => setState(() {}),
        ),
      ],
      if (_error != null || c.error != null)
        Padding(padding: const EdgeInsets.only(top: Gap.md), child: Notice((_error ?? c.error)!, tone: NoticeTone.error, icon: Icons.error_outline)),
      if (_vaultMismatch)
        Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: OutlinedButton(
            onPressed: c.busy
                ? null
                : () => pushPage(
                      context,
                      CloudflareLoginScreen(controller: c, join: true, initialUrl: _selfHost ? _url.text : ServerPolicy.defaultUrl, initialUsername: _user.text),
                    ),
            child: Text(tr('Mở kho bằng mật khẩu kho hoặc mã khôi phục'), textAlign: TextAlign.center),
          ),
        ),
      const SizedBox(height: Gap.xl),
      FilledButton(
        onPressed: _serverValid(c) ? () => _submitServer(c) : null,
        child: c.busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Text(_register ? tr('Tạo tài khoản') : tr('Đăng nhập')),
      ),
    ];
  }

  // ---- Bước 2c: Google Drive (không cần máy chủ) ----

  Future<void> _driveSignIn(VaultController c) async {
    setState(() => _error = null);
    final r = await c.driveSignIn();
    if (!mounted) return;
    setState(() {
      _error = r.error;
      _driveHasVault = r.error == null ? r.hasVault : null;
    });
  }

  Future<void> _driveSubmit(VaultController c) async {
    setState(() => _error = null);
    final err = _driveHasVault == true ? await c.driveOpenVault(_pass.text) : await c.driveCreateVault(_pass.text);
    if (mounted) setState(() => _error = err);
  }

  List<Widget> _driveStep(VaultController c) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final hasVault = _driveHasVault;
    final canSubmit = !c.busy && (hasVault == true ? _pass.text.isNotEmpty : (_passLongEnough && _passMatch));
    return [
      _backButton(),
      const SizedBox(height: Gap.md),
      Text(tr('Google Drive'), textAlign: TextAlign.center, style: text.headlineMedium),
      const SizedBox(height: Gap.sm),
      Text(
        hasVault == null
            ? tr('Kho được lưu dạng đã mã hóa trong thư mục ẩn của app trên Google Drive của bạn. Google không đọc được nội dung.')
            : hasVault
                ? tr('Google Drive này đã có kho. Nhập mật khẩu của kho để mở.')
                : tr('Chưa có kho trên Google Drive này. Đặt mật khẩu để tạo kho mới. Nếu quên, chỉ mã khôi phục mở lại được kho.'),
        textAlign: TextAlign.center,
        style: text.bodyMedium?.copyWith(color: colors.muted),
      ),
      const SizedBox(height: Gap.xl),
      if (hasVault == null)
        FilledButton.icon(
          onPressed: c.busy ? null : () => _driveSignIn(c),
          icon: c.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.login),
          label: Text(tr('Đăng nhập Google')),
        )
      else ...[
        if (hasVault) _passwordField(_pass, tr('Mật khẩu kho')) else ..._newPasswordFields(tr('Mật khẩu kho')),
      ],
      if (_error != null || c.error != null)
        Padding(padding: const EdgeInsets.only(top: Gap.md), child: Notice((_error ?? c.error)!, tone: NoticeTone.error, icon: Icons.error_outline)),
      if (hasVault != null) ...[
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: canSubmit ? () => _driveSubmit(c) : null,
          child: c.busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(hasVault ? tr('Mở kho') : tr('Tạo kho')),
        ),
      ],
    ];
  }

  // ---- Bước 3: lưu mã khôi phục ----

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
          child: SelectableText(key, textAlign: TextAlign.center, style: text.titleLarge?.copyWith(fontFamily: Fonts.mono, letterSpacing: 2, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
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
