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
}
