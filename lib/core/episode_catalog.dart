import '../models/anime_content.dart';

class EpisodeVariant {
  const EpisodeVariant({
    required this.season,
    required this.episode,
    required this.quality,
  });

  final AnimeSeason season;
  final AnimeEpisode episode;
  final String quality;
}

/// برچسب پیش‌فرض وقتی هیچ کیفیتی (480p و...) از نام فصل/قسمت پیدا نشود.
const unknownQualityLabel = 'بدون برچسب کیفیت';

/// true وقتی [quality] همان «بدون برچسب کیفیت» است — شامل حالت‌های
/// چند سروره مثل «بدون برچسب کیفیت · سرور 2».
bool isUnknownQuality(String quality) =>
    quality == unknownQualityLabel ||
    quality.startsWith('$unknownQualityLabel ·') ||
    quality.startsWith('$unknownQualityLabel •');

/// true وقتی متن به تیزر/تریلر اشاره دارد (فارسی یا انگلیسی).
bool isTrailerLabel(String value) =>
    RegExp(r'تیزر|trailer|teaser', caseSensitive: false).hasMatch(value);

/// برچسب نمایشی کیفیت: «بدون برچسب کیفیت» به «پخش» تبدیل می‌شود و
/// پسوند سرور حفظ می‌ماند («بدون برچسب کیفیت · سرور 2» ← «سرور 2»).
String qualityDisplayLabel(String quality) {
  if (quality == unknownQualityLabel) return 'پخش';
  final server = RegExp(r'·\s*(سرور\s*.+)').firstMatch(quality);
  if (server != null && quality.startsWith(unknownQualityLabel)) {
    return server.group(1)!.trim();
  }
  final dotServer = RegExp(r'•\s*(سرور\s*.+)').firstMatch(quality);
  if (dotServer != null && quality.startsWith(unknownQualityLabel)) {
    return dotServer.group(1)!.trim();
  }
  return quality;
}

class EpisodeGroup {
  const EpisodeGroup({
    required this.id,
    required this.name,
    required this.variants,
  });

  final String id;
  final String name;
  final List<EpisodeVariant> variants;

  /// true وقتی این گروه مربوط به تیزر است (شناسه منطقی trailer یا نام تیزر).
  bool get isTrailer => id.contains('trailer') || isTrailerLabel(name);

  EpisodeVariant variantFor(String? quality) {
    if (quality != null) {
      for (final variant in variants) {
        if (variant.quality == quality) return variant;
      }
    }
    return variants.first;
  }

  bool contains(AnimeEpisode episode) => variants.any(
    (variant) =>
        variant.episode.id == episode.id &&
        variant.episode.fileUrl == episode.fileUrl,
  );
}

class EpisodeSeasonGroup {
  const EpisodeSeasonGroup({
    required this.id,
    required this.name,
    required this.episodes,
  });

  final String id;
  final String name;
  final List<EpisodeGroup> episodes;

  List<String> get qualities =>
      _qualityList(episodes.expand((episode) => episode.variants));

  /// true وقتی این فصل همان فصل تیزرها است.
  bool get isTrailerSeason => id == 'trailer';

  /// کیفیت‌های نمایشی فصل — بدون آلودگی تیزرها:
  /// - فصل تیزرها: فقط کیفیت‌های واقعی (معمولاً خالی → انتخاب‌گر کیفیت مخفی).
  /// - فصل فیلم/سریال عادی: کیفیت تیزرها (معمولاً «بدون برچسب کیفیت»)
  ///   از فهرست حذف می‌شود تا چیپ اضافه نسازد؛ کیفیت‌های واقعی فیلم می‌ماند.
  /// - اگر هیچ واریانت غیرتیزری نبود، کیفیت‌های واقعی همه واریانت‌ها برمی‌گردد.
  List<String> get displayQualities {
    final allVariants = episodes.expand((episode) => episode.variants);
    if (isTrailerSeason) {
      return _qualityList(
        allVariants.where((variant) => !isUnknownQuality(variant.quality)),
      );
    }
    final nonTrailer = allVariants.where(
      (variant) =>
          !isTrailerLabel(variant.episode.name) &&
          !isTrailerLabel(variant.season.name),
    );
    final list = _qualityList(nonTrailer);
    if (list.isNotEmpty) return list;
    return _qualityList(
      allVariants.where((variant) => !isUnknownQuality(variant.quality)),
    );
  }
}

class EpisodeCatalog {
  const EpisodeCatalog({required this.seasons, required this.qualities});

  final List<EpisodeSeasonGroup> seasons;
  final List<String> qualities;

  Iterable<EpisodeGroup> get episodes =>
      seasons.expand((season) => season.episodes);

  EpisodeGroup? groupFor(AnimeEpisode episode) {
    for (final group in episodes) {
      if (group.contains(episode)) return group;
    }
    return null;
  }

  static EpisodeCatalog from(AnimeContent content) {
    if (content.seasons.isEmpty) {
      return const EpisodeCatalog(seasons: [], qualities: []);
    }
    if (content.kind == ContentKind.movie &&
        content.seasons.length == 1 &&
        content.seasons.first.id == 'movie') {
      final raw = content.seasons.first;
      final all = raw.episodes
          .map(
            (episode) => EpisodeVariant(
              season: raw,
              episode: episode,
              quality: episodeQuality(raw.name, episode.name),
            ),
          )
          .toList(growable: false);
      // تیزر فیلم نباید به‌عنوان یک «کیفیت» (معمولاً «بدون برچسب کیفیت»)
      // قاطی نسخه‌های اصلی شود؛ جدا می‌شود تا چیپ کیفیت را آلوده نکند.
      final mains = all
          .where(
            (variant) =>
                !isTrailerLabel(variant.episode.name) &&
                !isTrailerLabel(raw.name),
          )
          .toList(growable: false);
      final trailers = all
          .where(
            (variant) =>
                isTrailerLabel(variant.episode.name) ||
                isTrailerLabel(raw.name),
          )
          .toList(growable: false);
      if (mains.isEmpty) {
        // فقط تیزر موجود است: همان را بدون آلودگی کیفیت نمایش بده.
        final trailerGroups = [
          for (final variant in trailers)
            EpisodeGroup(
              id: 'logical:movie:trailer-${variant.episode.id}',
              name: variant.episode.name.isEmpty
                  ? 'تیزر'
                  : variant.episode.name,
              variants: [variant],
            ),
        ];
        final fallbackVariants = trailerGroups.isEmpty
            ? const <EpisodeVariant>[]
            : trailerGroups.expand((group) => group.variants);
        return EpisodeCatalog(
          seasons: [
            EpisodeSeasonGroup(
              id: 'movie',
              name: 'فیلم',
              episodes: trailerGroups.isEmpty
                  ? [
                      EpisodeGroup(
                        id: 'logical:movie:main',
                        name: 'پخش فیلم',
                        variants: _uniqueVariants(all),
                      ),
                    ]
                  : trailerGroups,
            ),
          ],
          qualities: _qualityList(fallbackVariants),
        );
      }
      final mainVariants = _uniqueVariants(mains);
      final trailerGroups = [
        for (final variant in trailers)
          EpisodeGroup(
            id: 'logical:movie:trailer-${variant.episode.id}',
            name: variant.episode.name.isEmpty
                ? 'تیزر'
                : variant.episode.name,
            variants: [variant],
          ),
      ];
      return EpisodeCatalog(
        seasons: [
          EpisodeSeasonGroup(
            id: 'movie',
            name: 'فیلم',
            episodes: [
              EpisodeGroup(
                id: 'logical:movie:main',
                name: 'پخش فیلم',
                variants: mainVariants,
              ),
              ...trailerGroups,
            ],
          ),
        ],
        qualities: _qualityList(mainVariants),
      );
    }

    final seasonBuckets = <String, List<(int, AnimeSeason)>>{};
    for (final (index, season) in content.seasons.indexed) {
      final key = _seasonKey(season.name, index);
      seasonBuckets.putIfAbsent(key, () => []).add((index, season));
    }
    final groupedSeasons = <EpisodeSeasonGroup>[];
    final allVariants = <EpisodeVariant>[];
    for (final entry in seasonBuckets.entries) {
      final episodeBuckets = <String, List<(int, EpisodeVariant)>>{};
      for (final (_, season) in entry.value) {
        for (final (episodeIndex, episode) in season.episodes.indexed) {
          final key = _episodeKey(episode.name, episodeIndex);
          final variant = EpisodeVariant(
            season: season,
            episode: episode,
            quality: episodeQuality(season.name, episode.name),
          );
          episodeBuckets.putIfAbsent(key, () => []).add((
            episodeIndex,
            variant,
          ));
        }
      }
      final groups = <EpisodeGroup>[];
      for (final bucket in episodeBuckets.entries) {
        final variants = _uniqueVariants(bucket.value.map((item) => item.$2));
        allVariants.addAll(variants);
        final first = variants.first;
        final isTrailerGroup =
            bucket.key.startsWith('trailer-') ||
            entry.key == 'trailer' ||
            isTrailerLabel(first.episode.name);
        groups.add(
          EpisodeGroup(
            id: 'logical:${entry.key}:${bucket.key}',
            name: isTrailerGroup
                ? first.episode.name
                : episodeDisplayName(first.episode.name),
            variants: variants,
          ),
        );
      }
      groups.sort((a, b) => _naturalCompare(a.name, b.name));
      groupedSeasons.add(
        EpisodeSeasonGroup(
          id: entry.key,
          name: _seasonDisplayName(entry.key, entry.value.first.$2.name),
          episodes: groups,
        ),
      );
    }
    groupedSeasons.sort((a, b) => _naturalCompare(a.name, b.name));
    return EpisodeCatalog(
      seasons: groupedSeasons,
      qualities: _qualityList(allVariants),
    );
  }
}

/// نام نمایشی یک قسمت سریال: رکوردهای قدیمی API گاهی فقط عددند («3»)
/// یا پیشوند ستاره دارند («*4»)؛ همه به «قسمت N» یکدست می‌شوند.
/// نام‌هایی که از قبل «قسمت» دارند یا توصیفی‌اند دست نخورده می‌مانند.
/// فقط برای نمایش است و شناسه/آدرس فایل را تغییر نمی‌دهد.
String episodeDisplayName(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty) return 'قسمت';
  if (isTrailerLabel(name)) return name;
  final bare =
      RegExp(r'^\*\s*([0-9۰-۹٠-٩]+)\s*$').firstMatch(name) ??
      RegExp(r'^([0-9۰-۹٠-٩]+)\s*$').firstMatch(name);
  if (bare != null) return 'قسمت ${bare.group(1)}';
  return name;
}

String episodeQuality(String seasonName, String episodeName) {
  final value = _latinDigits('$seasonName $episodeName');
  final pixels = RegExp(
    r'(?<!\d)(\d{3,4})\s*[pP](?!\w)',
  ).firstMatch(value)?.group(1);
  if (pixels != null) return '${int.parse(pixels)}p';
  if (RegExp(r'\b(4k|uhd)\b', caseSensitive: false).hasMatch(value)) {
    return '4K';
  }
  if (RegExp(r'\bfhd\b', caseSensitive: false).hasMatch(value)) return '1080p';
  if (RegExp(r'\bhd\b', caseSensitive: false).hasMatch(value)) return '720p';
  if (RegExp(r'\bsd\b', caseSensitive: false).hasMatch(value)) return '480p';
  return unknownQualityLabel;
}

String recommendedEpisodeQuality(Iterable<String> qualities) {
  final values = qualities.toList(growable: false);
  if (values.contains('720p')) return '720p';
  return values.isEmpty ? unknownQualityLabel : values.first;
}

/// یک بستهٔ دانلودی: چند قسمت/فایل هم‌کیفیت که با یک دکمه یکجا دانلود می‌شوند.
class QualityDownloadBatch {
  const QualityDownloadBatch({
    required this.label,
    required this.season,
    required this.episodes,
  });

  /// متن دکمه (مثلاً «فصل 1 · 720p · دانلود همه 12 قسمت»).
  final String label;

  /// فصل مصنوعی برای نام پوشه/فایل و شناسهٔ یکتای دانلود.
  final AnimeSeason season;
  final List<AnimeEpisode> episodes;
}

/// نقشهٔ دکمه‌های تب دانلود برای محتوای عادی (غیر هنتای).
class NormalDownloadPlan {
  const NormalDownloadPlan({
    required this.isMovie,
    this.movieAll,
    required this.batches,
  });

  final bool isMovie;

  /// دکمهٔ «دانلود همه کیفیت‌ها» (فقط فیلم).
  final QualityDownloadBatch? movieAll;
  final List<QualityDownloadBatch> batches;
}

List<AnimeEpisode> _distinctEpisodes(Iterable<AnimeEpisode> input) {
  final seen = <String>{};
  return [
    for (final episode in input)
      if (episode.fileUrl.isNotEmpty && seen.add(episode.fileUrl)) episode,
  ];
}

/// دکمه‌های دانلود تب «قسمت‌ها و دانلود» برای محتوای عادی:
/// - فیلم: «دانلود همه کیفیت‌ها» + تک‌تک کیفیت‌ها.
/// - سریال/انیمه: برای هر فصل، همهٔ قسمت‌های هر کیفیت جداگانه
///   (بدون قاطی کردن چند کیفیت باهم)؛ تیزرها کنار گذاشته می‌شوند.
NormalDownloadPlan normalDownloadPlan(AnimeContent content) {
  final catalog = EpisodeCatalog.from(content);
  final isMovie =
      content.kind == ContentKind.movie &&
      catalog.seasons.length == 1 &&
      catalog.seasons.first.id == 'movie';
  if (isMovie) {
    final season = catalog.seasons.first;
    final main = season.episodes.firstWhere(
      (group) => group.id == 'logical:movie:main',
      orElse: () => season.episodes.first,
    );
    final mains = main.variants
        .where(
          (variant) =>
              !isTrailerLabel(variant.episode.name) &&
              !isTrailerLabel(variant.season.name),
        )
        .toList(growable: false);
    if (mains.isEmpty) return const NormalDownloadPlan(isMovie: true, batches: []);
    final qualities = _qualityList(mains);
    if (qualities.every(isUnknownQuality)) {
      final episodes = _distinctEpisodes(mains.map((item) => item.episode));
      return NormalDownloadPlan(
        isMovie: true,
        batches: [
          QualityDownloadBatch(
            label: 'دانلود فیلم',
            season: AnimeSeason(
              id: 'movie-all',
              name: 'کیفیت‌های پخش',
              episodes: episodes,
            ),
            episodes: episodes,
          ),
        ],
      );
    }
    final known = qualities
        .where((quality) => !isUnknownQuality(quality))
        .toList(growable: false);
    final effective = known.isEmpty ? qualities : known;
    return NormalDownloadPlan(
      isMovie: true,
      movieAll: QualityDownloadBatch(
        label: 'دانلود همه ${mains.length} کیفیت',
        season: AnimeSeason(
          id: 'movie-all',
          name: 'کیفیت‌های پخش',
          episodes: _distinctEpisodes(mains.map((item) => item.episode)),
        ),
        episodes: _distinctEpisodes(mains.map((item) => item.episode)),
      ),
      batches: [
        for (final quality in effective)
          for (final variant in mains.where(
            (item) => item.quality == quality,
          ))
            QualityDownloadBatch(
              label: 'دانلود کیفیت ${qualityDisplayLabel(quality)}',
              season: AnimeSeason(
                id: 'movie-$quality',
                name: 'کیفیت‌های پخش · $quality',
                episodes: [variant.episode],
              ),
              episodes: [variant.episode],
            ),
      ],
    );
  }

  final batches = <QualityDownloadBatch>[];
  for (final season in catalog.seasons) {
    if (season.isTrailerSeason) continue;
    final groups = season.episodes
        .where((group) => !group.isTrailer)
        .toList(growable: false);
    if (groups.isEmpty) continue;
    final qualities = season.displayQualities;
    if (qualities.isEmpty) {
      final episodes = _distinctEpisodes(
        groups.expand((group) => group.variants.map((item) => item.episode)),
      );
      if (episodes.isEmpty) continue;
      batches.add(
        QualityDownloadBatch(
          label: '${season.name} · دانلود همه ${episodes.length} قسمت',
          season: AnimeSeason(
            id: '${season.id}-all',
            name: season.name,
            episodes: episodes,
          ),
          episodes: episodes,
        ),
      );
      continue;
    }
    for (final quality in qualities) {
      final episodes = _distinctEpisodes([
        for (final group in groups)
          if (group.variants.any((item) => item.quality == quality))
            group.variantFor(quality).episode,
      ]);
      if (episodes.isEmpty) continue;
      batches.add(
        QualityDownloadBatch(
          label:
              '${season.name} · ${qualityDisplayLabel(quality)} · دانلود همه ${episodes.length} قسمت',
          season: AnimeSeason(
            id: '${season.id}-$quality',
            name: '${season.name} · $quality',
            episodes: episodes,
          ),
          episodes: episodes,
        ),
      );
    }
  }
  return NormalDownloadPlan(isMovie: false, batches: batches);
}

List<EpisodeVariant> _uniqueVariants(Iterable<EpisodeVariant> input) {
  final values = <EpisodeVariant>[];
  final counts = <String, int>{};
  for (final variant in input) {
    if (values.any((item) => item.episode.fileUrl == variant.episode.fileUrl)) {
      continue;
    }
    final count = (counts[variant.quality] ?? 0) + 1;
    counts[variant.quality] = count;
    values.add(
      count == 1
          ? variant
          : EpisodeVariant(
              season: variant.season,
              episode: variant.episode,
              quality: '${variant.quality} · سرور $count',
            ),
    );
  }
  values.sort((a, b) {
    final rank = _qualityRank(b.quality).compareTo(_qualityRank(a.quality));
    return rank != 0 ? rank : a.quality.compareTo(b.quality);
  });
  return List.unmodifiable(values);
}

List<String> _qualityList(Iterable<EpisodeVariant> variants) {
  final result = variants.map((item) => item.quality).toSet().toList()
    ..sort((a, b) {
      final rank = _qualityRank(b).compareTo(_qualityRank(a));
      return rank != 0 ? rank : a.compareTo(b);
    });
  return List.unmodifiable(result);
}

int _qualityRank(String value) {
  if (value.toLowerCase().contains('4k')) return 2160;
  return int.tryParse(RegExp(r'\d{3,4}').firstMatch(value)?.group(0) ?? '') ??
      0;
}

String _seasonKey(String input, int fallbackIndex) {
  var value = _latinDigits(input).toLowerCase();
  if (isTrailerLabel(value)) return 'trailer';
  value = value.replaceAll(RegExp(r'\d{3,4}\s*p\b'), ' ');
  final number = RegExp(r'\d+').firstMatch(value)?.group(0);
  if (number != null) return 'season-${int.parse(number)}';
  value = value
      .replaceAll(RegExp(r'فصل|season|زیرنویس|دوبله|فارسی|اختصاصی'), ' ')
      .replaceAll(RegExp(r'[^a-z\u0600-\u06ff]+'), ' ')
      .trim();
  return value.isEmpty ? 'season-${fallbackIndex + 1}' : 'season-$value';
}

String _episodeKey(String input, int fallbackIndex) {
  final value = _latinDigits(input).toLowerCase();
  if (isTrailerLabel(value)) {
    return 'trailer-${fallbackIndex + 1}';
  }
  final number = RegExp(r'\d+').firstMatch(value)?.group(0);
  if (number != null) return 'episode-${int.parse(number)}';
  final text = value
      .replaceAll(RegExp(r'قسمت|episode|part'), ' ')
      .replaceAll(RegExp(r'[^a-z\u0600-\u06ff]+'), ' ')
      .trim();
  return text.isEmpty ? 'episode-${fallbackIndex + 1}' : 'episode-$text';
}

String _seasonDisplayName(String key, String original) {
  if (key == 'trailer') return 'تیزرها';
  final number = RegExp(r'^season-(\d+)$').firstMatch(key)?.group(1);
  if (number != null) return 'فصل $number';
  final cleaned = original
      .replaceAll(RegExp(r'\d{3,4}\s*[pP]\b'), ' ')
      .replaceAll(RegExp(r'زیرنویس|دوبله|فارسی|اختصاصی'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? 'فصل' : cleaned;
}

String _latinDigits(String value) {
  const source = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';
  var result = value;
  for (var index = 0; index < source.length; index++) {
    result = result.replaceAll(source[index], '${index % 10}');
  }
  return result;
}

int _naturalCompare(String left, String right) {
  final leftNumbers = RegExp(r'\d+')
      .allMatches(_latinDigits(left))
      .map((match) => int.parse(match.group(0)!))
      .toList();
  final rightNumbers = RegExp(r'\d+')
      .allMatches(_latinDigits(right))
      .map((match) => int.parse(match.group(0)!))
      .toList();
  for (var i = 0; i < leftNumbers.length && i < rightNumbers.length; i++) {
    final result = leftNumbers[i].compareTo(rightNumbers[i]);
    if (result != 0) return result;
  }
  return left.toLowerCase().compareTo(right.toLowerCase());
}
