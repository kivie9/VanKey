import 'package:material_ui/material_ui.dart';

/// Khoảng cách chuẩn (bội của 4). Dùng thay cho số rời rạc trong từng màn hình.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Bo góc chuẩn.
abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

/// Màu nhấn có thể chọn. Màu đầu (xanh ngọc) là màu của prototype.
const accentColors = [0xFF0B7A6B, 0xFF4F6BED, 0xFF2563EB, 0xFF7C3AED, 0xFFDB2777, 0xFFEA580C];

/// Bộ màu theo ngữ nghĩa (lấy từ prototype). Mọi màn hình lấy màu qua đây hoặc qua `Theme.of(context).colorScheme`,
/// không viết mã màu rời trong màn hình.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.page,
    required this.card,
    required this.field,
    required this.line,
    required this.fg,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.warn,
    required this.danger,
    required this.success,
  });

  /// Nền toàn trang.
  final Color page;

  /// Nền thẻ, hộp thoại, thanh dưới.
  final Color card;

  /// Nền ô nhập và các khối phụ.
  final Color field;

  /// Đường kẻ mảnh.
  final Color line;
  final Color fg;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color warn;
  final Color danger;
  final Color success;

  /// Nếu ngữ cảnh không có theme của VanKey (ví dụ test dùng MaterialApp trần) thì dùng bộ màu mặc định.
  static AppColors of(BuildContext context) {
    final t = Theme.of(context);
    return t.extension<AppColors>() ?? AppColors.forBrightness(t.brightness, 0);
  }

  static AppColors forBrightness(Brightness b, int accentIndex) {
    final base = Color(accentColors[accentIndex.clamp(0, accentColors.length - 1)]);
    if (b == Brightness.light) {
      return AppColors(
        page: const Color(0xFFF4F5F7),
        card: const Color(0xFFFFFFFF),
        field: const Color(0x0F000000), // đen 6%
        line: const Color(0xFFE3E6EA),
        fg: const Color(0xFF15171A),
        muted: const Color(0xFF6B7280),
        accent: base,
        onAccent: Colors.white,
        accentSoft: Color.alphaBlend(base.withValues(alpha: 0.12), Colors.white),
        warn: const Color(0xFFB45309),
        danger: const Color(0xFFB42318),
        success: const Color(0xFF15803D),
      );
    }
    // Giao diện tối: nền gần đen (tiết kiệm pin OLED), chữ xám sáng thay vì trắng tinh để đỡ lóa,
    // màu nhấn dịu hơn. Độ tương phản vẫn đạt mức đọc thoải mái (chữ chính ≈ 14:1, chữ phụ ≈ 6:1).
    final isTeal = accentIndex == 0;
    final hsl = HSLColor.fromColor(base);
    final accent = isTeal ? const Color(0xFF3DB5A0) : hsl.withLightness(0.60).withSaturation((hsl.saturation * 0.75).clamp(0, 1)).toColor();
    return AppColors(
      page: const Color(0xFF0B0B0D),
      card: const Color(0xFF141418),
      field: const Color(0x0DFFFFFF), // trắng 5%
      line: const Color(0xFF26262C),
      fg: const Color(0xFFC6C9CF),
      muted: const Color(0xFF858891),
      accent: accent,
      onAccent: HSLColor.fromColor(accent).withLightness(0.07).toColor(),
      accentSoft: Color.alphaBlend(accent.withValues(alpha: 0.13), const Color(0xFF141418)),
      warn: const Color(0xFFDDA050),
      danger: const Color(0xFFE8857A),
      success: const Color(0xFF58BE86),
    );
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => this;
}

abstract final class AppTheme {
  /// [fontFamily]: để trống = phông hệ thống (Roboto trên Android). Chỉ test chụp ảnh mới truyền vào.
  static ThemeData build(Brightness b, int accentIndex, {String? fontFamily}) {
    final c = AppColors.forBrightness(b, accentIndex);
    final dark = b == Brightness.dark;

    final scheme = ColorScheme(
      brightness: b,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      secondaryContainer: c.accentSoft,
      onSecondaryContainer: c.accent,
      tertiary: c.warn,
      onTertiary: Colors.black,
      error: c.danger,
      onError: dark ? Colors.black : Colors.white,
      errorContainer: dark ? const Color(0xFF2A1311) : const Color(0xFFFDECEA),
      onErrorContainer: c.danger,
      surface: c.card,
      onSurface: c.fg,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.page,
      surfaceContainerLow: c.card,
      surfaceContainer: c.card,
      surfaceContainerHigh: c.card,
      surfaceContainerHighest: Color.alphaBlend(c.field, c.card),
      outline: c.muted,
      outlineVariant: c.line,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: c.fg,
      onInverseSurface: c.page,
      inversePrimary: c.accent,
      surfaceTint: Colors.transparent, // tắt lớp phủ màu theo độ cao của Material 3
    );

    // Ô nhập dạng viền: nhãn nổi lên góc trên bên trái và cắt ngang đường viền. Phân vùng bằng màu nền, không viền (chỉ lỗi mới có viền đỏ).
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: color, width: width));
    final noBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none);

    final text = _textTheme(c, fontFamily);
    // Không viền: thẻ tách khỏi nền trang nhờ khác màu nền.
    final cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg));

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      extensions: [c],
      scaffoldBackgroundColor: c.page,
      canvasColor: c.card,
      dividerColor: c.line,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: text,
      primaryTextTheme: text,

      appBarTheme: AppBarTheme(
        backgroundColor: c.page,
        foregroundColor: c.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: c.fg),
      ),
      cardTheme: CardThemeData(color: c.card, elevation: 0, margin: EdgeInsets.zero, shape: cardShape, clipBehavior: Clip.antiAlias),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.muted, size: 22),
      listTileTheme: ListTileThemeData(
        iconColor: c.muted,
        textColor: c.fg,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: c.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 2),
        minVerticalPadding: Gap.sm,
        shape: const RoundedRectangleBorder(),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.field,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 16),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        border: noBorder,
        enabledBorder: noBorder,
        focusedBorder: noBorder,
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger),
        disabledBorder: noBorder,
        labelStyle: text.bodyLarge?.copyWith(color: c.muted),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: c.accent, fontWeight: FontWeight.w500),
        hintStyle: text.bodyLarge?.copyWith(color: c.muted.withValues(alpha: 0.7)),
        helperStyle: text.bodySmall?.copyWith(color: c.muted),
        errorStyle: text.bodySmall?.copyWith(color: c.danger),
        prefixIconColor: c.muted,
        suffixIconColor: c.muted,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.line,
          disabledForegroundColor: c.muted,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.fg,
          disabledForegroundColor: c.muted,
          side: BorderSide.none,
          backgroundColor: c.card,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.muted, minimumSize: const Size(44, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md))),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 0,
        highlightElevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        shape: const CircleBorder(),
        sizeConstraints: const BoxConstraints.tightFor(width: 58, height: 58),
        smallSizeConstraints: const BoxConstraints.tightFor(width: 44, height: 44),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.card,
        selectedColor: c.accentSoft,
        disabledColor: c.line,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill)),
        labelStyle: text.bodyMedium?.copyWith(color: c.fg, fontWeight: FontWeight.w500),
        secondaryLabelStyle: text.bodyMedium?.copyWith(color: c.accent, fontWeight: FontWeight.w600),
        checkmarkColor: c.accent,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
        elevation: 0,
        pressElevation: 0,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md))),
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentSoft : c.card),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.fg),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onAccent : c.muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.line),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onAccent),
        side: BorderSide(color: c.muted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      sliderTheme: SliderThemeData(activeTrackColor: c.accent, thumbColor: c.accent, inactiveTrackColor: c.line, overlayColor: c.accent.withValues(alpha: 0.12)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.line, circularTrackColor: c.line),

      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 19),
        contentTextStyle: text.bodyLarge?.copyWith(color: c.muted),
        actionsPadding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.line,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.card,
        elevation: 4,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        textStyle: text.bodyLarge,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: BorderSide(color: c.line))),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: BorderSide(color: c.line))),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.fg,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.page),
        actionTextColor: c.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        elevation: 4,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.fg, borderRadius: BorderRadius.circular(Radii.sm)),
        textStyle: text.bodySmall?.copyWith(color: c.page),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: c.muted,
        collapsedIconColor: c.muted,
        tilePadding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSoft,
        height: 68,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.accent : c.muted, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium?.copyWith(color: s.contains(WidgetState.selected) ? c.accent : c.muted, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.card,
        indicatorColor: c.accentSoft,
        selectedIconTheme: IconThemeData(color: c.accent),
        unselectedIconTheme: IconThemeData(color: c.muted),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: c.accent, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: c.muted),
      ),
      badgeTheme: BadgeThemeData(backgroundColor: c.danger, textColor: dark ? Colors.black : Colors.white),
    );
  }

  static TextTheme _textTheme(AppColors c, String? family) {
    TextStyle s(double size, FontWeight w, {double? h, double ls = 0, Color? color}) =>
        TextStyle(fontFamily: family, fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: color ?? c.fg);
    return TextTheme(
      displaySmall: s(30, FontWeight.w800, h: 1.15, ls: -0.5),
      headlineLarge: s(28, FontWeight.w800, h: 1.2, ls: -0.4),
      headlineMedium: s(24, FontWeight.w800, h: 1.2, ls: -0.3),
      headlineSmall: s(21, FontWeight.w700, h: 1.25, ls: -0.2),
      titleLarge: s(21, FontWeight.w700, h: 1.25, ls: -0.2),
      titleMedium: s(16, FontWeight.w600, h: 1.3),
      titleSmall: s(14, FontWeight.w600, h: 1.3, color: c.muted),
      bodyLarge: s(15.5, FontWeight.w400, h: 1.35),
      bodyMedium: s(14, FontWeight.w400, h: 1.35),
      bodySmall: s(12.5, FontWeight.w400, h: 1.3, color: c.muted),
      labelLarge: s(15, FontWeight.w600, h: 1.2),
      labelMedium: s(12.5, FontWeight.w600, h: 1.2, ls: 0.2),
      labelSmall: s(11, FontWeight.w600, h: 1.2, ls: 0.4, color: c.muted),
    );
  }
}
