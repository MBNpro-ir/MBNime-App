import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/core/episode_catalog.dart';
import 'package:mbnime/models/anime_content.dart';

void main() {
  test(
    'resume restores raw episode identity, quality variants and next episode',
    () {
      final content = AnimeContent(
        id: 'title',
        title: 'Title',
        subtitle: '',
        description: '',
        year: 0,
        rating: 0,
        kind: ContentKind.series,
        colors: [],
        genres: [],
        seasons: [
          AnimeSeason(
            id: '480',
            name: 'Season 1 480p',
            episodes: [
              AnimeEpisode(
                id: 'raw1',
                name: '1',
                fileUrl: 'https://cdn/1-480.mp4',
              ),
              AnimeEpisode(
                id: 'raw2',
                name: '2',
                fileUrl: 'https://cdn/2-480.mp4',
              ),
            ],
          ),
          AnimeSeason(
            id: '720',
            name: 'Season 1 720p',
            episodes: [
              AnimeEpisode(
                id: 'hd1',
                name: '1',
                fileUrl: 'https://cdn/1-720.mp4',
              ),
              AnimeEpisode(
                id: 'hd2',
                name: '2',
                fileUrl: 'https://cdn/2-720.mp4',
              ),
            ],
          ),
        ],
      );
      final catalog = EpisodeCatalog.from(content);
      final group = catalog.episodes.first;
      final resumed = catalog.resumeVariant(
        episodeId: group.id,
        fileUrl: 'https://cdn/1-720.mp4',
      )!;
      expect(resumed.episode.id, 'hd1');
      expect(catalog.groupFor(resumed.episode)!.variants.length, 2);
      expect(catalog.episodes.length, 2);
      expect(
        catalog
            .resumeVariant(
              episodeId: group.id,
              fileUrl: 'https://expired/link',
              preferredQuality: '480p',
            )!
            .episode
            .id,
        'raw1',
      );
      expect(
        catalog.resumeVariant(
          episodeId: 'removed',
          fileUrl: 'https://missing/link',
        ),
        isNull,
      );
    },
  );
}
