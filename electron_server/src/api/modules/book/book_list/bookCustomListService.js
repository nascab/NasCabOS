const path = require('path');
const userUtil = require('../../../../utils/userUtil');
const BookListService = require('../list/bookListService');

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

function _applyBookIndexPathPrefixFilter(query, paths) {
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
        this.where('b.path', p).orWhere('b.path', 'like', `${prefix}%`);
      });
    }
    for (const pair of folderExactPairs) {
      builder.orWhere(function () {
        this.where('b.is_file', 0).andWhere('b.path', pair.parent).andWhere('b.filename', pair.name);
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

class BookCustomListService {
  constructor(knexBook) {
    this.knexBook = knexBook;
    this.tableName = 'book_list';
    this.mapTableName = 'book_list2index';
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
    const row = await this.knexBook(this.tableName)
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

    const base = this.knexBook(`${this.tableName} as l`).where('l.uid', uid);
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
      const bookListService = new BookListService(this.knexBook);
      const validPaths = await bookListService.getValidPaths(user);

      const knex = this.knexBook;
      const basePreviewQuery = knex(`${this.mapTableName} as m`).join('book_index as b', 'm.index_id', 'b.id').whereIn('m.list_id', listIds).whereIn('b.show_type', ['book', 'series']);

      if (!validPaths || validPaths.length === 0) {
        basePreviewQuery.whereRaw('1 = 0');
      } else {
        _applyBookIndexPathPrefixFilter(basePreviewQuery, validPaths);
      }

      const rows = await basePreviewQuery
        .select(
          'm.list_id as list_id',
          'b.id',
          'b.type',
          'b.path',
          'b.filename',
          'b.file_hash',
          'b.title',
          'b.artist',
          'b.year',
          'b.ext',
          'b.size',
          'b.cover_state',
          'b.view_time',
          'b.create_time',
          'b.show_type',
          'b.total_page',
          'b.book_count',
          knex.raw(
            `
            case
              when b.show_type = 'series' then (
                select path || ? || filename
                from book_index as s
                where s.show_type = 'subbook'
                  and s.is_file = 1
                  and s.path = (b.path || ? || b.filename)
                order by s.id asc
                limit 1
              )
              else ''
            end as first_file_path
            `,
            [path.sep, path.sep]
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
      const [id] = await this.knexBook(this.tableName).insert({ uid, name: n });
      return { id: Number(id) || 0, uid, name: n };
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
      const affected = await this.knexBook(this.tableName).where({ id: row.id }).update({ name: n });
      if (!affected) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      return { id: row.id, uid: row.uid, name: n };
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
    const affected = await this.knexBook(this.tableName).where({ id: row.id }).delete();
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

    const rows = await this.knexBook('book_index')
      .whereIn('id', ids)
      .whereIn('show_type', ['book', 'series'])
      .select('id', 'path', 'filename', 'show_type')
      .catch(() => []);

    if (!rows || rows.length === 0) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const bookListService = new BookListService(this.knexBook);
    for (const idx of rows) {
      const can = await bookListService.canUserAccessIndex({ user, indexRow: idx });
      if (!can) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
    }

    const insertRows = rows.map(r => ({
      list_id: row.id,
      index_id: r.id,
    }));

    await this.knexBook(this.mapTableName).insert(insertRows).onConflict(['list_id', 'index_id']).ignore();
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

    await this.knexBook(this.mapTableName).where({ list_id: row.id }).whereIn('index_id', ids).delete();
    return true;
  }
}

module.exports = BookCustomListService;
