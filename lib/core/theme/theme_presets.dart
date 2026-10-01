import 'package:flutter/material.dart';

class ThemePreset {
  final String id;
  final String name;
  final String subtitle;
  final String icon;
  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgCard;
  final Color bgSurface;
  final Color bgElevated;
  final Color accent;
  final Color accentSecondary;
  final Color brandPrimary;
  final Color brandSecondary;
  final Color borderSubtle;
  final Color borderAccent;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgCard,
    required this.bgSurface,
    required this.bgElevated,
    required this.accent,
    required this.accentSecondary,
    required this.brandPrimary,
    required this.brandSecondary,
    this.borderSubtle = const Color(0x24FFFFFF),
    Color? borderAccent,
  }) : borderAccent = borderAccent ?? accent;

  /// Return a pure OLED variation where backgrounds become true pitch black (#000000)
  ThemePreset toPureOled() {
    return ThemePreset(
      id: id,
      name: name,
      subtitle: subtitle,
      icon: icon,
      bgPrimary: const Color(0xFF000000),
      bgSecondary: const Color(0xFF0A0A0A),
      bgCard: const Color(0xFF141414),
      bgSurface: const Color(0xFF1E1E1E),
      bgElevated: const Color(0xFF282828),
      accent: accent,
      accentSecondary: accentSecondary,
      brandPrimary: brandPrimary,
      brandSecondary: brandSecondary,
      borderSubtle: const Color(0x30303030),
      borderAccent: accent.withValues(alpha: 0.35),
    );
  }

  // Pre-configured 6 Cinema Dark & OLED Presets
  static const ThemePreset emeraldObsidian = ThemePreset(
    id: 'emerald_obsidian',
    name: 'Emerald Obsidian',
    subtitle: 'Cyber Emerald & Deep Charcoal',
    icon: '💎',
    bgPrimary: Color(0xFF101114),
    bgSecondary: Color(0xFF1C1E21),
    bgCard: Color(0xFF232936),
    bgSurface: Color(0xFF2B2E39),
    bgElevated: Color(0xFF383A40),
    accent: Color(0xFF2FF58B),
    accentSecondary: Color(0xFF1CB7FF),
    brandPrimary: Color(0xFF10A84D),
    brandSecondary: Color(0xFF2166E5),
    borderSubtle: Color(0x24FFFFFF),
    borderAccent: Color(0x401CB7FF),
  );

  static const ThemePreset pureOled = ThemePreset(
    id: 'pure_oled',
    name: 'Pure OLED Black',
    subtitle: 'Pitch Black & Electric Mint',
    icon: '⚡',
    bgPrimary: Color(0xFF000000),
    bgSecondary: Color(0xFF0A0A0A),
    bgCard: Color(0xFF141414),
    bgSurface: Color(0xFF1E1E1E),
    bgElevated: Color(0xFF282828),
    accent: Color(0xFF00FFA3),
    accentSecondary: Color(0xFF00E5FF),
    brandPrimary: Color(0xFF00C853),
    brandSecondary: Color(0xFF0091EA),
    borderSubtle: Color(0x2AFFFFFF),
    borderAccent: Color(0x4D00FFA3),
  );

  static const ThemePreset crimsonVelvet = ThemePreset(
    id: 'crimson_velvet',
    name: 'Crimson Velvet',
    subtitle: 'Cinematic Scarlet & Ruby Red',
    icon: '🍿',
    bgPrimary: Color(0xFF11080A),
    bgSecondary: Color(0xFF1E0E12),
    bgCard: Color(0xFF2A151A),
    bgSurface: Color(0xFF381C23),
    bgElevated: Color(0xFF45222B),
    accent: Color(0xFFE50914),
    accentSecondary: Color(0xFFFF4B55),
    brandPrimary: Color(0xFFB71C1C),
    brandSecondary: Color(0xFF7F0000),
    borderSubtle: Color(0x2EFFFFFF),
    borderAccent: Color(0x4DE50914),
  );

  static const ThemePreset cyberCyan = ThemePreset(
    id: 'cyber_cyan',
    name: 'Cyber Cyan',
    subtitle: 'Oceanic Midnight & Electric Cyan',
    icon: '🌊',
    bgPrimary: Color(0xFF080E18),
    bgSecondary: Color(0xFF0F1826),
    bgCard: Color(0xFF172437),
    bgSurface: Color(0xFF1E3048),
    bgElevated: Color(0xFF283F5E),
    accent: Color(0xFF00D8FF),
    accentSecondary: Color(0xFF38EF7D),
    brandPrimary: Color(0xFF0288D1),
    brandSecondary: Color(0xFF01579B),
    borderSubtle: Color(0x28FFFFFF),
    borderAccent: Color(0x4D00D8FF),
  );

  static const ThemePreset midnightAmethyst = ThemePreset(
    id: 'midnight_amethyst',
    name: 'Midnight Amethyst',
    subtitle: 'Cosmic Indigo & Royal Violet',
    icon: '🔮',
    bgPrimary: Color(0xFF0E0B18),
    bgSecondary: Color(0xFF171226),
    bgCard: Color(0xFF221B37),
    bgSurface: Color(0xFF2F254B),
    bgElevated: Color(0xFF3E3162),
    accent: Color(0xFFA855F7),
    accentSecondary: Color(0xFFEC4899),
    brandPrimary: Color(0xFF7C3AED),
    brandSecondary: Color(0xFF5B21B6),
    borderSubtle: Color(0x28FFFFFF),
    borderAccent: Color(0x4DA855F7),
  );

  static const ThemePreset sunsetAmber = ThemePreset(
    id: 'sunset_amber',
    name: 'Sunset Amber',
    subtitle: 'Espresso Obsidian & Golden Amber',
    icon: '🍯',
    bgPrimary: Color(0xFF13100D),
    bgSecondary: Color(0xFF1E1914),
    bgCard: Color(0xFF2B231C),
    bgSurface: Color(0xFF3A3026),
    bgElevated: Color(0xFF4C3E31),
    accent: Color(0xFFF59E0B),
    accentSecondary: Color(0xFFFFB74D),
    brandPrimary: Color(0xFFD97706),
    brandSecondary: Color(0xFFB45309),
    borderSubtle: Color(0x28FFFFFF),
    borderAccent: Color(0x4DF59E0B),
  );

  static const List<ThemePreset> allPresets = [
    emeraldObsidian,
    pureOled,
    crimsonVelvet,
    cyberCyan,
    midnightAmethyst,
    sunsetAmber,
  ];

  static ThemePreset getById(String id) {
    return allPresets.firstWhere(
      (p) => p.id == id,
      orElse: () => emeraldObsidian,
    );
  }
}
