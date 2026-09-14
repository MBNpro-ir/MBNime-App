import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/anime_content.dart';

class AnimeOnApiException implements Exception {
  const AnimeOnApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HomeCatalog {
  const HomeCatalog({
    required this.featured,
    required this.movies,
    required this.series,
    required this.sections,
  });
  final List<AnimeContent> featured;
  final List<AnimeContent> movies;
  final List<AnimeContent> series;
  final List<HomeSection> sections;
}

class HomeSection {
  const HomeSection({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<AnimeContent> items;
}

class CatalogGroup {
  const CatalogGroup({required this.id, required this.name, this.imageUrl});
  final String id;
  final String name;
  final String? imageUrl;
}

abstract interface class ContentApi {
  Future<AnimeContent> details(AnimeContent summary);
  Future<List<AnimeComment>> comments(String contentId);
}

class AnimeOnApi implements ContentApi {
  AnimeOnApi({
    http.Client? client,
    this.apiKey = const String.fromEnvironment('MBN_API_KEY'),
  }) : _client = client ?? http.Client();

  static const _origin = 'https://animeonapp.com';
  static const _loginPage = '$_origin/animebaz/user/login1';
  static const _loginAction = '$_origin/animebaz/user/do_login1';
  static const _signupAction = '$_origin/animebaz/user/signup/do_signup1';
  static const _searchAction = '$_origin/animebaz/home/autocompleteajax';
  static const _legacyOrigin = 'http://animeonapi.info/animebaz/api';
  final String apiKey;
  static const _legacyVersion = '𝑴𝑶𝑫 𝑩𝒚 @𝑯𝒂𝒄𝒌_𝑻𝒆𝒂𝒎';

  final http.Client _client;
  String? _sessionCookie;
  String? get sessionCookie => _sessionCookie;
  void restoreCookie(String cookie) => _sessionCookie = cookie;
  void clearSession() => _sessionCookie = null;

  Future<bool> login({required String email, required String password}) async {
    _sessionCookie = null;
    await _get(Uri.parse(_loginPage));
    await _post(
      Uri.parse(_loginAction),
      body: {'email': email.trim(), 'password': password},
    );
    final verification = await _get(Uri.parse(_loginPage));
    final body = verification.body.trim();
    if (body.contains('id="login-form"')) return false;
    return _sessionCookie != null && body.isEmpty;
  }

  Future<bool> validateCurrentSession() async {
    if (_sessionCookie == null) return false;
    final verification = await _get(Uri.parse(_loginPage));
    final body = verification.body.trim();
    return verification.statusCode == 200 &&
        !body.contains('id="login-form"') &&
        body.isEmpty;
  }

  /// Uses the account service's current registration form and field names.
  /// A successful registration is verified by immediately signing in; this
  /// avoids trusting redirects or translated flash messages from the website.
  Future<bool> register({
    required String name,
    required String email,
    required String mobile,
    required String password,
  }) async {
    _sessionCookie = null;
    await _get(Uri.parse(_loginPage));
    await _post(
      Uri.parse(_signupAction),
      body: {
        'name': name.trim(),
        'email': email.trim(),
        'mobile': mobile.trim(),
        'password': password,
        'password2': password,
      },
    );
    return login(email: email, password: password);
  }

  Future<HomeCatalog> home() async {
    final responses = await Future.wait([
      _legacyGet('get_slider'),
      _legacyGet('get_latest_movies'),
      _legacyGet('get_latest_tvseries'),
      _legacyGet('get_features_genre_and_movie'),
    ]);
    try {
      final sliderJson = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final sections = (jsonDecode(responses[3].body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map((row) {
            final id = _text(row['genre_id']);
            return HomeSection(
              id: id,
              title: _homeSectionTitles[id] ?? _cleanSectionTitle(row['name']),
              items: _parseList(row['videos'] as List<dynamic>? ?? const []),
            );
          })
          .where((section) => section.items.isNotEmpty)
          .toList();
      sections.sort(
        (a, b) =>
            _homeSectionPriority(a.id).compareTo(_homeSectionPriority(b.id)),
      );
      return HomeCatalog(
        featured: _parseList(sliderJson['data'] as List<dynamic>? ?? const []),
        movies: _parseList(
          jsonDecode(responses[1].body) as List<dynamic>,
          kindHint: ContentKind.movie,
        ),
        series: _parseList(
          jsonDecode(responses[2].body) as List<dynamic>,
          kindHint: ContentKind.series,
        ),
        sections: sections,
      );
    } catch (_) {
      throw const AnimeOnApiException('کاتالوگ MBNime قابل خواندن نیست.');
    }
  }

  Future<List<AnimeContent>> catalog({
    required ContentKind kind,
    int page = 1,
  }) async {
    final endpoint = kind == ContentKind.movie ? 'get_movies' : 'get_tvseries';
    final response = await _legacyGet(endpoint, {'page': '$page'});
    try {
      return _parseList(
        jsonDecode(response.body) as List<dynamic>,
        kindHint: kind,
      );
    } catch (_) {
      throw const AnimeOnApiException('فهرست محتوا قابل خواندن نیست.');
    }
  }

  Future<List<CatalogGroup>> genres() => _groups('get_all_genre', 'genre_id');

  Future<List<CatalogGroup>> countries() =>
      _groups('get_all_country', 'country_id');

  /// Keeps the complete server country list available through [countries],
  /// but returns only UI-worthy entries here. The legacy API exposes many
  /// empty country IDs and duplicate historical rows without a content count,
  /// so each candidate's first page must be checked explicitly.
  Future<List<CatalogGroup>> countriesWithContent() async {
    final allCountries = (await countries())
        .where((group) => !_isHiddenCountryLabel(group.name))
        .toList(growable: false);
    final visible = <CatalogGroup>[];

    // Limit concurrency so the screen loads quickly without sending all of
    // the legacy server's country probes at once.
    const batchSize = 12;
    for (var start = 0; start < allCountries.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, allCountries.length);
      final batch = allCountries.sublist(start, end);
      final checked = await Future.wait(batch.map(_countryIfVisible));
      visible.addAll(checked.whereType<CatalogGroup>());
    }
    return visible;
  }

  Future<CatalogGroup?> _countryIfVisible(CatalogGroup group) async {
    try {
      final response = await _legacyGet('get_movie_by_country_id', {
        'id': group.id,
        'page': '1',
      });
      final decoded = jsonDecode(response.body);
      if (decoded is List<dynamic>) return decoded.isEmpty ? null : group;
      // An unexpected response is not proof that the country is empty.
      return group;
    } catch (_) {
      // Only confirmed empty arrays are hidden. Preserve the entry if a probe
      // fails so a temporary network/server issue cannot erase countries.
      return group;
    }
  }

  static bool _isHiddenCountryLabel(String name) {
    final normalized = name.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'بدون عنوان' ||
        normalized == 'خارجی' ||
        normalized == 'foreign' ||
        normalized == 'other';
  }

  static String _cleanSectionTitle(Object? value) =>
      _brandSafeText(value).replaceAll('🆕', '').replaceAll('👌', '').trim();

  static int _homeSectionPriority(String id) {
    final index = _homeSectionOrder.indexOf(id);
    return index < 0 ? _homeSectionOrder.length : index;
  }

  Future<List<AnimeContent>> catalogByGroup({
    required CatalogGroup group,
    required bool country,
    int page = 1,
  }) async {
    final response = await _legacyGet(
      country ? 'get_movie_by_country_id' : 'get_movie_by_genre_id',
      {'id': group.id, 'page': '$page'},
    );
    try {
      return _parseList(jsonDecode(response.body) as List<dynamic>);
    } catch (_) {
      throw const AnimeOnApiException('محتوای این دسته قابل خواندن نیست.');
    }
  }

  Future<List<CatalogGroup>> _groups(String endpoint, String idKey) async {
    final response = await _legacyGet(endpoint);
    try {
      return (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(
            (row) => CatalogGroup(
              id: _text(row[idKey]),
              name: _brandSafeText(row['name'], fallback: 'بدون عنوان'),
              imageUrl: _nullableText(row['image_url']),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      throw const AnimeOnApiException('دسته‌بندی‌ها قابل خواندن نیستند.');
    }
  }

  /// Loads full details. List endpoints do not carry the `is_tvseries`
  /// flag, so the initial kind guess can be wrong (e.g. a series fetched
  /// as `type=movie` returns zero playable files). When the first attempt
  /// yields nothing playable, retry once with the other type.
  @override
  Future<AnimeContent> details(AnimeContent summary) async {
    if (isPromotionalContent(summary)) {
      throw const AnimeOnApiException(
        'این مورد تبلیغاتی در MBNime نمایش داده نمی‌شود.',
      );
    }
    final first = await _detailsAs(summary, summary.kind);
    if (_playableCount(first) > 0) return first;
    final other = summary.kind == ContentKind.movie
        ? ContentKind.series
        : ContentKind.movie;
    final second = await _detailsAs(summary, other);
    return _playableCount(second) > 0 ? second : first;
  }

  /// Public, read-only comments for a title. Comment submission deliberately
  /// stays outside this client until moderation and abuse handling exist.
  @override
  Future<List<AnimeComment>> comments(String contentId) async {
    final response = await _legacyGet('get_all_comments', {'id': contentId});
    try {
      return (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          // The legacy endpoint sometimes prepends a global announcement
          // whose videos_id does not match the requested title.
          .where((row) => _text(row['videos_id']) == contentId)
          .map(
            (row) => AnimeComment(
              id: _text(row['comments_id']),
              userName: _brandSafeText(
                row['user_name'],
                fallback: 'کاربر MBNime',
              ),
              text: _brandSafeText(row['comments']),
              userImageUrl: _nullableText(row['user_img_url']),
            ),
          )
          .where((comment) => comment.id.isNotEmpty && comment.text.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      throw const AnimeOnApiException('نظرات این عنوان قابل خواندن نیست.');
    }
  }

  Future<AnimeContent> _detailsAs(
    AnimeContent summary,
    ContentKind kind,
  ) async {
    final response = await _legacyGet('get_single_details', {
      'type': kind == ContentKind.movie ? 'movie' : 'tvseries',
      'id': summary.id,
    });
    try {
      final row = jsonDecode(response.body) as Map<String, dynamic>;
      final tvSeasons = (row['season'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (season) => AnimeSeason(
              id: _text(season['seasons_id']),
              name: _text(season['seasons_name'], fallback: 'فصل'),
              episodes: (season['episodes'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .map(
                    (episode) => AnimeEpisode(
                      id: _text(episode['episodes_id']),
                      name: _text(episode['episodes_name'], fallback: 'قسمت'),
                      fileUrl: _text(episode['file_url']),
                      imageUrl: _nullableText(episode['image_url']),
                      fileType: _text(episode['file_type']),
                      fileSize: _text(episode['file_size']),
                    ),
                  )
                  .where((episode) => episode.fileUrl.isNotEmpty)
                  .toList(growable: false),
            ),
          )
          .where((season) => season.episodes.isNotEmpty)
          .toList(growable: false);
      final movieEpisodes = (row['videos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (video) => AnimeEpisode(
              id: _text(video['video_file_id']),
              name: _text(video['label'], fallback: 'پخش فیلم'),
              fileUrl: _text(video['file_url']),
              fileType: _text(video['file_type']),
              fileSize: _text(video['file_size']),
            ),
          )
          .where((episode) => episode.fileUrl.isNotEmpty)
          .toList(growable: false);
      final seasons = [
        if (movieEpisodes.isNotEmpty)
          AnimeSeason(
            id: 'movie',
            name: 'کیفیت‌های پخش',
            episodes: movieEpisodes,
          ),
        ...tvSeasons,
      ];
      return _contentFromRow(row, seasons: seasons);
    } catch (_) {
      throw const AnimeOnApiException('جزئیات این عنوان قابل خواندن نیست.');
    }
  }

  Future<List<AnimeContent>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final response = await _get(
      Uri.parse(_searchAction).replace(queryParameters: {'term': normalized}),
    );
    if (response.statusCode != 200) {
      throw const AnimeOnApiException('جست‌وجوی آنلاین در دسترس نیست.');
    }
    try {
      final rows = jsonDecode(response.body) as List<dynamic>;
      return rows
          .whereType<Map<String, dynamic>>()
          .map(_contentFromSearchRow)
          .where((content) => !isPromotionalContent(content))
          .toList(growable: false);
    } catch (_) {
      throw const AnimeOnApiException('پاسخ جست‌وجو قابل خواندن نیست.');
    }
  }

  Future<http.Response> _legacyGet(
    String endpoint, [
    Map<String, String> extra = const {},
  ]) async {
    if (apiKey.trim().isEmpty) {
      throw const AnimeOnApiException(
        'تنظیمات اتصال سرویس در این بیلد موجود نیست. '
        'برای تست از Run-MBNime-Debug.ps1 استفاده کن؛ '
        'یا MBN_API_KEY را با --dart-define-from-file هنگام اجرا بده.',
      );
    }
    final uri = Uri.parse('$_legacyOrigin/$endpoint').replace(
      queryParameters: {
        'api_secret_key': apiKey,
        'version': _legacyVersion,
        'sp': 'true',
        'country': 'other',
        ...extra,
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200 || response.body.trim().isEmpty) {
      throw const AnimeOnApiException('سرور محتوای MBNime پاسخ نداد.');
    }
    return response;
  }

  List<AnimeContent> _parseList(List<dynamic> rows, {ContentKind? kindHint}) =>
      rows
          .whereType<Map<String, dynamic>>()
          .where((row) => !_isPromotionalRow(row))
          .map((row) => _contentFromRow(row, kindHint: kindHint))
          .toList(growable: false);

  static bool isPromotionalContent(AnimeContent content) =>
      _isPromotional(content.id, content.title);

  static bool _isPromotionalRow(Map<String, dynamic> row) =>
      _isPromotional(_text(row['videos_id']), _text(row['title']));

  static bool _isPromotional(String id, String title) {
    if (_promotionalContentIds.contains(id)) return true;
    final normalized = title
        .toLowerCase()
        .replaceAll(RegExp(r'[\s‌_-]+'), ' ')
        .trim();
    return normalized.contains('kidkat') ||
        normalized.contains('اینستاگرام ما') ||
        (normalized.contains('animeon') && normalized.contains('ios')) ||
        (normalized.contains('محتوای ویژه') && normalized.contains('اخبار اپ'));
  }

  int _playableCount(AnimeContent content) =>
      content.seasons.fold(0, (sum, season) => sum + season.episodes.length);

  AnimeContent _contentFromRow(
    Map<String, dynamic> row, {
    ContentKind? kindHint,
    List<AnimeSeason> seasons = const [],
  }) {
    final title = _brandSafeText(row['title'], fallback: 'بدون عنوان');
    // List endpoints omit `is_tvseries`; fall back to the endpoint hint.
    final seriesFlag = _text(row['is_tvseries']);
    final isSeries = seriesFlag.isNotEmpty
        ? seriesFlag == '1'
        : (kindHint == ContentKind.series || seasons.isNotEmpty);
    final release = _text(row['release']);
    final year = int.tryParse(
      RegExp(r'\d{4}').firstMatch(release)?.group(0) ?? '',
    );
    final genreRows = row['genre'] is List<dynamic>
        ? row['genre'] as List<dynamic>
        : const <dynamic>[];
    final genres = genreRows
        .whereType<Map<String, dynamic>>()
        .map((item) => _brandSafeText(item['name']))
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final countries = _namedRows(row['country']);
    final alternateTitles = _brandSafeText(row['writer'])
        .split(',')
        .map((value) => value.trim())
        .where(
          (value) => value.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(value),
        )
        .toSet()
        .toList(growable: false);
    final directors = _people(row['director']);
    final cast = _people(row['cast']);
    final downloads =
        (row['download_links'] is List<dynamic>
                ? row['download_links'] as List<dynamic>
                : const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => AnimeDownload(
                id: _text(item['download_link_id']),
                label: _brandSafeText(item['label'], fallback: 'دانلود'),
                url: _text(item['download_url']),
                fileSize: _text(item['file_size']),
              ),
            )
            .where((item) => item.url.isNotEmpty)
            .toList(growable: false);
    final relatedIds = <String>{};
    final relatedMovies =
        (row['related_movie'] is List<dynamic>
                ? row['related_movie'] as List<dynamic>
                : const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where((item) => _text(item['videos_id']).isNotEmpty)
            .where((item) => !_isPromotionalRow(item))
            .where((item) => relatedIds.add(_text(item['videos_id'])))
            .map((item) => _contentFromRow(item, kindHint: ContentKind.movie));
    // Series details use a separate key. Reading only `related_movie` left
    // the Similar tab empty for titles such as Saga of Tanya the Evil.
    final relatedSeries =
        (row['related_tvseries'] is List<dynamic>
                ? row['related_tvseries'] as List<dynamic>
                : const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where((item) => _text(item['videos_id']).isNotEmpty)
            .where((item) => !_isPromotionalRow(item))
            .where((item) => relatedIds.add(_text(item['videos_id'])))
            .map((item) => _contentFromRow(item, kindHint: ContentKind.series));
    final related = [...relatedMovies, ...relatedSeries];
    return AnimeContent(
      id: _text(row['videos_id']),
      title: title.replaceAll('📺', '').trim(),
      subtitle: _brandSafeText(
        row['video_quality'],
        fallback: isSeries ? 'سریال' : 'فیلم',
      ),
      description: _brandSafeText(
        row['description'],
        fallback: 'اطلاعات این عنوان در آرشیو MBNime ثبت شده است.',
      ),
      year: year ?? DateTime.now().year,
      rating: double.tryParse(_text(row['imdb_rating'])) ?? 0,
      kind: isSeries ? ContentKind.series : ContentKind.movie,
      colors: _palettes[title.hashCode.abs() % _palettes.length],
      genres: genres,
      episodes: seasons.fold(0, (sum, season) => sum + season.episodes.length),
      // Despite their names, this API's poster is the 16:9 artwork and its
      // thumbnail is the portrait card image.
      imageUrl: _nullableText(row['thumbnail_url']),
      backdropUrl: _nullableText(row['poster_url']),
      seasons: seasons,
      imdbId: _nullableText(row['imdbid']),
      runtime: _brandSafeText(row['runtime']),
      alternateTitles: alternateTitles,
      countries: countries,
      directors: directors,
      cast: cast,
      related: related,
      downloads: downloads,
    );
  }

  static List<String> _namedRows(Object? value) =>
      (value is List<dynamic> ? value : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map((item) => _brandSafeText(item['name']))
          .where((name) => name.isNotEmpty)
          .toList(growable: false);

  static List<AnimePerson> _people(Object? value) =>
      (value is List<dynamic> ? value : const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => AnimePerson(
              id: _text(item['star_id']),
              name: _brandSafeText(item['name'], fallback: 'بدون نام'),
              imageUrl: _nullableText(item['image_url']),
            ),
          )
          .where((person) => person.id.isNotEmpty)
          .toList(growable: false);

  AnimeContent _contentFromSearchRow(Map<String, dynamic> row) {
    final title = _brandSafeText(row['title'], fallback: 'بدون عنوان');
    final type = _text(row['type']).toLowerCase();
    final rawUrl = _text(row['url']);
    final id = RegExp(r'/watch2/(\d+)').firstMatch(rawUrl)?.group(1) ?? '';
    final kind = type == 'movie' ? ContentKind.movie : ContentKind.series;
    final searchPortrait = _nullableText(
      row['image'],
    )?.replaceFirst('http://', 'https://');
    final searchBackdrop = searchPortrait?.replaceFirst(
      '/video_thumb/',
      '/poster_image/',
    );
    return AnimeContent(
      id: id,
      title: title,
      subtitle: type.isEmpty ? 'MBNime' : type,
      description: 'برای مشاهده اطلاعات کامل، این عنوان را باز کن.',
      year: DateTime.now().year,
      rating: 0,
      kind: kind,
      colors: _palettes[title.hashCode.abs() % _palettes.length],
      genres: const [],
      imageUrl: searchPortrait,
      backdropUrl: searchBackdrop,
      detailUrl: rawUrl,
    );
  }

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  static String _brandSafeText(Object? value, {String fallback = ''}) {
    final text = _text(value, fallback: fallback);
    return text
        .replaceAll(RegExp(r'anime\s*on', caseSensitive: false), 'MBNime')
        .replaceAll(RegExp(r'انیمه[\s‌]*آن'), 'MBNime');
  }

  static String? _nullableText(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 25));
      _captureCookie(response);
      return response;
    } on TimeoutException {
      throw const AnimeOnApiException('ارتباط با MBNime زمان‌بر شد.');
    } on http.ClientException {
      throw const AnimeOnApiException('اتصال به MBNime برقرار نشد.');
    }
  }

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> body,
  }) async {
    try {
      final response = await _client
          .post(uri, headers: _headers(), body: body)
          .timeout(const Duration(seconds: 25));
      _captureCookie(response);
      return response;
    } on TimeoutException {
      throw const AnimeOnApiException('ارتباط با MBNime زمان‌بر شد.');
    } on http.ClientException {
      throw const AnimeOnApiException('اتصال به MBNime برقرار نشد.');
    }
  }

  Map<String, String> _headers() => {
    'Accept': 'text/html,application/json',
    'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 17) MBNime/1.0',
    'Cookie': ?_sessionCookie,
  };

  void _captureCookie(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) return;
    final match = RegExp(r'ci_session=([^;]+)').firstMatch(setCookie);
    if (match != null) _sessionCookie = 'ci_session=${match.group(1)}';
  }
}

const _palettes = <List<Color>>[
  [Color(0xFFEF8354), Color(0xFF3D193A)],
  [Color(0xFF61D4FF), Color(0xFF102A43)],
  [Color(0xFF9B7EDE), Color(0xFF261447)],
  [Color(0xFFFF6685), Color(0xFF41172A)],
];

// Non-catalog promotional cards published repeatedly by the legacy API.
// Keep both IDs and narrow title fallbacks so they stay hidden across every
// endpoint even if the server duplicates them under a new ID.
const _promotionalContentIds = <String>{
  '10320', // Legacy iOS promotion.
  '10358', // App/cinema news promotion.
  '10598', // KidKat app.
  '10838', // Instagram.
  '13587', // Duplicate iOS promotion.
};

/// Editorial order for the legacy home collections: discovery first, archives
/// second, viewing formats third, then genre shelves.
const _homeSectionOrder = <String>[
  '375', // Most viewed this month.
  '468', // Weekly picks.
  '73', // Editorial selection.
  '470', // Series 2025.
  '461', // Series 2024.
  '462', // Movies 2024.
  '433', // Movies 2022.
  '46', // Dubbed.
  '47', // Hard-subbed.
  '467', // Chinese anime.
  '49', // Action.
  '66', // Adventure.
  '53', // Fantasy.
  '58', // Sci-fi.
  '68', // Mystery.
  '67', // Horror.
  '62', // Crime.
  '50', // Comedy.
  '51', // Romance.
  '465', // Martial arts.
  '466', // Samurai.
];

const _homeSectionTitles = <String, String>{
  '375': 'پربازدیدهای ماه',
  '468': 'پیشنهاد هفته',
  '73': 'منتخب MBNime',
  '470': 'سریال‌های ۲۰۲۵',
  '461': 'سریال‌های ۲۰۲۴',
  '462': 'فیلم‌های ۲۰۲۴',
  '433': 'فیلم‌های ۲۰۲۲',
  '46': 'دوبله فارسی',
  '47': 'زیرنویس چسبیده',
  '467': 'انیمه چینی',
  '49': 'اکشن',
  '66': 'ماجراجویی',
  '53': 'فانتزی',
  '58': 'علمی–تخیلی',
  '68': 'رازآلود',
  '67': 'ترسناک',
  '62': 'جنایی',
  '50': 'کمدی',
  '51': 'عاشقانه',
  '465': 'رزمی',
  '466': 'سامورایی',
};
