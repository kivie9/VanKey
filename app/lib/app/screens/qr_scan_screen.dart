import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/vault/models.dart';
import '../vault_controller.dart';
import 'import_screen.dart';
import 'item_editor_screen.dart';
import '../i18n.dart';
import '../qr_image.dart';
import '../widgets/form_layout.dart';

/// Quét QR bằng camera (hoặc chọn ảnh QR có sẵn). Hỗ trợ otpauth:// và otpauth-migration:// của Google Authenticator.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  /// Điện thoại: quét bằng ML Kit (mobile_scanner). Máy tính (Windows): mở camera bằng package camera,
  /// chụp định kỳ rồi đọc mã bằng bộ đọc Dart thuần (qr_image.dart).
  static final bool _mlKit = Platform.isAndroid || Platform.isIOS;

  final MobileScannerController? _scanner = _mlKit
      ? MobileScannerController(formats: const [BarcodeFormat.qrCode])
      : null;
  CameraController? _cam;
  Timer? _tick;
  bool _busy = false;
  String? _camError;
  bool _handled = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (!_mlKit) _startDesktopCamera();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _cam?.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  Future<void> _startDesktopCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted)
          setState(() => _camError = tr('Không tìm thấy camera trên máy này.'));
        return;
      }
      final c = CameraController(
        cams.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _cam = c;
      setState(() {});
      _tick = Timer.periodic(
        const Duration(milliseconds: 700),
        (_) => _scanFrame(),
      );
    } on Object catch (e) {
      if (mounted)
        setState(
          () => _camError = tr(
            'Không mở được camera ({p0}). Kiểm tra camera không bị app khác dùng, hoặc chọn ảnh QR bên dưới.',
            {'p0': e.toString()},
          ),
        );
    }
  }

  /// Chụp một khung hình và tìm mã QR trong đó. Lỗi một khung thì bỏ qua, thử lại ở lần sau.
  Future<void> _scanFrame() async {
    final c = _cam;
    if (_busy ||
        _handled ||
        c == null ||
        !c.value.isInitialized ||
        c.value.isTakingPicture)
      return;
    _busy = true;
    String? path;
    try {
      final shot = await c.takePicture();
      path = shot.path;
      final v = QrImageDecoder.decode(await File(path).readAsBytes());
      if (v != null && mounted) _onValue(v);
    } on Object {
      // khung hình lỗi: bỏ qua
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } on Object {
          // file tạm không xóa được thì thôi
        }
      }
      _busy = false;
    }
  }

  void _onValue(String? v) {
    if (_handled || v == null) return;
    final text = v.trim();
    final nav = Navigator.of(context);
    final c = widget.controller;
    if (text.startsWith('otpauth-migration://')) {
      _handled = true;
      nav.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ImportScreen(controller: c, initialText: text),
        ),
      );
    } else if (text.startsWith('otpauth://')) {
      _handled = true;
      nav.pushReplacement(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ItemEditorScreen(
            controller: c,
            prefillSecret: text,
            startType: ItemType.totp,
          ),
        ),
      );
    } else {
      setState(() => _message = tr('Mã QR này không phải mã 2FA.'));
    }
  }

  Future<void> _fromImage() async {
    final files = await widget.controller.external(
      () => FilePicker.pickFiles(type: FileType.image),
    );
    if (files.isEmpty || files.first.path == null) return;
    final path = files.first.path!;
    String? v;
    final s = _scanner;
    if (s != null) {
      try {
        final cap = await s.analyzeImage(
          path,
          formats: const [BarcodeFormat.qrCode],
        );
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

  Widget _mobileBody() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scanner!,
          onDetect: (cap) => _onValue(
            cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue,
          ),
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                tr(
                  'Không mở được camera. Cấp quyền camera cho VanKey trong cài đặt điện thoại, hoặc chọn ảnh QR bên dưới.\n({p0})',
                  {'p0': error.errorCode.name},
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        if (_message != null)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_message!),
              ),
            ),
          ),
      ],
    );
  }

  Widget _desktopBody() {
    final cam = _cam;
    final Widget view;
    if (_camError != null) {
      view = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_camError!, textAlign: TextAlign.center),
        ),
      );
    } else if (cam == null || !cam.value.isInitialized) {
      view = const Center(child: CircularProgressIndicator());
    } else {
      view = Center(
        child: AspectRatio(
          aspectRatio: cam.value.aspectRatio,
          child: CameraPreview(cam),
        ),
      );
    }
    return Stack(
      children: [
        // Khung camera và thông báo lỗi không kéo rộng theo cửa sổ.
        Positioned.fill(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: formMaxWidth),
              child: view,
            ),
          ),
        ),
        if (_message != null)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_message!),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Quét mã QR'))),
    body: _mlKit ? _mobileBody() : _desktopBody(),
    bottomNavigationBar: FormBar(
      padding: const EdgeInsets.all(12),
      child: OutlinedButton.icon(
        onPressed: _fromImage,
        icon: const Icon(Icons.image_outlined),
        label: Padding(
          padding: EdgeInsets.all(12),
          child: Text(tr('Chọn ảnh QR có sẵn')),
        ),
      ),
    ),
  );
}
