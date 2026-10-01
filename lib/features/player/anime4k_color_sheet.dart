import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/player/player_shaders.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/local_storage_service.dart';

export '../../core/player/player_shaders.dart' show Anime4kMode, Anime4kQuality, PlayerShaders;

class ColorProfileConfig {
  final String id;
  final String name;
  final bool isCustom;
  final int brightness; // -100 to 100
  final int contrast; // -100 to 100
  final int saturation; // -100 to 100
  final int gamma; // -100 to 100
  final int hue; // -180 to 180

  const ColorProfileConfig({
    required this.id,
    required this.name,
    this.isCustom = false,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.gamma = 0,
    this.hue = 0,
  });

  ColorProfileConfig copyWith({
    String? id,
    String? name,
    bool? isCustom,
    int? brightness,
    int? contrast,
    int? saturation,
    int? gamma,
    int? hue,
  }) {
    return ColorProfileConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      isCustom: isCustom ?? this.isCustom,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      gamma: gamma ?? this.gamma,
      hue: hue ?? this.hue,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isCustom': isCustom,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'gamma': gamma,
        'hue': hue,
      };

  factory ColorProfileConfig.fromJson(Map<String, dynamic> json) {
    return ColorProfileConfig(
      id: json['id']?.toString() ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name']?.toString() ?? 'Custom Profile',
      isCustom: json['isCustom'] == true,
      brightness: (json['brightness'] as num?)?.toInt() ?? 0,
      contrast: (json['contrast'] as num?)?.toInt() ?? 0,
      saturation: (json['saturation'] as num?)?.toInt() ?? 0,
      gamma: (json['gamma'] as num?)?.toInt() ?? 0,
      hue: (json['hue'] as num?)?.toInt() ?? 0,
    );
  }
}

class ColorProfileRegistry {
  static const Map<String, ColorProfileConfig> builtInPresets = {
    'natural': ColorProfileConfig(
      id: 'natural',
      name: 'Natural',
      brightness: 0,
      contrast: 0,
      saturation: 0,
      gamma: 0,
      hue: 0,
    ),
    'cinema': ColorProfileConfig(
      id: 'cinema',
      name: 'Cinema',
      brightness: 2,
      contrast: 12,
      saturation: 8,
      gamma: 5,
      hue: 0,
    ),
    'cinema_dark': ColorProfileConfig(
      id: 'cinema_dark',
      name: 'Cinema Dark',
      brightness: -12,
      contrast: 18,
      saturation: 6,
      gamma: 12,
      hue: -1,
    ),
    'cinema_hdr': ColorProfileConfig(
      id: 'cinema_hdr',
      name: 'Cinema HDR',
      brightness: 5,
      contrast: 22,
      saturation: 12,
      gamma: 3,
      hue: -1,
    ),
    'anime': ColorProfileConfig(
      id: 'anime',
      name: 'Anime',
      brightness: 10,
      contrast: 22,
      saturation: 30,
      gamma: -3,
      hue: 3,
    ),
    'anime_vibrant': ColorProfileConfig(
      id: 'anime_vibrant',
      name: 'Anime Vibrant',
      brightness: 14,
      contrast: 28,
      saturation: 42,
      gamma: -6,
      hue: 4,
    ),
    'anime_soft': ColorProfileConfig(
      id: 'anime_soft',
      name: 'Anime Soft',
      brightness: 8,
      contrast: 16,
      saturation: 25,
      gamma: -1,
      hue: 2,
    ),
    'anime_4k': ColorProfileConfig(
      id: 'anime_4k',
      name: 'Anime 4K',
      brightness: 0,
      contrast: 20,
      saturation: 50,
      gamma: 1,
      hue: 2,
    ),
    'vivid': ColorProfileConfig(
      id: 'vivid',
      name: 'Vivid',
      brightness: 8,
      contrast: 25,
      saturation: 35,
      gamma: 2,
      hue: 1,
    ),
    'vivid_pop': ColorProfileConfig(
      id: 'vivid_pop',
      name: 'Vivid Pop',
      brightness: 12,
      contrast: 32,
      saturation: 48,
      gamma: 4,
      hue: 2,
    ),
    'vivid_warm': ColorProfileConfig(
      id: 'vivid_warm',
      name: 'Vivid Warm',
      brightness: 6,
      contrast: 24,
      saturation: 32,
      gamma: 1,
      hue: 8,
    ),
    'dark': ColorProfileConfig(
      id: 'dark',
      name: 'Dark Mode',
      brightness: -18,
      contrast: 15,
      saturation: -8,
      gamma: 15,
      hue: -2,
    ),
    'warm': ColorProfileConfig(
      id: 'warm',
      name: 'Warm Tones',
      brightness: 3,
      contrast: 10,
      saturation: 15,
      gamma: 2,
      hue: 6,
    ),
    'cool': ColorProfileConfig(
      id: 'cool',
      name: 'Cool Tones',
      brightness: 1,
      contrast: 8,
      saturation: 12,
      gamma: 1,
      hue: -6,
    ),
    'grayscale': ColorProfileConfig(
      id: 'grayscale',
      name: 'Grayscale',
      brightness: 2,
      contrast: 20,
      saturation: -100,
      gamma: 8,
      hue: 0,
    ),
  };

  static const Map<String, String> presetDescriptions = {
    'natural': 'Default balanced studio calibration',
    'cinema': 'Balanced colors for movie theater viewing',
    'cinema_dark': 'Optimized for dark room cinema viewing',
    'cinema_hdr': 'Enhanced cinema with HDR-like contrast',
    'anime': 'Enhanced line color & separation for anime',
    'anime_vibrant': 'Maximum vibrancy & saturation for colorful anime',
    'anime_soft': 'Gentle pastels & smooth gradients for soft anime',
    'anime_4k': 'Ultra-sharp clarity with punchy 4K vibrancy',
    'vivid': 'Bright, punchy, high-contrast dynamic colors',
    'vivid_pop': 'Maximum eye-catching pop & vibrant tones',
    'vivid_warm': 'Vivid saturation with warm sunset temperature',
    'dark': 'Dimmed brightness optimized for late-night viewing',
    'warm': 'Cozy warm colors reducing eye strain',
    'cool': 'Crisp cool blue spectrum for modern action',
    'grayscale': 'Classic noir black & white presentation',
  };

  static const Map<String, IconData> presetIcons = {
    'natural': Icons.nature,
    'cinema': Icons.movie,
    'cinema_dark': Icons.movie_outlined,
    'cinema_hdr': Icons.hdr_on,
    'anime': Icons.animation,
    'anime_vibrant': Icons.color_lens,
    'anime_soft': Icons.blur_on,
    'anime_4k': Icons.four_k,
    'vivid': Icons.palette,
    'vivid_pop': Icons.auto_awesome,
    'vivid_warm': Icons.wb_sunny,
    'dark': Icons.dark_mode,
    'warm': Icons.wb_incandescent,
    'cool': Icons.ac_unit,
    'grayscale': Icons.gradient,
  };

  /// Computes a 4x5 ColorFilter matrix combining the color profile and Anime4K visual adjustments
  static List<double> computeColorMatrix({
    required ColorProfileConfig profile,
    required Anime4kMode anime4kMode,
    required Anime4kQuality anime4kQuality,
  }) {
    // 1. Calculate base parameters
    double b = profile.brightness.toDouble();
    double c = profile.contrast.toDouble();
    double s = profile.saturation.toDouble();
    double g = profile.gamma.toDouble();
    double h = profile.hue.toDouble();

    // 2. Modulate visual enhancement according to Anime4K mode
    if (anime4kMode != Anime4kMode.off) {
      final isHq = anime4kQuality == Anime4kQuality.hq;
      final qMult = isHq ? 1.35 : 1.0;

      switch (anime4kMode) {
        case Anime4kMode.modeA: // Line reconstruction & sharpening
          c += 14 * qMult;
          s += 12 * qMult;
          b += 2 * qMult;
          break;
        case Anime4kMode.modeB: // Soft lines
          c += 8 * qMult;
          s += 10 * qMult;
          g -= 4 * qMult;
          break;
        case Anime4kMode.modeC: // Denoise + upscale
          c += 12 * qMult;
          s += 15 * qMult;
          b += 4 * qMult;
          break;
        case Anime4kMode.modeAA: // Double line reconstruction
          c += 22 * qMult;
          s += 20 * qMult;
          b += 4 * qMult;
          break;
        case Anime4kMode.modeBB: // Double soft reconstruction
          c += 15 * qMult;
          s += 16 * qMult;
          g -= 6 * qMult;
          break;
        case Anime4kMode.modeCA: // Denoise + line reconstruction
          c += 18 * qMult;
          s += 18 * qMult;
          b += 3 * qMult;
          break;
        case Anime4kMode.off:
          break;
      }
    }

    // 3. Contrast multiplier & offset
    final contrastFactor = (1.0 + (c / 100.0)).clamp(0.1, 3.0);
    final contrastOffset = 128.0 * (1.0 - contrastFactor);

    // 4. Brightness offset
    final brightnessOffset = (b / 100.0) * 255.0;

    // 5. Saturation factor (ITU-R BT.709 luminance weights)
    final sat = (1.0 + (s / 100.0)).clamp(0.0, 3.0);
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;

    final sr = (1.0 - sat) * lr;
    final sg = (1.0 - sat) * lg;
    final sb = (1.0 - sat) * lb;

    // 6. Hue rotation matrix around gray axis
    final hueRad = h * math.pi / 180.0;
    final cosH = math.cos(hueRad);
    final sinH = math.sin(hueRad);

    final hr00 = 0.213 + cosH * 0.787 - sinH * 0.213;
    final hr01 = 0.715 - cosH * 0.715 - sinH * 0.715;
    final hr02 = 0.072 - cosH * 0.072 + sinH * 0.928;

    final hr10 = 0.213 - cosH * 0.213 + sinH * 0.143;
    final hr11 = 0.715 + cosH * 0.285 + sinH * 0.140;
    final hr12 = 0.072 - cosH * 0.072 - sinH * 0.283;

    final hr20 = 0.213 - cosH * 0.213 - sinH * 0.787;
    final hr21 = 0.715 - cosH * 0.715 + sinH * 0.715;
    final hr22 = 0.072 + cosH * 0.928 + sinH * 0.072;

    // 7. Gamma modulation
    final gammaMult = (1.0 - (g / 250.0)).clamp(0.5, 1.8);

    // Combine into 4x5 ColorFilter matrix
    final totalR = (sr + sat) * contrastFactor * gammaMult;
    final totalG = (sg + sat) * contrastFactor * gammaMult;
    final totalB = (sb + sat) * contrastFactor * gammaMult;
    final totalOffset = contrastOffset + brightnessOffset;

    return <double>[
      (totalR * hr00), (totalG * hr01), (totalB * hr02), 0.0, totalOffset,
      (totalR * hr10), (totalG * hr11), (totalB * hr12), 0.0, totalOffset,
      (totalR * hr20), (totalG * hr21), (totalB * hr22), 0.0, totalOffset,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];
  }

  /// Resolves the active ColorProfileConfig from either built-in presets or custom profiles
  static ColorProfileConfig getProfile({
    required String profileId,
    required List<Map<String, dynamic>> customProfiles,
  }) {
    if (builtInPresets.containsKey(profileId)) {
      return builtInPresets[profileId]!;
    }
    for (final map in customProfiles) {
      try {
        if (map['id'] == profileId) {
          return ColorProfileConfig.fromJson(map);
        }
      } catch (_) {}
    }
    return builtInPresets['natural']!;
  }

  /// Helper to calculate the active 4x5 color matrix directly from LocalStorageService state
  static List<double> computeFromStorage(LocalStorageService storage) {
    final mode = Anime4kMode.fromKey(storage.activeAnime4kMode);
    final quality = Anime4kQuality.fromKey(storage.activeAnime4kQuality);
    final profile = getProfile(
      profileId: storage.activeColorProfileId,
      customProfiles: storage.customColorProfiles,
    );
    return computeColorMatrix(
      profile: profile,
      anime4kMode: mode,
      anime4kQuality: quality,
    );
  }
}

class Anime4kColorSheet extends StatefulWidget {
  final LocalStorageService storage;
  final VoidCallback onSettingsChanged;
  final bool isPanelMode;
  final VoidCallback? onClose;
  final dynamic player;

  const Anime4kColorSheet({
    super.key,
    required this.storage,
    required this.onSettingsChanged,
    this.isPanelMode = false,
    this.onClose,
    this.player,
  });

  static Future<void> show(
    BuildContext context, {
    required LocalStorageService storage,
    required VoidCallback onSettingsChanged,
    dynamic player,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Anime4kColorSheet(
        storage: storage,
        onSettingsChanged: onSettingsChanged,
        player: player,
      ),
    );
  }

  @override
  State<Anime4kColorSheet> createState() => _Anime4kColorSheetState();
}

class _Anime4kColorSheetState extends State<Anime4kColorSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Anime4kMode _currentMode;
  late Anime4kQuality _currentQuality;
  late String _activeProfileId;
  late List<ColorProfileConfig> _customProfiles;
  ColorProfileConfig? _editingCustomProfile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentMode = Anime4kMode.fromKey(widget.storage.activeAnime4kMode);
    _currentQuality = Anime4kQuality.fromKey(widget.storage.activeAnime4kQuality);
    _activeProfileId = widget.storage.activeColorProfileId;
    _loadCustomProfiles();
  }

  void _loadCustomProfiles() {
    final raw = widget.storage.getCustomColorProfiles();
    _customProfiles = raw.map((e) => ColorProfileConfig.fromJson(e)).toList();
    if (_customProfiles.isNotEmpty) {
      _editingCustomProfile = _customProfiles.firstWhere(
        (p) => p.id == _activeProfileId,
        orElse: () => _customProfiles.first,
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onModeChanged(Anime4kMode mode) {
    HapticFeedback.selectionClick();
    setState(() => _currentMode = mode);
    widget.storage.setActiveAnime4kMode(mode.toKey());
    if (widget.player != null) {
      PlayerShaders.applyShader(
        player: widget.player,
        mode: mode,
        quality: _currentQuality,
      );
    }
    widget.onSettingsChanged();
  }

  void _onQualityChanged(Anime4kQuality quality) {
    HapticFeedback.selectionClick();
    setState(() => _currentQuality = quality);
    widget.storage.setActiveAnime4kQuality(quality.toKey());
    if (widget.player != null) {
      PlayerShaders.applyShader(
        player: widget.player,
        mode: _currentMode,
        quality: quality,
      );
    }
    widget.onSettingsChanged();
  }

  void _onProfileSelected(String profileId) {
    HapticFeedback.selectionClick();
    setState(() => _activeProfileId = profileId);
    widget.storage.setActiveColorProfileId(profileId);
    final p = ColorProfileRegistry.getProfile(
      profileId: profileId,
      customProfiles: widget.storage.customColorProfiles,
    );
    if (widget.player != null) {
      PlayerShaders.setHardwareColorSettings(
        player: widget.player,
        brightness: p.brightness,
        contrast: p.contrast,
        saturation: p.saturation,
        gamma: p.gamma,
        hue: p.hue,
      );
    }
    widget.onSettingsChanged();
  }

  void _resetAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _currentMode = Anime4kMode.off;
      _currentQuality = Anime4kQuality.fast;
      _activeProfileId = 'natural';
    });
    widget.storage.setActiveAnime4kMode(Anime4kMode.off.toKey());
    widget.storage.setActiveAnime4kQuality(Anime4kQuality.fast.toKey());
    widget.storage.setActiveColorProfileId('natural');
    if (widget.player != null) {
      PlayerShaders.applyShader(
        player: widget.player,
        mode: Anime4kMode.off,
        quality: Anime4kQuality.fast,
      );
      PlayerShaders.setHardwareColorSettings(
        player: widget.player,
        brightness: 0,
        contrast: 0,
        saturation: 0,
        gamma: 0,
        hue: 0,
      );
    }
    widget.onSettingsChanged();
  }

  void _createNewCustomProfile() {
    final controller = TextEditingController(text: 'Custom ${_customProfiles.length + 1}');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSecondary,
        title: const Text('New Custom Color Profile', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a name for your custom profile. Starting values will match your active visual state.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Profile Name',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: AppTheme.bgSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final name = controller.text.trim().isEmpty ? 'Custom Profile' : controller.text.trim();
              Navigator.pop(ctx);
              _saveNewProfile(name);
            },
            child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _saveNewProfile(String name) {
    final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final newProfile = ColorProfileConfig(
      id: newId,
      name: name,
      isCustom: true,
      brightness: 0,
      contrast: 10,
      saturation: 15,
      gamma: 0,
      hue: 0,
    );

    setState(() {
      _customProfiles.add(newProfile);
      _editingCustomProfile = newProfile;
      _activeProfileId = newId;
    });

    widget.storage.saveCustomColorProfiles(_customProfiles.map((e) => e.toJson()).toList());
    widget.storage.setActiveColorProfileId(newId);
    widget.onSettingsChanged();
  }

  void _renameProfile(ColorProfileConfig profile) {
    final controller = TextEditingController(text: profile.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSecondary,
        title: const Text('Rename Profile', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Profile Name',
            filled: true,
            fillColor: AppTheme.bgSurface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen, foregroundColor: Colors.black),
            onPressed: () {
              final newName = controller.text.trim().isEmpty ? profile.name : controller.text.trim();
              Navigator.pop(ctx);
              _updateProfileName(profile.id, newName);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _updateProfileName(String id, String newName) {
    setState(() {
      final index = _customProfiles.indexWhere((p) => p.id == id);
      if (index != -1) {
        _customProfiles[index] = _customProfiles[index].copyWith(name: newName);
        if (_editingCustomProfile?.id == id) {
          _editingCustomProfile = _customProfiles[index];
        }
      }
    });
    widget.storage.saveCustomColorProfiles(_customProfiles.map((e) => e.toJson()).toList());
  }

  void _deleteProfile(ColorProfileConfig profile) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSecondary,
        title: Text('Delete "${profile.name}"?', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'Are you sure you want to delete this custom color profile?',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDelete(profile.id);
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String id) {
    setState(() {
      _customProfiles.removeWhere((p) => p.id == id);
      if (_activeProfileId == id) {
        _activeProfileId = 'natural';
        widget.storage.setActiveColorProfileId('natural');
      }
      _editingCustomProfile = _customProfiles.isNotEmpty ? _customProfiles.first : null;
    });
    widget.storage.saveCustomColorProfiles(_customProfiles.map((e) => e.toJson()).toList());
    widget.onSettingsChanged();
  }

  void _updateSliderValue({
    int? brightness,
    int? contrast,
    int? saturation,
    int? gamma,
    int? hue,
  }) {
    if (_editingCustomProfile == null) return;
    final updated = _editingCustomProfile!.copyWith(
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      gamma: gamma,
      hue: hue,
    );

    setState(() {
      _editingCustomProfile = updated;
      final idx = _customProfiles.indexWhere((p) => p.id == updated.id);
      if (idx != -1) _customProfiles[idx] = updated;
      _activeProfileId = updated.id;
    });

    widget.storage.saveCustomColorProfiles(_customProfiles.map((e) => e.toJson()).toList());
    widget.storage.setActiveColorProfileId(updated.id);
    if (widget.player != null) {
      PlayerShaders.setHardwareColorSettings(
        player: widget.player,
        brightness: updated.brightness,
        contrast: updated.contrast,
        saturation: updated.saturation,
        gamma: updated.gamma,
        hue: updated.hue,
      );
    }
    widget.onSettingsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isPanel = widget.isPanelMode;
    return Container(
      height: isPanel ? double.infinity : MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: isPanel ? Colors.transparent : AppTheme.bgSecondary,
        borderRadius: isPanel ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          if (!isPanel)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

          // Header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isPanel ? 12 : 20, vertical: isPanel ? 6 : 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: AppTheme.accentGreen, size: isPanel ? 18 : 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isPanel ? 'Anime4K & Color' : 'Anime4K & Color Profiler',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isPanel ? 14 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _resetAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    foregroundColor: Colors.white60,
                  ),
                  child: const Text('Reset', style: TextStyle(fontSize: 11)),
                ),
                if (isPanel && widget.onClose != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onClose,
                  ),
                ],
              ],
            ),
          ),

          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.accentGreen,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.white70,
              indicator: BoxDecoration(
                color: AppTheme.accentGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              tabs: const [
                Tab(text: 'Anime4K'),
                Tab(text: 'Presets'),
                Tab(text: 'Custom Profiles'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAnime4kTab(),
                _buildPresetsTab(),
                _buildCustomProfilesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Tab 1: Anime4K Modes (Fast & HQ)
  // -------------------------------------------------------------
  Widget _buildAnime4kTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Fast vs HQ Segmented Pill Switcher
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _onQualityChanged(Anime4kQuality.fast),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _currentQuality == Anime4kQuality.fast ? AppTheme.accentGreen : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '⚡ Fast (Mid-End)',
                      style: TextStyle(
                        color: _currentQuality == Anime4kQuality.fast ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _onQualityChanged(Anime4kQuality.hq),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _currentQuality == Anime4kQuality.hq ? AppTheme.accentGreen : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '✨ Quality / HQ (High-End)',
                      style: TextStyle(
                        color: _currentQuality == Anime4kQuality.hq ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Off / Native Card
        GestureDetector(
          onTap: () => _onModeChanged(Anime4kMode.off),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _currentMode == Anime4kMode.off ? AppTheme.accentGreen : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.power_settings_new,
                  color: _currentMode == Anime4kMode.off ? AppTheme.accentGreen : Colors.white38,
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Original / Off', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Bypasses Anime4K enhancement filters', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
                const Spacer(),
                if (_currentMode == Anime4kMode.off)
                  Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 20),
              ],
            ),
          ),
        ),

        // 2-Column Grid of Anime4K Modes (Mode A, B, C, A+A, B+B, C+A)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.65,
          ),
          itemCount: Anime4kMode.values.length - 1, // Exclude Off
          itemBuilder: (context, index) {
            final mode = Anime4kMode.values[index + 1];
            final isSelected = _currentMode == mode;

            return GestureDetector(
              onTap: () => _onModeChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.accentGreen.withValues(alpha: 0.12) : AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppTheme.accentGreen : Colors.white10,
                    width: isSelected ? 1.8 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(
                          mode.label,
                          style: TextStyle(
                            color: isSelected ? AppTheme.accentGreen : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mode.description,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Tab 2: Built-in Presets
  // -------------------------------------------------------------
  Widget _buildPresetsTab() {
    final presets = ColorProfileRegistry.builtInPresets.values.toList();

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final p = presets[index];
        final isSelected = _activeProfileId == p.id;
        final icon = ColorProfileRegistry.presetIcons[p.id] ?? Icons.palette;
        final desc = ColorProfileRegistry.presetDescriptions[p.id] ?? '';

        return GestureDetector(
          onTap: () => _onProfileSelected(p.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.accentGreen.withValues(alpha: 0.12) : AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppTheme.accentGreen : Colors.white10,
                width: isSelected ? 1.8 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(icon, color: isSelected ? AppTheme.accentGreen : Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.name,
                        style: TextStyle(
                          color: isSelected ? AppTheme.accentGreen : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 16),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // Tab 3: Custom Profiles & Live Sliders
  // -------------------------------------------------------------
  Widget _buildCustomProfilesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Top Action: Create New Profile
        Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _createNewCustomProfile,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('+ New Custom Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const Spacer(),
            if (_editingCustomProfile != null) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                tooltip: 'Rename',
                onPressed: () => _renameProfile(_editingCustomProfile!),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                tooltip: 'Delete',
                onPressed: () => _deleteProfile(_editingCustomProfile!),
              ),
            ],
          ],
        ),

        const SizedBox(height: 12),

        // Custom Profiles Chip Selector
        if (_customProfiles.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              children: [
                Icon(Icons.tune, color: Colors.white24, size: 36),
                SizedBox(height: 8),
                Text('No custom color profiles created yet', style: TextStyle(color: Colors.white54, fontSize: 13)),
                SizedBox(height: 4),
                Text('Tap "+ New Custom Profile" to create and tune your own visual style!', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          )
        else ...[
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _customProfiles.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final p = _customProfiles[index];
                final isSelected = _activeProfileId == p.id;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _editingCustomProfile = p;
                      _activeProfileId = p.id;
                    });
                    widget.storage.setActiveColorProfileId(p.id);
                    widget.onSettingsChanged();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.accentGreen : AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.palette_outlined,
                          size: 14,
                          color: isSelected ? Colors.black : Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p.name,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Live Sliders for Active Custom Profile
          if (_editingCustomProfile != null) ...[
            _buildSlider(
              label: 'Brightness',
              value: _editingCustomProfile!.brightness,
              min: -50,
              max: 50,
              icon: Icons.brightness_6,
              onChanged: (v) => _updateSliderValue(brightness: v.round()),
            ),
            _buildSlider(
              label: 'Contrast',
              value: _editingCustomProfile!.contrast,
              min: -50,
              max: 80,
              icon: Icons.contrast,
              onChanged: (v) => _updateSliderValue(contrast: v.round()),
            ),
            _buildSlider(
              label: 'Saturation',
              value: _editingCustomProfile!.saturation,
              min: -100,
              max: 100,
              icon: Icons.color_lens_outlined,
              onChanged: (v) => _updateSliderValue(saturation: v.round()),
            ),
            _buildSlider(
              label: 'Gamma',
              value: _editingCustomProfile!.gamma,
              min: -50,
              max: 50,
              icon: Icons.tonality,
              onChanged: (v) => _updateSliderValue(gamma: v.round()),
            ),
            _buildSlider(
              label: 'Hue Shift',
              value: _editingCustomProfile!.hue,
              min: -180,
              max: 180,
              icon: Icons.rotate_right,
              unit: '°',
              onChanged: (v) => _updateSliderValue(hue: v.round()),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required int value,
    required double min,
    required double max,
    required IconData icon,
    required ValueChanged<double> onChanged,
    String unit = '',
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.accentGreen, size: 16),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                '$value$unit',
                style: TextStyle(
                  color: AppTheme.accentGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.accentGreen,
              inactiveTrackColor: Colors.white10,
              thumbColor: AppTheme.accentGreen,
              overlayColor: AppTheme.accentGreen.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.toDouble().clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
