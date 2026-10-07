import 'dart:async';
import 'dart:convert';
import 'dart:io';

class StreamSession {
  final String id;
  final Uri originalUri;
  final Uri upstreamBaseUri;
  String? signCookie;
  final String referer;
  final DateTime createdAt;
  final Future<String?> Function()? cookieRefresher;

  StreamSession({
    required this.id,
    required this.originalUri,
    required this.upstreamBaseUri,
    this.signCookie,
    required this.referer,
    required this.createdAt,
    this.cookieRefresher,
  });
}

class LocalStreamProxy {
  static LocalStreamProxy? _instance;
  HttpServer? _server;
  int? _port;
  final HttpClient _client = HttpClient()
    ..maxConnectionsPerHost = 32
    ..idleTimeout = const Duration(seconds: 30)
    ..connectionTimeout = const Duration(seconds: 12)
    ..badCertificateCallback = ((cert, host, port) => true);

  final Map<String, StreamSession> _sessions = {};

  double _estimatedBandwidthBps = 3.5 * 1024 * 1024; // 3.5 MB/s initial default

  double get estimatedBandwidthBps => _estimatedBandwidthBps;
  double get estimatedBandwidthMbps => (_estimatedBandwidthBps * 8) / 1000000.0;

  void recordThroughput(int bytes, int durationMs) {
    if (durationMs < 40 || bytes < 2048) return;
    final sampleBps = bytes / (durationMs / 1000.0);
    _estimatedBandwidthBps = 0.25 * sampleBps + 0.75 * _estimatedBandwidthBps;
  }

  static LocalStreamProxy get instance {
    _instance ??= LocalStreamProxy._();
    return _instance!;
  }

  LocalStreamProxy._();

  int get port => _port ?? 0;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      _server!.listen(_handleRequest);
    } catch (e) {
      // Ignore or log error
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _sessions.clear();
  }

  /// Registers an upstream stream and returns a local proxy URL with the proper extension.
  /// This ensures ExoPlayer detects DASH (.mpd) or HLS (.m3u8) correctly, and all
  /// relative segment requests (/stream/$sessionId/chunk.m4s) resolve to the proxy seamlessly.
  String registerStream({
    required String originalUrl,
    String? signCookie,
    String? referer,
    Future<String?> Function()? cookieRefresher,
  }) {
    if (_port == null) return originalUrl;

    final sessionId = 's_${DateTime.now().millisecondsSinceEpoch}_${_sessions.length}';
    final originalUri = Uri.parse(originalUrl);
    // Base URI for resolving relative chunks (init.m4s, chunk.m4s, segment.ts)
    final upstreamBaseUri = originalUri.resolve('.');

    final session = StreamSession(
      id: sessionId,
      originalUri: originalUri,
      upstreamBaseUri: upstreamBaseUri,
      signCookie: signCookie?.trim().replaceAll(RegExp(r';+$'), ''),
      referer: referer ?? 'https://apig.inmoviebox.com',
      createdAt: DateTime.now(),
      cookieRefresher: cookieRefresher,
    );

    _sessions[sessionId] = session;
    _pruneOldSessions();

    final pathLower = originalUri.path.toLowerCase();
    String extension = 'video.mp4';
    if (pathLower.endsWith('.mpd') || originalUrl.contains('/dash/')) {
      extension = 'index.mpd';
    } else if (pathLower.endsWith('.m3u8') || originalUrl.contains('hls')) {
      extension = 'index.m3u8';
    }

    return 'http://127.0.0.1:$_port/stream/$sessionId/$extension';
  }

  /// Backward compatible wrapper
  String getProxiedUrl(String originalUrl, {String? signCookie, String? referer, Future<String?> Function()? cookieRefresher}) {
    return registerStream(
      originalUrl: originalUrl,
      signCookie: signCookie,
      referer: referer,
      cookieRefresher: cookieRefresher,
    );
  }

  void _pruneOldSessions() {
    if (_sessions.length > 50) {
      final now = DateTime.now();
      _sessions.removeWhere((_, s) => now.difference(s.createdAt).inHours > 4);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      // Handle session-based streaming: /stream/<sessionId>/<subpath...>
      if (path.startsWith('/stream/')) {
        await _handleSessionStream(request);
        return;
      }

      // Legacy direct proxy: /proxy?url=...
      if (path.startsWith('/proxy')) {
        await _handleDirectProxy(request);
        return;
      }

      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found')
        ..close();
    } catch (e) {
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Proxy error: $e')
          ..close();
      } catch (_) {}
    }
  }

  void _applyUpstreamHeaders(
    HttpClientRequest upstreamReq,
    StreamSession session,
    HttpRequest clientReq,
  ) {
    upstreamReq.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );
    upstreamReq.headers.set('Referer', session.referer);
    upstreamReq.headers.set('Origin', 'https://moviebox.ph');

    if (session.signCookie != null && session.signCookie!.isNotEmpty) {
      upstreamReq.headers.set('Cookie', session.signCookie!);
    }

    final range = clientReq.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
    }
  }

  Future<void> _handleSessionStream(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    // pathSegments: ['stream', sessionId, ...remaining]
    if (segments.length < 3) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid stream path')
        ..close();
      return;
    }

    final sessionId = segments[1];
    final subpath = segments.sublist(2).join('/');
    final session = _sessions[sessionId];

    if (session == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Session expired or not found')
        ..close();
      return;
    }

    // Determine target URL: manifest vs relative chunk
    final isManifest = subpath == 'index.mpd' || subpath == 'index.m3u8' || subpath == 'video.mp4';
    final targetUri = isManifest ? session.originalUri : session.upstreamBaseUri.resolve(subpath);

    HttpClientRequest upstreamReq = await _client.getUrl(targetUri);
    _applyUpstreamHeaders(upstreamReq, session, request);
    HttpClientResponse upstreamRes = await upstreamReq.close();

    // Proactive CloudFront token auto-refresh on 401 Unauthorized / 403 Forbidden
    if ((upstreamRes.statusCode == HttpStatus.forbidden || upstreamRes.statusCode == HttpStatus.unauthorized) &&
        session.cookieRefresher != null) {
      try {
        await upstreamRes.drain().timeout(const Duration(milliseconds: 500));
      } catch (_) {}

      try {
        final refreshedCookie = await session.cookieRefresher!();
        if (refreshedCookie != null && refreshedCookie.isNotEmpty) {
          session.signCookie = refreshedCookie.trim().replaceAll(RegExp(r';+$'), '');
          upstreamReq = await _client.getUrl(targetUri);
          _applyUpstreamHeaders(upstreamReq, session, request);
          upstreamRes = await upstreamReq.close();
        }
      } catch (_) {}
    }

    // Filter DASH MPD Manifest when a fixed quality is requested
    final qualityParam = request.uri.queryParameters['quality'];
    if (subpath.endsWith('.mpd') &&
        qualityParam != null &&
        qualityParam != 'auto' &&
        upstreamRes.statusCode == 200) {
      try {
        final mpdContent = await utf8.decodeStream(upstreamRes);
        final filteredMpd = filterMpdForQuality(mpdContent, qualityParam);
        final bytes = utf8.encode(filteredMpd);
        request.response.statusCode = 200;
        request.response.headers.set('Content-Type', 'application/dash+xml; charset=utf-8');
        request.response.headers.set('Access-Control-Allow-Origin', '*');
        request.response.headers.set('Access-Control-Allow-Headers', '*');
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
        return;
      } catch (_) {
        // Fallback to normal streaming on decode/filter issue
      }
    }

    request.response.statusCode = upstreamRes.statusCode;

    // Set correct Content-Type for MediaSource detection
    if (subpath.endsWith('.mpd')) {
      request.response.headers.set('Content-Type', 'application/dash+xml; charset=utf-8');
    } else if (subpath.endsWith('.m3u8')) {
      request.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
    } else {
      final upstreamContentType = upstreamRes.headers.value(HttpHeaders.contentTypeHeader);
      if (upstreamContentType != null) {
        request.response.headers.set(HttpHeaders.contentTypeHeader, upstreamContentType);
      }
    }

    // Copy Content-Range, Accept-Ranges, Content-Length
    final contentRange = upstreamRes.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      request.response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
    }
    final acceptRanges = upstreamRes.headers.value(HttpHeaders.acceptRangesHeader);
    if (acceptRanges != null) {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, acceptRanges);
    }
    if (upstreamRes.contentLength >= 0) {
      request.response.contentLength = upstreamRes.contentLength;
    }

    // Enable CORS for players
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Headers', '*');

    try {
      final stopwatch = Stopwatch()..start();
      int bytesTransferred = 0;
      await for (final chunk in upstreamRes) {
        bytesTransferred += chunk.length;
        request.response.add(chunk);
      }
      await request.response.flush();
      stopwatch.stop();
      if (bytesTransferred > 0) {
        recordThroughput(bytesTransferred, stopwatch.elapsedMilliseconds);
      }
    } catch (e) {
      // Safely handle client disconnect / broken pipe during seek or chunk drop
      try {
        await upstreamRes.drain().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Filters a multi-representation DASH MPD XML to retain only the specified target quality
  static String filterMpdForQuality(String mpdXml, String targetQuality) {
    final adaptationSetRegex = RegExp(
      r'(<AdaptationSet\b[^>]*>)(.*?)(</AdaptationSet>)',
      dotAll: true,
    );

    return mpdXml.replaceAllMapped(adaptationSetRegex, (adaptMatch) {
      final openTag = adaptMatch.group(1)!;
      final body = adaptMatch.group(2)!;
      final closeTag = adaptMatch.group(3)!;

      final isVideo = openTag.contains('video') ||
          openTag.contains('width') ||
          openTag.contains('height') ||
          body.contains('mimeType="video') ||
          body.contains('height="');

      if (!isVideo) {
        return adaptMatch.group(0)!;
      }

      final repRegex = RegExp(
        r'<Representation\b([^>]*?)(?:>(.*?)</Representation>|/>)',
        dotAll: true,
      );

      final reps = repRegex.allMatches(body).toList();
      if (reps.isEmpty) return adaptMatch.group(0)!;

      Match? targetRep;
      Match? closestRep;
      int minDiff = 999999;
      final targetH = int.tryParse(targetQuality) ?? 1080;

      for (final r in reps) {
        final attrs = r.group(1) ?? '';
        final hMatch = RegExp(r'height="(\d+)"').firstMatch(attrs);
        final height = int.tryParse(hMatch?.group(1) ?? '');
        if (height != null) {
          final diff = (height - targetH).abs();
          if (diff < minDiff) {
            minDiff = diff;
            closestRep = r;
          }
          if (height.toString() == targetQuality) {
            targetRep = r;
            break;
          }
        }
      }

      final chosen = targetRep ?? closestRep ?? reps.first;
      final chosenStr = chosen.group(0)!;

      var newBody = body.replaceAll(repRegex, '');
      newBody = '$newBody\n      $chosenStr\n    ';

      return '$openTag$newBody$closeTag';
    });
  }

  Future<void> _handleDirectProxy(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final targetUrl = query['url'];
    if (targetUrl == null || targetUrl.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Missing url parameter')
        ..close();
      return;
    }

    final signCookie = query['cookie'];
    final referer = query['referer'] ?? 'https://apig.inmoviebox.com';

    final upstreamUri = Uri.parse(targetUrl);
    final upstreamReq = await _client.getUrl(upstreamUri);

    upstreamReq.headers.set('User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    upstreamReq.headers.set('Referer', referer);
    upstreamReq.headers.set('Origin', 'https://moviebox.ph');

    if (signCookie != null && signCookie.isNotEmpty) {
      upstreamReq.headers.set('Cookie', signCookie);
    }

    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
    }

    final upstreamRes = await upstreamReq.close();
    request.response.statusCode = upstreamRes.statusCode;

    upstreamRes.headers.forEach((name, values) {
      if (name.toLowerCase() != 'transfer-encoding') {
        for (final value in values) {
          request.response.headers.add(name, value);
        }
      }
    });

    request.response.headers.set('Access-Control-Allow-Origin', '*');
    try {
      await upstreamRes.pipe(request.response);
    } catch (_) {
      try {
        await upstreamRes.drain().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
  }
}
