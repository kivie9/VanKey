import 'package:material_ui/material_ui.dart';

import '../constants.dart';
import '../../core/sync/cloudflare_sync.dart';
import '../i18n.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/ui.dart';

/// Đăng nhập / đăng ký tài khoản máy chủ Cloudflare cho kho đang có trên máy (bật đồng bộ từ Cài đặt).
/// [join] = mở kho bằng mật khẩu kho hoặc mã khôi phục riêng, dùng khi mật khẩu tài khoản không mở được kho.
class CloudflareLoginScreen extends StatefulWidget {
  const CloudflareLoginScreen({
    super.key,
    required this.controller,
    this.join = false,
    this.initialUrl,
    this.initialUsername,
  });
  final VaultController controller;
  final bool join;
  final String? initialUrl;
  final String? initialUsername;

  @override
  State<CloudflareLoginScreen> createState() => _CloudflareLoginScreenState();
}

class _CloudflareLoginScreenState extends State<CloudflareLoginScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _vault = TextEditingController();
  final _registerCode = TextEditingController();
  bool _register = false;
  bool _useRecovery = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url.text = widget.initialUrl ?? ServerPolicy.defaultUrl;
    _user.text = widget.initialUsername ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    _vault.dispose();
    _registerCode.dispose();
    super.dispose();
  }

  bool get _valid =>
      VaultController.isAllowedServerUrl(_url.text) &&
      AccountPolicy.normalizeUsername(_user.text) != null &&
      (_register && !widget.join
          ? AccountPolicy.checkNewPassword(_password.text) == null
          : _password.text.isNotEmpty) &&
      (!widget.join || _vault.text.isNotEmpty);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final c = widget.controller;
    final String? err;
    if (widget.join) {
      err = await c.joinFromCloud(
        url: _url.text,
        username: _user.text,
        accountPassword: _password.text,
        vaultPassphrase: _useRecovery ? null : _vault.text,
        recoveryKey: _useRecovery ? _vault.text : null,
      );
    } else {
      err = await c.signInCloudflare(
        url: _url.text,
        username: _user.text,
        password: _password.text,
        register: _register,
        registerCode: _registerCode.text,
      );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null && !widget.join) Navigator.of(context).pop();
    // Với join: controller đã chuyển sang màn chính, màn này tự bị thay thế.
    if (err == null && widget.join && Navigator.of(context).canPop())
      Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool secret = false,
    TextInputType? type,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: type,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, helperText: helper),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.join
            ? tr('Đăng nhập tài khoản có sẵn')
            : (_register
                  ? tr('Tạo tài khoản máy chủ')
                  : tr('Đăng nhập máy chủ')),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Notice(
          widget.join
              ? tr(
                  'Đăng nhập bằng mật khẩu tài khoản, rồi nhập mật khẩu hoặc mã khôi phục của kho để mở kho đã đồng bộ.',
                )
              : tr(
                  'Máy chủ chỉ giữ bản đã mã hóa của kho. Nên dùng cùng mật khẩu với mật khẩu kho để máy khác đăng nhập là mở được kho.',
                ),
          icon: Icons.cloud_outlined,
        ),
        const SizedBox(height: Gap.lg),
        _field(
          _url,
          tr('Địa chỉ máy chủ'),
          type: TextInputType.url,
          helper: tr('Ví dụ: https://vankey.ten-ban.workers.dev'),
        ),
        _field(_user, tr('Tên đăng nhập')),
        _field(
          _password,
          _register && !widget.join
              ? tr('Mật khẩu tài khoản (từ {p0} ký tự)', {
                  'p0': AccountPolicy.minPasswordLength,
                })
              : tr('Mật khẩu tài khoản'),
          secret: true,
        ),
        if (_register && !widget.join)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NewPasswordHint(_password.text),
          ),
        if (widget.join) ...[
          _field(
            _vault,
            _useRecovery ? tr('Mã khôi phục của kho') : tr('Mật khẩu của kho'),
            secret: !_useRecovery,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _useRecovery = !_useRecovery;
                _vault.clear();
              }),
              child: Text(
                _useRecovery
                    ? tr('Dùng mật khẩu kho')
                    : tr('Dùng mã khôi phục'),
              ),
            ),
          ),
        ] else
          SectionCard(
            children: [
              SwitchListTile(
                title: Text(tr('Tạo tài khoản mới')),
                subtitle: Text(
                  tr('Bật nếu bạn chưa có tài khoản trên máy chủ này'),
                ),
                value: _register,
                onChanged: (v) => setState(() => _register = v),
              ),
            ],
          ),
        if (!widget.join && _register) ...[
          const SizedBox(height: Gap.lg),
          _field(
            _registerCode,
            tr('Mã mời (nếu máy chủ yêu cầu)'),
            secret: true,
            helper: tr('Chủ máy chủ đặt mã này. Bỏ trống nếu không có.'),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: Notice(
              _error!,
              tone: NoticeTone.error,
              icon: Icons.error_outline,
            ),
          ),
        const SizedBox(height: Gap.xl),
        FilledButton(
          onPressed: _valid && !_busy ? _submit : null,
          child: Padding(
            padding: EdgeInsets.zero,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(
                    widget.join
                        ? tr('Tải kho về')
                        : (_register ? tr('Tạo tài khoản') : tr('Đăng nhập')),
                  ),
          ),
        ),
      ],
    ),
  );
}

/// Thiết bị đã đăng nhập vào tài khoản; gỡ từ xa một thiết bị bị mất.
class CloudflareDevicesScreen extends StatefulWidget {
  const CloudflareDevicesScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<CloudflareDevicesScreen> createState() =>
      _CloudflareDevicesScreenState();
}

class _CloudflareDevicesScreenState extends State<CloudflareDevicesScreen> {
  late Future<List<CloudflareDevice>> _future = widget.controller
      .cloudflareDevices();

  Future<void> _revoke(CloudflareDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Gỡ thiết bị "{p0}"?', {'p0': d.name})),
        content: Text(
          tr(
            'Thiết bị này sẽ mất quyền truy cập ngay. Nếu nghi bị lộ, hãy đổi mật khẩu kho sau đó.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Gỡ')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.revokeCloudflareDevice(d.id);
      if (mounted)
        setState(() => _future = widget.controller.cloudflareDevices());
    } on Object catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Không gỡ được: {p0}', {'p0': e}))),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Thiết bị đã đăng nhập'))),
    body: FutureBuilder<List<CloudflareDevice>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snap.hasError)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('Không tải được danh sách thiết bị.')),
            ),
          );
        final list = snap.data!;
        return ListView(
          children: [
            for (final d in list)
              ListTile(
                leading: Icon(
                  d.current ? Icons.smartphone : Icons.devices_other,
                ),
                title: Text(
                  d.current ? tr('{p0} (máy này)', {'p0': d.name}) : d.name,
                ),
                subtitle: Text(
                  tr('Hoạt động lần cuối: {p0}', {
                    'p0': d.lastSeen.toLocal().toString().split('.').first,
                  }),
                ),
                trailing: d.current
                    ? null
                    : IconButton(
                        tooltip: tr('Gỡ thiết bị'),
                        icon: const Icon(Icons.link_off),
                        onPressed: () => _revoke(d),
                      ),
              ),
          ],
        );
      },
    ),
  );
}
