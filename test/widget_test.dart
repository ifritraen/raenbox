import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_plus/core/network/moviebox_signer.dart';
import 'package:moviebox_plus/core/proxy/local_stream_proxy.dart';
import 'package:moviebox_plus/data/models/moviebox_models.dart';
import 'package:moviebox_plus/data/services/local_storage_service.dart';

void main() {
  group('MovieBoxSigner Unit Tests', () {
    test('generateXClientToken format and validity', () {
      const timestamp = 1725992000000;
      final token = MovieBoxSigner.generateXClientToken(timestamp);
      expect(token, startsWith('1725992000000,'));
      final parts = token.split(',');
      expect(parts.length, 2);
      expect(parts[1].length, 32); // MD5 hex length
    });

    test('generateXTrSignature output structure', () {
      const timestamp = 1725992000000;
      final sig = MovieBoxSigner.generateXTrSignature(
        method: 'GET',
        accept: 'application/json',
        contentType: 'application/json',
        url: 'https://api3.aoneroom.com/wefeed-mobile-bff/tab/ranking-list?tabId=0',
        timestamp: timestamp,
      );
      expect(sig, startsWith('1725992000000|2|'));
      final parts = sig.split('|');
      expect(parts.length, 3);
      expect(parts[1], '2');
      expect(parts[2].isNotEmpty, true);
    });

    test('extractRealStreamUrl decodes CloudFront-Policy correctly', () {
      // CloudFront-Policy containing: {"Statement":[{"Resource":"https://sacdn.hakunaymatata.com/dash/123_1080/*"}]}
      const dummyUrl = 'https://macdn.aoneroom.com/other/2026/09/04/b164fbfb4347792950bdfbfb563d39d9.mp4';
      const cookie = 'CloudFront-Policy=eyJTdGF0ZW1lbnQiOlt7IlJlc291cmNlIjoiaHR0cHM6Ly9zYWNkbi5oYWt1bmF5bWF0YXRhLmNvbS9kYXNoLzEyM18xMDgwLyoifV19;';
      final resolved = MovieBoxSigner.extractRealStreamUrl(dummyUrl, cookie);
      expect(resolved, 'https://sacdn.hakunaymatata.com/dash/123_1080/index.mpd');
    });

    test('extractRealStreamUrl preserves direct mp4 if no policy', () {
      const directUrl = 'https://cdn.example.com/video.mp4';
      final resolved = MovieBoxSigner.extractRealStreamUrl(directUrl, null);
      expect(resolved, directUrl);
    });

    test('LocalStreamProxy session registration', () async {
      await LocalStreamProxy.instance.start();
      final proxied = LocalStreamProxy.instance.registerStream(
        originalUrl: 'https://sacdn.hakunaymatata.com/dash/123_1080/index.mpd',
        signCookie: 'CloudFront-Policy=abc;',
      );
      expect(proxied, contains('http://127.0.0.1:'));
      expect(proxied, contains('/stream/'));
      expect(proxied, endsWith('/index.mpd'));
      await LocalStreamProxy.instance.stop();
    });

    test('MediaItem model parsing', () {
      final json = {
        'subjectId': '5904172458474619680',
        'title': 'Beauty in Black [Hindi]',
        'subjectType': 2,
        'releaseDate': '2024-10-24',
        'imdbRatingValue': '5.9',
        'cover': {'url': 'https://pacdn.aoneroom.com/test.jpg'}
      };

      final item = MediaItem.fromJson(json);
      expect(item.subjectId, '5904172458474619680');
      expect(item.title, 'Beauty in Black');
      expect(item.isSeries, true);
      expect(item.isMovie, false);
      expect(item.imdbRating, '5.9');
      expect(item.coverUrl, 'https://pacdn.aoneroom.com/test.jpg');
    });

    test('LocalStorageService geocentric region detection', () {
      final detected = LocalStorageService.detectDeviceRegion();
      expect(detected.isNotEmpty, true);
      expect(['IN', 'US', 'NG', 'PH', 'KR', 'JP', 'GB', 'CN'].contains(detected), true);
    });
  });
}
