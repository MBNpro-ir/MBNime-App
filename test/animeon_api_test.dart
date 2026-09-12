import 'package:mbnime/models/anime_content.dart';
import 'package:mbnime/services/animeon_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'login keeps the official ci_session and accepts an authenticated page',
    () async {
      var requestNumber = 0;
      final api = AnimeOnApi(
        apiKey: 'test-client-key',
        client: MockClient((request) async {
          requestNumber++;
          if (requestNumber == 1) {
            return http.Response(
              '',
              200,
              headers: {'set-cookie': 'ci_session=first; Path=/'},
            );
          }
          if (requestNumber == 2) {
            expect(request.method, 'POST');
            expect(request.headers['cookie'], 'ci_session=first');
            return http.Response(
              '',
              200,
              headers: {'set-cookie': 'ci_session=active; Path=/'},
            );
          }
          expect(request.headers['cookie'], 'ci_session=active');
          return http.Response('', 200);
        }),
      );

      expect(
        await api.login(email: 'member@example.com', password: 'secret'),
        isTrue,
      );
      expect(api.sessionCookie, 'ci_session=active');
    },
  );

  test('login rejects a response that still contains the login form', () async {
    final api = AnimeOnApi(
      apiKey: 'test-client-key',
      client: MockClient(
        (_) async => http.Response(
          '<form id="login-form"></form>',
          200,
          headers: {'set-cookie': 'ci_session=guest; Path=/'},
        ),
      ),
    );

    expect(
      await api.login(email: 'wrong@example.com', password: 'wrong'),
      isFalse,
    );
  });

  test(
    'promotional cards are removed from every parsed catalog list',
    () async {
      final api = AnimeOnApi(
        apiKey: 'test-client-key',
        client: MockClient(
          (_) async => http.Response(
            '[{"videos_id":"10320","title":"AnimeON for ios"},'
            '{"videos_id":"7","title":"A real anime"}]',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

      final items = await api.catalog(kind: ContentKind.movie);
      expect(items.map((item) => item.id), ['7']);
    },
  );

  test(
    'details retries with the other type when the first has no files',
    () async {
      const seriesRow =
          '{"videos_id":"17358","title":"Clevatess","is_tvseries":"1",'
          '"season":[{"seasons_id":"1","seasons_name":"season 1",'
          '"episodes":[{"episodes_id":"11","episodes_name":"part 1",'
          '"file_url":"https://cdn.example/ep1.mp4"}]}],"videos":[]}';
      const emptyRow =
          '{"videos_id":"17358","title":"Clevatess","is_tvseries":"1",'
          '"season":[],"videos":[]}';
      final requestedTypes = <String>[];
      final api = AnimeOnApi(
        apiKey: 'test-client-key',
        client: MockClient((request) async {
          final type = request.url.queryParameters['type']!;
          requestedTypes.add(type);
          return http.Response(type == 'movie' ? emptyRow : seriesRow, 200);
        }),
      );

      // List rows lack is_tvseries, so a series can be mislabeled as movie.
      final summary = AnimeContent(
        id: '17358',
        title: 'Clevatess',
        subtitle: 'film',
        description: '',
        year: 2025,
        rating: 8,
        kind: ContentKind.movie,
        colors: const [Color(0xFF000000), Color(0xFF111111)],
        genres: const [],
      );
      final details = await api.details(summary);

      expect(requestedTypes, ['movie', 'tvseries']);
      expect(details.kind, ContentKind.series);
      expect(details.seasons, hasLength(1));
      expect(
        details.seasons.first.episodes.single.fileUrl,
        'https://cdn.example/ep1.mp4',
      );
    },
  );

  test('details parses the complete information payload', () async {
    const payload = '''{
      "videos_id":"17697","title":"Make a Girl","imdb_rating":"6.3",
      "imdbid":"tt33503342","release":"2025-01-31","runtime":"92 Min",
      "writer":"یه دختر بساز,Meiku a Garu,2025",
      "country":[{"name":"Japan"}],
      "director":[{"star_id":"1","name":"Gensho Yasuda"}],
      "cast":[{"star_id":"2","name":"Atsumi Tanezaki","image_url":"http://cdn/cast.jpg"}],
      "genre":[{"name":"عاشقانه"}],
      "download_links":[{"download_link_id":"3","label":"720P","file_size":"714","download_url":"https://cdn/movie.mp4"}],
      "related_movie":[{"videos_id":"4","title":"Your Name.","release":"2016","imdb_rating":"8.4"}],
      "videos":[{"video_file_id":"5","label":"720P","file_url":"https://cdn/movie.mp4"}]
    }''';
    final api = AnimeOnApi(
      apiKey: 'test-client-key',
      client: MockClient(
        (_) async => http.Response(
          payload,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    const summary = AnimeContent(
      id: '17697',
      title: 'Make a Girl',
      subtitle: 'فیلم',
      description: '',
      year: 2025,
      rating: 6.3,
      kind: ContentKind.movie,
      colors: [Color(0xFF000000), Color(0xFF111111)],
      genres: [],
    );

    final details = await api.details(summary);

    expect(details.imdbId, 'tt33503342');
    expect(details.runtime, '92 Min');
    expect(details.alternateTitles, ['یه دختر بساز', 'Meiku a Garu']);
    expect(details.countries, ['Japan']);
    expect(details.directors.single.name, 'Gensho Yasuda');
    expect(details.cast.single.name, 'Atsumi Tanezaki');
    expect(details.downloads.single.fileSize, '714');
    expect(details.related.single.title, 'Your Name.');
    expect(
      details.seasons.single.episodes.single.fileUrl,
      'https://cdn/movie.mp4',
    );
  });

  test(
    'comments are read-only and unrelated announcement rows are hidden',
    () async {
      final api = AnimeOnApi(
        apiKey: 'test-client-key',
        client: MockClient(
          (_) async => http.Response(
            '[{"comments_id":"1","videos_id":"1","user_name":"system",'
            '"comments":"announcement"},'
            '{"comments_id":"9","videos_id":"17697","user_name":"Sara",'
            '"user_img_url":"https://cdn/avatar.jpg","comments":"عالی بود"}]',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

      final comments = await api.comments('17697');

      expect(comments, hasLength(1));
      expect(comments.single.userName, 'Sara');
      expect(comments.single.text, 'عالی بود');
    },
  );

  test(
    'search parses live catalog rows and upgrades artwork to HTTPS',
    () async {
      final api = AnimeOnApi(
        apiKey: 'test-client-key',
        client: MockClient(
          (_) async => http.Response(
            '[{"title":"Attack on Titan","type":"TV-Series",'
            '"image":"http://animeonapp.com/poster.jpg",'
            '"url":"https://animeonapp.com/animebaz/watch2/12550.html"}]',
            200,
          ),
        ),
      );

      final results = await api.search('attack');
      expect(results, hasLength(1));
      expect(results.single.id, '12550');
      expect(results.single.kind, ContentKind.series);
      expect(results.single.imageUrl, startsWith('https://'));
    },
  );

  test(
    'countriesWithContent hides foreign and confirmed empty countries',
    () async {
      final probedIds = <String>[];
      final api = AnimeOnApi(
        apiKey: 'test-client-key',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/get_all_country')) {
            return http.Response(
              '[{"country_id":"1","name":"خارجی"},'
              '{"country_id":"2","name":"Active"},'
              '{"country_id":"3","name":"Empty"},'
              '{"country_id":"4","name":"Temporary error"}]',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          final id = request.url.queryParameters['id']!;
          probedIds.add(id);
          if (id == '2') return http.Response('[{"videos_id":"9"}]', 200);
          if (id == '3') return http.Response('[]', 200);
          return http.Response('server unavailable', 503);
        }),
      );

      final visible = await api.countriesWithContent();

      expect(visible.map((country) => country.id), ['2', '4']);
      expect(probedIds, isNot(contains('1')));
    },
  );

  test('home parses and orders the original editorial shelves', () async {
    final api = AnimeOnApi(
      apiKey: 'test-client-key',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/get_slider')) {
          return http.Response('{"data":[]}', 200);
        }
        if (request.url.path.endsWith('/get_latest_movies') ||
            request.url.path.endsWith('/get_latest_tvseries')) {
          return http.Response('[]', 200);
        }
        return http.Response(
          '[{"genre_id":"49","name":"اکشن","videos":['
          '{"videos_id":"1","title":"Action","imdb_rating":"8.2"}]},'
          '{"genre_id":"468","name":"پیشنهاد هفته","videos":['
          '{"videos_id":"2","title":"Pick","imdb_rating":"7"}]},'
          '{"genre_id":"375","name":"پر بازدید ماهانه","videos":['
          '{"videos_id":"3","title":"Popular","imdb_rating":"9"}]}]',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final home = await api.home();

    expect(home.sections.map((section) => section.id), ['375', '468', '49']);
    expect(home.sections.first.title, 'پربازدیدهای ماه');
    expect(home.sections.first.items.first.ratingLabel, '9');
  });
}
