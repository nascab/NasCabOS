const BookListService = require('../list/bookListService');
const path = require('path');
const fs = require('fs');

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

function _normalizeListRow(row) {
  if (!row || typeof row !== 'object') return row;
  const baseDir = row.path === undefined || row.path === null ? '' : String(row.path).trim();
  const name = row.filename === undefined || row.filename === null ? '' : String(row.filename).trim();
  return {
    ...row,
    full_path: baseDir && name ? path.join(baseDir, name) : '',
  };
}

class BookHistoryService {
  constructor(knexBook) {
    this.knexBook = knexBook;
    this.tableName = 'book_history';
  }

  async getIndexByFileHash(fileHash) {
    const fh = fileHash === undefined || fileHash === null ? '' : String(fileHash).trim();
    if (!fh) return null;
    return await this.knexBook('book_index')
      .where({ file_hash: fh, is_file: 1 })
      .first('id', 'path', 'filename', 'file_hash', 'type', 'ext', 'total_page')
      .catch(() => null);
  }

  async canUserAccessIndex(user, indexRow) {
    const service = new BookListService(this.knexBook);
    return await service.canUserAccessIndex({ user, indexRow });
  }

  async getProgress({ uid, fileHash }) {
    const u = Number(uid || 0) || 0;
    const fh = fileHash === undefined || fileHash === null ? '' : String(fileHash).trim();
    if (!u || !fh) return null;
    return await this.knexBook(this.tableName)
      .where({ uid: u, file_hash: fh })
      .first('uid', 'file_hash', 'current_page', 'total_page', 'fraction', 'last_read_at')
      .catch(() => null);
  }

  async upsertProgress({ uid, fileHash, currentPage, totalPage, fraction }) {
    const u = Number(uid || 0) || 0;
    const fh = fileHash === undefined || fileHash === null ? '' : String(fileHash).trim();
    if (!u || !fh) return null;

    const page = Math.max(0, Number(currentPage || 0) || 0);
    const total = Math.max(0, Number(totalPage || 0) || 0);
    const fracRaw = Number(fraction);
    const frac = Number.isFinite(fracRaw) ? Math.max(0, Math.min(1, fracRaw)) : 0;
    const row = {
      uid: u,
      file_hash: fh,
      current_page: page,
      total_page: total,
      fraction: frac,
      last_read_at: new Date(),
    };

    await this.knexBook(this.tableName).insert(row).onConflict(['uid', 'file_hash']).merge(row);
    return await this.getProgress({ uid: u, fileHash: fh });
  }

  async clearAll({ user }) {
    const uid = user && user.id ? Number(user.id) : 0;
    if (!uid) {
      const err = new Error('auth.UNAUTHORIZED');
      err.statusCode = 401;
      throw err;
    }
    const deleted = await this.knexBook(this.tableName)
      .where({ uid })
      .delete()
      .catch(() => 0);
    return Number(deleted) || 0;
  }

  async listHistory({ user, limit = 200 }) {
    const uid = user && user.id ? Number(user.id) : 0;
    if (!uid) {
      const err = new Error('auth.UNAUTHORIZED');
      err.statusCode = 401;
      throw err;
    }

    const safeLimit = Math.min(200, Math.max(1, Number(limit) || 200));
    const bookListService = new BookListService(this.knexBook);
    const validPaths = await bookListService.getValidPaths(user);
    const validPathsWithStatus = (validPaths || []).map(p => ({
      path: p,
      valid: fs.existsSync(p),
    }));

    const knex = this.knexBook;
    const baseQuery = knex(`${this.tableName} as h`).join('book_index as b', 'b.file_hash', 'h.file_hash').where('h.uid', uid).andWhere('b.is_file', 1).whereIn('b.show_type', ['book', 'subbook']);

    if (!validPaths || validPaths.length === 0) {
      baseQuery.whereRaw('1 = 0');
    } else {
      _applyBookIndexPathPrefixFilter(baseQuery, validPaths);
    }

    const countRow = await baseQuery
      .clone()
      .clearSelect()
      .clearOrder()
      .countDistinct({ cnt: 'b.id' })
      .first()
      .catch(() => null);
    const total = Math.max(0, Number((countRow && (countRow.cnt ?? countRow['count(`b`.`id`)'] ?? countRow['count(*)'])) || 0) || 0);

    const rows = await baseQuery
      .clone()
      .select(
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
        'h.current_page',
        'h.fraction',
        'h.last_read_at',
        knex.raw("'' as first_file_path")
      )
      .orderBy('h.last_read_at', 'desc')
      .orderBy('h.id', 'desc')
      .limit(safeLimit)
      .catch(() => []);

    const items = (rows || []).map(r => _normalizeListRow(r));
    for (const item of items) {
      if (item && typeof item === 'object') item.is_favorite = false;
    }

    return {
      items,
      validPaths: validPathsWithStatus,
      pagination: {
        total,
        page: 1,
        limit: safeLimit,
        totalPages: total > 0 ? 1 : 0,
        hasNextPage: false,
        hasPrevPage: false,
      },
    };
  }
}

module.exports = BookHistoryService;
