import 'package:material_ui/material_ui.dart';

import '../constants.dart';
import '../../core/import_export/exporters.dart';
import '../../core/vault/models.dart';
import '../i18n.dart';
import '../widgets/qr_view.dart';
import '../widgets/form_layout.dart';

/// Hiện một hoặc nhiều mã QR (mỗi mã một trang). Dùng để chuyển 2FA sang app khác.
class QrShowScreen extends StatefulWidget {
  const QrShowScreen({super.key, required this.title, required this.codes, required this.hint});
  final String title;
  final List<String> codes;
  final String hint;

  /// Một mục 2FA → link `otpauth://` của nó.
  static QrShowScreen forItem(Item item) => QrShowScreen(
        title: item.title,
        codes: [Exporters.otpAuthOf(item)!.toUri()],
        hint: tr('Quét mã này bằng app 2FA khác để thêm tài khoản.'),
      );

  /// Mọi mục 2FA → các mã `otpauth-migration://` để nhập vào Google Authenticator.
  static QrShowScreen forGoogleAuthenticator(Iterable<Item> items) => QrShowScreen(
        title: tr('Chuyển sang Google Authenticator'),
        codes: Exporters.googleMigrationUris(items, perBatch: 6),
        hint: tr('Trong Google Authenticator chọn Nhập tài khoản → Quét mã QR, rồi quét lần lượt từng mã.'),
      );

  @override
  State<QrShowScreen> createState() => _QrShowScreenState();
}

class _QrShowScreenState extends State<QrShowScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final codes = widget.codes;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: codes.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Chưa có mục 2FA nào để xuất.'), textAlign: TextAlign.center)))
          : ListView(padding: formPadding(MediaQuery.sizeOf(context).width, const EdgeInsets.all(16)), children: [
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tr('Mã QR này chứa khóa bí mật. Không chụp màn hình hay gửi cho ai; đóng màn này ngay khi quét xong.'))),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Center(child: QrView(key: ValueKey(_page), data: codes[_page], size: Sizes.qrCode)),
              const SizedBox(height: 12),
              if (codes.length > 1)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(tooltip: tr('Mã trước'), icon: const Icon(Icons.chevron_left), onPressed: _page > 0 ? () => setState(() => _page--) : null),
                  Text(tr('Mã {p0} / {p1}', {'p0': _page + 1, 'p1': codes.length}), style: Theme.of(context).textTheme.titleMedium),
                  IconButton(tooltip: tr('Mã sau'), icon: const Icon(Icons.chevron_right), onPressed: _page < codes.length - 1 ? () => setState(() => _page++) : null),
                ]),
              const SizedBox(height: 8),
              Text(widget.hint, textAlign: TextAlign.center),
            ]),
    );
  }
}
