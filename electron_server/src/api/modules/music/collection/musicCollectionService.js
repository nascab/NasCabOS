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

function _applyMusicIndexPathPrefixFilter(query, paths) {
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
        this.where('m.path', p).orWhere('m.path', 'like', `${prefix}%`);
      });
    }
    for (const pair of folderExactPairs) {
      builder.orWhere(function () {
        this.where('m.show_type', 'series').andWhere('m.path', pair.parent).andWhere('m.filename', pair.name);
      });
    }
  });
}

class MusicCollectionService {
  _uid(user) {
    return user.id;
  }

  async _getCollectionById(knexMusic, collectionId) {
    const id = Number(collectionId);
    if (!Number.isFinite(id) || id <= 0) return null;
    return knexMusic('music_collection').where({ id }).first();
  }

  async _getSourcePaths(knexMusic) {
    const sources = await knexMusic('music_source').select('path');
    return (sources || []).map(s => (s && s.path ? String(s.path).trim() : '')).filter(Boolean);
  }

  async _validateAndNormalizePaths(knexMusic, pathList) {
    const input = Array.isArray(pathList) ? pathList : [];
    const cleaned = input.map(p => String(p || '').trim()).filter(Boolean);
    const uniq = [...new Set(cleaned)];
    if (uniq.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const sourcePaths = await this._getSourcePaths(knexMusic);
    if (sourcePaths.length === 0) {
      const err = new Error('music.MUSIC_SOURCE_LIST_EMPTY');
      err.statusCode = 400;
      throw err;
    }

    const invalid = uniq.find(p => !sourcePaths.some(s => p.startsWith(s)));
    if (invalid) {
      const err = new Error('music.MUSIC_SOURCE_OUT_OF_RANGE');
      err.statusCode = 400;
      err.args = { path: invalid };
      throw err;
    }

    return uniq;
  }

  async _ensureCollectionAccess({ knexMusic, collectionId, user }) {
    const uid = this._uid(user);
    const collection = await this._getCollectionById(knexMusic, collectionId);
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

  async _getCollectionPreviews(knexMusic, pathList) {
    const prefixes = Array.isArray(pathList) ? pathList.filter(Boolean) : [];
    if (prefixes.length === 0) return [];

    const rows = await knexMusic('music_index as m')
      .whereIn('m.show_type', ['music', 'submusic'])
      .where('m.has_inner_cover', 1)
      .modify(qb => _applyMusicIndexPathPrefixFilter(qb, prefixes))
      .select('m.id', 'm.path', 'm.filename', 'm.show_type', 'm.genre', 'm.has_inner_cover', 'm.mtime')
      .select(
        knexMusic.raw(
          `
          case
            when m.show_type = 'series' then (
              select path || ? || filename
              from music_index as s
              where s.show_type = 'submusic'
                and (s.path = (m.path || ? || m.filename) or s.path like ((m.path || ? || m.filename) || ? || '%'))
              order by s.has_inner_cover desc, s.id asc
              limit 1
            )
            else ''
          end as first_file_path
          `,
          [path.sep, path.sep, path.sep, path.sep]
        )
      )
      .orderBy('m.has_inner_cover', 'desc')
      .orderBy('m.mtime', 'desc')
      .orderBy('m.id', 'desc')
      .limit(4)
      .catch(() => []);

    return (rows || []).map(r => ({
      id: r && r.id ? Number(r.id) : 0,
      path: r && r.path ? String(r.path) : '',
      filename: r && r.filename ? String(r.filename) : '',
      show_type: r && r.show_type ? String(r.show_type) : '',
      first_file_path: r && r.first_file_path ? String(r.first_file_path) : '',
      genre: r && r.genre ? String(r.genre) : '',
      has_inner_cover: Number(r && r.has_inner_cover ? r.has_inner_cover : 0) || 0,
      mtime: r && r.mtime ? r.mtime : null,
    }));
  }

  async listCollections({ knexMusic }, params, user) {
    const uid = this._uid(user);
    const page = Math.max(1, Number(params.page || 1));
    const pageSize = Math.max(1, Math.min(100, Number(params.pageSize || 20)));
    const offset = (page - 1) * pageSize;
    const keyword = String(params.keyword || '').trim();

    const sortFieldInput = String(params.sortField || 'create_time');
    const sortOrderInput = String(params.sortOrder || 'desc').toLowerCase();
    const sortOrder = sortOrderInput === 'asc' ? 'asc' : 'desc';
    const sortField = sortFieldInput === 'name' || sortFieldInput === 'create_time' ? sortFieldInput : 'create_time';

    const base = knexMusic('music_collection as c')
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
        const previews = await this._getCollectionPreviews(knexMusic, pathList);
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

  async getCollection({ knexMusic }, collectionId, user) {
    const { collection } = await this._ensureCollectionAccess({ knexMusic, collectionId, user });
    return {
      id: collection.id,
      uid: collection.uid,
      name: collection.name,
      path_list: _parsePathList(collection.path_list),
      create_time: collection.create_time,
    };
  }

  async createCollection({ knexMusic }, payload, user) {
    const uid = this._uid(user);
    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const normalizedPaths = await this._validateAndNormalizePaths(knexMusic, payload.path_list);

    const dup = await knexMusic('music_collection').where({ uid, name }).first();
    if (dup) {
      const err = new Error('music.MUSIC_COLLECTION_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    const [id] = await knexMusic('music_collection').insert({
      uid,
      name,
      path_list: JSON.stringify(normalizedPaths),
    });

    return { id };
  }

  async updateCollection({ knexMusic }, payload, user) {
    const collectionId = Number(payload.id);
    if (!Number.isFinite(collectionId) || collectionId <= 0) throw new Error('common.PARAM_ERROR');

    const { collection } = await this._ensureCollectionAccess({ knexMusic, collectionId, user });

    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const normalizedPaths = await this._validateAndNormalizePaths(knexMusic, payload.path_list);

    const uid = this._uid(user);
    const dup = await knexMusic('music_collection').where({ uid, name }).andWhereNot({ id: collection.id }).first();
    if (dup) {
      const err = new Error('music.MUSIC_COLLECTION_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    await knexMusic('music_collection')
      .where({ id: collection.id })
      .update({
        name,
        path_list: JSON.stringify(normalizedPaths),
      });

    return true;
  }

  async deleteCollection({ knexMusic }, payload, user) {
    const collectionId = Number(payload.id);
    if (!Number.isFinite(collectionId) || collectionId <= 0) throw new Error('common.PARAM_ERROR');

    const { collection } = await this._ensureCollectionAccess({ knexMusic, collectionId, user });
    const affected = await knexMusic('music_collection').where({ id: collection.id }).delete();
    return { affected };
  }
}

module.exports = new MusicCollectionService();
