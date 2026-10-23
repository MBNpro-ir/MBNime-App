import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SourceClient, SourceUnavailable, parseEpisodes } from '../src/source.mjs';
import worker, { SourceGateway } from '../src/worker.mjs';

const link = (url, label) => {
  const sig = Buffer.from(JSON.stringify({ url })).toString('base64url') + '.signature';
  return `<a href="/?hi_route=go&amp;sig=${sig}">${label}</a>`;
};
const page = (number, url = 'https://cdn.example/720.mp4') =>
  `<section><h3>قسمت ${number}</h3>${link(url, 'دانلود 720P')}</section>`;
const response = (html, headers) => new Response(html, { headers });

test('default fetch keeps the global receiver required by the Workers runtime', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = function () {
    assert.equal(this, globalThis);
    return Promise.resolve(response('ok'));
  };
  try {
    const client = new SourceClient({});
    assert.equal(await client.request('/', { deadline: Date.now() + 1000 }), 'ok');
  } finally { globalThis.fetch = original; }
});

test('episodes preserve Unicode numbers, episode grouping, download preference and URL safety', () => {
  const html = '<section>قسمت ۱' + link('https://cdn.example/play720.mp4', 'پخش 720P') +
    link('https://cdn.example/download720.mp4', 'دانلود 720P') + '</section>' +
    '<section>قسمت ٢' + link('https://cdn.example/2.mp4', '1080P') +
    link('http://cdn.example/unsafe.mp4', '480P') +
    link('https://user:password@cdn.example/private.mp4', '360P') + '</section>';
  assert.deepEqual(parseEpisodes(html), [
    { episode: 1, quality: '720p', download_url: 'https://cdn.example/download720.mp4' },
    { episode: 2, quality: '1080p', download_url: 'https://cdn.example/2.mp4' },
  ]);
  assert.deepEqual(parseEpisodes(link('https://cdn.example/720.mp4', '720P')), []);
});

test('malformed links do not hide valid links or forward off-origin route payloads', () => {
  const html = '<a href="/?hi_route=go&sig=bad">720p</a>' + page(3);
  assert.equal(parseEpisodes(html)[0].episode, 3);
  assert.deepEqual(parseEpisodes(page(1).replace('href="/', 'href="https://other.example/')), []);
});

test('login sends credentials only to the official HTTPS origin, with source test cookie', async () => {
  const calls = [];
  const client = new SourceClient({ username: 'user', password: 'private', fetchImpl: async (url, options) => {
    calls.push({ url, ...options });
    if (url.endsWith('/wp-login.php') && options.method === 'GET') {
      return response('', { 'Set-Cookie': 'wordpress_test_cookie=test; Secure; HttpOnly' });
    }
    if (options.method === 'POST') {
      return response('', { 'Set-Cookie': 'wordpress_logged_in_hash=session; Secure; HttpOnly' });
    }
    return response(page(1));
  } });
  const rows = await client.episodes(42);
  assert.equal(rows.length, 1);
  assert.equal(calls.length, 3);
  assert.equal(new URLSearchParams(calls[1].body).get('pwd'), 'private');
  assert.match(calls[1].headers.Cookie, /wordpress_test_cookie=test/);
  assert.match(calls[2].headers.Cookie, /wordpress_logged_in_hash=session/);
  assert.ok(calls.every(call => new URL(call.url).origin === 'https://hentaiiran.com'));
});

test('redirects cannot forward source cookies or password to another host', async () => {
  let calls = 0;
  const client = new SourceClient({ username: 'user', password: 'private', fetchImpl: async () => {
    calls++;
    return new Response('', { status: 307, headers: { Location: 'https://other.example/login' } });
  } });
  await assert.rejects(client.episodes(42), SourceUnavailable);
  assert.equal(calls, 1);
});

test('subsequent reads fetch a new episode immediately and concurrent login happens only once', async () => {
  let logins = 0, current = 1;
  const client = new SourceClient({ username: 'user', password: 'private', fetchImpl: async (url, options) => {
    if (url.endsWith('/wp-login.php')) {
      if (options.method === 'POST') logins++;
      return response('', options.method === 'POST' ? { 'Set-Cookie': 'wordpress_logged_in_hash=session' } : {});
    }
    return response(page(current));
  } });
  const first = await Promise.all([client.episodes(42), client.episodes(43)]);
  assert.equal(logins, 1);
  assert.equal(first[0][0].episode, 1);
  current = 2;
  assert.equal((await client.episodes(42))[0].episode, 2);
  assert.equal(logins, 1);
});

test('login failure cools down requests and does not return partial pages as episode data', async () => {
  let calls = 0;
  const client = new SourceClient({ username: 'user', password: 'private', fetchImpl: async () => {
    calls++;
    return response('login required');
  } });
  await assert.rejects(client.episodes(42), SourceUnavailable);
  await assert.rejects(client.episodes(43), SourceUnavailable);
  assert.equal(calls, 2);
});

test('oversized source bodies are rejected instead of buffering unbounded HTML', async () => {
  const client = new SourceClient({ fetchImpl: async () => response('x', { 'Content-Length': String(3 * 1024 * 1024) }) });
  await assert.rejects(client.request('/', { deadline: Date.now() + 1000 }), SourceUnavailable);
});

const gateway = () => new SourceGateway({}, { SOURCE_USERNAME: 'user', SOURCE_PASSWORD: 'private' });
const request = (id = 42, ip = 'test') => new Request(`https://gateway.example/v1/titles/${id}`, { headers: { 'X-Client-IP': ip } });

test('gateway coalesces only active reads; a later request always gets new source data', async () => {
  const service = gateway();
  let release, calls = 0;
  service.source.episodes = async () => { calls++; await new Promise(resolve => { release = resolve; }); return [{ episode: calls }]; };
  const one = service.fetch(request()), two = service.fetch(request());
  release();
  const [a, b] = await Promise.all([one, two]);
  assert.equal(calls, 1);
  assert.deepEqual((await a.json()).episodes, (await b.json()).episodes);
  const three = service.fetch(request());
  release();
  assert.equal((await (await three).json()).episodes[0].episode, 2);
});

test('gateway bounds concurrency, queued work and per-client request rate', async () => {
  const service = gateway(), releases = [];
  service.source.episodes = async () => { await new Promise(resolve => releases.push(resolve)); return [{ episode: 1 }]; };
  const pending = Array.from({ length: 15 }, (_, i) => service.fetch(request(i + 1)));
  assert.equal(service.active, 3);
  assert.equal(service.waiting.length, 12);
  assert.equal((await service.fetch(request(16))).status, 503);
  for (let i = 0; i < 15; i++) { releases[i](); await new Promise(resolve => setImmediate(resolve)); }
  await Promise.all(pending);
  assert.equal(service.active, 0);
  service.source.episodes = async () => [];
  for (let i = 0; i < 30; i++) await service.fetch(request(42, 'other'));
  assert.equal((await service.fetch(request(42, 'other'))).status, 429);
});

test('source errors are sanitized without credentials, HTML or cookie details', async () => {
  const service = gateway();
  service.source.episodes = async () => { throw new Error('private wordpress_logged_in token'); };
  const result = await service.fetch(request());
  assert.equal(result.status, 503);
  assert.equal(await result.text(), '{"error":"source_unavailable"}');
  assert.equal(result.headers.get('Cache-Control'), 'no-store');
});

test('authorized worker supports approved web/native requests and never proxies arbitrary paths or methods', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ allowed: true }));
  let calls = 0;
  const env = { ALLOWED_ORIGINS: 'https://anime.mbnpro.ir', SOURCE_SESSION: {
    idFromName: () => 'one', get: () => ({ fetch: async () => { calls++; return Response.json({ id: 42, episodes: [] }); } }),
  } };
  const webRequest = (origin, method = 'GET', path = '/v1/titles/42') => new Request(`https://gateway.example${path}`, {
    method, headers: { Authorization: 'Bearer account-token', ...(origin ? { Origin: origin } : {}) },
  });
  const web = await worker.fetch(webRequest('https://anime.mbnpro.ir'), env);
  assert.equal(web.status, 200);
  assert.equal(web.headers.get('Access-Control-Allow-Origin'), 'https://anime.mbnpro.ir');
  assert.equal((await worker.fetch(webRequest(null), env)).status, 200);
  assert.equal((await worker.fetch(webRequest('https://other.example'), env)).status, 403);
  assert.equal((await worker.fetch(webRequest('https://anime.mbnpro.ir', 'OPTIONS'), env)).status, 204);
  assert.equal((await worker.fetch(webRequest(null, 'POST'), env)).status, 405);
  for (const path of ['/v1/titles/0', '/v1/titles/2147483648', '/v1/titles/42/url', '/wp-login.php']) {
    assert.equal((await worker.fetch(webRequest(null, 'GET', path), env)).status, 404);
  }
  assert.equal(calls, 2);
});

test('permission defaults off, is checked on every read, and fails closed before source access', async (t) => {
  let allowed = false, upstream = 0, checks = 0;
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    checks++;
    assert.equal(url, 'https://login.a.mbnpro.ir/api/anime/adult-access');
    assert.equal(options.headers.Authorization, 'Bearer account-token');
    assert.equal(options.redirect, 'manual');
    if (allowed === 'offline') throw new Error('network down');
    if (allowed === 'revoked') return new Response('', { status: 401 });
    return Response.json({ allowed });
  });
  const env = { SOURCE_SESSION: { idFromName: () => 'one', get: () => ({ fetch: async () => { upstream++; return Response.json({ episodes: [] }); } }) } };
  const request = (token = 'account-token') => new Request('https://gateway.example/v1/titles/42', { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  assert.equal((await worker.fetch(request(null), env)).status, 401);
  assert.equal(checks, 0);
  for (const [value, status] of [[false, 403], [true, 200], [false, 403], ['true', 403], ['offline', 503], ['revoked', 401]]) {
    allowed = value;
    const result = await worker.fetch(request(), env);
    assert.equal(result.status, status);
    assert.equal(result.headers.get('Cache-Control'), 'no-store');
  }
  assert.equal(checks, 6);
  assert.equal(upstream, 1);
});
