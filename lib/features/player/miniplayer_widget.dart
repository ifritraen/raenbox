import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/services/miniplayer_service.dart';
import '../../core/theme/app_theme.dart';

class MiniplayerWidget extends StatefulWidget {
  const MiniplayerWidget({super.key});

  @override
  State<MiniplayerWidget> createState() => _MiniplayerWidgetState();
}

class _MiniplayerWidgetState extends State<MiniplayerWidget> {
  double? _x;
  double? _y;
  double _width = 240.0;
  bool _isDragging = false;
  bool _isResizing = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _triggerControlsVisibility() {
    setState(() => _showControls = true);
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildCornerHandle({
    required Alignment alignment,
    required void Function(DragUpdateDetails) onPanUpdate,
    required IconData icon,
  }) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _isResizing = true),
        onPanUpdate: onPanUpdate,
        onPanEnd: (_) => setState(() => _isResizing = false),
        onPanCancel: () => setState(() => _isResizing = false),
        child: Container(
          width: 28,
          height: 28,
          color: Colors.transparent,
          alignment: alignment,
          padding: const EdgeInsets.all(3),
          child: Icon(
            icon,
            size: 11,
            color: _isResizing ? AppTheme.accentGreen : Colors.white54,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = MiniplayerService.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: service.isActiveNotifier,
      builder: (context, isActive, _) {
        if (!isActive || service.videoController == null) {
          return const SizedBox.shrink();
        }

        final media = MediaQuery.of(context);
        final screenWidth = media.size.width;
        final screenHeight = media.size.height;
        final topSafe = media.padding.top + 6;
        final bottomSafe = media.padding.bottom + 56;

        final height = _width * 9 / 16;
        final minW = 160.0;
        final maxW = (screenWidth - 20.0).clamp(minW, 460.0);

        _x ??= (screenWidth - _width - 12.0).clamp(12.0, screenWidth - _width);
        _y ??= (screenHeight - height - bottomSafe).clamp(topSafe, screenHeight - height);

        final clampedX = _x!.clamp(8.0, (screenWidth - _width - 8.0).clamp(8.0, screenWidth));
        final clampedY = _y!.clamp(topSafe, (screenHeight - height - 8.0).clamp(topSafe, screenHeight));

        return Positioned(
          left: clampedX,
          top: clampedY,
          child: Container(
            width: _width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isResizing
                    ? AppTheme.accentGreen
                    : (_isDragging ? AppTheme.accentCyan : Colors.white24),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Stack(
                children: [
                  // Video & Drag to Move
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => setState(() => _isDragging = true),
                      onPanUpdate: (details) {
                        setState(() {
                          _x = (_x ?? clampedX) + details.delta.dx;
                          _y = (_y ?? clampedY) + details.delta.dy;
                        });
                      },
                      onPanEnd: (_) => setState(() => _isDragging = false),
                      onPanCancel: () => setState(() => _isDragging = false),
                      onTap: () {
                        _triggerControlsVisibility();
                      },
                      child: Video(
                        controller: service.videoController!,
                        controls: NoVideoControls,
                      ),
                    ),
                  ),

                  // Top Action Buttons (Expand & Close)
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => service.expand(context),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.open_in_full_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => service.close(),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Single-line Bottom Controls: [Play/Pause] | [Seekbar] | [Time]
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.85),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            // Play / Pause Button
                            ValueListenableBuilder<bool>(
                              valueListenable: service.isPlayingNotifier,
                              builder: (context, isPlaying, _) {
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    service.playOrPause();
                                    _startHideTimer();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: AppTheme.accentGreen,
                                      size: 18,
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Thin Seekbar
                            Expanded(
                              child: ValueListenableBuilder<Duration>(
                                valueListenable: service.durationNotifier,
                                builder: (context, duration, _) {
                                  return ValueListenableBuilder<Duration>(
                                    valueListenable: service.positionNotifier,
                                    builder: (context, position, _) {
                                      final maxMs = duration.inMilliseconds > 0
                                          ? duration.inMilliseconds.toDouble()
                                          : (service.currentStream?.duration != null && service.currentStream!.duration > 0
                                              ? service.currentStream!.duration * 1000.0
                                              : 1.0);
                                      final valMs = position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

                                      return SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                                          activeTrackColor: AppTheme.accentGreen,
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: AppTheme.accentGreen,
                                        ),
                                        child: Slider(
                                          value: valMs,
                                          min: 0,
                                          max: maxMs,
                                          onChanged: (val) {
                                            service.seek(Duration(milliseconds: val.toInt()));
                                            _startHideTimer();
                                          },
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            // Time Spent
                            ValueListenableBuilder<Duration>(
                              valueListenable: service.positionNotifier,
                              builder: (context, pos, _) {
                                return Text(
                                  _formatDuration(pos),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 4-Corner Resize Handles
                  // Top-Left
                  _buildCornerHandle(
                    alignment: Alignment.topLeft,
                    icon: Icons.north_west_rounded,
                    onPanUpdate: (details) {
                      setState(() {
                        final newW = (_width - details.delta.dx).clamp(minW, maxW);
                        final dw = newW - _width;
                        _width = newW;
                        _x = (_x ?? clampedX) - dw;
                        _y = (_y ?? clampedY) - (dw * 9 / 16);
                      });
                    },
                  ),
                  // Top-Right
                  _buildCornerHandle(
                    alignment: Alignment.topRight,
                    icon: Icons.north_east_rounded,
                    onPanUpdate: (details) {
                      setState(() {
                        final newW = (_width + details.delta.dx).clamp(minW, maxW);
                        final dw = newW - _width;
                        _width = newW;
                        _y = (_y ?? clampedY) - (dw * 9 / 16);
                      });
                    },
                  ),
                  // Bottom-Left
                  _buildCornerHandle(
                    alignment: Alignment.bottomLeft,
                    icon: Icons.south_west_rounded,
                    onPanUpdate: (details) {
                      setState(() {
                        final newW = (_width - details.delta.dx).clamp(minW, maxW);
                        final dw = newW - _width;
                        _width = newW;
                        _x = (_x ?? clampedX) - dw;
                      });
                    },
                  ),
                  // Bottom-Right
                  _buildCornerHandle(
                    alignment: Alignment.bottomRight,
                    icon: Icons.south_east_rounded,
                    onPanUpdate: (details) {
                      setState(() {
                        _width = (_width + details.delta.dx).clamp(minW, maxW);
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
