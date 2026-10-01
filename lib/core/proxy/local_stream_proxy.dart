import 'dart:async';
import 'dart:io';

class StreamSession {
  final String id;
  final Uri originalUri;
  final Uri upstreamBaseUri;
  final String? signCookie;
  final String referer;
  final DateTime createdAt;

  StreamSession({
    required this.id,
    required this.originalUri,
    required this.upstreamBaseUri,
    this.signCookie,
    required this.referer,
    required this.createdAt,
  });
}

class LocalStreamProxy {
  static LocalStreamProxy? _instance;
  HttpServer? _server;
  int? _port;
  final HttpClient _client = HttpClient()
    ..badCertificateCallback = ((cert, host, port) => true);

  final Map<String, StreamSession> _sessions = {};

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
  String getProxiedUrl(String originalUrl, {String? signCookie, String? referer}) {
    return registerStream(
      originalUrl: originalUrl,
      signCookie: signCookie,
      referer: referer,
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

    final upstreamReq = await _client.getUrl(targetUri);

    // Forward standard browser headers
    upstreamReq.headers.set('User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    upstreamReq.headers.set('Referer', session.referer);
    upstreamReq.headers.set('Origin', 'https://moviebox.ph');

    if (session.signCookie != null && session.signCookie!.isNotEmpty) {
      upstreamReq.headers.set('Cookie', session.signCookie!);
    }

    // Forward Range header for video seeking
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
    }

    final upstreamRes = await upstreamReq.close();
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

    await upstreamRes.pipe(request.response);
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
    await upstreamRes.pipe(request.response);
  }
}
