const userUtil = require('../../../../utils/userUtil');
const path = require('path');
const photoTimeLineService = require('../timeline/photoTimeLineService');
const smartAlbumFilterUtil = require('./photoSmartAlbumFilterUtil');
const { applyPathPrefixFilter } = require('../timeline/photoPathQueryUtil');

class PhotoSmartAlbumService {
  _uid(user) {
    return user && user.id;
  }

  _normalizeType(type) {
    const t = String(type || 'condition').trim();
    if (t === 'smart_date') return 'smart_date';
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

  async _getById(knexPhoto, id) {
    const smartAlbumId = Number(id);
    if (!Number.isFinite(smartAlbumId) || smartAlbumId <= 0) return null;
    return knexPhoto('photo_smart_album').where({ id: smartAlbumId }).first();
  }

  async _ensureAccess({ knexPhoto, id, user }) {
    const uid = this._uid(user);
    const album = await this._getById(knexPhoto, id);
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

  async listSmartAlbums({ knexPhoto }, params, user) {
    const uid = this._uid(user);
    const page = Math.max(1, Number(params.page || 1));
    const pageSize = Math.max(1, Math.min(100, Number(params.pageSize || 20)));
    const offset = (page - 1) * pageSize;
    const keyword = String(params.keyword || '').trim();
    const type = params.type !== undefined ? this._normalizeType(params.type) : null;
    const previewLimitInput = params.previewLimit ?? params.preview_limit;
    const previewLimitNum = Number(previewLimitInput);
    const previewLimit = Math.max(1, Math.min(20, Number.isFinite(previewLimitNum) ? previewLimitNum : 4));

    const sortFieldInput = String(params.sortField || 'create_time');
    const sortOrderInput = String(params.sortOrder || 'desc').toLowerCase();
    const sortOrder = sortOrderInput === 'asc' ? 'asc' : 'desc';
    const sortField = sortFieldInput === 'name' || sortFieldInput === 'create_time' ? sortFieldInput : 'create_time';

    const base = knexPhoto('photo_smart_album as a')
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

    const validPaths = user ? await photoTimeLineService.getValidPaths(user) : [];

    const enriched = await Promise.all(
      (rows || []).map(async r => {
        const filterContent = smartAlbumFilterUtil.parseFilterContentText(r.filter_content);
        const previews = await this._getSmartAlbumPreviews(knexPhoto, r.type, filterContent, validPaths, previewLimit);
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

  async _getSmartAlbumPreviews(knexPhoto, type, filterContent, validPaths, previewLimit = 4) {
    const paths = Array.isArray(validPaths) ? validPaths.filter(Boolean) : [];
    if (paths.length === 0) return [];

    const query = knexPhoto('photo_index as p').where('p.is_file', 1).andWhere('p.in_trash', 0);
    applyPathPrefixFilter(query, 'p.path', paths);
    smartAlbumFilterUtil.applySmartAlbumFilter(query, type, filterContent, 'p');

    const rows = await query
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

  async getSmartAlbum({ knexPhoto }, id, user) {
    const album = await this._ensureAccess({ knexPhoto, id, user });
    return {
      id: album.id,
      uid: album.uid,
      name: album.name,
      type: album.type,
      filter_content: smartAlbumFilterUtil.parseFilterContentText(album.filter_content),
      create_time: album.create_time,
    };
  }

  async createSmartAlbum({ knexPhoto }, payload, user) {
    const uid = this._uid(user);
    const name = String(payload.name || '').trim();
    if (!name) throw new Error('common.PARAM_ERROR');

    const type = this._normalizeType(payload.type);
    const filterContentText = this._stringifyFilterContent(payload.filter_content);

    const dup = await knexPhoto('photo_smart_album').where({ uid, name }).first();
    if (dup) {
      const err = new Error('photo.ALBUM_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    const [id] = await knexPhoto('photo_smart_album').insert({
      uid,
      name,
      type,
      filter_content: filterContentText,
      create_time: new Date(),
    });
    return { id };
  }

  async updateSmartAlbum({ knexPhoto }, payload, user) {
    const uid = this._uid(user);
    const id = Number(payload.id);
    if (!Number.isFinite(id) || id <= 0) throw new Error('common.PARAM_ERROR');

    const existing = await this._getById(knexPhoto, id);
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

    const data = {};
    if (payload.name !== undefined) {
      const name = String(payload.name || '').trim();
      if (!name) throw new Error('common.PARAM_ERROR');
      const dup = await knexPhoto('photo_smart_album').where({ uid: existing.uid, name }).andWhereNot({ id }).first();
      if (dup) {
        const err = new Error('photo.ALBUM_NAME_EXISTS');
        err.statusCode = 409;
        throw err;
      }
      data.name = name;
    }
    if (payload.type !== undefined) {
      data.type = this._normalizeType(payload.type);
    }
    if (payload.filter_content !== undefined) {
      data.filter_content = this._stringifyFilterContent(payload.filter_content);
    }

    if (Object.keys(data).length === 0) throw new Error('common.PARAM_ERROR');
    await knexPhoto('photo_smart_album').where({ id }).update(data);
    return true;
  }

  async deleteSmartAlbum({ knexPhoto }, payload, user) {
    const uid = this._uid(user);
    const id = Number(payload.id);
    if (!Number.isFinite(id) || id <= 0) throw new Error('common.PARAM_ERROR');

    const existing = await this._getById(knexPhoto, id);
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

    const affected = await knexPhoto('photo_smart_album').where({ id }).delete();
    return { affected };
  }
}

module.exports = new PhotoSmartAlbumService();
