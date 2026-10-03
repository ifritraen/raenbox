import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/local_storage_service.dart';
import 'anime4k_color_sheet.dart';

class PlayerSettingsSheet extends StatefulWidget {
  final LocalStorageService storage;
  final List<String> availableResolutions;
  final String currentResolution;
  final ValueChanged<String> onResolutionChanged;
  final VoidCallback onSettingsChanged;

  final dynamic player;

  const PlayerSettingsSheet({
    super.key,
    required this.storage,
    required this.availableResolutions,
    required this.currentResolution,
    required this.onResolutionChanged,
    required this.onSettingsChanged,
    this.player,
  });

  static Future<void> show({
    required BuildContext context,
    required LocalStorageService storage,
    required List<String> availableResolutions,
    required String currentResolution,
    required ValueChanged<String> onResolutionChanged,
    required VoidCallback onSettingsChanged,
    dynamic player,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PlayerSettingsSheet(
        storage: storage,
        availableResolutions: availableResolutions,
        currentResolution: currentResolution,
        onResolutionChanged: onResolutionChanged,
        onSettingsChanged: onSettingsChanged,
        player: player,
      ),
    );
  }

  @override
  State<PlayerSettingsSheet> createState() => _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends State<PlayerSettingsSheet> {
  late String _doubleTapLayout;
  late int _seekDurationX;
  late int _seekDurationY;
  late double _longPressSpeed;
  late int _longPressDragRate;
  late bool _gesturesEnabled;

  @override
  void initState() {
    super.initState();
    _doubleTapLayout = widget.storage.playerDoubleTapLayout;
    _seekDurationX = widget.storage.playerSeekDurationX;
    _seekDurationY = widget.storage.playerSeekDurationY;
    _longPressSpeed = widget.storage.playerLongPressSpeed;
    _longPressDragRate = widget.storage.playerLongPressDragRate;
    _gesturesEnabled = widget.storage.playerGesturesEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar & Header
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.tune, color: AppTheme.accentGreen, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Player & Gesture Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: AppTheme.borderSubtle, height: 1),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [

                  // 2. Anime4K Visual Enhancement & Color Profiles
                  _buildSectionHeader('Visual Enhancements', Icons.auto_awesome),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Anime4kColorSheet.show(
                        context,
                        storage: widget.storage,
                        player: widget.player,
                        onSettingsChanged: () {
                          setState(() {});
                          widget.onSettingsChanged();
                        },
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (widget.storage.activeAnime4kMode != 'off' ||
                                  widget.storage.activeColorProfileId != 'natural')
                              ? AppTheme.accentGreen.withValues(alpha: 0.6)
                              : AppTheme.borderSubtle,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (widget.storage.activeAnime4kMode != 'off' ||
                                      widget.storage.activeColorProfileId != 'natural')
                                  ? AppTheme.accentGreen.withValues(alpha: 0.2)
                                  : Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              color: (widget.storage.activeAnime4kMode != 'off' ||
                                      widget.storage.activeColorProfileId != 'natural')
                                  ? AppTheme.accentGreen
                                  : Colors.white70,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Anime4K & Color Profiles',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  () {
                                    final mode = Anime4kMode.fromKey(widget.storage.activeAnime4kMode);
                                    final profile = ColorProfileRegistry.getProfile(
                                      profileId: widget.storage.activeColorProfileId,
                                      customProfiles: widget.storage.customColorProfiles,
                                    );
                                    final modeStr = mode == Anime4kMode.off ? 'Off' : mode.label;
                                    return 'Anime4K: $modeStr • Profile: ${profile.name}';
                                  }(),
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Gestures Master Switch
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Touch Gestures',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Volume (right), Brightness (left), Seek (lower), Speed (upper)',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                      value: _gesturesEnabled,
                      activeThumbColor: AppTheme.accentGreen,
                      onChanged: (val) async {
                        setState(() => _gesturesEnabled = val);
                        await widget.storage.setPlayerGesturesEnabled(val);
                        widget.onSettingsChanged();
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Double-Tap Division Layout
                  _buildSectionHeader('Double-Tap Screen Division', Icons.touch_app_outlined),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose how double-tapping is divided across the screen. Middle is always Play/Pause.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  _buildLayoutOption(
                    id: '1+1+1',
                    title: '1+1+1 (Simple)',
                    description: 'Left (-X sec)  :  Middle (Play/Pause)  :  Right (+X sec)',
                    diagram: ['-X', 'Play', '+X'],
                  ),
                  const SizedBox(height: 8),
                  _buildLayoutOption(
                    id: '2+1+2',
                    title: '2+1+2 (Advance) - Recommended',
                    description: 'Far Left (-X) : Mid Left (-Y) : Middle : Mid Right (+Y) : Far Right (+X)',
                    diagram: ['-X', '-Y', 'Play', '+Y', '+X'],
                  ),
                  const SizedBox(height: 8),
                  _buildLayoutOption(
                    id: '4+1+4',
                    title: '4+1+4 (Complex Matrix)',
                    description: '9 Zones: Upper & Lower halves for forward/backward multi-speed jumps',
                    diagram: ['±X', '±Y', 'Play', '+Y', '+X'],
                  ),
                  const SizedBox(height: 20),

                  // 4. Seek Durations (X & Y)
                  _buildSectionHeader('Double-Tap Seek Intervals', Icons.fast_forward_outlined),
                  const SizedBox(height: 10),
                  _buildSeekSliderRow(
                    label: 'Primary Seek (X)',
                    subtitle: 'Outer zones & simple double-tap duration',
                    currentValue: _seekDurationX,
                    min: 5.0,
                    max: 60.0,
                    divisions: 11,
                    onChanged: (sec) async {
                      setState(() => _seekDurationX = sec);
                      await widget.storage.setPlayerSeekDurationX(sec);
                      widget.onSettingsChanged();
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildSeekSliderRow(
                    label: 'Secondary Seek (Y)',
                    subtitle: 'Inner zones in Advance & Complex layouts',
                    currentValue: _seekDurationY,
                    min: 2.0,
                    max: 30.0,
                    divisions: 14,
                    onChanged: (sec) async {
                      setState(() => _seekDurationY = sec);
                      await widget.storage.setPlayerSeekDurationY(sec);
                      widget.onSettingsChanged();
                    },
                  ),
                  const SizedBox(height: 20),

                  // 5. Long Tap Acceleration Speed & Drag Sensitivity
                  _buildSectionHeader('Long Tap Speed & Gesture Lock', Icons.speed_outlined),
                  const SizedBox(height: 6),
                  const Text(
                    'Speed while holding finger down. Drag up/down to micro-tune; flick left/right to lock speed.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [1.5, 2.0, 2.5, 3.0].map((spd) {
                      final isSelected = (_longPressSpeed - spd).abs() < 0.05;
                      return ChoiceChip(
                        selected: isSelected,
                        selectedColor: AppTheme.accentGreen.withValues(alpha: 0.25),
                        backgroundColor: AppTheme.bgCard,
                        side: BorderSide(
                          color: isSelected ? AppTheme.accentGreen : AppTheme.borderSubtle,
                        ),
                        label: Text(
                          '${spd}x',
                          style: TextStyle(
                            color: isSelected ? AppTheme.accentGreen : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                        onSelected: (_) async {
                          setState(() => _longPressSpeed = spd);
                          await widget.storage.setPlayerLongPressSpeed(spd);
                          widget.onSettingsChanged();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  _buildDragRateSliderRow(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accentCyan, size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildLayoutOption({
    required String id,
    required String title,
    required String description,
    required List<String> diagram,
  }) {
    final isSelected = _doubleTapLayout == id;

    return GestureDetector(
      onTap: () async {
        setState(() => _doubleTapLayout = id);
        await widget.storage.setPlayerDoubleTapLayout(id);
        widget.onSettingsChanged();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.bgCard : AppTheme.bgCard.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.accentGreen : AppTheme.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? AppTheme.accentGreen : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                description,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ),
            const SizedBox(height: 8),
            // Mini visual diagram
            Container(
              height: 24,
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: diagram.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final col = entry.value;
                  final isLast = idx == diagram.length - 1;
                  final isCenter = col.contains('Play');

                  return Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : const Border(right: BorderSide(color: Colors.white12, width: 0.8)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: isCenter
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.play_arrow_rounded, color: AppTheme.accentGreen, size: 13),
                                  const SizedBox(width: 1),
                                  Text(
                                    'Play',
                                    style: TextStyle(
                                      color: AppTheme.accentGreen,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                col,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekSliderRow({
    required String label,
    required String subtitle,
    required int currentValue,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.accentCyan, width: 1),
                ),
                child: Text(
                  '${currentValue}s',
                  style: TextStyle(
                    color: AppTheme.accentCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.accentCyan,
              inactiveTrackColor: Colors.white12,
              thumbColor: AppTheme.accentCyan,
              overlayColor: AppTheme.accentCyan.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: currentValue.toDouble().clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v.round());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragRateSliderRow() {
    String sensitivityLabel = 'Normal';
    if (_longPressDragRate <= 18) {
      sensitivityLabel = 'High (Fast Tuning)';
    } else if (_longPressDragRate >= 35) {
      sensitivityLabel = 'Low (Precise Tuning)';
    }

    return Container(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Vertical Drag Sensitivity',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.accentGreen, width: 1),
                ),
                child: Text(
                  '${_longPressDragRate}px • $sensitivityLabel',
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Pixels of thumb drag needed for ±0.1x speed change. Smaller = faster.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.accentGreen,
              inactiveTrackColor: Colors.white12,
              thumbColor: AppTheme.accentGreen,
              overlayColor: AppTheme.accentGreen.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: _longPressDragRate.toDouble().clamp(10.0, 50.0),
              min: 10.0,
              max: 50.0,
              divisions: 8,
              onChanged: (v) async {
                HapticFeedback.selectionClick();
                final rate = v.round();
                setState(() => _longPressDragRate = rate);
                await widget.storage.setPlayerLongPressDragRate(rate);
                widget.onSettingsChanged();
              },
            ),
          ),
        ],
      ),
    );
  }
}
