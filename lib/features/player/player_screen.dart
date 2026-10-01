import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/proxy/local_stream_proxy.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/services/local_storage_service.dart';
import '../../data/services/moviebox_api_service.dart';
import '../../core/services/pip_service.dart';
import '../../core/services/miniplayer_service.dart';
import 'player_settings_sheet.dart';
import 'anime4k_color_sheet.dart';

class SubtitleItem {
  final Duration start;
  final Duration end;
  final String text;

  SubtitleItem({required this.start, required this.end, required this.text});
}

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

class PlayerHandoverResult {
  final Duration position;
  final int season;
  final int episode;
  final StreamLink currentStream;
  final Dub? currentDub;
  final Player? player;
  final VideoController? videoController;

  const PlayerHandoverResult({
    required this.position,
    required this.season,
    required this.episode,
    required this.currentStream,
    this.currentDub,
    this.player,
    this.videoController,
  });
}

class PlayerScreen extends StatefulWidget {
  final String subjectId;
  final String title;
  final String? coverUrl;
  final int subjectType;
  final StreamLink initialStream;
  final List<StreamLink> allStreams;
  final int season;
  final int episode;
  final List<Dub> dubs;
  final Dub? initialDub;
  final List<SeasonInfo> seasons;
  final MovieBoxApiService apiService;
  final String? offlineAudioPath;
  final Duration? initialPosition;
  final Player? existingPlayer;
  final VideoController? existingVideoController;
  final bool fromDetailScreen;

  const PlayerScreen({
    super.key,
    required this.subjectId,
    required this.title,
    this.coverUrl,
    required this.subjectType,
    required this.initialStream,
    required this.allStreams,
    this.season = 0,
    this.episode = 0,
    this.dubs = const [],
    this.initialDub,
    this.seasons = const [],
    required this.apiService,
    this.initialPosition,
    this.offlineAudioPath,
    this.existingPlayer,
    this.existingVideoController,
    this.fromDetailScreen = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _ActiveSideDrawer {
  none,
  quality,
  audioTrack,
  subtitles,
  episodes,
  anime4k,
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription> _subscriptions = [];

  late StreamLink _currentStream;
  String _selectedResolution = '1080';
  bool _showControls = true;
  bool _hasError = false;
  String _errorMessage = '';
  Timer? _hideTimer;
  Timer? _progressTimer;
  LocalStorageService? _storage;

  // MediaKit Playback State
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> _pulseNotifier = ValueNotifier<bool>(false);
  bool _isPlaying = false;
  bool _isPlayerInitialized = false;

  // Media Dubs & Episodes
  late List<Dub> _dubs;
  Dub? _currentDub;
  late List<SeasonInfo> _seasons;
  late int _currentSeason;
  late int _currentEpisode;
  bool _isLoadingMedia = false;

  // Subtitles
  List<SubtitleItem> _subtitles = [];
  String? _currentSubtitleText;
  CaptionTrack? _selectedCaption;

  // Player Settings & Gesture Preferences
  bool _gesturesEnabled = true;
  String _doubleTapLayout = '2+1+2';
  int _seekDurationX = 10;
  int _seekDurationY = 5;
  double _longPressSettingSpeed = 2.0;
  int _longPressDragRate = 25;

  bool get _isAnime4kOrColorActive =>
      (_storage?.activeAnime4kMode != 'off' && _storage?.activeAnime4kMode != null) ||
      (_storage?.activeColorProfileId != 'natural' && _storage?.activeColorProfileId != null);

  // Runtime Gesture State
  double _brightness = 1.0;
  double _volume = 1.0;
  double _currentPlaybackSpeed = 1.0;

  // Active HUD Overlay State
  bool _showHud = false;
  Timer? _hudTimer;
  String _hudTitle = '';
  String _hudValue = '';
  IconData _hudIcon = Icons.info_outline;
  double? _hudProgress;

  // Long Press Speed Boost & Lock State
  bool _isLongPressActive = false;
  double _longPressActiveSpeed = 2.0;
  double _normalSpeedBeforeLongPress = 1.0;
  double _longPressStartY = 0.0;
  double _longPressStartX = 0.0;
  bool _isSpeedLocked = false;
  double _lockedSpeed = 1.0;

  // 1-Second Played Time Pulse State
  Timer? _oneSecPulseTimer;
  bool _pulseTick = false;

  // Landscape Right Side Drawer
  _ActiveSideDrawer _activeSideDrawer = _ActiveSideDrawer.none;
  int _drawerSeasonNumber = 1;

  // Pan Gesture Tracking
  _ActivePanGesture _activePan = _ActivePanGesture.none;
  Offset? _panStartPos;
  double _panStartBrightness = 1.0;
  double _panStartVolume = 1.0;
  Duration _panStartPosition = Duration.zero;
  Duration _panSeekTarget = Duration.zero;
  double _panSpeedTarget = 1.0;

  // Double-tap visual ripple
  _DoubleTapRipple? _activeRipple;
  Timer? _rippleTimer;
  bool _isHandedOver = false;

  @override
  void initState() {
    super.initState();
    _currentStream = widget.initialStream;
    _dubs = List.from(widget.dubs);
    _currentDub = widget.initialDub;
    _seasons = List.from(widget.seasons);
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;
    _selectedResolution = _currentStream.availableResolutions.isNotEmpty
        ? _currentStream.availableResolutions.first
        : '1080';

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (widget.existingPlayer != null && widget.existingVideoController != null) {
      _player = widget.existingPlayer!;
      _videoController = widget.existingVideoController!;
      _isPlaying = _player.state.playing;
      _position = _player.state.position;
      _duration = _player.state.duration;
      _positionNotifier.value = _position;
      _durationNotifier.value = _duration;
    } else {
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
        ),
      );

      _videoController = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          hwdec: Platform.isAndroid ? 'mediacodec' : 'auto',
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: true,
        ),
      );
    }

    _setupPlayerStreams();
    _initPlayer();
  }

  void _setupPlayerStreams() {
    _subscriptions.add(_player.stream.position.listen((pos) {
      _position = pos;
      _positionNotifier.value = pos;
      _onPlayerSubtitleUpdate(pos);
    }));

    _subscriptions.add(_player.stream.duration.listen((dur) {
      _duration = dur;
      _durationNotifier.value = dur;
    }));

    _subscriptions.add(_player.stream.playing.listen((playing) {
      _isPlaying = playing;
      _updateWakeLock(playing);
      if (mounted) setState(() {});
    }));

    _subscriptions.add(_player.stream.error.listen((err) {
      if (mounted && err.isNotEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Playback error: $err';
        });
      }
    }));
  }

  void _loadPlayerSettings() {
    if (_storage == null) return;
    setState(() {
      _gesturesEnabled = _storage!.playerGesturesEnabled;
      _doubleTapLayout = _storage!.playerDoubleTapLayout;
      _seekDurationX = _storage!.playerSeekDurationX;
      _seekDurationY = _storage!.playerSeekDurationY;
      _longPressSettingSpeed = _storage!.playerLongPressSpeed;
      _longPressDragRate = _storage!.playerLongPressDragRate;
    });

    _applyActiveVisualEnhancements();
  }

  Future<void> _applyActiveVisualEnhancements() async {
    if (_storage == null) return;
    final activeMode = Anime4kMode.fromKey(_storage!.activeAnime4kMode);
    final activeQuality = Anime4kQuality.fromKey(_storage!.activeAnime4kQuality);
    await PlayerShaders.applyShader(
      player: _player,
      mode: activeMode,
      quality: activeQuality,
    );

    final profile = ColorProfileRegistry.getProfile(
      profileId: _storage!.activeColorProfileId,
      customProfiles: _storage!.customColorProfiles,
    );
    await PlayerShaders.setHardwareColorSettings(
      player: _player,
      brightness: profile.brightness,
      contrast: profile.contrast,
      saturation: profile.saturation,
      gamma: profile.gamma,
      hue: profile.hue,
    );
  }

  void _showAnime4kColorSheet() {
    setState(() {
      _activeSideDrawer = (_activeSideDrawer == _ActiveSideDrawer.anime4k)
          ? _ActiveSideDrawer.none
          : _ActiveSideDrawer.anime4k;
    });
  }

  Future<void> _initPlayer() async {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    _storage = await LocalStorageService.getInstance();
    _loadPlayerSettings();

    if (widget.existingPlayer != null) {
      _isPlayerInitialized = true;
      _updateWakeLock(_player.state.playing);
      _startHideTimer();
      _startProgressTimer();
      _startPulseTimer();
      if (_currentStream.captions.isNotEmpty && _selectedCaption == null) {
        final enCap = _currentStream.captions.firstWhere(
          (c) =>
              c.language.toLowerCase().contains('en') ||
              c.lanName.toLowerCase().contains('english'),
          orElse: () => _currentStream.captions.first,
        );
        _loadSubtitleTrack(enCap);
      }
      if (mounted) setState(() {});
      return;
    }

    // Background fetch seasons if series and empty
    if (_seasons.isEmpty && widget.subjectType == 2) {
      widget.apiService.fetchSeasonInfo(widget.subjectId).then((sList) {
        if (mounted && sList.isNotEmpty) {
          setState(() => _seasons = sList);
        }
      });
    }

    // Background fetch dubs if empty
    if (_dubs.isEmpty) {
      widget.apiService.fetchDetail(widget.subjectId).then((det) {
        if (mounted && det != null && det.dubs.isNotEmpty) {
          setState(() {
            _dubs = det.dubs;
            if (_currentDub == null && det.dubs.isNotEmpty) {
              _currentDub = det.dubs.first;
            }
          });
        }
      });
    }

    final rawUrl = _currentStream.url;
    final playbackUrl = LocalStreamProxy.instance.registerStream(
      originalUrl: rawUrl,
      signCookie: _currentStream.signCookie,
    );

    try {
      // Check if we have previous watch progress
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
      if (widget.initialPosition != null && widget.initialPosition! > Duration.zero) {
        startPos = widget.initialPosition;
      } else if (prevRecord.positionSeconds > 0) {
        startPos = Duration(seconds: prevRecord.positionSeconds);
      }

      // Set low-level mpv performance properties (direct mediacodec, loop-filter skip, threads)
      await PlayerShaders.applyPerformanceProperties(_player);

      await _player.open(Media(playbackUrl, start: startPos), play: true);

      // Attach offline audio track if available
      if (widget.offlineAudioPath != null && File(widget.offlineAudioPath!).existsSync()) {
        try {
          await _player.setAudioTrack(AudioTrack.uri('file://${widget.offlineAudioPath!}'));
        } catch (_) {}
      }

      await _applyActiveVisualEnhancements();

      _isPlayerInitialized = true;
      _updateWakeLock(true);
      _startHideTimer();
      _startProgressTimer();
      _startPulseTimer();

      // Auto-load English subtitle if available
      if (_currentStream.captions.isNotEmpty && _selectedCaption == null) {
        final enCap = _currentStream.captions.firstWhere(
          (c) => c.language.toLowerCase().contains('en') || c.lanName.toLowerCase().contains('english'),
          orElse: () => _currentStream.captions.first,
        );
        _loadSubtitleTrack(enCap);
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to load video stream ($e)';
        });
      }
    }
  }

  void _onPlayerSubtitleUpdate(Duration pos) {
    if (_subtitles.isEmpty) {
      if (_currentSubtitleText != null) setState(() => _currentSubtitleText = null);
      return;
    }

    SubtitleItem? match;
    for (final s in _subtitles) {
      if (pos >= s.start && pos <= s.end) {
        match = s;
        break;
      }
    }

    final newText = match?.text;
    if (newText != _currentSubtitleText) {
      setState(() => _currentSubtitleText = newText);
    }
  }

  Future<void> _loadSubtitleTrack(CaptionTrack? caption) async {
    _selectedCaption = caption;
    _subtitles.clear();
    _currentSubtitleText = null;

    if (caption == null || caption.url.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    try {
      final res = await http.get(Uri.parse(caption.url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final content = utf8.decode(res.bodyBytes, allowMalformed: true);
        _subtitles = _parseSrt(content);
      }
    } catch (_) {}

    if (mounted) setState(() {});
  }

  List<SubtitleItem> _parseSrt(String content) {
    final items = <SubtitleItem>[];
    final blocks = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n\n');
    final timeRegex = RegExp(
        r'(\d{2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{1,3})');

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;
      final match = timeRegex.firstMatch(block);
      if (match != null) {
        final startMs = int.parse(match.group(4)!.padRight(3, '0'));
        final endMs = int.parse(match.group(8)!.padRight(3, '0'));
        final start = Duration(
          hours: int.parse(match.group(1)!),
          minutes: int.parse(match.group(2)!),
          seconds: int.parse(match.group(3)!),
          milliseconds: startMs,
        );
        final end = Duration(
          hours: int.parse(match.group(5)!),
          minutes: int.parse(match.group(6)!),
          seconds: int.parse(match.group(7)!),
          milliseconds: endMs,
        );
        final textLines = lines.skipWhile((l) => !l.contains('-->')).skip(1).join('\n').trim();
        if (textLines.isNotEmpty) {
          items.add(SubtitleItem(start: start, end: end, text: textLines));
        }
      }
    }
    return items;
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveProgress();
    });
  }

  void _startPulseTimer() {
    _oneSecPulseTimer?.cancel();
    _oneSecPulseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPlayerInitialized && _isPlaying && _showControls) {
        _pulseTick = !_pulseTick;
        _pulseNotifier.value = _pulseTick;
      }
    });
  }

  void _saveProgress() {
    if (!_isPlayerInitialized) return;
    final pos = _position.inSeconds;
    var dur = _duration.inSeconds;
    if (dur <= 0 && _currentStream.duration > 0) {
      dur = _currentStream.duration;
    }
    if (dur > 0 && pos > 0) {
      _storage?.saveWatchProgress(
        subjectId: widget.subjectId,
        title: widget.title,
        coverUrl: widget.coverUrl,
        subjectType: widget.subjectType,
        positionSeconds: pos,
        durationSeconds: dur,
      );
    }
  }

  void _updateWakeLock(bool isPlaying) {
    if (_storage?.isKeepScreenAwake == true) {
      WakelockPlus.enable();
    } else {
      if (isPlaying) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    }
  }

  @override
  void dispose() {
    _saveProgress();
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _oneSecPulseTimer?.cancel();
    _hudTimer?.cancel();
    _rippleTimer?.cancel();

    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _pulseNotifier.dispose();

    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();

    if (!_isHandedOver) {
      _player.dispose();
    }

    if (_storage?.isKeepScreenAwake != true) {
      WakelockPlus.disable();
    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  void _togglePlayPause() {
    if (!_isPlayerInitialized) return;
    _player.playOrPause();
    _startHideTimer();
  }

  void _seekRelative(int seconds) {
    if (!_isPlayerInitialized) return;
    final target = _position + Duration(seconds: seconds);
    _player.seek(target);
    _startHideTimer();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  // ==================== GESTURE LOGIC ====================

  void _handleDoubleTap(Offset localPos, Size screenSize) {
    if (!_isPlayerInitialized) return;

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
    } else if (_doubleTapLayout == '4+1+4') {
      if (rx < 0.20) {
        seekDelta = isUpperHalf ? _seekDurationX : -_seekDurationX;
      } else if (rx < 0.40) {
        seekDelta = isUpperHalf ? _seekDurationY : -_seekDurationY;
      } else if (rx <= 0.60) {
        isPlayPause = true;
      } else if (rx <= 0.80) {
        seekDelta = isUpperHalf ? -_seekDurationY : _seekDurationY;
      } else {
        seekDelta = isUpperHalf ? -_seekDurationX : _seekDurationX;
      }
    } else {
      // Default: '2+1+2'
      if (rx < 0.20) {
        seekDelta = -_seekDurationX;
      } else if (rx < 0.40) {
        seekDelta = -_seekDurationY;
      } else if (rx <= 0.60) {
        isPlayPause = true;
      } else if (rx <= 0.80) {
        seekDelta = _seekDurationY;
      } else {
        seekDelta = _seekDurationX;
      }
    }

    HapticFeedback.lightImpact();

    if (isPlayPause) {
      final wasPlaying = _isPlaying;
      _togglePlayPause();
      _triggerRipple(
        position: localPos,
        label: wasPlaying ? 'Paused' : 'Playing',
        icon: wasPlaying ? Icons.pause : Icons.play_arrow,
        isLeft: rx < 0.5,
      );
    } else if (seekDelta != 0) {
      _seekRelative(seekDelta);
      final isFwd = seekDelta > 0;
      _triggerRipple(
        position: localPos,
        label: '${isFwd ? '+' : ''}${seekDelta}s',
        icon: isFwd ? Icons.fast_forward : Icons.fast_rewind,
        isLeft: rx < 0.5,
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
    _hideTimer?.cancel();
    if (_showControls) {
      setState(() => _showControls = false);
    }
    _panStartPos = pos;
    _activePan = _ActivePanGesture.none;
    _panStartBrightness = _brightness;
    _panStartVolume = _volume;
    _panStartPosition = _position;
    _panSeekTarget = _panStartPosition;
    _panSpeedTarget = _currentPlaybackSpeed;
  }

  void _onPanUpdate(Offset pos, Size screenSize) {
    if (_panStartPos == null) return;

    final dx = pos.dx - _panStartPos!.dx;
    final dy = pos.dy - _panStartPos!.dy;

    if (_activePan == _ActivePanGesture.none) {
      if (dx.abs() > 14 || dy.abs() > 14) {
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
      _player.setVolume(newV * 100.0);
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
      final totalSec = _duration.inSeconds;
      final deltaSec = (dx * 0.25).round();
      final targetSec = (_panStartPosition.inSeconds + deltaSec).clamp(0, totalSec);
      _panSeekTarget = Duration(seconds: targetSec);
      final diff = _panSeekTarget.inSeconds - _panStartPosition.inSeconds;
      final diffStr = diff >= 0
          ? '+${_formatDuration(Duration(seconds: diff))}'
          : '-${_formatDuration(Duration(seconds: diff.abs()))}';
      setState(() {
        _showHudOverlay(
          title: 'Seek ($diffStr)',
          value: '${_formatDuration(_panSeekTarget)} / ${_formatDuration(Duration(seconds: totalSec))}',
          icon: diff >= 0 ? Icons.fast_forward : Icons.fast_rewind,
          progress: totalSec > 0 ? targetSec / totalSec : 0.0,
        );
      });
    } else if (_activePan == _ActivePanGesture.speed) {
      final rawSpeed = _currentPlaybackSpeed + (dx / 300.0);
      final snapped = ((rawSpeed * 4).round() / 4).clamp(0.5, 3.0);
      _panSpeedTarget = snapped;
      setState(() {
        _showHudOverlay(
          title: 'Playback Speed',
          value: '${snapped.toStringAsFixed(2)}x',
          icon: Icons.speed,
          progress: (snapped - 0.5) / 2.5,
        );
      });
    }
  }

  void _onPanEnd() {
    if (_activePan == _ActivePanGesture.seek) {
      _player.seek(_panSeekTarget);
      _startHideTimer();
    } else if (_activePan == _ActivePanGesture.speed) {
      _player.setRate(_panSpeedTarget);
      setState(() => _currentPlaybackSpeed = _panSpeedTarget);
    }

    _activePan = _ActivePanGesture.none;
    _panStartPos = null;

    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 1000), () {
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

  // ==================== LONG PRESS SPEED BOOST ====================

  void _onLongPressStart(Offset pos) {
    if (!_isPlayerInitialized) return;
    _hideTimer?.cancel();
    if (_showControls) {
      _showControls = false;
    }

    if (_isSpeedLocked) {
      HapticFeedback.mediumImpact();
      _isSpeedLocked = false;
      _currentPlaybackSpeed = 1.0;
      _player.setRate(1.0);
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

    _player.setRate(_longPressActiveSpeed);
    setState(() {});
  }

  void _onLongPressMoveUpdate(Offset pos) {
    if (!_isLongPressActive || !_isPlayerInitialized) return;

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
      _player.setRate(_longPressActiveSpeed);
      setState(() {});
    }
  }

  void _onLongPressEnd() {
    if (!_isLongPressActive || !_isPlayerInitialized) return;

    if (_isSpeedLocked) {
      _isLongPressActive = false;
      _currentPlaybackSpeed = _lockedSpeed;
      _player.setRate(_lockedSpeed);
      setState(() {});
    } else {
      _isLongPressActive = false;
      _player.setRate(_normalSpeedBeforeLongPress);
      setState(() {});
    }
  }

  // ==================== STREAM / DUB / EPISODE SWITCHING ====================

  Future<void> _reloadStreamAtPosition(Duration pos, {bool autoPlay = true}) async {
    final rawUrl = _currentStream.url;
    final playbackUrl = LocalStreamProxy.instance.registerStream(
      originalUrl: rawUrl,
      signCookie: _currentStream.signCookie,
    );

    try {
      await _player.open(Media(playbackUrl, start: pos), play: autoPlay);
      await _applyActiveVisualEnhancements();
      _startHideTimer();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _switchDub(Dub dub) async {
    if (_currentDub?.subjectId == dub.subjectId) return;
    final currentPos = _position;
    final wasPlaying = _isPlaying;

    setState(() {
      _currentDub = dub;
      _isLoadingMedia = true;
    });

    try {
      final streams = await widget.apiService.fetchPlayInfo(
        dub.subjectId,
        season: _currentSeason,
        episode: _currentEpisode,
      );

      if (streams.isNotEmpty && mounted) {
        _currentStream = streams.first;
        await _reloadStreamAtPosition(currentPos, autoPlay: wasPlaying);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingMedia = false);
    }
  }

  Future<void> _switchEpisode(int season, int episode) async {
    if (_currentSeason == season && _currentEpisode == episode) return;
    final currentPos = _position;
    final wasPlaying = _isPlaying;

    setState(() {
      _currentSeason = season;
      _currentEpisode = episode;
      _isLoadingMedia = true;
    });

    try {
      final targetSubjectId = _currentDub?.subjectId ?? widget.subjectId;
      final streams = await widget.apiService.fetchPlayInfo(
        targetSubjectId,
        season: season,
        episode: episode,
      );

      if (streams.isNotEmpty && mounted) {
        _currentStream = streams.first;
        await _reloadStreamAtPosition(currentPos, autoPlay: wasPlaying);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingMedia = false);
    }
  }

  void _showQualityPicker() {
    setState(() {
      _activeSideDrawer = (_activeSideDrawer == _ActiveSideDrawer.quality)
          ? _ActiveSideDrawer.none
          : _ActiveSideDrawer.quality;
    });
  }

  void _showAudioTrackPicker() {
    setState(() {
      _activeSideDrawer = (_activeSideDrawer == _ActiveSideDrawer.audioTrack)
          ? _ActiveSideDrawer.none
          : _ActiveSideDrawer.audioTrack;
    });
  }

  void _showSubtitlesPicker() {
    setState(() {
      _activeSideDrawer = (_activeSideDrawer == _ActiveSideDrawer.subtitles)
          ? _ActiveSideDrawer.none
          : _ActiveSideDrawer.subtitles;
    });
  }

  void _showEpisodesPicker() {
    setState(() {
      _drawerSeasonNumber = _currentSeason > 0 ? _currentSeason : 1;
      _activeSideDrawer = (_activeSideDrawer == _ActiveSideDrawer.episodes)
          ? _ActiveSideDrawer.none
          : _ActiveSideDrawer.episodes;
    });
  }

  Widget _buildLockedSpeedBadge() {
    if (!_isSpeedLocked || _isLongPressActive) return const SizedBox.shrink();

    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _isSpeedLocked = false;
              _currentPlaybackSpeed = 1.0;
              _player.setRate(1.0);
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.accentGreen, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentGreen.withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, color: AppTheme.accentGreen, size: 14),
                const SizedBox(width: 6),
                Text(
                  '${_lockedSpeed.toStringAsFixed(1)}x LOCKED',
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '(Tap to Unlock)',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== LANDSCAPE RIGHT-SIDE DRAWER ====================

  Widget _buildRightSideDrawer() {
    final isDrawerOpen = _activeSideDrawer != _ActiveSideDrawer.none;
    final screenWidth = MediaQuery.of(context).size.width;
    final isAnime4k = _activeSideDrawer == _ActiveSideDrawer.anime4k;

    // Standard drawers: ~24% width; Anime4K: ~32% width
    final panelWidth = isAnime4k
        ? (screenWidth * 0.32).clamp(240.0, 340.0)
        : (screenWidth * 0.24).clamp(180.0, 260.0);

    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        offset: isDrawerOpen ? Offset.zero : const Offset(1.0, 0.0),
        child: SizedBox(
          width: panelWidth,
          height: double.infinity,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: isAnime4k
                        ? Colors.black.withValues(alpha: 0.72)
                        : AppTheme.bgSecondary.withValues(alpha: 0.92),
                    border: Border(
                      left: BorderSide(
                        color: isAnime4k
                            ? AppTheme.accentGreen.withValues(alpha: 0.3)
                            : AppTheme.borderSubtle,
                        width: 1.2,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(-4, 0),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    left: false,
                    child: _buildDrawerContent(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerContent() {
    switch (_activeSideDrawer) {
      case _ActiveSideDrawer.quality:
        return _buildQualityDrawer();
      case _ActiveSideDrawer.audioTrack:
        return _buildAudioTrackDrawer();
      case _ActiveSideDrawer.subtitles:
        return _buildSubtitlesDrawer();
      case _ActiveSideDrawer.episodes:
        return _buildEpisodesDrawer();
      case _ActiveSideDrawer.anime4k:
        if (_storage == null) return const SizedBox.shrink();
        return Anime4kColorSheet(
          storage: _storage!,
          player: _player,
          isPanelMode: true,
          onClose: () => setState(() => _activeSideDrawer = _ActiveSideDrawer.none),
          onSettingsChanged: () {
            if (mounted) {
              setState(() {});
            }
          },
        );
      case _ActiveSideDrawer.none:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDrawerHeader(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accentCyan, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _activeSideDrawer = _ActiveSideDrawer.none),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityDrawer() {
    final resolutions = _currentStream.availableResolutions;
    return Column(
      children: [
        _buildDrawerHeader('Quality', Icons.hd_outlined),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: resolutions.length,
            itemBuilder: (context, index) {
              final res = resolutions[index];
              final isSelected = res == _selectedResolution;
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  Icons.hd_outlined,
                  size: 18,
                  color: isSelected ? AppTheme.accentCyan : Colors.white54,
                ),
                title: Text(
                  '${res}p HD',
                  style: TextStyle(
                    color: isSelected ? AppTheme.accentCyan : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
                trailing: isSelected ? Icon(Icons.check, color: AppTheme.accentCyan, size: 16) : null,
                onTap: () {
                  setState(() {
                    _selectedResolution = res;
                    _activeSideDrawer = _ActiveSideDrawer.none;
                  });
                  _showHudOverlay(title: 'Quality', value: '${res}p', icon: Icons.hd);
                  _hudTimer?.cancel();
                  _hudTimer = Timer(const Duration(milliseconds: 1200), () {
                    if (mounted) setState(() => _showHud = false);
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAudioTrackDrawer() {
    return Column(
      children: [
        _buildDrawerHeader('Audio Track', Icons.audiotrack_outlined),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _dubs.length,
            itemBuilder: (context, index) {
              final dub = _dubs[index];
              final isSelected = _currentDub?.subjectId == dub.subjectId;
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  Icons.audiotrack_outlined,
                  size: 18,
                  color: isSelected ? AppTheme.accentGreen : Colors.white54,
                ),
                title: Text(
                  dub.lanName,
                  style: TextStyle(
                    color: isSelected ? AppTheme.accentGreen : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
                trailing: isSelected ? Icon(Icons.check, color: AppTheme.accentGreen, size: 16) : null,
                onTap: () {
                  setState(() => _activeSideDrawer = _ActiveSideDrawer.none);
                  _switchDub(dub);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitlesDrawer() {
    final captions = _currentStream.captions;
    return Column(
      children: [
        _buildDrawerHeader('Subtitles', Icons.subtitles_outlined),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  Icons.subtitles_off_outlined,
                  size: 18,
                  color: _selectedCaption == null ? AppTheme.accentGreen : Colors.white54,
                ),
                title: Text(
                  'Off',
                  style: TextStyle(
                    color: _selectedCaption == null ? AppTheme.accentGreen : Colors.white,
                    fontWeight: _selectedCaption == null ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
                trailing: _selectedCaption == null ? Icon(Icons.check, color: AppTheme.accentGreen, size: 16) : null,
                onTap: () {
                  setState(() => _activeSideDrawer = _ActiveSideDrawer.none);
                  _loadSubtitleTrack(null);
                },
              ),
              ...captions.map((c) {
                final isSelected = _selectedCaption?.url == c.url;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.subtitles_outlined,
                    size: 18,
                    color: isSelected ? AppTheme.accentGreen : Colors.white54,
                  ),
                  title: Text(
                    c.lanName.isNotEmpty ? c.lanName : c.language,
                    style: TextStyle(
                      color: isSelected ? AppTheme.accentGreen : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                  trailing: isSelected ? Icon(Icons.check, color: AppTheme.accentGreen, size: 16) : null,
                  onTap: () {
                    setState(() => _activeSideDrawer = _ActiveSideDrawer.none);
                    _loadSubtitleTrack(c);
                  },
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodesDrawer() {
    final activeSeason = _seasons.firstWhere(
      (s) => s.seasonNumber == _drawerSeasonNumber,
      orElse: () => _seasons.isNotEmpty ? _seasons.first : SeasonInfo(seasonNumber: 1, maxEp: 24),
    );

    return Column(
      children: [
        _buildDrawerHeader('Episodes', Icons.video_library_outlined),
        if (_seasons.length > 1)
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _seasons.length,
              separatorBuilder: (_, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final s = _seasons[index];
                final isSel = s.seasonNumber == _drawerSeasonNumber;
                return ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  selected: isSel,
                  selectedColor: AppTheme.accentGreen.withValues(alpha: 0.25),
                  backgroundColor: AppTheme.bgCard,
                  side: BorderSide(color: isSel ? AppTheme.accentGreen : AppTheme.borderSubtle),
                  label: Text(
                    'S${s.seasonNumber}',
                    style: TextStyle(
                      color: isSel ? AppTheme.accentGreen : Colors.white70,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      fontSize: 11,
                    ),
                  ),
                  onSelected: (_) => setState(() => _drawerSeasonNumber = s.seasonNumber),
                );
              },
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.3,
            ),
            itemCount: activeSeason.maxEp > 0 ? activeSeason.maxEp : 24,
            itemBuilder: (context, index) {
              final epNum = index + 1;
              final isEpSel = _currentSeason == _drawerSeasonNumber && _currentEpisode == epNum;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() => _activeSideDrawer = _ActiveSideDrawer.none);
                  _switchEpisode(_drawerSeasonNumber, epNum);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isEpSel ? AppTheme.accentGreen : AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isEpSel ? AppTheme.accentGreen : AppTheme.borderSubtle),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$epNum',
                    style: TextStyle(
                      color: isEpSel ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== PLAYER SETTINGS DIALOG ====================

  void _openPlayerSettings() {
    if (_storage == null) return;
    PlayerSettingsSheet.show(
      context: context,
      storage: _storage!,
      player: _player,
      availableResolutions: _currentStream.availableResolutions,
      currentResolution: _selectedResolution,
      onResolutionChanged: (res) {
        setState(() => _selectedResolution = res);
      },
      onSettingsChanged: () {
        _loadPlayerSettings();
      },
    );
  }

  void _handleBack() {
    _saveProgress();
    if (widget.fromDetailScreen) {
      _isHandedOver = true;
      Navigator.of(context).pop(
        PlayerHandoverResult(
          position: _player.state.position,
          season: _currentSeason,
          episode: _currentEpisode,
          currentStream: _currentStream,
          currentDub: _currentDub,
          player: _player,
          videoController: _videoController,
        ),
      );
      return;
    }
    if (_player.state.playing) {
      _isHandedOver = true;
      MiniplayerService.instance.dock(
        player: _player,
        videoController: _videoController,
        subjectId: widget.subjectId,
        title: widget.title,
        coverUrl: widget.coverUrl,
        subjectType: widget.subjectType,
        currentStream: _currentStream,
        allStreams: widget.allStreams,
        season: _currentSeason,
        episode: _currentEpisode,
        dubs: _dubs,
        initialDub: _currentDub,
        seasons: _seasons,
        apiService: widget.apiService,
        offlineAudioPath: widget.offlineAudioPath,
        storage: _storage,
      );
    } else {
      _player.pause();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return ValueListenableBuilder<bool>(
      valueListenable: PipService.inPipNotifier,
      builder: (context, inPip, _) {
        if (inPip && _isPlayerInitialized) {
          return PopScope(
            canPop: true,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Video(
                  controller: _videoController,
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
            backgroundColor: Colors.black,
            body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _showControls = !_showControls);
          if (_showControls) _startHideTimer();
        },
        onDoubleTapDown: (details) {
          _handleDoubleTap(details.localPosition, screenSize);
        },
        onPanStart: (details) {
          if (!_gesturesEnabled) return;
          _onPanStart(details.localPosition, screenSize);
        },
        onPanUpdate: (details) {
          if (!_gesturesEnabled) return;
          _onPanUpdate(details.localPosition, screenSize);
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
            // Video View (Native libmpv GPU Pipeline)
            if (_isPlayerInitialized)
              Center(
                child: Video(
                  controller: _videoController,
                  fit: BoxFit.contain,
                  controls: null,
                ),
              )
            else if (_hasError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen),
                      icon: const Icon(Icons.refresh, color: Colors.black),
                      label: const Text('Retry Playback', style: TextStyle(color: Colors.black)),
                      onPressed: _initPlayer,
                    ),
                  ],
                ),
              )
            else
              Center(
                child: CircularProgressIndicator(color: AppTheme.accentGreen),
              ),

            // Brightness Screen Dimmer
            _buildBrightnessScrim(),

            // Live Subtitle Overlay
            if (_currentSubtitleText != null && _currentSubtitleText!.isNotEmpty)
              Positioned(
                bottom: _showControls ? 80 : 32,
                left: 32,
                right: 32,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _currentSubtitleText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(blurRadius: 3.0, color: Colors.black, offset: Offset(1, 1)),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

            // Loading Indicator for Dub / Episode Transitions
            if (_isLoadingMedia)
              Center(
                child: CircularProgressIndicator(color: AppTheme.accentGreen),
              ),

            // Double Tap Ripple Effect
            _buildDoubleTapRipple(),

            // Gesture HUD (Brightness / Volume / Seek / Speed)
            if (_showHud) _buildGestureHud(),

            // Long Press Speed Boost Center Pill
            if (_isLongPressActive) _buildLongPressSpeedPill(),

            // Locked Speed Badge (Top Center)
            _buildLockedSpeedBadge(),

            // Controls Overlay with Smooth Animation (suppressed during active HUD or gestures to prevent overlap)
            IgnorePointer(
              ignoring: !_showControls || _hasError || _showHud || _isLongPressActive || _activePan != _ActivePanGesture.none,
              child: AnimatedOpacity(
                opacity: (_showControls && !_hasError && !_showHud && !_isLongPressActive && _activePan == _ActivePanGesture.none) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildTopBar(),
                    if (_isPlayerInitialized) ...[
                      _buildCenterControls(),
                      _buildBottomBar(),
                    ],
                  ],
                ),
              ),
            ),

            // Landscape Right Side Drawer for Quality, Audio, Subtitles, Episodes, Anime4K
            _buildRightSideDrawer(),
          ],
        ),
      ),
    ),
  );
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
      left: _activeRipple!.position.dx - 45,
      top: _activeRipple!.position.dy - 45,
      child: IgnorePointer(
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.7),
            border: Border.all(color: AppTheme.accentGreen, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentGreen.withValues(alpha: 0.3),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_activeRipple!.icon, color: AppTheme.accentGreen, size: 28),
              const SizedBox(height: 2),
              Text(
                _activeRipple!.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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
          width: 160,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_hudIcon, color: AppTheme.accentGreen, size: 36),
              const SizedBox(height: 6),
              Text(
                _hudTitle,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                _hudValue,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              if (_hudProgress != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _hudProgress!.clamp(0.0, 1.0),
                    backgroundColor: Colors.white24,
                    color: AppTheme.accentGreen,
                    minHeight: 4,
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
      top: 24,
      left: 0,
      right: 0,
      child: Center(
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.accentGreen, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentGreen.withValues(alpha: 0.3),
                  blurRadius: 14,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: AppTheme.accentGreen, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${_longPressActiveSpeed.toStringAsFixed(1)}x SPEED BOOST',
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '(Drag ↕ Tune • Flick ↔ Lock)',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final title = widget.subjectType == 2
        ? '${widget.title} - S${_currentSeason}E$_currentEpisode'
        : widget.title;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black87, Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _handleBack,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Dedicated PiP Button
            IconButton(
              icon: const Icon(
                Icons.picture_in_picture_alt_outlined,
                color: Colors.white70,
                size: 20,
              ),
              tooltip: 'Picture-in-Picture',
              onPressed: () => PipService.enterPiP(),
            ),

            // 1. Dedicated Subtitles Button
            IconButton(
              icon: Icon(
                _selectedCaption != null ? Icons.subtitles : Icons.subtitles_outlined,
                color: _selectedCaption != null ? AppTheme.accentGreen : Colors.white70,
                size: 20,
              ),
              tooltip: 'Subtitles',
              onPressed: _showSubtitlesPicker,
            ),

            // 2. Dedicated Audio Track Button
            if (_dubs.isNotEmpty)
              IconButton(
                icon: Icon(
                  _currentDub != null ? Icons.audiotrack : Icons.audiotrack_outlined,
                  color: _currentDub != null ? AppTheme.accentGreen : Colors.white70,
                  size: 20,
                ),
                tooltip: 'Audio Track',
                onPressed: _showAudioTrackPicker,
              ),

            // 3. Dedicated Episodes Button
            if (widget.subjectType == 2 || _seasons.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.video_library_outlined, color: Colors.white70, size: 20),
                tooltip: 'Episodes',
                onPressed: _showEpisodesPicker,
              ),

            // 4. Real Anime4K & Color Profiles Button
            IconButton(
              icon: Icon(
                _isAnime4kOrColorActive ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                color: _isAnime4kOrColorActive ? AppTheme.accentGreen : Colors.white70,
                size: 20,
              ),
              tooltip: 'Anime4K & Color Profiles',
              onPressed: _showAnime4kColorSheet,
            ),

            // 5. Dedicated Resolution Pill Button
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _showQualityPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_selectedResolution}p',
                      style: TextStyle(
                        color: AppTheme.accentCyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_drop_down, color: AppTheme.accentCyan, size: 14),
                  ],
                ),
              ),
            ),

            // 6. Unified Player & Gesture Settings Button
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white70, size: 20),
              tooltip: 'Player Settings',
              onPressed: _openPlayerSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 42,
          icon: const Icon(Icons.replay_10, color: Colors.white),
          onPressed: () => _seekRelative(-_seekDurationX),
        ),
        const SizedBox(width: 32),
        IconButton(
          iconSize: 64,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              key: ValueKey<bool>(_isPlaying),
              color: AppTheme.accentGreen,
              size: 64,
            ),
          ),
          onPressed: _togglePlayPause,
        ),
        const SizedBox(width: 32),
        IconButton(
          iconSize: 42,
          icon: const Icon(Icons.forward_10, color: Colors.white),
          onPressed: () => _seekRelative(_seekDurationX),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Colors.black87],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ValueListenableBuilder<Duration>(
          valueListenable: _durationNotifier,
          builder: (context, duration, _) {
            return ValueListenableBuilder<Duration>(
              valueListenable: _positionNotifier,
              builder: (context, position, _) {
                return Row(
                  children: [
                    // 1-Second pulsing dot indicator
                    ValueListenableBuilder<bool>(
                      valueListenable: _pulseNotifier,
                      builder: (context, pulseTick, _) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: pulseTick
                                ? AppTheme.accentGreen
                                : AppTheme.accentGreen.withValues(alpha: 0.25),
                            boxShadow: pulseTick
                                ? [
                                    BoxShadow(
                                      color: AppTheme.accentGreen.withValues(alpha: 0.6),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        );
                      },
                    ),
                    Text(
                      _formatDuration(position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: position.inMilliseconds
                            .clamp(0, duration.inMilliseconds)
                            .toDouble(),
                        max: duration.inMilliseconds > 0
                            ? duration.inMilliseconds.toDouble()
                            : 1.0,
                        activeColor: AppTheme.accentGreen,
                        inactiveColor: Colors.white24,
                        onChanged: (val) {
                          _player.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
