import { SourceClient, SourceUnavailable } from './source.mjs';

const titleId = path => {
  const match = /^\/v1\/titles\/([1-9]\d{0,9})$/.exec(path);
  const id = Number(match?.[1]);
  return id > 0 && id < 2 ** 31 ? id : null;
};
const json = (body, status = 200) => Response.json(body, { status, headers: {
  'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
  'Content-Security-Policy': "default-src 'none'", ...(status === 503 || status === 429 ? { 'Retry-After': '20' } : {}),
} });

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin');
    const allowed = (env.ALLOWED_ORIGINS ?? '').split(',').map(x => x.trim());
    if (origin && !allowed.includes(origin)) return json({ error: 'origin_denied' }, 403);
    const cors = response => {
      const headers = new Headers(response.headers);
      headers.set('Vary', 'Origin');
      if (origin) headers.set('Access-Control-Allow-Origin', origin);
      return new Response(response.body, { status: response.status, headers });
    };
    if (!titleId(new URL(request.url).pathname)) return cors(json({ error: 'not_found' }, 404));
    if (request.method === 'OPTIONS') return cors(new Response(null, { status: 204, headers: {
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Accept',
      'Access-Control-Max-Age': '600',
    } }));
    if (request.method !== 'GET') return cors(json({ error: 'method_not_allowed' }, 405));
    try {
      // One source session; cookies/passwords never leave this object. Reads
      // are coalesced only while in flight, never served from a timed snapshot.
      const id = env.SOURCE_SESSION.idFromName('official-source');
      const stub = env.SOURCE_SESSION.get(id, { locationHint: 'weur' });
      return cors(await stub.fetch(new Request(request.url, { headers: {
        'X-Client-IP': request.headers.get('CF-Connecting-IP') ?? 'unknown',
      } })));
    } catch (error) {
      console.warn(JSON.stringify({ event: 'source_dispatch_failure', name: error.name }));
      return cors(json({ error: 'source_unavailable' }, 503));
    }
  },
};

export class SourceGateway {
  constructor(_state, env) {
    this.source = new SourceClient({ username: env.SOURCE_USERNAME, password: env.SOURCE_PASSWORD });
    this.inFlight = new Map();
    this.clients = new Map();
    this.active = 0;
    this.waiting = [];
  }

  async fetch(request) {
    const id = titleId(new URL(request.url).pathname);
    if (!id || request.method !== 'GET') return json({ error: 'not_found' }, 404);
    const ip = request.headers.get('X-Client-IP') ?? 'unknown', now = Date.now();
    const recent = this.clients.get(ip) ?? { start: now, count: 0 };
    if (now - recent.start > 60000) { recent.start = now; recent.count = 0; }
    if (++recent.count > 30) return json({ error: 'rate_limited' }, 429);
    if (!this.clients.has(ip) && this.clients.size >= 10000) this.clients.delete(this.clients.keys().next().value);
    this.clients.set(ip, recent);
    try {
      let pending = this.inFlight.get(id);
      if (!pending) {
        if (this.active >= 3 && this.waiting.length >= 12) return json({ error: 'busy' }, 503);
        pending = this.load(id).finally(() => this.inFlight.delete(id));
        this.inFlight.set(id, pending);
      }
      const episodes = await pending;
      return json({ id, episodes, fetched_at: new Date().toISOString(), source: 'live' });
    } catch (error) {
      // Diagnostic codes only; never log source bodies, URLs or exception text.
      const code = error instanceof SourceUnavailable && /^source_[a-z_0-9]+$/.test(error.message)
        ? error.message : 'source_transport_failure';
      console.warn(JSON.stringify({ event: 'source_failure', code, kind: error.name, phase: this.source.phase }));
      return json({ error: 'source_unavailable' }, 503);
    }
  }

  async load(id) {
    if (this.active >= 3) {
      await new Promise((resolve, reject) => {
        const item = { resolve, timer: null };
        item.timer = setTimeout(() => {
          const index = this.waiting.indexOf(item);
          if (index >= 0) this.waiting.splice(index, 1);
          reject(new Error('queue deadline'));
        }, 10000);
        this.waiting.push(item);
      });
    } else this.active++;
    try { return await this.source.episodes(id); }
    finally {
      const next = this.waiting.shift();
      if (next) { clearTimeout(next.timer); next.resolve(); }
      else this.active--;
    }
  }
}
