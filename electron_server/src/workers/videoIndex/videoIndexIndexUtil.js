'use strict';

const fs = require('fs');
const path = require('path');
const FileUtil = require('../../utils/fileUtil');
const VideoFfprobeUtil = require('../../utils/videoFfprobeUtil');
const { readAndParseNfo } = require('./nfoParser');
const { getFirstLetter, isSeasonFolderName, parseEpisodeFromName, parseSeasonNumberFromName, normalizeNameForNfoGuess, isSeasonFolderOfShow } = require('./videoIndexUtil');

function _isImageExt(ext) {
  const e = String(ext || '').toLowerCase();
  return e === '.jpg' || e === '.jpeg' || e === '.png' || e === '.webp';
}

function _normalizeSimpleName(s) {
  return String(s || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '')
    .replace(/[_-]+/g, '');
}

const _POSTER_BASE_NAMES = ['poster', 'folder', 'cover', 'front', 'movie'];
const _FANART_BASE_NAMES = ['fanart', 'backdrop', 'background', 'landscape', 'back'];
const _LOGO_BASE_NAMES = ['logo', 'clearlogo'];

const _ARTWORK_SUFFIXES = ['poster', 'post', 'thumb', 'fanart', 'logo', 'clearlogo'];

function isArtworkFilePath(p) {
  const full = String(p || '');
  if (!full) return false;
  const ext = path.extname(full).toLowerCase();
  if (!_isImageExt(ext)) return false;
  const rawBase = String(path.basename(full, ext) || '')
    .trim()
    .toLowerCase();
  const normalized = _normalizeSimpleName(rawBase);

  for (const suf of _ARTWORK_SUFFIXES) {
    const s = String(suf || '')
      .trim()
      .toLowerCase();
    if (!s) continue;
    if (rawBase === s) return true;
    if (rawBase.endsWith(`-${s}`) || rawBase.endsWith(`_${s}`)) return true;
  }

  return _POSTER_BASE_NAMES.includes(normalized) || _FANART_BASE_NAMES.includes(normalized) || _LOGO_BASE_NAMES.includes(normalized);
}

function isArtworkImageFilePath(p) {
  const full = String(p || '');
  if (!full) return false;
  const ext = path.extname(full).toLowerCase();
  if (!_isImageExt(ext)) return false;
  const name = path.basename(full);
  if (FileUtil.isHideFile(name)) return false;
  return true;
}

function _safeFileExists(baseDir, rel) {
  const r = rel === undefined || rel === null ? '' : String(rel).trim();
  if (!r) return false;
  if (path.isAbsolute(r)) return false;
  const baseResolved = path.resolve(String(baseDir || ''));
  const basePrefix = baseResolved.endsWith(path.sep) ? baseResolved : `${baseResolved}${path.sep}`;
  const full = path.resolve(baseResolved, r);
  if (full !== baseResolved && !full.startsWith(basePrefix)) return false;
  try {
    return fs.existsSync(full) && fs.statSync(full).isFile();
  } catch (_) {
    return false;
  }
}

async function resolveArtworkPaths({ baseDir, searchDir, current = null, videoBaseName = '', onlyVideoBase = false, seasonNumber = 0 }) {
  const base = String(baseDir || '');
  const search = String(searchDir || '');
  if (!base || !search) return { poster_path: '', fanart_path: '', logo_path: '' };

  const cur = current && typeof current === 'object' ? current : {};
  const videoBase = _normalizeSimpleName(videoBaseName);
  const sn = Math.max(0, Number(seasonNumber || 0) || 0);
  const restrictToVideoBase = !!onlyVideoBase && !!videoBase;

  const keepOrEmpty = k => {
    const v = cur[k] === undefined || cur[k] === null ? '' : String(cur[k]).trim();
    if (!v) return '';
    return _safeFileExists(base, v) ? v : '';
  };

  const res = {
    poster_path: keepOrEmpty('poster_path'),
    fanart_path: keepOrEmpty('fanart_path'),
    logo_path: keepOrEmpty('logo_path'),
  };

  const normalizeRelBase = relPath => {
    const rel = relPath === undefined || relPath === null ? '' : String(relPath).trim();
    if (!rel) return '';
    const ext = path.extname(rel).toLowerCase();
    return _normalizeSimpleName(path.basename(rel, ext));
  };

  if (restrictToVideoBase) {
    if (res.poster_path && !normalizeRelBase(res.poster_path).startsWith(videoBase)) res.poster_path = '';
    if (res.fanart_path && !normalizeRelBase(res.fanart_path).startsWith(videoBase)) res.fanart_path = '';
    if (res.logo_path && !normalizeRelBase(res.logo_path).startsWith(videoBase)) res.logo_path = '';
  }

  if (sn === 0 && res.poster_path && res.fanart_path && res.logo_path) return res;

  let entries;
  try {
    entries = await fs.promises.readdir(search, { withFileTypes: true });
  } catch (_) {
    return res;
  }

  const files = [];
  for (const ent of entries || []) {
    if (!ent || !ent.isFile()) continue;
    const name = ent.name;
    const ext = path.extname(name).toLowerCase();
    if (!_isImageExt(ext)) continue;
    files.push({ name, ext, base: _normalizeSimpleName(path.basename(name, ext)) });
  }

  const findFirstMatch = bases => {
    for (const b of bases) {
      const norm = _normalizeSimpleName(b);
      const hit = files.find(f => f.base === norm);
      if (hit) return hit.name;
    }
    return '';
  };

  const makeRel = fileName => {
    const abs = path.resolve(search, fileName);
    const rel = path.relative(base, abs);
    if (!rel || path.isAbsolute(rel)) return '';
    return rel;
  };

  if (sn > 0) {
    const padded = String(sn).padStart(2, '0');
    const seasonPoster = findFirstMatch([`season${padded}-poster`]);
    if (seasonPoster) res.poster_path = makeRel(seasonPoster);
    const seasonFanart = findFirstMatch([`season${padded}-fanart`]);
    if (seasonFanart) res.fanart_path = makeRel(seasonFanart);

    const curPosterBase = res.poster_path ? normalizeRelBase(res.poster_path) : '';
    const curPosterIsShowLevelGeneric = !!res.poster_path && path.dirname(res.poster_path) === '.' && _POSTER_BASE_NAMES.includes(curPosterBase);
    if (!res.poster_path || curPosterIsShowLevelGeneric) {
      const posterCandidates = restrictToVideoBase ? [] : [..._POSTER_BASE_NAMES];
      if (videoBase) posterCandidates.push(`${videoBase}-poster`, `${videoBase}-post`, `${videoBase}-thumb`, videoBase);
      const hit = findFirstMatch(posterCandidates);
      if (hit) res.poster_path = makeRel(hit);
    }
  }

  if (!res.poster_path) {
    const posterCandidates = restrictToVideoBase ? [] : [..._POSTER_BASE_NAMES];
    if (videoBase) posterCandidates.push(`${videoBase}-poster`, `${videoBase}-post`, `${videoBase}-thumb`, videoBase);
    const hit = findFirstMatch(posterCandidates);
    if (hit) res.poster_path = makeRel(hit);
  }
  if (!res.fanart_path) {
    const fanartCandidates = restrictToVideoBase ? [] : [..._FANART_BASE_NAMES];
    if (videoBase) fanartCandidates.push(`${videoBase}-fanart`);
    const hit = findFirstMatch(fanartCandidates);
    if (hit) res.fanart_path = makeRel(hit);
  }
  if (!res.logo_path) {
    const logoCandidates = restrictToVideoBase ? [] : [..._LOGO_BASE_NAMES];
    if (videoBase) logoCandidates.push(`${videoBase}-logo`, `${videoBase}-clearlogo`);
    const hit = findFirstMatch(logoCandidates);
    if (hit) res.logo_path = makeRel(hit);
  }

  return res;
}

async function deleteMissingIndexes({ knex, scanPath }) {
  const root = scanPath ? path.resolve(String(scanPath)) : '';
  if (!root) return;

  const deleteSubtreeByPathPrefix = async targetDir => {
    if (!targetDir) return;
    const prefix = targetDir.endsWith(path.sep) ? targetDir : `${targetDir}${path.sep}`;
    await knex('video_index')
      .where(qb => {
        qb.where('path', targetDir).orWhere('path', 'like', `${prefix}%`);
      })
      .delete()
      .catch(() => {});
  };

  try {
    fs.statSync(root);
  } catch (_) {
    await deleteSubtreeByPathPrefix(root);
    return;
  }

  const rootPrefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
  let lastId = 0;
  let fileDeleteIds = [];

  const flushFileDeletes = async () => {
    if (fileDeleteIds.length === 0) return;
    const ids = fileDeleteIds;
    fileDeleteIds = [];
    await knex('video_index')
      .whereIn('id', ids)
      .delete()
      .catch(() => {});
  };

  while (true) {
    const pageSize = 5000;
    const rows = await knex('video_index')
      .select('id', 'path', 'filename', 'is_file')
      .where(qb => {
        qb.where('path', root).orWhere('path', 'like', `${rootPrefix}%`);
      })
      .andWhere('id', '>', lastId)
      .orderBy('id', 'asc')
      .limit(pageSize)
      .catch(() => []);

    if (!rows || rows.length === 0) break;

    for (const r of rows) {
      const id = r && r.id ? Number(r.id) : 0;
      if (id > lastId) lastId = id;

      const parent = r && r.path ? String(r.path) : '';
      const name = r && r.filename ? String(r.filename) : '';
      if (!parent || !name) {
        if (id) fileDeleteIds.push(id);
        if (fileDeleteIds.length >= 1000) await flushFileDeletes();
        continue;
      }

      const targetPath = path.join(parent, name);
      try {
        fs.statSync(targetPath);
      } catch (err) {
        if (err && err.code && err.code !== 'ENOENT') continue;
        const isFile = Number(r.is_file) === 1;
        if (isFile) {
          if (id) fileDeleteIds.push(id);
          if (fileDeleteIds.length >= 1000) await flushFileDeletes();
        } else {
          if (id) {
            await knex('video_index')
              .where({ id })
              .delete()
              .catch(() => {});
          }
          await deleteSubtreeByPathPrefix(targetPath);
        }
      }
    }

    if (rows.length < pageSize) break;
  }

  await flushFileDeletes();
}

function _safeJoinText(arr) {
  const list = Array.isArray(arr) ? arr.map(s => (s ? String(s) : '')).filter(Boolean) : [];
  return list.join(',');
}

function _safeJsonStringify(v) {
  try {
    return JSON.stringify(v);
  } catch (_) {
    return '[]';
  }
}

function _nfoFieldsFromParsed(parsed) {
  if (!parsed) return null;
  const nfoName = parsed.title ? String(parsed.title) : '';
  const nfoRegions = _safeJoinText(parsed.countries);
  const nfoLanguage = _safeJoinText(parsed.languages);
  const nfoGenres = _safeJoinText(parsed.genres);
  const nfoTags = _safeJoinText(parsed.tags);
  const nfoAlias = _safeJoinText(parsed.aliases);
  const actorsDetailed = Array.isArray(parsed.actorsDetailed) ? parsed.actorsDetailed : [];
  const directorsDetailed = Array.isArray(parsed.directorsDetailed) ? parsed.directorsDetailed : [];
  const actorNames = actorsDetailed.length > 0 ? actorsDetailed.map(p => (p && p.name ? String(p.name) : '')).filter(Boolean) : parsed.actors;
  const directorNames = directorsDetailed.length > 0 ? directorsDetailed.map(p => (p && p.name ? String(p.name) : '')).filter(Boolean) : parsed.directors;

  const nfoActor = _safeJoinText(actorNames);
  const nfoDirector = _safeJoinText(directorNames);
  const releaseDate = parsed.premiered ? String(parsed.premiered).slice(0, 10) : null;

  return {
    nfo_name: nfoName,
    nfo_name_fl: getFirstLetter(nfoName),
    nfo_alias: nfoAlias,
    nfo_tags: nfoTags,
    nfo_regions: nfoRegions,
    nfo_language: nfoLanguage,
    nfo_imdb_id: parsed.imdbId ? String(parsed.imdbId) : '',
    nfo_genres: nfoGenres,
    nfo_release_date: releaseDate || null,
    nfo_storyline: parsed.plot ? String(parsed.plot) : '',
    nfo_score: Number(parsed.rating || 0) || 0,
    nfo_year: Number(parsed.year || 0) || 0,
    nfo_actor: nfoActor,
    nfo_director: nfoDirector,
    nfo_actor_json: _safeJsonStringify(actorsDetailed),
    nfo_director_json: _safeJsonStringify(directorsDetailed),
    nfo_get_state: 1,
  };
}

function buildNfoFieldsFromParsed(parsed) {
  return _nfoFieldsFromParsed(parsed);
}

async function findAndParseNfoForVideo(fullPath) {
  const resolved = String(fullPath || '');
  if (!resolved) return { nfoPath: '', parsed: null };
  const dir = path.dirname(resolved);
  const base = path.parse(resolved).name;
  const dirBase = path.basename(dir);
  const candidates = [path.join(dir, `${base}.nfo`), path.join(dir, 'movie.nfo'), path.join(dir, `${dirBase}.nfo`), path.join(dir, 'tvshow.nfo')];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p) && fs.statSync(p).isFile()) {
        const parsed = await readAndParseNfo(p);
        return { nfoPath: p, parsed };
      }
    } catch (_) {}
  }
  return { nfoPath: '', parsed: null };
}

async function findAndParseNfoForMovieFolder(folderPath) {
  const dir = String(folderPath || '');
  if (!dir) return { nfoPath: '', parsed: null };
  const folderName = path.basename(dir);
  const candidates = [path.join(dir, 'movie.nfo'), path.join(dir, `${folderName}.nfo`)];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p) && fs.statSync(p).isFile()) {
        const parsed = await readAndParseNfo(p);
        return { nfoPath: p, parsed };
      }
    } catch (_) {}
  }
  return { nfoPath: '', parsed: null };
}

async function findAndParseNfoForEpisodeFile(fullPath) {
  const resolved = String(fullPath || '');
  if (!resolved) return { nfoPath: '', parsed: null };
  const dir = path.dirname(resolved);
  const base = path.parse(resolved).name;
  const p = path.join(dir, `${base}.nfo`);
  try {
    if (fs.existsSync(p) && fs.statSync(p).isFile()) {
      const parsed = await readAndParseNfo(p);
      return { nfoPath: p, parsed };
    }
  } catch (_) {}
  return { nfoPath: '', parsed: null };
}

function _emptyNfoFields() {
  return {
    nfo_name: '',
    nfo_name_fl: '',
    nfo_alias: '',
    nfo_tags: '',
    nfo_regions: '',
    nfo_language: '',
    nfo_imdb_id: '',
    nfo_genres: '',
    nfo_release_date: null,
    nfo_storyline: '',
    nfo_score: 0,
    nfo_year: 0,
    nfo_actor: '',
    nfo_director: '',
    nfo_actor_json: '[]',
    nfo_director_json: '[]',
    nfo_get_state: 0,
  };
}

async function findAndParseNfoForTvShowFolder(showFolder) {
  const dir = String(showFolder || '');
  if (!dir) return { nfoPath: '', parsed: null };
  const candidates = [path.join(dir, 'tvshow.nfo'), path.join(dir, `${path.basename(dir)}.nfo`)];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p) && fs.statSync(p).isFile()) {
        const parsed = await readAndParseNfo(p);
        return { nfoPath: p, parsed };
      }
    } catch (_) {}
  }
  return { nfoPath: '', parsed: null };
}

async function findAndParseNfoForSeasonFolder(seasonFolder) {
  const dir = String(seasonFolder || '');
  if (!dir) return { nfoPath: '', parsed: null };
  const candidates = [path.join(dir, 'season.nfo'), path.join(dir, `${path.basename(dir)}.nfo`)];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p) && fs.statSync(p).isFile()) {
        const parsed = await readAndParseNfo(p);
        return { nfoPath: p, parsed };
      }
    } catch (_) {}
  }
  return { nfoPath: '', parsed: null };
}

function _splitIndexKeyText(text) {
  const raw = text === undefined || text === null ? '' : String(text);
  const parts = raw.split(/[,，、|\/；;]+/).map(s => String(s || '').trim());
  const res = [];
  const seen = new Set();
  for (const p of parts) {
    if (!p) continue;
    if (seen.has(p)) continue;
    seen.add(p);
    res.push(p);
  }
  return res;
}

async function syncVideoIndex2KeyFromNfoFields({ knex, indexId, mediaType, nfoRegions, nfoGenres }) {
  const id = Number(indexId || 0) || 0;
  if (!id) return false;
  const mt = mediaType ? String(mediaType) : '';
  if (mt !== 'tv' && mt !== 'movie' && mt !== 'bdmv' && mt !== 'video_ts') return false;

  const rows = [];
  for (const key of _splitIndexKeyText(nfoGenres)) {
    rows.push({ index_id: id, key, key_type: 'genres' });
  }
  for (const key of _splitIndexKeyText(nfoRegions)) {
    rows.push({ index_id: id, key, key_type: 'region' });
  }

  await knex('video_index2key')
    .where({ index_id: id })
    .delete()
    .catch(() => {});

  if (rows.length === 0) return true;

  await knex('video_index2key')
    .insert(rows)
    .onConflict(['index_id', 'key', 'key_type'])
    .ignore()
    .catch(() => {});

  return true;
}

async function upsertIndex(knex, row) {
  if (!row || !row.path || !row.filename) return 0;
  await knex('video_index').insert(row).onConflict(['path', 'filename']).merge(row);
  const existed = await knex('video_index')
    .where({ path: row.path, filename: row.filename })
    .first('id')
    .catch(() => null);
  return existed && existed.id ? Number(existed.id || 0) || 0 : 0;
}

function _toRelativeSafePath(baseDir, targetPath) {
  const base = String(baseDir || '').trim();
  const target = String(targetPath || '').trim();
  if (!base || !target) return '';
  const rel = path.relative(base, target);
  if (!rel || path.isAbsolute(rel) || rel.startsWith(`..${path.sep}`) || rel === '..') return '';
  return rel;
}

function _hasCaseInsensitiveFileInDir(targetDir, expectedName) {
  try {
    const expected = String(expectedName || '').trim().toLowerCase();
    if (!expected) return false;
    const entries = fs.readdirSync(targetDir, { withFileTypes: true });
    return entries.some(ent => ent && ent.isFile && ent.isFile() && String(ent.name || '').trim().toLowerCase() === expected);
  } catch (_) {
    return false;
  }
}

function _hasPlayableFilesInBdmvStreamDir(targetDir) {
  try {
    const streamDir = path.join(targetDir, 'STREAM');
    const entries = fs.readdirSync(streamDir, { withFileTypes: true });
    return entries.some(ent => {
      if (!ent || !ent.isFile || !ent.isFile()) return false;
      const name = String(ent.name || '').trim().toLowerCase();
      return name.endsWith('.m2ts') || name.endsWith('.mts') || name.endsWith('.ssif');
    });
  } catch (_) {
    return false;
  }
}

function getBdmvPaths(folderPath) {
  const folder = folderPath ? path.resolve(String(folderPath)) : '';
  if (!folder) return null;
  const candidates = [
    { discRootDir: folder, bdmvDir: path.join(folder, 'BDMV') },
    { discRootDir: path.join(folder, 'BDROM'), bdmvDir: path.join(folder, 'BDROM', 'BDMV') },
    { discRootDir: path.join(folder, 'BD_ROM'), bdmvDir: path.join(folder, 'BD_ROM', 'BDMV') },
    { discRootDir: path.join(folder, 'BD-ROM'), bdmvDir: path.join(folder, 'BD-ROM', 'BDMV') },
  ];

  for (const candidate of candidates) {
    const hasMarkers =
      _hasCaseInsensitiveFileInDir(candidate.bdmvDir, 'index.bdmv') &&
      _hasCaseInsensitiveFileInDir(candidate.bdmvDir, 'movieobject.bdmv');
    if (!hasMarkers && !_hasPlayableFilesInBdmvStreamDir(candidate.bdmvDir)) continue;
    return {
      folder,
      discRootDir: candidate.discRootDir,
      bdmvDir: candidate.bdmvDir,
      streamDir: path.join(candidate.bdmvDir, 'STREAM'),
      playlistDir: path.join(candidate.bdmvDir, 'PLAYLIST'),
    };
  }
  return null;
}

function getVideoTsPaths(folderPath) {
  const folder = folderPath ? path.resolve(String(folderPath)) : '';
  if (!folder) return null;
  const videoTsDir = path.join(folder, 'VIDEO_TS');
  if (!_hasCaseInsensitiveFileInDir(videoTsDir, 'video_ts.ifo')) return null;
  return {
    folder,
    videoTsDir,
  };
}

async function resolveBdmvMainVideoFile(folderPath) {
  const paths = getBdmvPaths(folderPath);
  if (!paths) return null;
  const { folder, bdmvDir, streamDir } = paths;
  try {
    const bdmvStat = await fs.promises.stat(bdmvDir);
    if (!bdmvStat.isDirectory()) return null;
  } catch (_) {
    return null;
  }

  let entries = [];
  try {
    entries = await fs.promises.readdir(streamDir, { withFileTypes: true });
  } catch (_) {
    entries = [];
  }

  const candidates = [];
  for (const ent of entries || []) {
    if (!ent || !ent.isFile()) continue;
    const name = String(ent.name || '');
    const ext = path.extname(name).toLowerCase();
    if (ext !== '.m2ts' && ext !== '.mts' && ext !== '.ssif') continue;
    const fullPath = path.join(streamDir, name);
    try {
      const stat = await fs.promises.stat(fullPath);
      if (!stat.isFile()) continue;
      candidates.push({ fullPath, size: Number(stat.size || 0) || 0, filename: name });
    } catch (_) {}
  }

  if (candidates.length === 0) {
    const fallback = path.join(bdmvDir, 'index.bdmv');
    try {
      const stat = await fs.promises.stat(fallback);
      if (stat.isFile()) {
        return {
          fullPath: fallback,
          relativePath: _toRelativeSafePath(folder, fallback),
          size: Number(stat.size || 0) || 0,
          filename: path.basename(fallback),
        };
      }
    } catch (_) {}
    return null;
  }

  candidates.sort((a, b) => {
    if (b.size !== a.size) return b.size - a.size;
    return a.filename.localeCompare(b.filename);
  });
  const picked = candidates[0];
  return {
    fullPath: picked.fullPath,
    relativePath: _toRelativeSafePath(folder, picked.fullPath),
    size: picked.size,
    filename: picked.filename,
  };
}

async function resolveVideoTsMainVideoFile(folderPath) {
  const paths = getVideoTsPaths(folderPath);
  if (!paths) return null;
  const { folder, videoTsDir } = paths;
  let entries = [];
  try {
    entries = await fs.promises.readdir(videoTsDir, { withFileTypes: true });
  } catch (_) {
    entries = [];
  }

  const candidates = [];
  for (const ent of entries || []) {
    if (!ent || !ent.isFile()) continue;
    const name = String(ent.name || '');
    const match = /^VTS_(\d{2})_(\d+)\.VOB$/i.exec(name);
    if (!match) continue;
    if (Number(match[2]) <= 0) continue;
    const fullPath = path.join(videoTsDir, name);
    try {
      const stat = await fs.promises.stat(fullPath);
      if (!stat.isFile()) continue;
      candidates.push({
        fullPath,
        size: Number(stat.size || 0) || 0,
        filename: name,
        titleNo: Number(match[1]) || 0,
        partNo: Number(match[2]) || 0,
      });
    } catch (_) {}
  }

  if (candidates.length === 0) return null;
  candidates.sort((a, b) => {
    if (b.size !== a.size) return b.size - a.size;
    if (a.titleNo !== b.titleNo) return a.titleNo - b.titleNo;
    if (a.partNo !== b.partNo) return a.partNo - b.partNo;
    return a.filename.localeCompare(b.filename);
  });
  const picked = candidates[0];
  return {
    fullPath: picked.fullPath,
    relativePath: _toRelativeSafePath(folder, picked.fullPath),
    size: picked.size,
    filename: picked.filename,
  };
}

async function indexTvShowFolder({ knex, showFolder, seasonCount, episodCount }) {
  const resolved = path.resolve(String(showFolder || ''));
  if (!resolved) return false;
  let stat;
  try {
    stat = await fs.promises.stat(resolved);
  } catch {
    return false;
  }
  if (!stat.isDirectory()) return false;

  const parent = path.dirname(resolved);
  const name = path.basename(resolved);

  const existed = await knex('video_index')
    .where({ path: parent, filename: name, is_file: 0 })
    .first('poster_path', 'fanart_path', 'logo_path')
    .catch(() => null);

  const artwork = await resolveArtworkPaths({
    baseDir: parent,
    searchDir: resolved,
    current: existed,
  });

  const { parsed } = await findAndParseNfoForTvShowFolder(resolved);
  const nfoFields = _nfoFieldsFromParsed(parsed) || {};
  const nfoName = nfoFields.nfo_name || normalizeNameForNfoGuess(name) || name;

  const base = {
    path: parent,
    filename: name,
    filename_fl: getFirstLetter(name),
    ext: '',
    is_file: 0,
    file_hash: '',
    media_type: 'tv',
    season_count: Math.max(0, Number(seasonCount || 0) || 0),
    episod_count: Math.max(0, Number(episodCount || 0) || 0),
    episod_num: 0,
    size: 0,
    width: 0,
    height: 0,
    duration: 0,
    nfo_name: nfoName,
    nfo_name_fl: getFirstLetter(nfoName),
    poster_path: artwork.poster_path,
    fanart_path: artwork.fanart_path,
    logo_path: artwork.logo_path,
    create_time: new Date(stat.ctimeMs),
    view_time: null,
    ...nfoFields,
  };

  const indexId = await upsertIndex(knex, base);
  if (indexId && parsed) {
    await syncVideoIndex2KeyFromNfoFields({
      knex,
      indexId,
      mediaType: base.media_type,
      nfoRegions: base.nfo_regions,
      nfoGenres: base.nfo_genres,
    });
  }
  return !!indexId;
}

async function indexSeasonFolder({ knex, seasonFolder, episodCount }) {
  const resolved = path.resolve(String(seasonFolder || ''));
  if (!resolved) return false;
  let stat;
  try {
    stat = await fs.promises.stat(resolved);
  } catch {
    return false;
  }
  if (!stat.isDirectory()) return false;

  const parent = path.dirname(resolved);
  const name = path.basename(resolved);
  const existed = await knex('video_index')
    .where({ path: parent, filename: name, is_file: 0 })
    .first('poster_path', 'fanart_path', 'logo_path')
    .catch(() => null);

  const seasonNumber = parseSeasonNumberFromName(name);
  const artworkFromShowFolder = await resolveArtworkPaths({
    baseDir: parent,
    searchDir: parent,
    current: existed,
    seasonNumber,
  });
  let artworkFromSeasonFolder = await resolveArtworkPaths({
    baseDir: parent,
    searchDir: resolved,
    current: { ...artworkFromShowFolder, poster_path: '' },
    seasonNumber: 0,
  });
  if (!artworkFromSeasonFolder.poster_path && seasonNumber) {
    artworkFromSeasonFolder = await resolveArtworkPaths({
      baseDir: parent,
      searchDir: resolved,
      current: { ...artworkFromShowFolder, poster_path: '' },
      seasonNumber,
    });
  }

  const artwork = {
    poster_path: artworkFromSeasonFolder.poster_path || artworkFromShowFolder.poster_path,
    fanart_path: artworkFromShowFolder.fanart_path || artworkFromSeasonFolder.fanart_path,
    logo_path: artworkFromShowFolder.logo_path || artworkFromSeasonFolder.logo_path,
  };

  const { parsed } = await findAndParseNfoForSeasonFolder(resolved);
  const nfoFields = _nfoFieldsFromParsed(parsed) || {};
  const nfoName = nfoFields.nfo_name || normalizeNameForNfoGuess(name) || name;

  const base = {
    path: parent,
    filename: name,
    filename_fl: getFirstLetter(name),
    ext: '',
    is_file: 0,
    file_hash: '',
    media_type: 'season',
    season_count: 0,
    episod_count: Math.max(0, Number(episodCount || 0) || 0),
    episod_num: 0,
    size: 0,
    width: 0,
    height: 0,
    duration: 0,
    nfo_name: nfoName,
    nfo_name_fl: getFirstLetter(nfoName),
    poster_path: artwork.poster_path,
    fanart_path: artwork.fanart_path,
    logo_path: artwork.logo_path,
    create_time: new Date(stat.ctimeMs),
    view_time: null,
    ...nfoFields,
  };

  const indexId = await upsertIndex(knex, base);
  return !!indexId;
}

async function indexEpisodeFile({ knex, fullPath, dirPath, filename, ext }) {
  const p = String(fullPath || '');
  if (!p) return false;
  let stat;
  try {
    stat = await fs.promises.stat(p);
  } catch {
    return false;
  }
  if (!stat.isFile()) return false;

  const existed = await knex('video_index')
    .where({ path: dirPath, filename, is_file: 1 })
    .first('poster_path', 'fanart_path', 'logo_path')
    .catch(() => null);

  const artwork = await resolveArtworkPaths({
    baseDir: dirPath,
    searchDir: dirPath,
    current: existed,
    videoBaseName: path.parse(filename).name,
    onlyVideoBase: true,
  });

  const fileHash = await FileUtil.getFileHash(p);
  let width = 0;
  let height = 0;
  let duration = 0;
  let cachedRow = null;
  if (fileHash) {
    cachedRow = await knex('video_ffmpeg_info')
      .where({ id: fileHash })
      .first()
      .catch(() => null);
  }

  const cached = cachedRow ? VideoFfprobeUtil.normalizeCacheRow(cachedRow) : null;
  const hasValidCached = !!cached && cached.width > 0 && cached.height > 0 && cached.duration > 0;
  if (hasValidCached) {
    width = cached.width;
    height = cached.height;
    duration = cached.duration;
  } else {
    const probed = await VideoFfprobeUtil.probeVideo(p);
    width = probed.width;
    height = probed.height;
    duration = probed.duration;
    if (fileHash) {
      await VideoFfprobeUtil.upsertFfmpegVideoInfo(knex, fileHash, {
        streamInfo: probed.streamInfo,
        duration,
        format: probed.format,
        size: stat.size,
        mtime: stat.mtimeMs,
        width,
        height,
        create_time: Date.now(),
      }).catch(() => false);
    }
  }

  const { parsed } = await findAndParseNfoForEpisodeFile(p);
  const nfoFields = parsed ? _nfoFieldsFromParsed(parsed) || {} : _emptyNfoFields();

  const fallbackName = normalizeNameForNfoGuess(filename) || path.parse(filename).name;
  const nfoName = parsed ? nfoFields.nfo_name || fallbackName || filename : '';

  // 从文件名解析“第几集”（例如：S01E01、EP01、e01、2、剧名1、第一集、第1集），解析失败则为0
  const parsedEp = parseEpisodeFromName(filename);
  const episodNum = parsedEp && parsedEp.episode ? Number(parsedEp.episode) || 0 : 0;

  const base = {
    path: dirPath,
    filename,
    filename_fl: getFirstLetter(filename),
    ext: ext || '',
    is_file: 1,
    file_hash: fileHash || '',
    media_type: 'episod',
    season_count: 0,
    episod_count: 0,
    episod_num: Math.max(0, episodNum),
    size: Number(stat.size || 0) || 0,
    width,
    height,
    duration,
    nfo_name: nfoName,
    nfo_name_fl: getFirstLetter(nfoName),
    poster_path: artwork.poster_path,
    fanart_path: artwork.fanart_path,
    logo_path: artwork.logo_path,
    create_time: new Date(stat.ctimeMs),
    view_time: null,
    ...nfoFields,
  };

  const indexId = await upsertIndex(knex, base);
  return !!indexId;
}

async function indexMovieFile({ knex, fullPath, dirPath, filename, ext }) {
  const p = String(fullPath || '');
  if (!p) return false;
  let stat;
  try {
    stat = await fs.promises.stat(p);
  } catch {
    return false;
  }
  if (!stat.isFile()) return false;

  const existed = await knex('video_index')
    .where({ path: dirPath, filename, is_file: 1 })
    .first('poster_path', 'fanart_path', 'logo_path')
    .catch(() => null);

  const artwork = await resolveArtworkPaths({
    baseDir: dirPath,
    searchDir: dirPath,
    current: existed,
    videoBaseName: path.parse(filename).name,
  });

  const fileHash = await FileUtil.getFileHash(p);
  let width = 0;
  let height = 0;
  let duration = 0;
  let cachedRow = null;
  if (fileHash) {
    cachedRow = await knex('video_ffmpeg_info')
      .where({ id: fileHash })
      .first()
      .catch(() => null);
  }

  const cached = cachedRow ? VideoFfprobeUtil.normalizeCacheRow(cachedRow) : null;
  const hasValidCached = !!cached && cached.width > 0 && cached.height > 0 && cached.duration > 0;
  if (hasValidCached) {
    width = cached.width;
    height = cached.height;
    duration = cached.duration;
  } else {
    const probed = await VideoFfprobeUtil.probeVideo(p);
    width = probed.width;
    height = probed.height;
    duration = probed.duration;
    if (fileHash) {
      await VideoFfprobeUtil.upsertFfmpegVideoInfo(knex, fileHash, {
        streamInfo: probed.streamInfo,
        duration,
        format: probed.format,
        size: stat.size,
        mtime: stat.mtimeMs,
        width,
        height,
        create_time: Date.now(),
      }).catch(() => false);
    }
  }

  const { parsed } = await findAndParseNfoForVideo(p);
  const nfoFields = _nfoFieldsFromParsed(parsed) || {};

  const baseName = path.parse(filename).name;
  const fallbackName = normalizeNameForNfoGuess(baseName) || baseName;
  const nfoName = nfoFields.nfo_name || fallbackName || baseName;

  const base = {
    path: dirPath,
    filename,
    filename_fl: getFirstLetter(filename),
    ext: ext || '',
    is_file: 1,
    file_hash: fileHash || '',
    media_type: 'movie',
    season_count: 0,
    episod_count: 0,
    episod_num: 0,
    size: Number(stat.size || 0) || 0,
    width,
    height,
    duration,
    nfo_name: nfoName,
    nfo_name_fl: getFirstLetter(nfoName),
    poster_path: artwork.poster_path,
    fanart_path: artwork.fanart_path,
    logo_path: artwork.logo_path,
    create_time: new Date(stat.ctimeMs),
    view_time: null,
    ...nfoFields,
  };

  const indexId = await upsertIndex(knex, base);
  if (indexId && parsed) {
    await syncVideoIndex2KeyFromNfoFields({
      knex,
      indexId,
      mediaType: base.media_type,
      nfoRegions: base.nfo_regions,
      nfoGenres: base.nfo_genres,
    });
  }
  return !!indexId;
}

async function indexBdmvFolder({ knex, folderPath, dirPath, filename }) {
  const folder = String(folderPath || '');
  if (!folder || !dirPath || !filename) return false;
  let stat;
  try {
    stat = await fs.promises.stat(folder);
  } catch {
    return false;
  }
  if (!stat.isDirectory()) return false;

  const playable = await resolveBdmvMainVideoFile(folder);
  if (!playable || !playable.fullPath || !playable.relativePath) return false;

  const existed = await knex('video_index')
    .where({ path: dirPath, filename, is_file: 0 })
    .first('poster_path', 'fanart_path', 'logo_path')
    .catch(() => null);

  const artwork = await resolveArtworkPaths({
    baseDir: dirPath,
    searchDir: folder,
    current: existed,
  });

  const fileHash = await FileUtil.getFileHash(playable.fullPath);
  let width = 0;
  let height = 0;
  let duration = 0;
  let cachedRow = null;
  if (fileHash) {
    cachedRow = await knex('video_ffmpeg_info')
      .where({ id: fileHash })
      .first()
      .catch(() => null);
  }

  const cached = cachedRow ? VideoFfprobeUtil.normalizeCacheRow(cachedRow) : null;
  const hasValidCached = !!cached && cached.width > 0 && cached.height > 0 && cached.duration > 0;
  if (hasValidCached) {
    width = cached.width;
    height = cached.height;
    duration = cached.duration;
  } else {
    const probed = await VideoFfprobeUtil.probeVideo(playable.fullPath);
    width = probed.width;
    height = probed.height;
    duration = probed.duration;
    if (fileHash) {
      await VideoFfprobeUtil.upsertFfmpegVideoInfo(knex, fileHash, {
        streamInfo: probed.streamInfo,
        duration,
        format: probed.format,
        size: playable.size,
        mtime: stat.mtimeMs,
        width,
        height,
        create_time: Date.now(),
      }).catch(() => false);
    }
  }

  const { parsed } = await findAndParseNfoForMovieFolder(folder);
  const nfoFields = _nfoFieldsFromParsed(parsed) || {};
  const fallbackName = normalizeNameForNfoGuess(filename) || filename;
  const nfoName = nfoFields.nfo_name || fallbackName || filename;

  const base = {
    path: dirPath,
    filename,
    filename_fl: getFirstLetter(filename),
    ext: '.bdmv',
    is_file: 0,
    file_hash: fileHash || '',
    play_rel_path: playable.relativePath,
    media_type: 'bdmv',
    season_count: 0,
    episod_count: 0,
    episod_num: 0,
    size: Number(playable.size || 0) || 0,
    width,
    height,
    duration,
    nfo_name: nfoName,
    nfo_name_fl: getFirstLetter(nfoName),
    poster_path: artwork.poster_path,
    fanart_path: artwork.fanart_path,
    logo_path: artwork.logo_path,
    create_time: new Date(stat.ctimeMs),
    view_time: null,
    ...nfoFields,
  };

  const indexId = await upsertIndex(knex, base);
  const bdmvSubtrees = [
    path.join(folder, 'BDMV'),
    path.join(folder, 'BDROM', 'BDMV'),
    path.join(folder, 'BD_ROM', 'BDMV'),
    path.join(folder, 'BD-ROM', 'BDMV'),
  ];
  for (const subtree of bdmvSubtrees) {
    const prefix = subtree.endsWith(path.sep) ? subtree : `${subtree}${path.sep}`;
    await knex('video_index')
      .where('is_file', 1)
      .andWhere(qb => {
        qb.where('path', subtree).orWhere('path', 'like', `${prefix}%`);
      })
      .delete()
      .catch(() => {});
  }
  if (indexId && parsed) {
    await syncVideoIndex2KeyFromNfoFields({
      knex,
      indexId,
      mediaType: base.media_type,
      nfoRegions: base.nfo_regions,
      nfoGenres: base.nfo_genres,
    });
  }
  return !!indexId;
}

async function indexVideoTsFolder({ knex, folderPath, dirPath, filename }) {
  const folder = String(folderPath || '');
  if (!folder || !dirPath || !filename) return false;
  let stat;
  try {
    stat = await fs.promises.stat(folder);
  } catch {
    return false;
  }
  if (!stat.isDirectory()) return false;

  const playable = await resolveVideoTsMainVideoFile(folder);
  if (!playable || !playable.fullPath || !playable.relativePath) return false;

  const existed = await knex('video_index')
    .where({ path: dirPath, filename, is_file: 0 })
    .first('poster_path', 'fanart_path', 'logo_path')
    .catch(() => null);

  const artwork = await resolveArtworkPaths({
    baseDir: dirPath,
    searchDir: folder,
    current: existed,
  });

  const fileHash = await FileUtil.getFileHash(playable.fullPath);
  let width = 0;
  let height = 0;
  let duration = 0;
  let cachedRow = null;
  if (fileHash) {
    cachedRow = await knex('video_ffmpeg_info').where({ id: fileHash }).first().catch(() => null);
  }
  const cached = cachedRow ? VideoFfprobeUtil.normalizeCacheRow(cachedRow) : null;
  const hasValidCached = !!cached && cached.width > 0 && cached.height > 0 && cached.duration > 0;
  if (hasValidCached) {
    width = cached.width;
    height = cached.height;
    duration = cached.duration;
  } else {
    const probed = await VideoFfprobeUtil.probeVideo(playable.fullPath);
    width = probed.width;
    height = probed.height;
    duration = probed.duration;
    if (fileHash) {
      await VideoFfprobeUtil.upsertFfmpegVideoInfo(knex, fileHash, {
        streamInfo: probed.streamInfo,
        duration,
        format: probed.format,
        size: playable.size,
        mtime: stat.mtimeMs,
        width,
        height,
        create_time: Date.now(),
      }).catch(() => false);
    }
  }

  const { parsed } = await findAndParseNfoForMovieFolder(folder);
  const nfoFields = _nfoFieldsFromParsed(parsed) || {};
  const fallbackName = normalizeNameForNfoGuess(filename) || filename;
  const nfoName = nfoFields.nfo_name || fallbackName || filename;

  const base = {
    path: dirPath,
    filename,
    filename_fl: getFirstLetter(filename),
    ext: '.video_ts',
    is_file: 0,
    file_hash: fileHash || '',
    play_rel_path: playable.relativePath,
    media_type: 'video_ts',
    season_count: 0,
    episod_count: 0,
    episod_num: 0,
    size: Number(playable.size || 0) || 0,
    width,
    height,
    duration,
    nfo_name: nfoName,
    nfo_name_fl: getFirstLetter(nfoName),
    poster_path: artwork.poster_path,
    fanart_path: artwork.fanart_path,
    logo_path: artwork.logo_path,
    create_time: new Date(stat.ctimeMs),
    view_time: null,
    ...nfoFields,
  };

  const indexId = await upsertIndex(knex, base);
  const subtree = path.join(folder, 'VIDEO_TS');
  const prefix = subtree.endsWith(path.sep) ? subtree : `${subtree}${path.sep}`;
  await knex('video_index')
    .where('is_file', 1)
    .andWhere(qb => {
      qb.where('path', subtree).orWhere('path', 'like', `${prefix}%`);
    })
    .delete()
    .catch(() => {});

  if (indexId && parsed) {
    await syncVideoIndex2KeyFromNfoFields({
      knex,
      indexId,
      mediaType: base.media_type,
      nfoRegions: base.nfo_regions,
      nfoGenres: base.nfo_genres,
    });
  }
  return !!indexId;
}

function classifyVideo({ dirPath, filename, parsedNfo }) {
  const nfoType = parsedNfo && parsedNfo.type ? String(parsedNfo.type) : '';
  //先根据nfo类型判断
  if (nfoType === 'episodedetails') return { kind: 'episode' };
  if (nfoType === 'movie') return { kind: 'movie' };

  const parentName = path.basename(String(dirPath || ''));
  const grandParentName = path.basename(path.dirname(String(dirPath || '')));
  //判断文件名是不是某一集的名字 是的话判定为剧集
  const epFromName = parseEpisodeFromName(filename);
  if (epFromName) return { kind: 'episode' };
  //判断父文件夹或者祖父文件夹是不是剧集文件夹 是的话判定为剧集
  if (isSeasonFolderName(parentName)) return { kind: 'episode' };
  if (isSeasonFolderName(grandParentName)) return { kind: 'episode' };
  //都不是 判定为电影
  return { kind: 'movie' };
}

function getTvFoldersFromEpisode({ fullPath }) {
  const dir = path.dirname(String(fullPath || ''));
  const parent = dir;
  const parentName = path.basename(parent);
  if (isSeasonFolderName(parentName)) {
    const showFolder = path.dirname(parent);
    const showName = path.basename(showFolder);

    // 检查季文件夹名是否与剧名存在包含关系（避免不同电视剧的季文件夹被误识别）
    if (isSeasonFolderOfShow(parentName, showName)) {
      return { showFolder, seasonFolder: parent };
    }

    // 没有包含关系，不视为该剧的季文件夹，将季文件夹视为剧级文件夹
    return { showFolder: parent, seasonFolder: '' };
  }
  return { showFolder: parent, seasonFolder: '' };
}

function buildSeasonKey(seasonFolder) {
  const resolved = path.resolve(String(seasonFolder || ''));
  const parent = path.dirname(resolved);
  const name = path.basename(resolved);
  return `${parent}||${name}`;
}

function buildShowKey(showFolder) {
  const resolved = path.resolve(String(showFolder || ''));
  const parent = path.dirname(resolved);
  const name = path.basename(resolved);
  return `${parent}||${name}`;
}

module.exports = {
  isArtworkImageFilePath,
  deleteMissingIndexes,
  findAndParseNfoForVideo,
  classifyVideo,
  getTvFoldersFromEpisode,
  buildShowKey,
  buildSeasonKey,
  parseSeasonNumberFromName,
  isSeasonFolderName,
  isArtworkFilePath,
  resolveArtworkPaths,
  buildNfoFieldsFromParsed,
  syncVideoIndex2KeyFromNfoFields,
  indexTvShowFolder,
  indexSeasonFolder,
  indexEpisodeFile,
  indexMovieFile,
  findAndParseNfoForMovieFolder,
  getBdmvPaths,
  getVideoTsPaths,
  resolveBdmvMainVideoFile,
  resolveVideoTsMainVideoFile,
  indexBdmvFolder,
  indexVideoTsFolder,
};
