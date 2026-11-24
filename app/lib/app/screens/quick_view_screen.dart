import 'package:material_ui/material_ui.dart';

import '../../core/totp/otpauth.dart';
import '../../core/totp/totp.dart';
import '../../core/vault/models.dart';
import '../vault_controller.dart';
import '../widgets/common.dart';
import 'item_editor_screen.dart';
import '../i18n.dart';

/// Xem nhanh mã 2FA từ một khóa, không lưu gì vào kho.
class QuickViewScreen extends StatefulWidget {
  const QuickViewScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<QuickViewScreen> createState() => _QuickViewScreenState();
}

class _QuickViewScreenState extends State<QuickViewScreen> {
  final _input = TextEditingController();
  TotpParams? _params;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _check() {
    final text = _input.text.trim();
    try {
      final TotpParams p;
      if (text.startsWith('otpauth://')) {
        p = OtpAuth.parse(text).toParams();
      } else {
        p = TotpParams(secret: text.replaceAll(RegExp(r'\s'), '').toUpperCase());
      }
      Otp.code(p, DateTime.now());
      setState(() {
        _params = p;
        _error = null;
      });
    } on Object {
      setState(() {
        _params = null;
        _error = tr('Khóa không hợp lệ (chỉ gồm chữ A–Z và số 2–7)');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Xem nhanh 2FA'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _input,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 5,
            maxLines: 8,
            style: Theme.of(context).textTheme.titleMedium,
            onChanged: (_) => setState(() => _params = null),
            decoration: InputDecoration(labelText: tr('Khóa 2FA hoặc link otpauth://'), alignLabelWithHint: true, contentPadding: const EdgeInsets.all(20)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _input.text.trim().isEmpty ? null : _check,
            child: Padding(padding: EdgeInsets.all(12), child: Text(tr('Kiểm tra'))),
          ),
          if (_error != null) ErrorText(_error!),
          if (_params != null) ...[
            const SizedBox(height: 24),
            Clock(builder: (context, now) => Center(child: Transform.scale(scale: 1.4, child: TotpChip(params: _params!, now: now)))),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(tr('Lưu vào kho')),
              onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => ItemEditorScreen(controller: widget.controller, prefillSecret: _input.text.trim(), startType: ItemType.totp),
              )),
            ),
          ],
        ]),
      );
}
