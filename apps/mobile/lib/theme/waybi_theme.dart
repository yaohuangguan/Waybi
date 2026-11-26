import 'package:flutter/material.dart';

/// Shared colors and geometry for the Kiwi Lime identity.
///
/// These are raw brand values. Widgets should prefer the theme-aware tokens
/// ([ColorScheme], [WaybiStatusColors], [WaybiDriveTypography]) through the
/// [WaybiThemeContext] helpers, so light and dark mode stay legible.
abstract final class WaybiColors {
  static const sky = Color(0xFFD0F58A);
  static const coastal = Color(0xFF79A83B);
  static const ocean = Color(0xFF486B29);
  static const teal = Color(0xFF729F36);
  static const deepTeal = Color(0xFF496B32);
  static const deepOcean = Color(0xFF29441F);
  static const darkOcean = Color(0xFF20351C);
  static const midnightOcean = Color(0xFF152510);
  static const lightBackground = Color(0xFFF8FBEF);
  static const mist = Color(0xFFF1F7E2);
  static const ice = Color(0xFFEAF5CF);
  static const horizon = Color(0xFFAAD85F);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF23351D);
  static const lightTextSecondary = Color(0xFF64705B);
  static const lightBorder = Color(0xFFDBE5CB);
  static const darkSurface = Color(0xFF2C4325);
  static const darkText = Color(0xFFF8FBEF);
  static const darkTextSecondary = Color(0xFFCCDABD);
  static const darkBorder = Color(0xFF49613C);

  /// Map-line status hues (traffic, markers). They are not text-safe on light
  /// surfaces; use [WaybiStatusColors] for text, icons and chips.
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
}

/// Always-dark guidance surfaces (turn banner, Just Drive HUD, transit trip
/// header). They float over the map in both light and dark mode, so their
/// colours are fixed and checked for contrast against [surface].
abstract final class WaybiInk {
  static const surface = WaybiColors.darkOcean;
  static const raised = WaybiColors.darkSurface;
  static const text = Color(0xFFFFFFFF);
  static const muted = WaybiColors.darkTextSecondary;
  static const accent = WaybiColors.sky;
  static const border = WaybiColors.darkBorder;
  static const danger = Color(0xFFFCA5A5);
  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFFBBF24);
}

abstract final class WaybiSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
}

abstract final class WaybiRadius {
  static const control = 10.0;
  static const button = 14.0;
  static const panel = 18.0;
  static const sheet = 24.0;
}

/// Font-size tokens for places that still need a literal size.
///
/// [caption] is the smallest size allowed for any readable text.
abstract final class WaybiTextSize {
  static const caption = 12.0;
  static const body = 14.0;
  static const bodyLarge = 16.0;
  static const title = 18.0;
}

/// Minimum interactive size (Material / WCAG target size).
abstract final class WaybiTouch {
  static const minTarget = 48.0;
}

/// Status colours with text-safe foregrounds and on-colours.
///
/// * [success], [warning], [info], [danger]: icon/text colour on the theme's
///   surfaces (at least 4.5:1).
/// * `on*`: text on a filled status background.
/// * `*Container` / `on*Container`: tinted chip or banner and its text.
@immutable
class WaybiStatusColors extends ThemeExtension<WaybiStatusColors> {
  const WaybiStatusColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  static const light = WaybiStatusColors(
    success: Color(0xFF166534),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCFCE7),
    onSuccessContainer: Color(0xFF14532D),
    warning: Color(0xFF9A5806),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF78350F),
    info: Color(0xFF1D4ED8),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFDBEAFE),
    onInfoContainer: Color(0xFF1E3A8A),
    danger: Color(0xFFB91C1C),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFEE2E2),
    onDangerContainer: Color(0xFF7F1D1D),
  );

  static const dark = WaybiStatusColors(
    success: Color(0xFF4ADE80),
    onSuccess: Color(0xFF052E16),
    successContainer: Color(0xFF1C4A2A),
    onSuccessContainer: Color(0xFFBBF7D0),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF3B1D02),
    warningContainer: Color(0xFF4A3510),
    onWarningContainer: Color(0xFFFDE68A),
    info: Color(0xFF93C5FD),
    onInfo: Color(0xFF172554),
    infoContainer: Color(0xFF1E3A5F),
    onInfoContainer: Color(0xFFDBEAFE),
    danger: Color(0xFFFCA5A5),
    onDanger: Color(0xFF450A0A),
    dangerContainer: Color(0xFF5C1F1F),
    onDangerContainer: Color(0xFFFECACA),
  );

  /// The theme's status colours, falling back to the brightness default so
  /// widgets also work under a plain [ThemeData].
  static WaybiStatusColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<WaybiStatusColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  WaybiStatusColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? onDangerContainer,
  }) => WaybiStatusColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    info: info ?? this.info,
    onInfo: onInfo ?? this.onInfo,
    infoContainer: infoContainer ?? this.infoContainer,
    onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    danger: danger ?? this.danger,
    onDanger: onDanger ?? this.onDanger,
    dangerContainer: dangerContainer ?? this.dangerContainer,
    onDangerContainer: onDangerContainer ?? this.onDangerContainer,
  );

  @override
  WaybiStatusColors lerp(WaybiStatusColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return WaybiStatusColors(
      success: mix(success, other.success),
      onSuccess: mix(onSuccess, other.onSuccess),
      successContainer: mix(successContainer, other.successContainer),
      onSuccessContainer: mix(onSuccessContainer, other.onSuccessContainer),
      warning: mix(warning, other.warning),
      onWarning: mix(onWarning, other.onWarning),
      warningContainer: mix(warningContainer, other.warningContainer),
      onWarningContainer: mix(onWarningContainer, other.onWarningContainer),
      info: mix(info, other.info),
      onInfo: mix(onInfo, other.onInfo),
      infoContainer: mix(infoContainer, other.infoContainer),
      onInfoContainer: mix(onInfoContainer, other.onInfoContainer),
      danger: mix(danger, other.danger),
      onDanger: mix(onDanger, other.onDanger),
      dangerContainer: mix(dangerContainer, other.dangerContainer),
      onDangerContainer: mix(onDangerContainer, other.onDangerContainer),
    );
  }
}

/// Glanceable type scale for anything read while driving.
///
/// Styles carry size, weight and height only; callers add a colour that
/// contrasts with their surface (usually [WaybiInk]).
@immutable
class WaybiDriveTypography extends ThemeExtension<WaybiDriveTypography> {
  const WaybiDriveTypography({
    required this.distance,
    required this.instruction,
    required this.secondary,
    required this.value,
    required this.unit,
    required this.label,
    required this.notice,
  });

  /// Distance to the next manoeuvre.
  final TextStyle distance;

  /// The current manoeuvre instruction.
  final TextStyle instruction;

  /// The "then" instruction, remaining distance and similar secondary lines.
  final TextStyle secondary;

  /// Speed, ETA, remaining distance and other glanceable values.
  final TextStyle value;

  /// Units next to a [value].
  final TextStyle unit;

  /// Short labels above values ("Speed", "Remaining").
  final TextStyle label;

  /// Lane and data notices.
  final TextStyle notice;

  static const standard = WaybiDriveTypography(
    distance: TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800),
    instruction: TextStyle(
      fontSize: 18,
      height: 1.25,
      fontWeight: FontWeight.w700,
    ),
    secondary: TextStyle(
      fontSize: 16,
      height: 1.25,
      fontWeight: FontWeight.w600,
    ),
    value: TextStyle(fontSize: 24, height: 1.1, fontWeight: FontWeight.w800),
    unit: TextStyle(fontSize: 14, height: 1.1, fontWeight: FontWeight.w700),
    label: TextStyle(
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: .4,
    ),
    notice: TextStyle(fontSize: 16, height: 1.25, fontWeight: FontWeight.w600),
  );

  static WaybiDriveTypography of(BuildContext context) =>
      Theme.of(context).extension<WaybiDriveTypography>() ?? standard;

  @override
  WaybiDriveTypography copyWith({
    TextStyle? distance,
    TextStyle? instruction,
    TextStyle? secondary,
    TextStyle? value,
    TextStyle? unit,
    TextStyle? label,
    TextStyle? notice,
  }) => WaybiDriveTypography(
    distance: distance ?? this.distance,
    instruction: instruction ?? this.instruction,
    secondary: secondary ?? this.secondary,
    value: value ?? this.value,
    unit: unit ?? this.unit,
    label: label ?? this.label,
    notice: notice ?? this.notice,
  );

  @override
  WaybiDriveTypography lerp(WaybiDriveTypography? other, double t) {
    if (other == null) return this;
    TextStyle mix(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return WaybiDriveTypography(
      distance: mix(distance, other.distance),
      instruction: mix(instruction, other.instruction),
      secondary: mix(secondary, other.secondary),
      value: mix(value, other.value),
      unit: mix(unit, other.unit),
      label: mix(label, other.label),
      notice: mix(notice, other.notice),
    );
  }
}

/// Readable access to Waybi tokens: `context.status.warning`,
/// `context.driveType.value`, `context.colors.surface`.
extension WaybiThemeContext on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get textStyles => Theme.of(this).textTheme;
  WaybiStatusColors get status => WaybiStatusColors.of(this);
  WaybiDriveTypography get driveType => WaybiDriveTypography.of(this);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// The app text scale. Body text never goes below [WaybiTextSize.caption].
const waybiTextTheme = TextTheme(
  displayLarge: TextStyle(fontSize: 57, height: 1.12),
  displayMedium: TextStyle(fontSize: 45, height: 1.16),
  displaySmall: TextStyle(fontSize: 36, height: 1.22),
  headlineLarge: TextStyle(fontSize: 32, height: 1.25),
  headlineMedium: TextStyle(fontSize: 28, height: 1.29),
  headlineSmall: TextStyle(fontSize: 24, height: 1.33),
  titleLarge: TextStyle(fontSize: 22, height: 1.27),
  titleMedium: TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w600,
  ),
  titleSmall: TextStyle(
    fontSize: 14,
    height: 1.43,
    fontWeight: FontWeight.w600,
  ),
  bodyLarge: TextStyle(fontSize: 16, height: 1.5),
  bodyMedium: TextStyle(fontSize: 14, height: 1.43),
  bodySmall: TextStyle(fontSize: WaybiTextSize.caption, height: 1.35),
  labelLarge: TextStyle(
    fontSize: 14,
    height: 1.43,
    fontWeight: FontWeight.w600,
  ),
  labelMedium: TextStyle(
    fontSize: WaybiTextSize.caption,
    height: 1.33,
    fontWeight: FontWeight.w600,
  ),
  labelSmall: TextStyle(
    fontSize: WaybiTextSize.caption,
    height: 1.33,
    fontWeight: FontWeight.w600,
    letterSpacing: .3,
  ),
);

abstract final class WaybiTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData lightFor(String language) =>
      _build(Brightness.light, language);
  static ThemeData darkFor(String language) =>
      _build(Brightness.dark, language);

  static const chineseFontFallback = <String>[
    'PingFang SC',
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'Microsoft YaHei UI',
    'sans-serif',
  ];

  static ThemeData _build(Brightness brightness, [String language = 'en']) {
    final dark = brightness == Brightness.dark;
    final status = dark ? WaybiStatusColors.dark : WaybiStatusColors.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: WaybiColors.ocean,
      brightness: brightness,
      primary: dark ? WaybiColors.sky : WaybiColors.ocean,
      onPrimary: dark ? WaybiColors.midnightOcean : Colors.white,
      surface: dark ? WaybiColors.darkOcean : WaybiColors.lightSurface,
      onSurface: dark ? WaybiColors.darkText : WaybiColors.lightText,
      error: status.danger,
      onError: status.onDanger,
      errorContainer: status.dangerContainer,
      onErrorContainer: status.onDangerContainer,
    );
    return ThemeData(
      useMaterial3: true,
      textTheme: waybiTextTheme,
      extensions: <ThemeExtension<dynamic>>[
        status,
        WaybiDriveTypography.standard,
      ],
      fontFamily: language == 'zh' ? 'Hiragino Sans GB' : null,
      fontFamilyFallback: language == 'zh' ? chineseFontFallback : null,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? WaybiColors.midnightOcean
          : WaybiColors.lightBackground,
      dividerColor: dark ? WaybiColors.darkBorder : WaybiColors.lightBorder,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: dark
            ? WaybiColors.darkOcean
            : WaybiColors.lightBackground,
        foregroundColor: dark ? WaybiColors.darkText : WaybiColors.deepOcean,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? WaybiColors.darkSurface : WaybiColors.lightSurface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: dark ? WaybiColors.darkBorder : WaybiColors.lightBorder,
          ),
          borderRadius: BorderRadius.circular(WaybiRadius.panel),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark
            ? WaybiColors.darkSurface
            : WaybiColors.lightSurface,
        selectedColor: dark ? WaybiColors.deepTeal : WaybiColors.ice,
        side: BorderSide(
          color: dark ? WaybiColors.darkBorder : WaybiColors.lightBorder,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        labelStyle: TextStyle(
          color: dark ? WaybiColors.darkText : WaybiColors.deepOcean,
          fontWeight: FontWeight.w700,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return dark
                ? WaybiColors.darkTextSecondary.withValues(alpha: .45)
                : WaybiColors.lightTextSecondary.withValues(alpha: .45);
          }
          if (states.contains(WidgetState.selected)) {
            return dark ? WaybiColors.midnightOcean : Colors.white;
          }
          return dark ? WaybiColors.darkTextSecondary : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return dark
                ? WaybiColors.darkBorder.withValues(alpha: .45)
                : WaybiColors.lightBorder.withValues(alpha: .55);
          }
          if (states.contains(WidgetState.selected)) {
            return dark ? WaybiColors.sky : WaybiColors.ocean;
          }
          return dark ? WaybiColors.darkSurface : WaybiColors.lightBorder;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return dark ? WaybiColors.darkBorder : WaybiColors.lightBorder;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: dark
            ? WaybiColors.darkOcean
            : WaybiColors.lightSurface,
        indicatorColor: dark ? WaybiColors.deepTeal : WaybiColors.ice,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: WaybiTextSize.caption,
            fontWeight: FontWeight.w600,
            color: dark ? WaybiColors.darkText : WaybiColors.deepOcean,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? WaybiColors.darkSurface : WaybiColors.lightSurface,
        hintStyle: TextStyle(
          color: dark
              ? WaybiColors.darkTextSecondary
              : WaybiColors.lightTextSecondary,
        ),
        labelStyle: TextStyle(
          color: dark
              ? WaybiColors.darkTextSecondary
              : WaybiColors.lightTextSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WaybiRadius.button),
          borderSide: BorderSide(
            color: dark ? WaybiColors.darkBorder : WaybiColors.lightBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WaybiRadius.button),
          borderSide: BorderSide(
            color: dark ? WaybiColors.darkBorder : WaybiColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WaybiRadius.button),
          borderSide: BorderSide(
            color: dark ? WaybiColors.sky : WaybiColors.ocean,
            width: 1.6,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark
            ? WaybiColors.darkOcean
            : WaybiColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WaybiRadius.sheet),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark
            ? WaybiColors.darkOcean
            : WaybiColors.lightSurface,
        modalBackgroundColor: dark
            ? WaybiColors.darkOcean
            : WaybiColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dividerTheme: DividerThemeData(
        color: dark ? WaybiColors.darkBorder : WaybiColors.lightBorder,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: dark ? WaybiColors.sky : WaybiColors.deepOcean,
        textColor: dark ? WaybiColors.darkText : WaybiColors.lightText,
      ),
    );
  }
}
