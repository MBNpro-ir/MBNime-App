"""Export source-authenticated episode metadata for direct client access.

Run outside the account server. Only HTTPS media URLs and episode/quality
labels are published; cookies, login fields and account HTML stay in memory.
"""
import base64
import json
import re
import threading
import time
from collections import OrderedDict
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, parse_qs

import requests
import os

ORIGIN = 'https://hentaiiran.com'


class SourceUnavailable(Exception):
    pass


class _Node:
    def __init__(self, tag='', attrs=(), parent=None):
        self.tag, self.attrs, self.parent = tag, dict(attrs), parent
        self.children = []

    def text(self):
        return ' '.join(c.text() if isinstance(c, _Node) else c for c in self.children)


class _Page(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.root = self.current = _Node()
        self.links = []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        node = _Node(tag, attrs, self.current)
        self.current.children.append(node)
        if tag == 'a' and 'hi_route=go' in node.attrs.get('href', ''):
            self.links.append(node)
        if tag not in ('area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'):
            self.current = node

    def handle_endtag(self, tag):
        node = self.current
        while node.parent is not None:
            if node.tag == tag:
                self.current = node.parent
                return
            node = node.parent

    def handle_data(self, value):
        if self.current.tag not in ('script', 'style'):
            self.current.children.append(value)


def parse_episodes(source):
    result, seen = {}, set()
    digits = str.maketrans('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩', '01234567890123456789')
    for link in _Page(source).links:
        try:
            sig = parse_qs(urlsplit(link.attrs['href']).query)['sig'][0].split('.')[0]
            payload = json.loads(base64.urlsafe_b64decode(sig + '=' * (-len(sig) % 4)))
            target = payload['url']
            target = parse_qs(urlsplit(target).query).get('u', [target])[0]
            parts = urlsplit(target)
            if parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or parts.port not in (None, 443):
                continue
        except (KeyError, ValueError, TypeError, UnicodeError):
            continue
        if target in seen:
            continue
        label = (link.attrs.get('aria-label', '') + ' ' + link.text()).translate(digits)
        quality = re.search(r'(?i)(2160|1440|1080|720|480|360)[pP]?', label + ' ' + target)
        if not quality:
            continue
        node, number = link, None
        for _ in range(7):
            text = node.text().translate(digits)
            match = re.search(r'(?:قسمت|اپیزود|[Ee]pisode)\s*[:#-]?\s*(\d+)', text)
            if match:
                number = int(match[1])
                break
            if node.parent is None:
                break
            node = node.parent
        if number is None:
            continue  # Never silently assign a multi-episode title to episode 1.
        seen.add(target)
        key = (number, quality[1])
        if key not in result or 'پخش' not in label:
            result[key] = {'episode': number, 'quality': quality[1] + 'p', 'download_url': target}
    return list(result.values())


class HentaiSource:
    def __init__(self):
        self._lock = threading.Lock()
        self._session = None
        self._login_at = 0
        self._retry_at = 0
        self._cache = OrderedDict()

    @staticmethod
    def _request(session, url, *, data=None):
        # Only the official HTTPS origin may receive source cookies/passwords.
        for _ in range(5):
            if urlsplit(url).netloc != 'hentaiiran.com' or urlsplit(url).scheme != 'https':
                raise SourceUnavailable()
            response = session.request('POST' if data is not None else 'GET', url,
                data=data, timeout=(8, 15), allow_redirects=False, stream=True)
            try:
                if response.is_redirect:
                    url = urljoin(url, response.headers['Location'])
                    if response.status_code in (301, 302, 303):
                        data = None
                    continue
                response.raise_for_status()
                chunks, size = [], 0
                for chunk in response.iter_content(65536):
                    size += len(chunk)
                    if size > 2 * 1024 * 1024:
                        raise SourceUnavailable()
                    chunks.append(chunk)
                return b''.join(chunks).decode('utf-8', errors='replace')
            finally:
                response.close()
        raise SourceUnavailable()

    def _login(self):
        username, password = os.environ.get('HENTAI_SOURCE_USERNAME', ''), os.environ.get('HENTAI_SOURCE_PASSWORD', '')
        if not username or not password:
            raise SourceUnavailable()
        if self._session is not None:
            self._session.close()
        session = self._session = requests.Session()
        session.headers['User-Agent'] = 'Mozilla/5.0 MBNime/1.0'
        self._request(session, ORIGIN + '/wp-login.php')
        self._request(session, ORIGIN + '/wp-login.php', data={
            'log': username, 'pwd': password, 'testcookie': '1', 'redirect_to': ORIGIN + '/'})
        if not any(c.name.startswith('wordpress_logged_in') for c in session.cookies):
            raise SourceUnavailable()
        self._login_at = time.monotonic()

    def episodes(self, title_id):
        if not isinstance(title_id, int) or not 0 < title_id < 2**31:
            raise ValueError('Invalid title id')
        if not self._lock.acquire(blocking=False):
            raise SourceUnavailable()
        try:
            now = time.monotonic()
            cached = self._cache.get(title_id)
            if cached and cached[0] > now:
                self._cache.move_to_end(title_id)
                return [dict(row) for row in cached[1]]
            if self._retry_at > now:
                raise SourceUnavailable()
            if self._session is None or now - self._login_at > 1800:
                self._login()
            page_url = ORIGIN + '/?post_type=anime&p=' + str(title_id)
            episodes = parse_episodes(self._request(self._session, page_url))
            if not episodes:
                # Expired WordPress cookies can yield a 200 login-gated page.
                # Refresh once, then cool down instead of a login retry storm.
                if now - self._login_at > 60:
                    self._login()
                    episodes = parse_episodes(self._request(self._session, page_url))
                if not episodes:
                    raise SourceUnavailable()
            self._cache[title_id] = (now + 300, episodes)
            while len(self._cache) > 256:
                self._cache.popitem(last=False)
            return [dict(row) for row in episodes]
        except (requests.RequestException, SourceUnavailable, OSError):
            self._retry_at = time.monotonic() + 30
            raise SourceUnavailable() from None
        finally:
            self._lock.release()


source = HentaiSource()


def export_catalog(output, *, ids=None, force=False):
    from concurrent.futures import ThreadPoolExecutor, as_completed
    from pathlib import Path
    import random
    output = Path(output)
    title_dir = output / 'v1' / 'titles'
    title_dir.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        try:
            source._login()
            break
        except requests.RequestException:
            if attempt == 2: raise
            time.sleep(2)
    rows, page = [], 1
    if ids:
        rows = [{'id': int(value), 'modified_gmt': ''} for value in ids]
    else:
        while True:
            batch = json.loads(source._request(source._session, ORIGIN +
                f'/wp-json/wp/v2/anime?per_page=100&page={page}&orderby=id&order=desc&_fields=id,modified_gmt'))
            if not isinstance(batch, list): raise SourceUnavailable()
            rows.extend(batch)
            if len(batch) < 100: break
            page += 1
    rows = list({int(row['id']): row for row in rows}.values())
    local = threading.local()
    def export(row):
        title_id, modified = int(row['id']), row['modified_gmt']
        path = title_dir / (str(title_id) + '.json')
        if path.exists() and not force:
            previous = json.loads(path.read_text())
            if previous.get('source_modified') == modified and previous.get('episodes'):
                return 'unchanged'
        if not hasattr(local, 'session'):
            local.session = requests.Session()
            local.session.headers.update(source._session.headers)
            local.session.cookies.update(source._session.cookies)
        for attempt in range(3):
            try:
                page = source._request(local.session, ORIGIN + '/?post_type=anime&p=' + str(title_id))
                episodes = parse_episodes(page)
                if not episodes:
                    print('No episode links for title', title_id, flush=True)
                    return 'empty'
                # This is a metadata snapshot, never a proxy or a cookie jar.
                payload = {'id': title_id, 'source_modified': modified, 'episodes': episodes}
                path.write_text(json.dumps(payload, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
                return 'updated'
            except (requests.RequestException, SourceUnavailable, ValueError, OSError):
                if attempt == 2: return 'failed'
                time.sleep(1 + random.random())
            finally:
                time.sleep(0.15)
    counts = dict(updated=0, unchanged=0, empty=0, failed=0)
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(export, row) for row in rows]
        for done in as_completed(futures):
            counts[done.result()] += 1
            total = sum(counts.values())
            if total % 50 == 0: print('Processed', total, counts, flush=True)
    print(json.dumps(counts), flush=True)
    if counts['failed'] or (not counts['updated'] and not counts['unchanged']):
        raise SourceUnavailable()
    manifest = {'version': 1, 'titles': len(list(title_dir.glob('*.json'))),
                'updated_at': int(time.time())}
    (output / 'v1' / 'index.json').write_text(json.dumps(manifest) + '\n')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--ids', nargs='*', type=int)
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    try:
        export_catalog(args.output, ids=args.ids, force=args.force)
    except (SourceUnavailable, requests.RequestException, ValueError, OSError):
        raise SystemExit('Source refresh failed; existing published links are retained.') from None
