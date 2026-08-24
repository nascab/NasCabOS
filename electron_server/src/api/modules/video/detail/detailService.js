const fs = require('fs');
const path = require('path');
const config = require('../../../../config/config');
const tableConfig = require('../../../../db/table/tableConfig');
const dbUtil = require('../../../../db/dbUtil');
const knexUtil = require('../../../../db/knexUtil');
const discContentUtil = require('../../../../utils/discContentUtil');
const nascabAccountUtil = require('../../service/utils/nascabAccountUtil');
const fileService = require('../../file/core/fileService');
const { TmdbClient } = require('../../../../workers/videoIndex/nfoFetchWorker/tmdbClient');
const { parseSeasonNumberFromName } = require('../../../../workers/videoIndex/videoIndexUtil');

function _compareSeasonRows(a, b) {
  const an = parseSeasonNumberFromName(a && a.filename);
  const bn = parseSeasonNumberFromName(b && b.filename);
  if (an > 0 && bn > 0 && an !== bn) return an - bn;
  if (an > 0 && bn <= 0) return -1;
  if (an <= 0 && bn > 0) return 1;
  const as = String(a && a.filename ? a.filename : '');
  const bs = String(b && b.filename ? b.filename : '');
  const c = as.localeCompare(bs);
  if (c !== 0) return c;
  return (Number(a && a.id) || 0) - (Number(b && b.id) || 0);
}

function _sortSeasonRows(seasons) {
  return [...(seasons || [])].sort(_compareSeasonRows);
}

function _resolveArtworkAbsolute({ baseDir, maybeRelative }) {
  const p = maybeRelative === undefined || maybeRelative === null ? '' : String(maybeRelative).trim();
  if (!p) return '';
  if (path.isAbsolute(p)) return p;
  const base = baseDir === undefined || baseDir === null ? '' : String(baseDir).trim();
  if (!base) return '';
  return path.resolve(base, p);
}

function _normalizeIndexRow(row) {
  if (!row || typeof row !== 'object') return row;
  const baseDir = row.path === undefined || row.path === null ? '' : String(row.path).trim();
  const poster = _resolveArtworkAbsolute({ baseDir, maybeRelative: row.poster_path });
  const fanart = _resolveArtworkAbsolute({ baseDir, maybeRelative: row.fanart_path });
  const logo = _resolveArtworkAbsolute({ baseDir, maybeRelative: row.logo_path });
  const fullPath = baseDir && row.filename ? path.join(baseDir, String(row.filename)) : '';
  const playRelPath = row.play_rel_path === undefined || row.play_rel_path === null ? '' : String(row.play_rel_path).trim();
  const playFilePath = row && (row.media_type === 'bdmv' || row.media_type === 'video_ts') && baseDir && playRelPath
    ? path.resolve(fullPath || baseDir, playRelPath)
    : '';
  return {
    ...row,
    poster_path: poster,
    fanart_path: fanart,
    logo_path: logo,
    full_path: fullPath,
    play_file_path: playFilePath,
    first_file_path: row && (row.media_type === 'bdmv' || row.media_type === 'video_ts') && playFilePath ? playFilePath : row.first_file_path,
  };
}

function _isHiddenDiscContentName(name) {
  const normalizedName = String(name || '').trim();
  return normalizedName.startsWith('.');
}

async function _isDiscContentFileVisible(filePath) {
  const resolvedPath = String(filePath || '').trim();
  if (!resolvedPath) return false;
  if (_isHiddenDiscContentName(path.basename(resolvedPath))) return false;
  try {
    const stat = await fs.promises.stat(resolvedPath);
    return Boolean(stat && stat.isFile() && Number(stat.size || 0) >= 1024 * 1024);
  } catch (_) {
    return false;
  }
}

async function _filterDiscContents(items) {
  const sourceItems = Array.isArray(items) ? items : [];
  const filtered = await Promise.all(
    sourceItems.map(async item => {
      if (!item || typeof item !== 'object') return null;

      const displayName = String(item.display_name || '').trim();
      if (_isHiddenDiscContentName(displayName)) return null;

      const itemPath = String(item.path || '').trim();
      if (!(await _isDiscContentFileVisible(itemPath))) return null;

      const playlistSource = Array.isArray(item.playlist) ? item.playlist : [];
      const playlist = (
        await Promise.all(
          playlistSource.map(async entry => {
            if (!entry || typeof entry !== 'object') return null;
            const entryName = String(entry.name || '').trim();
            if (_isHiddenDiscContentName(entryName)) return null;
            const entryPath = String(entry.path || '').trim();
            if (!(await _isDiscContentFileVisible(entryPath))) return null;
            return entry;
          })
        )
      )
        .filter(Boolean)
        .map((entry, index) => ({
          ...entry,
          order_no: index + 1,
        }));

      return {
        ...item,
        order_no: 0,
        playlist,
      };
    })
  );

  return filtered
    .filter(Boolean)
    .map((item, index) => ({
      ...item,
      order_no: index + 1,
    }));
}

async function _resolveDiscContentsForItem(item) {
  if (!item || typeof item !== 'object') return { discType: '', items: [] };
  const mediaType = item.media_type ? String(item.media_type).trim().toLowerCase() : '';

  if (mediaType === 'bdmv') {
    const playFilePath = item.play_file_path ? String(item.play_file_path).trim() : '';
    if (!playFilePath) return { discType: 'bdmv', items: [] };
    return await discContentUtil.getLocalBdmvDiscContentsFromPlayFile(playFilePath).catch(() => ({ discType: 'bdmv', items: [] }));
  }

  if (mediaType === 'video_ts') {
    const playFilePath = item.play_file_path ? String(item.play_file_path).trim() : '';
    if (!playFilePath) return { discType: 'video_ts', items: [] };
    return await discContentUtil.getLocalVideoTsDiscContentsFromPlayFile(playFilePath).catch(() => ({ discType: 'video_ts', items: [] }));
  }

  return { discType: '', items: [] };
}

/** 刷新索引的最近查看时间，供列表按 view_time 排序 */
async function _touchVideoIndexViewTime(knexVideo, indexId) {
  const id = Number(indexId || 0) || 0;
  if (!id) return null;
  const now = new Date();
  try {
    const n = await knexVideo('video_index').where({ id }).update({ view_time: now });
    return Number(n) > 0 ? now : null;
  } catch (_) {
    return null;
  }
}

function _normalizeNonNegativeInt(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.floor(n));
}

async function _collectOpenSkipTargetIds({ knexVideo, item }) {
  const ids = new Set();
  const currentId = Number(item && item.id) || 0;
  if (currentId) ids.add(currentId);
  if (!item || typeof item !== 'object') return Array.from(ids);

  const mediaType = item.media_type ? String(item.media_type).trim().toLowerCase() : '';
  if (mediaType === 'movie' || mediaType === 'episod' || mediaType === 'bdmv' || mediaType === 'video_ts') {
    return Array.from(ids);
  }

  if (mediaType === 'season') {
    const seasonFolder = item.path && item.filename ? path.join(String(item.path), String(item.filename)) : '';
    if (!seasonFolder) return Array.from(ids);
    const rows = await knexVideo('video_index')
      .where({ path: seasonFolder, is_file: 1, media_type: 'episod' })
      .select('id')
      .catch(() => []);
    for (const row of rows || []) {
      const id = Number(row && row.id) || 0;
      if (id) ids.add(id);
    }
    return Array.from(ids);
  }

  if (mediaType === 'tv') {
    const showFolder = item.path && item.filename ? path.join(String(item.path), String(item.filename)) : '';
    if (!showFolder) return Array.from(ids);

    const seasonRows = await knexVideo('video_index')
      .where({ path: showFolder, is_file: 0, media_type: 'season' })
      .select('id', 'filename')
      .catch(() => []);
    const seasonFolders = [];
    for (const row of seasonRows || []) {
      const id = Number(row && row.id) || 0;
      if (id) ids.add(id);
      const name = row && row.filename ? String(row.filename).trim() : '';
      if (name) seasonFolders.push(path.join(showFolder, name));
    }

    const directEpisodeRows = await knexVideo('video_index')
      .where({ path: showFolder, is_file: 1, media_type: 'episod' })
      .select('id')
      .catch(() => []);
    for (const row of directEpisodeRows || []) {
      const id = Number(row && row.id) || 0;
      if (id) ids.add(id);
    }

    if (seasonFolders.length > 0) {
      const episodeRows = await knexVideo('video_index')
        .where({ is_file: 1, media_type: 'episod' })
        .whereIn('path', seasonFolders)
        .select('id')
        .catch(() => []);
      for (const row of episodeRows || []) {
        const id = Number(row && row.id) || 0;
        if (id) ids.add(id);
      }
    }
  }

  return Array.from(ids);
}

async function _getFirstEpisodeRowUnderFolder({ knex, rootFolder, recursive }) {
  const resolved = rootFolder ? path.resolve(String(rootFolder)) : '';
  if (!resolved) return null;

  const prefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;

  return await knex('video_index')
    .where({ is_file: 1, media_type: 'episod' })
    .andWhere(qb => {
      if (recursive) {
        qb.where('path', resolved).orWhere('path', 'like', `${prefix}%`);
      } else {
        qb.where('path', resolved);
      }
    })
    .orderBy('episod_num', 'asc')
    .orderBy('id', 'asc')
    .first()
    .catch(() => null);
}

function _shouldAddFirstFilePath(item) {
  if (!item || typeof item !== 'object') return false;
  const t = item.media_type ? String(item.media_type).trim() : '';
  if (t !== 'tv' && t !== 'season') return false;
  const poster = item.poster_path ? String(item.poster_path).trim() : '';
  const fanart = item.fanart_path ? String(item.fanart_path).trim() : '';
  return !poster && !fanart;
}

function _pickTmdbProfileSize(requested) {
  const reqSize = Math.max(1, Number(requested || 0) || 240);
  const sizes = [45, 92, 154, 185, 342, 500, 780];
  for (const s of sizes) {
    if (s >= reqSize) return s;
  }
  return sizes[sizes.length - 1];
}

function _pickTmdbPosterSize(requested) {
  const reqSize = Math.max(1, Number(requested || 0) || 342);
  const sizes = [92, 154, 185, 342, 500, 780];
  for (const s of sizes) {
    if (s >= reqSize) return s;
  }
  return sizes[sizes.length - 1];
}

function _tmdbProfileImageUrl(profilePath, size) {
  const fp = String(profilePath || '').trim();
  if (!fp) return '';
  const safe = _pickTmdbProfileSize(size);
  const base = `https://image.tmdb.org/t/p/w${safe}`;
  return `${base}${fp.startsWith('/') ? fp : `/${fp}`}`;
}

function _tmdbPosterImageUrl(posterPath, size) {
  const fp = String(posterPath || '').trim();
  if (!fp) return '';
  const safe = _pickTmdbPosterSize(size);
  const base = `https://image.tmdb.org/t/p/w${safe}`;
  return `${base}${fp.startsWith('/') ? fp : `/${fp}`}`;
}

function _maybeConvertTmdbImageUrlToSize(thumbUrl, size) {
  const input = String(thumbUrl || '').trim();
  if (!input) return '';
  let u;
  try {
    u = new URL(input);
  } catch (_) {
    return input;
  }
  if (u.hostname !== 'image.tmdb.org') return input;
  const idx = u.pathname.indexOf('/t/p/');
  if (idx < 0) return input;
  const after = u.pathname.slice(idx + '/t/p/'.length);
  const parts = after.split('/').filter(Boolean);
  if (parts.length < 2) return input;
  const safe = _pickTmdbProfileSize(size);
  parts[0] = `w${safe}`;
  u.pathname = `/t/p/${parts.join('/')}`;
  return u.toString();
}

function _maybeConvertTmdbPosterImageUrlToSize(thumbUrl, size) {
  const input = String(thumbUrl || '').trim();
  if (!input) return '';
  let u;
  try {
    u = new URL(input);
  } catch (_) {
    return input;
  }
  if (u.hostname !== 'image.tmdb.org') return input;
  const idx = u.pathname.indexOf('/t/p/');
  if (idx < 0) return input;
  const after = u.pathname.slice(idx + '/t/p/'.length);
  const parts = after.split('/').filter(Boolean);
  if (parts.length < 2) return input;
  const safe = _pickTmdbPosterSize(size);
  parts[0] = `w${safe}`;
  u.pathname = `/t/p/${parts.join('/')}`;
  return u.toString();
}

function _sanitizeTmdbIdForPath(tmdbId) {
  const id = String(tmdbId || '').trim();
  if (!id) return '';
  if (!/^\d+$/.test(id)) return '';
  return id;
}

let _tmdbClientPromise = null;
let _tmdbClientConfigKey = '';

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

async function _getDetailHistory({ knexVideo, uid, item }) {
  const safeUid = Number(uid || 0) || 0;
  if (!safeUid) return null;
  if (!item || typeof item !== 'object') return null;

  const mediaType = item.media_type ? String(item.media_type).trim() : '';
  const isFile = Number(item.is_file || 0) === 1;
  const fileHash = item.file_hash ? String(item.file_hash).trim() : '';

  if ((isFile || mediaType === 'bdmv' || mediaType === 'video_ts') && fileHash) {
    const pref = await knexVideo('video_play_preference')
      .where({ uid: safeUid, file_hash: fileHash })
      .first()
      .catch(() => null);
    if (!pref) return null;

    const playbackPosition = Number(pref.playback_position || 0) || 0;
    const duration = Number(item.duration || 0) || 0;
    const episodNum = mediaType === 'episod' ? Number(item.episod_num || 0) || 0 : 0;

    return {
      playback_position: playbackPosition,
      duration,
      last_watched_at: pref.last_watched_at,
      episod_num: episodNum > 0 ? episodNum : undefined,
    };
  }

  if (mediaType !== 'tv' && mediaType !== 'season') return null;

  const showFolder = item.path && item.filename ? path.join(String(item.path), String(item.filename)) : '';
  if (!showFolder) return null;

  let episodeFolders = [];
  if (mediaType === 'season') {
    episodeFolders = [showFolder];
  } else {
    const seasons = await knexVideo('video_index')
      .where({ path: showFolder, is_file: 0, media_type: 'season' })
      .select('path', 'filename', 'id')
      .catch(() => []);

    if (seasons && seasons.length > 0) {
      const sortedSeasons = _sortSeasonRows(seasons);
      episodeFolders = sortedSeasons.map(s => (s && s.path && s.filename ? path.join(String(s.path), String(s.filename)) : '')).filter(Boolean);
    } else {
      episodeFolders = [showFolder];
    }
  }

  if (!episodeFolders || episodeFolders.length === 0) return null;

  const pref = await knexVideo('video_play_preference as p')
    .join('video_index as v', 'v.file_hash', 'p.file_hash')
    .where('p.uid', safeUid)
    .andWhere('v.is_file', 1)
    .andWhere('v.media_type', 'episod')
    .whereIn('v.path', episodeFolders)
    .orderBy('p.last_watched_at', 'desc')
    .orderBy('p.id', 'desc')
    .first('p.playback_position', 'p.last_watched_at', 'v.episod_num', 'v.duration')
    .catch(() => null);

  if (!pref) return null;

  const playbackPosition = Number(pref.playback_position || 0) || 0;
  const episodNum = Number(pref.episod_num || 0) || 0;
  const duration = Number(pref.duration || 0) || 0;

  return {
    playback_position: playbackPosition,
    duration,
    last_watched_at: pref.last_watched_at,
    episod_num: episodNum > 0 ? episodNum : undefined,
  };
}

async function _fillFavoriteStateForRows({ knexVideo, uid, rows }) {
  const safeUid = Number(uid || 0) || 0;
  const list = Array.isArray(rows) ? rows : [];
  if (list.length === 0) return;

  for (const r of list) {
    if (r && typeof r === 'object') r.is_favorite = false;
  }
  if (!safeUid) return;

  const ids = list.map(r => Number(r && r.id) || 0).filter(v => v > 0);
  if (ids.length === 0) return;

  const favRows = await knexVideo('video_favorite')
    .where({ uid: safeUid })
    .whereIn('index_id', ids)
    .select('index_id')
    .catch(() => []);

  const favSet = new Set((favRows || []).map(r => Number(r && r.index_id) || 0).filter(v => v > 0));
  for (const r of list) {
    const id = Number(r && r.id) || 0;
    if (r && typeof r === 'object') r.is_favorite = favSet.has(id);
  }
}

class VideoDetailService {
  constructor(knexVideo) {
    this.knexVideo = knexVideo;
  }

  async setOpenSkip({ indexId, openSkipStartSec, openSkipEndSec }) {
    const id = Number(indexId || 0) || 0;
    if (!id) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const row = await this.knexVideo('video_index')
      .where({ id })
      .first()
      .catch(() => null);
    if (!row) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const item = _normalizeIndexRow(row);
    const targetIds = await _collectOpenSkipTargetIds({
      knexVideo: this.knexVideo,
      item,
    });
    const safeTargetIds = targetIds
      .map(v => Number(v) || 0)
      .filter(v => v > 0);
    if (safeTargetIds.length === 0) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const safeStart = _normalizeNonNegativeInt(openSkipStartSec);
    const safeEnd = _normalizeNonNegativeInt(openSkipEndSec);

    await this.knexVideo.transaction(async trx => {
      await trx('video_index')
        .whereIn('id', safeTargetIds)
        .update({
          open_skip_start_sec: safeStart,
          open_skip_end_sec: safeEnd,
        });
    });

    const updated = await this.knexVideo('video_index')
      .where({ id })
      .first()
      .catch(() => null);

    return {
      updated_count: safeTargetIds.length,
      media_type: item.media_type,
      item: _normalizeIndexRow(updated || row),
    };
  }

  async getEpisodesPaged({ indexId, page, pageSize, sortOrder }) {
    const id = Number(indexId || 0) || 0;
    if (!id) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const safePage = Math.max(1, Number(page || 1) || 1);
    const safeLimit = Math.min(200, Math.max(1, Number(pageSize || 50) || 50));
    const order = String(sortOrder || 'asc')
      .trim()
      .toLowerCase();
    const safeOrder = order === 'desc' ? 'desc' : 'asc';

    const row = await this.knexVideo('video_index')
      .where({ id })
      .first()
      .catch(() => null);
    if (!row) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const item = _normalizeIndexRow(row);
    const mediaType = item && item.media_type ? String(item.media_type).trim() : '';

    let episodeFolder = '';
    if (mediaType === 'season') {
      episodeFolder = item.path && item.filename ? path.join(String(item.path), String(item.filename)) : '';
    } else if (mediaType === 'tv') {
      const seasonCount = Math.max(0, Number(item.season_count || 0) || 0);
      if (seasonCount <= 1) {
        const showFolder = item.path && item.filename ? path.join(String(item.path), String(item.filename)) : '';
        if (showFolder) {
          episodeFolder = showFolder;
          const seasonRows = await this.knexVideo('video_index')
            .where({ path: showFolder, is_file: 0, media_type: 'season' })
            .select('*')
            .catch(() => []);
          const firstSeason = seasonRows && seasonRows.length > 0 ? _normalizeIndexRow(_sortSeasonRows(seasonRows)[0]) : null;
          if (firstSeason && firstSeason.full_path) episodeFolder = String(firstSeason.full_path);
        }
      }
    }

    if (!episodeFolder) {
      return {
        items: [],
        pagination: {
          total: 0,
          page: safePage,
          limit: safeLimit,
          totalPages: 0,
          hasNextPage: false,
          hasPrevPage: safePage > 1,
        },
      };
    }

    const base = this.knexVideo('video_index').where({
      path: episodeFolder,
      is_file: 1,
      media_type: 'episod',
    });

    const countRow = await base
      .clone()
      .count({ cnt: '*' })
      .first()
      .catch(() => null);
    const total = Math.max(0, Number((countRow && (countRow.cnt ?? countRow['count(*)'])) || 0) || 0);

    const offset = (safePage - 1) * safeLimit;
    const rows = await base
      .clone()
      .orderBy('episod_num', safeOrder)
      .orderBy('id', 'asc')
      .limit(safeLimit)
      .offset(offset)
      .select('*')
      .catch(() => []);

    const items = (rows || []).map(r => _normalizeIndexRow(r));

    const totalPages = Math.ceil(total / safeLimit);
    return {
      items,
      pagination: {
        total,
        page: safePage,
        limit: safeLimit,
        totalPages,
        hasNextPage: safePage < totalPages,
        hasPrevPage: safePage > 1,
      },
    };
  }

  async getTvPlayInfo({ uid, indexId }) {
    const safeUid = Number(uid || 0) || 0;
    if (!safeUid) {
      const err = new Error('common.UNAUTHORIZED');
      err.statusCode = 401;
      throw err;
    }

    const id = Number(indexId || 0) || 0;
    if (!id) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const row = await this.knexVideo('video_index')
      .where({ id })
      .first()
      .catch(() => null);
    if (!row) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const item = _normalizeIndexRow(row);
    const mediaType = item && item.media_type ? String(item.media_type).trim() : '';

    if (item && Number(item.is_file) === 1 && item.full_path) {
      return {
        playlist: [
          {
            path: String(item.full_path),
            name: (item.nfo_name ? String(item.nfo_name).trim() : '') || (item.filename ? String(item.filename) : ''),
          },
        ],
        initialIndex: 0,
      };
    }

    if ((mediaType === 'bdmv' || mediaType === 'video_ts') && item.play_file_path) {
      return {
        playlist: [
          {
            path: String(item.play_file_path),
            name: (item.nfo_name ? String(item.nfo_name).trim() : '') || (item.filename ? String(item.filename) : ''),
          },
        ],
        initialIndex: 0,
      };
    }

    let episodeFolders = [];
    let episodeRows = [];

    if (mediaType === 'tv') {
      const showFolder = item.path && item.filename ? path.join(String(item.path), String(item.filename)) : '';
      if (showFolder) {
        const seasons = await this.knexVideo('video_index')
          .where({ path: showFolder, is_file: 0, media_type: 'season' })
          .select('path', 'filename', 'id')
          .catch(() => []);

        if (seasons && seasons.length > 0) {
          const sortedSeasons = _sortSeasonRows(seasons);
          for (const s of sortedSeasons) {
            const seasonFolder = s && s.path && s.filename ? path.join(String(s.path), String(s.filename)) : '';
            if (!seasonFolder) continue;
            episodeFolders.push(seasonFolder);
            const rows = await this.knexVideo('video_index')
              .where({ path: seasonFolder, is_file: 1, media_type: 'episod' })
              .orderBy('episod_num', 'asc')
              .orderBy('id', 'asc')
              .select('id', 'path', 'filename', 'file_hash', 'nfo_name', 'episod_num')
              .catch(() => []);
            episodeRows.push(...(rows || []));
          }
        } else {
          episodeFolders = [showFolder];
          const rows = await this.knexVideo('video_index')
            .where({ path: showFolder, is_file: 1, media_type: 'episod' })
            .orderBy('episod_num', 'asc')
            .orderBy('id', 'asc')
            .select('id', 'path', 'filename', 'file_hash', 'nfo_name', 'episod_num')
            .catch(() => []);
          episodeRows = rows || [];
        }
      }
    } else if (mediaType === 'season') {
      const seasonFolder = item.path && item.filename ? path.join(String(item.path), String(item.filename)) : '';
      if (seasonFolder) {
        episodeFolders = [seasonFolder];
        const rows = await this.knexVideo('video_index')
          .where({ path: seasonFolder, is_file: 1, media_type: 'episod' })
          .orderBy('episod_num', 'asc')
          .orderBy('id', 'asc')
          .select('id', 'path', 'filename', 'file_hash', 'nfo_name', 'episod_num')
          .catch(() => []);
        episodeRows = rows || [];
      }
    }

    let initialIndex = 0;
    if (episodeFolders.length > 0 && episodeRows.length > 0) {
      const pref = await this.knexVideo('video_play_preference as p')
        .join('video_index as v', 'v.file_hash', 'p.file_hash')
        .where('p.uid', safeUid)
        .andWhere('v.is_file', 1)
        .andWhere('v.media_type', 'episod')
        .whereIn('v.path', episodeFolders)
        .orderBy('p.last_watched_at', 'desc')
        .orderBy('p.id', 'desc')
        .first('p.file_hash')
        .catch(() => null);

      const fileHash = pref && pref.file_hash ? String(pref.file_hash).trim() : '';
      if (fileHash) {
        const idx = episodeRows.findIndex(r => (r && r.file_hash ? String(r.file_hash) : '') === fileHash);
        if (idx >= 0) initialIndex = idx;
      }
    }

    const playlist = (episodeRows || [])
      .map(r => {
        const normalized = _normalizeIndexRow(r);
        const p = normalized && normalized.full_path ? String(normalized.full_path) : '';
        if (!p) return null;
        const name = (normalized.nfo_name ? String(normalized.nfo_name).trim() : '') || (normalized.filename ? String(normalized.filename) : '');
        return { path: p, name };
      })
      .filter(Boolean);

    return { playlist, initialIndex };
  }

  async getDiscContents({ indexId }) {
    const id = Number(indexId || 0) || 0;
    if (!id) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    const row = await this.knexVideo('video_index').where({ id }).first().catch(() => null);
    if (!row) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    const item = _normalizeIndexRow(row);
    const mediaType = item && item.media_type ? String(item.media_type).trim().toLowerCase() : '';
    if (mediaType !== 'bdmv' && mediaType !== 'video_ts') {
      return { items: [], disc_type: '' };
    }
    const resolved = await _resolveDiscContentsForItem(item);
    const filteredItems = await _filterDiscContents(resolved.items || []);
    return {
      disc_type: resolved.discType || mediaType,
      items: filteredItems,
    };
  }

  async getDiscContentThumbPath({ indexId, internalPath = '', size = 320 }) {
    const id = Number(indexId || 0) || 0;
    if (!id) return '';
    const row = await this.knexVideo('video_index').where({ id }).first().catch(() => null);
    if (!row) return '';
    const item = _normalizeIndexRow(row);
    const mediaType = item && item.media_type ? String(item.media_type).trim().toLowerCase() : '';
    if (mediaType !== 'bdmv' && mediaType !== 'video_ts') return '';

    let targetPath = '';
    if (mediaType === 'bdmv' || mediaType === 'video_ts') {
      const normalizedInternal = String(internalPath || '').replace(/\\/g, '/').replace(/^\/+/, '').trim();
      if (normalizedInternal && item.full_path) {
        targetPath = path.resolve(String(item.full_path), normalizedInternal);
      } else {
        targetPath = item.play_file_path ? String(item.play_file_path).trim() : '';
      }
    }

    if (!targetPath) return '';
    return await fileService.getTinyImgByPath(targetPath, size).catch(() => '');
  }

  async getDetail({ uid, indexId }) {
    const id = Number(indexId || 0) || 0;
    if (!id) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const row = await this.knexVideo('video_index')
      .where({ id })
      .first()
      .catch(() => null);
    if (!row) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const viewNow = await _touchVideoIndexViewTime(this.knexVideo, id);
    const item = _normalizeIndexRow(row);
    if (viewNow) item.view_time = viewNow;
    await _fillFavoriteStateForRows({ knexVideo: this.knexVideo, uid, rows: [item] });
    const mediaType = item && item.media_type ? String(item.media_type).trim() : '';

    let seasonList = [];
    let episodeList = [];

    if (mediaType === 'tv') {
      const showFolder = item.path && item.filename ? path.join(String(item.path), String(item.filename)) : '';
      if (showFolder) {
        const seasonCount = Math.max(0, Number(item.season_count || 0) || 0);
        if (seasonCount > 1) {
          const seasons = await this.knexVideo('video_index')
            .where({ path: showFolder, is_file: 0, media_type: 'season' })
            .select('*')
            .catch(() => []);
          seasonList = _sortSeasonRows(seasons).map(r => _normalizeIndexRow(r));

          await _fillFavoriteStateForRows({ knexVideo: this.knexVideo, uid, rows: seasonList });

          for (const s of seasonList) {
            const poster = s && s.poster_path ? String(s.poster_path).trim() : '';
            if (poster) continue;
            const seasonFolder = s && s.path && s.filename ? path.join(String(s.path), String(s.filename)) : '';
            const firstEp = await _getFirstEpisodeRowUnderFolder({
              knex: this.knexVideo,
              rootFolder: seasonFolder,
              recursive: false,
            });
            const normalized = _normalizeIndexRow(firstEp);
            const fp = normalized && normalized.full_path ? String(normalized.full_path).trim() : '';
            if (fp) s.first_file_path = fp;
          }
        }
      }
    } else if (mediaType === 'season') {
    }

    if (_shouldAddFirstFilePath(item)) {
      const rootFolder =
        mediaType === 'tv'
          ? item.path && item.filename
            ? path.join(String(item.path), String(item.filename))
            : ''
          : mediaType === 'season'
            ? item.path && item.filename
              ? path.join(String(item.path), String(item.filename))
              : ''
            : '';

      const firstEp = await _getFirstEpisodeRowUnderFolder({
        knex: this.knexVideo,
        rootFolder,
        recursive: mediaType === 'tv',
      });
      const normalized = _normalizeIndexRow(firstEp);
      const fp = normalized && normalized.full_path ? String(normalized.full_path).trim() : '';
      if (fp) item.first_file_path = fp;
    }

    const history = await _getDetailHistory({
      knexVideo: this.knexVideo,
      uid,
      item,
    });

    return { item, season_list: seasonList, episode_list: episodeList, history };
  }

  async getOrDownloadPersonJpeg({ tmdbId, size = 240, thumbUrl = '' }) {
    const id = _sanitizeTmdbIdForPath(tmdbId);
    if (!id) return null;

    const safeSize = _pickTmdbProfileSize(size);
    const avatarRoot = typeof config.getNfoAvatarPath === 'function' ? config.getNfoAvatarPath() : '';
    if (!avatarRoot) return null;

    const filePath = path.join(avatarRoot, `${id}_w${safeSize}.jpg`);
    try {
      const st = await fs.promises.stat(filePath);
      if (st && st.isFile()) {
        const buf = await fs.promises.readFile(filePath);
        return { filePath, buffer: buf };
      }
    } catch (_) {}

    let url = '';
    const thumb = String(thumbUrl || '').trim();
    if (thumb) {
      url = _maybeConvertTmdbImageUrlToSize(thumb, safeSize) || thumb;
    } else {
      const tmdb = await _getTmdbClient();
      if (!tmdb || !tmdb.apiToken) return null;
      const person = await tmdb.requestJson(`/3/person/${encodeURIComponent(id)}`, { language: 'zh-CN' }).catch(() => null);
      const profilePath = person && person.profile_path ? String(person.profile_path).trim() : '';
      if (!profilePath) return null;
      url = _tmdbProfileImageUrl(profilePath, safeSize);
      if (!url) return null;
      await fs.promises.mkdir(avatarRoot, { recursive: true });
      const ok = await tmdb.downloadToFile(url, filePath);
      if (!ok) return null;
      const buf = await fs.promises.readFile(filePath);
      return { filePath, buffer: buf };
    }

    if (!url) return null;

    const tmdb = await _getTmdbClient();
    if (!tmdb) return null;
    await fs.promises.mkdir(avatarRoot, { recursive: true });
    const ok = await tmdb.downloadToFile(url, filePath);
    if (!ok) return null;
    const buf = await fs.promises.readFile(filePath);
    return { filePath, buffer: buf };
  }

  async getPersonJpegCacheInfo({ tmdbId, size = 240, thumbUrl = '' }) {
    const id = _sanitizeTmdbIdForPath(tmdbId);
    if (!id) return null;

    const safeSize = _pickTmdbProfileSize(size);
    const avatarRoot = typeof config.getNfoAvatarPath === 'function' ? config.getNfoAvatarPath() : '';
    if (!avatarRoot) return null;

    const filePath = path.join(avatarRoot, `${id}_w${safeSize}.jpg`);
    let exists = false;
    try {
      const st = await fs.promises.stat(filePath);
      exists = !!(st && st.isFile());
    } catch (_) {}

    let url = '';
    const thumb = String(thumbUrl || '').trim();
    if (thumb) {
      url = _maybeConvertTmdbImageUrlToSize(thumb, safeSize) || thumb;
    } else {
      const tmdb = await _getTmdbClient();
      if (tmdb && tmdb.apiToken) {
        const person = await tmdb.requestJson(`/3/person/${encodeURIComponent(id)}`, { language: 'zh-CN' }).catch(() => null);
        const profilePath = person && person.profile_path ? String(person.profile_path).trim() : '';
        if (profilePath) url = _tmdbProfileImageUrl(profilePath, safeSize);
      }
    }

    return { filePath, exists, url };
  }

  async getPosterJpegCacheInfo({ tmdbId, mediaType, size = 342, thumbUrl = '' }) {
    const id = _sanitizeTmdbIdForPath(tmdbId);
    if (!id) return null;

    const mt = String(mediaType || '')
      .trim()
      .toLowerCase();
    if (mt !== 'movie' && mt !== 'tv' && mt !== 'bdmv' && mt !== 'video_ts') return null;

    const safeSize = _pickTmdbPosterSize(size);
    const posterRoot = typeof config.getNfoPosterPath === 'function' ? config.getNfoPosterPath() : '';
    if (!posterRoot) return null;

    const filePath = path.join(posterRoot, `${mt}_${id}_w${safeSize}.jpg`);
    let exists = false;
    try {
      const st = await fs.promises.stat(filePath);
      exists = !!(st && st.isFile());
    } catch (_) {}

    let url = '';
    const thumb = String(thumbUrl || '').trim();
    if (thumb) {
      url = _maybeConvertTmdbPosterImageUrlToSize(thumb, safeSize) || thumb;
    } else {
      const tmdb = await _getTmdbClient();
      if (tmdb && tmdb.apiToken) {
        const endpoint = mt === 'tv' ? `/3/tv/${encodeURIComponent(id)}` : `/3/movie/${encodeURIComponent(id)}`;
        const detail = await tmdb.requestJson(endpoint, { language: 'zh-CN' }).catch(() => null);
        const posterPath = detail && detail.poster_path ? String(detail.poster_path).trim() : '';
        if (posterPath) url = _tmdbPosterImageUrl(posterPath, safeSize);
      }
    }

    return { filePath, exists, url };
  }
}

module.exports = VideoDetailService;
