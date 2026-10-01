import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/services/miniplayer_service.dart';
import '../../core/theme/app_theme.dart';

class MiniplayerWidget extends StatelessWidget {
  const MiniplayerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final service = MiniplayerService.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: service.isActiveNotifier,
      builder: (context, isActive, _) {
        if (!isActive || service.videoController == null) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.borderSubtle,
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => service.expand(context),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Row(
                  children: [
                    // 16:9 Video surface thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 96,
                        height: 54,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Video(
                              controller: service.videoController!,
                              controls: NoVideoControls,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Title & Season/Episode subtitle
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service.title ?? 'Playing',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            service.season > 0 && service.episode > 0
                                ? 'Season  • Episode '
                                : 'Playing now',
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Play/Pause button
                    ValueListenableBuilder<bool>(
                      valueListenable: service.isPlayingNotifier,
                      builder: (context, isPlaying, _) {
                        return IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          onPressed: () => service.playOrPause(),
                        );
                      },
                    ),

                    // Close (X) button
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: () => service.close(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
