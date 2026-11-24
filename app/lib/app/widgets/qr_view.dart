import 'package:material_ui/material_ui.dart';
import 'package:zxing2/qrcode.dart';

/// Vẽ mã QR. Luôn đen trên nền trắng (kể cả giao diện tối) để máy quét đọc được.
class QrView extends StatelessWidget {
  const QrView({super.key, required this.data, this.size = 280});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Dữ liệu dài (nhiều tài khoản) dùng mức sửa lỗi thấp để mã đỡ dày đặc.
    final level = data.length > 300 ? ErrorCorrectionLevel.l : ErrorCorrectionLevel.m;
    final matrix = Encoder.encode(data, level).matrix!;
    final n = matrix.width;
    final dark = List<bool>.generate(n * n, (i) => matrix.get(i % n, i ~/ n) == 1);
    return Semantics(
      image: true,
      label: 'QR',
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.05),
        child: CustomPaint(painter: _QrPainter(n, dark)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.n, this.dark);
  final int n;
  final List<bool> dark;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / n;
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (dark[y * n + x]) {
          // +0,5 px để các ô liền nhau, không hở đường chỉ do làm tròn.
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.n != n || old.dark != dark;
}
