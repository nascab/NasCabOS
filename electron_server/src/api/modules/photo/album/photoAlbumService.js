const path = require('path');
const userUtil = require('../../../../utils/userUtil');
const { applyPathPrefixFilter } = require('../timeline/photoPathQueryUtil');
const photoTimeLineService = require('../timeline/photoTimeLineService');
class PhotoAlbumService {
  _uid(user) {
    return user.id;
  }

  async _getAlbumById(knexPhoto, albumId) {
    const id = Number(albumId);
    if (!Number.isFinite(id) || id <= 0) return null;
    return knexPhoto('photo_album').where({ id }).first();
  }

  async _ensureAlbumAccess({ knexPhoto, albumId, user }) {
    const uid = this._uid(user);
    const album = await this._getAlbumById(knexPhoto, albumId);
    if (!album) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    if (userUtil.isAdmin(user)) {
      return { album, role: 'admin', share: null };
    }

    if (Number(album.uid) === Number(uid)) {
      return { album, role: 'owner', share: null };
    }

    if (Number(album.is_public) === 1) {
      return { album, role: 'public', share: null };
    }

    const share = await knexPhoto('photo_album_share').where({ album_id: album.id, uid }).first();
    if (!share) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }
    return { album, role: 'shared', share };
  }

  async listAlbums({ knexPhoto, knexMain }, params, user) {
    const uid = this._uid(user);
    const page = Math.max(1, Number(params.page || 1));
    const pageSize = Math.max(1, Math.min(100, Number(params.pageSize || 20)));
    const offset = (page - 1) * pageSize;
    const keyword = String(params.keyword || '').trim();
    const type = String(params.type || 'all').trim();
    const previewLimitInput = params.previewLimit ?? params.preview_limit;
    const previewLimitNum = Number(previewLimitInput);
    const previewLimit = Math.max(1, Math.min(20, Number.isFinite(previewLimitNum) ? previewLimitNum : 4));

    const sortFieldInput = String(params.sortField || 'create_time');
    const sortOrderInput = String(params.sortOrder || 'desc').toLowerCase();
    const sortOrder = sortOrderInput === 'asc' ? 'asc' : 'desc';
    const sortField = sortFieldInput === 'name' || sortFieldInput === 'create_time' ? sortFieldInput : 'create_time';

    const knex = knexPhoto;
    const base = knex('photo_album as a')
      .modify(qb => {
        if (keyword) qb.where('a.name', 'like', `%${keyword}%`);

        if (type === 'my_shared') {
          qb.where('a.uid', uid).whereExists(function () {
            this.select(1).from('photo_album_share as s').whereRaw('s.album_id = a.id').where('s.owner_id', uid);
          });
          return;
        }

        if (type === 'shared_to_me') {
          qb.whereExists(function () {
            this.select(1).from('photo_album_share as s').whereRaw('s.album_id = a.id').where('s.uid', uid);
          });
          return;
        }

        // 管理员与普通用户一致：仅能看到自己的相册、公开相册、以及分享给自己的相册
        qb.where(builder => {
          builder
            .where('a.uid', uid)
            .orWhere('a.is_public', 1)
            .orWhereExists(function () {
              this.select(1).from('photo_album_share as s').whereRaw('s.album_id = a.id').where('s.uid', uid);
            });
        });
      })
      .select('a.id', 'a.uid as owner_id', 'a.name', 'a.is_public', 'a.create_time')
      .orderBy(`a.${sortField}`, sortOrder)
      .orderBy('a.id', 'desc');

    const [{ count }] = await base.clone().clearSelect().clearOrder().count('* as count');
    const items = await base.clone().offset(offset).limit(pageSize);

    //   - - 先一次性查询所有相册的封面行（ ai.is_cover = 1 ，每个相册最多取到 1 张用于预览）。
    // - 对“没有查到封面”的相册，再逐个相册查询最新 4 张（ where album_id = ? order by ... limit 4 ），并做了批量并发（每批 8 个相册）避免单次页里相册数量多时太慢。
    const albumIds = items.map(it => it.id);
    const previewsByAlbum = new Map();
    const validPaths = user ? await photoTimeLineService.getValidPaths(user) : [];
    const validPathsList = Array.isArray(validPaths) ? validPaths.filter(Boolean) : [];

    if (albumIds.length > 0 && validPathsList.length > 0) {
      const coverQuery = knex('photo_album_index as ai')
        .leftJoin('photo_index as p', 'ai.file_hash', 'p.file_hash')
        .whereIn('ai.album_id', albumIds)
        .andWhere('ai.is_cover', 1)
        .andWhere('p.is_file', 1)
        .andWhere('p.in_trash', 0);
      applyPathPrefixFilter(coverQuery, 'p.path', validPathsList);
      const coverRows = await coverQuery
        .select(
          'ai.album_id',
          'ai.create_time as index_create_time',
          'ai.id as album_index_id',
          'p.id as photo_id',
          'p.path',
          'p.filename',
          'p.file_hash',
          'p.type',
          'p.duration',
          'p.original_time',
          'p.original_date'
        )
        .orderBy([
          { column: 'ai.album_id', order: 'asc' },
          { column: 'ai.create_time', order: 'desc' },
          { column: 'ai.id', order: 'desc' },
        ]);

      for (const row of coverRows) {
        if (!row || !row.path || !row.filename) continue;
        if (previewsByAlbum.has(row.album_id)) continue;
        previewsByAlbum.set(row.album_id, [
          {
            id: row.photo_id,
            path: row.path,
            filename: row.filename,
            file_hash: row.file_hash,
            type: row.type,
            duration: row.duration,
            original_time: row.original_time,
            original_date: row.original_date,
            fullpath: path.join(row.path, row.filename),
          },
        ]);
      }

      const missingAlbumIds = albumIds.filter(id => !previewsByAlbum.has(id));
      const batchSize = 8;
      for (let i = 0; i < missingAlbumIds.length; i += batchSize) {
        const batch = missingAlbumIds.slice(i, i + batchSize);
        const batchResults = await Promise.all(
          batch.map(albumId => {
            const q = knex('photo_album_index as ai')
              .leftJoin('photo_index as p', 'ai.file_hash', 'p.file_hash')
              .where('ai.album_id', albumId)
              .andWhere('p.is_file', 1)
              .andWhere('p.in_trash', 0);
            applyPathPrefixFilter(q, 'p.path', validPathsList);
            return q
              .select(
                'ai.album_id',
                'ai.create_time as index_create_time',
                'ai.id as album_index_id',
                'p.id as photo_id',
                'p.path',
                'p.filename',
                'p.file_hash',
                'p.type',
                'p.duration',
                'p.original_time',
                'p.original_date'
              )
              .orderBy([
                { column: 'ai.create_time', order: 'desc' },
                { column: 'ai.id', order: 'desc' },
              ])
              .limit(previewLimit);
          })
        );

        for (let j = 0; j < batch.length; j++) {
          const albumId = batch[j];
          const rows = batchResults[j] || [];
          const previews = rows
            .filter(r => r && r.path && r.filename)
            .map(r => ({
              id: r.photo_id,
              path: r.path,
              filename: r.filename,
              file_hash: r.file_hash,
              type: r.type,
              duration: r.duration,
              original_time: r.original_time,
              original_date: r.original_date,
              fullpath: path.join(r.path, r.filename),
            }));
          previewsByAlbum.set(albumId, previews);
        }
      }
    }

    let ownerIdToUsername = new Map();
    if (knexMain) {
      const otherOwnerIds = [...new Set(
        items
          .filter(a => Number(a.owner_id) !== Number(uid))
          .map(a => Number(a.owner_id))
      )].filter(Boolean);
      if (otherOwnerIds.length > 0) {
        const rows = await knexMain('user').whereIn('id', otherOwnerIds).select('id', 'username');
        rows.forEach(r => { ownerIdToUsername.set(Number(r.id), r.username || ''); });
      }
    }

    const enriched = items.map(a => {
      const isOwner = Number(a.owner_id) === Number(uid);
      return {
        ...a,
        is_owner: isOwner,
        owner_username: isOwner ? undefined : (ownerIdToUsername.get(Number(a.owner_id)) ?? null),
        previews: previewsByAlbum.get(a.id) || [],
      };
    });

    return {
      items: enriched,
      pagination: {
        total: Number(count || 0),
        page,
        pageSize,
      },
    };
  }

  async getAlbum({ knexPhoto, knexMain }, albumId, user) {
    const { album } = await this._ensureAlbumAccess({ knexPhoto, albumId, user });
    const shares = await knexPhoto('photo_album_share as s').where({ album_id: album.id }).select('s.uid', 's.can_add', 's.can_delete', 's.create_time');

    const uidList = shares.map(s => s.uid);
    let usersById = new Map();
    if (uidList.length > 0) {
      const rows = await knexMain('user').whereIn('id', uidList).select('id', 'username');
      usersById = new Map(rows.map(r => [r.id, r.username]));
    }

    const shareItems = shares.map(s => ({
      uid: s.uid,
      username: usersById.get(s.uid) || null,
      can_add: s.can_add,
      can_delete: s.can_delete,
    }));

    return {
      id: album.id,
      owner_id: album.uid,
      name: album.name,
      is_public: album.is_public,
      create_time: album.create_time,
      shares: shareItems,
    };
  }

  async createAlbum({ knexPhoto }, payload, user) {
    const uid = this._uid(user);
    const name = String(payload.name || '').trim();
    const isPublic = payload.is_public ? 1 : 0;
    const shares = Array.isArray(payload.shares) ? payload.shares : [];
    if (!name) throw new Error('common.PARAM_ERROR');

    const dup = await knexPhoto('photo_album').where({ uid, name }).first();
    if (dup) {
      const err = new Error('photo.ALBUM_NAME_EXISTS');
      err.statusCode = 409;
      throw err;
    }

    return knexPhoto.transaction(async trx => {
      const [albumId] = await trx('photo_album').insert({
        uid,
        name,
        is_public: isPublic,
        create_time: new Date(),
      });

      if (!isPublic) {
        const rows = shares
          .filter(s => s && Number.isFinite(Number(s.uid)) && Number(s.uid) > 0 && Number(s.uid) !== Number(uid))
          .map(s => ({
            owner_id: uid,
            album_id: albumId,
            uid: Number(s.uid),
            can_add: s.can_add === 0 ? 0 : 1,
            can_delete: s.can_delete === 0 ? 0 : 1,
            create_time: new Date(),
          }));
        if (rows.length > 0) {
          await trx('photo_album_share').insert(rows);
        }
      }

      return { id: albumId };
    });
  }

  async updateAlbum({ knexPhoto }, payload, user) {
    const uid = this._uid(user);
    const albumId = Number(payload.id);
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');

    const existing = await this._getAlbumById(knexPhoto, albumId);
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
      const dup = await knexPhoto('photo_album').where({ uid: existing.uid, name }).andWhereNot({ id: albumId }).first();
      if (dup) {
        const err = new Error('photo.ALBUM_NAME_EXISTS');
        err.statusCode = 409;
        throw err;
      }
      data.name = name;
    }
    if (payload.is_public !== undefined) {
      data.is_public = payload.is_public ? 1 : 0;
    }
    const shares = Array.isArray(payload.shares) ? payload.shares : [];

    return knexPhoto.transaction(async trx => {
      if (Object.keys(data).length > 0) {
        await trx('photo_album').where({ id: albumId }).update(data);
      }

      const nowPublic = data.is_public !== undefined ? data.is_public : existing.is_public;
      await trx('photo_album_share').where({ album_id: albumId }).delete();
      if (!nowPublic) {
        const rows = shares
          .filter(s => s && Number.isFinite(Number(s.uid)) && Number(s.uid) > 0 && Number(s.uid) !== Number(existing.uid))
          .map(s => ({
            owner_id: existing.uid,
            album_id: albumId,
            uid: Number(s.uid),
            can_add: s.can_add === 0 ? 0 : 1,
            can_delete: s.can_delete === 0 ? 0 : 1,
            create_time: new Date(),
          }));
        if (rows.length > 0) {
          await trx('photo_album_share').insert(rows);
        }
      }
      return true;
    });
  }

  async deleteAlbum({ knexPhoto }, payload, user) {
    const uid = this._uid(user);
    const albumId = Number(payload.id);
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');

    const existing = await this._getAlbumById(knexPhoto, albumId);
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

    return knexPhoto.transaction(async trx => {
      await trx('photo_album_index').where({ album_id: albumId }).delete();
      await trx('photo_album_share').where({ album_id: albumId }).delete();
      const affected = await trx('photo_album').where({ id: albumId }).delete();
      return { affected };
    });
  }

  async addAlbumIndexes({ knexPhoto }, payload, user) {
    const uid = this._uid(user);
    const albumId = Number(payload.album_id);
    const fileHashes = Array.isArray(payload.file_hashes) ? payload.file_hashes : [];
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');
    if (fileHashes.length === 0) throw new Error('common.PARAM_ERROR');

    const access = await this._ensureAlbumAccess({ knexPhoto, albumId, user });
    if (access.role !== 'owner' && access.role !== 'admin') {
      if (access.role !== 'shared' || Number(access.share.can_add) !== 1) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
    }

    return knexPhoto.transaction(async trx => {
      const exists = await trx('photo_album_index').where({ album_id: albumId }).whereIn('file_hash', fileHashes).select('file_hash');
      const existingSet = new Set(exists.map(e => e.file_hash));
      const toInsert = fileHashes
        .filter(h => h && !existingSet.has(h))
        .map(h => ({
          album_id: albumId,
          file_hash: h,
          is_cover: 0,
          create_time: new Date(),
        }));
      if (toInsert.length > 0) {
        await trx('photo_album_index').insert(toInsert);
      }
      return { inserted: toInsert.length };
    });
  }

  async removeAlbumIndexes({ knexPhoto }, payload, user) {
    const albumId = Number(payload.album_id);
    const fileHashes = Array.isArray(payload.file_hashes) ? payload.file_hashes : [];
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');
    if (fileHashes.length === 0) throw new Error('common.PARAM_ERROR');

    const access = await this._ensureAlbumAccess({ knexPhoto, albumId, user });
    if (access.role !== 'owner' && access.role !== 'admin') {
      if (access.role !== 'shared' || Number(access.share.can_delete) !== 1) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
    }

    return knexPhoto.transaction(async trx => {
      const affected = await trx('photo_album_index').where({ album_id: albumId }).whereIn('file_hash', fileHashes).delete();

      const cover = await trx('photo_album_index').where({ album_id: albumId, is_cover: 1 }).first();
      if (!cover) {
        const first = await trx('photo_album_index').where({ album_id: albumId }).orderBy('id', 'asc').first();
        if (first) {
          await trx('photo_album_index').where({ id: first.id }).update({ is_cover: 1 });
        }
      }
      return { affected };
    });
  }

  async setAlbumCover({ knexPhoto }, payload, user) {
    const uid = this._uid(user);
    const albumId = Number(payload.album_id ?? payload.albumId);
    const fileHash = String(payload.file_hash ?? payload.fileHash ?? '').trim();
    if (!Number.isFinite(albumId) || albumId <= 0) throw new Error('common.PARAM_ERROR');
    if (!fileHash) throw new Error('common.PARAM_ERROR');

    const album = await this._getAlbumById(knexPhoto, albumId);
    if (!album) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    if (Number(album.uid) !== Number(uid)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    return knexPhoto.transaction(async trx => {
      await trx('photo_album_index').where({ album_id: albumId }).update({ is_cover: 0 });
      const updated = await trx('photo_album_index').where({ album_id: albumId, file_hash: fileHash }).update({ is_cover: 1 });
      if (!updated) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      return true;
    });
  }

  async listAlbumPhotoIndexRows({ knexPhoto }, params, user) {
    const raw =
      params.album_ids ??
      params.albumIds ??
      params.album_id ??
      params.albumId ??
      (params.body ? (params.body.album_ids ?? params.body.albumIds ?? params.body.album_id ?? params.body.albumId) : undefined);

    const validPaths = Array.isArray(params.validPaths) ? params.validPaths : [];

    const rawIds = Array.isArray(raw) ? raw : raw === null || raw === undefined ? [] : [raw];
    const albumIds = [];
    for (const v of rawIds) {
      if (v === null || v === undefined || v === '') continue;
      if (typeof v === 'string' && v.includes(',')) {
        for (const part of v.split(',')) {
          const id = Number(part);
          if (Number.isFinite(id) && id > 0) albumIds.push(id);
        }
        continue;
      }
      const id = Number(v);
      if (Number.isFinite(id) && id > 0) albumIds.push(id);
    }
    const uniqueAlbumIds = [...new Set(albumIds)];
    if (uniqueAlbumIds.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    for (const albumId of uniqueAlbumIds) {
      await this._ensureAlbumAccess({ knexPhoto, albumId, user });
    }

    const query = knexPhoto('photo_album_index as ai')
      .join('photo_index as p', 'ai.file_hash', 'p.file_hash')
      .whereIn('ai.album_id', uniqueAlbumIds)
      .andWhere('p.is_file', 1)
      .andWhere('p.in_trash', 0)
      .orderBy('p.original_time', 'desc')
      .orderBy('p.id', 'desc');

    if (validPaths.length > 0) {
      applyPathPrefixFilter(query, 'p.path', validPaths);
    }

    const rows = await query
      .select('ai.album_id as album_id', 'p.id as photo_id', 'p.path as path', 'p.filename as filename', 'p.file_hash as file_hash', 'p.original_time as original_time')
      .catch(() => []);
    return Array.isArray(rows) ? rows : [];
  }
}

module.exports = new PhotoAlbumService();
