const path = require('path');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const dbUtil = require('../../../../db/dbUtil');
const knexUtil = require('../../../../db/knexUtil');
const tableConfig = require('../../../../db/table/tableConfig');
const nascabAccountUtil = require('../../service/utils/nascabAccountUtil');
const config = require('../../../../config/config');
const { TmdbClient } = require('../../../../workers/videoIndex/nfoFetchWorker/tmdbClient');

function _normalizeToTmdbLanguage(locale) {
  const raw = String(locale || '').trim();
  if (!raw || raw === 'system') return '';
  const primary = raw.split(/[-_]/)[0].toLowerCase();
  const map = {
    zh: 'zh-CN',
    en: 'en-US',
    es: 'es-ES',
    fr: 'fr-FR',
    de: 'de-DE',
    ja: 'ja-JP',
    pt: 'pt-BR',
    ru: 'ru-RU',
    ar: 'ar-SA',
    ko: 'ko-KR',
    th: 'th-TH',
    vi: 'vi-VN',
    id: 'id-ID',
  };
  if (map[primary]) return map[primary];
  if (/^[a-z]{2}-[A-Z]{2}$/.test(raw)) return raw;
  return '';
}

function _getSystemLocale() {
  try {
    const v = Intl.DateTimeFormat().resolvedOptions().locale;
    return String(v || '').trim();
  } catch (_) {
    return '';
  }
}

let _tmdbClientPromise = null;
let _tmdbClientConfigKey = '';

async function _getTmdbClient() {
  const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
  const [tmdbApiTokenDec, tmdbApiTokenDefaultDec, tmdbApiUrlDec, tmdbProxyEnable, tmdbProxyUrl, tmdbLanguage, uiLanguage] = await Promise.all([
    nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, 'tmdbApiToken'),
    nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, 'tmdbApiTokenDefault'),
    nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, 'tmdbApiUrl'),
    tableConfig.getConfigByKey('tmdbProxyEnable'),
    tableConfig.getConfigByKey('tmdbProxyUrl'),
    tableConfig.getConfigByKey('tmdbLanguage'),
    tableConfig.getConfigByKey(tableConfig.KEY_SERVER_UI_LANGUAGE),
  ]);

  let apiToken = tmdbApiTokenDec ? String(tmdbApiTokenDec).trim() : '';
  if (!apiToken && tmdbApiTokenDefaultDec) apiToken = String(tmdbApiTokenDefaultDec).trim();
  let apiUrl = tmdbApiUrlDec ? String(tmdbApiUrlDec).trim() : '';
  const proxyEnabled = tmdbProxyEnable === '1' || tmdbProxyEnable === 1;
  const proxyUrl = proxyEnabled && tmdbProxyUrl ? String(tmdbProxyUrl).trim() : '';
  const preferred = tmdbLanguage ? String(tmdbLanguage).trim() : '';
  const effectiveLanguage = _normalizeToTmdbLanguage(preferred) || _normalizeToTmdbLanguage(uiLanguage) || _normalizeToTmdbLanguage(_getSystemLocale()) || 'en-US';

  if (!apiToken || !apiUrl) {
    const defaults = config.getDefaultTmdbConfig();
    if (!apiToken && defaults.tmdbApiToken) apiToken = String(defaults.tmdbApiToken).trim();
    if (!apiUrl && defaults.tmdbApiUrl) apiUrl = String(defaults.tmdbApiUrl).trim();
  }

  const key = `${apiUrl}||${apiToken}||${proxyUrl}||${effectiveLanguage}`;
  if (_tmdbClientPromise && _tmdbClientConfigKey === key) {
    return await _tmdbClientPromise;
  }
  _tmdbClientConfigKey = key;
  _tmdbClientPromise = Promise.resolve(new TmdbClient({ apiUrl, apiToken, proxyUrl, language: effectiveLanguage }));
  return await _tmdbClientPromise;
}

function _pickYearFromDate(dateStr) {
  const s = String(dateStr || '').trim();
  const m = s.match(/^(\d{4})/);
  const y = m ? Number(m[1]) : 0;
  return y > 0 ? y : 0;
}

function _pickActorsFromCredits(credits, limit = 6) {
  const l = Math.max(0, Number(limit || 0) || 0);
  const cast = credits && Array.isArray(credits.cast) ? credits.cast : [];
  const out = [];
  const seen = new Set();
  for (const c of cast) {
    const name = c && c.name ? String(c.name).trim() : '';
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(name);
    if (l > 0 && out.length >= l) break;
  }
  return out;
}

function _pickGenresFromDetail(genres, limit = 6) {
  const l = Math.max(0, Number(limit || 0) || 0);
  const list = Array.isArray(genres) ? genres : [];
  const out = [];
  const seen = new Set();
  for (const g of list) {
    const name = g && g.name ? String(g.name).trim() : '';
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(name);
    if (l > 0 && out.length >= l) break;
  }
  return out;
}

function _mapMovieResult(tmdb, r) {
  const title = (r && (r.title || r.name) ? String(r.title || r.name) : '').trim();
  const originalTitle = (r && r.original_title ? String(r.original_title) : '').trim();
  const overview = (r && r.overview ? String(r.overview) : '').trim();
  const posterPath = r && r.poster_path ? String(r.poster_path) : '';
  const backdropPath = r && r.backdrop_path ? String(r.backdrop_path) : '';
  return {
    id: r && r.id ? Number(r.id) : 0,
    media_type: 'movie',
    title,
    original_title: originalTitle,
    overview,
    year: _pickYearFromDate(r && r.release_date ? r.release_date : ''),
    poster_url: posterPath ? tmdb.buildImageUrl(posterPath) : '',
    backdrop_url: backdropPath ? tmdb.buildImageUrl(backdropPath) : '',
    vote_average: r && r.vote_average ? Number(r.vote_average) : 0,
    actors: _pickActorsFromCredits(r && r.credits ? r.credits : null),
    genres: _pickGenresFromDetail(r && r.genres ? r.genres : null),
  };
}

function _mapTvResult(tmdb, r) {
  const title = (r && (r.name || r.title) ? String(r.name || r.title) : '').trim();
  const originalTitle = (r && r.original_name ? String(r.original_name) : '').trim();
  const overview = (r && r.overview ? String(r.overview) : '').trim();
  const posterPath = r && r.poster_path ? String(r.poster_path) : '';
  const backdropPath = r && r.backdrop_path ? String(r.backdrop_path) : '';
  return {
    id: r && r.id ? Number(r.id) : 0,
    media_type: 'tv',
    title,
    original_title: originalTitle,
    overview,
    year: _pickYearFromDate(r && r.first_air_date ? r.first_air_date : ''),
    poster_url: posterPath ? tmdb.buildImageUrl(posterPath) : '',
    backdrop_url: backdropPath ? tmdb.buildImageUrl(backdropPath) : '',
    vote_average: r && r.vote_average ? Number(r.vote_average) : 0,
    actors: _pickActorsFromCredits(r && r.credits ? r.credits : null),
    genres: _pickGenresFromDetail(r && r.genres ? r.genres : null),
  };
}

async function _enrichResults(tmdb, mediaType, results) {
  const list = Array.isArray(results) ? results : [];
  if (!tmdb || (mediaType !== 'movie' && mediaType !== 'tv') || list.length === 0) return list;

  const queue = list.map(r => r).filter(r => r && r.id);
  const concurrency = 4;

  const workers = Array.from({ length: Math.min(concurrency, queue.length) }).map(async () => {
    while (queue.length > 0) {
      const item = queue.shift();
      if (!item || !item.id) continue;

      const hasActors = Array.isArray(item.actors) && item.actors.length > 0;
      const hasGenres = Array.isArray(item.genres) && item.genres.length > 0;
      if (hasActors && hasGenres) continue;

      const details = mediaType === 'movie' ? await tmdb.getMovieDetails(item.id).catch(() => null) : await tmdb.getTvDetails(item.id).catch(() => null);
      if (!details) continue;

      item.actors = _pickActorsFromCredits(details.credits);
      item.genres = _pickGenresFromDetail(details.genres);
    }
  });

  await Promise.all(workers);
  return list;
}

class VideoTmdbController {
  async search(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const mediaType = String(body.media_type ?? body.mediaType ?? '').trim();
      const searchMode = String(body.search_mode ?? body.searchMode ?? 'keyword').trim();
      const query = String(body.query ?? body.keyword ?? '').trim();
      const tmdbId = String(body.tmdb_id ?? body.tmdbId ?? '').trim();
      const page = Math.max(1, Number(body.page ?? 1) || 1);

      if (mediaType !== 'movie' && mediaType !== 'tv') {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const tmdb = await _getTmdbClient();
      if (!tmdb) return ResponseUtil.error(req, res, 'common.ERROR', 500);

      if (searchMode === 'tmdb_id') {
        const idNum = Number(tmdbId || 0) || 0;
        if (!idNum) return ResponseUtil.success(req, res, { page: 1, total_pages: 0, results: [] }, 'common.SUCCESS', 200);
        const details = mediaType === 'movie' ? await tmdb.getMovieDetails(idNum) : await tmdb.getTvDetails(idNum);
        if (!details) return ResponseUtil.success(req, res, { page: 1, total_pages: 0, results: [] }, 'common.SUCCESS', 200);
        const item = mediaType === 'movie' ? _mapMovieResult(tmdb, details) : _mapTvResult(tmdb, details);
        return ResponseUtil.success(req, res, { page: 1, total_pages: 1, results: [item].filter(e => e && e.id) }, 'common.SUCCESS', 200);
      }

      if (!query) return ResponseUtil.success(req, res, { page: 1, total_pages: 0, results: [] }, 'common.SUCCESS', 200);

      const endpoint = mediaType === 'movie' ? '/3/search/movie' : '/3/search/tv';
      const raw = await tmdb.requestJson(endpoint, {
        query,
        include_adult: 'false',
        language: tmdb.language,
        page,
      });

      const resultsRaw = Array.isArray(raw && raw.results) ? raw.results : [];
      const totalPages = Math.max(0, Number(raw && raw.total_pages ? raw.total_pages : 0) || 0);

      let results = resultsRaw.map(r => (mediaType === 'movie' ? _mapMovieResult(tmdb, r) : _mapTvResult(tmdb, r))).filter(e => e && e.id);
      // results = await _enrichResults(tmdb, mediaType, results);

      return ResponseUtil.success(req, res, { page, total_pages: totalPages, results }, 'common.SUCCESS', 200);
    } catch (e) {
      console.log(e);
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new VideoTmdbController();
