import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/core/episode_catalog.dart';
import 'package:mbnime/models/anime_content.dart';

void main() {
  test('quality seasons collapse into logical seasons and episodes', () {
    const content = AnimeContent(
      id: 'show',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [Colors.black],
      genres: [],
      seasons: [
        AnimeSeason(
          id: 'a',
          name: '1 480p زیرنویس',
          episodes: [
            AnimeEpisode(id: '1a', name: '*1', fileUrl: '480-1'),
            AnimeEpisode(id: '2a', name: '*2', fileUrl: '480-2'),
          ],
        ),
        AnimeSeason(
          id: 'b',
          name: '۱ 720P زیرنویس',
          episodes: [
            AnimeEpisode(id: '1b', name: '*۱', fileUrl: '720-1'),
            AnimeEpisode(id: '2b', name: '*۲', fileUrl: '720-2'),
          ],
        ),
        AnimeSeason(
          id: 'c',
          name: '1 1080p زیرنویس',
          episodes: [
            AnimeEpisode(id: '1c', name: '*1', fileUrl: '1080-1'),
            AnimeEpisode(id: '2c', name: '*2', fileUrl: '1080-2'),
          ],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    expect(catalog.seasons, hasLength(1));
    expect(catalog.seasons.single.name, 'فصل 1');
    expect(catalog.seasons.single.episodes, hasLength(2));
    expect(catalog.seasons.single.episodes.first.variants, hasLength(3));
    expect(catalog.qualities, ['1080p', '720p', '480p']);
    expect(recommendedEpisodeQuality(catalog.qualities), '720p');
    expect(
      catalog.seasons.single.episodes.first.variantFor('1080p').episode.fileUrl,
      '1080-1',
    );
  });

  test('movie qualities become one playable movie', () {
    const content = AnimeContent(
      id: 'movie',
      title: 'Movie',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.movie,
      colors: [],
      genres: [],
      seasons: [
        AnimeSeason(
          id: 'movie',
          name: 'کیفیت‌های پخش',
          episodes: [
            AnimeEpisode(id: '1', name: '720P', fileUrl: 'movie-720'),
            AnimeEpisode(id: '2', name: '1080P', fileUrl: 'movie-1080'),
          ],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    expect(catalog.episodes, hasLength(1));
    expect(catalog.episodes.single.variants, hasLength(2));
  });

  test('trailer without a quality label does not pollute season qualities', () {
    const content = AnimeContent(
      id: 'show-with-trailer',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        AnimeSeason(
          id: 'trailer',
          name: 'تیزر',
          episodes: [AnimeEpisode(id: 't1', name: 'تیزر', fileUrl: 'trailer')],
        ),
        AnimeSeason(
          id: '720',
          name: 'فصل 1 زیرنویس 720p',
          episodes: [AnimeEpisode(id: 'e1', name: 'قسمت 1', fileUrl: '720-1')],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    final season = catalog.seasons.singleWhere((item) => item.name == 'فصل 1');
    expect(season.qualities, ['720p']);
    expect(
      catalog.seasons.singleWhere((item) => item.name == 'تیزرها').qualities,
      ['بدون برچسب کیفیت'],
    );
  });

  test('trailer season hides the unknown quality chip', () {
    const content = AnimeContent(
      id: 'show-with-trailer',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        AnimeSeason(
          id: 'trailer',
          name: 'تیزر',
          episodes: [AnimeEpisode(id: 't1', name: 'تیزر', fileUrl: 'trailer')],
        ),
        AnimeSeason(
          id: '720',
          name: 'فصل 1 زیرنویس 720p',
          episodes: [AnimeEpisode(id: 'e1', name: 'قسمت 1', fileUrl: '720-1')],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    final trailerSeason = catalog.seasons.singleWhere(
      (item) => item.name == 'تیزرها',
    );
    expect(trailerSeason.isTrailerSeason, isTrue);
    // به‌جای نمایش «بدون برچسب کیفیت»، ردیف کیفیت مخفی می‌شود.
    expect(trailerSeason.displayQualities, isEmpty);
    final trailerGroup = trailerSeason.episodes.single;
    expect(trailerGroup.isTrailer, isTrue);
    expect(isUnknownQuality(trailerGroup.variants.single.quality), isTrue);
  });

  test('movie trailer does not pollute the movie quality list', () {
    const content = AnimeContent(
      id: 'movie-with-trailer',
      title: 'Movie',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.movie,
      colors: [],
      genres: [],
      seasons: [
        AnimeSeason(
          id: 'movie',
          name: 'کیفیت‌های پخش',
          episodes: [
            AnimeEpisode(id: '1', name: '720P', fileUrl: 'movie-720'),
            AnimeEpisode(id: '2', name: '1080P', fileUrl: 'movie-1080'),
            AnimeEpisode(id: '3', name: '480p', fileUrl: 'movie-480'),
            AnimeEpisode(id: 't', name: 'تیزر', fileUrl: 'movie-trailer'),
          ],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    final season = catalog.seasons.single;
    expect(season.name, 'فیلم');
    // چیپ «بدون برچسب کیفیت» نباید بین کیفیت‌های فیلم دیده شود.
    expect(season.displayQualities, ['1080p', '720p', '480p']);
    expect(catalog.qualities, ['1080p', '720p', '480p']);
    expect(season.episodes, hasLength(2));
    final main = season.episodes.firstWhere(
      (group) => group.id == 'logical:movie:main',
    );
    expect(main.name, 'پخش فیلم');
    expect(main.variants, hasLength(3));
    final trailer = season.episodes.firstWhere((group) => group.isTrailer);
    expect(trailer.variants, hasLength(1));
    expect(isUnknownQuality(trailer.variants.single.quality), isTrue);
  });

  test('movie download plan lists all-qualities plus each quality', () {
    const content = AnimeContent(
      id: 'movie-dl',
      title: 'Movie',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.movie,
      colors: [],
      genres: [],
      seasons: [
        AnimeSeason(
          id: 'movie',
          name: 'کیفیت‌های پخش',
          episodes: [
            AnimeEpisode(id: '1', name: '720P', fileUrl: 'movie-720'),
            AnimeEpisode(id: '2', name: '1080P', fileUrl: 'movie-1080'),
            AnimeEpisode(id: 't', name: 'تیزر', fileUrl: 'movie-trailer'),
          ],
        ),
      ],
    );

    final plan = normalDownloadPlan(content);
    expect(plan.isMovie, isTrue);
    expect(plan.movieAll, isNotNull);
    expect(plan.movieAll!.label, 'دانلود همه 2 کیفیت');
    expect(plan.movieAll!.episodes, hasLength(2));
    expect(
      plan.batches.map((batch) => batch.label),
      ['دانلود کیفیت 1080p', 'دانلود کیفیت 720p'],
    );
    for (final batch in plan.batches) {
      expect(batch.episodes, hasLength(1));
      expect(batch.episodes.single.fileUrl, isNot('movie-trailer'));
    }
  });

  test('series download plan batches every episode of each quality', () {
    const content = AnimeContent(
      id: 'show-dl',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        AnimeSeason(
          id: 'a',
          name: '1 480p زیرنویس',
          episodes: [
            AnimeEpisode(id: '1a', name: '*1', fileUrl: '480-1'),
            AnimeEpisode(id: '2a', name: '*2', fileUrl: '480-2'),
          ],
        ),
        AnimeSeason(
          id: 'b',
          name: '۱ 720P زیرنویس',
          episodes: [
            AnimeEpisode(id: '1b', name: '*۱', fileUrl: '720-1'),
            AnimeEpisode(id: '2b', name: '*۲', fileUrl: '720-2'),
          ],
        ),
      ],
    );

    final plan = normalDownloadPlan(content);
    expect(plan.isMovie, isFalse);
    expect(plan.movieAll, isNull);
    // هر کیفیت جداگانه با همهٔ قسمت‌هایش؛ بدون بستهٔ چندکیفیتی.
    expect(plan.batches, hasLength(2));
    final byLabel = {for (final batch in plan.batches) batch.label: batch};
    expect(byLabel.keys.any((label) => label.contains('720p')), isTrue);
    expect(byLabel.keys.any((label) => label.contains('480p')), isTrue);
    for (final batch in plan.batches) {
      expect(batch.episodes, hasLength(2));
    }
  });

  test('bare and starred episode numbers display as قسمت N', () {
    // قالب واقعی API پسوند ستاره است («4*») که در رابط راست‌به‌چپ «*4»
    // دیده می‌شود؛ هر دو جهت پشتیبانی می‌شود.
    const content = AnimeContent(
      id: 'starred',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        AnimeSeason(
          id: 's1080',
          name: 'فصل 1 زیرنویس 1080p',
          episodes: [
            AnimeEpisode(id: 'e3', name: '3', fileUrl: 'u3'),
            AnimeEpisode(id: 'e4', name: '4*', fileUrl: 'u4'),
            AnimeEpisode(id: 'e5', name: '*5', fileUrl: 'u5'),
            AnimeEpisode(id: 'e6', name: 'قسمت 6', fileUrl: 'u6'),
            AnimeEpisode(id: 'e7', name: 'قسمت اول', fileUrl: 'u7'),
          ],
        ),
      ],
    );

    expect(episodeDisplayName('3'), 'قسمت 3');
    expect(episodeDisplayName('4*'), 'قسمت 4');
    expect(episodeDisplayName('*5'), 'قسمت 5');
    expect(episodeDisplayName('* 5'), 'قسمت 5');
    expect(episodeDisplayName('قسمت 6'), 'قسمت 6');
    expect(episodeDisplayName('قسمت اول'), 'قسمت اول');
    expect(episodeDisplayName('تیزر'), 'تیزر');
    expect(episodeDisplayName('  '), 'قسمت');

    final catalog = EpisodeCatalog.from(content);
    final names = catalog.seasons.single.episodes
        .map((group) => group.name)
        .toSet();
    expect(names, {'قسمت 3', 'قسمت 4', 'قسمت 5', 'قسمت 6', 'قسمت اول'});
    // ستاره هیچ‌جا در نام نمایشی نمی‌ماند.
    expect(names.any((name) => name.contains('*')), isFalse);
  });

  test('trailer helpers detect fa/en labels and server suffixes', () {
    expect(isTrailerLabel('تیزر'), isTrue);
    expect(isTrailerLabel('Trailer EP1'), isTrue);
    expect(isTrailerLabel('قسمت 1'), isFalse);
    expect(isUnknownQuality('بدون برچسب کیفیت'), isTrue);
    expect(isUnknownQuality('بدون برچسب کیفیت · سرور 2'), isTrue);
    expect(isUnknownQuality('720p'), isFalse);
    expect(qualityDisplayLabel('بدون برچسب کیفیت'), 'پخش');
    expect(
      qualityDisplayLabel('بدون برچسب کیفیت · سرور 2'),
      'سرور 2',
    );
  });
}
