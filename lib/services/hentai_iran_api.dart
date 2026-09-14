import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/anime_content.dart';
import 'animeon_api.dart';

/// Read-only adapter for HentaiIran's public WordPress catalogue.
///
/// The site stays the source of truth: lists come from `/wp-json/wp/v2/anime`
/// (with `_embed` taxonomy terms), episode/download links and the
/// «جزئیات تکمیلی / لینک‌های مرتبط / ژانرها / برچسب‌ها» sidebar are parsed
/// from the public title page, and no media bytes are ever copied or cached.
class HentaiIranApi implements ContentApi {
  HentaiIranApi({http.Client? client}) : _client = client ?? http.Client();

  static const origin = 'https://hentaiiran.com';

  /// Taxonomy slugs exactly as exposed by `/wp-json/wp/v2/types`.
  static const taxonomyGenre = 'genre';
  static const taxonomyTag = 'anime_tag';
  static const taxonomyStudio = 'hi_studio';
  static const taxonomyStatus = 'hi_status';
  static const taxonomyCensor = 'hi_censor';
  static const taxonomySubtitle = 'hi_sub';
  static const taxonomyYear = 'hi_year';

  static const Map<String, String> taxonomyTitles = {
    taxonomyGenre: 'ژانرها',
    taxonomyTag: 'برچسب‌ها',
    taxonomyStudio: 'استودیوها',
    taxonomyStatus: 'وضعیت پخش',
    taxonomyCensor: 'سانسور',
    taxonomyYear: 'سال ساخت',
    taxonomySubtitle: 'زیرنویس',
  };

  final http.Client _client;

  Map<String, String> get _headers => const {
    'Accept': 'application/json, text/html',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MBNime/1.0',
  };

  // ---------------------------------------------------------------- terms

  Future<List<HentaiTerm>> terms(
    String taxonomy, {
    int perPage = 100,
    int page = 1,
    String? search,
  }) async {
    final uri = Uri.parse('$origin/wp-json/wp/v2/$taxonomy').replace(
      queryParameters: {
        'per_page': '$perPage',
        'page': '$page',
        'orderby': 'count',
        'order': 'desc',
        if (search != null && search.trim().isNotEmpty)
          'search': search.trim(),
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw const AnimeOnApiException('دسته‌بندی هنتای در دسترس نیست.');
    }
    final data = jsonDecode(response.body);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => HentaiTerm(
            id: '${row['id']}',
            name: _strip(row['name']),
            count: (row['count'] as num?)?.toInt() ?? 0,
            slug: '${row['slug'] ?? ''}',
            taxonomy: taxonomy,
          ),
        )
        .where((term) => term.name.isNotEmpty)
        .toList(growable: false);
  }

  /// همه ترم‌های یک تاکسونومی (ورق‌به‌ورق؛ سقف وردپرس ۱۰۰ تاست و
  /// `per_page=200` خطای ۴۰۰ می‌دهد).
  Future<List<HentaiTerm>> termsAll(
    String taxonomy, {
    int maxPages = 5,
  }) async {
    final all = <HentaiTerm>[];
    for (var page = 1; page <= maxPages; page++) {
      final next = await terms(taxonomy, perPage: 100, page: page);
      if (next.isEmpty) break;
      all.addAll(next);
      if (next.length < 100) break;
    }
    return all;
  }

  Future<List<HentaiTerm>> genres() => terms(taxonomyGenre);
  Future<List<HentaiTerm>> tags() => terms(taxonomyTag);
  Future<List<HentaiTerm>> studios() => terms(taxonomyStudio);
  Future<List<HentaiTerm>> statuses() => terms(taxonomyStatus);
  Future<List<HentaiTerm>> censors() => terms(taxonomyCensor);
  Future<List<HentaiTerm>> years() =>
      terms(taxonomyYear, perPage: 100);

  // ---------------------------------------------------------------- lists

  /// Filtered anime archive. Every [HentaiFilter] id is a numeric WP term id.
  Future<List<AnimeContent>> anime({
    int page = 1,
    int perPage = 24,
    String? search,
    HentaiFilter filter = const HentaiFilter(),
    HentaiSort sort = HentaiSort.newest,
  }) async {
    final query = <String, String>{
      'per_page': '$perPage',
      'page': '$page',
      '_embed': '1',
      'orderby': sort.restOrderBy,
      'order': sort.restOrder,
      if (search != null && search.trim().isNotEmpty)
        'search': search.trim(),
      if (filter.genreId != null) taxonomyGenre: filter.genreId!,
      if (filter.tagId != null) taxonomyTag: filter.tagId!,
      if (filter.studioId != null) taxonomyStudio: filter.studioId!,
      if (filter.statusId != null) taxonomyStatus: filter.statusId!,
      if (filter.censorId != null) taxonomyCensor: filter.censorId!,
      if (filter.yearId != null) taxonomyYear: filter.yearId!,
      if (filter.subtitleId != null) taxonomySubtitle: filter.subtitleId!,
    };
    final uri = Uri.parse(
      '$origin/wp-json/wp/v2/anime',
    ).replace(queryParameters: query);
    late http.Response response;
    try {
      response = await _get(uri);
    } on AnimeOnApiException {
      rethrow;
    }
    if (response.statusCode == 400 || response.statusCode == 404) {
      // Past the last page.
      return const [];
    }
    if (response.statusCode != 200) {
      throw const AnimeOnApiException('فهرست هنتای ایران در دسترس نیست.');
    }
    final rows = jsonDecode(response.body);
    if (rows is! List) return const [];
    var items = rows
        .whereType<Map<String, dynamic>>()
        .map(_summary)
        .toList(growable: false);
    items = sort.applyToSummaries(items);
    return items;
  }

  Future<List<AnimeContent>> latest({int page = 1, String? search}) =>
      anime(page: page, search: search, sort: HentaiSort.newest);

  Future<List<AnimeContent>> byTerm(
    String taxonomy,
    String id, {
    int page = 1,
    int perPage = 24,
    HentaiSort sort = HentaiSort.newest,
  }) {
    final filter = HentaiFilter.fromTaxonomy(taxonomy, id);
    return anime(page: page, perPage: perPage, filter: filter, sort: sort);
  }

  /// Home shelves mirroring the website sections:
  /// featured slider, latest updates, popular (monthly views), newest by
  /// release year, random picks and per-genre rails.
  Future<HentaiHome> home({int genreRails = 3}) async {
    final topGenres = await genres().catchError(
      (_) => const <HentaiTerm>[],
    );
    final rails = topGenres.take(genreRails).toList(growable: false);
    final results = await Future.wait([
      anime(page: 1, perPage: 12, sort: HentaiSort.newest).catchError(
        (_) => const <AnimeContent>[],
      ),
      popular(limit: 12).catchError((_) => const <AnimeContent>[]),
      newestByYear(limit: 12).catchError((_) => const <AnimeContent>[]),
      randomTitles(limit: 10).catchError((_) => const <AnimeContent>[]),
      ...rails.map(
        (term) => byTerm(
          taxonomyGenre,
          term.id,
          page: 1,
          perPage: 10,
        ).catchError((_) => const <AnimeContent>[]),
      ),
    ]);
    final latest = results[0] as List<AnimeContent>; // ignore: unnecessary_cast
    final popularList = results[1] as List<AnimeContent>; // ignore: unnecessary_cast
    final byYear = results[2] as List<AnimeContent>; // ignore: unnecessary_cast
    final random = results[3] as List<AnimeContent>; // ignore: unnecessary_cast
    final featured = <AnimeContent>[
      ...latest.take(6),
      ...popularList.take(6),
    ].take(12).toList(growable: false);
    final sections = <HentaiSection>[];
    for (var i = 0; i < rails.length; i++) {
      final items = results[4 + i] as List<AnimeContent>; // ignore: unnecessary_cast
      if (items.isEmpty) continue;
      sections.add(
        HentaiSection(
          id: 'genre-${rails[i].id}',
          title: rails[i].name,
          items: items,
          taxonomy: taxonomyGenre,
          termId: rails[i].id,
          termName: rails[i].name,
        ),
      );
    }
    return HentaiHome(
      featured: featured.isEmpty ? latest : featured,
      latest: latest,
      popular: popularList,
      newestByYear: byYear,
      random: random,
      genreSections: sections,
    );
  }

  // ------------------------------------------- HTML archive sorts (site)

  /// «پربازدیدترین‌ها» — `/anime/?sort=views&period=monthly`.
  Future<List<AnimeContent>> popular({int limit = 20}) =>
      _archiveHtml(sort: 'views', limit: limit);

  /// «سال انتشار» — `/anime/?sort=year`.
  Future<List<AnimeContent>> newestByYear({int limit = 20}) =>
      _archiveHtml(sort: 'year', limit: limit);

  /// «هنتای رندوم» — `/anime/?sort=random`.
  Future<List<AnimeContent>> randomTitles({int limit = 20}) =>
      _archiveHtml(sort: 'random', limit: limit);

  Future<List<AnimeContent>> _archiveHtml({
    required String sort,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$origin/anime/').replace(
      queryParameters: {
        'sort': sort,
        if (sort == 'views') 'period': 'monthly',
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw const AnimeOnApiException('آرشیو هنتای ایران در دسترس نیست.');
    }
    return _parseArchiveCards(response.body, limit: limit);
  }

  List<AnimeContent> _parseArchiveCards(String html, {int limit = 20}) {
    final doc = html_parser.parse(html);
    final cards = doc.querySelectorAll('a.anime-card');
    final seen = <String>{};
    final items = <AnimeContent>[];
    for (final card in cards) {
      if (items.length >= limit) break;
      final href = card.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;
      final id =
          card.attributes['data-post-id']?.trim() ?? _slugFromUrl(href);
      if (id.isEmpty || !seen.add(id)) continue;
      final img = card.querySelector('img');
      final image =
          img?.attributes['src']?.trim() ??
          img?.attributes['data-src']?.trim();
      var title =
          card.attributes['title']?.trim() ??
          card.attributes['aria-label']?.trim() ??
          '';
      if (title.isEmpty) {
        title =
            card.querySelector('h3')?.text.trim() ??
            _strip(card.text).split('\n').first.trim();
      }
      title = _cleanCardTitle(title);
      if (title.isEmpty) continue;
      final year = _yearFromText(card.text);
      final studio = _studioFromCard(card);
      items.add(
        AnimeContent(
          id: id,
          title: title,
          subtitle: [
            if (studio.isNotEmpty) studio,
            if (year > 0) '$year',
          ].join(' • ').ifEmpty('هنتای ایران'),
          description: '',
          year: year,
          rating: 0,
          kind: ContentKind.anime,
          colors: _paletteFor(title),
          genres: const ['هنتای'],
          imageUrl: (image == null || image.isEmpty) ? null : image,
          detailUrl: href,
          isHentai: true,
          studio: studio,
          ageRating: '18+',
        ),
      );
    }
    return items;
  }

  // ---------------------------------------------------------------- details

  AnimeContent _summary(Map<String, dynamic> row) {
    final embedded = row['_embedded'];
    String? image;
    if (embedded is Map) {
      final media = embedded['wp:featuredmedia'];
      if (media is List && media.isNotEmpty && media.first is Map) {
        final first = media.first as Map;
        image =
            (first['source_url'] ?? (first['guid'] as Map?)?['rendered'])
                ?.toString();
      }
    }
    final terms = _embeddedTerms(embedded);
    final studio = _firstTerm(terms[taxonomyStudio]);
    final status = _firstTerm(terms[taxonomyStatus]);
    final censor = _firstTerm(terms[taxonomyCensor]);
    final subtitle = _firstTerm(terms[taxonomySubtitle]);
    final year = _yearFromTerms(terms[taxonomyYear]) ??
        int.tryParse((row['date'] ?? '').toString().substring(0, 4)) ??
        0;
    final genreTerms = terms[taxonomyGenre] ?? const <String>[];
    final tagNames = terms[taxonomyTag] ?? const <String>[];
    final title = _strip((row['title'] as Map?)?['rendered']);
    final genreList = genreTerms.isEmpty
        ? const ['هنتای']
        : genreTerms;
    return AnimeContent(
      id: '${row['id']}',
      title: title.isEmpty ? 'بدون عنوان' : title,
      subtitle: [
        if (studio.isNotEmpty) studio,
        if (year > 0) '$year',
      ].join(' • ').ifEmpty('هنتای ایران'),
      description: _strip((row['excerpt'] as Map?)?['rendered']),
      year: year,
      rating: 0,
      kind: ContentKind.anime,
      colors: _paletteFor(title),
      genres: genreList,
      imageUrl: (image == null || image.isEmpty) ? null : image,
      detailUrl: row['link']?.toString(),
      isHentai: true,
      studio: studio,
      statusLabel: status,
      censorLabel: censor,
      subtitleLabel: subtitle,
      ageRating: '18+',
      tags: tagNames,
    );
  }

  @override
  Future<AnimeContent> details(AnimeContent summary) async {
    // 1) Structured taxonomy terms from the REST single endpoint.
    Map<String, List<String>> restTerms = const {};
    String restDescription = '';
    String restDate = '';
    try {
      final single = await _restSingle(summary);
      if (single != null) {
        restTerms = _embeddedTerms(single['_embedded']);
        restDescription = _strip(
          (single['excerpt'] as Map?)?['rendered'],
        );
        restDate = '${single['date'] ?? ''}';
      }
    } catch (_) {
      // The HTML page below is the fallback source of truth.
    }

    // 2) Full title page: episodes, sidebar, related rails.
    final url = summary.detailUrl ?? '$origin/?p=${summary.id}';
    final response = await _get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw const AnimeOnApiException('جزئیات این عنوان قابل خواندن نیست.');
    }
    final doc = html_parser.parse(response.body);

    final page = _parseDetailPage(doc, summary);

    final genres = page.genres.isNotEmpty
        ? page.genres
        : (restTerms[taxonomyGenre] ?? const <String>[]);
    final tags = page.tags.isNotEmpty
        ? page.tags
        : (restTerms[taxonomyTag] ?? summary.tags);
    final studio = page.studio.isNotEmpty
        ? page.studio
        : (_firstTerm(restTerms[taxonomyStudio], fallback: summary.studio));
    final status = page.status.isNotEmpty
        ? page.status
        : (_firstTerm(restTerms[taxonomyStatus], fallback: summary.statusLabel));
    final censor = _firstTerm(
      restTerms[taxonomyCensor],
      fallback: summary.censorLabel,
    );
    final subtitle = _firstTerm(
      restTerms[taxonomySubtitle],
      fallback: summary.subtitleLabel,
    );
    var year = page.year > 0 ? page.year : summary.year;
    if (year <= 0) {
      year = _yearFromTerms(restTerms[taxonomyYear]) ?? year;
    }
    final description = page.description.isNotEmpty
        ? page.description
        : (restDescription.isNotEmpty
            ? restDescription
            : summary.description);

    final seasons = page.episodesByNumber.isEmpty
        ? const <AnimeSeason>[]
        : _buildSeasons(page.episodesByNumber);
    final downloads = page.episodesByNumber.values
        .expand((list) => list)
        .map(
          (e) => AnimeDownload(
            id: 'dl-${e.id}',
            label: e.name,
            url: e.fileUrl,
            fileSize: e.fileSize,
          ),
        )
        .toList(growable: false);

    return AnimeContent(
      id: summary.id,
      title: summary.title,
      subtitle: [
        if (studio.isNotEmpty) studio,
        if (year > 0) '$year',
      ].join(' • ').ifEmpty('هنتای ایران'),
      description: description.isEmpty
          ? 'توضیح فارسی این عنوان در هنتای ایران ثبت نشده است.'
          : description,
      year: year,
      rating: 0,
      kind: ContentKind.anime,
      colors: summary.colors,
      genres: genres.where((g) => g.trim().isNotEmpty).toList(growable: false),
      imageUrl: summary.imageUrl ?? page.poster,
      backdropUrl: page.poster ?? summary.imageUrl,
      detailUrl: summary.detailUrl,
      isHentai: true,
      seasons: seasons,
      studio: studio,
      statusLabel: status,
      censorLabel: censor,
      subtitleLabel: subtitle,
      viewsText: page.views,
      downloadsText: page.downloadsCount,
      publishDateText: page.publishDate.isNotEmpty
          ? page.publishDate
          : (restDate.isNotEmpty ? restDate.substring(0, 10) : ''),
      ageRating: '18+',
      tags: tags,
      related: page.related,
      downloads: downloads,
      relatedLinks: page.relatedLinks,
    );
  }

  Future<Map<String, dynamic>?> _restSingle(AnimeContent summary) async {
    final numeric = int.tryParse(summary.id);
    late Uri uri;
    if (numeric != null) {
      uri = Uri.parse(
        '$origin/wp-json/wp/v2/anime/$numeric',
      ).replace(queryParameters: {'_embed': '1'});
    } else {
      final slug = _slugFromUrl(summary.detailUrl ?? '');
      if (slug.isEmpty) return null;
      uri = Uri.parse('$origin/wp-json/wp/v2/anime').replace(
        queryParameters: {'slug': slug, '_embed': '1'},
      );
    }
    final response = await _get(uri);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) return data;
    if (data is List && data.isNotEmpty && data.first is Map) {
      return (data.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  _ParsedDetail _parseDetailPage(dom.Document doc, AnimeContent summary) {
    // --- description
    var description = _strip(
      doc.querySelector('meta[name="description"]')?.attributes['content'],
    );
    final poster = doc
            .querySelector('meta[property="og:image"]')
            ?.attributes['content']
            ?.trim() ??
        '';
    description = _cleanDescription(description);

    // --- episodes grouped by «قسمت N»
    final episodesByNumber = <String, List<AnimeEpisode>>{};
    var order = 0;
    for (final link in doc.querySelectorAll('a[href*="hi_route=go"]')) {
      final rawHref = link.attributes['href'];
      if (rawHref == null || rawHref.isEmpty) continue;
      final href = rawHref.replaceAll('&amp;', '&');
      final aria = link.attributes['aria-label'] ?? '';
      final text = _strip(link.text).replaceAll(RegExp(r'\s+'), ' ');
      final combined = '$aria $text';
      if (!_isWatchOrDownloadLabel(combined)) continue;
      final ep = _episodeNumber(link, fallback: '${order + 1}');
      final absolute = Uri.parse(origin).resolve(href).toString();
      // لینک «پخش آنلاین» همان فایل MP4 (معمولاً 1080P) را باز می‌کند؛
      // کیفیت را از نشانی مقصد هم بخوان تا برچسب «بدون برچسب کیفیت»
      // ساخته نشود. اگر هیچ کیفیتی پیدا نشد، لینک تکراری است و رد می‌شود.
      final target = _decodeGoTarget(absolute);
      final quality = _qualityLabel('$combined $target');
      if (quality == 'پخش آنلاین') continue;
      final resolved = _normalizeMediaUrl(_directMediaUrl(absolute));
      if (resolved.isEmpty) continue;
      order++;
      final episode = AnimeEpisode(
        id: '${summary.id}-ep$ep-$quality-$order',
        name: 'قسمت $ep • ${quality.toLowerCase()}',
        fileUrl: resolved,
        fileType: 'mp4',
      );
      episodesByNumber.putIfAbsent(ep, () => []).add(episode);
    }

    // --- «جزئیات تکمیلی» sidebar
    var publishDate = '';
    var year = 0;
    var studio = '';
    var status = '';
    var views = '';
    var downloadsCount = '';
    final detailRoot = _sectionRoot(doc, ['جزئیات تکمیلی', 'جزئیات']);
    if (detailRoot != null) {
      for (final row in detailRoot.querySelectorAll('div')) {
        final classes = row.attributes['class'] ?? '';
        if (!classes.contains('justify-between')) continue;
        final spans = row.querySelectorAll('span');
        if (spans.length < 2) continue;
        final label = _strip(spans.first.text);
        final valueEl = spans.last;
        final value = _strip(valueEl.text);
        if (label.contains('تاریخ انتشار')) {
          publishDate = value;
        } else if (label.contains('سال انتشار')) {
          year = _yearFromText(valueEl.text) != 0
              ? _yearFromText(valueEl.text)
              : (int.tryParse(_faToEn(value).replaceAll(RegExp(r'[^0-9]'), '')) ??
                  0);
        } else if (label.contains('استودیو')) {
          studio = value;
        } else if (label.contains('رده سنی') || label.contains('ردهٔ')) {
          // ثابت ‎+18‎ — نادیده گرفته می‌شود چون در مدل ذخیره است.
        } else if (label.contains('بازدید')) {
          views = value;
        } else if (label.contains('دانلود')) {
          downloadsCount = value;
        }
      }
      // وضعیت داخل «جزئیات تکمیلی» نیست؛ از لینک‌های مرتبط برداشته می‌شود.
    }

    // --- «لینک‌های مرتبط»
    final relatedLinks = <HentaiRelatedLink>[];
    final linksRoot = _sectionRoot(doc, ['لینک‌های مرتبط', 'لینکهای مرتبط']);
    if (linksRoot != null) {
      for (final a in linksRoot.querySelectorAll('a[href]')) {
        final title = _strip(a.text);
        final href = a.attributes['href']?.trim() ?? '';
        if (title.isEmpty || href.isEmpty) continue;
        if (href.contains('/hentai-subtitle-farsi')) {
          relatedLinks.add(
            HentaiRelatedLink(
              title: title,
              url: href,
              taxonomy: taxonomySubtitle,
              highlight: true,
            ),
          );
          continue;
        }
        final taxonomy = _taxonomyFromUrl(href);
        relatedLinks.add(
          HentaiRelatedLink(
            title: title,
            url: href,
            taxonomy: taxonomy,
            termId: _slugFromUrl(href),
            highlight: (a.attributes['class'] ?? '').contains('green'),
          ),
        );
        if (taxonomy == taxonomyStatus && status.isEmpty) status = title;
        if (taxonomy == taxonomyStudio && studio.isEmpty) {
          studio = title
              .replaceFirst('استودیو', '')
              .replaceFirst('استدیو', '')
              .trim();
        }
      }
    }

    // --- «ژانرها» و «برچسب‌ها»
    List<String> genres = const [];
    final genresRoot = _sectionRoot(doc, ['ژانرها']);
    if (genresRoot != null) {
      // ریشه «لینک‌های مرتبط» هم کلمه ژانر دارد؛ دقیقاً بخش ژانرها را بردار.
      genres = genresRoot
          .querySelectorAll('a[href*="/genre/"]')
          .map((a) => _strip(a.text))
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }
    if (genres.isEmpty) {
      genres = doc
          .querySelectorAll('a[href*="/genre/"]')
          .map((a) => _strip(a.text))
          .where((t) => t.isNotEmpty && t.length < 30)
          .toSet()
          .take(20)
          .toList(growable: false);
    }
    var tags = <String>[];
    final tagsRoot = _sectionRoot(doc, ['برچسب']);
    if (tagsRoot != null) {
      tags = tagsRoot
          .querySelectorAll('a[href*="/anime-tag/"]')
          .map((a) => _strip(a.text))
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }

    // --- تب «انیمه‌های مشابه» سایت
    final related = <AnimeContent>[];
    final seenRelated = <String>{};
    for (final card
        in doc.querySelectorAll('.hi-similar-rail__item a.anime-card')) {
      final href = card.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;
      final id =
          card.attributes['data-post-id']?.trim() ?? _slugFromUrl(href);
      if (id.isEmpty || !seenRelated.add(id)) continue;
      final img = card.querySelector('img');
      final image = img?.attributes['src']?.trim();
      // متن تمیز داخل h3 (صفت title پیشوند «مشاهده، دانلود و تماشای…» دارد).
      var title = _cleanCardTitle(_strip(card.querySelector('h3')?.text));
      if (title.isEmpty) {
        title = _cleanCardTitle(card.attributes['title'] ?? '');
      }
      if (title.isEmpty) continue;
      final studio = card
              .querySelector('span[title]')
              ?.attributes['title']
              ?.trim() ??
          '';
      var year = 0;
      var censor = '';
      for (final span in card.querySelectorAll('span')) {
        if (year == 0) year = _yearFromText(span.text);
        if (censor.isEmpty) {
          final badge = _strip(span.text).toUpperCase();
          if (badge == 'CEN' || badge == 'UNC') censor = badge;
        }
        if (year > 0 && censor.isNotEmpty) break;
      }
      related.add(
        AnimeContent(
          id: id,
          title: title,
          subtitle: [
            if (studio.isNotEmpty) studio,
            if (year > 0) '$year',
          ].join(' • ').ifEmpty('هنتای ایران'),
          description: '',
          year: year,
          rating: 0,
          kind: ContentKind.anime,
          colors: _paletteFor(title),
          genres: const ['هنتای'],
          imageUrl: (image == null || image.isEmpty) ? null : image,
          detailUrl: href,
          isHentai: true,
          studio: studio,
          censorLabel: censor,
        ),
      );
      if (related.length >= 24) break;
    }

    return _ParsedDetail(
      description: description,
      poster: poster.isEmpty ? null : poster,
      episodesByNumber: episodesByNumber,
      publishDate: publishDate,
      year: year,
      studio: studio,
      status: status,
      views: views,
      downloadsCount: downloadsCount,
      relatedLinks: relatedLinks,
      genres: genres,
      tags: tags,
      related: related,
    );
  }

  List<AnimeSeason> _buildSeasons(Map<String, List<AnimeEpisode>> grouped) {
    final episodes = grouped.entries.toList()
      ..sort((a, b) => _faToEn(a.key).compareTo(_faToEn(b.key)));
    return [
      AnimeSeason(
        id: 'episodes',
        name: 'قسمت‌ها',
        episodes: episodes.expand((e) => e.value).toList(growable: false),
      ),
    ];
  }

  // ---------------------------------------------------------------- comments

  @override
  Future<List<AnimeComment>> comments(String contentId) async {
    final numeric = int.tryParse(contentId);
    if (numeric == null) return const [];
    final uri = Uri.parse('$origin/wp-json/wp/v2/comments').replace(
      queryParameters: {
        'post': '$numeric',
        'per_page': '100',
        'orderby': 'date',
        'order': 'desc',
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) return const [];
    final data = jsonDecode(response.body);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => AnimeComment(
            id: '${row['id']}',
            userName: _strip(row['author_name']).ifEmpty('کاربر هنتای ایران'),
            text: _strip((row['content'] as Map?)?['rendered']),
            userImageUrl: _avatarFromRow(row),
          ),
        )
        .where((c) => c.text.isNotEmpty)
        .toList(growable: false);
  }

  // ------------------------------------------------------------------- blog

  /// «وبلاگ» سایت — پست‌های وردپرسی `/wp-json/wp/v2/posts`.
  Future<List<HentaiPost>> posts({int page = 1, String? search}) async {
    final uri = Uri.parse('$origin/wp-json/wp/v2/posts').replace(
      queryParameters: {
        'per_page': '12',
        'page': '$page',
        '_embed': '1',
        if (search != null && search.trim().isNotEmpty)
          'search': search.trim(),
      },
    );
    final response = await _get(uri);
    if (response.statusCode == 400 || response.statusCode == 404) {
      return const [];
    }
    if (response.statusCode != 200) {
      throw const AnimeOnApiException('وبلاگ هنتای ایران در دسترس نیست.');
    }
    final data = jsonDecode(response.body);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(_postFromRow)
        .toList(growable: false);
  }

  HentaiPost _postFromRow(Map<String, dynamic> row) {
    String? image;
    final embedded = row['_embedded'];
    if (embedded is Map) {
      final media = embedded['wp:featuredmedia'];
      if (media is List && media.isNotEmpty && media.first is Map) {
        image = ((media.first as Map)['source_url'])?.toString();
      }
    }
    return HentaiPost(
      id: '${row['id']}',
      title: _strip((row['title'] as Map?)?['rendered']).ifEmpty('بدون عنوان'),
      excerpt: _strip((row['excerpt'] as Map?)?['rendered']),
      content: _strip((row['content'] as Map?)?['rendered']),
      link: row['link']?.toString() ?? '',
      imageUrl: (image == null || image.isEmpty) ? null : image,
      date: '${row['date'] ?? ''}',
    );
  }

  // ------------------------------------------------------------------ helpers

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const AnimeOnApiException('ارتباط با هنتای ایران زمان‌بر شد.');
    } on http.ClientException {
      throw const AnimeOnApiException('اتصال به هنتای ایران برقرار نشد.');
    }
  }

  static Map<String, List<String>> _embeddedTerms(Object? embedded) {
    final result = <String, List<String>>{
      taxonomyStatus: const [],
      taxonomyStudio: const [],
      taxonomyCensor: const [],
      taxonomySubtitle: const [],
      taxonomyYear: const [],
      taxonomyGenre: const [],
      taxonomyTag: const [],
    };
    if (embedded is! Map) return result;
    final groups = embedded['wp:term'];
    if (groups is! List) return result;
    for (final group in groups) {
      if (group is! List || group.isEmpty) continue;
      String? taxonomy;
      final names = <String>[];
      for (final term in group) {
        if (term is! Map) continue;
        taxonomy ??= term['taxonomy']?.toString();
        final name = _strip(term['name']);
        if (name.isNotEmpty) names.add(name);
      }
      if (taxonomy != null && taxonomy.isNotEmpty) {
        result[taxonomy] = names;
      }
    }
    return result;
  }

  static int? _yearFromTerms(List<String>? names) {
    if (names == null) return null;
    for (final name in names) {
      final year = _yearFromText(name);
      if (year > 0) return year;
    }
    return null;
  }

  static int _yearFromText(String text) {
    final normalized = _faToEn(text);
    final match = RegExp(r'(19|20)\d{2}').firstMatch(normalized);
    return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
  }

  static String _studioFromCard(dom.Element card) {
    // ساختار کارت آرشیو ثابت نیست؛ نام استودیو معمولاً تنها متن لاتین
    // کوتاه داخل کارت است (مثل Pink Pineapple).
    final latin = RegExp(r'[A-Za-z][A-Za-z0-9 .,&!-]+').allMatches(card.text);
    for (final m in latin) {
      final candidate = m.group(0)!.trim();
      if (candidate.length >= 3 &&
          candidate.length <= 42 &&
          !candidate.toLowerCase().contains('hentai') &&
          !candidate.contains('http')) {
        return candidate;
      }
    }
    return '';
  }

  static String _cleanCardTitle(String raw) {
    var title = raw
        .replaceAll('دانلود و تماشای رایگان انیمه', '')
        .replaceAll('مشاهده، دانلود و تماشای هنتای', '')
        .replaceAll('دانلود و تماشای هنتای', '')
        .replaceAll('دانلود و تماشای', '')
        .replaceAll('تماشای رایگان', '')
        .replaceAll('با توضیحات فارسی', '')
        .replaceAll('زیرنویس فارسی', '')
        .replaceAll('مشاهده،', '')
        .replaceAll('مشاهده', '')
        .trim();
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title;
  }

  static String _cleanDescription(String raw) {
    var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 900) text = '${text.substring(0, 900)}…';
    return text;
  }

  static bool _isWatchOrDownloadLabel(String combined) {
    return combined.contains('پخش') ||
        combined.contains('1080') ||
        combined.contains('720') ||
        combined.contains('480');
  }

  static String _qualityLabel(String combined) {
    if (combined.contains('1080')) return '1080P';
    if (combined.contains('720')) return '720P';
    if (combined.contains('480')) return '480P';
    return 'پخش آنلاین';
  }

  static String _episodeNumber(dom.Element link, {required String fallback}) {
    dom.Element? node = link;
    for (var depth = 0; depth < 6 && node != null; depth++) {
      final String text = node.text;
      final match = RegExp(
        r'قسمت\s*([۰-۹0-9]+)',
      ).firstMatch(text);
      if (match != null) return _faToEn(match.group(1)!);
      node = node.parent;
    }
    final aria = link.attributes['aria-label'] ?? '';
    final afterCasm = RegExp(r'قسمت\s*([۰-۹0-9]+)').firstMatch(aria);
    if (afterCasm != null) return _faToEn(afterCasm.group(1)!);
    final direct = RegExp(r'([۰-۹0-9]+)').firstMatch(aria);
    if (direct != null) return _faToEn(direct.group(1)!);
    return _faToEn(fallback);
  }

  /// ریشه بخش سایدبار (جزئیات تکمیلی / لینک‌ها / ژانرها / برچسب‌ها).
  static dom.Element? _sectionRoot(dom.Document doc, List<String> keywords) {
    final headings = doc.querySelectorAll('h3, h2, h4');
    for (final h in headings) {
      final text = _strip(h.text);
      if (keywords.any(text.contains)) {
        dom.Element? node = h.parent;
        for (var depth = 0; depth < 4 && node != null; depth++) {
          if (node.querySelectorAll('a, div').length >= 2) return node;
          node = node.parent;
        }
        return h.parent;
      }
    }
    return null;
  }

  static String _taxonomyFromUrl(String url) {
    if (url.contains('/genre/')) return taxonomyGenre;
    if (url.contains('/anime-tag/')) return taxonomyTag;
    if (url.contains('/studio/')) return taxonomyStudio;
    if (url.contains('/status/')) return taxonomyStatus;
    if (url.contains('/censor/')) return taxonomyCensor;
    if (url.contains('/year/')) return taxonomyYear;
    if (url.contains('/subtitle/') || url.contains('subtitle-farsi')) {
      return taxonomySubtitle;
    }
    return 'link';
  }

  static String _slugFromUrl(String url) {
    try {
      final segments = Uri.parse(url).pathSegments.where(
        (s) => s.isNotEmpty,
      );
      return segments.isEmpty ? '' : segments.last;
    } catch (_) {
      return '';
    }
  }

  static String? _avatarFromRow(Map<String, dynamic> row) {
    final avatars = row['author_avatar_urls'];
    if (avatars is Map) {
      for (final key in ['96', '48', '24']) {
        final url = avatars[key]?.toString();
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  static String _strip(Object? value) =>
      html_parser.parse(value?.toString() ?? '').body?.text.trim() ?? '';

  static String _firstTerm(List<String>? terms, {String fallback = ''}) =>
      (terms != null && terms.isNotEmpty) ? terms.first : fallback;

  static String _faToEn(String input) => input
      .replaceAllMapped(
        RegExp(r'[۰-۹]'),
        (m) => '${'۰۱۲۳۴۵۶۷۸۹'.indexOf(m.group(0)!)}',
      )
      .replaceAllMapped(
        RegExp(r'[٠-٩]'),
        (m) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(m.group(0)!)}',
      );

  static List<Color> _paletteFor(String seed) =>
      _palettes[seed.hashCode.abs() % _palettes.length];

  /// نشانی مقصد داخل توکن `sig` (بدون دنبال‌کردن `u` صفحه تماشا).
  static String _decodeGoTarget(String href) {
    try {
      final token = Uri.parse(href).queryParameters['sig'];
      if (token == null) return href;
      final payload = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(token.split('.').first)),
        ),
      );
      final target = payload is Map ? payload['url']?.toString() : null;
      return (target == null || target.isEmpty) ? href : target;
    } catch (_) {
      return href;
    }
  }

  static String _directMediaUrl(String href) {
    final target = _decodeGoTarget(href);
    if (target == href) return href;
    try {
      final direct = Uri.parse(target).queryParameters['u'];
      return direct != null && direct.isNotEmpty ? direct : target;
    } catch (_) {
      return target;
    }
  }

  /// یکدست‌سازی درصدگذاری نشانی تا لینک «پخش آنلاین» و دانلود مستقیمِ
  /// یک کیفیت، رشته یکسان بگیرند و تکراری‌زدایی کیفیت‌ها کار کند.
  static String _normalizeMediaUrl(String url) {
    try {
      return Uri.parse(url).toString();
    } catch (_) {
      return url;
    }
  }
}

const _palettes = <List<Color>>[
  [Color(0xFFB91C3C), Color(0xFF450A0A)],
  [Color(0xFFEF8354), Color(0xFF3D193A)],
  [Color(0xFF9B7EDE), Color(0xFF261447)],
  [Color(0xFFFF6685), Color(0xFF41172A)],
];

class HentaiTerm {
  const HentaiTerm({
    required this.id,
    required this.name,
    required this.count,
    this.slug = '',
    this.taxonomy = '',
  });
  final String id;
  final String name;
  final int count;
  final String slug;
  final String taxonomy;
}

/// ترکیب فیلترهای آرشیو انیمه‌ها (همه شناسه‌ها عددی وردپرس هستند).
class HentaiFilter {
  const HentaiFilter({
    this.genreId,
    this.tagId,
    this.studioId,
    this.statusId,
    this.censorId,
    this.yearId,
    this.subtitleId,
  });

  final String? genreId;
  final String? tagId;
  final String? studioId;
  final String? statusId;
  final String? censorId;
  final String? yearId;
  final String? subtitleId;

  factory HentaiFilter.fromTaxonomy(String taxonomy, String id) {
    return HentaiFilter(
      genreId: taxonomy == HentaiIranApi.taxonomyGenre ? id : null,
      tagId: taxonomy == HentaiIranApi.taxonomyTag ? id : null,
      studioId: taxonomy == HentaiIranApi.taxonomyStudio ? id : null,
      statusId: taxonomy == HentaiIranApi.taxonomyStatus ? id : null,
      censorId: taxonomy == HentaiIranApi.taxonomyCensor ? id : null,
      yearId: taxonomy == HentaiIranApi.taxonomyYear ? id : null,
      subtitleId: taxonomy == HentaiIranApi.taxonomySubtitle ? id : null,
    );
  }

  bool get isEmpty =>
      genreId == null &&
      tagId == null &&
      studioId == null &&
      statusId == null &&
      censorId == null &&
      yearId == null &&
      subtitleId == null;

  int get activeCount =>
      [
        genreId,
        tagId,
        studioId,
        statusId,
        censorId,
        yearId,
        subtitleId,
      ].where((v) => v != null).length;
}

/// مرتب‌سازی آرشیو؛ دقیقاً هم‌نام گزینه‌های سایت.
enum HentaiSort {
  newest('جدیدترین', 'date', 'desc'),
  oldest('قدیمی‌ترین', 'date', 'asc'),
  titleAsc('حروف الفبا (الف تا ی)', 'title', 'asc'),
  titleDesc('حروف الفبا (ی تا الف)', 'title', 'desc'),
  modified('آخرین بروزرسانی', 'modified', 'desc');

  const HentaiSort(this.label, this.restOrderBy, this.restOrder);
  final String label;
  final String restOrderBy;
  final String restOrder;

  List<AnimeContent> applyToSummaries(List<AnimeContent> items) {
    // orderby/title سمت سرور انجام می‌شود؛ فقط برای اطمینان همان ترتیب حفظ
    // می‌شود تا رفتار همه فیلترها قابل پیش‌بینی بماند.
    return items;
  }
}

class HentaiSection {
  const HentaiSection({
    required this.id,
    required this.title,
    required this.items,
    required this.taxonomy,
    required this.termId,
    this.termName = '',
  });
  final String id;
  final String title;
  final List<AnimeContent> items;
  final String taxonomy;
  final String termId;
  final String termName;
}

class HentaiHome {
  const HentaiHome({
    required this.featured,
    required this.latest,
    required this.popular,
    required this.newestByYear,
    required this.random,
    required this.genreSections,
  });
  final List<AnimeContent> featured;
  final List<AnimeContent> latest;
  final List<AnimeContent> popular;
  final List<AnimeContent> newestByYear;
  final List<AnimeContent> random;
  final List<HentaiSection> genreSections;
}

class HentaiPost {
  const HentaiPost({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.content,
    required this.link,
    required this.date,
    this.imageUrl,
  });
  final String id;
  final String title;
  final String excerpt;
  final String content;
  final String link;
  final String date;
  final String? imageUrl;
}

class _ParsedDetail {
  const _ParsedDetail({
    required this.description,
    required this.poster,
    required this.episodesByNumber,
    required this.publishDate,
    required this.year,
    required this.studio,
    required this.status,
    required this.views,
    required this.downloadsCount,
    required this.relatedLinks,
    required this.genres,
    required this.tags,
    required this.related,
  });
  final String description;
  final String? poster;
  final Map<String, List<AnimeEpisode>> episodesByNumber;
  final String publishDate;
  final int year;
  final String studio;
  final String status;
  final String views;
  final String downloadsCount;
  final List<HentaiRelatedLink> relatedLinks;
  final List<String> genres;
  final List<String> tags;
  final List<AnimeContent> related;
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
