import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/proxy/local_stream_proxy.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/services/download_service.dart';
import '../../data/services/local_storage_service.dart';
import '../../data/services/moviebox_api_service.dart';
import '../../core/services/pip_service.dart';
import '../../core/services/miniplayer_service.dart';
import '../player/anime4k_color_sheet.dart';
import '../player/player_screen.dart';
import '../player/player_settings_sheet.dart';
import '../me/bouncy_category_sheet.dart';

enum _ActivePanGesture {
  none,
  brightness,
  volume,
  seek,
  speed,
}

class _DoubleTapRipple {
  final Offset position;
  final String label;
  final IconData icon;
  final bool isLeft;

  _DoubleTapRipple({
    required this.position,
    required this.label,
    required this.icon,
    required this.isLeft,
  });
}

class DetailScreen extends StatefulWidget {
  final String subjectId;
  final MovieBoxApiService apiService;

  const DetailScreen({
    super.key,
    required this.subjectId,
    required this.apiService,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  MediaDetail? _detail;
  List<SeasonInfo> _seasons = [];
  List<MediaItem> _recommendations = [];
  bool _isRecommendationsLoading = true;
  int _selectedSeason = 1;
  int _selectedEpisode = 1;
  Dub? _selectedDub;

  LocalStorageService? _storage;
  DownloadService? _downloadService;
  bool _isBookmarked = false;
  bool _isFavorite = false;

  // Portrait Player State
  Player? _player;
  VideoController? _videoController;
  final List<StreamSubscription> _subscriptions = [];
  List<StreamLink> _streams = [];
  StreamLink? _currentStream;
  bool _isPlaying = false;
  bool _isVideoLoading = true;
  String? _videoError;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _showControls = true;
  Timer? _controlsTimer;
  Timer? _progressTimer;

  // Gesture Preferences & Settings
  bool _gesturesEnabled = true;
  String _doubleTapLayout = '2+1+2';
  int _seekDurationX = 10;
  int _seekDurationY = 5;
  double _longPressSettingSpeed = 2.0;
  int _longPressDragRate = 25;

  // Runtime Gesture State
  _ActivePanGesture _activePan = _ActivePanGesture.none;
  Offset? _panStartPos;
  double _brightness = 1.0;
  double _volume = 1.0;
  double _currentPlaybackSpeed = 1.0;
  double _panStartBrightness = 1.0;
  double _panStartVolume = 1.0;
  Duration _panStartPosition = Duration.zero;
  Duration _panSeekTarget = Duration.zero;
  double _panSpeedTarget = 1.0;

  // Active HUD Overlay State
  bool _showHud = false;
  Timer? _hudTimer;
  String _hudTitle = '';
  String _hudValue = '';
  IconData _hudIcon = Icons.info_outline;
  double? _hudProgress;

  // Double-tap Ripple Effect
  _DoubleTapRipple? _activeRipple;
  Timer? _rippleTimer;

  // Long Press Speed Boost & Lock State
  bool _isLongPressActive = false;
  double _longPressActiveSpeed = 2.0;
  double _normalSpeedBeforeLongPress = 1.0;
  double _longPressStartY = 0.0;
  double _longPressStartX = 0.0;
  bool _isSpeedLocked = false;
  double _lockedSpeed = 1.0;

  // Tab switcher (0 = For you, 1 = Comments)
  int _activeDetailTab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _saveWatchProgress() {
    if (_detail == null || _storage == null) return;
    final pos = _player?.state.position.inSeconds ?? _position.inSeconds;
    var dur = _player?.state.duration.inSeconds ?? _duration.inSeconds;
    if (dur <= 0 && _currentStream != null && _currentStream!.duration > 0) {
      dur = _currentStream!.duration;
    }
    if (pos > 0 && dur > 0) {
      _storage?.saveWatchProgress(
        subjectId: widget.subjectId,
        title: _detail!.title,
        coverUrl: _detail!.coverUrl,
        subjectType: _detail!.subjectType,
        positionSeconds: pos,
        durationSeconds: dur,
      );
    }
  }

  bool _isHandedOver = false;

  @override
  void dispose() {
    _progressTimer?.cancel();
    _saveWatchProgress();
    _controlsTimer?.cancel();
    _hudTimer?.cancel();
    _rippleTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    if (!_isHandedOver) {
      _player?.stop();
      _player?.dispose();
    }
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isRecommendationsLoading = true;
        _errorMessage = null;
      });
    }
    _storage = await LocalStorageService.getInstance();
    _loadPlayerSettings();
    _downloadService = DownloadService.getInstance(_storage!);

    _isBookmarked = _storage?.isBookmarked(widget.subjectId) ?? false;
    _isFavorite = _storage?.isFavorite(widget.subjectId) ?? false;

    try {
      final detail = await widget.apiService.fetchDetail(widget.subjectId);
      List<SeasonInfo> seasons = [];
      if (detail != null && detail.isSeries) {
        seasons = await widget.apiService.fetchSeasonInfo(widget.subjectId);
      }

      // Fetch "For You" Recommendations dynamically based on video genre and format
      widget.apiService
          .fetchRecommendations(
            widget.subjectId,
            genre: detail?.genre,
            subjectType: detail?.subjectType,
          )
          .then((recs) {
        if (mounted) {
          setState(() {
            _recommendations = recs;
            _isRecommendationsLoading = false;
          });
        }
      }).catchError((_) {
        if (mounted) {
          setState(() => _isRecommendationsLoading = false);
        }
      });

      if (mounted) {
        setState(() {
          _detail = detail;
          _seasons = seasons;
          if (seasons.isNotEmpty && !seasons.any((s) => s.seasonNumber == _selectedSeason)) {
            _selectedSeason = seasons.first.seasonNumber;
            _selectedEpisode = 1;
          }
          if (detail != null && detail.dubs.isNotEmpty) {
            _selectedDub = detail.dubs.firstWhere(
              (d) => d.subjectId == widget.subjectId,
              orElse: () => detail.dubs.first,
            );
          }
          if (detail == null) {
            _errorMessage = 'Content not found or unavailable in your region.';
          }
          _isLoading = false;
        });

        // Initialize portrait playback automatically
        if (detail != null) {
          _loadAndPlayStream(
            season: detail.isSeries ? _selectedSeason : 0,
            episode: detail.isSeries ? _selectedEpisode : 0,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load: $e';
        });
      }
    }
  }

  Future<void> _loadAndPlayStream({int season = 0, int episode = 0}) async {
    if (_detail == null) return;
    if (MiniplayerService.instance.isActive) {
      MiniplayerService.instance.close();
    }
    setState(() {
      _isVideoLoading = true;
      _videoError = null;
    });

    var targetSubjectId = _selectedDub?.subjectId ?? widget.subjectId;

    try {
      var streams = await widget.apiService.fetchPlayInfo(
        targetSubjectId,
        season: season,
        episode: episode,
      );

      // Fallback to clicked subject ID if selected dub has no streams
      if (streams.isEmpty && targetSubjectId != widget.subjectId) {
        final fallbackStreams = await widget.apiService.fetchPlayInfo(
          widget.subjectId,
          season: season,
          episode: episode,
        );
        if (fallbackStreams.isNotEmpty) {
          streams = fallbackStreams;
          targetSubjectId = widget.subjectId;
        }
      }

      if (!mounted) return;

      if (streams.isEmpty) {
        setState(() {
          _isVideoLoading = false;
          _videoError = 'No stream found in this region.';
        });
        return;
      }

      _streams = streams;
      _currentStream = streams.first;

      final rawUrl = _currentStream!.url;
      final playbackUrl = LocalStreamProxy.instance.registerStream(
        originalUrl: rawUrl,
        signCookie: _currentStream!.signCookie,
      );

      // Initialize media_kit Player if not already created
      if (_player == null) {
        _player = Player(
          configuration: const PlayerConfiguration(
            bufferSize: 32 * 1024 * 1024,
          ),
        );

        _videoController = VideoController(
          _player!,
          configuration: VideoControllerConfiguration(
            hwdec: Platform.isAndroid ? 'mediacodec' : 'auto',
            enableHardwareAcceleration: true,
            androidAttachSurfaceAfterVideoParameters: true,
          ),
        );

        _subscriptions.add(_player!.stream.position.listen((pos) {
          if (mounted) {
            setState(() => _position = pos);
          }
        }));

        _subscriptions.add(_player!.stream.duration.listen((dur) {
          if (mounted) {
            setState(() => _duration = dur);
          }
        }));

        _subscriptions.add(_player!.stream.playing.listen((playing) {
          if (mounted) {
            setState(() => _isPlaying = playing);
            if (playing) {
              WakelockPlus.enable();
            } else {
              WakelockPlus.disable();
              _saveWatchProgress();
            }
          }
        }));

        _subscriptions.add(_player!.stream.error.listen((err) {
          if (mounted && err.isNotEmpty) {
            setState(() {
              _videoError = 'Playback error: $err';
              _isVideoLoading = false;
            });
          }
        }));
      }

      // Read saved watch position
      final history = _storage?.getWatchHistory() ?? [];
      final prevRecord = history.firstWhere(
        (r) => r.subjectId == widget.subjectId,
        orElse: () => LocalRecord(
          subjectId: '',
          title: '',
          subjectType: 1,
          updatedAt: DateTime.now(),
        ),
      );

      Duration? startPos;
      if (prevRecord.positionSeconds > 0) {
        startPos = Duration(seconds: prevRecord.positionSeconds);
      }

      await PlayerShaders.applyPerformanceProperties(_player!);
      await _player!.open(Media(playbackUrl, start: startPos), play: true);
      await _applyActiveVisualEnhancements();

      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted && _isPlaying) {
          _saveWatchProgress();
        }
      });

      if (mounted) {
        setState(() {
          _isVideoLoading = false;
        });
        _startControlsTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _videoError = 'Error loading stream: $e';
        });
      }
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _loadPlayerSettings() {
    if (_storage == null) return;
    _gesturesEnabled = _storage!.playerGesturesEnabled;
    _doubleTapLayout = _storage!.playerDoubleTapLayout;
    _seekDurationX = _storage!.playerSeekDurationX;
    _seekDurationY = _storage!.playerSeekDurationY;
    _longPressSettingSpeed = _storage!.playerLongPressSpeed;
    _longPressDragRate = _storage!.playerLongPressDragRate;
    _applyActiveVisualEnhancements();
  }

  Future<void> _applyActiveVisualEnhancements() async {
    if (_storage == null || _player == null) return;
    try {
      final activeMode = Anime4kMode.fromKey(_storage!.activeAnime4kMode);
      final activeQuality = Anime4kQuality.fromKey(_storage!.activeAnime4kQuality);
      await PlayerShaders.applyShader(
        player: _player!,
        mode: activeMode,
        quality: activeQuality,
      );

      final profile = ColorProfileRegistry.getProfile(
        profileId: _storage!.activeColorProfileId,
        customProfiles: _storage!.customColorProfiles,
      );
      await PlayerShaders.setHardwareColorSettings(
        player: _player!,
        brightness: profile.brightness,
        contrast: profile.contrast,
        saturation: profile.saturation,
        gamma: profile.gamma,
        hue: profile.hue,
      );
    } catch (_) {}
  }

  void _handleDoubleTap(Offset localPos, Size screenSize) {
    if (_player == null) return;

    final rx = (localPos.dx / screenSize.width).clamp(0.0, 1.0);
    final ry = (localPos.dy / screenSize.height).clamp(0.0, 1.0);
    final isUpperHalf = ry < 0.5;

    int seekDelta = 0;
    bool isPlayPause = false;

    if (_doubleTapLayout == '1+1+1') {
      if (rx < 0.35) {
        seekDelta = -_seekDurationX;
      } else if (rx > 0.65) {
        seekDelta = _seekDurationX;
      } else {
        isPlayPause = true;
      }
    } else if (_doubleTapLayout == '2+1+2') {
      if (rx < 0.20) {
        seekDelta = -_seekDurationX;
      } else if (rx < 0.40) {
        seekDelta = -_seekDurationY;
      } else if (rx > 0.80) {
        seekDelta = _seekDurationX;
      } else if (rx > 0.60) {
        seekDelta = _seekDurationY;
      } else {
        isPlayPause = true;
      }
    } else if (_doubleTapLayout == '4+1+4') {
      if (rx < 0.20) {
        seekDelta = isUpperHalf ? -_seekDurationX : _seekDurationX;
      } else if (rx < 0.40) {
        seekDelta = isUpperHalf ? -_seekDurationY : _seekDurationY;
      } else if (rx > 0.80) {
        seekDelta = isUpperHalf ? _seekDurationX : -_seekDurationX;
      } else if (rx > 0.60) {
        seekDelta = isUpperHalf ? _seekDurationY : -_seekDurationY;
      } else {
        isPlayPause = true;
      }
    }

    if (isPlayPause) {
      HapticFeedback.mediumImpact();
      _triggerRipple(
        position: localPos,
        label: _isPlaying ? 'Pause' : 'Play',
        icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        isLeft: false,
      );
      if (_isPlaying) {
        _player?.pause();
      } else {
        _player?.play();
      }
    } else if (seekDelta != 0) {
      HapticFeedback.selectionClick();
      final totalSec = _duration.inSeconds > 0
          ? _duration.inSeconds
          : (_currentStream?.duration ?? 0);
      final currentPos = _player?.state.position ?? _position;
      final newSec = (currentPos.inSeconds + seekDelta).clamp(0, totalSec > 0 ? totalSec : 999999);
      final target = Duration(seconds: newSec);
      _player?.seek(target);

      _triggerRipple(
        position: localPos,
        label: '${seekDelta > 0 ? "+$seekDelta" : seekDelta}s',
        icon: seekDelta > 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
        isLeft: seekDelta < 0,
      );
    }
  }

  void _triggerRipple({
    required Offset position,
    required String label,
    required IconData icon,
    required bool isLeft,
  }) {
    _rippleTimer?.cancel();
    setState(() {
      _activeRipple = _DoubleTapRipple(
        position: position,
        label: label,
        icon: icon,
        isLeft: isLeft,
      );
    });
    _rippleTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _activeRipple = null);
    });
  }

  void _onPanStart(Offset pos, Size screenSize) {
    _controlsTimer?.cancel();
    if (_showControls) {
      setState(() => _showControls = false);
    }
    _panStartPos = pos;
    _activePan = _ActivePanGesture.none;
    _panStartBrightness = _brightness;
    _panStartVolume = _volume;
    _panStartPosition = _player?.state.position ?? _position;
    _panSeekTarget = _panStartPosition;
    _panSpeedTarget = _currentPlaybackSpeed;
  }

  void _onPanUpdate(Offset pos, Size screenSize) {
    if (_panStartPos == null) return;

    final dx = pos.dx - _panStartPos!.dx;
    final dy = pos.dy - _panStartPos!.dy;

    if (_activePan == _ActivePanGesture.none) {
      if (dx.abs() > 10 || dy.abs() > 10) {
        if (dy.abs() > dx.abs()) {
          if (_panStartPos!.dx < screenSize.width * 0.5) {
            _activePan = _ActivePanGesture.brightness;
          } else {
            _activePan = _ActivePanGesture.volume;
          }
        } else {
          if (_panStartPos!.dy > screenSize.height * 0.5) {
            _activePan = _ActivePanGesture.seek;
          } else {
            _activePan = _ActivePanGesture.speed;
          }
        }
      }
    }

    if (_activePan == _ActivePanGesture.brightness) {
      final delta = -dy / (screenSize.height * 0.75);
      final newB = (_panStartBrightness + delta).clamp(0.05, 1.0);
      setState(() {
        _brightness = newB;
        _showHudOverlay(
          title: 'Brightness',
          value: '${(newB * 100).round()}%',
          icon: newB > 0.6
              ? Icons.brightness_7
              : newB > 0.3
                  ? Icons.brightness_6
                  : Icons.brightness_4,
          progress: newB,
        );
      });
    } else if (_activePan == _ActivePanGesture.volume) {
      final delta = -dy / (screenSize.height * 0.75);
      final newV = (_panStartVolume + delta).clamp(0.0, 1.0);
      _player?.setVolume(newV * 100.0);
      setState(() {
        _volume = newV;
        _showHudOverlay(
          title: 'Volume',
          value: '${(newV * 100).round()}%',
          icon: newV > 0.6
              ? Icons.volume_up
              : newV > 0.0
                  ? Icons.volume_down
                  : Icons.volume_mute,
          progress: newV,
        );
      });
    } else if (_activePan == _ActivePanGesture.seek) {
      final totalSec = _duration.inSeconds > 0
          ? _duration.inSeconds
          : (_currentStream?.duration ?? 0);
      final deltaSec = (dx * 0.25).round();
      final targetSec = (_panStartPosition.inSeconds + deltaSec).clamp(0, totalSec > 0 ? totalSec : 999999);
      _panSeekTarget = Duration(seconds: targetSec);
      final sign = deltaSec >= 0 ? '+' : '';
      setState(() {
        _showHudOverlay(
          title: 'Seeking',
          value: '$sign${deltaSec}s [${_formatDuration(_panSeekTarget)} / ${_formatDuration(Duration(seconds: totalSec))}]',
          icon: deltaSec >= 0 ? Icons.fast_forward : Icons.fast_rewind,
          progress: totalSec > 0 ? targetSec / totalSec : null,
        );
      });
    } else if (_activePan == _ActivePanGesture.speed) {
      final delta = (dx / (screenSize.width * 0.5));
      final steps = (delta / 0.1).round();
      final rawSpeed = (1.0 + (steps * 0.25)).clamp(0.5, 3.0);
      _panSpeedTarget = double.parse(rawSpeed.toStringAsFixed(2));
      setState(() {
        _showHudOverlay(
          title: 'Playback Speed',
          value: '${_panSpeedTarget.toStringAsFixed(2)}x',
          icon: Icons.speed,
        );
      });
    }
  }

  void _onPanEnd() {
    if (_activePan == _ActivePanGesture.seek) {
      _player?.seek(_panSeekTarget);
    } else if (_activePan == _ActivePanGesture.speed) {
      _player?.setRate(_panSpeedTarget);
      setState(() => _currentPlaybackSpeed = _panSpeedTarget);
    }

    _activePan = _ActivePanGesture.none;
    _panStartPos = null;

    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showHud = false);
    });
  }

  void _showHudOverlay({
    required String title,
    required String value,
    required IconData icon,
    double? progress,
  }) {
    _hudTitle = title;
    _hudValue = value;
    _hudIcon = icon;
    _hudProgress = progress;
    _showHud = true;
    _hudTimer?.cancel();
  }

  void _onLongPressStart(Offset pos) {
    if (_player == null || !_player!.state.playing) return;
    _controlsTimer?.cancel();
    if (_showControls) {
      _showControls = false;
    }

    if (_isSpeedLocked) {
      HapticFeedback.mediumImpact();
      _isSpeedLocked = false;
      _currentPlaybackSpeed = 1.0;
      _player?.setRate(1.0);
      _showHudOverlay(
        title: 'Speed Unlocked',
        value: '1.0x (Normal)',
        icon: Icons.lock_open,
      );
      _hudTimer?.cancel();
      _hudTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _showHud = false);
      });
      setState(() {});
      return;
    }

    HapticFeedback.mediumImpact();

    _normalSpeedBeforeLongPress = _currentPlaybackSpeed;
    _longPressActiveSpeed = _longPressSettingSpeed;
    _longPressStartY = pos.dy;
    _longPressStartX = pos.dx;
    _isLongPressActive = true;

    _player?.setRate(_longPressActiveSpeed);
    setState(() {});
  }

  void _onLongPressMoveUpdate(Offset pos) {
    if (!_isLongPressActive || _player == null) return;

    final dx = (pos.dx - _longPressStartX).abs();
    if (dx > 45 && !_isSpeedLocked) {
      HapticFeedback.heavyImpact();
      _isSpeedLocked = true;
      _lockedSpeed = _longPressActiveSpeed;
      _showHudOverlay(
        title: '🔒 Speed Locked',
        value: '${_lockedSpeed.toStringAsFixed(1)}x',
        icon: Icons.lock,
      );
      _hudTimer?.cancel();
      _hudTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showHud = false);
      });
      setState(() {});
      return;
    }

    final dy = pos.dy - _longPressStartY;
    final step = (-dy / _longPressDragRate).floor();
    final raw = (_longPressSettingSpeed + (step * 0.1)).clamp(0.5, 4.0);
    final newSpeed = double.parse(raw.toStringAsFixed(1));

    if (newSpeed != _longPressActiveSpeed) {
      HapticFeedback.selectionClick();
      _longPressActiveSpeed = newSpeed;
      if (_isSpeedLocked) _lockedSpeed = newSpeed;
      _player?.setRate(_longPressActiveSpeed);
      setState(() {});
    }
  }

  void _onLongPressEnd() {
    if (!_isLongPressActive || _player == null) return;

    if (_isSpeedLocked) {
      _isLongPressActive = false;
      _currentPlaybackSpeed = _lockedSpeed;
      _player?.setRate(_lockedSpeed);
      setState(() {});
    } else {
      _isLongPressActive = false;
      _player?.setRate(_normalSpeedBeforeLongPress);
      setState(() {});
    }
  }

  void _openPlayerSettings() {
    if (_storage == null || _player == null) return;
    PlayerSettingsSheet.show(
      context: context,
      storage: _storage!,
      player: _player!,
      availableResolutions: _currentStream?.availableResolutions ?? ['1080', '720', '480'],
      currentResolution: '1080',
      onResolutionChanged: (res) {},
      onSettingsChanged: () {
        _loadPlayerSettings();
      },
    );
  }

  Widget _buildBrightnessScrim() {
    final opacity = (1.0 - _brightness).clamp(0.0, 0.9);
    if (opacity <= 0.01) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: opacity * 0.85),
        ),
      ),
    );
  }

  Widget _buildDoubleTapRipple() {
    if (_activeRipple == null) return const SizedBox.shrink();

    return Positioned(
      left: (_activeRipple!.position.dx - 36).clamp(10.0, 300.0),
      top: (_activeRipple!.position.dy - 36).clamp(10.0, 160.0),
      child: IgnorePointer(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.75),
            border: Border.all(color: AppTheme.accentGreen, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentGreen.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_activeRipple!.icon, color: AppTheme.accentGreen, size: 22),
              const SizedBox(height: 2),
              Text(
                _activeRipple!.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGestureHud() {
    return Center(
      child: IgnorePointer(
        child: Container(
          width: 140,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_hudIcon, color: AppTheme.accentGreen, size: 28),
              const SizedBox(height: 4),
              Text(
                _hudTitle,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _hudValue,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_hudProgress != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _hudProgress!.clamp(0.0, 1.0),
                    backgroundColor: Colors.white24,
                    color: AppTheme.accentGreen,
                    minHeight: 3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLongPressSpeedPill() {
    return Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: Center(
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.accentGreen, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentGreen.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: AppTheme.accentGreen, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${_longPressActiveSpeed.toStringAsFixed(1)}x SPEED BOOST',
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '(Drag ↕ • Flick ↔ Lock)',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockedSpeedBadge() {
    if (!_isSpeedLocked || _isLongPressActive) return const SizedBox.shrink();

    return Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _isSpeedLocked = false;
              _currentPlaybackSpeed = 1.0;
              _player?.setRate(1.0);
            });
            _showHudOverlay(
              title: 'Speed Unlocked',
              value: '1.0x (Normal)',
              icon: Icons.lock_open,
            );
            _hudTimer?.cancel();
            _hudTimer = Timer(const Duration(milliseconds: 1200), () {
              if (mounted) setState(() => _showHud = false);
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.accentGreen, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentGreen.withValues(alpha: 0.25),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, color: AppTheme.accentGreen, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${_lockedSpeed.toStringAsFixed(1)}x',
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '(Tap to Unlock)',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startControlsTimer();
    }
  }

  Future<void> _openFullscreenPlayer() async {
    if (_detail == null || _currentStream == null) return;
    _saveWatchProgress();
    final currentPos = _player?.state.position ?? _position;
    await _player?.pause();

    if (!mounted) return;

    final returnedPos = await Navigator.of(context).push<Duration>(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          subjectId: widget.subjectId,
          title: _detail!.title,
          coverUrl: _detail!.coverUrl,
          subjectType: _detail!.subjectType,
          initialStream: _currentStream!,
          allStreams: _streams,
          season: _detail!.isSeries ? _selectedSeason : 0,
          episode: _detail!.isSeries ? _selectedEpisode : 0,
          dubs: _detail?.dubs ?? const [],
          initialDub: _selectedDub,
          seasons: _seasons,
          apiService: widget.apiService,
          initialPosition: currentPos,
        ),
      ),
    );

    if (mounted && _player != null) {
      if (returnedPos != null && returnedPos > Duration.zero) {
        await _player!.seek(returnedPos);
      }
      _saveWatchProgress();
      await _player!.play();
      _startControlsTimer();
    }
  }

  void _showLanguageSelectorSheet() {
    if (_detail == null || _detail!.dubs.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select language',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              ..._detail!.dubs.map((dub) {
                final isSel = _selectedDub?.subjectId == dub.subjectId;
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSel ? const Color(0xFF0F3B34) : AppTheme.bgCard,
                      foregroundColor: isSel ? const Color(0xFF00E5FF) : Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSel ? const Color(0xFF00BFA5) : AppTheme.borderSubtle,
                        ),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      if (_selectedDub?.subjectId != dub.subjectId) {
                        setState(() => _selectedDub = dub);
                        _loadAndPlayStream(
                          season: _detail!.isSeries ? _selectedSeason : 0,
                          episode: _detail!.isSeries ? _selectedEpisode : 0,
                        );
                      }
                    },
                    child: Text(
                      dub.lanName,
                      style: TextStyle(
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showSeasonSelectorSheet() {
    if (_seasons.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_seasons.length} seasons',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              ..._seasons.map((s) {
                final isSel = _selectedSeason == s.seasonNumber;
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSel ? const Color(0xFF0F3B34) : AppTheme.bgCard,
                      foregroundColor: isSel ? const Color(0xFF00E5FF) : Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSel ? const Color(0xFF00BFA5) : AppTheme.borderSubtle,
                        ),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      if (_selectedSeason != s.seasonNumber) {
                        setState(() {
                          _selectedSeason = s.seasonNumber;
                          _selectedEpisode = 1;
                        });
                        _loadAndPlayStream(
                          season: s.seasonNumber,
                          episode: 1,
                        );
                      }
                    },
                    child: Text(
                      'Season ${s.seasonNumber.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showAllEpisodesSheet() {
    if (_seasons.isEmpty) return;
    final currentSeason = _seasons.firstWhere(
      (s) => s.seasonNumber == _selectedSeason,
      orElse: () => _seasons.first,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _showSeasonSelectorSheet();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.borderSubtle),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Season ${_selectedSeason.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(
                      child: GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          childAspectRatio: 1.0,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: currentSeason.maxEp,
                        itemBuilder: (context, epIndex) {
                          final epNum = epIndex + 1;
                          final isEpSel = _selectedEpisode == epNum;
                          return GestureDetector(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              if (_selectedEpisode != epNum) {
                                setState(() => _selectedEpisode = epNum);
                                _loadAndPlayStream(
                                  season: _selectedSeason,
                                  episode: epNum,
                                );
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isEpSel ? const Color(0xFF0F3B34) : AppTheme.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isEpSel ? const Color(0xFF00BFA5) : AppTheme.borderSubtle,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                epNum.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  color: isEpSel ? const Color(0xFF00E5FF) : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showDownloadDialog() async {
    if (_detail == null || _downloadService == null) return;
    final targetSubjectId = _selectedDub?.subjectId ?? widget.subjectId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: AppTheme.accentGreen),
      ),
    );

    var streams = await widget.apiService.fetchPlayInfo(
      targetSubjectId,
      season: _detail!.isSeries ? _selectedSeason : 0,
      episode: _detail!.isSeries ? _selectedEpisode : 0,
    );

    if (streams.isEmpty && targetSubjectId != widget.subjectId) {
      streams = await widget.apiService.fetchPlayInfo(
        widget.subjectId,
        season: _detail!.isSeries ? _selectedSeason : 0,
        episode: _detail!.isSeries ? _selectedEpisode : 0,
      );
    }

    if (mounted) Navigator.of(context).pop();

    if (streams.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active download streams found.')),
        );
      }
      return;
    }

    final stream = streams.first;
    final resolutions = stream.availableResolutions.isNotEmpty
        ? stream.availableResolutions
        : ['720'];

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select Download Quality',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
              ...resolutions.map((res) {
                return ListTile(
                  leading:
                      Icon(Icons.download_rounded, color: AppTheme.accentCyan),
                  title: Text(
                    '${res}p HD',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _downloadService!.startDownload(
                      subjectId: widget.subjectId,
                      title: _detail!.title,
                      coverUrl: _detail!.coverUrl,
                      subjectType: _detail!.subjectType,
                      streamUrl: stream.url,
                      signCookie: stream.signCookie,
                      quality: res,
                      season: _detail!.isSeries ? _selectedSeason : null,
                      episode: _detail!.isSeries ? _selectedEpisode : null,
                    );
                    final epInfo = _detail!.isSeries
                        ? ' S${_selectedSeason.toString().padLeft(2, '0')}E${_selectedEpisode.toString().padLeft(2, '0')}'
                        : '';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Download started for ${_detail!.title}$epInfo (${res}p)')),
                    );
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showInfoSheet() {
    if (_detail == null) return;
    final d = _detail!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    d.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (d.imdbRating != null && d.imdbRating!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.badgeGold.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.badgeGold),
                          ),
                          child: Text(
                            '★ ${d.imdbRating} IMDB',
                            style: const TextStyle(
                              color: AppTheme.badgeGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      if (d.releaseDate != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d.releaseDate!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      if (d.duration != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d.duration!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      if (d.country != null && d.country!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d.country!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      if (d.genre != null && d.genre!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.accentGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            d.genre!,
                            style: TextStyle(
                                color: AppTheme.accentGreen, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Storyline & Overview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    d.description?.isNotEmpty == true
                        ? d.description!
                        : 'No detailed synopsis provided.',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (d.actors.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Cast & Crew',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: d.actors.length,
                        itemBuilder: (context, index) {
                          final actor = d.actors[index];
                          return Container(
                            width: 75,
                            margin: const EdgeInsets.only(right: 12),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: AppTheme.bgCard,
                                  backgroundImage: actor.avatarUrl != null
                                      ? ResizeImage(
                                          CachedNetworkImageProvider(
                                              actor.avatarUrl!),
                                          width: 120,
                                          height: 120,
                                        )
                                      : null,
                                  child: actor.avatarUrl == null
                                      ? const Icon(Icons.person,
                                          color: Colors.white54)
                                      : null,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  actor.name,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleBack() {
    _saveWatchProgress();
    if (_player != null &&
        _player!.state.playing &&
        _currentStream != null &&
        _detail != null &&
        _videoController != null) {
      _isHandedOver = true;
      MiniplayerService.instance.dock(
        player: _player!,
        videoController: _videoController!,
        subjectId: widget.subjectId,
        title: _detail!.title,
        coverUrl: _detail!.coverUrl,
        subjectType: _detail!.subjectType,
        currentStream: _currentStream!,
        allStreams: _streams,
        season: _detail!.isSeries ? _selectedSeason : 0,
        episode: _detail!.isSeries ? _selectedEpisode : 0,
        dubs: _detail!.dubs,
        initialDub: _selectedDub,
        seasons: _seasons,
        apiService: widget.apiService,
        storage: _storage,
      );
    } else {
      _player?.pause();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.bgPrimary,
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.accentGreen)),
      );
    }

    if (_detail == null) {
      return Scaffold(
        backgroundColor: AppTheme.bgPrimary,
        appBar: AppBar(
          backgroundColor: AppTheme.bgPrimary,
          title: const Text('Detail'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 56),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Failed to load content details.',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentGreen),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final d = _detail!;

    return ValueListenableBuilder<bool>(
      valueListenable: PipService.inPipNotifier,
      builder: (context, inPip, child) {
        if (inPip && _videoController != null) {
          return PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Video(
                  controller: _videoController!,
                  controls: NoVideoControls,
                ),
              ),
            ),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBack();
          },
          child: Scaffold(
            backgroundColor: AppTheme.bgPrimary,
            body: SafeArea(
              top: true,
              child: Column(
                children: [
            // 1. TOP PORTRAIT VIDEO PLAYER (Aspect Ratio 16:9)
            _buildPortraitVideoPlayer(d),

            // 2. SCROLLABLE DETAILS & RECOMMENDATION GRID
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title + Info > Button Row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  d.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _showInfoSheet,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Info',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(width: 2),
                                      Icon(Icons.chevron_right,
                                          color: Colors.white70, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Metadata Badges Row (★ Rating, Year, Country, Genre, Seasons)
                          Row(
                            children: [
                              Icon(
                                d.isSeries ? Icons.tv : Icons.movie_outlined,
                                color: Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              const Text('|', style: TextStyle(color: Colors.white24, fontSize: 12)),
                              const SizedBox(width: 6),
                              if (d.imdbRating != null && d.imdbRating!.isNotEmpty) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, color: AppTheme.badgeGold, size: 16),
                                    const SizedBox(width: 3),
                                    Text(
                                      d.imdbRating!,
                                      style: const TextStyle(
                                        color: AppTheme.badgeGold,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 6),
                                const Text('|', style: TextStyle(color: Colors.white24, fontSize: 12)),
                                const SizedBox(width: 6),
                              ],
                              if (d.releaseDate != null) ...[
                                Text(
                                  d.releaseDate!.split('-').first,
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                ),
                                const SizedBox(width: 6),
                                const Text('|', style: TextStyle(color: Colors.white24, fontSize: 12)),
                                const SizedBox(width: 6),
                              ],
                              if (d.country != null && d.country!.isNotEmpty) ...[
                                Text(
                                  d.country!,
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                ),
                                const SizedBox(width: 6),
                                const Text('|', style: TextStyle(color: Colors.white24, fontSize: 12)),
                                const SizedBox(width: 6),
                              ],
                              if (d.genre != null && d.genre!.isNotEmpty) ...[
                                Text(
                                  d.genre!.split(',').first.trim(),
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                ),
                              ],
                              if (d.isSeries && _seasons.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                const Text('|', style: TextStyle(color: Colors.white24, fontSize: 12)),
                                const SizedBox(width: 6),
                                Text(
                                  '${_seasons.length} ${_seasons.length > 1 ? "seasons" : "season"}',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Action Buttons Row (+ Add to list, Share, Download)
                          Row(
                            children: [
                              // Add to list
                              Expanded(
                                child: _buildActionButton(
                                  icon: _isBookmarked
                                      ? Icons.check_circle
                                      : Icons.playlist_add,
                                  label: _isBookmarked
                                      ? 'In List'
                                      : 'Add to list',
                                  color: _isBookmarked
                                      ? AppTheme.accentGreen
                                      : Colors.white,
                                  onTap: () {
                                    setState(
                                        () => _isBookmarked = !_isBookmarked);
                                    _storage?.toggleBookmark(
                                      subjectId: d.subjectId,
                                      title: d.title,
                                      coverUrl: d.coverUrl,
                                      subjectType: d.subjectType,
                                    );
                                  },
                                  onLongPress: () {
                                    if (_storage != null) {
                                      showBouncyCategorySheet(
                                        context: context,
                                        storage: _storage!,
                                        record: LocalRecord(
                                          subjectId: d.subjectId,
                                          title: d.title,
                                          coverUrl: d.coverUrl,
                                          subjectType: d.subjectType,
                                          updatedAt: DateTime.now(),
                                        ),
                                      ).then((_) {
                                        if (mounted) {
                                          setState(() => _isBookmarked =
                                              _storage!
                                                  .isBookmarked(d.subjectId));
                                        }
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Share
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.share_rounded,
                                  label: 'Share',
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(
                                        text:
                                            '${d.title} - Watch on RaenBox'));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Copied link to clipboard!')),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Download
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.download_rounded,
                                  label: 'Download',
                                  onTap: _showDownloadDialog,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Resources Section (Dubbing + Season Dropdown + Episodes)
                          _buildResourcesSection(d),

                          const SizedBox(height: 16),

                          // Tabs Header: For you | Comments
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _activeDetailTab = 0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'For you',
                                      style: TextStyle(
                                        color: _activeDetailTab == 0
                                            ? Colors.white
                                            : Colors.white54,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 28,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: _activeDetailTab == 0
                                            ? AppTheme.accentGreen
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _activeDetailTab = 1),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Comments(99+)',
                                          style: TextStyle(
                                            color: _activeDetailTab == 1
                                                ? Colors.white
                                                : Colors.white54,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Colors.redAccent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 28,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: _activeDetailTab == 1
                                            ? AppTheme.accentGreen
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),

                  // Content of Active Tab (3-Column Grid for "For you")
                  if (_activeDetailTab == 0) ...[
                    if (_isRecommendationsLoading)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.accentGreen,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (_recommendations.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No recommendations available',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.54,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 12,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final rec = _recommendations[index];
                              return _buildRecommendationCard(rec);
                            },
                            childCount: _recommendations.length,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 30)),
                  ] else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(Icons.chat_bubble_outline,
                                  color: Colors.white38, size: 40),
                              const SizedBox(height: 10),
                              const Text(
                                'Join the conversation! Leave a comment for other fans.',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
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

  // -------------------------------------------------------------
  // Top Portrait Video Player Widget
  // -------------------------------------------------------------
  Widget _buildPortraitVideoPlayer(MediaDetail d) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final videoSize = Size(constraints.maxWidth, constraints.maxHeight);

          return Container(
            color: Colors.black,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTapDown: (details) {
                _handleDoubleTap(details.localPosition, videoSize);
              },
              onPanStart: (details) {
                if (!_gesturesEnabled) return;
                _onPanStart(details.localPosition, videoSize);
              },
              onPanUpdate: (details) {
                if (!_gesturesEnabled) return;
                _onPanUpdate(details.localPosition, videoSize);
              },
              onPanEnd: (_) {
                if (!_gesturesEnabled) return;
                _onPanEnd();
              },
              onLongPressStart: (details) {
                if (!_gesturesEnabled) return;
                _onLongPressStart(details.localPosition);
              },
              onLongPressMoveUpdate: (details) {
                if (!_gesturesEnabled) return;
                _onLongPressMoveUpdate(details.localPosition);
              },
              onLongPressEnd: (_) {
                if (!_gesturesEnabled) return;
                _onLongPressEnd();
              },
              onLongPressCancel: () {
                if (!_gesturesEnabled) return;
                _onLongPressEnd();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Video Surface or Backdrop Poster
                  if (_videoController != null &&
                      !_isVideoLoading &&
                      _videoError == null)
                    Video(
                      controller: _videoController!,
                      controls: NoVideoControls,
                    )
                  else if (d.coverUrl != null)
                    CachedNetworkImage(
                      imageUrl: d.coverUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 720,
                      placeholder: (context, url) => Container(color: Colors.black),
                      errorWidget: (context, url, error) => Container(
                        color: AppTheme.bgSecondary,
                        child: const Icon(Icons.movie, size: 48, color: Colors.white24),
                      ),
                    ),

                  // Subtle vignette/gradient overlay
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black87
                        ],
                        stops: [0.0, 0.25, 0.7, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),

                  // Brightness Screen Dimmer
                  _buildBrightnessScrim(),

                  // Double Tap Ripple Effect
                  _buildDoubleTapRipple(),

                  // Gesture HUD (Brightness / Volume / Seek / Speed)
                  if (_showHud) _buildGestureHud(),

                  // Long Press Speed Boost Center Pill
                  if (_isLongPressActive) _buildLongPressSpeedPill(),

                  // Locked Speed Badge (Top Center)
                  _buildLockedSpeedBadge(),

                  // Loading / Error HUD
                  if (_isVideoLoading)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.accentGreen,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Loading stream...',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    )
                  else if (_videoError != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.orangeAccent, size: 36),
                            const SizedBox(height: 6),
                            Text(
                              _videoError!,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentGreen,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                              ),
                              icon: const Icon(Icons.refresh, size: 14),
                              label: const Text('Retry Stream',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () {
                                _loadAndPlayStream(
                                  season: d.isSeries ? _selectedSeason : 0,
                                  episode: d.isSeries ? _selectedEpisode : 0,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Interactive Controls Overlay (suppressed when gestures/HUD are active to avoid overlap)
                  IgnorePointer(
                    ignoring: !_showControls ||
                        _isVideoLoading ||
                        _videoError != null ||
                        _showHud ||
                        _isLongPressActive ||
                        _activePan != _ActivePanGesture.none,
                    child: AnimatedOpacity(
                      opacity: (_showControls &&
                              !_isVideoLoading &&
                              _videoError == null &&
                              !_showHud &&
                              !_isLongPressActive &&
                              _activePan == _ActivePanGesture.none)
                          ? 1.0
                          : 0.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Top Bar (Back, Title, Settings Tune, Pip, Fav, Bookmark)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back_ios_new,
                                        color: Colors.white, size: 18),
                                    onPressed: _handleBack,
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.tune,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    tooltip: 'Player Settings',
                                    onPressed: _openPlayerSettings,
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.picture_in_picture_alt_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    tooltip: 'Picture-in-Picture',
                                    onPressed: () {
                                      PipService.enterPiP();
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isFavorite
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: _isFavorite
                                          ? Colors.redAccent
                                          : Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() => _isFavorite = !_isFavorite);
                                      _storage?.toggleFavorite(
                                        subjectId: d.subjectId,
                                        title: d.title,
                                        coverUrl: d.coverUrl,
                                        subjectType: d.subjectType,
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isBookmarked
                                          ? Icons.bookmark
                                          : Icons.bookmark_border,
                                      color: _isBookmarked
                                          ? AppTheme.accentCyan
                                          : Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(
                                          () => _isBookmarked = !_isBookmarked);
                                      _storage?.toggleBookmark(
                                        subjectId: d.subjectId,
                                        title: d.title,
                                        coverUrl: d.coverUrl,
                                        subjectType: d.subjectType,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Center Play/Pause Overlay Button
                          if (!_isVideoLoading && _videoError == null)
                            Center(
                              child: GestureDetector(
                                onTap: () {
                                  if (_player != null) {
                                    if (_isPlaying) {
                                      _player!.pause();
                                    } else {
                                      _player!.play();
                                    }
                                    _startControlsTimer();
                                  }
                                },
                                child: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Colors.black54,
                                  child: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ),

                          // Bottom Scrub Bar & Fullscreen Button
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (_player != null) {
                                        if (_isPlaying) {
                                          _player!.pause();
                                        } else {
                                          _player!.play();
                                        }
                                      }
                                    },
                                    child: Icon(
                                      _isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 2.5,
                                        thumbShape: const RoundSliderThumbShape(
                                            enabledThumbRadius: 5),
                                        overlayShape: const RoundSliderOverlayShape(
                                            overlayRadius: 10),
                                        activeTrackColor: AppTheme.accentGreen,
                                        inactiveTrackColor: Colors.white24,
                                        thumbColor: AppTheme.accentGreen,
                                      ),
                                      child: Slider(
                                        value: _position.inMilliseconds
                                            .clamp(0, _duration.inMilliseconds)
                                            .toDouble(),
                                        max: _duration.inMilliseconds > 0
                                            ? _duration.inMilliseconds.toDouble()
                                            : 1.0,
                                        onChanged: (val) {
                                          _player?.seek(Duration(
                                              milliseconds: val.toInt()));
                                        },
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _openFullscreenPlayer,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(
                                        Icons.fullscreen_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------
  // Action Pill Button (+ Add to list, Share, Download)
  // -------------------------------------------------------------
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    Color color = Colors.white,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Resources Section (Dubbing + Season Dropdown + Episodes)
  // -------------------------------------------------------------
  Widget _buildResourcesSection(MediaDetail d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Resources',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Uploaded by MovieBox HQ',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Dropdown Buttons Row: [Language Dub ⌵] and [Season 01 ⌵]
        Row(
          children: [
            // Language Dub Dropdown Button
            if (d.dubs.isNotEmpty)
              GestureDetector(
                onTap: _showLanguageSelectorSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedDub?.lanName ?? 'Audio',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                    ],
                  ),
                ),
              ),

            if (d.dubs.isNotEmpty && d.isSeries && _seasons.isNotEmpty)
              const SizedBox(width: 10),

            // Season Selector Dropdown Button
            if (d.isSeries && _seasons.isNotEmpty)
              GestureDetector(
                onTap: _showSeasonSelectorSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Season ${_selectedSeason.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                    ],
                  ),
                ),
              ),
          ],
        ),

        // Horizontal Scrollable Episodes Bar (Series only): [All] [01] [02] [03]...
        if (d.isSeries && _seasons.isNotEmpty) ...[
          const SizedBox(height: 12),
          Builder(
            builder: (ctx) {
              final currentSeason = _seasons.firstWhere(
                (s) => s.seasonNumber == _selectedSeason,
                orElse: () => _seasons.first,
              );
              return SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: currentSeason.maxEp + 1, // +1 for "All"
                  itemBuilder: (context, index) {
                    // Index 0 is the [All] button
                    if (index == 0) {
                      return GestureDetector(
                        onTap: _showAllEpisodesSheet,
                        child: Container(
                          width: 48,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.borderSubtle),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'All',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }

                    final epNum = index;
                    final isEpSel = _selectedEpisode == epNum;
                    return GestureDetector(
                      onTap: () {
                        if (_selectedEpisode != epNum) {
                          setState(() => _selectedEpisode = epNum);
                          _loadAndPlayStream(
                            season: _selectedSeason,
                            episode: epNum,
                          );
                        }
                      },
                      child: Container(
                        width: 44,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: isEpSel ? const Color(0xFF0F3B34) : AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isEpSel ? const Color(0xFF00BFA5) : AppTheme.borderSubtle,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          epNum.toString().padLeft(2, '0'),
                          style: TextStyle(
                            color: isEpSel ? const Color(0xFF00E5FF) : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------
  // Recommendation Card (3-Column Grid Matching Mobile App)
  // -------------------------------------------------------------
  Widget _buildRecommendationCard(MediaItem rec) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailScreen(
              subjectId: rec.subjectId,
              apiService: widget.apiService,
            ),
          ),
        );
      },
      onLongPress: () {
        if (_storage != null) {
          showBouncyCategorySheet(
            context: context,
            storage: _storage!,
            mediaItem: rec,
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: rec.coverUrl ?? '',
                    fit: BoxFit.cover,
                    memCacheWidth: 220,
                    memCacheHeight: 330,
                    placeholder: (context, url) => Container(
                      color: AppTheme.bgCard,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.brandGreen,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppTheme.bgCard,
                      child:
                          const Icon(Icons.movie, color: Colors.white24, size: 28),
                    ),
                  ),
                ),

                // Top Right Language/Category Badge Pill
                if (rec.genre != null && rec.genre!.isNotEmpty)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        rec.genre!.split(',').first.trim(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            rec.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

