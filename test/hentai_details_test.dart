import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnime/models/anime_content.dart';
import 'package:mbnime/services/animeon_api.dart';
import 'package:mbnime/services/hentai_iran_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

AnimeContent summary() => const AnimeContent(
  id: '42',
  title: 'Example',
  subtitle: '',
  description: '',
  year: 2025,
  rating: 0,
  kind: ContentKind.anime,
  colors: [Colors.red, Colors.black],
  genres: [],
  isHentai: true,
  detailUrl: 'https://hentaiiran.com/anime/example/',
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'gated source uses direct catalog snapshot without account server or credentials',
    () async {
      final calls = <Uri>[];
      final api = HentaiIranApi(
        client: MockClient((request) async {
          calls.add(request.url);
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(request.headers.containsKey('Cookie'), isFalse);
          final snapshot = request.url.host == 'raw.githubusercontent.com';
          return http.Response(
            jsonEncode({
              'id': 42,
              'title': 'Example',
              'synopsis_fa': 'description',
              'episodes': snapshot
                  ? [
                      {
                        'episode': 1,
                        'quality': '720p',
                        'download_url': 'https://cdn.example/1.mp4',
                      },
                      {
                        'episode': 2,
                        'quality': '1080p',
                        'download_url': 'https://cdn.example/2.mp4',
                      },
                    ]
                  : [],
            }),
            200,
          );
        }),
      );
      final content = await api.details(summary());
      expect(calls.map((u) => u.host), [
        'hentaiiran.com',
        'raw.githubusercontent.com',
      ]);
      expect(
        calls.last.path,
        '/MBNpro-ir/MBNime-App/source-catalog/v1/titles/42.json',
      );
      expect(content.seasons.single.episodes, hasLength(2));
      expect(content.description, 'description');
    },
  );

  test(
    'native details use the structured episode API before JavaScript-only HTML',
    () async {
      final calls = <String>[];
      final api = HentaiIranApi(
        client: MockClient((request) async {
          calls.add(request.url.path);
          return http.Response(
            jsonEncode({
              'id': 42,
              'title': 'Example',
              'episodes': [
                {
                  'episode': 1,
                  'quality': '720p',
                  'download_url': 'https://cdn.example/1.mp4',
                },
                {
                  'episode': 2,
                  'quality': '1080p',
                  'download_url': 'https://cdn.example/2.mp4',
                },
              ],
            }),
            200,
          );
        }),
      );
      final content = await api.details(summary());
      expect(calls, ['/wp-json/hanime/v1/anime/42']);
      expect(content.seasons.single.episodes, hasLength(2));
      expect(
        content.seasons.single.episodes.first.fileUrl,
        'https://cdn.example/1.mp4',
      );
    },
  );
  test(
    'legacy HTML links still work if the structured endpoint is absent',
    () async {
      final sig = base64Url.encode(
        utf8.encode(jsonEncode({'url': 'https://cdn.example/1-720p.mp4'})),
      );
      final api = HentaiIranApi(
        client: MockClient((request) async {
          if (request.url.path.contains('/hanime/')) {
            return http.Response('{}', 404);
          }
          if (request.url.path.contains('/wp/v2/')) {
            return http.Response('{}', 200);
          }
          return http.Response(
            '<section><h3>قسمت 1</h3><a href="/?hi_route=go&amp;sig=$sig" aria-label="دانلود قسمت 1 720p">دانلود 720p</a></section>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      final content = await api.details(summary());
      expect(
        content.seasons.single.episodes.single.fileUrl,
        'https://cdn.example/1-720p.mp4',
      );
    },
  );
  test(
    'a page without episode links reports a retryable error rather than an empty success',
    () async {
      final api = HentaiIranApi(
        client: MockClient((request) async {
          if (request.url.path.contains('/wp-json/')) {
            return http.Response(
              jsonEncode({'id': 42, 'title': 'Example', 'episodes': []}),
              200,
            );
          }
          return http.Response(
            '<main><button data-episode="1">Play</button></main>',
            200,
          );
        }),
      );
      await expectLater(
        api.details(summary()),
        throwsA(isA<AnimeOnApiException>()),
      );
    },
  );

  test(
    'a previously loaded REST detail keeps working when the source goes offline',
    () async {
      final row = {
        'id': 42,
        'title': 'Example',
        'episodes': [
          {
            'episode': 1,
            'quality': '720p',
            'download_url': 'https://cdn.example/1.mp4',
          },
        ],
      };
      final online = HentaiIranApi(
        client: MockClient((_) async => http.Response(jsonEncode(row), 200)),
      );
      await online.details(summary());

      final offline = HentaiIranApi(
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      final content = await offline.details(summary());
      expect(
        content.seasons.single.episodes.single.fileUrl,
        'https://cdn.example/1.mp4',
      );
    },
  );

  test(
    'an empty REST episode response does not erase a complete cached detail',
    () async {
      final row = {
        'id': 42,
        'title': 'Example',
        'episodes': [
          {
            'episode': 1,
            'quality': '720p',
            'download_url': 'https://cdn.example/1.mp4',
          },
        ],
      };
      await HentaiIranApi(
        client: MockClient((_) async => http.Response(jsonEncode(row), 200)),
      ).details(summary());

      final empty = HentaiIranApi(
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'id': 42, 'episodes': []}), 200),
        ),
      );
      final content = await empty.details(summary());
      expect(
        content.seasons.single.episodes.single.fileUrl,
        'https://cdn.example/1.mp4',
      );
    },
  );
}
