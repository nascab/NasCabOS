'use strict';

const fs = require('fs');
const http = require('http');
const https = require('https');
const tls = require('tls');
const { URL } = require('url');

function _jsonStringifySafe(v) {
  try {
    return JSON.stringify(v);
  } catch (_) {
    return '';
  }
}

function _readAll(res) {
  return new Promise(resolve => {
    const chunks = [];
    res.on('data', d => chunks.push(d));
    res.on('end', () => resolve(Buffer.concat(chunks)));
    res.on('error', () => resolve(Buffer.concat(chunks)));
  });
}

function _sleep(ms) {
  const n = Math.max(0, Number(ms || 0) || 0);
  if (!n) return Promise.resolve();
  return new Promise(resolve => setTimeout(resolve, n));
}

function _buildProxyAuthHeader(proxyUrl) {
  const u = proxyUrl && typeof proxyUrl === 'object' ? proxyUrl : null;
  if (!u) return '';
  const user = u.username ? decodeURIComponent(u.username) : '';
  const pass = u.password ? decodeURIComponent(u.password) : '';
  if (!user && !pass) return '';
  const raw = `${user}:${pass}`;
  return `Basic ${Buffer.from(raw).toString('base64')}`;
}

function _normalizeProxyUrlString(proxyUrlStr) {
  const raw = String(proxyUrlStr || '').trim();
  if (!raw) return '';
  if (raw.includes('://')) return raw;
  return `http://${raw}`;
}

function _normalizeApiUrlString(apiUrlStr) {
  const raw = String(apiUrlStr || '').trim();
  if (!raw) return 'https://api.tmdb.org';
  if (raw.includes('://')) return raw;
  return `https://${raw}`;
}

function _createHttpsProxyAgent(proxyUrlStr) {
  const raw = _normalizeProxyUrlString(proxyUrlStr);
  if (!raw) {
    console.log('[TmdbClient] _createHttpsProxyAgent: proxyUrlStr empty, agent=null');
    return null;
  }

  let proxyUrl;
  try {
    proxyUrl = new URL(raw);
  } catch (e) {
    console.log('[TmdbClient] _createHttpsProxyAgent: invalid proxy URL', raw.slice(0, 80), e && e.message);
    return null;
  }

  const isHttpsProxy = proxyUrl.protocol === 'https:';
  const isHttpProxy = proxyUrl.protocol === 'http:';
  if (!isHttpsProxy && !isHttpProxy) return null;

  const host = proxyUrl.hostname;
  const port = Number(proxyUrl.port || (isHttpsProxy ? 443 : 80)) || (isHttpsProxy ? 443 : 80);
  if (!host || !port) return null;

  const proxyAuth = _buildProxyAuthHeader(proxyUrl);

  return new https.Agent({
    keepAlive: true,
    createConnection: (options, callback) => {
      const targetHost = options.servername || options.host || options.hostname;
      const targetPort = Number(options.port || 443) || 443;
      const connectHeaders = {
        Host: `${targetHost}:${targetPort}`,
      };
      if (proxyAuth) connectHeaders['Proxy-Authorization'] = proxyAuth;

      const connectOptions = {
        host,
        port,
        method: 'CONNECT',
        path: `${targetHost}:${targetPort}`,
        headers: connectHeaders,
      };

      const req = (isHttpsProxy ? https : http).request(connectOptions);
      req.once('connect', (res, socket) => {
        if (!res || res.statusCode !== 200) {
          try {
            socket.destroy();
          } catch (_) {}
          const err = new Error(`Proxy CONNECT failed (${res ? res.statusCode : 'no_status'})`);
          return callback(err);
        }
        const tlsSocket = tls.connect({
          socket,
          servername: targetHost,
          rejectUnauthorized: options.rejectUnauthorized !== false,
        });
        tlsSocket.once('secureConnect', () => callback(null, tlsSocket));
        tlsSocket.once('error', e => callback(e));
      });
      req.once('error', e => callback(e));
      req.end();
    },
  });
}

class TmdbClient {
  constructor({ apiUrl, apiToken, proxyUrl, language }) {
    this.apiUrl = _normalizeApiUrlString(apiUrl);
    this.apiToken = String(apiToken || '').trim();
    this.imageBaseUrl = 'https://image.tmdb.org/t/p/original';
    this.minRequestIntervalMs = 0;
    this._lastRequestAtMs = 0;
    this._rateLimitQueue = Promise.resolve();
    this.proxyUrl = _normalizeProxyUrlString(proxyUrl);
    this._proxyAgent = this.proxyUrl ? _createHttpsProxyAgent(this.proxyUrl) : null;
    this.language = String(language || '').trim() || 'zh-CN';
    console.log('[TmdbClient] apiUrl=', this.apiUrl, 'proxyUrl=', this.proxyUrl || '(none)', 'agent=', this._proxyAgent ? 'ok' : 'null');
  }

  setProxyUrl(proxyUrl) {
    this.proxyUrl = _normalizeProxyUrlString(proxyUrl);
    this._proxyAgent = this.proxyUrl ? _createHttpsProxyAgent(this.proxyUrl) : null;
  }

  setLanguage(language) {
    this.language = String(language || '').trim() || 'zh-CN';
  }

  async withRateLimit(fn) {
    const task = typeof fn === 'function' ? fn : null;
    if (!task) throw new Error('rate limit task missing');

    const run = async () => {
      const last = Number(this._lastRequestAtMs || 0) || 0;
      const now = Date.now();
      const waitMs = Math.max(0, last + (Number(this.minRequestIntervalMs) || 0) - now);
      if (waitMs) await _sleep(waitMs);
      this._lastRequestAtMs = Date.now();
      return await task();
    };

    const p = this._rateLimitQueue.then(run);
    this._rateLimitQueue = p.catch(() => {});
    return await p;
  }

  buildApiUrl(pathname, query = null) {
    const u = new URL(this.apiUrl);
    const basePath = u.pathname && u.pathname !== '/' ? u.pathname.replace(/\/+$/, '') : '';
    const p = String(pathname || '');
    u.pathname = `${basePath}${p.startsWith('/') ? p : `/${p}`}`;
    u.search = '';
    if (query && typeof query === 'object') {
      for (const [k, v] of Object.entries(query)) {
        if (v === undefined || v === null) continue;
        const s = String(v).trim();
        if (!s) continue;
        u.searchParams.set(k, s);
      }
    }
    return u;
  }

  async requestJson(pathname, query = null) {
    if (!this.apiToken) throw new Error('TMDB token missing');
    return await this.withRateLimit(async () => {
      const url = this.buildApiUrl(pathname, query);
      console.log('[TmdbClient.requestJson] request url=', url.href, 'pathname=', pathname);
      const body = await new Promise((resolve, reject) => {
        const req = https.request(
          url,
          {
            method: 'GET',
            headers: {
              Authorization: `Bearer ${this.apiToken}`,
              Accept: 'application/json',
            },
            agent: this._proxyAgent || undefined,
          },
          async res => {
            const buf = await _readAll(res);
            const text = buf.toString('utf8');
            if (res.statusCode && res.statusCode >= 400) {
              const err = new Error(`TMDB ${res.statusCode} ${url.pathname}`);
              err.statusCode = res.statusCode;
              err.body = text;
              return reject(err);
            }
            try {
              return resolve(JSON.parse(text || '{}'));
            } catch (e) {
              const err = new Error(`TMDB invalid JSON ${url.pathname}`);
              err.body = text;
              return reject(err);
            }
          }
        );
        req.on('error', reject);
        req.end();
      });
      return body;
    });
  }

  buildImageUrl(filePath) {
    const fp = String(filePath || '').trim();
    if (!fp) return '';
    if (fp.startsWith('http://') || fp.startsWith('https://')) return fp;
    const base = this.imageBaseUrl.replace(/\/+$/, '');
    return `${base}${fp.startsWith('/') ? fp : `/${fp}`}`;
  }

  async downloadToFile(imageUrl, targetPath, { onSuccess } = {}) {
    console.log('tmdb下载图片', imageUrl, targetPath);
    const urlStr = String(imageUrl || '').trim();
    const out = String(targetPath || '').trim();
    if (!urlStr || !out) return false;

    await fs.promises.mkdir(require('path').dirname(out), { recursive: true });

    const tmp = `${out}.${Date.now()}.tmp`;

    return await this.withRateLimit(async () => {
      return await new Promise(resolve => {
        const file = fs.createWriteStream(tmp);
        const req = https.get(urlStr, { headers: { Accept: '*/*' }, agent: this._proxyAgent || undefined }, res => {
          if (res.statusCode && res.statusCode >= 400) {
            file.close(() => {
              try {
                fs.unlinkSync(tmp);
              } catch (_) {}
              resolve(false);
            });
            return;
          }
          res.pipe(file);
          file.on('finish', () => {
            file.close(() => {
              try {
                fs.renameSync(tmp, out);
                if (typeof onSuccess === 'function') {
                  try { onSuccess(out); } catch (_) {}
                }
                resolve(true);
              } catch (_) {
                try { fs.unlinkSync(tmp); } catch (_) {}
                resolve(false);
              }
            });
          });
        });
        req.on('error', () => {
          try {
            file.close(() => {});
          } catch (_) {}
          try {
            fs.unlinkSync(tmp);
          } catch (_) {}
          resolve(false);
        });
      });
    });
  }

  async searchMovie({ query, year = 0, page = 1 }) {
    console.log('tmdb搜索电影', query, year);
    const q = String(query || '').trim();
    if (!q) return [];
    const p = Math.max(1, Number(page || 1) || 1);
    const res = await this.requestJson('/3/search/movie', {
      query: q,
      year: year || undefined,
      include_adult: 'false',
      language: this.language,
      page: p,
    });
    let results = Array.isArray(res && res.results) ? res.results : [];
    return results;
  }

  async searchTv({ query, page = 1 }) {
    console.log('tmdb搜索电视剧', query);
    const q = String(query || '').trim();
    if (!q) return [];
    const p = Math.max(1, Number(page || 1) || 1);
    const res = await this.requestJson('/3/search/tv', {
      query: q,
      include_adult: 'false',
      language: this.language,
      page: p,
    });
    let results = Array.isArray(res && res.results) ? res.results : [];
    return results;
  }

  async getMovieDetails(id) {
    console.log('tmdb获取电影详情', id);
    const tmdbId = Number(id || 0) || 0;
    if (!tmdbId) return null;
    return await this.requestJson(`/3/movie/${tmdbId}`, { append_to_response: 'credits,external_ids,images', include_image_language: 'en,null', language: this.language });
  }

  async getTvDetails(id) {
    console.log('tmdb获取电视剧详情', id);
    const tmdbId = Number(id || 0) || 0;
    if (!tmdbId) return null;
    return await this.requestJson(`/3/tv/${tmdbId}`, { append_to_response: 'credits,external_ids,images', include_image_language: 'en,null', language: this.language });
  }

  async getSeasonDetails(tvId, seasonNumber) {
    const tid = Number(tvId || 0) || 0;
    const sn = Number(seasonNumber || 0) || 0;
    if (!tid || sn <= 0) return null;
    return await this.requestJson(`/3/tv/${tid}/season/${sn}`, { append_to_response: 'credits,external_ids,images', include_image_language: 'en,null', language: this.language });
  }

  async getEpisodeDetails(tvId, seasonNumber, episodeNumber) {
    console.log('tmdb获取剧集详情', tvId, seasonNumber, episodeNumber);
    const tid = Number(tvId || 0) || 0;
    const sn = Number(seasonNumber || 0) || 0;
    const en = Number(episodeNumber || 0) || 0;
    if (!tid || sn <= 0 || en <= 0) return null;
    return await this.requestJson(`/3/tv/${tid}/season/${sn}/episode/${en}`, { append_to_response: 'credits,external_ids,images', include_image_language: 'en,null', language: this.language });
  }
}

module.exports = {
  TmdbClient,
  _jsonStringifySafe,
};
