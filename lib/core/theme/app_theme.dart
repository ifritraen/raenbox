import 'package:flutter/material.dart';
import 'theme_presets.dart';

class AppTheme {
  static ThemePreset _currentPreset = ThemePreset.emeraldObsidian;
  static bool _isPureOled = false;

  static ThemePreset get currentPreset =>
      _isPureOled ? _currentPreset.toPureOled() : _currentPreset;

  static bool get isPureOled => _isPureOled;

  static void setPreset(ThemePreset preset, {bool isPureOled = false}) {
    _currentPreset = preset;
    _isPureOled = isPureOled;
  }

  // Dynamic Primary Backgrounds
  static Color get bgPrimary => currentPreset.bgPrimary;
  static Color get bgSecondary => currentPreset.bgSecondary;
  static Color get bgCard => currentPreset.bgCard;
  static Color get bgSurface => currentPreset.bgSurface;
  static Color get bgElevated => currentPreset.bgElevated;

  // Dynamic Accents
  static Color get accentCyan => currentPreset.accentSecondary;
  static Color get accentGreen => currentPreset.accent;
  static Color get brandGreen => currentPreset.brandPrimary;
  static Color get brandBlue => currentPreset.brandSecondary;

  // Dynamic Borders
  static Color get borderSubtle => currentPreset.borderSubtle;
  static Color get borderAccent => currentPreset.borderAccent;

  // Highlights & Badges
  static const Color badgeGold = Color(0xFFD9A404);
  static const Color liveRed = Color(0xFFCC3129);
  static const Color orangeHot = Color(0xFFF08028);

  // Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);

  // Dynamic Gradients
  static LinearGradient get brandGradient => LinearGradient(
        colors: [brandBlue, brandGreen],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );

  static LinearGradient get heroOverlayGradient => LinearGradient(
        colors: [Colors.transparent, bgPrimary],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  static LinearGradient get cyanGreenGradient => LinearGradient(
        colors: [accentCyan, accentGreen],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static ThemeData buildTheme(ThemePreset preset, {bool isPureOled = false}) {
    final effective = isPureOled ? preset.toPureOled() : preset;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: effective.bgPrimary,
      primaryColor: effective.brandPrimary,
      colorScheme: ColorScheme.dark(
        primary: effective.accent,
        secondary: effective.accentSecondary,
        surface: effective.bgSecondary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: effective.bgPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: effective.bgSecondary,
        selectedItemColor: effective.accent,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        color: effective.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: effective.borderSubtle, width: 0.8),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 24),
        headlineMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 20),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 14),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 12),
        bodySmall: TextStyle(color: textMuted, fontSize: 10),
      ),
    );
  }

  static ThemeData get darkTheme => buildTheme(_currentPreset, isPureOled: _isPureOled);
}
