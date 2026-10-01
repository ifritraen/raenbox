import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/moviebox_models.dart';
import 'local_storage_service.dart';

enum DownloadStatus { pending, downloading, paused, completed, failed }

class DownloadTask {
  final String id;
  final String subjectId;
  final String title;
  final String? coverUrl;
  final int subjectType;
  final String streamUrl;
  final String? signCookie;
  final String quality;
  final int? season;
  final int? episode;

  double progress = 0.0;
  int receivedBytes = 0;
  int totalBytes = 0;
  DownloadStatus status = DownloadStatus.pending;
  String? filePath;
  String? audioFilePath;
  String? errorMessage;

  int currentChunkIndex = 0;
  int totalChunks = 0;
  double speedBytesPerSec = 0.0;
  int activeThreads = 0;

  HttpClientRequest? _activeRequest;
  bool _cancelRequested = false;

  DownloadTask({
    required this.id,
    required this.subjectId,
    required this.title,
    this.coverUrl,
    required this.subjectType,
    required this.streamUrl,
    this.signCookie,
    required this.quality,
    this.season,
    this.episode,
  });

  bool get isSeries =>
      subjectType == 2 || (season != null && episode != null && season! > 0 && episode! > 0);

  String get formattedSpeed {
    if (speedBytesPerSec <= 0) return '';
    if (speedBytesPerSec < 1024 * 1024) {
      return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get formattedSize {
    if (receivedBytes <= 0) return '0 B';
    if (receivedBytes < 1024 * 1024) {
      return '${(receivedBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (receivedBytes < 1024 * 1024 * 1024) {
      return '${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(receivedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get displayTitle {
    if (isSeries && season != null && episode != null && season! > 0 && episode! > 0) {
      final sStr = season.toString().padLeft(2, '0');
      final eStr = episode.toString().padLeft(2, '0');
      return '$title S${sStr}E$eStr';
    }
    return title;
  }
}

class DownloadService extends ChangeNotifier {
  static DownloadService? _instance;
  final LocalStorageService _storage;
  final Map<String, DownloadTask> _tasks = {};

  static DownloadService getInstance(LocalStorageService storage) {
    _instance ??= DownloadService._(storage);
    return _instance!;
  }

  DownloadService._(this._storage);

  List<DownloadTask> get tasks => _tasks.values.toList();
  List<DownloadTask> get activeTasks =>
      _tasks.values.where((t) => t.status == DownloadStatus.downloading).toList();
  List<DownloadTask> get pendingTasks =>
      _tasks.values.where((t) => t.status == DownloadStatus.pending).toList();

  DownloadTask? getTask(String id) => _tasks[id];

  int get maxConcurrent => _storage.maxConcurrentDownloads;
  int get defaultThreads => _storage.downloadThreads;

  static String buildTaskId(String subjectId, {int? season, int? episode}) {
    if (season != null && episode != null && season > 0 && episode > 0) {
      return '${subjectId}_s${season}_e$episode';
    }
    return subjectId;
  }

  Future<void> startDownload({
    required String subjectId,
    required String title,
    String? coverUrl,
    required int subjectType,
    required String streamUrl,
    String? signCookie,
    required String quality,
    int? season,
    int? episode,
  }) async {
    final taskId = buildTaskId(subjectId, season: season, episode: episode);
    final existing = _tasks[taskId];
    if (existing != null &&
        (existing.status == DownloadStatus.downloading ||
            existing.status == DownloadStatus.completed)) {
      return;
    }

    final task = existing ??
        DownloadTask(
          id: taskId,
          subjectId: subjectId,
          title: title,
          coverUrl: coverUrl,
          subjectType: subjectType,
          streamUrl: streamUrl,
          signCookie: signCookie,
          quality: quality,
          season: season,
          episode: episode,
        );

    _tasks[taskId] = task;
    task._cancelRequested = false;

    // Check concurrency limit
    final runningCount =
        _tasks.values.where((t) => t.status == DownloadStatus.downloading).length;
    if (runningCount >= maxConcurrent) {
      task.status = DownloadStatus.pending;
      notifyListeners();
      return;
    }

    _executeTask(task);
  }

  void _checkQueue() {
    final runningCount =
        _tasks.values.where((t) => t.status == DownloadStatus.downloading).length;
    if (runningCount < maxConcurrent) {
      for (final task in _tasks.values) {
        if (task.status == DownloadStatus.pending) {
          _executeTask(task);
          break;
        }
      }
    }
  }

  Future<void> _executeTask(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    task._cancelRequested = false;
    task.activeThreads = defaultThreads;
    notifyListeners();

    try {
      final downloadDir = await _resolveDownloadDirectory(task);

      final isDash = task.streamUrl.contains('/dash/') || task.streamUrl.endsWith('.mpd');
      if (isDash) {
        await _downloadDashStream(task, downloadDir);
      } else {
        await _downloadProgressiveStream(task, downloadDir);
      }

      if (task.status == DownloadStatus.downloading) {
        // Validate downloaded file integrity
        if (task.filePath == null || task.receivedBytes <= 0) {
          throw Exception('Download finished with 0 bytes received');
        }
        final vFile = File(task.filePath!);
        if (!await vFile.exists() || await vFile.length() < 1024 * 10) {
          throw Exception('Downloaded video file is missing or corrupted');
        }

        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.speedBytesPerSec = 0.0;
        task.activeThreads = 0;

        await _storage.saveDownloadRecord(
          LocalRecord(
            subjectId: task.id,
            title: task.displayTitle,
            coverUrl: task.coverUrl,
            subjectType: task.subjectType,
            updatedAt: DateTime.now(),
            downloadPath: task.filePath,
            audioDownloadPath: task.audioFilePath,
          ),
        );
      }
    } catch (e) {
      if (!task._cancelRequested && task.status != DownloadStatus.paused) {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.toString().replaceFirst('Exception: ', '');
        task.speedBytesPerSec = 0.0;
        task.activeThreads = 0;
      }
    } finally {
      notifyListeners();
      _checkQueue();
    }
  }

  // -------------------------------------------------------------
  // Public External Storage Path Resolution
  // -------------------------------------------------------------
  Future<Directory> _resolveDownloadDirectory(DownloadTask task) async {
    final cleanFolder = _sanitizeFileName(task.title);

    if (Platform.isAndroid) {
      try {
        final publicDir =
            Directory('/storage/emulated/0/Download/RaenBox/Download/$cleanFolder');
        if (!await publicDir.exists()) {
          await publicDir.create(recursive: true);
        }
        return publicDir;
      } catch (e) {
        debugPrint('[DownloadService] Public storage direct creation note: $e');
      }

      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final dir = Directory('${extDir.path}/Download/$cleanFolder');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      } catch (e) {
        debugPrint('[DownloadService] External app storage fallback note: $e');
      }
    }

    final docDir = await getApplicationDocumentsDirectory();
    final fallback = Directory('${docDir.path}/downloads/$cleanFolder');
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback;
  }

  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // -------------------------------------------------------------
  // DASH Multithreaded Stream Downloader
  // -------------------------------------------------------------
  Future<void> _downloadDashStream(DownloadTask task, Directory downloadDir) async {
    final cleanTitle = _sanitizeFileName(task.title);
    String vFileName;
    String aFileName;

    if (task.isSeries && task.season != null && task.episode != null && task.season! > 0 && task.episode! > 0) {
      final sStr = task.season.toString().padLeft(2, '0');
      final eStr = task.episode.toString().padLeft(2, '0');
      vFileName = '${cleanTitle}_S${sStr}E${eStr}_${task.quality}p.mp4';
      aFileName = '${cleanTitle}_S${sStr}E${eStr}_${task.quality}p_audio.m4a';
    } else {
      vFileName = '${cleanTitle}_${task.quality}p.mp4';
      aFileName = '${cleanTitle}_${task.quality}p_audio.m4a';
    }

    final videoFile = File('${downloadDir.path}/$vFileName');
    final audioFile = File('${downloadDir.path}/$aFileName');
    task.filePath = videoFile.path;
    task.audioFilePath = audioFile.path;

    final baseUrl = task.streamUrl.substring(0, task.streamUrl.lastIndexOf('/') + 1);

    // 1. Fetch Manifest
    final client = HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 15);

    final mpdReq = await client.getUrl(Uri.parse(task.streamUrl));
    _setHeaders(mpdReq, task.signCookie);
    final mpdResp = await mpdReq.close();

    if (mpdResp.statusCode != 200) {
      throw Exception('Failed to load DASH manifest: HTTP ${mpdResp.statusCode}');
    }

    final mpdXml = await _readStringFromStream(mpdResp);

    // 2. Parse Scoped Video & Audio Representations
    final videoRep = _parseVideoRepresentation(mpdXml, task.quality);
    if (videoRep == null || videoRep.totalSegments <= 0) {
      throw Exception('Could not resolve video segments for quality ${task.quality}p');
    }

    final audioRep = _parseAudioRepresentation(mpdXml);

    final totalVideoChunks = videoRep.totalSegments;
    final totalAudioChunks = audioRep != null ? audioRep.totalSegments : 0;
    task.totalChunks = totalVideoChunks + totalAudioChunks;

    final threads = defaultThreads.clamp(1, 8);
    task.activeThreads = threads;

    // File sinks
    final videoSink = await videoFile.open(
      mode: task.currentChunkIndex == 0 ? FileMode.write : FileMode.append,
    );
    RandomAccessFile? audioSink;
    if (audioRep != null && totalAudioChunks > 0) {
      audioSink = await audioFile.open(
        mode: task.currentChunkIndex == 0 ? FileMode.write : FileMode.append,
      );
    }

    int lastSpeedTime = DateTime.now().millisecondsSinceEpoch;
    int lastSpeedBytes = task.receivedBytes;

    void updateSpeed() {
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = now - lastSpeedTime;
      if (dt >= 600) {
        final dBytes = task.receivedBytes - lastSpeedBytes;
        task.speedBytesPerSec = (dBytes / (dt / 1000.0));
        lastSpeedTime = now;
        lastSpeedBytes = task.receivedBytes;
        notifyListeners();
      }
    }

    try {
      // 3. Download Init Segments
      if (task.currentChunkIndex == 0) {
        final vInitUrl = baseUrl + videoRep.initFile;
        final vInitBytes = await _fetchChunkWithRetry(client, vInitUrl, task.signCookie);
        if (vInitBytes == null || vInitBytes.isEmpty) {
          throw Exception('Failed to download video initialization segment');
        }
        await videoSink.writeFrom(vInitBytes);
        task.receivedBytes += vInitBytes.length;

        if (audioRep != null && audioSink != null) {
          final aInitUrl = baseUrl + audioRep.initFile;
          final aInitBytes = await _fetchChunkWithRetry(client, aInitUrl, task.signCookie);
          if (aInitBytes != null && aInitBytes.isNotEmpty) {
            await audioSink.writeFrom(aInitBytes);
            task.receivedBytes += aInitBytes.length;
          }
        }
      }

      // 4. Download Video Chunks using Parallel Sliding Window Worker Pool
      final vStartSeq = videoRep.startNumber;
      final vEndSeq = videoRep.startNumber + totalVideoChunks - 1;

      int nextVFetch = vStartSeq;
      int nextVWrite = vStartSeq;
      final Map<int, Uint8List> vChunkBuffer = {};
      bool hasError = false;
      String? errorMsg;

      final int maxInFlight = (threads * 3).clamp(6, 24);

      Future<void> runVideoWorker() async {
        while (!task._cancelRequested && task.status == DownloadStatus.downloading && !hasError) {
          int chunkIdx = -1;
          if (nextVFetch <= vEndSeq) {
            if (nextVFetch < nextVWrite + maxInFlight) {
              chunkIdx = nextVFetch++;
            } else {
              await Future.delayed(const Duration(milliseconds: 20));
              continue;
            }
          } else {
            break;
          }

          final chunkName = _buildChunkName(videoRep.mediaTemplate, videoRep.id, chunkIdx);
          final chunkUrl = baseUrl + chunkName;
          final bytes = await _fetchChunkWithRetry(client, chunkUrl, task.signCookie, maxRetries: 3);

          if (bytes == null || bytes.isEmpty) {
            hasError = true;
            errorMsg = 'Failed to download video segment #$chunkIdx after 3 attempts';
            break;
          }

          vChunkBuffer[chunkIdx] = bytes;
          task.receivedBytes += bytes.length;
          updateSpeed();
        }
      }

      // Spawn video worker pool
      final workers = List.generate(threads, (_) => runVideoWorker());

      // Sequential Writer loop
      while (!task._cancelRequested && task.status == DownloadStatus.downloading && !hasError) {
        if (vChunkBuffer.containsKey(nextVWrite)) {
          final bytes = vChunkBuffer.remove(nextVWrite)!;
          await videoSink.writeFrom(bytes);
          nextVWrite++;
          task.currentChunkIndex = (nextVWrite - vStartSeq);
          task.progress = (task.currentChunkIndex / task.totalChunks).clamp(0.0, 1.0);
          updateSpeed();
        } else if (nextVWrite > vEndSeq) {
          break;
        } else {
          await Future.delayed(const Duration(milliseconds: 15));
        }
      }

      await Future.wait(workers);

      if (hasError) {
        throw Exception(errorMsg ?? 'Video segment download failed');
      }

      // 5. Download Audio Chunks if present
      if (audioRep != null && audioSink != null && totalAudioChunks > 0 && !task._cancelRequested && task.status == DownloadStatus.downloading) {
        final aStartSeq = audioRep.startNumber;
        final aEndSeq = audioRep.startNumber + totalAudioChunks - 1;

        int nextAFetch = aStartSeq;
        int nextAWrite = aStartSeq;
        final Map<int, Uint8List> aChunkBuffer = {};

        Future<void> runAudioWorker() async {
          while (!task._cancelRequested && task.status == DownloadStatus.downloading && !hasError) {
            int chunkIdx = -1;
            if (nextAFetch <= aEndSeq) {
              if (nextAFetch < nextAWrite + maxInFlight) {
                chunkIdx = nextAFetch++;
              } else {
                await Future.delayed(const Duration(milliseconds: 20));
                continue;
              }
            } else {
              break;
            }

            final chunkName = _buildChunkName(audioRep.mediaTemplate, audioRep.id, chunkIdx);
            final chunkUrl = baseUrl + chunkName;
            final bytes = await _fetchChunkWithRetry(client, chunkUrl, task.signCookie, maxRetries: 3);

            if (bytes == null || bytes.isEmpty) {
              hasError = true;
              errorMsg = 'Failed to download audio segment #$chunkIdx';
              break;
            }

            aChunkBuffer[chunkIdx] = bytes;
            task.receivedBytes += bytes.length;
            updateSpeed();
          }
        }

        final audioWorkers = List.generate(threads, (_) => runAudioWorker());

        while (!task._cancelRequested && task.status == DownloadStatus.downloading && !hasError) {
          if (aChunkBuffer.containsKey(nextAWrite)) {
            final bytes = aChunkBuffer.remove(nextAWrite)!;
            await audioSink.writeFrom(bytes);
            nextAWrite++;
            task.currentChunkIndex = totalVideoChunks + (nextAWrite - aStartSeq);
            task.progress = (task.currentChunkIndex / task.totalChunks).clamp(0.0, 1.0);
            updateSpeed();
          } else if (nextAWrite > aEndSeq) {
            break;
          } else {
            await Future.delayed(const Duration(milliseconds: 15));
          }
        }

        await Future.wait(audioWorkers);

        if (hasError) {
          throw Exception(errorMsg ?? 'Audio segment download failed');
        }
      }
    } finally {
      await videoSink.flush();
      await videoSink.close();
      if (audioSink != null) {
        await audioSink.flush();
        await audioSink.close();
      }
      client.close(force: true);
    }
  }

  // -------------------------------------------------------------
  // Progressive MP4 Stream Downloader (Range-Accelerated / Streaming)
  // -------------------------------------------------------------
  Future<void> _downloadProgressiveStream(DownloadTask task, Directory downloadDir) async {
    final cleanTitle = _sanitizeFileName(task.title);
    String vFileName;
    if (task.isSeries && task.season != null && task.episode != null && task.season! > 0 && task.episode! > 0) {
      final sStr = task.season.toString().padLeft(2, '0');
      final eStr = task.episode.toString().padLeft(2, '0');
      vFileName = '${cleanTitle}_S${sStr}E${eStr}_${task.quality}p.mp4';
    } else {
      vFileName = '${cleanTitle}_${task.quality}p.mp4';
    }

    final file = File('${downloadDir.path}/$vFileName');
    task.filePath = file.path;

    final client = HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 15);

    final req = await client.getUrl(Uri.parse(task.streamUrl));
    _setHeaders(req, task.signCookie);
    final resp = await req.close();

    if (resp.statusCode != 200 && resp.statusCode != 206) {
      client.close();
      throw Exception('HTTP ${resp.statusCode}: Stream unavailable');
    }

    final contentLength = resp.contentLength;
    task.totalBytes = contentLength;

    final sink = file.openWrite();
    int received = 0;
    int lastSpeedTime = DateTime.now().millisecondsSinceEpoch;
    int lastSpeedBytes = 0;

    try {
      await for (final chunk in resp) {
        if (task.status == DownloadStatus.paused || task._cancelRequested) {
          await sink.close();
          client.close(force: true);
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        task.receivedBytes = received;

        final now = DateTime.now().millisecondsSinceEpoch;
        final dt = now - lastSpeedTime;
        if (dt >= 600) {
          final dBytes = received - lastSpeedBytes;
          task.speedBytesPerSec = (dBytes / (dt / 1000.0));
          lastSpeedTime = now;
          lastSpeedBytes = received;
        }

        if (task.totalBytes > 0) {
          task.progress = (received / task.totalBytes).clamp(0.0, 1.0);
        }
        notifyListeners();
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  // -------------------------------------------------------------
  // DASH Representation Extraction Helpers
  // -------------------------------------------------------------
  _DashRepresentation? _parseVideoRepresentation(String xml, String targetQuality) {
    final repRegex = RegExp(
      r'<Representation\b([^>]*?)(?:>(.*?)</Representation>|/>)',
      dotAll: true,
    );

    _DashRepresentation? bestMatch;
    _DashRepresentation? fallbackMatch;

    for (final m in repRegex.allMatches(xml)) {
      final attrs = m.group(1) ?? '';
      final body = m.group(2) ?? '';

      final idMatch = RegExp(r'id="([^"]+)"').firstMatch(attrs);
      if (idMatch == null) continue;
      final id = idMatch.group(1)!;

      final heightMatch = RegExp(r'height="([^"]+)"').firstMatch(attrs);
      final height = heightMatch?.group(1);

      final mimeMatch = RegExp(r'mimeType="([^"]+)"').firstMatch(attrs);
      final mime = mimeMatch?.group(1) ?? '';

      // Check if video representation
      if (!mime.contains('video') && !attrs.contains('video') && height == null) {
        continue;
      }

      // Extract template
      final tmpl = _extractTemplate(attrs, body, xml);
      final count = _countSegments(body, tmpl, xml);

      final rep = _DashRepresentation(
        id: id,
        height: height,
        initTemplate: tmpl.initTemplate,
        mediaTemplate: tmpl.mediaTemplate,
        startNumber: tmpl.startNumber,
        totalSegments: count,
      );

      fallbackMatch ??= rep;
      if (height == targetQuality) {
        bestMatch = rep;
        break;
      }
    }

    return bestMatch ?? fallbackMatch;
  }

  _DashRepresentation? _parseAudioRepresentation(String xml) {
    final repRegex = RegExp(
      r'<Representation\b([^>]*?)(?:>(.*?)</Representation>|/>)',
      dotAll: true,
    );

    for (final m in repRegex.allMatches(xml)) {
      final attrs = m.group(1) ?? '';
      final body = m.group(2) ?? '';

      final idMatch = RegExp(r'id="([^"]+)"').firstMatch(attrs);
      if (idMatch == null) continue;
      final id = idMatch.group(1)!;

      final mimeMatch = RegExp(r'mimeType="([^"]+)"').firstMatch(attrs);
      final mime = mimeMatch?.group(1) ?? '';

      if (!mime.contains('audio') && !attrs.contains('audio')) {
        continue;
      }

      final tmpl = _extractTemplate(attrs, body, xml);
      final count = _countSegments(body, tmpl, xml);

      return _DashRepresentation(
        id: id,
        height: null,
        initTemplate: tmpl.initTemplate,
        mediaTemplate: tmpl.mediaTemplate,
        startNumber: tmpl.startNumber,
        totalSegments: count,
      );
    }
    return null;
  }

  _TemplateInfo _extractTemplate(String attrs, String body, String fullXml) {
    String searchScope = body.isNotEmpty ? body : attrs;
    if (!searchScope.contains('initialization=') && !searchScope.contains('media=')) {
      searchScope = fullXml;
    }

    final initMatch = RegExp(r'initialization="([^"]+)"').firstMatch(searchScope);
    final mediaMatch = RegExp(r'media="([^"]+)"').firstMatch(searchScope);
    final startNumMatch = RegExp(r'startNumber="(\d+)"').firstMatch(searchScope);

    final initTmpl = initMatch?.group(1) ?? r'init-stream$RepresentationID$.m4s';
    final mediaTmpl = mediaMatch?.group(1) ?? r'chunk-stream$RepresentationID$-$Number%05d$.m4s';
    final startNum = int.tryParse(startNumMatch?.group(1) ?? '1') ?? 1;

    return _TemplateInfo(
      initTemplate: initTmpl,
      mediaTemplate: mediaTmpl,
      startNumber: startNum,
    );
  }

  int _countSegments(String body, _TemplateInfo tmpl, String fullXml) {
    // 1. Check <SegmentTimeline> inside body
    final sMatches = RegExp(r'<S\b([^>]*?)/>').allMatches(body);
    if (sMatches.isNotEmpty) {
      int count = 0;
      for (final sm in sMatches) {
        final tag = sm.group(1) ?? '';
        final rMatch = RegExp(r'r="(\d+)"').firstMatch(tag);
        if (rMatch != null) {
          count += 1 + (int.tryParse(rMatch.group(1)!) ?? 0);
        } else {
          count += 1;
        }
      }
      return count;
    }

    // 2. Check for SegmentTemplate duration & timescale
    final durationMatch = RegExp(r'duration="(\d+)"').firstMatch(body) ??
        RegExp(r'duration="(\d+)"').firstMatch(fullXml);
    final timescaleMatch = RegExp(r'timescale="(\d+)"').firstMatch(body) ??
        RegExp(r'timescale="(\d+)"').firstMatch(fullXml);
    final mediaDurationMatch =
        RegExp(r'mediaPresentationDuration="PT([^"]+)"').firstMatch(fullXml);

    if (durationMatch != null && timescaleMatch != null && mediaDurationMatch != null) {
      final dur = double.tryParse(durationMatch.group(1)!) ?? 0.0;
      final timescale = double.tryParse(timescaleMatch.group(1)!) ?? 1.0;
      final totalSec = _parseIsoDuration(mediaDurationMatch.group(1)!);
      if (dur > 0 && timescale > 0 && totalSec > 0) {
        final segDur = dur / timescale;
        return (totalSec / segDur).ceil();
      }
    }

    return 0;
  }

  double _parseIsoDuration(String iso) {
    // e.g. 18.0S or 1H30M15S
    double total = 0.0;
    final hMatch = RegExp(r'(\d+)H').firstMatch(iso);
    final mMatch = RegExp(r'(\d+)M').firstMatch(iso);
    final sMatch = RegExp(r'([\d\.]+)S').firstMatch(iso);

    if (hMatch != null) total += (double.tryParse(hMatch.group(1)!) ?? 0) * 3600;
    if (mMatch != null) total += (double.tryParse(mMatch.group(1)!) ?? 0) * 60;
    if (sMatch != null) total += double.tryParse(sMatch.group(1)!) ?? 0;
    return total;
  }

  String _buildChunkName(String tmpl, String repId, int chunkIndex) {
    final numStr = chunkIndex.toString().padLeft(5, '0');
    return tmpl
        .replaceAll(r'$RepresentationID$', repId)
        .replaceAll(r'$Number%05d$', numStr)
        .replaceAll(r'$Number$', chunkIndex.toString());
  }

  Future<Uint8List?> _fetchChunkWithRetry(
    HttpClient client,
    String url,
    String? signCookie, {
    int maxRetries = 3,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final req = await client.getUrl(Uri.parse(url));
        _setHeaders(req, signCookie);
        final resp = await req.close();
        if (resp.statusCode != 200) {
          if (attempt == maxRetries - 1) return null;
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          continue;
        }

        final builder = BytesBuilder(copy: false);
        await for (final chunk in resp) {
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        if (bytes.isNotEmpty) return bytes;
      } catch (e) {
        if (attempt == maxRetries - 1) return null;
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    return null;
  }

  void _setHeaders(HttpClientRequest request, String? signCookie) {
    request.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );
    request.headers.set('Referer', 'https://apig.inmoviebox.com');
    if (signCookie != null && signCookie.isNotEmpty) {
      request.headers.set('Cookie', signCookie);
    }
  }

  Future<String> _readStringFromStream(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return String.fromCharCodes(builder.takeBytes());
  }

  void pauseDownload(String taskId) {
    final task = _tasks[taskId];
    if (task != null && task.status == DownloadStatus.downloading) {
      task.status = DownloadStatus.paused;
      task._cancelRequested = true;
      task.speedBytesPerSec = 0.0;
      task.activeThreads = 0;
      task._activeRequest?.abort();
      notifyListeners();
      _checkQueue();
    }
  }

  void resumeDownload(String taskId) {
    final task = _tasks[taskId];
    if (task != null && (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)) {
      task.status = DownloadStatus.pending;
      task._cancelRequested = false;
      task.errorMessage = null;
      notifyListeners();
      _checkQueue();
    }
  }

  Future<void> removeTask(String taskId) async {
    final task = _tasks.remove(taskId);
    if (task != null) {
      task._cancelRequested = true;
      task._activeRequest?.abort();
      if (task.filePath != null) {
        final f = File(task.filePath!);
        if (await f.exists()) await f.delete();
      }
      if (task.audioFilePath != null) {
        final af = File(task.audioFilePath!);
        if (await af.exists()) await af.delete();
      }
    }
    await _storage.removeDownloadRecord(taskId);
    notifyListeners();
    _checkQueue();
  }
}

class _DashRepresentation {
  final String id;
  final String? height;
  final String initTemplate;
  final String mediaTemplate;
  final int startNumber;
  final int totalSegments;

  _DashRepresentation({
    required this.id,
    required this.height,
    required this.initTemplate,
    required this.mediaTemplate,
    required this.startNumber,
    required this.totalSegments,
  });

  String get initFile => initTemplate.replaceAll(r'$RepresentationID$', id);
}

class _TemplateInfo {
  final String initTemplate;
  final String mediaTemplate;
  final int startNumber;

  _TemplateInfo({
    required this.initTemplate,
    required this.mediaTemplate,
    required this.startNumber,
  });
}
