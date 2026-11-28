import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../i18n.dart';
import '../theme.dart';
import 'ui.dart';

/// Khung của các màn mở khóa, thiết lập lần đầu và đăng nhập máy chủ, cùng kiểu với trang đăng nhập bản web (`server/web/src/app/brand.tsx`).
///
/// - Cửa sổ rộng (máy tính): chia đôi, bảng giới thiệu bên trái, form bên phải.
/// - Màn hẹp (điện thoại): dải màu có hình vẽ ở trên, form ở dưới.
/// - Màn hẹp mà thiếu chỗ (bàn phím đang mở, màn thấp, chữ hệ thống lớn): dải màu thu lại còn logo và tên.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.children, this.compactHeader = false, this.maxWidth = 420});

  /// Nội dung form.
  final List<Widget> children;

  /// Màn hẹp luôn dùng dải thu gọn: dành cho form dài, cần chỗ cho ô nhập.
  final bool compactHeader;

  /// Bề rộng tối đa của form.
  final double maxWidth;

  /// Từ bề rộng này thì chia đôi (trùng mốc của bản web).
  static const wideWidth = 860.0;

  /// Màn hẹp cần ít nhất chừng này chiều cao (sau khi trừ bàn phím) mới hiện hình vẽ.
  static const _artHeight = 680.0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: LayoutBuilder(builder: (context, box) {
          if (box.maxWidth >= wideWidth) {
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: math.max(360, box.maxWidth * 0.4), child: const _BrandPanel()),
              Expanded(child: SafeArea(child: _form(const EdgeInsets.all(Gap.xl)))),
            ]);
          }
          // Scaffold đã trừ bàn phím khỏi chiều cao này.
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final compact = compactHeader || box.maxHeight < _artHeight || scale > 1.3;
          return Column(children: [
            // Dải màu đậm nằm dưới thanh trạng thái nên biểu tượng giờ, pin phải màu sáng.
            AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: _BrandHeader(compact: compact)),
            Expanded(child: SafeArea(top: false, child: _form(const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.xxl)))),
          ]);
        }),
      );

  Widget _form(EdgeInsets padding) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(shrinkWrap: true, padding: padding, children: children),
        ),
      );
}

/// Hai màu nền của phần giới thiệu: màu nhấn làm đậm để chữ trắng luôn dễ đọc, cả giao diện sáng lẫn tối.
List<Color> _brandColors(BuildContext context) {
  final hsl = HSLColor.fromColor(AppColors.of(context).accent);
  final s = math.min(hsl.saturation, 0.85);
  return [
    hsl.withSaturation(s).withLightness(0.26).toColor(),
    hsl.withSaturation(s).withLightness(0.19).toColor(),
  ];
}

class _BrandBackground extends StatelessWidget {
  const _BrandBackground({required this.child, this.radius = BorderRadius.zero});
  final Widget child;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _brandColors(context)),
          ),
          child: CustomPaint(
            painter: const _PatternPainter(),
            child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
          ),
        ),
      );
}

class _Name extends StatelessWidget {
  const _Name({required this.logoSize});
  final double logoSize;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        // Logo cùng màu nhấn với nền, thêm viền sáng để không bị chìm.
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(logoSize * 0.28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
          ),
          child: AppLogo(size: logoSize),
        ),
        const SizedBox(width: Gap.md),
        Flexible(
          child: Text('VanKey', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
        ),
      ]);
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final points = [
      tr('Kho được giải mã ngay trên thiết bị của bạn'),
      tr('Mật khẩu của bạn không được gửi lên máy chủ'),
      tr('Mở được cả khi không có mạng'),
    ];
    return _BrandBackground(
      child: SafeArea(
        right: false,
        child: LayoutBuilder(
          // Cửa sổ thấp thì cuộn được; đủ cao thì hình vẽ nằm sát đáy.
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: math.max(0, box.maxHeight - 80)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _Name(logoSize: 36),
                    const SizedBox(height: Gap.xxl),
                    Text(tr('Két an toàn cho mật khẩu và mã 2FA của bạn'), style: t.headlineLarge?.copyWith(color: Colors.white, height: 1.2)),
                    const SizedBox(height: Gap.lg),
                    Text(tr('Mã hóa đầu-cuối. Đồng bộ giữa các thiết bị.'), style: t.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: Gap.xl),
                    for (final p in points)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.md),
                        child: Row(children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                          ),
                          const SizedBox(width: Gap.md),
                          Expanded(child: Text(p, style: t.bodyLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600))),
                        ]),
                      ),
                  ]),
                  const Padding(
                    padding: EdgeInsets.only(top: Gap.xl),
                    child: Center(child: _Illustration(maxWidth: 380, maxHeight: 285)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: _BrandBackground(
          radius: const BorderRadius.vertical(bottom: Radius.circular(Radii.xl)),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.lg),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _Name(logoSize: compact ? 32 : 36),
                if (!compact) ...[
                  const SizedBox(height: Gap.md),
                  const _Illustration(maxWidth: 240, maxHeight: 180),
                ],
              ]),
            ),
          ),
        ),
      );
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.maxWidth, required this.maxHeight});
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = _brandColors(context);
    return ExcludeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: AspectRatio(aspectRatio: 360 / 270, child: CustomPaint(painter: _IllustrationPainter(c.first))),
      ),
    );
  }
}

Paint _stroke(Color color, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..strokeWidth = width
  ..color = color;

/// Hoa văn mờ: chìa khóa, ổ khóa, dấu sao và nét gạch, lặp theo ô 160x160 và xoay nhẹ.
class _PatternPainter extends CustomPainter {
  const _PatternPainter();
  static const _tile = 160.0;

  @override
  void paint(Canvas canvas, Size size) {
    final p = _stroke(Colors.white.withValues(alpha: 0.07), 5);
    final motif = Path()
      ..addOval(Rect.fromCircle(center: const Offset(30, 34), radius: 13))
      ..moveTo(43, 34)
      ..lineTo(78, 34)
      ..moveTo(66, 34)
      ..lineTo(66, 45)
      ..moveTo(76, 34)
      ..lineTo(76, 42)
      ..addRRect(RRect.fromLTRBR(102, 92, 136, 119, const Radius.circular(6)))
      ..moveTo(109, 92)
      ..lineTo(109, 83)
      ..arcToPoint(const Offset(129, 83), radius: const Radius.circular(10))
      ..lineTo(129, 92)
      ..moveTo(124, 22)
      ..lineTo(124, 46)
      ..moveTo(114, 28)
      ..lineTo(134, 40)
      ..moveTo(134, 28)
      ..lineTo(114, 40)
      ..moveTo(18, 112)
      ..relativeQuadraticBezierTo(10, -14, 20, 0)
      ..relativeQuadraticBezierTo(10, 14, 20, 0)
      ..moveTo(30, 142)
      ..relativeLineTo(34, 0);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.rotate(-12 * math.pi / 180);
    // Vẽ rộng hơn khung để sau khi xoay không hở góc.
    final reach = size.width + size.height;
    for (var y = -_tile; y < reach; y += _tile) {
      for (var x = -reach / 2; x < reach; x += _tile) {
        canvas.drawPath(motif.shift(Offset(x, y)), p);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => false;
}

/// Khiên, ổ khóa, thẻ mật khẩu, thẻ mã 2FA và chìa khóa. Hệ toạ độ 360x270 như hình của bản web.
class _IllustrationPainter extends CustomPainter {
  const _IllustrationPainter(this.brand);
  final Color brand;

  static const _ink = Color(0xFF06201B);
  static const _gold = Color(0xFFF4B740);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 360);
    Paint fill(Color color) => Paint()..color = color;
    final soft = Color.lerp(brand, Colors.white, 0.83)!;

    void rotated(double degrees, Offset center, VoidCallback draw) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(degrees * math.pi / 180);
      canvas.translate(-center.dx, -center.dy);
      draw();
      canvas.restore();
    }

    void card(Rect rect, double radius) {
      final r = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      canvas.drawRRect(r, fill(Colors.white));
      canvas.drawRRect(r, _stroke(_ink, 4));
    }

    canvas.drawOval(Rect.fromCenter(center: const Offset(180, 252), width: 264, height: 18), fill(Colors.black.withValues(alpha: 0.25)));

    // Khiên.
    final outer = Path()
      ..moveTo(180, 22)
      ..lineTo(272, 56)
      ..lineTo(272, 132)
      ..cubicTo(272, 190, 233, 225, 180, 248)
      ..cubicTo(127, 225, 88, 190, 88, 132)
      ..lineTo(88, 56)
      ..close();
    canvas.drawPath(outer, fill(Colors.white));
    canvas.drawPath(outer, _stroke(_ink, 5));
    final inner = Path()
      ..moveTo(180, 44)
      ..lineTo(252, 71)
      ..lineTo(252, 132)
      ..cubicTo(252, 176, 223, 205, 180, 224)
      ..cubicTo(137, 205, 108, 176, 108, 132)
      ..lineTo(108, 71)
      ..close();
    canvas.drawPath(inner, fill(soft));

    // Ổ khóa.
    final shackle = Path()
      ..moveTo(154, 122)
      ..lineTo(154, 104)
      ..arcToPoint(const Offset(206, 104), radius: const Radius.circular(26))
      ..lineTo(206, 122);
    canvas.drawPath(shackle, _stroke(_ink, 10)..strokeCap = StrokeCap.butt);
    final body = RRect.fromLTRBR(138, 118, 222, 184, const Radius.circular(14));
    canvas.drawRRect(body, fill(_gold));
    canvas.drawRRect(body, _stroke(_ink, 5));
    canvas.drawCircle(const Offset(180, 145), 9, fill(_ink));
    canvas.drawLine(const Offset(180, 148), const Offset(180, 164), _stroke(_ink, 8));

    // Thẻ mật khẩu.
    rotated(-9, const Offset(74, 78), () {
      card(const Rect.fromLTWH(18, 56, 112, 44), 12);
      for (final x in [42.0, 63.0, 84.0, 105.0]) {
        canvas.drawCircle(Offset(x, 78), 6, fill(_ink));
      }
    });

    // Thẻ mã 2FA.
    rotated(7, const Offset(281, 184), () {
      card(const Rect.fromLTWH(214, 158, 134, 52), 13);
      final code = TextPainter(
        text: TextSpan(text: '482 913', style: TextStyle(fontFamily: Fonts.mono, fontWeight: FontWeight.w700, fontSize: 19, color: brand)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);
      code.paint(canvas, Offset(226, 184 - code.height / 2));
      code.dispose();
      const ring = Offset(331, 184);
      canvas.drawCircle(ring, 8, _stroke(soft, 4));
      canvas.drawArc(Rect.fromCircle(center: ring, radius: 8), -math.pi / 2, math.pi * 1.5, false, _stroke(brand, 4));
    });

    // Chìa khóa: vẽ nét đậm trước, nét vàng đè lên để thành viền.
    rotated(-24, const Offset(66, 190), () {
      final teeth = Path()
        ..moveTo(70, 190)
        ..lineTo(124, 190)
        ..moveTo(108, 190)
        ..lineTo(108, 206)
        ..moveTo(122, 190)
        ..lineTo(122, 202);
      const bow = Offset(52, 190);
      canvas.drawPath(teeth, _stroke(_ink, 15));
      canvas.drawCircle(bow, 20, _stroke(_ink, 17));
      canvas.drawPath(teeth, _stroke(_gold, 7));
      canvas.drawCircle(bow, 20, _stroke(_gold, 9));
    });
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter old) => old.brand != brand;
}
