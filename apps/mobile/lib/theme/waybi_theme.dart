import 'package:flutter/material.dart';

/// Shared colors and geometry for the Kiwi Lime identity.
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
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
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
    final scheme = ColorScheme.fromSeed(
      seedColor: WaybiColors.ocean,
      brightness: brightness,
      primary: dark ? WaybiColors.sky : WaybiColors.ocean,
      onPrimary: dark ? WaybiColors.midnightOcean : Colors.white,
      surface: dark ? WaybiColors.darkOcean : WaybiColors.lightSurface,
      onSurface: dark ? WaybiColors.darkText : WaybiColors.lightText,
      error: WaybiColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
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
            fontSize: 11,
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
