import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/core/download_paths.dart';
import 'package:mbnime/models/anime_content.dart';

void main() {
  test('safe Persian paths, no traversal or reserved Windows filenames', () {
    expect(safeDownloadComponent('فصل اول'), 'فصل اول');
    for (final text in ['..', '', 'CON', 'NUL.txt', 'a/b:c*?', 'name. ']) {
      final safe = safeDownloadComponent(text);
      expect(safe, isNotEmpty);
      expect(safe.contains('/'), isFalse);
      expect(safe.contains(':'), isFalse);
      expect(safe.endsWith('.'), isFalse);
      expect(safe, isNot('..'));
    }
    expect(safeDownloadComponent('CON'), '_CON');
  });
  test('quality/season identities do not overwrite each other', () {
    final first = downloadIdentity('movie', '720p', '1');
    final second = downloadIdentity('movie', '1080p', '1');
    expect(first, isNot(second));
    expect(first, downloadIdentity('movie', '720p', '1'));
    expect(
      episodeDownloadFilename(
        const AnimeEpisode(
          id: '1',
          name: 'قسمت/1',
          fileUrl: 'https://example.org/file.mkv?token=abc',
        ),
        first,
      ),
      endsWith('.mkv'),
    );
    expect(
      episodeDownloadFilename(
        const AnimeEpisode(
          id: '1',
          name: '1',
          fileUrl: 'https://example.org/',
          fileType: '../../bad',
        ),
        first,
      ),
      endsWith('.mp4'),
    );
  });
}
