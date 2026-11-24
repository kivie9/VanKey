import 'package:material_ui/material_ui.dart';

import '../../core/security/password_strength.dart';
import '../i18n.dart';
import '../theme.dart';

/// Khối nhóm: một thẻ bo góc chứa nhiều dòng, ngăn cách bằng đường kẻ mảnh. Dùng cho Cài đặt, chi tiết, form.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.children, this.padding = EdgeInsets.zero, this.dividerIndent = Gap.lg});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  /// Lề trái của đường kẻ (để đường kẻ không chạm mép thẻ).
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(indent: dividerIndent, height: 1));
      rows.add(children[i]);
    }
    return Card(child: Padding(padding: padding, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)));
  }
}

/// Danh sách mà MỖI dòng là một thẻ riêng (có khoảng cách giữa các thẻ). Dùng cho Cài đặt, Đồng bộ, Thùng rác...
class CardList extends StatelessWidget {
  const CardList({super.key, required this.children, this.gap = Gap.sm});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            Card(child: children[i]),
          ],
        ],
      );
}

/// Tiêu đề nhóm nhỏ, chữ hoa mờ (dùng phía trên một [SectionCard] hoặc danh sách).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.count, this.collapsed, this.onTap, this.padding = const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.lg, Gap.sm)});
  final String text;
  final int? count;
  final bool? collapsed;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(children: [
          Text(text.toUpperCase(), style: t.labelSmall?.copyWith(color: c.muted, letterSpacing: 0.9)),
          if (count != null) ...[
            const SizedBox(width: Gap.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(Radii.pill)),
              child: Text('$count', style: t.labelSmall?.copyWith(color: c.muted)),
            ),
          ],
          const Spacer(),
          if (collapsed != null) Icon(collapsed! ? Icons.expand_more : Icons.expand_less, size: 20, color: c.muted),
        ]),
      ),
    );
  }
}

/// Ô icon bo góc nền nhạt (dùng ở đầu dòng cài đặt).
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.size = 38, this.color});
  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = color ?? c.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: fg.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(Radii.md - 2)),
      child: Icon(icon, size: size * 0.52, color: fg),
    );
  }
}

/// Logo VanKey nhỏ (cùng hình với biểu tượng app) cho màn tạo kho và mở khóa.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.accent, Color.lerp(c.accent, Colors.black, 0.25)!]),
        boxShadow: [BoxShadow(color: c.accent.withValues(alpha: 0.20), blurRadius: size * 0.45, offset: Offset(0, size * 0.12))],
      ),
      child: CustomPaint(painter: _LogoMarkPainter()),
    );
  }
}

/// Hình logo: chữ V trắng viền đen và chiếc khiên ở đầu cánh trái. Hệ toạ độ 180x180 như docs/brand/vankey-logo.svg.
class _LogoMarkPainter extends CustomPainter {
  static const _ink = Color(0xFF0E1330);
  static const _unit = 180.0;
  static const _shiftX = 7.0;
  static const _shiftY = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _unit;
    canvas.scale(s);
    canvas.translate(_shiftX, _shiftY);

    final v = Path()
      ..moveTo(54, 80)
      ..quadraticBezierTo(72, 106, 90, 128)
      ..quadraticBezierTo(112, 98, 134, 46);
    Paint stroke(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width
      ..color = color;
    canvas.drawPath(v, stroke(_ink, 38));
    canvas.drawPath(v, stroke(Colors.white, 24));

    final shield = Path()
      ..moveTo(44, 34)
      ..lineTo(62, 41)
      ..lineTo(62, 58)
      ..cubicTo(62, 68, 54, 74, 44, 78)
      ..cubicTo(34, 74, 26, 68, 26, 58)
      ..lineTo(26, 41)
      ..close();
    canvas.drawPath(shield, stroke(_ink, 6));
    canvas.drawPath(shield, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dải thông báo nhỏ (cảnh báo, lỗi, gợi ý) trong thẻ màu.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.icon = Icons.info_outline, this.tone = NoticeTone.info});
  final String text;
  final IconData icon;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = switch (tone) { NoticeTone.info => c.accent, NoticeTone.warn => c.warn, NoticeTone.error => c.danger };
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: Gap.md),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.fg))),
      ]),
    );
  }
}

enum NoticeTone { info, warn, error }

/// Thanh độ mạnh mật khẩu (thanh 4 đoạn + nhãn).
class StrengthMeter extends StatelessWidget {
  const StrengthMeter(this.strength, {super.key});
  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (label, color, filled) = switch (strength.level) {
      StrengthLevel.weak => (tr('Yếu'), c.danger, 1),
      StrengthLevel.fair => (tr('Tạm được'), c.warn, 2),
      StrengthLevel.strong => (tr('Mạnh'), c.success, 3),
      StrengthLevel.veryStrong => (tr('Rất mạnh'), c.success, 4),
    };
    return Padding(
      padding: const EdgeInsets.only(top: Gap.sm),
      child: Row(children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(child: Container(height: 5, decoration: BoxDecoration(color: i < filled ? color : c.line, borderRadius: BorderRadius.circular(Radii.pill)))),
          if (i < 3) const SizedBox(width: 4),
        ],
        const SizedBox(width: Gap.md),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
      ]),
    );
  }
}

/// Màn hình giữa trang cho tạo kho / mở khóa: căn giữa, bề rộng tối đa vừa phải.
class CenteredPage extends StatelessWidget {
  const CenteredPage({super.key, required this.children, this.maxWidth = 460});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.xxl), children: children),
            ),
          ),
        ),
      );
}

/// Trạng thái rỗng: icon lớn mờ, tiêu đề, dòng mô tả.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 38, color: c.accent),
          ),
          const SizedBox(height: Gap.lg),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: Gap.sm),
            Text(message!, style: t.bodyMedium?.copyWith(color: c.muted), textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }
}

/// Hộp xác nhận cho thao tác khó hoàn tác. Trả về true nếu người dùng đồng ý.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final c = AppColors.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: danger ? Icon(Icons.delete_outline_rounded, color: c.danger, size: 28) : null,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: c.onAccent == Colors.white ? Colors.white : Colors.black) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
