import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
  String _selectedResolution = 'auto';
  String _activeQualityTier = '1080';
  Timer? _abrTimer;
  DateTime _lastBufferTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastQualitySwitchTime = DateTime.fromMillisecondsSinceEpoch(0);
  int _consecutiveBufferingCount = 0;
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
  bool _isBuffering = false;
  Timer? _bufferingWatchdogTimer;

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
  int _subDelayMs = 0;
  double _subFontSize = 16;
  double _subBottom = 32;
  bool _subBg = true;
  int _subColor = 0xFFFFFFFF;

  bool _isCaptionEnglish(CaptionTrack c) {
    final l = c.language.toLowerCase().trim();
    final name = c.lanName.toLowerCase().trim();
    return l == 'en' ||
        l == 'eng' ||
        l.startsWith('en-') ||
        l.startsWith('en_') ||
        name.contains('english') ||
        name.contains('inglés') ||
        name.contains('ingles') ||
        name == 'en';
  }

  bool _isEnglishTrack(SubtitleTrack t) {
    final l = (t.language ?? '').toLowerCase().trim();
    final title = (t.title ?? '').toLowerCase().trim();
    return l == 'en' ||
        l == 'eng' ||
        l.startsWith('en-') ||
        l.startsWith('en_') ||
        title.contains('english') ||
        title.contains('eng');
  }

  CaptionTrack? _pickEnglish() {
    for (final c in _currentStream.captions) {
      if (_isCaptionEnglish(c)) {
        return c;
      }
    }
    return null;
  }
  CaptionTrack? _selectedCaption;
  bool _hasAutoSelectedSubtitle = false;

  bool get _isSubtitleActive =>
      _selectedCaption != null ||
      (_isPlayerInitialized &&
          _player.state.track.subtitle.id != 'no' &&
          _player.state.track.subtitle.id.isNotEmpty);

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
    _selectedResolution = 'auto';

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
      _volume = (_player.state.volume / 100.0).clamp(0.0, 3.0);
      _positionNotifier.value = _position;
      _durationNotifier.value = _duration;
    } else {
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 64 * 1024 * 1024,
        ),
      );

      _videoController = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          hwdec: Platform.isAndroid ? 'mediacodec-copy' : 'auto',
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: false,
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

    _subscriptions.add(_player.stream.buffering.listen((buffering) {
      if (_isBuffering != buffering) {
        if (mounted) {
          setState(() {
            _isBuffering = buffering;
          });
        }
        _onBufferingChanged(buffering);
      }
    }));

    _subscriptions.add(_player.stream.error.listen((err) {
      if (mounted && err.isNotEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Playback error: $err';
        });
      }
    }));

    _subscriptions.add(_player.stream.tracks.listen((tracks) {
      if (_selectedCaption != null) {
        _player.setSubtitleTrack(SubtitleTrack.no());
        return;
      }
      if (_hasAutoSelectedSubtitle) return;
      final subTracks = tracks.subtitle;
      if (subTracks.isEmpty) return;

      final enTrack = subTracks.firstWhere(
        (t) => _isEnglishTrack(t),
        orElse: () => SubtitleTrack.no(),
      );

      _hasAutoSelectedSubtitle = true;
      if (enTrack.id != 'no') {
        if (_player.state.track.subtitle.id != enTrack.id) {
          _player.setSubtitleTrack(enTrack);
        }
      } else {
        if (_player.state.track.subtitle.id != 'no') {
          _player.setSubtitleTrack(SubtitleTrack.no());
        }
      }
    }));
  }

  void _onBufferingChanged(bool buffering) {
    _bufferingWatchdogTimer?.cancel();
    if (buffering) {
      _lastBufferTime = DateTime.now();
      _consecutiveBufferingCount++;
      if (_selectedResolution == 'auto' && _consecutiveBufferingCount >= 2) {
        _stepDownQualityInAuto();
      }
      // If buffering continues for over 10 seconds, trigger stream recovery
      _bufferingWatchdogTimer = Timer(const Duration(seconds: 10), () {
        if (_isBuffering && mounted) {
          _recoverStalledPlayback();
        }
      });
    }
  }

  Future<void> _recoverStalledPlayback() async {
    debugPrint('[Player] Buffer stalled for >10s, auto-recovering...');
    _showHudOverlay(
      title: 'Buffering',
      value: 'Optimizing connection...',
      icon: Icons.sync,
    );
    _hudTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showHud = false);
    });
    try {
      final currentPos = _position;
      await _refreshStreamCookie();
      // Re-trigger playback by seeking to current position to force demuxer reload
      await _player.seek(currentPos);
      if (!_player.state.playing) {
        await _player.play();
      }
    } catch (e) {
      debugPrint('[Player] Error during auto-recovery: $e');
    }
  }

  Future<String?> _refreshStreamCookie() async {
    try {
      final streams = await widget.apiService.fetchPlayInfo(
        widget.subjectId,
        season: _currentSeason,
        episode: _currentEpisode,
      );
      if (streams.isNotEmpty) {
        final matching = streams.firstWhere(
          (s) => s.id == _currentStream.id || s.format == _currentStream.format,
          orElse: () => streams.first,
        );
        if (matching.signCookie != null && matching.signCookie!.isNotEmpty) {
          _currentStream = matching;
          return matching.signCookie;
        }
      }
    } catch (e) {
      debugPrint('[Player] Failed to refresh stream cookie: $e');
    }
    return null;
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
    _selectedResolution = _storage?.preferredQuality ?? 'auto';
    if (_selectedResolution == 'auto') {
      _startAbrMonitor();
    }
    _loadPlayerSettings();
    _loadSubSettings();
    try {
      await (_player.platform as NativePlayer).setProperty('volume-max', '300');
    } catch (_) {}

    if (widget.existingPlayer != null) {
      _isPlayerInitialized = true;
      _updateWakeLock(_player.state.playing);
      _startHideTimer();
      _startProgressTimer();
      _startPulseTimer();
      final enCaption = _pickEnglish();
      if (enCaption != null && _selectedCaption == null) {
        _hasAutoSelectedSubtitle = true;
        _loadSubtitleTrack(enCaption);
      } else if (_selectedCaption == null) {
        final subTracks = _player.state.tracks.subtitle;
        final enTrack = subTracks.firstWhere(
          (t) => _isEnglishTrack(t),
          orElse: () => SubtitleTrack.no(),
        );
        _hasAutoSelectedSubtitle = true;
        _player.setSubtitleTrack(enTrack);
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
    final basePlaybackUrl = LocalStreamProxy.instance.registerStream(
      originalUrl: rawUrl,
      signCookie: _currentStream.signCookie,
      cookieRefresher: _refreshStreamCookie,
    );
    final playbackUrl = _selectedResolution == 'auto'
        ? basePlaybackUrl
        : '$basePlaybackUrl?quality=$_selectedResolution';

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
      final enCaption = _pickEnglish();
      if (enCaption != null && _selectedCaption == null) {
        _hasAutoSelectedSubtitle = true;
        _loadSubtitleTrack(enCaption);
      } else if (_selectedCaption == null) {
        final subTracks = _player.state.tracks.subtitle;
        final enTrack = subTracks.firstWhere(
          (t) => _isEnglishTrack(t),
          orElse: () => SubtitleTrack.no(),
        );
        _hasAutoSelectedSubtitle = true;
        _player.setSubtitleTrack(enTrack);
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
    final t = pos - Duration(milliseconds: _subDelayMs);
    for (final s in _subtitles) {
      if (t >= s.start && t <= s.end) {
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
    _hasAutoSelectedSubtitle = true;
    _selectedCaption = caption;
    _subtitles.clear();
    _currentSubtitleText = null;

    // Disable MPV embedded subtitle track so it doesn't double-render or show Arabic
    try {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } catch (_) {}

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
        final textLines = lines
            .skipWhile((l) => !l.contains('-->'))
            .skip(1)
            .join('\n')
            .replaceAll(RegExp(r'<[^>]*>|\{\\[^}]*\}'), '')
            .trim();
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
    _bufferingWatchdogTimer?.cancel();
    _abrTimer?.cancel();

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
      final newV = (_panStartVolume + delta).clamp(0.0, 3.0);
      if ((_volume <= 1.0 && newV > 1.0) || (_volume > 1.0 && newV <= 1.0)) {
        HapticFeedback.lightImpact();
      }
      _player.setVolume(newV * 100.0);
      final isBoost = newV > 1.0;
      setState(() {
        _volume = newV;
        _showHudOverlay(
          title: isBoost ? 'Volume Boost' : 'Volume',
          value: '${(newV * 100).round()}%',
          icon: isBoost
              ? Icons.volume_up
              : (newV > 0.6
                  ? Icons.volume_up
                  : (newV > 0.0
                      ? Icons.volume_down
                      : Icons.volume_mute)),
          progress: (newV / 3.0).clamp(0.0, 1.0),
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

  Future<void> _reloadStreamAtPosition(Duration pos, {bool autoPlay = true, String? qualityOverride}) async {
    final rawUrl = _currentStream.url;
    final basePlaybackUrl = LocalStreamProxy.instance.registerStream(
      originalUrl: rawUrl,
      signCookie: _currentStream.signCookie,
      cookieRefresher: _refreshStreamCookie,
    );
    final targetQ = qualityOverride ?? _selectedResolution;
    final playbackUrl = (targetQ == 'auto')
        ? basePlaybackUrl
        : '$basePlaybackUrl?quality=$targetQ';

    try {
      await _player.open(Media(playbackUrl, start: pos), play: autoPlay);
      await _applyActiveVisualEnhancements();
      _startHideTimer();

      _hasAutoSelectedSubtitle = false;
      final enCaption = _pickEnglish();
      if (enCaption != null) {
        _hasAutoSelectedSubtitle = true;
        _loadSubtitleTrack(enCaption);
      } else {
        _loadSubtitleTrack(null);
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  // ==================== QUALITY & SMART ABR ENGINE ====================

  void _startAbrMonitor() {
    _abrTimer?.cancel();
    _abrTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_isPlaying || _selectedResolution != 'auto') return;

      final now = DateTime.now();
      // 10s cooldown to prevent switching thrashing
      if (now.difference(_lastQualitySwitchTime).inSeconds < 10) return;

      final bandwidthMbps = LocalStreamProxy.instance.estimatedBandwidthMbps;
      final timeSinceBuffer = now.difference(_lastBufferTime).inSeconds;

      // Emergency downgrade if stalled recently or consecutive buffer events
      if (_consecutiveBufferingCount > 0 || timeSinceBuffer < 8) {
        _consecutiveBufferingCount = 0;
        _stepDownQualityInAuto();
      } else if (_activeQualityTier == '1080' && bandwidthMbps < 2.5) {
        _switchQualityTier('720', isAuto: true);
      } else if (_activeQualityTier == '720' && bandwidthMbps < 1.2) {
        _switchQualityTier('480', isAuto: true);
      }
      // Upgrade if network is smooth and fast for at least 15s
      else if (timeSinceBuffer >= 15) {
        if (_activeQualityTier == '480' && bandwidthMbps >= 2.0) {
          _switchQualityTier('720', isAuto: true);
        } else if (_activeQualityTier == '720' && bandwidthMbps >= 4.0) {
          _switchQualityTier('1080', isAuto: true);
        }
      }
    });
  }

  void _stepDownQualityInAuto() {
    if (_activeQualityTier == '1080') {
      _switchQualityTier('720', isAuto: true);
    } else if (_activeQualityTier == '720') {
      _switchQualityTier('480', isAuto: true);
    }
  }

  Future<void> _switchQualityTier(String targetTier, {bool isAuto = false}) async {
    if (!mounted) return;
    _lastQualitySwitchTime = DateTime.now();
    final prevTier = _activeQualityTier;
    _activeQualityTier = targetTier;

    // 1. Try media_kit VideoTrack switch if multiple video tracks exist
    final videoTracks = _player.state.tracks.video;
    VideoTrack? matchingTrack;
    if (videoTracks.length > 1) {
      final targetH = int.tryParse(targetTier) ?? 1080;
      for (final t in videoTracks) {
        if (t.h != null && (t.h! - targetH).abs() < 60) {
          matchingTrack = t;
          break;
        } else if (t.title?.contains(targetTier) ?? false) {
          matchingTrack = t;
          break;
        }
      }
    }

    if (matchingTrack != null && _player.state.track.video.id != matchingTrack.id) {
      await _player.setVideoTrack(matchingTrack);
      if (mounted) setState(() {});
      if (isAuto && prevTier != targetTier) {
        _showHudOverlay(
          title: 'Auto Quality',
          value: '${targetTier}p',
          icon: Icons.speed,
        );
      }
      return;
    }

    // 2. Seamless reload via LocalStreamProxy manifest filter at current playback position
    final pos = _player.state.position;
    final isPlaying = _player.state.playing;
    await _reloadStreamAtPosition(pos, autoPlay: isPlaying, qualityOverride: targetTier);
    if (isAuto && prevTier != targetTier) {
      _showHudOverlay(
        title: 'Auto Quality',
        value: '${targetTier}p',
        icon: Icons.speed,
      );
    }
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
    final options = ['auto', ...resolutions];
    return Column(
      children: [
        _buildDrawerHeader('Quality', Icons.hd_outlined),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: options.length,
            itemBuilder: (context, index) {
              final res = options[index];
              final isSelected = res == _selectedResolution;
              final isAuto = res == 'auto';
              final label = isAuto
                  ? 'Auto (Smooth Adaptive)'
                  : '${res}p ${res == '1080' ? 'Full HD' : (res == '720' ? 'HD' : 'SD')}';
              final subtitle = isAuto
                  ? 'Adapts to connection speed (Current: ${_activeQualityTier}p)'
                  : null;

              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  isAuto ? Icons.speed_rounded : Icons.hd_outlined,
                  size: 18,
                  color: isSelected ? AppTheme.accentCyan : Colors.white54,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppTheme.accentCyan : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
                subtitle: subtitle != null
                    ? Text(
                        subtitle,
                        style: TextStyle(
                          color: isSelected ? AppTheme.accentCyan.withValues(alpha: 0.7) : Colors.white38,
                          fontSize: 10,
                        ),
                      )
                    : null,
                trailing: isSelected ? Icon(Icons.check, color: AppTheme.accentCyan, size: 16) : null,
                onTap: () async {
                  setState(() {
                    _selectedResolution = res;
                    _activeSideDrawer = _ActiveSideDrawer.none;
                  });
                  await _storage?.setPreferredQuality(res);
                  if (res == 'auto') {
                    _startAbrMonitor();
                    _showHudOverlay(title: 'Quality', value: 'Auto (${_activeQualityTier}p)', icon: Icons.speed);
                  } else {
                    _abrTimer?.cancel();
                    await _switchQualityTier(res, isAuto: false);
                    _showHudOverlay(title: 'Quality', value: '${res}p', icon: Icons.hd);
                  }
                  _hudTimer?.cancel();
                  _hudTimer = Timer(const Duration(milliseconds: 1400), () {
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
    final sortedCaptions = List<CaptionTrack>.from(captions);
    sortedCaptions.sort((a, b) {
      final aEn = _isCaptionEnglish(a);
      final bEn = _isCaptionEnglish(b);
      if (aEn && !bEn) return -1;
      if (!aEn && bEn) return 1;
      final aName = a.lanName.isNotEmpty ? a.lanName : a.language;
      final bName = b.lanName.isNotEmpty ? b.lanName : b.language;
      return aName.compareTo(bName);
    });

    final embeddedTracks = _player.state.tracks.subtitle
        .where((t) => t.id != 'no' && t.id != 'auto')
        .toList();
    embeddedTracks.sort((a, b) {
      final aEn = _isEnglishTrack(a);
      final bEn = _isEnglishTrack(b);
      if (aEn && !bEn) return -1;
      if (!aEn && bEn) return 1;
      final aName = (a.title != null && a.title!.isNotEmpty) ? a.title! : (a.language ?? a.id);
      final bName = (b.title != null && b.title!.isNotEmpty) ? b.title! : (b.language ?? b.id);
      return aName.compareTo(bName);
    });

    final isOff = _selectedCaption == null &&
        (_player.state.track.subtitle.id == 'no' || _player.state.track.subtitle.id.isEmpty);

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
                  color: isOff ? AppTheme.accentGreen : Colors.white54,
                ),
                title: Text(
                  'Off',
                  style: TextStyle(
                    color: isOff ? AppTheme.accentGreen : Colors.white,
                    fontWeight: isOff ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
                trailing: isOff ? Icon(Icons.check, color: AppTheme.accentGreen, size: 16) : null,
                onTap: () {
                  setState(() => _activeSideDrawer = _ActiveSideDrawer.none);
                  _loadSubtitleTrack(null);
                },
              ),
              ...sortedCaptions.map((c) {
                final isSelected = _selectedCaption?.url == c.url;
                final isEn = _isCaptionEnglish(c);
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.subtitles_outlined,
                    size: 18,
                    color: isSelected ? AppTheme.accentGreen : (isEn ? Colors.white : Colors.white54),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.lanName.isNotEmpty ? c.lanName : c.language,
                          style: TextStyle(
                            color: isSelected ? AppTheme.accentGreen : Colors.white,
                            fontWeight: (isSelected || isEn) ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (isEn)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.accentGreen.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'EN',
                            style: TextStyle(
                              color: AppTheme.accentGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                        ),
                    ],
                  ),
                  trailing: isSelected ? Icon(Icons.check, color: AppTheme.accentGreen, size: 16) : null,
                  onTap: () {
                    setState(() => _activeSideDrawer = _ActiveSideDrawer.none);
                    _loadSubtitleTrack(c);
                  },
                );
              }),
              if (embeddedTracks.isNotEmpty) ...[
                if (sortedCaptions.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Text(
                      'EMBEDDED TRACKS',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ...embeddedTracks.map((t) {
                  final isSelected = _selectedCaption == null && _player.state.track.subtitle.id == t.id;
                  final isEn = _isEnglishTrack(t);
                  final label = (t.title != null && t.title!.isNotEmpty)
                      ? t.title!
                      : ((t.language != null && t.language!.isNotEmpty) ? t.language! : 'Track ${t.id}');
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      Icons.closed_caption_outlined,
                      size: 18,
                      color: isSelected ? AppTheme.accentGreen : (isEn ? Colors.white : Colors.white54),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isSelected ? AppTheme.accentGreen : Colors.white,
                              fontWeight: (isSelected || isEn) ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (isEn)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.accentGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'EN',
                              style: TextStyle(
                                color: AppTheme.accentGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: isSelected ? Icon(Icons.check, color: AppTheme.accentGreen, size: 16) : null,
                    onTap: () {
                      _hasAutoSelectedSubtitle = true;
                      setState(() {
                        _activeSideDrawer = _ActiveSideDrawer.none;
                        _selectedCaption = null;
                        _subtitles.clear();
                        _currentSubtitleText = null;
                      });
                      _player.setSubtitleTrack(t);
                    },
                  );
                }),
              ],
              const Divider(color: Colors.white12),
              _subSlider('Delay ${(_subDelayMs / 1000).toStringAsFixed(1)}s', _subDelayMs.toDouble(), -5000, 5000,
                  (v) => _subDelayMs = (v / 100).round() * 100),
              _subSlider('Size ${_subFontSize.round()}', _subFontSize, 10, 36, (v) => _subFontSize = v),
              _subSlider('Bottom ${_subBottom.round()}', _subBottom, 8, 140, (v) => _subBottom = v),
              SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                activeThumbColor: AppTheme.accentGreen,
                title: const Text('Background', style: TextStyle(color: Colors.white, fontSize: 12)),
                value: _subBg,
                onChanged: (v) => setState(() {
                  _subBg = v;
                  _saveSubSettings();
                }),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Wrap(
                  spacing: 8,
                  children: [0xFFFFFFFF, 0xFFFFEB3B, 0xFF69F0AE, 0xFF40C4FF, 0xFFFF8A80].map((c) {
                    return GestureDetector(
                      onTap: () => setState(() {
                        _subColor = c;
                        _saveSubSettings();
                      }),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _subColor == c ? AppTheme.accentGreen : Colors.white24,
                            width: 2,
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
      ],
    );
  }

  Widget _subSlider(String label, double value, double min, double max, void Function(double) onChange) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          SizedBox(
            height: 28,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              activeColor: AppTheme.accentGreen,
              onChanged: (v) => setState(() => onChange(v)),
              onChangeEnd: (_) => _saveSubSettings(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSubSettings() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _subDelayMs = p.getInt('sub_delay') ?? 0;
      _subFontSize = p.getDouble('sub_size') ?? 16;
      _subBottom = p.getDouble('sub_bottom') ?? 32;
      _subBg = p.getBool('sub_bg') ?? true;
      _subColor = p.getInt('sub_color') ?? 0xFFFFFFFF;
    });
  }

  Future<void> _saveSubSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('sub_delay', _subDelayMs);
    await p.setDouble('sub_size', _subFontSize);
    await p.setDouble('sub_bottom', _subBottom);
    await p.setBool('sub_bg', _subBg);
    await p.setInt('sub_color', _subColor);
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
      onResolutionChanged: (res) async {
        setState(() => _selectedResolution = res);
        await _storage?.setPreferredQuality(res);
        if (res == 'auto') {
          _startAbrMonitor();
          _showHudOverlay(title: 'Quality', value: 'Auto (${_activeQualityTier}p)', icon: Icons.speed);
        } else {
          _abrTimer?.cancel();
          await _switchQualityTier(res, isAuto: false);
          _showHudOverlay(title: 'Quality', value: '${res}p', icon: Icons.hd);
        }
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
                bottom: _subBottom,
                left: 32,
                right: 32,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _subBg ? Colors.black.withValues(alpha: 0.6) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _currentSubtitleText!,
                        style: TextStyle(
                          color: Color(_subColor),
                          fontSize: _subFontSize,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(blurRadius: 3.0, color: Colors.black, offset: Offset(1, 1)),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),

            // Loading Indicator for Dub / Episode Transitions or Network Buffering
            if (_isLoadingMedia || (_isBuffering && !_hasError))
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.accentGreen.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: AppTheme.accentGreen,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isLoadingMedia ? 'Loading media...' : 'Buffering...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
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
            if (_activeSideDrawer != _ActiveSideDrawer.none)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _activeSideDrawer = _ActiveSideDrawer.none),
                ),
              ),
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
            color: Colors.black.withValues(alpha: 0.25),
            border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.6), width: 1),
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
    final isBoost = _volume > 1.0 && _hudTitle.contains('Volume');
    final accentColor = isBoost ? const Color(0xFFFF9100) : AppTheme.accentGreen;

    return Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: Center(
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: isBoost ? 0.75 : 0.28),
              borderRadius: BorderRadius.circular(12),
              border: isBoost
                  ? Border.all(color: const Color(0xFFFF9100).withValues(alpha: 0.6), width: 1.2)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_hudIcon, color: accentColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  _hudTitle.isEmpty ? _hudValue : '$_hudTitle  $_hudValue',
                  style: TextStyle(
                    color: isBoost ? const Color(0xFFFF9100) : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                if (isBoost) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9100).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'BOOST',
                      style: TextStyle(
                        color: const Color(0xFFFF9100),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
                if (_hudProgress != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _hudProgress!.clamp(0.0, 1.0),
                        backgroundColor: Colors.white24,
                        color: accentColor,
                        minHeight: 2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(12),
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
              icon: Icon(
                Icons.picture_in_picture_alt_outlined,
                color: AppTheme.accentGreen,
                size: 20,
              ),
              tooltip: 'Picture-in-Picture',
              onPressed: () => PipService.enterPiP(),
            ),

            // 1. Dedicated Subtitles Button
            IconButton(
              icon: Icon(
                _isSubtitleActive ? Icons.subtitles : Icons.subtitles_outlined,
                color: _isSubtitleActive ? AppTheme.accentGreen : Colors.white70,
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
                icon: Icon(Icons.video_library_outlined, color: AppTheme.accentGreen, size: 20),
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
                      _selectedResolution == 'auto'
                          ? 'Auto • ${_activeQualityTier}p'
                          : '${_selectedResolution}p',
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
              icon: Icon(Icons.tune, color: AppTheme.accentGreen, size: 20),
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
          icon: Icon(Icons.replay_10, color: AppTheme.accentGreen),
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
          icon: Icon(Icons.forward_10, color: AppTheme.accentGreen),
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
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _handleBack,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.fullscreen_exit_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
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
