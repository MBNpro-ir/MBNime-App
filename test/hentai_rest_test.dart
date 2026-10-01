import 'package:flutter_test/flutter_test.dart';
import 'package:mbnime/services/hentai_iran_api.dart';

void main() {
  test('public REST detail preserves episodes, qualities and safe HTTPS links', () {
    final content = HentaiIranApi.contentFromRest({
      'id': 42, 'title': 'Example &amp; title', 'year': '2025',
      'genres': [{'id': 1, 'name': 'Example'}],
      'episodes': [
        {'episode': 1, 'quality': '720p', 'download_url': 'https://cdn.example/1.mp4'},
        {'episode': 1, 'quality': '1080p', 'download_url': 'https://cdn.example/1-hd.mp4'},
        {'episode': 2, 'quality': '720p', 'download_url': 'https://cdn.example/2.mp4'},
        {'episode': 2, 'quality': '720p', 'download_url': 'https://cdn.example/2.mp4'},
        {'episode': 3, 'quality': '720p', 'download_url': 'javascript:alert(1)'},
      ],
      'similar_anime': [{'id': 43, 'title': 'Related', 'permalink': 'https://example/title/'}],
    });
    expect(content.title, 'Example & title');
    expect(content.year, 2025);
    expect(content.seasons.single.episodes, hasLength(3));
    expect(content.downloads, hasLength(3));
    expect(content.seasons.single.episodes[1].name, contains('1080p'));
    expect(content.related.single.id, '43');
    expect(content.related.single.seasons, isEmpty);
  });
}
