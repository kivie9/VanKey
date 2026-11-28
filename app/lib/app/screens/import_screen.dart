import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors.dart';
import '../../core/import_export/imported_item.dart';
import '../../core/import_export/extra_importers.dart';
import '../../core/import_export/importers.dart';
import '../i18n.dart';
import '../theme.dart';
import '../vault_controller.dart';
import '../widgets/common.dart';
import '../widgets/form_layout.dart';

/// Khối ví dụ định dạng: nền nhạt, chữ đơn cách để chép được.
class _ExampleBox extends StatelessWidget {
  const _ExampleBox({required this.title, required this.example});
  final String title;
  final String example;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: 6),
          SelectableText(
            example,
            style: TextStyle(fontFamily: Fonts.mono, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Nhập từ file xuất của app khác, hoặc dán nội dung/link (otpauth://, otpauth-migration://).
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.controller, this.initialText});
  final VaultController controller;
  final String? initialText;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _text = TextEditingController();
  List<({ImportedItem item, bool duplicate})>? _rows;
  List<ImportWarning> _warnings = const [];
  final _selected = <int>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.initialText;
    if (t != null) {
      _text.text = t;
      _parse();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final files = await widget.controller.external(
      () => FilePicker.pickFiles(),
    );
    if (files.isEmpty || files.first.path == null) return;
    try {
      final bytes = await File(files.first.path!).readAsBytes();
      if (ExtraImporters.isZip(bytes)) {
        _parseResult(() => Importers.autoBytes(bytes));
      } else {
        _text.text = utf8.decode(bytes, allowMalformed: true);
        _parse();
      }
    } on Object {
      setState(
        () => _error = tr(
          'Không đọc được file này (cần file văn bản: JSON, CSV hoặc danh sách link).',
        ),
      );
    }
  }

  void _parse() => _parseResult(() => Importers.auto(_text.text));

  void _parseResult(ImportResult Function() read) {
    final c = widget.controller;
    try {
      final r = read();
      final rows = r.markDuplicates(c.data.items);
      setState(() {
        _rows = rows;
        _warnings = r.warnings;
        _selected
          ..clear()
          ..addAll([
            for (var i = 0; i < rows.length; i++)
              if (!rows[i].duplicate) i,
          ]);
        _error = rows.isEmpty ? tr('Không tìm thấy mục nào để nhập.') : null;
      });
    } on EncryptedImportException {
      setState(
        () => _error = tr(
          'File này được mã hóa bởi app nguồn. Xuất lại bản không mã hóa từ app đó.',
        ),
      );
    } on VaultException catch (e) {
      setState(() => _error = tr('Không đọc được: {p0}', {'p0': e.message}));
    }
  }

  void _import() {
    final c = widget.controller;
    final rows = _rows!;
    c.mutate((d) {
      var out = d;
      for (final i in _selected) {
        out = out.upsert(rows[i].item.toItem(clock: c.clock));
      }
      return out;
    });
    final n = _selected.length;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(tr('Đã nhập {p0} mục', {'p0': n}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Nhập dữ liệu'))),
      body: ListView(
        padding: formPadding(MediaQuery.sizeOf(context).width),
        children: [
          if (rows == null || rows.isEmpty) ...[
            Text(
              tr('Cách nhập'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                '1. Chọn file xuất từ app khác: Google Authenticator (xuất link), Aegis, 2FAS, Bitwarden, 1Password, Chrome, KeePass.',
              ),
            ),
            const SizedBox(height: 8),
            Text(tr('2. Hoặc dán vào ô bên dưới một trong hai dạng sau:')),
            const SizedBox(height: 8),
            _ExampleBox(
              title: tr(
                'Danh sách link otpauth:// (mỗi dòng một tài khoản 2FA)',
              ),
              example: 'otpauth://totp/GitHub:van@mail.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub',
            ),
            const SizedBox(height: 8),
            _ExampleBox(
              title: tr('CSV có dòng tiêu đề ở đầu (các cột có thể bỏ bớt):'),
              example: 'name,username,password,url,totp,folder\nGitHub,van-dev,Pass123!,github.com,JBSWY3DPEHPK3PXP,Công việc',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: Padding(
                padding: EdgeInsets.all(12),
                child: Text(tr('Chọn file')),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 10,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Nội dung cần nhập'),
                hintText: tr('Dán danh sách link otpauth:// hoặc CSV vào đây'),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _text.text.trim().isEmpty ? null : _parse,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(tr('Đọc')),
              ),
            ),
            if (_error != null) ErrorText(_error!),
          ] else ...[
            Text(
              tr('Tìm thấy {p0} mục. Mục trùng đã bỏ chọn sẵn.', {
                'p0': rows.length,
              }),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (_warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr(
                    '{p0} mục bị bỏ qua hoặc đọc chưa hết (Steam, HOTP, dòng lỗi...).',
                    {'p0': _warnings.length},
                  ),
                  style: TextStyle(color: Colors.orange.shade700),
                ),
              ),
            const SizedBox(height: 8),
            for (var i = 0; i < rows.length; i++)
              CheckboxListTile(
                value: _selected.contains(i),
                onChanged: (v) => setState(
                  () => v == true ? _selected.add(i) : _selected.remove(i),
                ),
                title: Text(rows[i].item.title),
                subtitle: Text(
                  [
                    if (rows[i].item.username.isNotEmpty)
                      rows[i].item.username
                    else if (rows[i].item.totp?.account.isNotEmpty ?? false)
                      rows[i].item.totp!.account,
                    if (rows[i].item.totp != null) tr('có 2FA'),
                    if (rows[i].duplicate) tr('trùng với mục đã có'),
                  ].join(' · '),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ],
      ),
      bottomNavigationBar: rows == null || rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _selected.isEmpty ? null : _import,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(tr('Nhập {p0} mục', {'p0': _selected.length})),
                  ),
                ),
              ),
            ),
    );
  }
}
