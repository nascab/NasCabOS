const path = require('path');
const userUtil = require('../../../../utils/userUtil');
const VideoSourceService = require('../source/videoSourceService');

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

class VideoAlbumService {
  _uid(user) {
    return user && user.id;
  }

  async _getById(knexVideo, albumId) {
    const id = Number(albumId);
    if (!Number.isFinite(id) || id <= 0) return null;
    return knexVideo('video_album').where({ id }).first();
  }

  async _ensureAccess({ knexVideo, albumId, user }) {
    const uid = this._uid(user);
    const album = await this._getById(knexVideo, albumId);
    if (!album) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    if (userUtil.isAdmin(user)) return { album, role: 'admin' };
    if (Number(album.uid) === Number(uid)) return { album, role: 'owner' };
    if (Number(album.is_public) === 1) return { album, role: 'public' };

    const err = new Error('auth.PERMISSION_DENIED');
    err.statusCode = 403;
    throw err;
  }

  async _getValidPaths(knexVideo, user) {
    const sourceService = new VideoSourceService(knexVideo);
    return await sourceService.getValidPaths(user);
  }

  async _getAlbumPreviews(knexVideo, albumIds, previewLimit) {
    const ids = Array.isArray(albumIds) ? albumIds.filter(v => Number.isFinite(Number(v)) && Number(v) > 0) : [];
    if (ids.length === 0) return new Map();

    const limit = Math.max(1, Math.min(20, Number(previewLimit) || 4));
    const previewsByAlbum = new Map();

    const coverRows = await knexVideo('video_album_index as ai')
      .leftJoin('video_index as v', 'ai.index_id', 'v.id')
      .whereIn('ai.album_id', ids)
      .andWhere('ai.is_cover', 1)
      .whereIn('v.media_type', ['tv', 'season', 'movie', 'bdmv', 'video_ts'])
      .select(
        'ai.album_id',
        'ai.create_time as index_create_time',
        'ai.id as album_index_id',
        'v.id as index_id',
        'v.path',
        'v.filename',
        'v.media_type',
        'v.poster_path',
        'v.fanart_path',
        'v.play_rel_path',
        'v.create_time'
      )
      .orderBy([
        { column: 'ai.album_id', order: 'asc' },
        { column: 'ai.create_time', order: 'desc' },
        { column: 'ai.id', order: 'desc' },
      ])
      .catch(() => []);

    await _fillFirstFilePathForFolderRows({ knex: knexVideo, rows: coverRows });

    for (const row of coverRows || []) {
      if (previewsByAlbum.has(row.album_id)) continue;
      previewsByAlbum.set(row.album_id, [
        {
          fullpath: _pickPreviewFullpath(row),
          media_type: row && row.media_type ? String(row.media_type) : '',
          first_file_path: row && row.first_file_path ? String(row.first_file_path) : '',
        },
      ]);
    }

    const missingAlbumIds = ids.filter(id => !previewsByAlbum.has(id));
    const batchSize = 8;
    for (let i = 0; i < missingAlbumIds.length; i += batchSize) {
      const batch = missingAlbumIds.slice(i, i + batchSize);
      const batchResults = await Promise.all(
        batch.map(albumId =>
          knexVideo('video_album_index as ai')
            .leftJoin('video_index as v', 'ai.index_id', 'v.id')
            .where('ai.album_id', albumId)
            .whereIn('v.media_type', ['tv', 'season', 'movie', 'bdmv', 'video_ts'])
            .select(
              'ai.album_id',
              'ai.create_time as index_create_time',
              'ai.id as album_index_id',
              'v.id as index_id',
              'v.path',
              'v.filename',
              'v.media_type',
              'v.poster_path',
              'v.fanart_path',
              'v.play_rel_path',
              'v.create_time'
            )
            .orderBy([
              { column: 'ai.create_time', order: 'desc' },
              { column: 'ai.id', order: 'desc' },
            ])
            .limit(limit)
            .catch(() => [])
        )
      );

      for (let j = 0; j < batch.length; j++) {
        const albumId = batch[j];
        const rows = batchResults[j] || [];
        await _fillFirstFilePathForFolderRows({ knex: knexVideo, rows });
        const previews = (rows || [])
          .map(r => ({
            fullpath: _pickPreviewFullpath(r),
            media_type: r && r.media_type ? String(r.media_type) : '',
            first_file_path: r && r.first_file_path ? String(r.first_file_path) : '',
          }))
          .filter(r => r && (r.fullpath || r.first_file_path));
        previewsByAlbum.set(albumId, previews);
      }
    }

    return previewsByAlbum;
  }

  async listAlbums({ knexVideo }, params, user) {
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

    const isAdmin = userUtil.isAdmin(user);

    const base = knexVideo('video_album as a')
      .modify(qb => {
        if (keyword) qb.where('a.name', 'like', `%${keyword}%`);
        if (isAdmin) return;
        qb.where(builder => {
          builder.where('a.uid', uid).orWhere('a.is_public', 1);
        });
      })
      .select('a.id', 'a.uid as owner_id', 'a.name', 'a.is_public', 'a.create_time')
      .orderBy(`a.${sortField}`, sortOrder)
      .orderBy('a.id', 'desc');

    const [{ count }] = await base.clone().clearSelect().clearOrder().count('* as count');
    const items = await base.clone().offset(offset).limit(pageSize);

    const albumIds = (items || []).map(it => it.id);
    const previewsByAlbum = await this._getAlbumPreviews(knexVideo, albumIds, previewLimit);

    const enriched = (items || []).map(a => ({
      ...a,
      is_owner: Number(a.owner_id) === Number(uid),
      previews: previewsByAlbum.get(a.id) || [],
    }));

    return {
      items: enriched,
      pagination: {
        total: Number(count || 0),
        page,
        pageSize,
      },
    };
  }

  async getAlbum({ knexVideo }, albumId, user) {
    const { album } = await this._ensureAccess({ knexVideo, albumId, user });
    return {
      id: album.id,
      owner_id: album.uid,
      name: album.name,
      is_public: album.is_public,
      create_time: album.create_time,
    };
  }

  async createAlbum({ knexVideo }, payload, user) {
    const uid = this._uid(user);
    const name = String(payload.name || '').trim();
    const isPublic = payload.is_public ? 1 : 0;
    if (!name) throw new Error('common.PARAM_ERROR');

    const dup = await knexVideo('video_album').where({ uid, name }).first();
    if (dup) {
      const err = new Error('video.VIDEO_ALBUM_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    const [id] = await knexVideo('video_album').insert({
      uid,
      name,
      is_public: isPublic,
      create_time: new Date(),
    });
    return { id };
  }

  async updateAlbum({ knexVideo }, payload, user) {
    const uid = this._uid(user);
    const albumId = Number(payload.id);
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');

    const existing = await this._getById(knexVideo, albumId);
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
      const dup = await knexVideo('video_album').where({ uid: existing.uid, name }).andWhereNot({ id: albumId }).first();
      if (dup) {
        const err = new Error('video.VIDEO_ALBUM_NAME_EXISTS');
        err.statusCode = 409;
        throw err;
      }
      data.name = name;
    }
    if (payload.is_public !== undefined) {
      data.is_public = payload.is_public ? 1 : 0;
    }
    if (Object.keys(data).length === 0) return true;

    await knexVideo('video_album').where({ id: albumId }).update(data);
    return true;
  }

  async deleteAlbum({ knexVideo }, payload, user) {
    const uid = this._uid(user);
    const albumId = Number(payload.id);
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');

    const existing = await this._getById(knexVideo, albumId);
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

    return knexVideo.transaction(async trx => {
      await trx('video_album_index').where({ album_id: albumId }).delete();
      const affected = await trx('video_album').where({ id: albumId }).delete();
      return { affected };
    });
  }

  async addAlbumIndexes({ knexVideo }, payload, user) {
    const albumId = Number(payload.album_id ?? payload.albumId);
    const indexIds = Array.isArray(payload.index_ids ?? payload.indexIds) ? (payload.index_ids ?? payload.indexIds) : [];
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');
    if (indexIds.length === 0) throw new Error('common.PARAM_ERROR');

    const access = await this._ensureAccess({ knexVideo, albumId, user });
    if (access.role !== 'owner' && access.role !== 'admin') {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    const uniqIds = [...new Set(indexIds.map(v => Math.trunc(Number(v) || 0)).filter(v => v > 0))];
    if (uniqIds.length === 0) throw new Error('common.PARAM_ERROR');

    const validPaths = await this._getValidPaths(knexVideo, user);
    if (!validPaths || validPaths.length === 0) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    return knexVideo.transaction(async trx => {
      const rows = await trx('video_index').whereIn('id', uniqIds).select('id', 'path', 'filename', 'media_type', 'is_file');
      const allowedIndexIds = new Set();
      for (const r of rows || []) {
        const p = r && r.path ? String(r.path).trim() : '';
        const name = r && r.filename ? String(r.filename).trim() : '';
        if (!p || !name) continue;
        const full = path.resolve(path.join(p, name));
        const ok = validPaths.some(vp => {
          const base = path.resolve(String(vp));
          if (full === base) return true;
          const prefix = base.endsWith(path.sep) ? base : `${base}${path.sep}`;
          return full.startsWith(prefix);
        });
        if (ok) allowedIndexIds.add(Number(r.id));
      }

      const allowList = [...allowedIndexIds];
      if (allowList.length === 0) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }

      const exists = await trx('video_album_index').where({ album_id: albumId }).whereIn('index_id', allowList).select('index_id');
      const existingSet = new Set((exists || []).map(e => Number(e && e.index_id) || 0).filter(v => v > 0));
      const toInsert = allowList
        .filter(id => id && !existingSet.has(id))
        .map(id => ({
          album_id: albumId,
          index_id: id,
          is_cover: 0,
          create_time: new Date(),
        }));
      if (toInsert.length > 0) {
        await trx('video_album_index').insert(toInsert);
      }

      const cover = await trx('video_album_index').where({ album_id: albumId, is_cover: 1 }).first();
      if (!cover) {
        const first = await trx('video_album_index').where({ album_id: albumId }).orderBy('id', 'asc').first();
        if (first) {
          await trx('video_album_index').where({ id: first.id }).update({ is_cover: 1 });
        }
      }

      return { inserted: toInsert.length };
    });
  }

  async removeAlbumIndexes({ knexVideo }, payload, user) {
    const albumId = Number(payload.album_id ?? payload.albumId);
    const indexIds = Array.isArray(payload.index_ids ?? payload.indexIds) ? (payload.index_ids ?? payload.indexIds) : [];
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');
    if (indexIds.length === 0) throw new Error('common.PARAM_ERROR');

    const access = await this._ensureAccess({ knexVideo, albumId, user });
    if (access.role !== 'owner' && access.role !== 'admin') {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    const uniqIds = [...new Set(indexIds.map(v => Math.trunc(Number(v) || 0)).filter(v => v > 0))];
    if (uniqIds.length === 0) throw new Error('common.PARAM_ERROR');

    return knexVideo.transaction(async trx => {
      const affected = await trx('video_album_index').where({ album_id: albumId }).whereIn('index_id', uniqIds).delete();

      const cover = await trx('video_album_index').where({ album_id: albumId, is_cover: 1 }).first();
      if (!cover) {
        const first = await trx('video_album_index').where({ album_id: albumId }).orderBy('id', 'asc').first();
        if (first) {
          await trx('video_album_index').where({ id: first.id }).update({ is_cover: 1 });
        }
      }
      return { affected };
    });
  }

  async setAlbumCover({ knexVideo }, payload, user) {
    const uid = this._uid(user);
    const albumId = Number(payload.album_id ?? payload.albumId);
    const indexId = Number(payload.index_id ?? payload.indexId);
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');
    if (!Number.isFinite(indexId) || indexId <= 0) throw new Error('common.PARAM_ERROR');

    const album = await this._getById(knexVideo, albumId);
    if (!album) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    if (!userUtil.isAdmin(user) && Number(album.uid) !== Number(uid)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    return knexVideo.transaction(async trx => {
      await trx('video_album_index').where({ album_id: albumId }).update({ is_cover: 0 });
      const updated = await trx('video_album_index').where({ album_id: albumId, index_id: indexId }).update({ is_cover: 1 });
      if (!updated) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      return true;
    });
  }
}

module.exports = new VideoAlbumService();
