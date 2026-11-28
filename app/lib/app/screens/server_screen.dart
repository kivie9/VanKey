import 'package:material_ui/material_ui.dart';

import '../constants.dart';
import '../i18n.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/form_layout.dart';
import '../widgets/ui.dart';

/// Cấu hình máy chủ đồng bộ: máy chủ VanKey hoặc máy chủ tự dựng (self-host).
/// Mở từ màn đăng nhập và từ Cài đặt > Tài khoản. Đang đăng nhập thì chỉ xem:
/// đổi máy chủ phải đăng xuất trước, vì phiên và kho đang gắn với máy chủ hiện tại.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late bool _selfHost = widget.controller.isSelfHost;
  late final _url = TextEditingController(text: widget.controller.customServerUrl ?? 'https://');
  late final _code = TextEditingController(text: widget.controller.serverInviteCode);
  bool _showCode = false;
  bool _saving = false;

  @override
  void dispose() {
    _url.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _valid => !_saving && (!_selfHost || VaultController.isAllowedServerUrl(_url.text));

  /// Đã gõ gì đó ngoài "https://" mà địa chỉ vẫn không dùng được.
  String? get _urlError {
    final t = _url.text.trim();
    if (t.isEmpty || t == 'https://' || VaultController.isAllowedServerUrl(t)) return null;
    return tr('Địa chỉ máy chủ phải bắt đầu bằng https://');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.controller.setServer(
      selfHostUrl: _selfHost ? _url.text : null,
      inviteCode: _selfHost ? _code.text : '',
    );
    if (mounted) Navigator.of(context).pop();
  }

  Widget _option({required bool selfHost, required String title, required String subtitle}) {
    final selected = _selfHost == selfHost;
    final colors = AppColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Gap.md),
      child: ListTile(
        selected: selected,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? colors.accent : colors.muted,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: () => setState(() => _selfHost = selfHost),
      ),
    );
  }

  List<Widget> _editor() => [
    _option(
      selfHost: false,
      title: ServerPolicy.officialName,
      subtitle: tr('Máy chủ VanKey. Không cần cấu hình gì thêm.'),
    ),
    _option(
      selfHost: true,
      title: tr('Tự dựng máy chủ (self-host)'),
      subtitle: tr('Dùng máy chủ Cloudflare của riêng bạn. Bạn nhập địa chỉ máy chủ.'),
    ),
    if (_selfHost) ...[
      const SizedBox(height: Gap.sm),
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: tr('Địa chỉ máy chủ'),
          helperText: tr('Ví dụ: https://vankey.ten-ban.workers.dev'),
          helperMaxLines: 2,
          errorText: _urlError,
          errorMaxLines: 2,
        ),
      ),
      const SizedBox(height: Gap.md),
      TextField(
        controller: _code,
        obscureText: !_showCode,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: tr('Mã mời (nếu máy chủ yêu cầu)'),
          helperText: tr('Chỉ dùng khi tạo tài khoản. Bỏ trống nếu không có.'),
          helperMaxLines: 2,
          suffixIcon: IconButton(
            tooltip: _showCode ? tr('Ẩn') : tr('Hiện'),
            icon: Icon(_showCode ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _showCode = !_showCode),
          ),
        ),
      ),
    ],
    const SizedBox(height: Gap.xl),
    FilledButton(onPressed: _valid ? _save : null, child: Text(tr('Lưu'))),
  ];

  List<Widget> _readOnly() {
    final c = widget.controller;
    return [
      SectionCard(
        children: [
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(tr('Loại máy chủ')),
            subtitle: Text(c.isSelfHost ? tr('Tự dựng máy chủ (self-host)') : ServerPolicy.officialName),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(tr('Địa chỉ máy chủ')),
            subtitle: SelectableText(c.serverUrl),
          ),
        ],
      ),
      const SizedBox(height: Gap.lg),
      Notice(tr('Đang đăng nhập máy chủ này. Muốn đổi máy chủ thì đăng xuất trước.'), icon: Icons.info_outline),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Máy chủ'))),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => ListView(
        padding: formPadding(MediaQuery.sizeOf(context).width),
        children: widget.controller.signedInToServer ? _readOnly() : _editor(),
      ),
    ),
  );
}
