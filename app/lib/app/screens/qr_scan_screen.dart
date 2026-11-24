import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/vault/models.dart';
import '../vault_controller.dart';
import 'import_screen.dart';
import 'item_editor_screen.dart';
import '../i18n.dart';
import '../qr_image.dart';

/// Quét QR bằng camera (hoặc chọn ảnh QR có sẵn). Hỗ trợ otpauth:// và otpauth-migration:// của Google Authenticator.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  /// Windows/Linux không có camera cho bộ quét này: chỉ đọc từ ảnh (Dart thuần).
  static final bool _hasCamera = Platform.isAndroid || Platform.isIOS;

  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _handled = false;
  String? _message;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onValue(String? v) {
    if (_handled || v == null) return;
    final text = v.trim();
    final nav = Navigator.of(context);
    final c = widget.controller;
    if (text.startsWith('otpauth-migration://')) {
      _handled = true;
      nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => ImportScreen(controller: c, initialText: text)));
    } else if (text.startsWith('otpauth://')) {
      _handled = true;
      nav.pushReplacement(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ItemEditorScreen(controller: c, prefillSecret: text, startType: ItemType.totp),
      ));
    } else {
      setState(() => _message = tr('Mã QR này không phải mã 2FA.'));
    }
  }

  Future<void> _fromImage() async {
    final files = await widget.controller.external(() => FilePicker.pickFiles(type: FileType.image));
    if (files.isEmpty || files.first.path == null) return;
    final path = files.first.path!;
    String? v;
    if (_hasCamera) {
      try {
        final cap = await _scanner.analyzeImage(path, formats: const [BarcodeFormat.qrCode]);
        final codes = cap?.barcodes ?? const <Barcode>[];
        v = codes.isEmpty ? null : codes.first.rawValue;
      } on Object {
        v = null;
      }
    }
    // ML Kit không đọc được (hoặc không có): thử bộ đọc Dart thuần.
    v ??= QrImageDecoder.decode(await File(path).readAsBytes());
    if (v == null) {
      setState(() => _message = tr('Không tìm thấy mã QR trong ảnh.'));
    } else {
      _onValue(v);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Quét mã QR'))),
        body: !_hasCamera
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.qr_code_2, size: 72),
                    const SizedBox(height: 12),
                    Text(tr('Máy tính không quét bằng camera. Hãy chụp màn hình mã QR (hoặc lưu ảnh) rồi chọn ảnh đó.'), textAlign: TextAlign.center),
                    if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!, style: const TextStyle(color: Colors.red))),
                  ]),
                ),
              )
            : Stack(children: [
          MobileScanner(
            controller: _scanner,
            onDetect: (cap) => _onValue(cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue),
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr('Không mở được camera. Hãy cấp quyền camera cho VanKey trong cài đặt điện thoại, hoặc chọn ảnh QR bên dưới.\n({p0})', {'p0': error.errorCode.name}),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          if (_message != null) Positioned(top: 16, left: 16, right: 16, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!)))),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: _fromImage,
              icon: const Icon(Icons.image_outlined),
              label: Padding(padding: EdgeInsets.all(12), child: Text(tr('Chọn ảnh QR có sẵn'))),
            ),
          ),
        ),
      );
}
