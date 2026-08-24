const fs = require('fs');
const path = require('path');
const config = require('../../../../config/config');

async function _unlinkIfExists(filePath) {
  const p = filePath === undefined || filePath === null ? '' : String(filePath).trim();
  if (!p) return false;
  try {
    await fs.promises.unlink(p);
    return true;
  } catch (_) {
    return false;
  }
}

function _isVideoFilename(name) {
  const n = name === undefined || name === null ? '' : String(name).trim();
  if (!n) return false;
  const ext = path.extname(n).toLowerCase();
  if (!ext) return false;
  if (typeof config.getFileType === 'function') {
    return config.getFileType(ext) === 'video';
  }
  return ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v'].includes(ext);
}

async function _cleanupEpisodeSidecarsInFolder(folderPath) {
  const folder = folderPath === undefined || folderPath === null ? '' : String(folderPath).trim();
  if (!folder) return 0;

  let entries = [];
  try {
    entries = await fs.promises.readdir(folder, { withFileTypes: true });
  } catch (_) {
    entries = [];
  }

  const videoFiles = (entries || [])
    .filter(e => e && e.isFile && e.isFile())
    .map(e => String(e.name || '').trim())
    .filter(n => _isVideoFilename(n));

  let deleted = 0;
  const deletedPaths = [];
  for (const vf of videoFiles) {
    const baseName = path.parse(vf).name;
    if (!baseName) continue;
    const candidates = [
      path.join(folder, `${baseName}.nfo`),
      path.join(folder, `${baseName}-poster.nfo`),
      path.join(folder, `${baseName}-post.jpg`),
      path.join(folder, `${baseName}-poster.jpg`),
      path.join(folder, `${baseName}-fanart.jpg`),
      path.join(folder, `${baseName}-fanart.png`),
      path.join(folder, `${baseName}-logo.png`),
      path.join(folder, `${baseName}-logo.jpg`),
      path.join(folder, `${baseName}.jpg`),
    ];
    for (const fp of candidates) {
      if (await _unlinkIfExists(fp)) {
        deleted += 1;
        deletedPaths.push(fp);
      }
    }
  }
  return { deleted, deletedPaths };
}

async function _walkFolders(rootFolder, maxDepth, onFolder) {
  const root = rootFolder === undefined || rootFolder === null ? '' : String(rootFolder).trim();
  if (!root) return;

  const depthLimit = Math.max(0, Number(maxDepth || 0) || 0);
  const queue = [{ folder: root, depth: 0 }];

  while (queue.length > 0) {
    const item = queue.shift();
    if (!item) continue;
    const folder = item.folder;
    const depth = Number(item.depth || 0) || 0;

    await onFolder(folder);

    if (depth >= depthLimit) continue;
    let entries = [];
    try {
      entries = await fs.promises.readdir(folder, { withFileTypes: true });
    } catch (_) {
      entries = [];
    }
    for (const e of entries || []) {
      if (!e || !e.isDirectory || !e.isDirectory()) continue;
      const name = String(e.name || '').trim();
      if (!name) continue;
      queue.push({ folder: path.join(folder, name), depth: depth + 1 });
    }
  }
}

async function cleanupTvTree(tvFolder) {
  const folder = tvFolder === undefined || tvFolder === null ? '' : String(tvFolder).trim();
  if (!folder) return { deleted: 0, deletedPaths: [] };

  let deleted = 0;
  const deletedPaths = [];

  const showLevelCandidates = [path.join(folder, 'tvshow.nfo'), path.join(folder, 'poster.jpg'), path.join(folder, 'fanart.jpg'), path.join(folder, 'logo.png'), path.join(folder, 'logo.jpg')];
  for (const fp of showLevelCandidates) {
    if (await _unlinkIfExists(fp)) {
      deleted += 1;
      deletedPaths.push(fp);
    }
  }

  let rootEntries = [];
  try {
    rootEntries = await fs.promises.readdir(folder, { withFileTypes: true });
  } catch (_) {
    rootEntries = [];
  }

  for (const e of rootEntries || []) {
    if (!e || !e.isFile || !e.isFile()) continue;
    const name = String(e.name || '').trim();
    if (!name) continue;
    const fp = path.join(folder, name);
    if (/^season\d{1,2}-poster\.(jpg|jpeg|png)$/i.test(name)) {
      if (await _unlinkIfExists(fp)) {
        deleted += 1;
        deletedPaths.push(fp);
      }
    }
    if (/^season\d{1,2}-fanart\.(jpg|jpeg|png)$/i.test(name)) {
      if (await _unlinkIfExists(fp)) {
        deleted += 1;
        deletedPaths.push(fp);
      }
    }
    if (/^season\d{1,2}\.nfo$/i.test(name)) {
      if (await _unlinkIfExists(fp)) {
        deleted += 1;
        deletedPaths.push(fp);
      }
    }
  }

  await _walkFolders(folder, 4, async dir => {
    const sub = await _cleanupEpisodeSidecarsInFolder(dir);
    deleted += sub.deleted;
    if (sub.deletedPaths && sub.deletedPaths.length) deletedPaths.push(...sub.deletedPaths);
    const seasonLevelCandidates = [path.join(dir, 'season.nfo'), path.join(dir, 'poster.jpg'), path.join(dir, 'fanart.jpg'), path.join(dir, 'logo.png'), path.join(dir, 'logo.jpg')];
    for (const fp of seasonLevelCandidates) {
      if (await _unlinkIfExists(fp)) {
        deleted += 1;
        deletedPaths.push(fp);
      }
    }
  });

  return { deleted, deletedPaths };
}

async function cleanupMovieOrEpisode({ dirPath, filename }) {
  const dir = dirPath === undefined || dirPath === null ? '' : String(dirPath).trim();
  const fn = filename === undefined || filename === null ? '' : String(filename).trim();
  if (!dir || !fn) return { deleted: 0, deletedPaths: [] };
  const baseName = path.parse(fn).name;
  if (!baseName) return { deleted: 0, deletedPaths: [] };

  const candidates = [
    path.join(dir, `${baseName}.nfo`),
    path.join(dir, `${baseName}-poster.nfo`),
    path.join(dir, `${baseName}-post.jpg`),
    path.join(dir, `${baseName}-poster.jpg`),
    path.join(dir, `${baseName}-fanart.jpg`),
    path.join(dir, `${baseName}-fanart.png`),
    path.join(dir, `${baseName}-logo.png`),
    path.join(dir, `${baseName}-logo.jpg`),
    path.join(dir, `${baseName}.jpg`),
  ];
  let deleted = 0;
  const deletedPaths = [];
  for (const fp of candidates) {
    if (await _unlinkIfExists(fp)) {
      deleted += 1;
      deletedPaths.push(fp);
    }
  }
  return { deleted, deletedPaths };
}

async function cleanupDiscMovieFolder({ dirPath, filename }) {
  const dir = dirPath === undefined || dirPath === null ? '' : String(dirPath).trim();
  const fn = filename === undefined || filename === null ? '' : String(filename).trim();
  if (!dir || !fn) return { deleted: 0, deletedPaths: [] };
  const movieFolder = path.join(dir, fn);
  const candidates = [
    path.join(movieFolder, 'movie.nfo'),
    path.join(movieFolder, 'poster.jpg'),
    path.join(movieFolder, 'fanart.jpg'),
    path.join(movieFolder, 'fanart.png'),
    path.join(movieFolder, 'logo.png'),
    path.join(movieFolder, 'logo.jpg'),
  ];
  let deleted = 0;
  const deletedPaths = [];
  for (const fp of candidates) {
    if (await _unlinkIfExists(fp)) {
      deleted += 1;
      deletedPaths.push(fp);
    }
  }
  return { deleted, deletedPaths };
}

async function _markTvTreePending(knexVideo, tvFolder) {
  if (!knexVideo) return false;
  const folder = tvFolder ? path.resolve(String(tvFolder)) : '';
  if (!folder) return false;

  const parentDir = path.dirname(folder);
  const folderName = path.basename(folder);
  if (parentDir && folderName) {
    await knexVideo('video_index')
      .where({ path: parentDir, filename: folderName, is_file: 0, media_type: 'tv' })
      .update({ nfo_get_state: 0 })
      .catch(() => {});
  }

  const prefix = folder.endsWith(path.sep) ? folder : `${folder}${path.sep}`;

  await knexVideo('video_index')
    .where({ path: folder, is_file: 0, media_type: 'season' })
    .update({ nfo_get_state: 0 })
    .catch(() => {});

  await knexVideo('video_index')
    .where({ is_file: 1, media_type: 'episod' })
    .andWhere(qb => {
      qb.where('path', folder).orWhere('path', 'like', `${prefix}%`);
    })
    .update({ nfo_get_state: 0 })
    .catch(() => {});

  return true;
}

async function _markSingleIndexPending(knexVideo, indexId) {
  const id = Number(indexId || 0) || 0;
  if (!id || !knexVideo) return false;
  await knexVideo('video_index')
    .where({ id })
    .update({ nfo_get_state: 0 })
    .catch(() => {});
  return true;
}

function _buildClearNfoPatch() {
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
  };
}

async function _clearNfoFieldsForTvTree(knexVideo, tvFolder) {
  if (!knexVideo) return false;
  const folder = tvFolder ? path.resolve(String(tvFolder)) : '';
  if (!folder) return false;

  const parentDir = path.dirname(folder);
  const folderName = path.basename(folder);
  const prefix = folder.endsWith(path.sep) ? folder : `${folder}${path.sep}`;

  const patch = _buildClearNfoPatch();

  const tvRow = await knexVideo('video_index')
    .where({ path: parentDir, filename: folderName, is_file: 0, media_type: 'tv' })
    .first('id')
    .catch(() => null);
  const tvId = tvRow && tvRow.id ? Number(tvRow.id) : 0;

  if (tvId) {
    await knexVideo('video_index')
      .where({ id: tvId })
      .update(patch)
      .catch(() => {});
    await knexVideo('video_index2key')
      .where({ index_id: tvId })
      .delete()
      .catch(() => {});
  }

  await knexVideo('video_index')
    .where({ path: folder, is_file: 0, media_type: 'season' })
    .update(patch)
    .catch(() => {});

  await knexVideo('video_index')
    .where({ is_file: 1, media_type: 'episod' })
    .andWhere(qb => {
      qb.where('path', folder).orWhere('path', 'like', `${prefix}%`);
    })
    .update(patch)
    .catch(() => {});

  return true;
}

async function _clearNfoFieldsForSingleIndex(knexVideo, indexId) {
  const id = Number(indexId || 0) || 0;
  if (!id || !knexVideo) return false;
  const patch = _buildClearNfoPatch();
  await knexVideo('video_index')
    .where({ id })
    .update(patch)
    .catch(() => {});
  await knexVideo('video_index2key')
    .where({ index_id: id })
    .delete()
    .catch(() => {});
  return true;
}

async function resolveTvIndexIdIfSeason(knexVideo, indexId) {
  const id = Number(indexId || 0) || 0;
  if (!id) return 0;
  if (!knexVideo) return id;

  const row = await knexVideo('video_index')
    .where({ id })
    .first('id', 'path', 'filename', 'media_type', 'is_file')
    .catch(() => null);
  if (!row) return id;
  const mt = row.media_type ? String(row.media_type).trim() : '';
  if (mt !== 'season') return id;

  const tvFolder = row.path ? String(row.path).trim() : '';
  if (!tvFolder) return id;
  const tvParentDir = path.dirname(tvFolder);
  const tvFolderName = path.basename(tvFolder);
  if (!tvParentDir || !tvFolderName) return id;

  const tvRow = await knexVideo('video_index')
    .where({ path: tvParentDir, filename: tvFolderName, is_file: 0, media_type: 'tv' })
    .first('id')
    .catch(() => null);
  const tvId = tvRow && tvRow.id ? Number(tvRow.id) : 0;
  return tvId || id;
}

async function cleanupByIndexId(knexVideo, indexId) {
  const id = Number(indexId || 0) || 0;
  if (!id || !knexVideo) return { deleted: 0, deletedPaths: [], indexId: id };

  const resolvedId = await resolveTvIndexIdIfSeason(knexVideo, id);
  const row = await knexVideo('video_index')
    .where({ id: resolvedId })
    .first('id', 'path', 'filename', 'media_type', 'is_file')
    .catch(() => null);
  if (!row) return { deleted: 0, deletedPaths: [], indexId: resolvedId };

  const mt = row.media_type ? String(row.media_type).trim() : '';
  const p = row.path ? String(row.path).trim() : '';
  const fn = row.filename ? String(row.filename).trim() : '';

  if (mt === 'tv' && p && fn) {
    const tvFolder = path.join(p, fn);
    const res = await cleanupTvTree(tvFolder);
    await _markTvTreePending(knexVideo, tvFolder);
    await _clearNfoFieldsForTvTree(knexVideo, tvFolder);
    return { ...res, indexId: resolvedId };
  }

  if ((mt === 'bdmv' || mt === 'video_ts') && p && fn) {
    const res = await cleanupDiscMovieFolder({ dirPath: p, filename: fn });
    await _markSingleIndexPending(knexVideo, resolvedId);
    await _clearNfoFieldsForSingleIndex(knexVideo, resolvedId);
    return { ...res, indexId: resolvedId };
  }

  if ((mt === 'movie' || mt === 'episod') && p && fn) {
    const res = await cleanupMovieOrEpisode({ dirPath: p, filename: fn });
    await _markSingleIndexPending(knexVideo, resolvedId);
    await _clearNfoFieldsForSingleIndex(knexVideo, resolvedId);
    return { ...res, indexId: resolvedId };
  }

  if (mt === 'season') {
    const tvId = await resolveTvIndexIdIfSeason(knexVideo, resolvedId);
    if (tvId && tvId !== resolvedId) return await cleanupByIndexId(knexVideo, tvId);
  }

  return { deleted: 0, deletedPaths: [], indexId: resolvedId };
}

module.exports = {
  cleanupByIndexId,
  cleanupTvTree,
  resolveTvIndexIdIfSeason,
};
