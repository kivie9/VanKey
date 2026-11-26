import 'dart:async';
import 'dart:math' as math;

import '../constants.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/totp/totp.dart';
import '../platform_bridge.dart';
import '../../core/vault/models.dart';
import '../i18n.dart';
import '../labels.dart';
import '../brand.dart';
import '../theme.dart';

/// Chép vào clipboard rồi tự xóa sau 30 giây (chỉ khi clipboard vẫn còn đúng nội dung đó).
Future<void> copyText(BuildContext context, String text, {String? what}) async {
  if (!await PlatformBridge.copySensitive(text)) await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(what ?? tr('Đã chép')), duration: Timing.copiedSnack));
  }
  Timer(Timing.clipboardClear, () async {
    final cur = await Clipboard.getData(Clipboard.kTextPlain);
    if (cur?.text == text) await Clipboard.setData(const ClipboardData(text: ''));
  });
}

/// Mở một trang mới (đẩy lên ngăn xếp điều hướng). Dùng chung cho mọi nơi cần chuyển trang.
Future<void> pushPage(BuildContext context, Widget page, {bool full = false}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: full, builder: (_) => page));

/// Dòng báo lỗi dưới form (màu lỗi của giao diện, không ghi cứng màu).
class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Gap.md),
        child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}

/// Biểu tượng của mục: logo thương hiệu nếu nhận ra (Facebook, Google...), không thì chữ cái đầu trên nền màu trầm.
class Avatar extends StatelessWidget {
  const Avatar(this.title, {super.key, this.size = 40, this.url = '', this.plain = false});

  /// Dùng cho một mục: nhận diện thương hiệu theo cả tên lẫn địa chỉ web của mục.
  Avatar.forItem(Item item, {Key? key, double size = 40, bool plain = false})
      : this(item.title, key: key, size: size, url: item.valueOf('url') ?? '', plain: plain);

  final String title;
  final double size;
  final String url;

  /// Chỉ vẽ biểu tượng (hoặc chữ cái), không nền, không viền. Dùng ở tab 2FA.
  final bool plain;

  static const _hues = [210.0, 160.0, 28.0, 280.0, 340.0, 190.0, 100.0, 50.0];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brand = BrandConfig.enabled ? brandFor(title, url) : null;
    if (plain) return _plain(context, brand);
    if (brand != null && brand.multicolor) {
      // Google: nền sáng, chữ G bốn màu (dải màu quét quanh tâm, bắt đầu lệch -40° để thanh ngang màu xanh dương nằm bên phải).
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: dark ? const Color(0xFFF1F3F4) : Colors.white, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: AppColors.of(context).line)),
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => SweepGradient(startAngle: -0.7, endAngle: -0.7 + 6.2832, colors: brand.sweep!, stops: brand.stops).createShader(r),
          child: Icon(brand.icon, size: size * 0.58, color: Colors.white),
        ),
      );
    }
    if (brand != null) {
      var bg = brand.color;
      // Giao diện tối: hạ nhẹ độ chói; màu gần đen (GitHub, Apple, X) đổi sang xám đậm để còn nhìn thấy.
      if (dark) bg = Color.lerp(bg, Colors.black, 0.15)!;
      if (dark && bg.computeLuminance() < 0.03) bg = const Color(0xFF2E2E35);
      final fg = bg.computeLuminance() > 0.6 ? const Color(0xFF111111) : Colors.white;
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.md)),
        child: Icon(brand.icon, size: size * 0.54, color: fg),
      );
    }
    final h = _hues[title.codeUnits.fold<int>(0, (a, b) => a + b) % _hues.length];
    final bg = HSLColor.fromAHSL(1, h, 0.28, dark ? 0.22 : 0.88).toColor();
    final fg = HSLColor.fromAHSL(1, h, dark ? 0.38 : 0.45, dark ? 0.68 : 0.30).toColor();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.md)),
      child: Text(
        title.isEmpty ? '?' : title.characters.first.toUpperCase(),
        style: TextStyle(fontFamily: Fonts.head, color: fg, fontWeight: FontWeight.w600, fontSize: size * 0.42),
      ),
    );
  }

  Widget _plain(BuildContext context, Brand? brand) {
    final c = AppColors.of(context);
    final Widget mark;
    if (brand != null && brand.multicolor) {
      mark = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => SweepGradient(startAngle: -0.7, endAngle: -0.7 + 6.2832, colors: brand.sweep!, stops: brand.stops).createShader(r),
        child: Icon(brand.icon, size: size * 0.8, color: Colors.white),
      );
    } else if (brand != null) {
      // Màu thương hiệu quá gần màu nền thẻ (đen trên nền tối, trắng trên nền sáng) thì dùng màu chữ.
      final contrast = (brand.color.computeLuminance() - c.card.computeLuminance()).abs();
      mark = Icon(brand.icon, size: size * 0.8, color: contrast < 0.15 ? c.fg : brand.color);
    } else {
      mark = Text(
        title.isEmpty ? '?' : title.characters.first.toUpperCase(),
        style: TextStyle(color: c.fg, fontWeight: FontWeight.w800, fontSize: size * 0.7, height: 1),
      );
    }
    return SizedBox.square(dimension: size, child: Center(child: mark));
  }
}

/// Một giây một lần cho cả app (không tạo bộ hẹn giờ riêng cho từng dòng).
class Clock extends StatefulWidget {
  const Clock({super.key, required this.builder});
  final Widget Function(BuildContext, DateTime) builder;

  @override
  State<Clock> createState() => _ClockState();
}

class _ClockState extends State<Clock> {
  late final ValueNotifier<DateTime> _now = ValueNotifier(DateTime.now());
  Timer? _align;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    // Căn mốc theo giây thật (không theo lúc mở màn), để mọi Clock trong app đổi số và vòng tròn cùng một nhịp.
    final msToNextSecond = 1000 - DateTime.now().millisecond;
    _align = Timer(Duration(milliseconds: msToNextSecond), () {
      _now.value = DateTime.now();
      _t = Timer.periodic(Timing.clockTick, (_) => _now.value = DateTime.now());
    });
  }

  @override
  void dispose() {
    _align?.cancel();
    _t?.cancel();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<DateTime>(valueListenable: _now, builder: (c, t, _) => widget.builder(c, t));
}

/// Mã 2FA có vòng đếm ngược; bấm để chép. Chạm được rộng (≥ 44 px) để dễ bấm.
class TotpChip extends StatelessWidget {
  const TotpChip({super.key, required this.params, required this.now, this.onNext, this.big = false, this.masked = false});
  final TotpParams params;
  final DateTime now;

  /// Chỉ với HOTP: lấy mã kế tiếp (tăng bộ đếm).
  final VoidCallback? onNext;

  /// Cỡ lớn (màn chi tiết, xem nhanh).
  final bool big;

  /// Ẩn các chữ số (••• •••). Bấm vẫn chép được mã mà không cần hiện ra.
  final bool masked;

  static String _mask(String code) {
    final dots = '•' * code.length;
    if (code.length == 6) return '${dots.substring(0, 3)} ${dots.substring(3)}';
    if (code.length == 8) return '${dots.substring(0, 4)} ${dots.substring(4)}';
    return dots;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final String code;
    try {
      code = Otp.code(params, now);
    } on Object {
      return Padding(padding: const EdgeInsets.all(Gap.sm), child: Text(tr('Khóa 2FA lỗi'), style: TextStyle(color: c.danger)));
    }
    final size = big ? 30.0 : 17.0;

    Widget codeText(Color color) => Text(
          masked ? _mask(code) : Otp.grouped(code),
          style: TextStyle(fontFamily: Fonts.mono, fontSize: size, fontWeight: FontWeight.w600, letterSpacing: big ? 2 : 0.5, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
        );

    if (params.isHotp) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _pill(context, onTap: () => copyText(context, code, what: tr('Đã chép mã 2FA')), child: codeText(c.fg)),
        if (onNext != null) IconButton(tooltip: tr('Mã kế tiếp'), icon: const Icon(Icons.skip_next), onPressed: onNext),
      ]);
    }

    final left = Otp.secondsRemaining(now, period: params.period);
    final frac = Otp.fractionRemaining(now, period: params.period);
    final urgent = left <= 5;
    final color = urgent ? c.danger : c.accent;
    return Semantics(
      button: true,
      label: masked ? tr('Mã 2FA đang ẩn. Bấm để chép') : tr('Mã 2FA {p0}, còn {p1} giây. Bấm để chép', {'p0': Otp.grouped(code), 'p1': left}),
      child: _pill(
        context,
        onTap: () => copyText(context, code, what: tr('Đã chép mã 2FA')),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // Chữ số dùng màu chữ chính (tương phản cao trên nền nhạt); màu nhấn chỉ dành cho vòng đếm.
          codeText(urgent ? c.danger : c.fg),
          SizedBox(width: big ? Gap.md : 10),
          // Cùng hướng và cùng kiểu quét với vòng ở danh sách (_PiePainter).
          SizedBox.square(
            dimension: big ? 26 : 20,
            child: CustomPaint(painter: _PiePainter(frac, color, c.line, stroke: big ? 3 : 2.5)),
          ),
        ]),
        tint: urgent ? c.danger.withValues(alpha: 0.10) : c.accentSoft,
      ),
    );
  }

  Widget _pill(BuildContext context, {required VoidCallback onTap, required Widget child, Color? tint}) {
    final c = AppColors.of(context);
    return Material(
      color: tint ?? c.accentSoft,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: big ? 56 : 44, minWidth: 44),
          child: Padding(padding: EdgeInsets.symmetric(horizontal: big ? Gap.xl : Gap.md, vertical: Gap.sm), child: Center(widthFactor: 1, child: child)),
        ),
      ),
    );
  }
}

/// Dòng mục dùng chung cho tab Kho và tab 2FA.
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, required this.now, required this.onTap, this.showCode = true, this.onNext, this.onLongPress, this.labels});
  final Item item;

  /// Thay (dòng chính, dòng phụ), dùng trong nhóm xếp chồng theo dịch vụ.
  final (String, String)? labels;
  final DateTime now;
  final VoidCallback onTap;
  final bool showCode;
  final VoidCallback? onNext;

  /// Nhấn giữ: hiện các thao tác nhanh.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = item.totp;
    final hasCode = showCode && t != null && t.secret.isNotEmpty;
    String? code;
    if (hasCode) {
      try {
        code = Otp.code(t, now);
      } on Object {
        code = null; // khóa lỗi: chạm thì mở mục như thường
      }
    }
    final current = code;
    final (title, subtitle) = labels ?? (item.title, item.subtitle);
    Widget name(TextStyle? style) => Row(children: [
          Flexible(child: Text(title, style: style)), // tên hiện đầy đủ, dài thì xuống dòng
          if (item.favorite) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.star_rounded, size: 16, color: c.warn)),
        ]);

    if (hasCode) {
      // Tab 2FA: trái là tên thương hiệu và tài khoản; phải là logo nhỏ ở trên, mã ở dưới. Chạm cả dòng là chép mã.
      final text = Theme.of(context).textTheme;
      return InkWell(
        onTap: current != null ? () => copyText(context, current, what: tr('Đã chép mã 2FA')) : onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                name(text.titleMedium),
                if (subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: text.bodyMedium?.copyWith(color: c.muted))),
              ]),
            ),
            const SizedBox(width: Gap.md),
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Avatar.forItem(item, size: 22, plain: true), // logo không nền, không viền
              const SizedBox(height: 6),
              TotpCode(params: t, now: now, onNext: onNext),
            ]),
          ]),
        ),
      );
    }

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      minVerticalPadding: Gap.md,
      // Icon loại mục nhỏ ở góc avatar: nhìn lướt là biết tài khoản, thẻ, Wi-Fi...
      leading: SizedBox(
        width: 40,
        height: 40,
        child: Stack(clipBehavior: Clip.none, children: [
          Avatar.forItem(item, plain: true), // logo không nền, không viền (giống tab 2FA)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(L.typeIcons[item.type], size: 12, color: c.accent, semanticLabel: L.type(item.type)),
            ),
          ),
        ]),
      ),
      title: name(null),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Mã 2FA trong danh sách: chữ số lớn không khung, hình tròn đếm ngược bên cạnh. Chạm vào dòng để chép (do dòng xử lý).
class TotpCode extends StatelessWidget {
  const TotpCode({super.key, required this.params, required this.now, this.onNext, this.compact = false});
  final bool compact;
  final TotpParams params;
  final DateTime now;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final String code;
    try {
      code = Otp.code(params, now);
    } on Object {
      return Text(tr('Khóa 2FA lỗi'), style: TextStyle(color: c.danger));
    }
    final style = TextStyle(fontFamily: Fonts.mono, fontSize: compact ? 16 : 22, fontWeight: FontWeight.w600, letterSpacing: 0.5, height: 1.1, fontFeatures: const [FontFeature.tabularFigures()]);

    if (params.isHotp) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(Otp.grouped(code), style: style.copyWith(color: c.accent)),
        if (onNext != null) IconButton(tooltip: tr('Mã kế tiếp'), icon: const Icon(Icons.skip_next), onPressed: onNext),
      ]);
    }

    final left = Otp.secondsRemaining(now, period: params.period);
    final frac = Otp.fractionRemaining(now, period: params.period);
    final color = left <= 5 ? c.danger : c.accent;
    return Semantics(
      label: tr('Mã 2FA {p0}, còn {p1} giây. Bấm để chép', {'p0': Otp.grouped(code), 'p1': left}),
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(Otp.grouped(code), style: style.copyWith(color: color)),
        const SizedBox(width: 10),
        // Hình tròn đặc thu nhỏ dần theo thời gian còn lại của mã.
        SizedBox.square(dimension: compact ? 15 : 18, child: CustomPaint(painter: _PiePainter(frac, color, c.line))),
      ]),
    );
  }
}

/// Vòng đếm ngược dùng chung. [stroke] = null: hình tròn đặc; có giá trị: vòng viền.
/// Luôn quét ngược chiều kim đồng hồ từ 12 giờ, để mọi màn hiển thị giống nhau.
class _PiePainter extends CustomPainter {
  _PiePainter(this.frac, this.color, this.track, {this.stroke});
  final double frac;
  final Color color;
  final Color track;
  final double? stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sweep = -2 * math.pi * frac.clamp(0.0, 1.0);
    final s = stroke;
    if (s == null) {
      canvas.drawOval(rect, Paint()..color = track);
      canvas.drawArc(rect, -math.pi / 2, sweep, true, Paint()..color = color);
      return;
    }
    final ring = rect.deflate(s / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s;
    canvas.drawOval(ring, base..color = track);
    canvas.drawArc(ring, -math.pi / 2, sweep, false, base..color = color);
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => old.frac != frac || old.color != color || old.track != track || old.stroke != stroke;
}
