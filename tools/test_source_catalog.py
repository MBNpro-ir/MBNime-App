import base64
import json
import unittest
from unittest.mock import patch
import source_catalog as hentai_source


def link(url, label):
    sig = base64.urlsafe_b64encode(json.dumps({'url': url}).encode()).decode().rstrip('=') + '.signature'
    return f'<a href="/?hi_route=go&amp;sig={sig}">{label}</a>'


class SourceTest(unittest.TestCase):
    def test_multi_episode_unicode_digits_duplicate_quality_and_unsafe_links(self):
        page = '<section><h3>قسمت ۱</h3>' + link('https://cdn.example/play720.mp4', 'پخش 720P')
        page += link('https://cdn.example/720.mp4', '720P') + '</section>'
        page += '<section><h3>قسمت ۲</h3>' + link('https://cdn.example/2-1080.mp4', '1080P')
        page += link('https://user:password@cdn.example/leak.mp4', '480P')
        page += link('http://cdn.example/unsafe.mp4', '360P') + '</section>'
        result = hentai_source.parse_episodes(page)
        self.assertEqual([(x['episode'], x['quality']) for x in result], [(1, '720p'), (2, '1080p')])
        self.assertEqual(result[0]['download_url'], 'https://cdn.example/720.mp4')

    def test_cache_cooldown_and_nonblocking_capacity(self):
        source = hentai_source.HentaiSource()
        source._session = object()
        source._login_at = hentai_source.time.monotonic()
        page = '<section>قسمت 1' + link('https://cdn.example/720.mp4', '720p') + '</section>'
        with patch.object(source, '_request', return_value=page) as fetch:
            first = source.episodes(42)
            first[0]['download_url'] = 'mutated'
            self.assertEqual(source.episodes(42)[0]['download_url'], 'https://cdn.example/720.mp4')
            self.assertEqual(fetch.call_count, 1)
        source._lock.acquire()
        try:
            with self.assertRaises(hentai_source.SourceUnavailable): source.episodes(43)
        finally:
            source._lock.release()
        with patch.object(source, '_request', side_effect=hentai_source.requests.Timeout('private request')) as fetch:
            for _ in range(3):
                with self.assertRaises(hentai_source.SourceUnavailable): source.episodes(43)
            self.assertEqual(fetch.call_count, 1)

    def test_redirect_never_sends_credentials_to_other_host(self):
        from unittest.mock import Mock
        session = Mock()
        response = session.request.return_value
        response.is_redirect = True
        response.status_code = 307
        response.headers = {'Location': 'https://other.example/login'}
        with self.assertRaises(hentai_source.SourceUnavailable):
            hentai_source.HentaiSource._request(session, hentai_source.ORIGIN + '/wp-login.php', data={'pwd': 'secret'})
        self.assertEqual(session.request.call_count, 1)
        response.close.assert_called_once()



if __name__ == '__main__': unittest.main()
