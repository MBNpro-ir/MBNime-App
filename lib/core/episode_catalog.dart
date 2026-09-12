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

class EpisodeGroup {
  const EpisodeGroup({
    required this.id,
    required this.name,
    required this.variants,
  });

  final String id;
  final String name;
  final List<EpisodeVariant> variants;

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
      final variants = _uniqueVariants(
        raw.episodes.map(
          (episode) => EpisodeVariant(
            season: raw,
            episode: episode,
            quality: episodeQuality(raw.name, episode.name),
          ),
        ),
      );
      return EpisodeCatalog(
        seasons: [
          EpisodeSeasonGroup(
            id: 'movie',
            name: 'فیلم',
            episodes: [
              EpisodeGroup(
                id: 'logical:movie:main',
                name: 'پخش فیلم',
                variants: variants,
              ),
            ],
          ),
        ],
        qualities: _qualityList(variants),
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
        groups.add(
          EpisodeGroup(
            id: 'logical:${entry.key}:${bucket.key}',
            name: variants.first.episode.name,
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
  return 'بدون برچسب کیفیت';
}

String recommendedEpisodeQuality(Iterable<String> qualities) {
  final values = qualities.toList(growable: false);
  if (values.contains('720p')) return '720p';
  return values.isEmpty ? 'بدون برچسب کیفیت' : values.first;
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
  if (RegExp(r'تیزر|trailer').hasMatch(value)) return 'trailer';
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
  if (RegExp(r'تیزر|trailer').hasMatch(value)) {
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
