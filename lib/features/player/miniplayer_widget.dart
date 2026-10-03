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
  double _width = 230.0;
  bool _isDragging = false;
  bool _isResizing = false;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
        final topSafe = media.padding.top + 8;
        final bottomSafe = media.padding.bottom + 56; // Above bottom bar

        // 16:9 video + 36px bottom controls & seekbar
        final videoHeight = _width * 9 / 16;
        final totalHeight = videoHeight + 36.0;

        // Initial position (bottom right)
        _x ??= (screenWidth - _width - 12.0).clamp(12.0, screenWidth - _width);
        _y ??= (screenHeight - totalHeight - bottomSafe).clamp(topSafe, screenHeight - totalHeight);

        // Clamping to current screen bounds on orientation change or resize
        final clampedX = _x!.clamp(8.0, (screenWidth - _width - 8.0).clamp(8.0, screenWidth));
        final clampedY = _y!.clamp(topSafe, (screenHeight - totalHeight - 8.0).clamp(topSafe, screenHeight));

        return Positioned(
          left: clampedX,
          top: clampedY,
          child: Container(
            width: _width,
            height: totalHeight,
            decoration: BoxDecoration(
              color: AppTheme.bgSecondary.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isResizing
                    ? AppTheme.accentGreen
                    : (_isDragging ? AppTheme.accentCyan : AppTheme.borderSubtle),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Video Surface & Tap to Expand / Drag to Move
                      SizedBox(
                        width: _width,
                        height: videoHeight,
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
                          onTap: () => service.expand(context),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Video(
                                controller: service.videoController!,
                                controls: NoVideoControls,
                              ),
                              // Floating overlay controls
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Expand Button
                                    GestureDetector(
                                      onTap: () => service.expand(context),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
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
                                    // Close Button
                                    GestureDetector(
                                      onTap: () => service.close(),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
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
                              // Play/Pause Center Pill (tap or button)
                              Center(
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: service.isPlayingNotifier,
                                  builder: (context, isPlaying, _) {
                                    if (isPlaying) return const SizedBox.shrink();
                                    return GestureDetector(
                                      onTap: () => service.playOrPause(),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.65),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppTheme.accentGreen, width: 1),
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom bar: Play/Pause, Title, Seekbar
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          color: AppTheme.bgSecondary,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Row with Play/Pause, Title, and Time
                              Row(
                                children: [
                                  ValueListenableBuilder<bool>(
                                    valueListenable: service.isPlayingNotifier,
                                    builder: (context, isPlaying, _) {
                                      return GestureDetector(
                                        onTap: () => service.playOrPause(),
                                        child: Icon(
                                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                          color: AppTheme.accentGreen,
                                          size: 20,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      service.title ?? 'Playing',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  ValueListenableBuilder<Duration>(
                                    valueListenable: service.positionNotifier,
                                    builder: (context, pos, _) {
                                      return Text(
                                        _formatDuration(pos),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontFeatures: [FontFeature.tabularFigures()],
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 14), // Margin for corner resize handle
                                ],
                              ),
                              // Bottom Seek Bar
                              ValueListenableBuilder<Duration>(
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

                                      return SizedBox(
                                        height: 10,
                                        child: SliderTheme(
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
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Bottom-Right Corner Resize Handle
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => setState(() => _isResizing = true),
                      onPanUpdate: (details) {
                        setState(() {
                          final maxW = (screenWidth - 24.0).clamp(160.0, 420.0);
                          _width = (_width + details.delta.dx).clamp(160.0, maxW);
                        });
                      },
                      onPanEnd: (_) => setState(() => _isResizing = false),
                      onPanCancel: () => setState(() => _isResizing = false),
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.bottomRight,
                        padding: const EdgeInsets.only(right: 2, bottom: 2),
                        child: Icon(
                          Icons.south_east_rounded,
                          size: 13,
                          color: _isResizing ? AppTheme.accentGreen : Colors.white38,
                        ),
                      ),
                    ),
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
