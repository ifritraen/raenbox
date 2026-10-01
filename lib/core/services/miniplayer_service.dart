import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/services/local_storage_service.dart';
import '../../data/services/moviebox_api_service.dart';
import '../../features/player/player_screen.dart';
import 'pip_service.dart';

class MiniplayerService {
  MiniplayerService._();
  static final MiniplayerService instance = MiniplayerService._();

  Player? player;
  VideoController? videoController;

  String? subjectId;
  String? title;
  String? coverUrl;
  int subjectType = 0;
  int season = 0;
  int episode = 0;
  StreamLink? currentStream;
  List<StreamLink> allStreams = [];
  List<Dub> dubs = [];
  Dub? initialDub;
  List<SeasonInfo> seasons = [];
  MovieBoxApiService? apiService;
  String? offlineAudioPath;

  final ValueNotifier<bool> isActiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);

  final List<StreamSubscription> _subscriptions = [];
  LocalStorageService? _storage;

  bool get isActive => isActiveNotifier.value;
  bool get isPlaying => isPlayingNotifier.value;

  void init(LocalStorageService storage) {
    _storage = storage;
  }

  /// Dock an existing player into the miniplayer service
  void dock({
    required Player player,
    required VideoController videoController,
    required String subjectId,
    required String title,
    String? coverUrl,
    required int subjectType,
    required StreamLink currentStream,
    List<StreamLink> allStreams = const [],
    int season = 0,
    int episode = 0,
    List<Dub> dubs = const [],
    Dub? initialDub,
    List<SeasonInfo> seasons = const [],
    required MovieBoxApiService apiService,
    String? offlineAudioPath,
    LocalStorageService? storage,
  }) {
    if (_storage == null && storage != null) {
      _storage = storage;
    }

    _clearSubscriptions();

    this.player = player;
    this.videoController = videoController;
    this.subjectId = subjectId;
    this.title = title;
    this.coverUrl = coverUrl;
    this.subjectType = subjectType;
    this.currentStream = currentStream;
    this.allStreams = allStreams;
    this.season = season;
    this.episode = episode;
    this.dubs = dubs;
    this.initialDub = initialDub;
    this.seasons = seasons;
    this.apiService = apiService;
    this.offlineAudioPath = offlineAudioPath;

    isPlayingNotifier.value = player.state.playing;

    _subscriptions.add(player.stream.playing.listen((playing) {
      isPlayingNotifier.value = playing;
      PipService.setAutoPiPEnabled(playing);
    }));

    _subscriptions.add(player.stream.completed.listen((completed) {
      if (completed) {
        isPlayingNotifier.value = false;
      }
    }));

    isActiveNotifier.value = true;
    PipService.setAutoPiPEnabled(player.state.playing);
  }

  /// Toggle play / pause in docked miniplayer
  void playOrPause() {
    if (player == null) return;
    player!.playOrPause();
  }

  /// Save progress to local storage
  void saveProgress() {
    if (player == null || subjectId == null || title == null) return;
    final pos = player!.state.position.inSeconds;
    var dur = player!.state.duration.inSeconds;
    if (dur <= 0 && currentStream != null && currentStream!.duration > 0) {
      dur = currentStream!.duration;
    }
    if (pos > 0 && dur > 0) {
      _storage?.saveWatchProgress(
        subjectId: subjectId!,
        title: title!,
        coverUrl: coverUrl,
        subjectType: subjectType,
        positionSeconds: pos,
        durationSeconds: dur,
      );
    }
  }

  /// Close and dismiss the miniplayer
  void close() {
    if (!isActive) return;
    saveProgress();
    _clearSubscriptions();

    try {
      player?.pause();
      player?.dispose();
    } catch (_) {}

    player = null;
    videoController = null;
    subjectId = null;
    title = null;
    coverUrl = null;
    currentStream = null;
    allStreams = [];
    dubs = [];
    seasons = [];

    PipService.setAutoPiPEnabled(false);
    isPlayingNotifier.value = false;
    isActiveNotifier.value = false;
  }

  /// Expand miniplayer back into full PlayerScreen seamlessly
  void expand(BuildContext context) {
    if (!isActive || player == null || videoController == null || apiService == null) return;

    final p = player!;
    final vc = videoController!;
    final sid = subjectId!;
    final t = title!;
    final cUrl = coverUrl;
    final sType = subjectType;
    final cStream = currentStream!;
    final aStreams = allStreams;
    final s = season;
    final ep = episode;
    final dList = dubs;
    final inDub = initialDub;
    final sList = seasons;
    final api = apiService!;
    final offAudio = offlineAudioPath;

    _clearSubscriptions();
    isActiveNotifier.value = false;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          subjectId: sid,
          title: t,
          coverUrl: cUrl,
          subjectType: sType,
          initialStream: cStream,
          allStreams: aStreams,
          season: s,
          episode: ep,
          dubs: dList,
          initialDub: inDub,
          seasons: sList,
          apiService: api,
          offlineAudioPath: offAudio,
          existingPlayer: p,
          existingVideoController: vc,
        ),
      ),
    );
  }

  void _clearSubscriptions() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
  }
}
