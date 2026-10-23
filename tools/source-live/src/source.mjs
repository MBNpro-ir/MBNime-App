import { parseDocument, DomUtils } from 'htmlparser2';

const ORIGIN = 'https://hentaiiran.com';
const BODY_LIMIT = 2 * 1024 * 1024;
const digits = value => value.replace(/[۰-۹٠-٩]/g, c => String(c.charCodeAt(0) % 16));
const nodeText = node => node.type === 'text' ? node.data :
  ['script', 'style'].includes(node.name) ? '' : (node.children ?? []).map(nodeText).join(' ');

export class SourceUnavailable extends Error {}

// The signed links are read only from the official authenticated page. Never
// fetch caller-supplied URLs or return account HTML, cookies, or login tokens.
export function parseEpisodes(html) {
  const document = parseDocument(html);
  const links = DomUtils.findAll(node => node.name === 'a' &&
    (node.attribs.href ?? '').includes('hi_route=go'), document.children);
  const files = new Map();
  for (const link of links) {
    try {
      const href = new URL(link.attribs.href, ORIGIN);
      if (href.origin !== ORIGIN) continue;
      const encoded = (href.searchParams.get('sig') ?? '').split('.')[0];
      const binary = atob(encoded.replace(/-/g, '+').replace(/_/g, '/'));
      const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(binary, c => c.charCodeAt(0))));
      let target = new URL(payload.url);
      if (target.searchParams.has('u')) target = new URL(target.searchParams.get('u'));
      if (target.protocol !== 'https:' || target.username || target.password ||
          (target.port && target.port !== '443')) continue;
      const label = digits(`${link.attribs['aria-label'] ?? ''} ${nodeText(link)}`);
      const quality = /(?:2160|1440|1080|720|480|360)/.exec(`${label} ${target.href}`)?.[0];
      if (!quality) continue;
      let node = link, number;
      for (let depth = 0; node && depth < 7; node = node.parent, depth++) {
        const match = /(?:قسمت|اپیزود|episode)\s*[:#-]?\s*(\d+)/i.exec(digits(nodeText(node)));
        if (match) { number = Number(match[1]); break; }
      }
      if (!Number.isSafeInteger(number) || number < 1) continue;
      const key = `${number}:${quality}`;
      if (!files.has(key) || !label.includes('پخش')) {
        files.set(key, { episode: number, quality: `${quality}p`, download_url: target.href });
      }
    } catch { /* A malformed source link cannot invalidate other episodes. */ }
  }
  return [...files.values()].sort((a, b) => a.episode - b.episode ||
    Number(a.quality.slice(0, -1)) - Number(b.quality.slice(0, -1)));
}

export class SourceClient {
  constructor({ username, password, fetchImpl = globalThis.fetch.bind(globalThis), now = Date.now }) {
    this.username = username;
    this.password = password;
    this.fetchImpl = fetchImpl;
    this.now = now;
    this.cookies = new Map();
    this.loginAt = 0;
    this.loginPromise = null;
    this.retryAt = 0;
  }

  async request(path, { form, deadline } = {}) {
    let url = new URL(path, ORIGIN);
    for (let redirect = 0; redirect < 5; redirect++) {
      if (url.origin !== ORIGIN || url.username || url.password) throw new SourceUnavailable();
      const remaining = deadline - this.now();
      if (remaining <= 0) throw new SourceUnavailable();
      const headers = {
        'User-Agent': 'Mozilla/5.0 MBNime/1.0',
        'Cache-Control': 'no-cache',
        'Accept': 'text/html',
      };
      if (this.cookies.size) headers.Cookie = [...this.cookies].map(([k, v]) => `${k}=${v}`).join('; ');
      if (form) headers['Content-Type'] = 'application/x-www-form-urlencoded';
      this.phase = url.pathname === '/wp-login.php' ? (form ? 'login_submit' : 'login_page') : 'title_page';
      const response = await this.fetchImpl(url.href, {
        method: form ? 'POST' : 'GET', headers,
        body: form ? new URLSearchParams(form).toString() : undefined,
        redirect: 'manual', signal: AbortSignal.timeout(Math.min(remaining, 12000)),
      });
      console.debug(JSON.stringify({ event: 'source_response', phase: this.phase, status: response.status }));
      const setCookies = response.headers.getSetCookie?.() ??
        (response.headers.get('set-cookie') ?? '').split(/,(?=\s*[\w-]+=)/);
      for (const cookie of setCookies) {
        const pair = /^\s*([^=;\s]+)=([^;]*)/.exec(cookie);
        if (!pair) continue;
        if (/(?:^|;)\s*max-age=0(?:;|$)/i.test(cookie) || !pair[2]) this.cookies.delete(pair[1]);
        else this.cookies.set(pair[1], pair[2]);
      }
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        await response.body?.cancel();
        const location = response.headers.get('location');
        if (!location) throw new SourceUnavailable();
        url = new URL(location, url);
        if ([301, 302, 303].includes(response.status)) form = undefined;
        continue;
      }
      if (!response.ok || Number(response.headers.get('content-length') ?? 0) > BODY_LIMIT) {
        await response.body?.cancel();
        throw new SourceUnavailable(`source_http_${response.status}`);
      }
      if (!response.body) return '';
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let text = '', size = 0;
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > BODY_LIMIT) throw new SourceUnavailable();
          text += decoder.decode(value, { stream: true });
        }
        return text + decoder.decode();
      } finally { await reader.cancel().catch(() => {}); }
    }
    throw new SourceUnavailable();
  }

  async login(deadline) {
    if (this.loginPromise) return this.loginPromise;
    if (this.retryAt > this.now()) throw new SourceUnavailable();
    this.loginPromise = (async () => {
      if (!this.username || !this.password) throw new SourceUnavailable('source_secrets_missing');
      this.cookies.clear();
      await this.request('/wp-login.php', { deadline });
      await this.request('/wp-login.php', {
        deadline, form: { log: this.username, pwd: this.password,
          testcookie: '1', redirect_to: `${ORIGIN}/` },
      });
      if (![...this.cookies.keys()].some(name => name.startsWith('wordpress_logged_in'))) {
        throw new SourceUnavailable('source_login_rejected');
      }
      this.loginAt = this.now();
    })();
    try { await this.loginPromise; }
    catch (error) { this.retryAt = this.now() + 20000; throw error; }
    finally { this.loginPromise = null; }
  }

  async episodes(id) {
    if (!Number.isSafeInteger(id) || id <= 0 || id >= 2 ** 31) throw new SourceUnavailable();
    const deadline = this.now() + 22000;
    if (this.retryAt > this.now()) throw new SourceUnavailable();
    if (!this.loginAt || this.now() - this.loginAt > 20 * 60000) await this.login(deadline);
    let rows = parseEpisodes(await this.request(`/?post_type=anime&p=${id}`, { deadline }));
    if (!rows.length && this.now() - this.loginAt > 60000) {
      await this.login(deadline);
      rows = parseEpisodes(await this.request(`/?post_type=anime&p=${id}`, { deadline }));
    }
    if (!rows.length) throw new SourceUnavailable('source_no_episode_links');
    return rows;
  }
}
