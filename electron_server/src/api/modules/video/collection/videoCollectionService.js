const path = require('path');
const userUtil = require('../../../../utils/userUtil');

function _parsePathList(pathListText) {
  if (!pathListText) return [];
  try {
    const arr = JSON.parse(String(pathListText));
    return Array.isArray(arr) ? arr.map(v => String(v || '').trim()).filter(Boolean) : [];
  } catch (_) {
    return [];
  }
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

class VideoCollectionService {
  _uid(user) {
    return user.id;
  }

  async _getCollectionById(knexVideo, collectionId) {
    const id = Number(collectionId);
    if (!Number.isFinite(id) || id <= 0) return null;
    return knexVideo('video_collection').where({ id }).first();
  }

  async _getSourcePaths(knexVideo) {
    const sources = await knexVideo('video_source').select('path');
    return (sources || []).map(s => (s && s.path ? String(s.path).trim() : '')).filter(Boolean);
  }

  async _validateAndNormalizePaths(knexVideo, pathList) {
    const input = Array.isArray(pathList) ? pathList : [];
    const cleaned = input.map(p => String(p || '').trim()).filter(Boolean);
    const uniq = [...new Set(cleaned)];
    if (uniq.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const sourcePaths = await this._getSourcePaths(knexVideo);
    if (sourcePaths.length === 0) {
      const err = new Error('video.VIDEO_SOURCE_LIST_EMPTY');
      err.statusCode = 400;
      throw err;
    }

    const invalid = uniq.find(p => !sourcePaths.some(s => p.startsWith(s)));
    if (invalid) {
      const err = new Error('video.VIDEO_SOURCE_OUT_OF_RANGE');
      err.statusCode = 400;
      err.args = { path: invalid };
      throw err;
    }

    return uniq;
  }

  async _ensureCollectionAccess({ knexVideo, collectionId, user }) {
    const uid = this._uid(user);
    const collection = await this._getCollectionById(knexVideo, collectionId);
    if (!collection) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    if (userUtil.isAdmin(user)) {
      return { collection, role: 'admin' };
    }

    if (Number(collection.uid) !== Number(uid)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    return { collection, role: 'owner' };
  }

  async _getCollectionPreviews(knexVideo, pathList) {
    const prefixes = Array.isArray(pathList) ? pathList.filter(Boolean) : [];
    if (prefixes.length === 0) return [];
    const rows = await knexVideo('video_index as v')
      .modify(qb => {
        qb.andWhere(builder => {
          const sep = path.sep;
          for (const prefix of prefixes) {
            const raw = String(prefix || '').trim();
            if (!raw) continue;
            const base = raw.endsWith(sep) ? raw.slice(0, -1) : raw;
            if (!base) continue;
            const likePrefix = `${base}${sep}`;
            builder.orWhere(function () {
              this.where('v.path', base).orWhere('v.path', 'like', `${likePrefix}%`);
            });
          }
        });
      })
      .whereIn('media_type', ['tv', 'season', 'movie', 'bdmv', 'video_ts'])
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

  async listCollections({ knexVideo }, params, user) {
    const uid = this._uid(user);
    const page = Math.max(1, Number(params.page || 1));
    const pageSize = Math.max(1, Math.min(100, Number(params.pageSize || 20)));
    const offset = (page - 1) * pageSize;
    const keyword = String(params.keyword || '').trim();

    const sortFieldInput = String(params.sortField || 'create_time');
    const sortOrderInput = String(params.sortOrder || 'desc').toLowerCase();
    const sortOrder = sortOrderInput === 'asc' ? 'asc' : 'desc';
    const sortField = sortFieldInput === 'name' || sortFieldInput === 'create_time' ? sortFieldInput : 'create_time';

    const base = knexVideo('video_collection as c')
      .modify(qb => {
        if (keyword) qb.where('c.name', 'like', `%${keyword}%`);
        qb.where('c.uid', uid);
      })
      .select('c.id', 'c.uid', 'c.name', 'c.path_list', 'c.create_time')
      .orderBy(`c.${sortField}`, sortOrder)
      .orderBy('c.id', 'desc');

    const [{ count }] = await base.clone().clearSelect().clearOrder().count('* as count');
    const items = await base.clone().offset(offset).limit(pageSize);

    const enriched = await Promise.all(
      (items || []).map(async row => {
        const pathList = _parsePathList(row.path_list);
        const previews = await this._getCollectionPreviews(knexVideo, pathList);
        return {
          id: row.id,
          uid: row.uid,
          name: row.name,
          path_list: pathList,
          create_time: row.create_time,
          previews,
        };
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

  async getCollection({ knexVideo }, collectionId, user) {
    const { collection } = await this._ensureCollectionAccess({ knexVideo, collectionId, user });
    return {
      id: collection.id,
      uid: collection.uid,
      name: collection.name,
      path_list: _parsePathList(collection.path_list),
      create_time: collection.create_time,
    };
  }

  async createCollection({ knexVideo }, payload, user) {
    const uid = this._uid(user);
    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const normalizedPaths = await this._validateAndNormalizePaths(knexVideo, payload.path_list);

    const dup = await knexVideo('video_collection').where({ uid, name }).first();
    if (dup) {
      const err = new Error('video.VIDEO_COLLECTION_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    const [id] = await knexVideo('video_collection').insert({
      uid,
      name,
      path_list: JSON.stringify(normalizedPaths),
      create_time: new Date(),
    });

    return this.getCollection({ knexVideo }, id, user);
  }

  async updateCollection({ knexVideo }, payload, user) {
    const collectionId = Number(payload.id);
    if (!Number.isFinite(collectionId) || collectionId <= 0) throw new Error('common.PARAM_ERROR');

    const { collection } = await this._ensureCollectionAccess({ knexVideo, collectionId, user });

    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const normalizedPaths = await this._validateAndNormalizePaths(knexVideo, payload.path_list);

    const uid = this._uid(user);
    const dup = await knexVideo('video_collection').where({ uid, name }).andWhereNot({ id: collection.id }).first();
    if (dup) {
      const err = new Error('video.VIDEO_COLLECTION_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    await knexVideo('video_collection')
      .where({ id: collection.id })
      .update({
        name,
        path_list: JSON.stringify(normalizedPaths),
      });

    return true;
  }

  async deleteCollection({ knexVideo }, payload, user) {
    const collectionId = Number(payload.id);
    if (!Number.isFinite(collectionId) || collectionId <= 0) throw new Error('common.PARAM_ERROR');

    const { collection } = await this._ensureCollectionAccess({ knexVideo, collectionId, user });
    const affected = await knexVideo('video_collection').where({ id: collection.id }).delete();
    return { affected };
  }
}

module.exports = new VideoCollectionService();
