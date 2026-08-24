'use strict';

const fs = require('fs');
const path = require('path');
const sharp = require('../../../utils/sharpConfigured');

const Logger = require('../../../utils/logger');
const FileUtil = require('../../../utils/fileUtil');
const dbUtil = require('../../../db/dbUtil');
const knexUtil = require('../../../db/knexUtil');
const tableConfig = require('../../../db/table/tableConfig');
const tableVideoSource = require('../../../db/table/tableVideoSource');
const config = require('../../../config/config');
const nascabAccountUtil = require('../../../api/modules/service/utils/nascabAccountUtil');

const { TmdbClient } = require('./tmdbClient');
const { buildMovieNfo, buildTvShowNfo, buildSeasonNfo, buildEpisodeNfo, writeTextIfChanged } = require('./jellyfinNfo');
const videoIndexIndexUtil = require('../videoIndexIndexUtil');
const { readAndParseNfo, hasValidNfo } = require('../nfoParser');
const { parseSeasonNumberFromName, parseEpisodeFromName, normalizeNameForNfoGuess } = require('../videoIndexUtil');
const tmdbUtil = require('./tmdbUtil');
function _pickYearFromText(s) {
  const m = String(s || '').match(/\b(19|20)\d{2}\b/);
  const y = m ? Number(m[0]) : 0;
  return y >= 1900 && y <= 2100 ? y : 0;
}

function _cleanSearchText(text) {
  const raw = String(text || '').trim();
  if (!raw) return '';
  const tokens = tmdbUtil.getSearchTokens(raw).tokens || [];
  if (tokens.length > 0) return tokens.join(' ').trim();
  return raw.replace(/\s+/g, ' ').trim();
}

function _normalizeSearchTitleFromFileName(filename) {
  const base = path.parse(String(filename || '')).name;
  const norm = normalizeNameForNfoGuess(base);
  return norm || base;
}

const _SKIP_NAME_HINTS = ['img_', 'video_', 'vid_', 'samsung_', 'short_', 'clip_', 'weixin_', 'wx_', 'dsc_', 'douyin_', 'xiaohongshu_', 'baiduyun_', 'mmexport'];

function _hasSkipNameHint(filename) {
  const s = String(filename || '').toLowerCase();
  if (!s) return false;
  return _SKIP_NAME_HINTS.some(t => s.includes(t));
}

function _shouldSkipByDurationSeconds(duration) {
  const d = Number(duration || 0) || 0;
  return d > 0 && d < 20 * 60;
}

function _isPureNumberText(text) {
  const s = String(text || '').trim();
  if (!s) return false;
  return /^\d+$/.test(s);
}

function _buildQueryAttemptsFromText(text) {
  const { tokens, year } = tmdbUtil.getSearchTokens(text);
  if (tokens.length === 0) return [];

  const seen = new Set();
  const out = [];
  const push = (q, y) => {
    const query = String(q || '').trim();
    const yr = Number(y || 0) || 0;
    if (!query) return;
    const key = `${query}||${yr || ''}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push({ query, year: yr });
  };

  for (let i = tokens.length; i >= 1; i -= 1) {
    const q = tokens.slice(0, i).join(' ').trim();
    if (!q || q.length < 2) continue;
    if (year) push(q, year);
    push(q, 0);
  }

  return out;
}

/** 与前端国际化 13 种语言一致，将 locale 规范为 TMDB 的 language 格式 */
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

function _pickList(arr, mapper, max = 0) {
  const list = Array.isArray(arr) ? arr : [];
  const out = [];
  for (const it of list) {
    const v = mapper(it);
    if (!v) continue;
    out.push(v);
    if (max > 0 && out.length >= max) break;
  }
  return out;
}

function _tmdbImageUrl(client, filePath) {
  if (!client) return '';
  return client.buildImageUrl(filePath);
}

function _mapCreditsToPeople({ client, credits }) {
  const cast = credits && Array.isArray(credits.cast) ? credits.cast : [];
  const crew = credits && Array.isArray(credits.crew) ? credits.crew : [];

  const actors = _pickList(
    cast,
    c => {
      const name = c && c.name ? String(c.name).trim() : '';
      if (!name) return null;
      const role = c && c.character ? String(c.character).trim() : '';
      const tmdbId = c && c.id ? String(c.id) : '';
      const thumb = c && c.profile_path ? _tmdbImageUrl(client, c.profile_path) : '';
      return { name, role, tmdbId, thumb };
    },
    30
  );

  const directors = _pickList(
    crew.filter(c => c && String(c.job || '').toLowerCase() === 'director'),
    c => {
      const name = c && c.name ? String(c.name).trim() : '';
      if (!name) return null;
      const tmdbId = c && c.id ? String(c.id) : '';
      const thumb = c && c.profile_path ? _tmdbImageUrl(client, c.profile_path) : '';
      return { name, tmdbId, thumb };
    },
    10
  );

  return { actors, directors };
}

function _mapMovieToNfo({ client, movie }) {
  const m = movie && typeof movie === 'object' ? movie : {};
  const { actors, directors } = _mapCreditsToPeople({ client, credits: m.credits });
  const genres = _pickList(m.genres, g => (g && g.name ? String(g.name) : ''), 0);
  const countries = _pickList(m.production_countries, c => (c && c.name ? String(c.name) : ''), 0);
  const languages = _pickList(m.spoken_languages, l => (l && l.english_name ? String(l.english_name) : l && l.name ? String(l.name) : ''), 0);
  const year = _pickYearFromText(m.release_date);
  const imdbId = m.external_ids && m.external_ids.imdb_id ? String(m.external_ids.imdb_id) : '';
  return {
    title: m.title || m.name || '',
    originalTitle: m.original_title || '',
    sortTitle: '',
    year,
    premiered: m.release_date || '',
    plot: m.overview || '',
    rating: m.vote_average ? Number(m.vote_average) : 0,
    genres,
    tags: [],
    countries,
    languages,
    tmdbId: m.id ? String(m.id) : '',
    imdbId,
    actors,
    directors,
  };
}

function _mapTvToNfo({ client, tv }) {
  const t = tv && typeof tv === 'object' ? tv : {};
  const { actors, directors } = _mapCreditsToPeople({ client, credits: t.credits });
  const genres = _pickList(t.genres, g => (g && g.name ? String(g.name) : ''), 0);
  const countries = _pickList(t.origin_country, c => (c ? String(c) : ''), 0);
  const languages = _pickList(t.languages, l => (l ? String(l) : ''), 0);
  const year = _pickYearFromText(t.first_air_date);
  const imdbId = t.external_ids && t.external_ids.imdb_id ? String(t.external_ids.imdb_id) : '';
  const studio = _pickList(t.networks, n => (n && n.name ? String(n.name) : ''), 1)[0] || '';
  return {
    title: t.name || '',
    originalTitle: t.original_name || '',
    sortTitle: '',
    year,
    premiered: t.first_air_date || '',
    plot: t.overview || '',
    rating: t.vote_average ? Number(t.vote_average) : 0,
    genres,
    tags: [],
    countries,
    languages,
    studio,
    tmdbId: t.id ? String(t.id) : '',
    imdbId,
    actors,
    directors,
  };
}

function _mapSeasonToNfo({ client, tvId, season }) {
  const s = season && typeof season === 'object' ? season : {};
  const { actors, directors } = _mapCreditsToPeople({ client, credits: s.credits });
  const year = _pickYearFromText(s.air_date);
  return {
    title: s.name || `Season ${s.season_number || ''}`,
    seasonNumber: Number(s.season_number || 0) || 0,
    year,
    premiered: s.air_date || '',
    plot: s.overview || '',
    rating: s.vote_average ? Number(s.vote_average) : 0,
    tmdbId: s.id ? String(s.id) : tvId ? `${tvId}:${s.season_number || ''}` : '',
    actors,
    directors,
  };
}

function _mapEpisodeToNfo({ client, episode }) {
  const e = episode && typeof episode === 'object' ? episode : {};
  const { actors, directors } = _mapCreditsToPeople({ client, credits: e.credits });
  return {
    title: e.name || '',
    seasonNumber: Number(e.season_number || 0) || 0,
    episodeNumber: Number(e.episode_number || 0) || 0,
    aired: e.air_date || '',
    plot: e.overview || '',
    rating: e.vote_average ? Number(e.vote_average) : 0,
    tmdbId: e.id ? String(e.id) : '',
    actors,
    directors,
  };
}

function _pickLogoPathFromImages(images) {
  const logos = images && Array.isArray(images.logos) ? images.logos : [];
  if (!logos || logos.length === 0) return '';
  const pick = logos.find(l => l && String(l.iso_639_1 || '').toLowerCase() === 'zh') || logos.find(l => l && String(l.iso_639_1 || '').toLowerCase() === 'en') || logos[0];
  return pick && pick.file_path ? String(pick.file_path) : '';
}

async function _ensureDownloaded(client, baseDir, fileName, filePath) {
  const fp = String(filePath || '').trim();
  const out = path.join(String(baseDir || ''), String(fileName || ''));
  if (!fp || !out) return false;
  try {
    if (fs.existsSync(out) && fs.statSync(out).isFile()) return false;
  } catch (_) {}

  const url = client.buildImageUrl(fp);
  if (!url) return false;

  const tmp = `${out}.${Date.now()}.tmp`;
  const ok = await client.downloadToFile(url, tmp);
  if (!ok) return false;
  try {
    await sharp(tmp)
      .jpeg({ quality: 85 })
      .toFile(out);
    try { fs.unlinkSync(tmp); } catch (_) {}
    return true;
  } catch (_) {
    try { fs.unlinkSync(tmp); } catch (_) {}
    try { fs.unlinkSync(out); } catch (_) {}
    return false;
  }
}

async function _ensureDownloadedJpeg(client, baseDir, fileName, filePath) {
  const fp = String(filePath || '').trim();
  const out = path.join(String(baseDir || ''), String(fileName || '')).trim();
  if (!fp || !out) return false;
  try {
    if (fs.existsSync(out) && fs.statSync(out).isFile()) return false;
  } catch (_) {}

  const url = client.buildImageUrl(fp);
  if (!url) return false;

  const tmp = `${out}.${Date.now()}.tmp`;
  const ok = await client.downloadToFile(url, tmp);
  if (!ok) return false;
  try {
    await sharp(tmp)
      .jpeg({ quality: 85 })
      .toFile(out);
    try { fs.unlinkSync(tmp); } catch (_) {}
    return true;
  } catch (_) {
    try { fs.unlinkSync(tmp); } catch (_) {}
    try { fs.unlinkSync(out); } catch (_) {}
    return false;
  }
}

async function _ensureDownloadedPng(client, baseDir, fileName, filePath) {
  const fp = String(filePath || '').trim();
  const out = path.join(String(baseDir || ''), String(fileName || '')).trim();
  if (!fp || !out) return false;
  try {
    if (fs.existsSync(out) && fs.statSync(out).isFile()) return false;
  } catch (_) {}

  const url = client.buildImageUrl(fp);
  if (!url) return false;

  const tmp = `${out}.${Date.now()}.tmp`;
  const ok = await client.downloadToFile(url, tmp);
  if (!ok) return false;
  try {
    await sharp(tmp)
      .png()
      .toFile(out);
    try { fs.unlinkSync(tmp); } catch (_) {}
    return true;
  } catch (_) {
    try { fs.unlinkSync(tmp); } catch (_) {}
    try { fs.unlinkSync(out); } catch (_) {}
    return false;
  }
}

async function _updateIndexFromNfoAndArtwork({ knex, row, baseDir, searchDir, nfoPath, videoBaseName = '', onlyVideoBase = false, seasonNumber = 0 }) {
  const r = row && typeof row === 'object' ? row : {};
  if (!r.id) return false;

  const parsed = nfoPath ? await readAndParseNfo(nfoPath) : null;
  const nfoFields = videoIndexIndexUtil.buildNfoFieldsFromParsed(parsed) || { nfo_get_state: 1 };

  const current = await knex('video_index')
    .where({ id: r.id })
    .first('poster_path', 'fanart_path', 'logo_path')
    .catch(() => null);

  const artwork = await videoIndexIndexUtil.resolveArtworkPaths({ baseDir, searchDir, current, videoBaseName, onlyVideoBase, seasonNumber });

  const patch = { ...nfoFields, ...artwork, view_time: new Date() };
  await knex('video_index')
    .where({ id: r.id })
    .update(patch)
    .catch(() => {});

  const hasKeyFields = nfoFields && (Object.prototype.hasOwnProperty.call(nfoFields, 'nfo_regions') || Object.prototype.hasOwnProperty.call(nfoFields, 'nfo_genres'));
  if (hasKeyFields) {
    await videoIndexIndexUtil.syncVideoIndex2KeyFromNfoFields({
      knex,
      indexId: r.id,
      mediaType: r.media_type,
      nfoRegions: nfoFields.nfo_regions,
      nfoGenres: nfoFields.nfo_genres,
    });
  }
  return true;
}

class NfoFetchRunner {
  constructor() {
    this.knexVideo = null;
    this.tmdb = null;
  }

  async init() {
    await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
    await knexUtil.init(dbUtil.DB_PATHS.VIDEO_DB);
    this.knexVideo = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);

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

    this.tmdb = new TmdbClient({ apiUrl, apiToken, proxyUrl, language: effectiveLanguage });
  }

  async getPendingRoots(limit = 5) {
    const matchRoots = await tableVideoSource.getMatchNfoPaths({ knex: this.knexVideo });
    const enabledRoots = (matchRoots || []).map(p => (p ? path.resolve(String(p)) : '')).filter(Boolean);
    if (enabledRoots.length === 0) return [];
    console.log('enabledRoots', enabledRoots);
    const rows = await this.knexVideo('video_index')
      .select('id', 'path', 'filename', 'media_type', 'is_file', 'nfo_name', 'nfo_get_state', 'duration')
      .where({ nfo_get_state: 0 })
      .whereIn('media_type', ['tv', 'movie', 'bdmv', 'video_ts'])
      .andWhere(qb => {
        qb.where(inner => {
          for (const root of enabledRoots) {
            const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
            inner.orWhere('path', root).orWhere('path', 'like', `${prefix}%`);
            inner.orWhere({ path: path.dirname(root), filename: path.basename(root) });
          }
        });
      })
      .orderBy('id', 'asc')
      .limit(Math.max(1, Math.min(50, Number(limit || 0) || 5)))
      .catch(() => []);
    return rows || [];
  }

  async markSkipped(row) {
    if (!row || !row.id) return;
    await this.knexVideo('video_index')
      .where({ id: row.id })
      .update({ nfo_get_state: 1 })
      .catch(() => {});
  }

  async markFailed(row) {
    if (!row || !row.id) return;
    console.log('nfo获取失败', row.id, row.path, row.filename);
    await this.knexVideo('video_index')
      .where({ id: row.id })
      .update({ nfo_get_state: 1 })
      .catch(() => {});
  }

  async processMovieRow(row) {
    const dirPath = row && row.path ? String(row.path) : '';
    const filename = row && row.filename ? String(row.filename) : '';
    if (!dirPath || !filename) return false;
    const mediaType = row && row.media_type ? String(row.media_type).trim() : '';
    const isDiscFolderMovie = mediaType === 'bdmv' || mediaType === 'video_ts';
    const movieFolder = isDiscFolderMovie ? path.join(dirPath, filename) : '';

    if (FileUtil.shouldSkipIndexingFilename(filename) || _hasSkipNameHint(path.parse(filename).name) || _shouldSkipByDurationSeconds(row && row.duration)) {
      await this.markSkipped(row);
      return true;
    }

    const preferTitle = (row.nfo_name ? String(row.nfo_name) : '').trim();
    const fallbackTitle = _normalizeSearchTitleFromFileName(filename);
    const rawTitle = preferTitle || fallbackTitle;

    const numericCheck = _cleanSearchText(rawTitle) || String(rawTitle || '').trim();
    if (_isPureNumberText(numericCheck) && numericCheck !== '1946') {
      await this.markSkipped(row);
      return true;
    }

    try {
      const st = await fs.promises.stat(isDiscFolderMovie ? movieFolder : path.join(dirPath, filename));
      if (isDiscFolderMovie ? !st.isDirectory() : !st.isFile()) return false;
    } catch (_) {
      return false;
    }

    const yearFromFilename = _pickYearFromText(filename);
    const attempts = _buildQueryAttemptsFromText(rawTitle);
    if (attempts.length === 0) {
      const q = _cleanSearchText(rawTitle);
      if (q) attempts.push({ query: q, year: yearFromFilename || 0 });
    }

    let tmdbId = 0;
    for (const a of attempts) {
      const q = a && a.query ? String(a.query) : '';
      const y = a && a.year ? Number(a.year) : 0;
      if (!q) continue;
      const results = await this.tmdb.searchMovie({ query: q, year: y || yearFromFilename || 0 });
      const picked = results && results[0] ? results[0] : null;
      const id = picked && picked.id ? Number(picked.id) : 0;
      if (id) {
        tmdbId = id;
        break;
      }
    }
    if (!tmdbId) return false;

    const details = await this.tmdb.getMovieDetails(tmdbId);
    if (!details) return false;

    const nfoData = _mapMovieToNfo({ client: this.tmdb, movie: details });
    const baseName = path.parse(filename).name;
    const nfoPath = isDiscFolderMovie ? path.join(movieFolder, 'movie.nfo') : path.join(dirPath, `${baseName}.nfo`);
    await writeTextIfChanged(nfoPath, buildMovieNfo(nfoData));

    if (details.poster_path) await _ensureDownloadedJpeg(this.tmdb, isDiscFolderMovie ? movieFolder : dirPath, isDiscFolderMovie ? 'poster.jpg' : `${baseName}-post.jpg`, details.poster_path);
    if (details.backdrop_path) await _ensureDownloadedJpeg(this.tmdb, isDiscFolderMovie ? movieFolder : dirPath, isDiscFolderMovie ? 'fanart.jpg' : `${baseName}-fanart.jpg`, details.backdrop_path);
    const logo = _pickLogoPathFromImages(details.images);
    if (logo) {
      await _ensureDownloadedPng(this.tmdb, isDiscFolderMovie ? movieFolder : dirPath, isDiscFolderMovie ? 'logo.png' : `${baseName}-logo.png`, logo);
      const legacy = path.join(isDiscFolderMovie ? movieFolder : dirPath, isDiscFolderMovie ? 'logo.jpg' : `${baseName}-logo.jpg`);
      try {
        if (fs.existsSync(legacy) && fs.statSync(legacy).isFile()) fs.unlinkSync(legacy);
      } catch (_) {}
    }

    await _updateIndexFromNfoAndArtwork({
      knex: this.knexVideo,
      row,
      baseDir: dirPath,
      searchDir: isDiscFolderMovie ? movieFolder : dirPath,
      nfoPath,
      videoBaseName: isDiscFolderMovie ? '' : baseName,
      onlyVideoBase: false,
      seasonNumber: 0,
    });

    return true;
  }

  async getSeasonsUnderShow(showFolder) {
    const resolved = path.resolve(String(showFolder || ''));
    if (!resolved) return [];
    const rows = await this.knexVideo('video_index')
      .select('id', 'path', 'filename', 'media_type', 'is_file', 'nfo_get_state')
      .where({ path: resolved, is_file: 0, media_type: 'season', nfo_get_state: 0 })
      .orderBy('id', 'asc')
      .catch(() => []);
    return rows || [];
  }

  async getSeasonsWithPendingEpisodesUnderShow(showFolder) {
    const resolved = path.resolve(String(showFolder || ''));
    if (!resolved) return [];
    const prefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;

    const episodeFolders = await this.knexVideo('video_index')
      .distinct('path')
      .where({ is_file: 1, media_type: 'episod', nfo_get_state: 0 })
      .andWhere('path', 'like', `${prefix}%`)
      .catch(() => []);

    const seasonNames = new Set();
    for (const r of episodeFolders || []) {
      const episodeDir = r && r.path ? String(r.path) : '';
      if (!episodeDir) continue;
      const rel = path.relative(resolved, episodeDir);
      if (!rel || rel.startsWith('..')) continue;
      const first = rel.split(path.sep).filter(Boolean)[0] || '';
      if (first) seasonNames.add(first);
    }
    const names = Array.from(seasonNames);
    if (names.length === 0) return [];

    const rows = await this.knexVideo('video_index')
      .select('id', 'path', 'filename', 'media_type', 'is_file', 'nfo_get_state')
      .where({ path: resolved, is_file: 0, media_type: 'season' })
      .whereIn('filename', names)
      .orderBy('id', 'asc')
      .catch(() => []);
    return rows || [];
  }

  async getSeasonsNeedingWork(showFolder) {
    const list = [];
    const a = await this.getSeasonsUnderShow(showFolder);
    const b = await this.getSeasonsWithPendingEpisodesUnderShow(showFolder);
    for (const r of a || []) list.push(r);
    for (const r of b || []) list.push(r);
    const seen = new Set();
    const out = [];
    for (const r of list) {
      const id = r && r.id ? Number(r.id) : 0;
      if (!id || seen.has(id)) continue;
      seen.add(id);
      out.push(r);
    }
    out.sort((x, y) => Number(x.id || 0) - Number(y.id || 0));
    return out;
  }

  async getEpisodesUnderFolder(seasonFolder) {
    const resolved = path.resolve(String(seasonFolder || ''));
    if (!resolved) return [];
    const prefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;
    const rows = await this.knexVideo('video_index')
      .select('id', 'path', 'filename', 'media_type', 'is_file', 'nfo_get_state', 'duration')
      .where({ is_file: 1, nfo_get_state: 0 })
      .andWhere('media_type', 'in', ['episod'])
      .andWhere(qb => {
        qb.where('path', resolved).orWhere('path', 'like', `${prefix}%`);
      })
      .orderBy('id', 'asc')
      .catch(() => []);
    return rows || [];
  }

  async getEpisodesInFolder(folder) {
    const resolved = path.resolve(String(folder || ''));
    if (!resolved) return [];
    const rows = await this.knexVideo('video_index')
      .select('id', 'path', 'filename', 'media_type', 'is_file', 'nfo_get_state', 'duration')
      .where({ is_file: 1, nfo_get_state: 0, path: resolved })
      .andWhere('media_type', 'in', ['episod'])
      .orderBy('id', 'asc')
      .catch(() => []);
    return rows || [];
  }

  async processTvRow(row) {
    const parentDir = row && row.path ? String(row.path) : '';
    const folderName = row && row.filename ? String(row.filename) : '';
    if (!parentDir || !folderName) return false;

    if (FileUtil.shouldSkipIndexingFilename(folderName)) {
      await this.markSkipped(row);
      return true;
    }

    const showFolder = path.join(parentDir, folderName);
    try {
      const st = await fs.promises.stat(showFolder);
      if (!st.isDirectory()) return false;
    } catch (_) {
      return false;
    }

    const nfoPath = path.join(showFolder, 'tvshow.nfo');
    if (await hasValidNfo(nfoPath, 'tvshow')) {
      const parsed = await readAndParseNfo(nfoPath);
      const tmdbId = parsed && parsed.tmdbId ? Number(parsed.tmdbId) : 0;
      if (tmdbId) {
        await _updateIndexFromNfoAndArtwork({
          knex: this.knexVideo,
          row,
          baseDir: parentDir,
          searchDir: showFolder,
          nfoPath,
          onlyVideoBase: false,
          seasonNumber: 0,
        });

        const seasons = await this.getSeasonsNeedingWork(showFolder);
        for (const sRow of seasons) {
          await this.processSeasonRow({ tvId: tmdbId, showFolder, showParentDir: parentDir, seasonRow: sRow });
        }

        const episodesInShowFolder = await this.getEpisodesInFolder(showFolder);
        if (episodesInShowFolder && episodesInShowFolder.length > 0) {
          const seasonDetails = await this.tmdb.getSeasonDetails(tmdbId, 1).catch(() => null);
          const episodeDetailsByNumber = new Map();
          const episodes = seasonDetails && Array.isArray(seasonDetails.episodes) ? seasonDetails.episodes : [];
          for (const e of episodes) {
            const en = e && e.episode_number ? Number(e.episode_number) : 0;
            if (en > 0) episodeDetailsByNumber.set(en, e);
          }
          for (const eRow of episodesInShowFolder) {
            const filename = eRow && eRow.filename ? String(eRow.filename) : '';
            const parsedEp = parseEpisodeFromName(filename);
            const episodeNumber = parsedEp && parsedEp.episode ? Number(parsedEp.episode) : 0;
            const preFetched = episodeNumber > 0 ? episodeDetailsByNumber.get(episodeNumber) : null;
            await this.processEpisodeRow({ tvId: tmdbId, seasonNumber: 1, episodeRow: eRow, episodeDetails: preFetched });
          }
        }

        return true;
      }
    }

    const preferTitle = (row.nfo_name ? String(row.nfo_name) : '').trim();
    const fallbackTitle = normalizeNameForNfoGuess(folderName) || folderName;
    const rawTitle = preferTitle || fallbackTitle;

    const attempts = _buildQueryAttemptsFromText(rawTitle);
    if (attempts.length === 0) {
      const q = _cleanSearchText(rawTitle);
      if (q) attempts.push({ query: q, year: 0 });
    }

    let tmdbId = 0;
    for (const a of attempts) {
      const q = a && a.query ? String(a.query) : '';
      if (!q) continue;
      const results = await this.tmdb.searchTv({ query: q });
      const picked = results && results[0] ? results[0] : null;
      const id = picked && picked.id ? Number(picked.id) : 0;
      if (id) {
        tmdbId = id;
        break;
      }
    }
    if (!tmdbId) return false;

    const details = await this.tmdb.getTvDetails(tmdbId);
    if (!details) return false;

    const nfoData = _mapTvToNfo({ client: this.tmdb, tv: details });
    await writeTextIfChanged(nfoPath, buildTvShowNfo(nfoData));

    if (details.poster_path) await _ensureDownloaded(this.tmdb, showFolder, 'poster.jpg', details.poster_path);
    if (details.backdrop_path) await _ensureDownloaded(this.tmdb, showFolder, 'fanart.jpg', details.backdrop_path);
    const logo = _pickLogoPathFromImages(details.images);
    if (logo) await _ensureDownloadedPng(this.tmdb, showFolder, 'logo.png', logo);

    await _updateIndexFromNfoAndArtwork({
      knex: this.knexVideo,
      row,
      baseDir: parentDir,
      searchDir: showFolder,
      nfoPath,
      onlyVideoBase: false,
      seasonNumber: 0,
    });

    const seasons = await this.getSeasonsNeedingWork(showFolder);
    for (const sRow of seasons) {
      await this.processSeasonRow({ tvId: tmdbId, showFolder, showParentDir: parentDir, seasonRow: sRow });
    }

    const episodesInShowFolder = await this.getEpisodesInFolder(showFolder);
    if (episodesInShowFolder && episodesInShowFolder.length > 0) {
      const seasonDetails = await this.tmdb.getSeasonDetails(tmdbId, 1).catch(() => null);
      const episodeDetailsByNumber = new Map();
      const episodes = seasonDetails && Array.isArray(seasonDetails.episodes) ? seasonDetails.episodes : [];
      for (const e of episodes) {
        const en = e && e.episode_number ? Number(e.episode_number) : 0;
        if (en > 0) episodeDetailsByNumber.set(en, e);
      }
      for (const eRow of episodesInShowFolder) {
        const filename = eRow && eRow.filename ? String(eRow.filename) : '';
        const parsedEp = parseEpisodeFromName(filename);
        const episodeNumber = parsedEp && parsedEp.episode ? Number(parsedEp.episode) : 0;
        const preFetched = episodeNumber > 0 ? episodeDetailsByNumber.get(episodeNumber) : null;
        await this.processEpisodeRow({ tvId: tmdbId, seasonNumber: 1, episodeRow: eRow, episodeDetails: preFetched });
      }
    }

    return true;
  }

  async processSeasonRow({ tvId, showFolder, showParentDir, seasonRow }) {
    const seasonName = seasonRow && seasonRow.filename ? String(seasonRow.filename) : '';
    const seasonFolder = path.join(showFolder, seasonName);
    const seasonNumber = parseSeasonNumberFromName(seasonName);
    if (!seasonNumber) return false;
    try {
      const st = await fs.promises.stat(seasonFolder);
      if (!st.isDirectory()) return false;
    } catch (_) {
      return false;
    }

    const nfoPath = path.join(seasonFolder, 'season.nfo');
    const hasSeasonNfo = await hasValidNfo(nfoPath, 'season');

    let seasonDetails = null;
    if (hasSeasonNfo) {
      await _updateIndexFromNfoAndArtwork({
        knex: this.knexVideo,
        row: seasonRow,
        baseDir: showFolder,
        searchDir: seasonFolder,
        nfoPath,
        onlyVideoBase: false,
        seasonNumber,
      });
      seasonDetails = await this.tmdb.getSeasonDetails(tvId, seasonNumber).catch(() => null);
    } else {
      seasonDetails = await this.tmdb.getSeasonDetails(tvId, seasonNumber);
      if (!seasonDetails) return false;

      const nfoData = _mapSeasonToNfo({ client: this.tmdb, tvId: String(tvId), season: seasonDetails });
      await writeTextIfChanged(nfoPath, buildSeasonNfo(nfoData));

      if (seasonDetails.poster_path) await _ensureDownloaded(this.tmdb, seasonFolder, 'poster.jpg', seasonDetails.poster_path);

      await _updateIndexFromNfoAndArtwork({
        knex: this.knexVideo,
        row: seasonRow,
        baseDir: showFolder,
        searchDir: seasonFolder,
        nfoPath,
        onlyVideoBase: false,
        seasonNumber,
      });
    }

    const episodeDetailsByNumber = new Map();
    const episodeList = seasonDetails && Array.isArray(seasonDetails.episodes) ? seasonDetails.episodes : [];
    for (const e of episodeList) {
      const en = e && e.episode_number ? Number(e.episode_number) : 0;
      if (en > 0) episodeDetailsByNumber.set(en, e);
    }

    const episodes = await this.getEpisodesUnderFolder(seasonFolder);
    for (const eRow of episodes) {
      const filename = eRow && eRow.filename ? String(eRow.filename) : '';
      const parsedEp = parseEpisodeFromName(filename);
      const episodeNumber = parsedEp && parsedEp.episode ? Number(parsedEp.episode) : 0;
      const seasonFromName = parsedEp && parsedEp.season ? Number(parsedEp.season) : 0;
      const sn = seasonFromName || Number(seasonNumber || 0) || 1;
      const preFetched = sn === seasonNumber && episodeNumber > 0 ? episodeDetailsByNumber.get(episodeNumber) : null;
      await this.processEpisodeRow({ tvId, seasonNumber, episodeRow: eRow, episodeDetails: preFetched });
    }

    return true;
  }

  async processEpisodeRow({ tvId, seasonNumber, episodeRow, episodeDetails }) {
    const dirPath = episodeRow && episodeRow.path ? String(episodeRow.path) : '';
    const filename = episodeRow && episodeRow.filename ? String(episodeRow.filename) : '';
    if (!dirPath || !filename) return false;

    if (FileUtil.shouldSkipIndexingFilename(filename) || _hasSkipNameHint(path.parse(filename).name) || _shouldSkipByDurationSeconds(episodeRow && episodeRow.duration)) {
      await this.markSkipped(episodeRow);
      return true;
    }

    const full = path.join(dirPath, filename);
    try {
      const st = await fs.promises.stat(full);
      if (!st.isFile()) return false;
    } catch (_) {
      return false;
    }

    let ep = parseEpisodeFromName(filename);
    const episodeNumber = ep && ep.episode ? Number(ep.episode) : 0;
    const seasonFromName = ep && ep.season ? Number(ep.season) : 0;
    const sn = seasonFromName || Number(seasonNumber || 0) || 1;
    if (!sn || !episodeNumber) return false;

    const preFetched = episodeDetails && typeof episodeDetails === 'object' ? episodeDetails : null;
    const preSeason = preFetched && preFetched.season_number ? Number(preFetched.season_number) : 0;
    const preEpisode = preFetched && preFetched.episode_number ? Number(preFetched.episode_number) : 0;
    const details = preFetched && preSeason === sn && preEpisode === episodeNumber ? preFetched : await this.tmdb.getEpisodeDetails(tvId, sn, episodeNumber);
    if (!details) return false;

    const nfoData = _mapEpisodeToNfo({ client: this.tmdb, episode: details });
    const baseName = path.parse(filename).name;
    const nfoPath = path.join(dirPath, `${baseName}.nfo`);
    await writeTextIfChanged(nfoPath, buildEpisodeNfo(nfoData));

    if (details.still_path) {
      await _ensureDownloadedJpeg(this.tmdb, dirPath, `${baseName}.jpg`, details.still_path);
    }

    await _updateIndexFromNfoAndArtwork({
      knex: this.knexVideo,
      row: episodeRow,
      baseDir: dirPath,
      searchDir: dirPath,
      nfoPath,
      videoBaseName: baseName,
      onlyVideoBase: true,
      seasonNumber: 0,
    });

    return true;
  }

  async _processMovieRowByTmdbId(row, tmdbId) {
    const dirPath = row && row.path ? String(row.path) : '';
    const filename = row && row.filename ? String(row.filename) : '';
    if (!dirPath || !filename) return false;
    const mediaType = row && row.media_type ? String(row.media_type).trim() : '';
    const isDiscFolderMovie = mediaType === 'bdmv' || mediaType === 'video_ts';
    const movieFolder = isDiscFolderMovie ? path.join(dirPath, filename) : '';

    if (FileUtil.shouldSkipIndexingFilename(filename) || _hasSkipNameHint(path.parse(filename).name) || _shouldSkipByDurationSeconds(row && row.duration)) {
      await this.markSkipped(row);
      return true;
    }

    try {
      const st = await fs.promises.stat(isDiscFolderMovie ? movieFolder : path.join(dirPath, filename));
      if (isDiscFolderMovie ? !st.isDirectory() : !st.isFile()) return false;
    } catch (_) {
      return false;
    }

    const details = await this.tmdb.getMovieDetails(tmdbId);
    if (!details) return false;

    const nfoData = _mapMovieToNfo({ client: this.tmdb, movie: details });
    const baseName = path.parse(filename).name;
    const nfoPath = isDiscFolderMovie ? path.join(movieFolder, 'movie.nfo') : path.join(dirPath, `${baseName}.nfo`);
    await writeTextIfChanged(nfoPath, buildMovieNfo(nfoData));

    if (details.poster_path) await _ensureDownloadedJpeg(this.tmdb, isDiscFolderMovie ? movieFolder : dirPath, isDiscFolderMovie ? 'poster.jpg' : `${baseName}-post.jpg`, details.poster_path);
    if (details.backdrop_path) await _ensureDownloadedJpeg(this.tmdb, isDiscFolderMovie ? movieFolder : dirPath, isDiscFolderMovie ? 'fanart.jpg' : `${baseName}-fanart.jpg`, details.backdrop_path);
    const logo = _pickLogoPathFromImages(details.images);
    if (logo) {
      await _ensureDownloadedPng(this.tmdb, isDiscFolderMovie ? movieFolder : dirPath, isDiscFolderMovie ? 'logo.png' : `${baseName}-logo.png`, logo);
      const legacy = path.join(isDiscFolderMovie ? movieFolder : dirPath, isDiscFolderMovie ? 'logo.jpg' : `${baseName}-logo.jpg`);
      try {
        if (fs.existsSync(legacy) && fs.statSync(legacy).isFile()) fs.unlinkSync(legacy);
      } catch (_) {}
    }

    await _updateIndexFromNfoAndArtwork({
      knex: this.knexVideo,
      row,
      baseDir: dirPath,
      searchDir: isDiscFolderMovie ? movieFolder : dirPath,
      nfoPath,
      videoBaseName: isDiscFolderMovie ? '' : baseName,
      onlyVideoBase: false,
      seasonNumber: 0,
    });

    return true;
  }

  async _processTvRowByTmdbId(row, tvId) {
    const parentDir = row && row.path ? String(row.path) : '';
    const folderName = row && row.filename ? String(row.filename) : '';
    if (!parentDir || !folderName) return false;

    if (FileUtil.shouldSkipIndexingFilename(folderName)) {
      await this.markSkipped(row);
      return true;
    }

    const showFolder = path.join(parentDir, folderName);
    try {
      const st = await fs.promises.stat(showFolder);
      if (!st.isDirectory()) return false;
    } catch (_) {
      return false;
    }

    const details = await this.tmdb.getTvDetails(tvId);
    if (!details) return false;

    const nfoPath = path.join(showFolder, 'tvshow.nfo');
    const nfoData = _mapTvToNfo({ client: this.tmdb, tv: details });
    await writeTextIfChanged(nfoPath, buildTvShowNfo(nfoData));

    if (details.poster_path) await _ensureDownloaded(this.tmdb, showFolder, 'poster.jpg', details.poster_path);
    if (details.backdrop_path) await _ensureDownloaded(this.tmdb, showFolder, 'fanart.jpg', details.backdrop_path);
    const logo = _pickLogoPathFromImages(details.images);
    if (logo) await _ensureDownloadedPng(this.tmdb, showFolder, 'logo.png', logo);

    await _updateIndexFromNfoAndArtwork({
      knex: this.knexVideo,
      row,
      baseDir: parentDir,
      searchDir: showFolder,
      nfoPath,
      onlyVideoBase: false,
      seasonNumber: 0,
    });

    const seasons = await this.getSeasonsNeedingWork(showFolder);
    for (const sRow of seasons) {
      await this.processSeasonRow({ tvId, showFolder, showParentDir: parentDir, seasonRow: sRow });
    }

    return true;
  }

  async _resolveTvIdFromShowFolder(showFolder) {
    const resolved = path.resolve(String(showFolder || ''));
    if (!resolved) return 0;
    const nfoPath = path.join(resolved, 'tvshow.nfo');
    if (!(await hasValidNfo(nfoPath, 'tvshow'))) return 0;
    const parsed = await readAndParseNfo(nfoPath);
    const tvId = parsed && parsed.tmdbId ? Number(parsed.tmdbId) : 0;
    return tvId > 0 ? tvId : 0;
  }

  async scrapeByIndexId({ indexId, tmdbId = 0 } = {}) {
    const id = Number(indexId || 0) || 0;
    if (!id) return { ok: false };
    const row = await this.knexVideo('video_index')
      .where({ id })
      .first('id', 'path', 'filename', 'media_type', 'is_file', 'nfo_name', 'nfo_get_state', 'duration')
      .catch(() => null);
    if (!row) return { ok: false };

    const mediaType = row.media_type ? String(row.media_type).trim() : '';
    const override = Number(tmdbId || 0) || 0;

    try {
      if (mediaType === 'movie' || mediaType === 'bdmv' || mediaType === 'video_ts') {
        const done = override ? await this._processMovieRowByTmdbId(row, override) : await this.processMovieRow(row);
        if (!done) await this.markFailed(row);
        return { ok: !!done };
      }
      if (mediaType === 'tv') {
        const done = override ? await this._processTvRowByTmdbId(row, override) : await this.processTvRow(row);
        if (!done) await this.markFailed(row);
        return { ok: !!done };
      }
      if (mediaType === 'season') {
        const showFolder = row.path ? String(row.path) : '';
        const seasonNumber = parseSeasonNumberFromName(row.filename);
        if (!showFolder || !seasonNumber) return { ok: false };
        const tvId = override || (await this._resolveTvIdFromShowFolder(showFolder));
        if (!tvId) return { ok: false };
        const done = await this.processSeasonRow({
          tvId,
          showFolder,
          showParentDir: path.dirname(showFolder),
          seasonRow: row,
        });
        if (!done) await this.markFailed(row);
        return { ok: !!done };
      }
      if (mediaType === 'episod') {
        const dirPath = row.path ? String(row.path) : '';
        if (!dirPath) return { ok: false };
        const seasonNumber = parseSeasonNumberFromName(path.basename(dirPath));
        let tvId = override;
        if (!tvId) {
          let cursor = path.resolve(dirPath);
          let found = '';
          for (let i = 0; i < 6; i += 1) {
            const candidate = path.join(cursor, 'tvshow.nfo');
            if (fs.existsSync(candidate)) {
              found = cursor;
              break;
            }
            const next = path.dirname(cursor);
            if (!next || next === cursor) break;
            cursor = next;
          }
          tvId = found ? await this._resolveTvIdFromShowFolder(found) : 0;
        }
        if (!tvId) return { ok: false };
        const done = await this.processEpisodeRow({ tvId, seasonNumber, episodeRow: row });
        if (!done) await this.markFailed(row);
        return { ok: !!done };
      }
      return { ok: false };
    } catch (err) {
      Logger.error('❌ scrapeByIndexId failed', err && err.message ? err.message : err);
      await this.markFailed(row);
      return { ok: false };
    }
  }

  async runOnce({ limit = 5 } = {}) {
    const roots = await this.getPendingRoots(limit);
    if (!roots || roots.length === 0) return { processed: 0, ok: 0 };
    let ok = 0;
    let processed = 0;
    for (const r of roots) {
      console.log('开始获取nfo信息', r.path, r.filename);
      processed += 1;
      try {
        if (r.media_type === 'movie' || r.media_type === 'bdmv' || r.media_type === 'video_ts') {
          const done = await this.processMovieRow(r);
          if (done) ok += 1;
          if (!done) await this.markFailed(r);
        } else if (r.media_type === 'tv') {
          const done = await this.processTvRow(r);
          if (done) ok += 1;
          if (!done) await this.markFailed(r);
        }
      } catch (err) {
        Logger.error('❌ nfoFetch handle failed', err && err.message ? err.message : err);
        await this.markFailed(r);
      }
    }
    return { processed, ok };
  }
}

module.exports = {
  NfoFetchRunner,
};
