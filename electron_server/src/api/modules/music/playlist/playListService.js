const path = require('path');
const userUtil = require('../../../../utils/userUtil');
const MusicListService = require('../list/musicListService');

function _escapeLikeValue(input) {
  return String(input || '')
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
}

function _normalizeSortBy(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  if (v === 'create_time' || v === 'name') return v;
  return 'create_time';
}

function _normalizeSortOrder(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  return v === 'asc' ? 'asc' : 'desc';
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
        this.where('x.path', p).orWhere('x.path', 'like', `${prefix}%`);
      });
    }
    for (const pair of folderExactPairs) {
      builder.orWhere(function () {
        this.where('x.show_type', 'series').andWhere('x.path', pair.parent).andWhere('x.filename', pair.name);
      });
    }
  });
}

function _normalizeIndexRow(row) {
  if (!row || typeof row !== 'object') return row;
  const baseDir = row.path === undefined || row.path === null ? '' : String(row.path).trim();
  const name = row.filename === undefined || row.filename === null ? '' : String(row.filename).trim();
  return {
    ...row,
    full_path: baseDir && name ? path.join(baseDir, name) : '',
  };
}

function _sqlIsUniqueViolation(err) {
  const msg = err && err.message ? String(err.message) : '';
  return msg.toLowerCase().includes('unique') || msg.toLowerCase().includes('constraint');
}

class PlayListService {
  constructor(knexMusic) {
    this.knexMusic = knexMusic;
    this.tableName = 'play_list';
    this.mapTableName = 'play_list2index';
  }

  _uid(user) {
    return user && user.id ? Number(user.id) : 0;
  }

  async _ensureListAccess({ listId, user }) {
    const id = Number(listId);
    if (!Number.isFinite(id) || id <= 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    const row = await this.knexMusic(this.tableName)
      .where({ id })
      .first('id', 'uid', 'name', 'create_time')
      .catch(() => null);
    if (!row || !row.id) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    const uid = this._uid(user);
    if (!userUtil.isAdmin(user) && uid && Number(row.uid) !== Number(uid)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }
    return row;
  }

  async listLists(params, user) {
    const uid = this._uid(user);
    if (!uid) {
      const err = new Error('auth.UNAUTHORIZED');
      err.statusCode = 401;
      throw err;
    }

    const safePage = Math.max(1, Number(params.page || 1) || 1);
    const safeLimit = Math.min(200, Math.max(1, Number(params.page_size ?? params.pageSize ?? 30) || 30));
    const offset = (safePage - 1) * safeLimit;

    const search = params.search === undefined || params.search === null ? '' : String(params.search).trim();
    const sortBy = _normalizeSortBy(params.sort_by ?? params.sortBy);
    const sortOrder = _normalizeSortOrder(params.sort_order ?? params.sortOrder);

    const base = this.knexMusic(`${this.tableName} as l`).where('l.uid', uid);
    if (search) {
      const escaped = _escapeLikeValue(search);
      base.andWhereRaw("l.name LIKE ? ESCAPE '\\'", [`%${escaped}%`]);
    }

    const countRow = await base
      .clone()
      .clearSelect()
      .clearOrder()
      .count('* as cnt')
      .first()
      .catch(() => null);
    const total = Math.max(0, Number((countRow && (countRow.cnt ?? countRow['count(*)'])) || 0) || 0);

    const listRows = await base.clone().select('l.id', 'l.uid', 'l.name', 'l.create_time').orderBy(`l.${sortBy}`, sortOrder).orderBy('l.id', 'desc').offset(offset).limit(safeLimit);

    const listIds = (listRows || []).map(r => Number(r && r.id ? r.id : 0)).filter(v => v > 0);
    const previewsByListId = new Map();
    if (listIds.length > 0) {
      const musicListService = new MusicListService(this.knexMusic);
      const validPaths = await musicListService.getValidPaths(user);

      const knex = this.knexMusic;
      const basePreviewQuery = knex(`${this.mapTableName} as m`)
        .join('music_index as x', 'm.index_id', 'x.id')
        .whereIn('m.list_id', listIds)
        .whereIn('x.show_type', ['music', 'series', 'submusic'])
        .where('x.has_inner_cover', 1);

      if (!validPaths || validPaths.length === 0) {
        basePreviewQuery.whereRaw('1 = 0');
      } else {
        _applyMusicIndexPathPrefixFilter(basePreviewQuery, validPaths);
      }

      const rows = await basePreviewQuery
        .select(
          'm.list_id as list_id',
          'x.id',
          'x.path',
          'x.filename',
          'x.ext',
          'x.size',
          'x.duration',
          'x.file_hash',
          'x.title',
          'x.artist',
          'x.album',
          'x.year',
          'x.has_inner_cover',
          'x.show_type',
          'x.music_count',
          knex.raw(
            `
            case
              when x.show_type = 'series' then (
                select path || ? || filename
                from music_index as s
                where s.show_type = 'submusic'
                  and (s.path = (x.path || ? || x.filename) or s.path like ((x.path || ? || x.filename) || ? || '%'))
                order by s.has_inner_cover desc, s.id asc
                limit 1
              )
              else ''
            end as first_file_path
            `,
            [path.sep, path.sep, path.sep, path.sep]
          )
        )
        .orderBy([
          { column: 'm.list_id', order: 'asc' },
          { column: 'm.create_time', order: 'desc' },
          { column: 'm.index_id', order: 'desc' },
        ])
        .catch(() => []);

      for (const r of rows) {
        const lid = Number(r && r.list_id ? r.list_id : 0);
        if (!lid) continue;
        const arr = previewsByListId.get(lid) || [];
        if (arr.length >= 4) continue;
        arr.push(_normalizeIndexRow(r));
        previewsByListId.set(lid, arr);
      }
    }

    const enriched = (listRows || []).map(r => ({
      id: r.id,
      uid: r.uid,
      name: r.name,
      create_time: r.create_time,
      previews: previewsByListId.get(Number(r.id)) || [],
    }));

    return {
      items: enriched,
      pagination: {
        total,
        page: safePage,
        pageSize: safeLimit,
      },
    };
  }

  async getList({ listId, user }) {
    const row = await this._ensureListAccess({ listId, user });
    return {
      id: row.id,
      uid: row.uid,
      name: row.name,
      create_time: row.create_time,
    };
  }

  async createList({ name, user }) {
    const uid = this._uid(user);
    if (!uid) {
      const err = new Error('auth.UNAUTHORIZED');
      err.statusCode = 401;
      throw err;
    }
    const n = name === undefined || name === null ? '' : String(name).trim();
    if (!n) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    try {
      const [id] = await this.knexMusic(this.tableName).insert({ uid, name: n });
      const createdRow = await this.knexMusic(this.tableName)
        .where({ id: Number(id) || 0 })
        .first('create_time')
        .catch(() => null);
      return {
        id: Number(id) || 0,
        uid,
        name: n,
        create_time: createdRow && createdRow.create_time ? createdRow.create_time : '',
      };
    } catch (e) {
      if (_sqlIsUniqueViolation(e)) {
        const err = new Error('common.DUPLICATE');
        err.statusCode = 409;
        throw err;
      }
      throw e;
    }
  }

  async updateList({ listId, name, user }) {
    const row = await this._ensureListAccess({ listId, user });
    const n = name === undefined || name === null ? '' : String(name).trim();
    if (!n) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    try {
      const affected = await this.knexMusic(this.tableName).where({ id: row.id }).update({ name: n });
      if (!affected) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      return { id: row.id, uid: row.uid, name: n, create_time: row.create_time };
    } catch (e) {
      if (_sqlIsUniqueViolation(e)) {
        const err = new Error('common.DUPLICATE');
        err.statusCode = 409;
        throw err;
      }
      throw e;
    }
  }

  async deleteList({ listId, user }) {
    const row = await this._ensureListAccess({ listId, user });
    const affected = await this.knexMusic(this.tableName).where({ id: row.id }).delete();
    if (!affected) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    return true;
  }

  async addListIndexes({ listId, indexIds, user }) {
    const row = await this._ensureListAccess({ listId, user });

    const raw = Array.isArray(indexIds) ? indexIds : indexIds === null || indexIds === undefined ? [] : [indexIds];
    const ids = raw
      .map(v => Number(v))
      .filter(v => Number.isFinite(v) && v > 0)
      .filter((v, i, arr) => arr.indexOf(v) === i);
    if (ids.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const rows = await this.knexMusic('music_index')
      .whereIn('id', ids)
      .whereIn('show_type', ['music', 'series', 'submusic'])
      .select('id', 'path', 'filename', 'show_type')
      .catch(() => []);

    if (!rows || rows.length === 0) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const musicListService = new MusicListService(this.knexMusic);
    const roots = await musicListService.getValidPaths(user);
    const isUnderAnyRoot = (filePath, rootList) => {
      const resolved = filePath ? path.resolve(String(filePath)) : '';
      if (!resolved) return false;
      const list = Array.isArray(rootList) ? rootList.map(p => path.resolve(String(p || ''))).filter(Boolean) : [];
      for (const root of list) {
        if (resolved === root) return true;
        const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
        if (resolved.startsWith(prefix)) return true;
      }
      return false;
    };
    const canAccessIndexRow = indexRow => {
      if (!indexRow || !indexRow.path || !indexRow.filename) return false;
      const full = path.join(String(indexRow.path), String(indexRow.filename));
      return isUnderAnyRoot(full, roots);
    };

    for (const idx of rows) {
      if (!canAccessIndexRow(idx)) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
    }

    const seriesFolderPaths = rows
      .filter(r => (r && r.show_type ? String(r.show_type) : '') === 'series')
      .map(r => (r && r.path && r.filename ? path.join(String(r.path), String(r.filename)) : ''))
      .filter(Boolean)
      .filter((v, i, arr) => arr.indexOf(v) === i);

    const submusicRows =
      seriesFolderPaths.length > 0
        ? await this.knexMusic('music_index')
            .whereIn('path', seriesFolderPaths)
            .andWhere('show_type', 'submusic')
            .select('id', 'path', 'filename', 'show_type')
            .catch(() => [])
        : [];

    for (const idx of submusicRows) {
      if (!canAccessIndexRow(idx)) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
    }

    const targetIds = [];
    for (const r of rows) {
      const showType = r && r.show_type ? String(r.show_type) : '';
      if (showType !== 'music' && showType !== 'submusic') continue;
      const id = Number(r && r.id) || 0;
      if (id > 0) targetIds.push(id);
    }
    for (const r of submusicRows) {
      const id = Number(r && r.id) || 0;
      if (id > 0) targetIds.push(id);
    }
    const uniqueTargetIds = Array.from(new Set(targetIds));
    const insertRows = uniqueTargetIds.map(id => ({ list_id: row.id, index_id: id }));

    if (insertRows.length > 0) {
      await this.knexMusic(this.mapTableName).insert(insertRows).onConflict(['list_id', 'index_id']).ignore();
    }
    return true;
  }

  async removeListIndexes({ listId, indexIds, user }) {
    const row = await this._ensureListAccess({ listId, user });

    const raw = Array.isArray(indexIds) ? indexIds : indexIds === null || indexIds === undefined ? [] : [indexIds];
    const ids = raw
      .map(v => Number(v))
      .filter(v => Number.isFinite(v) && v > 0)
      .filter((v, i, arr) => arr.indexOf(v) === i);
    if (ids.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    await this.knexMusic(this.mapTableName).where({ list_id: row.id }).whereIn('index_id', ids).delete();
    return true;
  }
}

module.exports = PlayListService;
