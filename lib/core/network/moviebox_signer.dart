import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class MovieBoxSigner {
  static const String secretKeyDefaultB64 =
      "NzZpUmwwN3MweFNOOWpxbUVXQXQ3OUVCSlp1bElRSXNWNjRGWnIyTw==";
  static const String secretKeyAltB64 =
      "WHFuMm5uTzQxL0w5Mm8xaXVYaFNMSFRiWHZZNFo1Wlo2Mm04bVNMQQ==";

  static List<int>? _cachedSecretBytes;
  static String? _cachedDeviceId;

  static List<int> getRawSecretBytes({bool useAlt = false}) {
    if (_cachedSecretBytes != null && !useAlt) {
      return _cachedSecretBytes!;
    }
    final b64Key = useAlt ? secretKeyAltB64 : secretKeyDefaultB64;
    final decodedStr = utf8.decode(base64.decode(b64Key));
    final paddedStr = decodedStr + '=' * ((4 - (decodedStr.length % 4)) % 4);
    final rawBytes = base64.decode(paddedStr);
    if (!useAlt) {
      _cachedSecretBytes = rawBytes;
    }
    return rawBytes;
  }

  static String getDeviceId() {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    _cachedDeviceId = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _cachedDeviceId!;
  }

  static String generateXClientToken(int timestamp) {
    final tsStr = timestamp.toString();
    final revTs = tsStr.split('').reversed.join('');
    final hash = md5.convert(utf8.encode(revTs)).toString();
    return '$tsStr,$hash';
  }

  static String buildCanonicalString({
    required String method,
    required String accept,
    required String contentType,
    required String url,
    String? body,
    required int timestamp,
  }) {
    final uri = Uri.parse(url);
    final path = uri.path;

    String canonicalUrl = path;
    if (uri.queryParametersAll.isNotEmpty) {
      final sortedKeys = uri.queryParametersAll.keys.toList()..sort();
      final queryParts = <String>[];
      for (final key in sortedKeys) {
        final values = uri.queryParametersAll[key]!;
        for (final val in values) {
          queryParts.add('$key=$val');
        }
      }
      canonicalUrl = '$path?${queryParts.join('&')}';
    }

    final bodyBytes = body != null ? utf8.encode(body) : null;
    String bodyHash = '';
    String bodyLen = '';
    if (bodyBytes != null) {
      final trimmed =
          bodyBytes.length > 102400 ? bodyBytes.sublist(0, 102400) : bodyBytes;
      bodyHash = md5.convert(trimmed).toString();
      bodyLen = bodyBytes.length.toString();
    }

    return '${method.toUpperCase()}\n'
        '$accept\n'
        '$contentType\n'
        '$bodyLen\n'
        '$timestamp\n'
        '$bodyHash\n'
        '$canonicalUrl';
  }

  static String generateXTrSignature({
    required String method,
    required String accept,
    required String contentType,
    required String url,
    String? body,
    required int timestamp,
    bool useAltKey = false,
  }) {
    final canonical = buildCanonicalString(
      method: method,
      accept: accept,
      contentType: contentType,
      url: url,
      body: body,
      timestamp: timestamp,
    );

    final keyBytes = getRawSecretBytes(useAlt: useAltKey);
    final hmacMd5 = Hmac(md5, keyBytes);
    final digest = hmacMd5.convert(utf8.encode(canonical));
    final sigBase64 = base64.encode(digest.bytes);

    return '$timestamp|2|$sigBase64';
  }

  static String getClientInfo({
    String region = "IN",
    String language = "en",
    String brand = "samsung",
    String model = "SM-S918B",
  }) {
    final regUpper = region.toUpperCase();
    final isIndia = regUpper == 'IN';
    final pkg = isIndia ? "com.community.mbox.in" : "com.community.oneroom";
    String tz = "UTC";
    String sp = "";
    if (isIndia) {
      tz = "Asia/Calcutta";
      sp = "90101";
    } else if (regUpper == 'BD') {
      tz = "Asia/Dhaka";
      sp = "";
    } else if (regUpper == 'US' || regUpper == 'GLOBAL') {
      tz = "America/New_York";
      sp = "";
    } else if (regUpper == 'PH') {
      tz = "Asia/Manila";
      sp = "";
    } else if (regUpper == 'NG') {
      tz = "Africa/Lagos";
      sp = "90101";
    }

    return json.encode({
      "package_name": pkg,
      "version_name": isIndia ? "4.0.02.0831.03" : "4.0.02.0831.03",
      "version_code": 50020126,
      "os": "android",
      "os_version": "14",
      "device_id": getDeviceId(),
      "install_store": "ps",
      "gaid": "d7578036d13336cc",
      "brand": brand,
      "model": model,
      "system_language": language,
      "net": "NETWORK_WIFI",
      "region": regUpper == 'GLOBAL' ? 'US' : regUpper,
      "timezone": tz,
      "sp_code": sp,
    });
  }

  static Map<String, String> buildHeaders({
    required String url,
    required String method,
    String? body,
    String? token,
    bool isPlayback = false,
    String region = "IN",
  }) {
    final regUpper = region.toUpperCase();
    final pkg = regUpper == 'IN' ? "com.community.mbox.in" : "com.community.oneroom";
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final isPost = method.toUpperCase() == "POST";
    final contentType =
        isPost ? "application/json; charset=utf-8" : "application/json";
    const accept = "application/json";

    final clientToken = generateXClientToken(timestamp);
    final signature = generateXTrSignature(
      method: method,
      accept: accept,
      contentType: contentType,
      url: url,
      body: body,
      timestamp: timestamp,
    );

    final headers = <String, String>{
      "user-agent":
          "$pkg/50020126 (Linux; U; Android 14; en_${regUpper == 'GLOBAL' ? 'US' : regUpper}; SM-S918B; Build/UP1A.231005.007; Cronet/133.0.6876.3)",
      "accept": accept,
      "content-type": contentType,
      "connection": "keep-alive",
      "x-client-token": clientToken,
      "x-tr-signature": signature,
      "x-client-info": getClientInfo(region: region),
      "x-client-status": "0",
      "x-play-mode": isPlayback ? "1" : "2",
    };

    if (token != null && token.isNotEmpty) {
      headers["Authorization"] = "Bearer $token";
    }

    return headers;
  }

  /// Extracts the real DASH or HLS stream URL from the encrypted/signed cookie.
  /// MovieBox hides the real master playlist inside CloudFront-Policy or urlprefix
  /// to prevent scraping and protect premium streams.
  static String extractRealStreamUrl(String rawUrl, String? signCookie) {
    if (signCookie == null || signCookie.isEmpty) return rawUrl;

    // Only extract if rawUrl is actually the dummy teaser preview clip or empty.
    // If rawUrl is already a valid stream (e.g. Transsion OSS, direct mp4/m3u8), preserve it!
    final isTeaser = rawUrl.contains('b164fbfb43477929') ||
        rawUrl.contains('macdn.aoneroom.com/other/') ||
        rawUrl.trim().isEmpty;

    if (!isTeaser) {
      return rawUrl;
    }

    // 1. CloudFront-Policy extraction
    if (signCookie.contains('CloudFront-Policy=')) {
      try {
        final b64 = signCookie.split('CloudFront-Policy=')[1].split(';')[0];
        final padded = b64 + '=' * ((4 - (b64.length % 4)) % 4);
        final normalized = padded.replaceAll('-', '+').replaceAll('_', '/');
        final decoded = utf8.decode(base64.decode(normalized), allowMalformed: true).trim();

        // Robust regex extraction first to prevent JSON parse errors on malformed padding
        final resMatch = RegExp(r'"Resource"\s*:\s*"([^"]+)"').firstMatch(decoded);
        String? resource = resMatch?.group(1);

        if (resource == null) {
          final lastBrace = decoded.lastIndexOf('}');
          if (lastBrace != -1) {
            final cleanJson = decoded.substring(0, lastBrace + 1);
            final root = json.decode(cleanJson);
            final statement = (root['Statement'] as List?)?.firstOrNull;
            resource = statement?['Resource']?.toString();
          }
        }

        if (resource != null && resource.startsWith('http')) {
          final base = resource.contains('*')
              ? resource.substring(0, resource.lastIndexOf('*'))
              : resource;
          final cleanBase = base.endsWith('/') ? base : '$base/';
          final isHls = cleanBase.contains('/hls/') || cleanBase.contains('.m3u8');
          return isHls ? '${cleanBase}index.m3u8' : '${cleanBase}index.mpd';
        }
      } catch (_) {}
    }

    // 2. urlprefix extraction (only if rawUrl was a teaser)
    if (signCookie.contains('urlprefix=')) {
      try {
        final b64 = signCookie.split('urlprefix=')[1].split(';')[0].split(':sign=')[0];
        final padded = b64 + '=' * ((4 - (b64.length % 4)) % 4);
        final normalized = padded.replaceAll('-', '+').replaceAll('_', '/');
        final decoded = utf8.decode(base64.decode(normalized), allowMalformed: true).trim();
        final urlMatch = RegExp(r'(https?://[^\s;"]+)').firstMatch(decoded);
        final matchedUrl = urlMatch?.group(1) ?? (decoded.startsWith('http') ? decoded : null);
        if (matchedUrl != null) {
          final base = matchedUrl.contains('*')
              ? matchedUrl.substring(0, matchedUrl.lastIndexOf('*'))
              : matchedUrl;
          final cleanBase = base.endsWith('/') ? base : '$base/';
          final isHls = cleanBase.contains('/hls/') || cleanBase.contains('.m3u8');
          return isHls ? '${cleanBase}index.m3u8' : '${cleanBase}index.mpd';
        }
      } catch (_) {}
    }

    return rawUrl;
  }
}

