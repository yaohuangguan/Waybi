import 'package:flutter/material.dart';

/// Shared colors and geometry for the Kiwi Lime identity.
abstract final class KiwiLensColors {
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

abstract final class KiwiLensSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
}

abstract final class KiwiLensRadius {
  static const control = 10.0;
  static const button = 14.0;
  static const panel = 18.0;
  static const sheet = 24.0;
}

abstract final class KiwiLensTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: KiwiLensColors.ocean,
      brightness: brightness,
      primary: dark ? KiwiLensColors.sky : KiwiLensColors.ocean,
      onPrimary: dark ? KiwiLensColors.midnightOcean : Colors.white,
      surface: dark ? KiwiLensColors.darkOcean : KiwiLensColors.lightSurface,
      onSurface: dark ? KiwiLensColors.darkText : KiwiLensColors.lightText,
      error: KiwiLensColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? KiwiLensColors.midnightOcean
          : KiwiLensColors.lightBackground,
      dividerColor: dark
          ? KiwiLensColors.darkBorder
          : KiwiLensColors.lightBorder,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: dark
            ? KiwiLensColors.darkOcean
            : KiwiLensColors.lightBackground,
        foregroundColor: dark
            ? KiwiLensColors.darkText
            : KiwiLensColors.deepOcean,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? KiwiLensColors.darkSurface : KiwiLensColors.lightSurface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: dark
                ? KiwiLensColors.darkBorder
                : KiwiLensColors.lightBorder,
          ),
          borderRadius: BorderRadius.circular(KiwiLensRadius.panel),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark
            ? KiwiLensColors.darkSurface
            : KiwiLensColors.lightSurface,
        selectedColor: dark ? KiwiLensColors.deepTeal : KiwiLensColors.ice,
        side: BorderSide(
          color: dark ? KiwiLensColors.darkBorder : KiwiLensColors.lightBorder,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        labelStyle: TextStyle(
          color: dark ? KiwiLensColors.darkText : KiwiLensColors.deepOcean,
          fontWeight: FontWeight.w700,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return dark
                ? KiwiLensColors.darkTextSecondary.withValues(alpha: .45)
                : KiwiLensColors.lightTextSecondary.withValues(alpha: .45);
          }
          if (states.contains(WidgetState.selected)) {
            return dark ? KiwiLensColors.midnightOcean : Colors.white;
          }
          return dark ? KiwiLensColors.darkTextSecondary : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return dark
                ? KiwiLensColors.darkBorder.withValues(alpha: .45)
                : KiwiLensColors.lightBorder.withValues(alpha: .55);
          }
          if (states.contains(WidgetState.selected)) {
            return dark ? KiwiLensColors.sky : KiwiLensColors.ocean;
          }
          return dark ? KiwiLensColors.darkSurface : KiwiLensColors.lightBorder;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return dark ? KiwiLensColors.darkBorder : KiwiLensColors.lightBorder;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: dark
            ? KiwiLensColors.darkOcean
            : KiwiLensColors.lightSurface,
        indicatorColor: dark ? KiwiLensColors.deepTeal : KiwiLensColors.ice,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: dark ? KiwiLensColors.darkText : KiwiLensColors.deepOcean,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? KiwiLensColors.darkSurface
            : KiwiLensColors.lightSurface,
        hintStyle: TextStyle(
          color: dark
              ? KiwiLensColors.darkTextSecondary
              : KiwiLensColors.lightTextSecondary,
        ),
        labelStyle: TextStyle(
          color: dark
              ? KiwiLensColors.darkTextSecondary
              : KiwiLensColors.lightTextSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiwiLensRadius.button),
          borderSide: BorderSide(
            color: dark
                ? KiwiLensColors.darkBorder
                : KiwiLensColors.lightBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiwiLensRadius.button),
          borderSide: BorderSide(
            color: dark
                ? KiwiLensColors.darkBorder
                : KiwiLensColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KiwiLensRadius.button),
          borderSide: BorderSide(
            color: dark ? KiwiLensColors.sky : KiwiLensColors.ocean,
            width: 1.6,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark
            ? KiwiLensColors.darkOcean
            : KiwiLensColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KiwiLensRadius.sheet),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark
            ? KiwiLensColors.darkOcean
            : KiwiLensColors.lightSurface,
        modalBackgroundColor: dark
            ? KiwiLensColors.darkOcean
            : KiwiLensColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dividerTheme: DividerThemeData(
        color: dark ? KiwiLensColors.darkBorder : KiwiLensColors.lightBorder,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: dark ? KiwiLensColors.sky : KiwiLensColors.deepOcean,
        textColor: dark ? KiwiLensColors.darkText : KiwiLensColors.lightText,
      ),
    );
  }
}
