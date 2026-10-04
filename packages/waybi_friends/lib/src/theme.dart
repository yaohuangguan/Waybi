import 'package:flutter/material.dart';

class WwhColors {
  static const cream = Color(0xFFF7F3E8);
  static const paper = Color(0xFFFFFCF5);
  static const ink = Color(0xFF23351D);
  static const moss = Color(0xFF496C32);
  static const lime = Color(0xFFD3F28D);
  static const sage = Color(0xFFC8D8B2);
  static const wood = Color(0xFFC98E5A);
  static const woodDark = Color(0xFF9E6742);
  static const sky = Color(0xFFBFE4E6);
  static const peach = Color(0xFFF0C9AA);
  static const softBlue = Color(0xFFD8E9F0);
  static const muted = Color(0xFF74806B);
}

ThemeData buildWaybiTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: WwhColors.cream,
    colorScheme: ColorScheme.fromSeed(
      seedColor: WwhColors.moss,
      brightness: Brightness.light,
      surface: WwhColors.paper,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 44,
        height: 1.02,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.8,
        color: WwhColors.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.12,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: WwhColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: WwhColors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: WwhColors.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: WwhColors.muted),
    ),
  );
}
