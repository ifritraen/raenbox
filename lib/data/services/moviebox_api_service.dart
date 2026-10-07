import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/network/moviebox_signer.dart';
import '../models/moviebox_models.dart';
import '../models/buzzbox_models.dart';
import 'local_storage_service.dart';

class MovieBoxApiService {
  static const List<String> gateways = [
    'https://api3.aoneroom.com',
    'https://api6.aoneroom.com',
    'https://api5.aoneroom.com',
    'https://api4.aoneroom.com',
    'https://api7.aoneroom.com',
    'https://api4sg.aoneroom.com',
    'https://apig.inmoviebox.com',
    'https://api.inmoviebox.com',
    'https://api-in.inmoviebox.com',
  ];

  final http.Client _client = http.Client();
  final LocalStorageService _storage;

  MovieBoxApiService(this._storage);

  String? _token;
  String? _lastTokenRegion;

  Future<void> _extractAndSaveToken(http.Response response, {String? region}) async {
    final xUser = response.headers['x-user'];
    if (xUser != null && xUser.isNotEmpty) {
      try {
        final decoded = json.decode(xUser);
        final token = decoded['token']?.toString();
        if (token != null && token.isNotEmpty) {
          _token = token;
          _lastTokenRegion = region ?? _storage.activeRegion;
          await _storage.setCachedToken(token);
        }
      } catch (_) {}
    }
  }

  /// Proactively ensures a valid Bearer token is available for playback requests
  Future<String?> ensureValidToken({bool forceRefresh = false, String? region}) async {
    final targetRegion = region ?? _storage.activeRegion;
    if (!forceRefresh && _lastTokenRegion == targetRegion) {
      if (_token != null && _token!.isNotEmpty) return _token;
      final cached = _storage.cachedToken;
      if (cached != null && cached.isNotEmpty) {
        _token = cached;
        return cached;
      }
    }

    const path =
        '/wefeed-mobile-bff/tab/ranking-list?tabId=0&categoryType=4516404531735022304&page=1&perPage=1';
    for (final host in gateways) {
      try {
        final fullUrl = '$host$path';
        final headers = MovieBoxSigner.buildHeaders(
          url: fullUrl,
          method: 'GET',
          token: null,
          region: targetRegion,
        );
        final response = await _client
            .get(Uri.parse(fullUrl), headers: headers)
            .timeout(const Duration(seconds: 4));
        await _extractAndSaveToken(response, region: targetRegion);
        if (_token != null && _token!.isNotEmpty) {
          return _token;
        }
      } catch (_) {}
    }
    return _token;
  }

  Future<http.Response?> _request({
    required String pathWithQuery,
    required String method,
    Map<String, dynamic>? bodyMap,
    bool isPlayback = false,
    String? overrideRegion,
    bool canRetry = true,
  }) async {
    final region = overrideRegion ?? _storage.activeRegion;
    if (isPlayback && (_token == null || _lastTokenRegion != region)) {
      await ensureValidToken(region: region);
    }

    final token = (_lastTokenRegion == region) ? (_token ?? _storage.cachedToken) : null;
    final bodyStr = bodyMap != null ? json.encode(bodyMap) : null;

    for (final host in gateways) {
      final fullUrl = '$host$pathWithQuery';
      final headers = MovieBoxSigner.buildHeaders(
        url: fullUrl,
        method: method,
        body: bodyStr,
        token: token,
        isPlayback: isPlayback,
        region: region,
      );

      try {
        final uri = Uri.parse(fullUrl);
        final response = method.toUpperCase() == 'POST'
            ? await _client
                .post(uri, headers: headers, body: bodyStr)
                .timeout(const Duration(seconds: 4))
            : await _client
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 4));

        await _extractAndSaveToken(response, region: region);

        if (response.statusCode == 200) {
          return response;
        } else if (response.statusCode == 441 && canRetry) {
          await ensureValidToken(forceRefresh: true, region: region);
          return _request(
            pathWithQuery: pathWithQuery,
            method: method,
            bodyMap: bodyMap,
            isPlayback: isPlayback,
            overrideRegion: overrideRegion,
            canRetry: false,
          );
        }
      } catch (e) {
        // Try next gateway
      }
    }
    return null;
  }

  // 1. Fetch Rankings (Trending, Cinema, Series, Bollywood, etc.)
  Future<List<MediaItem>> fetchRankings({
    required String categoryType,
    int page = 1,
    int perPage = 15,
  }) async {
    final path =
        '/wefeed-mobile-bff/tab/ranking-list?tabId=0&categoryType=$categoryType&page=$page&perPage=$perPage';
    final res = await _request(pathWithQuery: path, method: 'GET');
    if (res == null) return [];

    try {
      final root = json.decode(utf8.decode(res.bodyBytes));
      final items = (root['data']?['items'] ?? root['data']?['subjects']) as List?;
      if (items == null) return [];
      return items.map((e) => MediaItem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // 2. Fetch Browse / Filter List
  Future<List<MediaItem>> fetchBrowseList({
    required String channelId, // "1" for Movie, "2" for TV, "1006" for Anime
    String classify = 'All',
    String country = 'All',
    String year = 'All',
    String genre = 'All',
    String sort = 'ForYou',
    int page = 1,
    int perPage = 15,
  }) async {
    // 1. Try Authentic Web BFF Filter (Direct 1:1 with movieboxhd.net)
    try {
      final webItems = await fetchWebSubjectFilter(
        channelId: channelId,
        classify: classify,
        country: country,
        year: year,
        genre: genre,
        sort: sort,
        page: page,
        perPage: perPage,
      );
      if (webItems.isNotEmpty) return webItems;
    } catch (_) {}

    // 2. Fallback to Mobile BFF
    const path = '/wefeed-mobile-bff/subject-api/list';
    final body = {
      'page': page,
      'perPage': perPage,
      'channelId': channelId,
      'classify': classify,
      'country': country,
      'year': year,
      'genre': genre,
      'sort': sort,
    };

    final res = await _request(pathWithQuery: path, method: 'POST', bodyMap: body);
    if (res == null) return [];

    try {
      final root = json.decode(utf8.decode(res.bodyBytes));
      final items = (root['data']?['items'] ?? root['data']?['subjects']) as List?;
      if (items == null) return [];
      return items.map((e) => MediaItem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // 3. Search Catalog
  Future<List<MediaItem>> search(String query, {int page = 1, int perPage = 20}) async {
    const path = '/wefeed-mobile-bff/subject-api/search/v2';
    final body = {
      'page': page,
      'perPage': perPage,
      'keyword': query,
    };

    final res = await _request(pathWithQuery: path, method: 'POST', bodyMap: body);
    if (res == null) return [];

    try {
      final root = json.decode(utf8.decode(res.bodyBytes));
      final results = root['data']?['results'] as List?;
      if (results == null) return [];

      final list = <MediaItem>[];
      for (final r in results) {
        final subjects = r['subjects'] as List?;
        if (subjects != null) {
          for (final s in subjects) {
            list.add(MediaItem.fromJson(s));
          }
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  // 3a. Fetch dynamic trending searches ("Everyone is searching")
  Future<List<String>> fetchTrendingSearches({String? region, String? classify}) async {
    try {
      final queryParams = <String, String>{'host': 'movieboxhd.net'};
      final targetRegion = region ?? _storage.activeRegion;
      if (targetRegion.isNotEmpty && targetRegion != 'GLOBAL') {
        queryParams['region'] = targetRegion;
      }
      if (classify != null && classify.isNotEmpty && classify != 'All') {
        queryParams['classify'] = classify;
      }
      final uri = Uri.https('h5-api.aoneroom.com', '/wefeed-h5api-bff/subject/everyone-search', queryParams);

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
          'Origin': 'https://movieboxhd.net',
          'Referer': 'https://movieboxhd.net/',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];
      final root = json.decode(utf8.decode(response.bodyBytes));
      if (root['code'] != 0) return [];
      final list = root['data']?['everyoneSearch'] as List?;
      if (list == null) return [];

      final suggestions = <String>[];
      for (final item in list) {
        if (item is Map && item['title'] != null) {
          final title = item['title'].toString().trim();
          if (title.isNotEmpty && !suggestions.contains(title)) {
            suggestions.add(title);
          }
        }
      }
      return suggestions;
    } catch (_) {
      return [];
    }
  }

  // 3b. Fetch real-time search suggestions / autocomplete as the user types
  Future<List<String>> fetchSearchSuggestions(String keyword) async {
    final clean = keyword.trim();
    if (clean.isEmpty) return [];

    try {
      const url = 'https://h5-api.aoneroom.com/wefeed-h5api-bff/subject/search-suggest';
      final response = await _client.post(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Origin': 'https://movieboxhd.net',
          'Referer': 'https://movieboxhd.net/',
        },
        body: json.encode({'keyword': clean}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return [];
      final root = json.decode(utf8.decode(response.bodyBytes));
      if (root['code'] != 0) return [];
      final items = root['data']?['items'] as List?;
      if (items == null) return [];

      final list = <String>[];
      for (final it in items) {
        if (it is Map && it['word'] != null) {
          final word = it['word'].toString().trim();
          if (word.isNotEmpty && !list.contains(word)) {
            list.add(word);
          }
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }


  // Detail cache: subjectId -> raw response data map
  final _detailCache = <String, Map<String, dynamic>>{};

  // 4. Fetch Media Details (uses web BFF with fallback to mobile BFF)
  Future<MediaDetail?> fetchDetail(String subjectId) async {
    final cached = _detailCache[subjectId];
    if (cached != null) return MediaDetail.fromJson(cached);

    try {
      final url = 'https://h5-api.aoneroom.com/wefeed-h5api-bff/detail?subjectId=$subjectId';
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
          'Origin': 'https://movieboxhd.net',
          'Referer': 'https://movieboxhd.net/',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final root = json.decode(utf8.decode(response.bodyBytes));
        if (root['code'] == 0 && root['data'] != null) {
          final data = root['data'] as Map<String, dynamic>;
          _detailCache[subjectId] = data;
          return MediaDetail.fromJson(data);
        }
      }
    } catch (_) {}

    // Fallback to Mobile BFF detail endpoint
    try {
      final path = '/wefeed-mobile-bff/subject-api/get?subjectId=$subjectId';
      final res = await _request(pathWithQuery: path, method: 'GET');
      if (res != null && res.statusCode == 200) {
        final root = json.decode(utf8.decode(res.bodyBytes));
        if (root['code'] == 0 && root['data'] != null) {
          final data = root['data'] as Map<String, dynamic>;
          _detailCache[subjectId] = data;
          return MediaDetail.fromJson(data);
        }
      }
    } catch (_) {}

    // Universal Cross-Region Detail Fallback Cascade (IN, GLOBAL)
    final activeReg = _storage.activeRegion.toUpperCase();
    final fallbackRegions = ['IN', 'GLOBAL']
        .where((r) => r != activeReg && (r != 'GLOBAL' || activeReg != 'US'))
        .toList();

    for (final fbRegion in fallbackRegions) {
      try {
        final path = '/wefeed-mobile-bff/subject-api/get?subjectId=$subjectId';
        final fbRes = await _request(pathWithQuery: path, method: 'GET', overrideRegion: fbRegion);
        if (fbRes != null && fbRes.statusCode == 200) {
          final root = json.decode(utf8.decode(fbRes.bodyBytes));
          if (root['code'] == 0 && root['data'] != null) {
            final data = root['data'] as Map<String, dynamic>;
            _detailCache[subjectId] = data;
            debugPrint('[MovieBoxAPI] Detail found via fallback region: $fbRegion for subject $subjectId');
            return MediaDetail.fromJson(data);
          }
        }
      } catch (_) {}
    }

    return null;
  }

  // 5. Fetch Season Information (from cached detail response — no extra request)
  Future<List<SeasonInfo>> fetchSeasonInfo(String subjectId) async {
    // Ensure detail is loaded (uses cache if already fetched)
    if (!_detailCache.containsKey(subjectId)) {
      await fetchDetail(subjectId);
    }
    final data = _detailCache[subjectId];
    if (data == null) return [];
    try {
      final resource = data['resource'] as Map<String, dynamic>?;
      final seasons = resource?['seasons'] as List?;
      if (seasons == null || seasons.isEmpty) return [];
      return seasons.map((e) => SeasonInfo.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  // Fallback helper to fetch streams from web BFF if mobile BFF yields 0 streams
  Future<List<StreamLink>> _fetchWebPlayInfo(
    String subjectId, {
    int season = 0,
    int episode = 0,
  }) async {
    for (final host in ['h5-api.aoneroom.com', 'netfilm.world']) {
      try {
        final url =
            'https://$host/wefeed-h5api-bff/subject/play?subjectId=$subjectId&se=$season&ep=$episode';
        final response = await _client.get(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://movieboxhd.net/',
            'Origin': 'https://movieboxhd.net',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode != 200) continue;
        final root = json.decode(utf8.decode(response.bodyBytes));
        final rawStreams = root['data']?['streams'] as List?;
        if (rawStreams == null || rawStreams.isEmpty) continue;

        final streamList = <StreamLink>[];
        final captionFutures = <Future<List<CaptionTrack>>>[];
        for (final s in rawStreams) {
          final map = s as Map<String, dynamic>;
          final rawUrl = map['url']?.toString() ?? '';
          final signCookie = map['signCookie']?.toString();
          final streamId = map['id']?.toString() ?? '';
          final resolvedUrl =
              MovieBoxSigner.extractRealStreamUrl(rawUrl, signCookie);

          streamList.add(StreamLink.fromJson(map, resolvedUrl: resolvedUrl));
          if (streamId.isNotEmpty) {
            captionFutures.add(
              fetchCaptions(subjectId: subjectId, streamId: streamId)
                  .timeout(const Duration(seconds: 2), onTimeout: () => []),
            );
          } else {
            captionFutures.add(Future.value([]));
          }
        }

        try {
          final results = await Future.wait(captionFutures);
          for (var i = 0; i < streamList.length && i < results.length; i++) {
            if (results[i].isNotEmpty) {
              final link = streamList[i];
              streamList[i] = StreamLink(
                id: link.id,
                format: link.format,
                resolutions: link.resolutions,
                rawUrl: link.rawUrl,
                url: link.url,
                signCookie: link.signCookie,
                duration: link.duration,
                captions: results[i],
              );
            }
          }
        } catch (_) {}

        final realStreams = streamList.where((s) => s.isRealStream).toList();
        if (realStreams.isNotEmpty) return realStreams;
        if (streamList.isNotEmpty) return streamList;
      } catch (_) {}
    }
    return [];
  }

  // 6. Fetch Playback Streams (Decodes real stream from signCookie & fetches subtitles)
  Future<List<StreamLink>> _parseStreamList(String subjectId, List rawStreams) async {
    final streamList = <StreamLink>[];
    final captionFutures = <Future<List<CaptionTrack>>>[];
    for (final s in rawStreams) {
      final map = s as Map<String, dynamic>;
      final rawUrl = map['url']?.toString() ?? '';
      final signCookie = map['signCookie']?.toString();
      final streamId = map['id']?.toString() ?? '';

      // Extract real full DASH / HLS stream URL hidden inside CloudFront-Policy or urlprefix
      final resolvedUrl = MovieBoxSigner.extractRealStreamUrl(rawUrl, signCookie);

      streamList.add(StreamLink.fromJson(map, resolvedUrl: resolvedUrl));
      if (streamId.isNotEmpty) {
        captionFutures.add(
          fetchCaptions(subjectId: subjectId, streamId: streamId)
              .timeout(const Duration(seconds: 2), onTimeout: () => []),
        );
      } else {
        captionFutures.add(Future.value([]));
      }
    }

    try {
      final results = await Future.wait(captionFutures);
      for (var i = 0; i < streamList.length && i < results.length; i++) {
        if (results[i].isNotEmpty) {
          final link = streamList[i];
          streamList[i] = StreamLink(
            id: link.id,
            format: link.format,
            resolutions: link.resolutions,
            rawUrl: link.rawUrl,
            url: link.url,
            signCookie: link.signCookie,
            duration: link.duration,
            captions: results[i],
          );
        }
      }
    } catch (_) {}

    // Prioritize real streams over dummy preview clips and filter them out if real ones exist
    final realStreams = streamList.where((s) => s.isRealStream).toList();
    if (realStreams.isNotEmpty) {
      return realStreams;
    }

    return streamList;
  }

  // 6. Fetch Playback Streams (Decodes real stream from signCookie, fetches subtitles & auto cross-region fallback)
  Future<List<StreamLink>> fetchPlayInfo(
    String subjectId, {
    int season = 0,
    int episode = 0,
  }) async {
    await ensureValidToken();

    final path =
        '/wefeed-mobile-bff/subject-api/play-info?subjectId=$subjectId&se=$season&ep=$episode';

    // 1. Try active user region first
    try {
      var res = await _request(pathWithQuery: path, method: 'GET', isPlayback: true);
      if (res != null) {
        var root = json.decode(utf8.decode(res.bodyBytes));
        if (root['code'] == 441) {
          await ensureValidToken(forceRefresh: true);
          res = await _request(pathWithQuery: path, method: 'GET', isPlayback: true, canRetry: false);
          if (res != null) {
            root = json.decode(utf8.decode(res.bodyBytes));
          }
        }

        final rawStreams = root['data']?['streams'] as List?;
        if (rawStreams != null && rawStreams.isNotEmpty) {
          final parsed = await _parseStreamList(subjectId, rawStreams);
          if (parsed.isNotEmpty) return parsed;
        }
      }
    } catch (_) {}

    // 2. Universal Cross-Region Stream Fallback Cascade (IN, GLOBAL)
    final activeReg = _storage.activeRegion.toUpperCase();
    final fallbackRegions = ['IN', 'GLOBAL']
        .where((r) => r != activeReg && (r != 'GLOBAL' || activeReg != 'US'))
        .toList();

    for (final fbRegion in fallbackRegions) {
      try {
        final fbRes = await _request(
          pathWithQuery: path,
          method: 'GET',
          isPlayback: true,
          overrideRegion: fbRegion,
        );
        if (fbRes != null && fbRes.statusCode == 200) {
          final fbRoot = json.decode(utf8.decode(fbRes.bodyBytes));
          final fbRawStreams = fbRoot['data']?['streams'] as List?;
          if (fbRawStreams != null && fbRawStreams.isNotEmpty) {
            debugPrint('[MovieBoxAPI] Stream unlocked via fallback region: $fbRegion for subject $subjectId');
            final parsed = await _parseStreamList(subjectId, fbRawStreams);
            if (parsed.isNotEmpty) return parsed;
          }
        }
      } catch (_) {}
    }

    // 3. Fallback to Web BFF endpoints
    return await _fetchWebPlayInfo(subjectId, season: season, episode: episode);
  }

  // 7. Fetch Stream Captions (Subtitles)
  Future<List<CaptionTrack>> fetchCaptions({
    required String subjectId,
    required String streamId,
  }) async {
    final path =
        '/wefeed-mobile-bff/subject-api/get-stream-captions?subjectId=$subjectId&streamId=$streamId';
    final res = await _request(pathWithQuery: path, method: 'GET', isPlayback: true);
    if (res == null) return [];

    try {
      final root = json.decode(utf8.decode(res.bodyBytes));
      final caps = root['data']?['extCaptions'] as List?;
      if (caps == null) return [];
      return caps.map((c) => CaptionTrack.fromJson(c)).toList();
    } catch (_) {
      return [];
    }
  }

  // 8. Fetch Authentic Tab Operating Rails from Web BFF (ONEROOM_MOVIE, ONEROOM_MIDNIGHT, etc.)
  Future<Map<String, dynamic>> fetchTabOperating(String tabId) async {
    final url =
        'https://h5-api.aoneroom.com/wefeed-h5api-bff/tab-operating?tabId=$tabId&host=movieboxhd.net';
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Origin': 'https://movieboxhd.net',
      'Referer': 'https://movieboxhd.net/',
    };

    try {
      final res = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map<String, dynamic>) {
          return decoded['data'] as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return {};
  }

  // 8b. Fetch Authentic Mobile App Tab Operating Rails (/wefeed-mobile-bff/tab-operating)
  Future<Map<String, dynamic>> fetchMobileTabOperating(int tabId, {String? region}) async {
    final path = '/wefeed-mobile-bff/tab-operating?tabId=$tabId';
    try {
      final res = await _request(
        pathWithQuery: path,
        method: 'GET',
        overrideRegion: region,
      );
      if (res != null && res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map<String, dynamic>) {
          return decoded['data'] as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return {};
  }

  // 9. Fetch Authentic Tab Trending Waterfall Feed from Web BFF
  Future<List<MediaItem>> fetchTabTrending(String tabId, {int page = 1, int perPage = 18}) async {
    final url =
        'https://h5-api.aoneroom.com/wefeed-h5api-bff/subject/trending?tabId=$tabId&page=$page&perPage=$perPage';
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Origin': 'https://movieboxhd.net',
      'Referer': 'https://movieboxhd.net/',
    };

    try {
      final res = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] != null) {
          final list = decoded['data']['subjectList'] as List<dynamic>? ?? [];
          return list.map((item) => MediaItem.fromJson(item as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  // 9b. Fetch Authentic Ranking List / Curated Playlist by GenreTopId
  Future<List<MediaItem>> fetchRankingList(
    String genreTopId, {
    int page = 1,
    int perPage = 20,
  }) async {
    if (genreTopId.isEmpty) return [];
    final url =
        'https://h5-api.aoneroom.com/wefeed-h5api-bff/ranking-list/content?id=$genreTopId&page=$page&perPage=$perPage';
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Origin': 'https://movieboxhd.net',
      'Referer': 'https://movieboxhd.net/',
    };

    try {
      final res = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map) {
          final data = decoded['data'] as Map<String, dynamic>;
          final subjectList = data['subjectList'] as List<dynamic>? ?? [];
          final items = subjectList.map((e) {
            final s = e is Map<String, dynamic> ? e : <String, dynamic>{};
            return MediaItem.fromJson(s);
          }).where((m) => m.subjectId.isNotEmpty).toList();

          // Auto-paginate if initial page has fewer than 12 items and more are available
          final pager = data['pager'];
          if (items.length < 12 &&
              pager is Map &&
              pager['hasMore'] == true &&
              page == 1) {
            final page2Items = await fetchRankingList(
              genreTopId,
              page: 2,
              perPage: perPage,
            );
            final existingIds = items.map((m) => m.subjectId).toSet();
            for (final p2 in page2Items) {
              if (existingIds.add(p2.subjectId)) {
                items.add(p2);
              }
            }
          }
          return items;
        }
      }
    } catch (_) {}
    return [];
  }

  // 10. Fetch Authentic Web BFF Subject Filter List (Direct 1:1 with movieboxhd.net)
  Future<List<MediaItem>> fetchWebSubjectFilter({
    required String channelId,
    String classify = 'All',
    String country = 'All',
    String year = 'All',
    String genre = 'All',
    String sort = 'ForYou',
    int page = 1,
    int perPage = 18,
  }) async {
    const url = 'https://h5-api.aoneroom.com/wefeed-h5api-bff/subject/filter';
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'Origin': 'https://movieboxhd.net',
      'Referer': 'https://movieboxhd.net/',
    };
    final body = <String, dynamic>{
      'channelId': channelId,
      'page': page,
      'perPage': perPage,
      if (classify != 'All') 'classify': classify,
      if (country != 'All') 'country': country,
      if (year != 'All') 'year': year,
      if (genre != 'All') 'genre': genre,
      if (sort.isNotEmpty) 'sort': sort,
    };

    try {
      final res = await _client
          .post(Uri.parse(url), headers: headers, body: json.encode(body))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map) {
          final items = decoded['data']['items'] as List<dynamic>? ?? [];
          return items.map((e) => MediaItem.fromJson(e as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  // Specific tab wrappers
  Future<Map<String, dynamic>> fetchHomeOperating() => fetchTabOperating('0');
  Future<List<MediaItem>> fetchHomeTrending({int page = 1, int perPage = 18}) =>
      fetchTabTrending('0', page: page, perPage: perPage);

  Future<Map<String, dynamic>> fetchMidnightOperating() => fetchTabOperating('ONEROOM_MIDNIGHT');
  Future<List<MediaItem>> fetchMidnightTrending({int page = 1, int perPage = 18}) =>
      fetchTabTrending('ONEROOM_MIDNIGHT', page: page, perPage: perPage);

  Future<Map<String, dynamic>> fetchMovieOperating() => fetchTabOperating('ONEROOM_MOVIE');
  Future<List<MediaItem>> fetchMovieTrending({int page = 1, int perPage = 18}) =>
      fetchTabTrending('ONEROOM_MOVIE', page: page, perPage: perPage);

  // 10. Fetch Subject Recommendations / "For You" ("More Like This")
  Future<List<MediaItem>> fetchRecommendations(
    String subjectId, {
    String? genre,
    int? subjectType,
  }) async {
    final results = <MediaItem>[];
    final seenIds = <String>{subjectId};

    // 1. Try official recommendation endpoint (supports perPage=30)
    try {
      final url =
          'https://h5-api.aoneroom.com/wefeed-h5api-bff/subject/recommend?subjectId=$subjectId&perPage=30&page=1';
      final res = await _client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
          'Origin': 'https://movieboxhd.net',
          'Referer': 'https://movieboxhd.net/',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map) {
          final items = decoded['data']['movieItems'] as List<dynamic>? ?? [];
          for (final e in items) {
            final map = e as Map<String, dynamic>;
            final id = map['id']?.toString() ?? '';
            if (id.isEmpty || !seenIds.add(id)) continue;
            final title = map['name']?.toString() ?? 'Untitled';
            final cover = map['cover']?.toString() ??
                (map['coverImage'] is Map
                    ? map['coverImage']['url']?.toString()
                    : null);
            final typeStr = map['subjectType']?.toString().toLowerCase() ?? '';
            final sType =
                (typeStr.contains('series') || typeStr.contains('tv')) ? 2 : 1;
            final tag = map['tag']?.toString();
            String? g;
            String? releaseDate;
            if (tag != null && tag.isNotEmpty) {
              final parts = tag.split('·').map((p) => p.trim()).toList();
              if (parts.isNotEmpty) releaseDate = parts[0];
              if (parts.length >= 3) g = parts[2];
            }
            results.add(MediaItem(
              subjectId: id,
              title: title,
              coverUrl: cover,
              subjectType: sType,
              genre: g,
              releaseDate: releaseDate,
            ));
          }
        }
      }
    } catch (_) {}

    // If official recommendations already returned 30 items, return them
    if (results.length >= 30) return results.take(30).toList();

    // 2. Supplement or Fallback: pull similar items by genre & format to reach 30 items
    if (genre != null && genre.isNotEmpty) {
      try {
        final firstGenre = genre.split(',').first.split('/').first.trim();
        final channel = subjectType == 2 ? '2' : '1';
        final needed = 30 - results.length;
        final genreItems = await fetchWebSubjectFilter(
          channelId: channel,
          genre: firstGenre,
          sort: 'ForYou',
          perPage: needed > 15 ? needed : 15,
        );
        for (final item in genreItems) {
          if (seenIds.add(item.subjectId)) {
            results.add(item);
            if (results.length >= 30) break;
          }
        }
      } catch (_) {}
    }

    return results.take(30).toList();
  }

  // -------------------------------------------------------------
  // BuzzBox Community APIs (/wefeed-mobile-bff/...)
  // -------------------------------------------------------------

  /// 1. Fetch Community Sub-Tabs (For You, Discover, Images, Nearby)
  Future<List<BuzzBoxTabItem>> fetchCommunityTabs() async {
    const path = '/wefeed-mobile-bff/community/tab';
    try {
      final res = await _request(pathWithQuery: path, method: 'GET');
      if (res != null && res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map<String, dynamic>) {
          final items = decoded['data']['items'] as List<dynamic>? ?? [];
          final list = items
              .whereType<Map<String, dynamic>>()
              .map((it) => BuzzBoxTabItem.fromJson(it))
              .toList();
          if (list.isNotEmpty) return list;
        }
      }
    } catch (_) {}
    return [
      BuzzBoxTabItem(tabId: 'explore', name: 'For You', type: 'post'),
      BuzzBoxTabItem(tabId: 'discover', name: 'Discover', type: 'post'),
      BuzzBoxTabItem(tabId: 'images', name: 'Images', type: 'post'),
      BuzzBoxTabItem(tabId: 'nearby', name: 'Nearby', type: 'post'),
    ];
  }

  /// 2. Fetch Community Entrance & Trending Groups
  Future<List<BuzzBoxGroup>> fetchCommunityTrendingEntrance() async {
    const path = '/wefeed-mobile-bff/community/trending-entrance';
    try {
      final res = await _request(pathWithQuery: path, method: 'GET');
      if (res != null && res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map<String, dynamic>) {
          final groups = decoded['data']['groups'] as List<dynamic>? ?? [];
          return groups
              .whereType<Map<String, dynamic>>()
              .map((g) => BuzzBoxGroup.fromJson(g))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// 3. Fetch BuzzBox Posts by subtab ('explore', 'discover', 'images', 'nearby')
  Future<List<BuzzBoxPost>> fetchBuzzBoxPosts(String tabId, {int page = 1, int perPage = 10}) async {
    String path;
    if (tabId == 'explore' || tabId == 'for-you' || tabId.isEmpty) {
      path = '/wefeed-mobile-bff/post/explore?page=$page&perPage=$perPage';
    } else if (tabId == 'nearby') {
      path = '/wefeed-mobile-bff/post/nearby?page=$page&perPage=$perPage';
    } else {
      final cleanTab = tabId == 'images' ? 'image' : tabId;
      path = '/wefeed-mobile-bff/post/list-by-tab?tabId=$cleanTab&page=$page&perPage=$perPage';
    }

    try {
      final res = await _request(pathWithQuery: path, method: 'GET');
      if (res != null && res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map<String, dynamic>) {
          final items = decoded['data']['items'] as List<dynamic>? ?? [];
          return items
              .whereType<Map<String, dynamic>>()
              .map((it) => BuzzBoxPost.fromJson(it))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// 4. Fetch Group Detail
  Future<BuzzBoxGroup?> fetchGroupDetail(String groupId) async {
    final path = '/wefeed-mobile-bff/group/get?groupId=$groupId';
    try {
      final res = await _request(pathWithQuery: path, method: 'GET');
      if (res != null && res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map<String, dynamic>) {
          return BuzzBoxGroup.fromJson(decoded['data'] as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    return null;
  }

  /// 5. Fetch Group Posts
  Future<List<BuzzBoxPost>> fetchGroupPosts(String groupId, {int page = 1, int perPage = 10}) async {
    final path = '/wefeed-mobile-bff/post/list-trending/group?groupId=$groupId&page=$page&perPage=$perPage';
    try {
      final res = await _request(pathWithQuery: path, method: 'GET');
      if (res != null && res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map<String, dynamic>) {
          final items = decoded['data']['items'] as List<dynamic>? ?? [];
          return items
              .whereType<Map<String, dynamic>>()
              .map((it) => BuzzBoxPost.fromJson(it))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// 6. Fetch Single Post Detail
  Future<BuzzBoxPost?> fetchPostDetail(String postId) async {
    final path = '/wefeed-mobile-bff/post/get?postId=$postId';
    try {
      final res = await _request(pathWithQuery: path, method: 'GET');
      if (res != null && res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded['code'] == 0 && decoded['data'] is Map<String, dynamic>) {
          return BuzzBoxPost.fromJson(decoded['data'] as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    return null;
  }
}
