const path = require('path');
const userUtil = require('../../../../utils/userUtil');
const VideoSourceService = require('../source/videoSourceService');
const smartAlbumFilterUtil = require('./videoSmartAlbumFilterUtil');

function _applyVideoIndexPathPrefixFilter(query, paths) {
  const list = Array.isArray(paths) ? paths.map(p => String(p || '').trim()).filter(Boolean) : [];
  if (list.length === 0) {
    query.whereRaw('1 = 0');
    return;
  }

  const sep = path.sep;
  const folderExactPairs = [];
  for (const raw of list) {
    const p = raw.endsWith(sep) ? raw.slice(0, -1) : raw;
    if (!p) continue;
    if (path.extname(p)) continue;
    const parent = path.dirname(p);
    const name = path.basename(p);
    if (!parent || !name) continue;
    folderExactPairs.push({ parent, name });
  }

  query.where(builder => {
    for (const p of list) {
      const prefix = p.endsWith(sep) ? p : `${p}${sep}`;
      builder.orWhere(function () {
        this.where('v.path', p).orWhere('v.path', 'like', `${prefix}%`);
      });
    }
    for (const pair of folderExactPairs) {
      builder.orWhere(function () {
        this.where('v.is_file', 0).andWhere('v.path', pair.parent).andWhere('v.filename', pair.name);
      });
    }
  });
}

function _resolveArtworkAbsolute({ baseDir, maybeRelative }) {
  const p = maybeRelative === undefined || maybeRelative === null ? '' : String(maybeRelative).trim();
  if (!p) return '';
  if (path.isAbsolute(p)) return p;
  const base = baseDir === undefined || baseDir === null ? '' : String(baseDir).trim();
  if (!base) return '';
  return path.resolve(base, p);
}

function _pickPreviewFullpath(row) {
  const baseDir = row && row.path ? String(row.path).trim() : '';
  const poster = _resolveArtworkAbsolute({ baseDir, maybeRelative: row && row.poster_path });
  if (poster) return poster;
  const fanart = _resolveArtworkAbsolute({ baseDir, maybeRelative: row && row.fanart_path });
  if (fanart) return fanart;
  const folderPath = baseDir && row && row.filename ? path.join(baseDir, String(row.filename).trim()) : '';
  const playRelPath = row && row.play_rel_path ? String(row.play_rel_path).trim() : '';
  if (folderPath && playRelPath) return path.resolve(folderPath, playRelPath);
  const filename = row && row.filename ? String(row.filename).trim() : '';
  if (baseDir && filename) return path.join(baseDir, filename);
  return '';
}

async function _getFirstEpisodeRowUnderFolder({ knex, rootFolder }) {
  const resolved = rootFolder ? path.resolve(String(rootFolder)) : '';
  if (!resolved) return null;
  const prefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;

  return await knex('video_index')
    .where({ is_file: 1, media_type: 'episod' })
    .andWhere(qb => {
      qb.where('path', resolved).orWhere('path', 'like', `${prefix}%`);
    })
    .orderBy('episod_num', 'asc')
    .orderBy('id', 'asc')
    .first('path', 'filename')
    .catch(() => null);
}

async function _fillFirstFilePathForFolderRows({ knex, rows }) {
  const list = Array.isArray(rows) ? rows : [];
  const folderRows = list.filter(r => r && (r.media_type === 'tv' || r.media_type === 'season'));
  if (folderRows.length === 0) return;

  await Promise.all(
    folderRows.map(async r => {
      const poster = r.poster_path ? String(r.poster_path).trim() : '';
      const fanart = r.fanart_path ? String(r.fanart_path).trim() : '';
      if (poster || fanart) return;
      const baseDir = r.path ? String(r.path).trim() : '';
      const name = r.filename ? String(r.filename).trim() : '';
      if (!baseDir || !name) return;
      const folder = path.join(baseDir, name);

      const first = await _getFirstEpisodeRowUnderFolder({
        knex,
        rootFolder: folder,
      });
      const epPath = first && first.path ? String(first.path).trim() : '';
      const epName = first && first.filename ? String(first.filename).trim() : '';
      if (!epPath || !epName) return;
      r.first_file_path = path.join(epPath, epName);
    })
  );
}

class VideoSmartAlbumService {
  _uid(user) {
    return user && user.id;
  }

  _normalizeType(type) {
    return 'condition';
  }

  _stringifyFilterContent(filterContent) {
    if (filterContent === undefined || filterContent === null) {
      return '{}';
    }
    if (typeof filterContent === 'string') {
      const s = filterContent.trim();
      if (!s) return '{}';
      try {
        JSON.parse(s);
        return s;
      } catch (_) {
        throw new Error('common.PARAM_ERROR');
      }
    }
    if (typeof filterContent === 'object') {
      try {
        return JSON.stringify(filterContent);
      } catch (_) {
        throw new Error('common.PARAM_ERROR');
      }
    }
    throw new Error('common.PARAM_ERROR');
  }

  async _getById(knexVideo, id) {
    const smartAlbumId = Number(id);
    if (!Number.isFinite(smartAlbumId) || smartAlbumId <= 0) return null;
    return knexVideo('video_smart_album').where({ id: smartAlbumId }).first();
  }

  async _ensureAccess({ knexVideo, id, user }) {
    const uid = this._uid(user);
    const album = await this._getById(knexVideo, id);
    if (!album) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    if (userUtil.isAdmin(user)) return album;

    if (Number(album.uid) !== Number(uid)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }
    return album;
  }

  async _getValidPaths(knexVideo, user) {
    const sourceService = new VideoSourceService(knexVideo);
    return await sourceService.getValidPaths(user);
  }

  async _getSmartAlbumPreviews(knexVideo, type, filterContent, validPaths) {
    const paths = Array.isArray(validPaths) ? validPaths.filter(Boolean) : [];
    if (paths.length === 0) return [];

    const query = knexVideo('video_index as v').whereIn('v.media_type', ['tv', 'season', 'movie', 'bdmv', 'video_ts']);
    _applyVideoIndexPathPrefixFilter(query, paths);
    smartAlbumFilterUtil.applySmartAlbumFilter(query, type, filterContent, 'v');

    const rows = await query
      .select('v.path', 'v.filename', 'v.media_type', 'v.poster_path', 'v.fanart_path', 'v.play_rel_path', 'v.create_time')
      .orderBy('v.create_time', 'desc')
      .orderBy('v.id', 'desc')
      .limit(4)
      .catch(() => []);

    await _fillFirstFilePathForFolderRows({ knex: knexVideo, rows });

    return (rows || [])
      .map(r => ({
        fullpath: _pickPreviewFullpath(r),
        media_type: r && r.media_type ? String(r.media_type) : '',
        first_file_path: r && r.first_file_path ? String(r.first_file_path) : '',
      }))
      .filter(r => r && (r.fullpath || r.first_file_path));
  }

  async listSmartAlbums({ knexVideo }, params, user) {
    const uid = this._uid(user);
    const page = Math.max(1, Number(params.page || 1));
    const pageSize = Math.max(1, Math.min(100, Number(params.pageSize || 20)));
    const offset = (page - 1) * pageSize;
    const keyword = String(params.keyword || '').trim();
    const type = params.type !== undefined && params.type !== null && String(params.type).trim() ? this._normalizeType(params.type) : null;

    const sortFieldInput = String(params.sortField || 'create_time');
    const sortOrderInput = String(params.sortOrder || 'desc').toLowerCase();
    const sortOrder = sortOrderInput === 'asc' ? 'asc' : 'desc';
    const sortField = sortFieldInput === 'name' || sortFieldInput === 'create_time' ? sortFieldInput : 'create_time';

    const base = knexVideo('video_smart_album as a')
      .modify(qb => {
        qb.where('a.uid', uid);
        if (keyword) qb.where('a.name', 'like', `%${keyword}%`);
        if (type) qb.where('a.type', type);
      })
      .select('a.id', 'a.uid', 'a.name', 'a.type', 'a.filter_content', 'a.create_time')
      .orderBy(`a.${sortField}`, sortOrder)
      .orderBy('a.id', 'desc');

    const [{ count }] = await base.clone().clearSelect().clearOrder().count('* as count');
    const rows = await base.clone().offset(offset).limit(pageSize);

    const validPaths = user ? await this._getValidPaths(knexVideo, user) : [];

    const enriched = await Promise.all(
      (rows || []).map(async r => {
        const filterContent = smartAlbumFilterUtil.parseFilterContentText(r.filter_content);
        const previews = await this._getSmartAlbumPreviews(knexVideo, r.type, filterContent, validPaths);
        return { ...r, filter_content: filterContent, previews };
      })
    );

    return {
      items: enriched,
      pagination: {
        total: Number(count || 0),
        page,
        pageSize,
      },
    };
  }

  async getSmartAlbum({ knexVideo }, id, user) {
    const album = await this._ensureAccess({ knexVideo, id, user });
    return {
      id: album.id,
      uid: album.uid,
      name: album.name,
      type: album.type,
      filter_content: smartAlbumFilterUtil.parseFilterContentText(album.filter_content),
      create_time: album.create_time,
    };
  }

  async createSmartAlbum({ knexVideo }, payload, user) {
    const uid = this._uid(user);
    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const type = this._normalizeType(payload.type);
    const filterContentText = this._stringifyFilterContent(payload.filter_content);

    const dup = await knexVideo('video_smart_album').where({ uid, name }).first();
    if (dup) {
      const err = new Error('video.VIDEO_SMART_ALBUM_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    const [id] = await knexVideo('video_smart_album').insert({
      uid,
      name,
      type,
      filter_content: filterContentText,
      create_time: new Date(),
    });
    return { id };
  }

  async updateSmartAlbum({ knexVideo }, payload, user) {
    const uid = this._uid(user);
    const id = Number(payload.id);
    if (!Number.isFinite(id) || id <= 0) throw new Error('common.PARAM_ERROR');
    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const existing = await this._getById(knexVideo, id);
    if (!existing) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    if (!userUtil.isAdmin(user) && Number(existing.uid) !== Number(uid)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    const type = this._normalizeType(payload.type);
    const filterContentText = this._stringifyFilterContent(payload.filter_content);

    const dup = await knexVideo('video_smart_album').where({ uid, name }).andWhere('id', '!=', id).first();
    if (dup) {
      const err = new Error('video.VIDEO_SMART_ALBUM_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    const affected = await knexVideo('video_smart_album')
      .where({ id })
      .update({
        name,
        type,
        filter_content: filterContentText,
      })
      .catch(() => 0);
    return { affected };
  }

  async deleteSmartAlbum({ knexVideo }, payload, user) {
    const uid = this._uid(user);
    const id = Number(payload.id);
    if (!Number.isFinite(id) || id <= 0) throw new Error('common.PARAM_ERROR');

    const existing = await this._getById(knexVideo, id);
    if (!existing) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    if (!userUtil.isAdmin(user) && Number(existing.uid) !== Number(uid)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    const affected = await knexVideo('video_smart_album').where({ id }).delete();
    return { affected };
  }
}

module.exports = new VideoSmartAlbumService();
