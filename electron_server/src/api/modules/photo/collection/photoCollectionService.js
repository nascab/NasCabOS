const path = require('path');
const userUtil = require('../../../../utils/userUtil');
class PhotoCollectionService {
  _uid(user) {
    return user.id;
  }

  async _getCollectionById(knexPhoto, collectionId) {
    const id = Number(collectionId);
    if (!Number.isFinite(id) || id <= 0) return null;
    return knexPhoto('photo_collection').where({ id }).first();
  }

  _parsePathList(pathListText) {
    if (!pathListText) return [];
    try {
      const arr = JSON.parse(String(pathListText));
      return Array.isArray(arr) ? arr.map(v => String(v || '').trim()).filter(Boolean) : [];
    } catch (_) {
      return [];
    }
  }

  async _getSourcePaths(knexPhoto) {
    const sources = await knexPhoto('photo_source').select('path');
    return (sources || []).map(s => (s && s.path ? String(s.path).trim() : '')).filter(Boolean);
  }

  async _validateAndNormalizePaths(knexPhoto, pathList) {
    const input = Array.isArray(pathList) ? pathList : [];
    const cleaned = input.map(p => String(p || '').trim()).filter(Boolean);
    const uniq = [...new Set(cleaned)];
    if (uniq.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const sourcePaths = await this._getSourcePaths(knexPhoto);
    if (sourcePaths.length === 0) {
      const err = new Error('photo.PHOTO_SOURCE_LIST_EMPTY');
      err.statusCode = 400;
      throw err;
    }

    const invalid = uniq.find(p => !sourcePaths.some(s => p.startsWith(s)));
    if (invalid) {
      const err = new Error('photo.PHOTO_SOURCE_OUT_OF_RANGE');
      err.statusCode = 400;
      err.args = { path: invalid };
      throw err;
    }

    return uniq;
  }

  async _ensureCollectionAccess({ knexPhoto, collectionId, user }) {
    const uid = this._uid(user);
    const collection = await this._getCollectionById(knexPhoto, collectionId);
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

  async listCollections({ knexPhoto }, params, user) {
    const uid = this._uid(user);
    const page = Math.max(1, Number(params.page || 1));
    const pageSize = Math.max(1, Math.min(100, Number(params.pageSize || 20)));
    const offset = (page - 1) * pageSize;
    const keyword = String(params.keyword || '').trim();
    const previewLimitInput = params.previewLimit ?? params.preview_limit;
    const previewLimitNum = Number(previewLimitInput);
    const previewLimit = Math.max(1, Math.min(20, Number.isFinite(previewLimitNum) ? previewLimitNum : 4));

    const sortFieldInput = String(params.sortField || 'create_time');
    const sortOrderInput = String(params.sortOrder || 'desc').toLowerCase();
    const sortOrder = sortOrderInput === 'asc' ? 'asc' : 'desc';
    const sortField = sortFieldInput === 'name' || sortFieldInput === 'create_time' ? sortFieldInput : 'create_time';

    const base = knexPhoto('photo_collection as c')
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
        const pathList = this._parsePathList(row.path_list);
        const previews = await this._getCollectionPreviews(knexPhoto, pathList, previewLimit);
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

  async _getCollectionPreviews(knexPhoto, pathList, previewLimit = 4) {
    const prefixes = Array.isArray(pathList) ? pathList.filter(Boolean) : [];
    if (prefixes.length === 0) return [];

    const rows = await knexPhoto('photo_index as p')
      .modify(qb => {
        qb.where('p.is_file', 1).andWhere('p.in_trash', 0);
        qb.andWhere(builder => {
          const sep = path.sep;
          for (const prefix of prefixes) {
            const raw = String(prefix || '').trim();
            if (!raw) continue;
            const base = raw.endsWith(sep) ? raw.slice(0, -1) : raw;
            if (!base) continue;
            const likePrefix = `${base}${sep}`;
            builder.orWhere(function () {
              this.where('p.path', base).orWhere('p.path', 'like', `${likePrefix}%`);
            });
          }
        });
      })
      .select('p.id', 'p.path', 'p.filename', 'p.file_hash', 'p.type', 'p.duration', 'p.original_time', 'p.original_date')
      .orderBy('p.original_time', 'desc')
      .orderBy('p.id', 'desc')
      .limit(previewLimit);

    return (rows || [])
      .filter(r => r && r.path && r.filename)
      .map(r => ({
        id: r.id,
        path: r.path,
        filename: r.filename,
        file_hash: r.file_hash,
        type: r.type,
        duration: r.duration,
        original_time: r.original_time,
        original_date: r.original_date,
        fullpath: path.join(r.path, r.filename),
      }));
  }

  async getCollection({ knexPhoto }, collectionId, user) {
    const { collection } = await this._ensureCollectionAccess({ knexPhoto, collectionId, user });
    return {
      id: collection.id,
      uid: collection.uid,
      name: collection.name,
      path_list: this._parsePathList(collection.path_list),
      create_time: collection.create_time,
    };
  }

  async createCollection({ knexPhoto }, payload, user) {
    const uid = this._uid(user);
    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const normalizedPaths = await this._validateAndNormalizePaths(knexPhoto, payload.path_list);

    const dup = await knexPhoto('photo_collection').where({ uid, name }).first();
    if (dup) {
      const err = new Error('photo.PHOTO_COLLECTION_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    const [id] = await knexPhoto('photo_collection').insert({
      uid,
      name,
      path_list: JSON.stringify(normalizedPaths),
      create_time: new Date(),
    });

    return this.getCollection({ knexPhoto }, id, user);
  }

  async updateCollection({ knexPhoto }, payload, user) {
    const collectionId = Number(payload.id);
    if (!Number.isFinite(collectionId) || collectionId <= 0) throw new Error('common.PARAM_ERROR');

    const { collection } = await this._ensureCollectionAccess({ knexPhoto, collectionId, user });

    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const normalizedPaths = await this._validateAndNormalizePaths(knexPhoto, payload.path_list);

    const uid = this._uid(user);
    const dup = await knexPhoto('photo_collection').where({ uid, name }).andWhereNot({ id: collection.id }).first();
    if (dup) {
      const err = new Error('photo.PHOTO_COLLECTION_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    await knexPhoto('photo_collection')
      .where({ id: collection.id })
      .update({ name, path_list: JSON.stringify(normalizedPaths) });

    return true;
  }

  async deleteCollection({ knexPhoto }, payload, user) {
    const collectionId = Number(payload.id);
    if (!Number.isFinite(collectionId) || collectionId <= 0) throw new Error('common.PARAM_ERROR');

    const { collection } = await this._ensureCollectionAccess({ knexPhoto, collectionId, user });
    const affected = await knexPhoto('photo_collection').where({ id: collection.id }).delete();
    return { affected };
  }
}

module.exports = new PhotoCollectionService();
