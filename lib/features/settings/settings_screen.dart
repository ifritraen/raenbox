import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_presets.dart';
import '../../data/services/local_storage_service.dart';
import '../player/player_settings_sheet.dart';

class SettingsScreen extends StatefulWidget {
  final LocalStorageService storage;

  const SettingsScreen({super.key, required this.storage});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _cacheSizeText = 'Calculating...';
  bool _isClearingCache = false;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    try {
      int totalBytes = PaintingBinding.instance.imageCache.currentSizeBytes;
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalBytes += await entity.length();
          }
        }
      }
      if (mounted) {
        setState(() {
          _cacheSizeText = _formatBytes(totalBytes);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cacheSizeText = '0 MB';
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1.0) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(1)} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _clearCache() async {
    if (_isClearingCache) return;
    setState(() => _isClearingCache = true);
    HapticFeedback.mediumImpact();

    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        final entries = tempDir.listSync(recursive: true);
        for (final entry in entries) {
          if (entry is File) {
            try {
              await entry.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    await _calculateCacheSize();
    if (mounted) {
      setState(() => _isClearingCache = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 18),
              const SizedBox(width: 8),
              const Text('Cache cleared successfully'),
            ],
          ),
          backgroundColor: AppTheme.bgCard,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final timeStr = '${pad(dt.hour)}:${pad(dt.minute)}';
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today at $timeStr';
    }
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} at $timeStr';
  }

  Future<void> _performExport() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    HapticFeedback.mediumImpact();

    try {
      final result = await widget.storage.exportAllData(isAuto: false);
      if (mounted) {
        setState(() => _isExporting = false);
        _showExportSuccessDialog(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showExportSuccessDialog(BackupExportResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.borderSubtle),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 24),
            const SizedBox(width: 10),
            const Text(
              'Backup Exported',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All your data has been safely exported to:',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: SelectableText(
                result.filePath,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildStatChip('${result.bookmarkCount} Bookmarks', Icons.bookmark_border),
                _buildStatChip('${result.historyCount} Watched', Icons.history),
                _buildStatChip('${result.customSectionCount} Rails', Icons.dashboard_customize),
                _buildStatChip(result.formattedSize, Icons.storage),
              ],
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Path'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result.filePath));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Path copied to clipboard'),
                  backgroundColor: AppTheme.bgCard,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.accentGreen),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _openBackupManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BackupsManagerSheet(
        storage: widget.storage,
        onStateChanged: () => setState(() {}),
      ),
    );
  }

  void _showRegionPicker() {
    final currentRegion = widget.storage.activeRegion;
    final isAuto = widget.storage.isAutoRegion;
    final detectedCatalog = LocalStorageService.getCatalog(widget.storage.detectedRegion);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.public, color: AppTheme.accentGreen, size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'Content Catalog & Region',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Text('✨', style: TextStyle(fontSize: 20)),
                  title: Text(
                    'Auto-Detect (${detectedCatalog.name})',
                    style: TextStyle(
                      color: isAuto ? AppTheme.accentGreen : Colors.white,
                      fontWeight: isAuto ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    'Automatically matched to device locale: ${detectedCatalog.flag} ${detectedCatalog.name}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  trailing: isAuto ? Icon(Icons.check_circle, color: AppTheme.accentGreen) : null,
                  onTap: () {
                    widget.storage.setAutoRegion(true);
                    Navigator.of(ctx).pop();
                    setState(() {});
                  },
                ),
                Divider(color: AppTheme.borderSubtle),
                ...LocalStorageService.supportedCatalogs.map((catalog) {
                  final isSelected = !isAuto && currentRegion == catalog.code;
                  return ListTile(
                    leading: Text(catalog.flag, style: const TextStyle(fontSize: 20)),
                    title: Text(
                      catalog.name,
                      style: TextStyle(
                        color: isSelected ? AppTheme.accentGreen : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      catalog.description,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                    trailing: isSelected ? Icon(Icons.check, color: AppTheme.accentGreen) : null,
                    onTap: () {
                      widget.storage.setActiveRegion(catalog.code, isManual: true);
                      Navigator.of(ctx).pop();
                      setState(() {});
                    },
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPreset = widget.storage.activeThemePreset;
    final isOled = widget.storage.isPureOled;

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ==================== 1. APPEARANCE & THEME ====================
          _buildSectionHeader('Appearance & Theme', Icons.palette_outlined),
          const SizedBox(height: 10),

          // Theme Presets Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.35,
            ),
            itemCount: ThemePreset.allPresets.length,
            itemBuilder: (context, index) {
              final preset = ThemePreset.allPresets[index];
              final isSelected = currentPreset.id == preset.id;
              return _buildThemeCard(preset, isSelected);
            },
          ),
          const SizedBox(height: 14),

          // Pure OLED Mode Switch Card
          Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isOled ? AppTheme.accentGreen.withValues(alpha: 0.5) : AppTheme.borderSubtle,
                width: isOled ? 1.5 : 1.0,
              ),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              activeThumbColor: AppTheme.accentGreen,
              title: Row(
                children: [
                  const Icon(Icons.dark_mode_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Pure OLED Pitch Black',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#000000',
                      style: TextStyle(color: AppTheme.accentGreen, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Forces true pitch black surfaces across all screens to maximize battery life on AMOLED displays.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ),
              value: isOled,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                widget.storage.setPureOled(val);
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 24),

          // ==================== 2. PLAYBACK & ENGINE ====================
          _buildSectionHeader('Playback & Video Engine', Icons.play_circle_outline_rounded),
          const SizedBox(height: 10),

          // Screen Wake Lock Switch Tile
          _buildSettingsCard(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              activeThumbColor: AppTheme.accentGreen,
              secondary: Icon(Icons.screen_lock_portrait, color: AppTheme.accentGreen, size: 22),
              title: const Text(
                'Keep Screen Awake',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Prevent phone screen from sleeping while browsing or streaming videos.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              value: widget.storage.isKeepScreenAwake,
              onChanged: (val) async {
                HapticFeedback.selectionClick();
                await widget.storage.setKeepScreenAwake(val);
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 10),

          // Player & Gesture Settings Shortcut
          _buildSettingsCard(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Icon(Icons.tune, color: AppTheme.accentGreen, size: 22),
              title: const Text(
                'Player & Gesture Controls',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Configure double-tap seek zones, speed boost, gestures, and Anime4K modes.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
              onTap: () {
                PlayerSettingsSheet.show(
                  context: context,
                  storage: widget.storage,
                  availableResolutions: const ['1080p Full HD', '720p HD', '480p SD'],
                  currentResolution: '1080p Full HD',
                  onResolutionChanged: (_) {},
                  onSettingsChanged: () {},
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // ==================== 3. CONTENT & REGION ====================
          _buildSectionHeader('Content & Region', Icons.public),
          const SizedBox(height: 10),

          // Feed Edition Switcher (Web vs. Original Mobile App)
          _buildSettingsCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.storage.feedEdition == FeedEdition.mobile
                            ? Icons.phone_android
                            : Icons.language,
                        color: AppTheme.accentGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Feed Experience',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          widget.storage.feedEdition == FeedEdition.mobile
                              ? '100% Original Mobile'
                              : 'Curated Web Hub',
                          style: TextStyle(
                            color: AppTheme.accentGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.storage.feedEdition == FeedEdition.mobile
                        ? 'Renders the exact 107-137 sections, banners, and rails directly from the live mobile backend.'
                        : 'Custom personalized feed with Continue Watching, curated highlights, and custom rails.',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgSecondary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (widget.storage.feedEdition != FeedEdition.web) {
                                await widget.storage.setFeedEdition(FeedEdition.web);
                                setState(() {});
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: widget.storage.feedEdition == FeedEdition.web
                                    ? AppTheme.accentGreen.withValues(alpha: 0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                border: widget.storage.feedEdition == FeedEdition.web
                                    ? Border.all(color: AppTheme.accentGreen)
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.language,
                                    size: 15,
                                    color: widget.storage.feedEdition == FeedEdition.web
                                        ? AppTheme.accentGreen
                                        : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Web Edition',
                                    style: TextStyle(
                                      color: widget.storage.feedEdition == FeedEdition.web
                                          ? AppTheme.accentGreen
                                          : AppTheme.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (widget.storage.feedEdition != FeedEdition.mobile) {
                                await widget.storage.setFeedEdition(FeedEdition.mobile);
                                setState(() {});
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: widget.storage.feedEdition == FeedEdition.mobile
                                    ? AppTheme.accentGreen.withValues(alpha: 0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                border: widget.storage.feedEdition == FeedEdition.mobile
                                    ? Border.all(color: AppTheme.accentGreen)
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.phone_android,
                                    size: 15,
                                    color: widget.storage.feedEdition == FeedEdition.mobile
                                        ? AppTheme.accentGreen
                                        : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Original Mobile',
                                    style: TextStyle(
                                      color: widget.storage.feedEdition == FeedEdition.mobile
                                          ? AppTheme.accentGreen
                                          : AppTheme.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Content Catalog & Region Picker
          _buildSettingsCard(
            child: Builder(builder: (context) {
              final activeCatalog = LocalStorageService.getCatalog(widget.storage.activeRegion);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                leading: Text(
                  widget.storage.isAutoRegion ? '✨' : activeCatalog.flag,
                  style: const TextStyle(fontSize: 22),
                ),
                title: Text(
                  widget.storage.isAutoRegion
                      ? 'Auto (${widget.storage.activeRegionCountryName})'
                      : widget.storage.activeRegionCountryName,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  widget.storage.isAutoRegion
                      ? 'Automatically determined by device locale'
                      : activeCatalog.description,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                onTap: _showRegionPicker,
              );
            }),
          ),
          const SizedBox(height: 10),

          // 18+ Content Kill Switch
          _buildSettingsCard(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              activeThumbColor: Colors.redAccent,
              secondary: Icon(
                Icons.block,
                color: widget.storage.is18PlusDisabled ? Colors.redAccent : AppTheme.textMuted,
                size: 22,
              ),
              title: Row(
                children: [
                  const Text(
                    'Hide 18+ Content',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'KILL SWITCH',
                      style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Instantly hides the MidNight🔞 tab, adult feeds, and all 18+ content options across the app.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ),
              value: widget.storage.is18PlusDisabled,
              onChanged: (val) async {
                HapticFeedback.heavyImpact();
                await widget.storage.setIs18PlusDisabled(val);
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 10),

          _buildSettingsCard(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              secondary: Icon(
                Icons.video_library_outlined,
                color: widget.storage.isBuzzBoxEnabled ? AppTheme.accentGreen : AppTheme.textMuted,
                size: 22,
              ),
              title: Row(
                children: [
                  const Text(
                    '😂 BuzzBox Community & Shorts',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      'Tab',
                      style: TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: const Text(
                'Show dedicated BuzzBox community tab beside MidNight (For You, Discover, Images, Nearby)',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              value: widget.storage.isBuzzBoxEnabled,
              onChanged: (val) async {
                HapticFeedback.selectionClick();
                await widget.storage.setBuzzBoxEnabled(val);
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 24),

          // ==================== 4. STORAGE & CACHE ====================
          _buildSectionHeader('Storage & Cache', Icons.storage_outlined),
          const SizedBox(height: 10),

          _buildSettingsCard(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Icon(Icons.cleaning_services_outlined, color: AppTheme.accentCyan, size: 22),
              title: const Text(
                'Clear Image & Network Cache',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Current cache size: $_cacheSizeText',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGreen.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.accentGreen,
                  elevation: 0,
                  side: BorderSide(color: AppTheme.accentGreen.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: _isClearingCache ? null : _clearCache,
                child: _isClearingCache
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGreen),
                      )
                    : const Text('Clear', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ==================== 5. DOWNLOAD SETTINGS ====================
          _buildSectionHeader('Download Settings', Icons.download_for_offline_outlined),
          const SizedBox(height: 10),

          // Download Threads Slider (IDM-style segment acceleration)
          _buildSettingsCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed_rounded, color: AppTheme.accentGreen, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Download Threads',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${widget.storage.downloadThreads} Threads',
                          style: TextStyle(color: AppTheme.accentGreen, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'IDM-style multithreaded chunk acceleration per download. Downloads multiple video segments simultaneously for faster speeds.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppTheme.accentGreen,
                      inactiveTrackColor: AppTheme.bgSurface,
                      thumbColor: AppTheme.accentGreen,
                      overlayColor: AppTheme.accentGreen.withValues(alpha: 0.2),
                      valueIndicatorColor: AppTheme.bgSecondary,
                      valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    child: Slider(
                      value: widget.storage.downloadThreads.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: '${widget.storage.downloadThreads} Threads',
                      onChanged: (val) async {
                        HapticFeedback.selectionClick();
                        await widget.storage.setDownloadThreads(val.round());
                        setState(() {});
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('1 (Single)', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                      Text('4 (Optimal Speed)', style: TextStyle(color: AppTheme.accentGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                      const Text('8 (Maximum)', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Concurrent Downloads Slider
          _buildSettingsCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sync_alt_rounded, color: AppTheme.accentCyan, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Concurrent Downloads',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${widget.storage.maxConcurrentDownloads} Active',
                          style: TextStyle(color: AppTheme.accentCyan, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Maximum number of videos downloading in parallel. Additional downloads are automatically queued and start sequentially.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppTheme.accentCyan,
                      inactiveTrackColor: AppTheme.bgSurface,
                      thumbColor: AppTheme.accentCyan,
                      overlayColor: AppTheme.accentCyan.withValues(alpha: 0.2),
                      valueIndicatorColor: AppTheme.bgSecondary,
                      valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    child: Slider(
                      value: widget.storage.maxConcurrentDownloads.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '${widget.storage.maxConcurrentDownloads} Active',
                      onChanged: (val) async {
                        HapticFeedback.selectionClick();
                        await widget.storage.setMaxConcurrentDownloads(val.round());
                        setState(() {});
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('1 Task', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                      Text('2 Tasks (Recommended)', style: TextStyle(color: AppTheme.accentCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                      const Text('5 Tasks', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Download Location Info Card
          _buildSettingsCard(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: Icon(Icons.folder_open_rounded, color: Colors.amber, size: 22),
              title: const Text(
                'Public Storage Location',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Download/RaenBox/Download/{Title}/\nAccessible by all File Managers on your device.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ==================== 6. BACKUP & RESTORE ====================
          _buildSectionHeader('Backup & Restore', Icons.backup_outlined),
          const SizedBox(height: 10),

          // Export & Import Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: AppTheme.borderSubtle),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(Icons.upload_file_outlined, size: 18, color: AppTheme.accentGreen),
                  label: const Text('Export All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _isExporting ? null : _performExport,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: AppTheme.borderSubtle),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(Icons.download_outlined, size: 18, color: AppTheme.accentCyan),
                  label: const Text('Import Backup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _openBackupManager,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Auto-Export Settings Card with Slider
          _buildSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  activeThumbColor: AppTheme.accentGreen,
                  secondary: Icon(Icons.cloud_sync_outlined, color: AppTheme.accentGreen, size: 22),
                  title: const Text(
                    'Auto-Export Backups',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Automatically saves rolling backups (last 5 versions) to Downloads/RaenBox/Backups/',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  value: widget.storage.isAutoExportEnabled,
                  onChanged: (val) async {
                    HapticFeedback.selectionClick();
                    await widget.storage.setAutoExportEnabled(val);
                    setState(() {});
                  },
                ),
                if (widget.storage.isAutoExportEnabled) ...[
                  Divider(color: AppTheme.borderSubtle, height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Export Frequency',
                              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.accentGreen.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                LocalStorageService.formatIntervalLabel(widget.storage.autoExportIntervalHours),
                                style: TextStyle(color: AppTheme.accentGreen, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Builder(builder: (context) {
                          final milestones = LocalStorageService.autoExportIntervalMilestones;
                          int currentIdx = milestones.indexOf(widget.storage.autoExportIntervalHours);
                          if (currentIdx == -1) currentIdx = 2; // Default 24h

                          return SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppTheme.accentGreen,
                              inactiveTrackColor: AppTheme.borderSubtle,
                              thumbColor: AppTheme.accentGreen,
                              overlayColor: AppTheme.accentGreen.withValues(alpha: 0.2),
                              trackHeight: 3,
                            ),
                            child: Slider(
                              min: 0,
                              max: (milestones.length - 1).toDouble(),
                              divisions: milestones.length - 1,
                              value: currentIdx.toDouble(),
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                final selectedHours = milestones[val.round()];
                                widget.storage.setAutoExportIntervalHours(selectedHours);
                                setState(() {});
                              },
                            ),
                          );
                        }),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text('6 Hours', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                              Text('1 Day', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                              Text('7 Days', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 13, color: AppTheme.textMuted),
                            const SizedBox(width: 5),
                            Text(
                              widget.storage.lastAutoExportDate != null
                                  ? 'Last backup: ${_formatDate(widget.storage.lastAutoExportDate!)}'
                                  : 'Last backup: Never',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Available Backups / History Tile
          _buildSettingsCard(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Icon(Icons.folder_zip_outlined, color: AppTheme.orangeHot, size: 22),
              title: const Text(
                'Available Backups & History',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Browse saved backups, restore older versions, or clean up disk space.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
              onTap: _openBackupManager,
            ),
          ),
          const SizedBox(height: 24),

          // ==================== 7. ABOUT & VERSION ====================
          _buildSectionHeader('About', Icons.info_outline),
          const SizedBox(height: 10),

          _buildSettingsCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.bgSecondary,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Center(
                      child: Text(
                        '🎬',
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RaenBox',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Version 1.0.0+1 • com.raen.raenbox',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Built with Flutter 3.11 & OneRoom Engine',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.accentGreen),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: child,
    );
  }

  Widget _buildThemeCard(ThemePreset preset, bool isSelected) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.storage.setThemePreset(preset.id);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: preset.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? preset.accent : preset.borderSubtle,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: preset.accent.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Row: Icon + Preset Name + Selection Check
            Row(
              children: [
                Text(preset.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: preset.accent, size: 16),
              ],
            ),

            // Mini UI preview palette dots
            Row(
              children: [
                // Scaffold dot
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: preset.bgPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                ),
                const SizedBox(width: 5),
                // Card dot
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: preset.bgSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                ),
                const SizedBox(width: 5),
                // Accent dot
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: preset.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                // Secondary accent dot
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: preset.accentSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),

            // Subtitle
            Text(
              preset.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 9.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// BACKUPS MANAGER SHEET
// ==============================================================================
class BackupsManagerSheet extends StatefulWidget {
  final LocalStorageService storage;
  final VoidCallback onStateChanged;

  const BackupsManagerSheet({
    super.key,
    required this.storage,
    required this.onStateChanged,
  });

  @override
  State<BackupsManagerSheet> createState() => _BackupsManagerSheetState();
}

class _BackupsManagerSheetState extends State<BackupsManagerSheet> {
  List<BackupFileInfo> _backups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    final list = await widget.storage.getAvailableBackups();
    if (mounted) {
      setState(() {
        _backups = list;
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final timeStr = '${pad(dt.hour)}:${pad(dt.minute)}';
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today at $timeStr';
    }
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} $timeStr';
  }

  void _showRestoreDialog(BackupFileInfo backup) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.borderSubtle),
        ),
        title: Row(
          children: [
            Icon(Icons.settings_backup_restore, color: AppTheme.accentGreen, size: 24),
            const SizedBox(width: 10),
            const Text(
              'Restore Backup',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              backup.fileName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '${backup.formattedSize} • ${_formatDateTime(backup.modifiedDate)}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.merge, color: AppTheme.accentGreen, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        'Merge & Combine (Recommended)',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Supplements your current bookmarks, categories, and history with this backup without deleting existing items.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Divider(color: AppTheme.borderSubtle, height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: const [
                      Icon(Icons.refresh, color: Colors.redAccent, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Clean Restore',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Completely wipes all current bookmarks, history, and settings and replaces them with this backup.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _executeRestore(backup.path, mergeMode: false);
            },
            child: const Text('Clean Restore'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _executeRestore(backup.path, mergeMode: true);
            },
            child: const Text('Merge & Combine', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRestore(String filePath, {required bool mergeMode}) async {
    HapticFeedback.mediumImpact();
    try {
      final file = File(filePath);
      await widget.storage.importBackupFromFile(file, mergeMode: mergeMode);
      if (mounted) {
        Navigator.of(context).pop(); // Close sheet
        widget.onStateChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 18),
                const SizedBox(width: 8),
                Text(mergeMode ? 'Data merged and restored successfully!' : 'Clean restore completed successfully!'),
              ],
            ),
            backgroundColor: AppTheme.bgCard,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore backup: $e'),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _confirmDelete(BackupFileInfo backup) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.borderSubtle),
        ),
        title: Row(
          children: const [
            Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text('Delete Backup?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${backup.fileName}"?',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await widget.storage.deleteBackup(backup.path);
              _loadBackups();
              widget.onStateChanged();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCustomPathOrJsonDialog() {
    final pathController = TextEditingController();
    final jsonController = TextEditingController();
    int selectedTab = 0; // 0: File Path, 1: Raw JSON

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppTheme.borderSubtle),
          ),
          title: Row(
            children: [
              Icon(Icons.file_open_outlined, color: AppTheme.accentCyan, size: 22),
              const SizedBox(width: 8),
              const Text('Import From File or JSON', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        selected: selectedTab == 0,
                        selectedColor: AppTheme.accentCyan.withValues(alpha: 0.25),
                        backgroundColor: AppTheme.bgCard,
                        side: BorderSide(color: selectedTab == 0 ? AppTheme.accentCyan : AppTheme.borderSubtle),
                        label: Text(
                          'File Path',
                          style: TextStyle(
                            color: selectedTab == 0 ? AppTheme.accentCyan : Colors.white70,
                            fontWeight: selectedTab == 0 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                        onSelected: (_) => setDialogState(() => selectedTab = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        selected: selectedTab == 1,
                        selectedColor: AppTheme.accentCyan.withValues(alpha: 0.25),
                        backgroundColor: AppTheme.bgCard,
                        side: BorderSide(color: selectedTab == 1 ? AppTheme.accentCyan : AppTheme.borderSubtle),
                        label: Text(
                          'Paste JSON',
                          style: TextStyle(
                            color: selectedTab == 1 ? AppTheme.accentCyan : Colors.white70,
                            fontWeight: selectedTab == 1 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                        onSelected: (_) => setDialogState(() => selectedTab = 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (selectedTab == 0) ...[
                  TextField(
                    controller: pathController,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: Platform.isAndroid
                          ? '/storage/emulated/0/Download/backup.json'
                          : 'C:\\path\\to\\backup.json',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      filled: true,
                      fillColor: AppTheme.bgCard,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.borderSubtle)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.borderSubtle)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.accentCyan)),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: jsonController,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Paste backup JSON payload here...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      filled: true,
                      fillColor: AppTheme.bgCard,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.borderSubtle)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.borderSubtle)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.accentCyan)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentCyan, foregroundColor: Colors.black),
              onPressed: () async {
                String? content;
                if (selectedTab == 0) {
                  final p = pathController.text.trim();
                  if (p.isEmpty) return;
                  final file = File(p);
                  if (!await file.exists()) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File does not exist at specified path'), behavior: SnackBarBehavior.floating),
                    );
                    return;
                  }
                  content = await file.readAsString();
                } else {
                  content = jsonController.text.trim();
                  if (content.isEmpty) return;
                }

                if (!mounted || !ctx.mounted) return;
                try {
                  final decoded = json.decode(content);
                  if (decoded is! Map<String, dynamic> || !decoded.containsKey('data')) {
                    throw const FormatException('Missing "data" object in backup JSON');
                  }
                  Navigator.of(ctx).pop();
                  _showRawRestoreConfirmDialog(decoded);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Invalid backup format: $e'), behavior: SnackBarBehavior.floating),
                  );
                }
              },
              child: const Text('Load & Verify', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showRawRestoreConfirmDialog(Map<String, dynamic> jsonMap) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppTheme.borderSubtle)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.accentGreen, size: 22),
            const SizedBox(width: 8),
            const Text('Backup Verified', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Backup file structure is valid. How would you like to restore this data?',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
              await widget.storage.importBackupData(jsonMap, mergeMode: false);
              widget.onStateChanged();
            },
            child: const Text('Clean Restore'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen, foregroundColor: Colors.black),
            onPressed: () async {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
              await widget.storage.importBackupData(jsonMap, mergeMode: true);
              widget.onStateChanged();
            },
            child: const Text('Merge & Combine', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.folder_zip_outlined, color: AppTheme.orangeHot, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Available Backups',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentCyan,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  icon: const Icon(Icons.file_open_outlined, size: 16),
                  label: const Text('Load Path / JSON', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _showCustomPathOrJsonDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(color: AppTheme.borderSubtle),

          // Body
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppTheme.accentGreen))
                : _backups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.textMuted),
                            const SizedBox(height: 12),
                            const Text('No backups found', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            const Text('Export your first backup to see it here', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _backups.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final b = _backups[index];
                          return Container(
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.borderSubtle),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (b.isAuto ? AppTheme.accentCyan : AppTheme.accentGreen).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  b.isAuto ? Icons.cloud_sync_outlined : Icons.inventory_2_outlined,
                                  color: b.isAuto ? AppTheme.accentCyan : AppTheme.accentGreen,
                                  size: 20,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatDateTime(b.modifiedDate),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (b.isAuto ? AppTheme.accentCyan : AppTheme.accentGreen).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      b.isAuto ? 'AUTO' : 'MANUAL',
                                      style: TextStyle(
                                        color: b.isAuto ? AppTheme.accentCyan : AppTheme.accentGreen,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    '${b.formattedSize} • ${b.bookmarkCount ?? 0} bookmarks • ${b.historyCount ?? 0} watched',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    b.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.settings_backup_restore, color: AppTheme.accentGreen, size: 22),
                                    tooltip: 'Restore this backup',
                                    onPressed: () => _showRestoreDialog(b),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
                                    tooltip: 'Delete backup',
                                    onPressed: () => _confirmDelete(b),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
