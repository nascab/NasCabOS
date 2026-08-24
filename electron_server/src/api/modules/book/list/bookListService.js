const path = require('path');
const fs = require('fs');
const userUtil = require('../../../../utils/userUtil');
const BookSourceService = require('../source/bookSourceService');
const { intersectPaths, parsePathListText } = require('../../photo/timeline/photoPathQueryUtil');

function _escapeLikeValue(input) {
  return String(input || '')
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
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

function _normalizeType(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  if (v === 'book' || v === 'comic') return v;
  return '';
}

function _normalizeTypeList(input) {
  if (Array.isArray(input)) {
    const list = input.map(v => _normalizeType(v)).filter(Boolean);
    return [...new Set(list)];
  }
  const s = input === undefined || input === null ? '' : String(input).trim();
  if (!s) return [];
  if (s.startsWith('[')) {
    try {
      const arr = JSON.parse(s);
      if (!Array.isArray(arr)) return [];
      const list = arr.map(v => _normalizeType(v)).filter(Boolean);
      return [...new Set(list)];
    } catch (_) {
      return [];
    }
  }
  const single = _normalizeType(s);
  return single ? [single] : [];
}

function _normalizeSortBy(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  if (v === 'view_time' || v === 'create_time' || v === 'favorite_time' || v === 'name' || v === 'title' || v === 'artist' || v === 'year') return v;
  return 'create_time';
}

function _normalizeSortOrder(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  return v === 'asc' ? 'asc' : 'desc';
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

function _isUnderAnyRoot({ filePath, roots }) {
  const resolved = filePath ? path.resolve(String(filePath)) : '';
  if (!resolved) return false;
  const list = Array.isArray(roots) ? roots.map(p => path.resolve(String(p || ''))).filter(Boolean) : [];
  for (const root of list) {
    if (resolved === root) return true;
    const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
    if (resolved.startsWith(prefix)) return true;
  }
  return false;
}

class BookListService {
  constructor(knexBook) {
    this.knexBook = knexBook;
  }

  async getValidPaths(user) {
    const service = new BookSourceService(this.knexBook);
    return await service.getValidPaths(user);
  }

  async getVisibleIndexCounts(params, user) {
    const validPaths = await this.getValidPaths(user);
    let finalPaths = validPaths;

    const sourceList = Array.isArray(params && params.sourceList) ? params.sourceList : Array.isArray(params && params.source_list) ? params.source_list : null;
    if (sourceList && sourceList.length > 0) {
      finalPaths = intersectPaths(finalPaths, sourceList);
    }

    const collectionId = Number(params && (params.collection_id ?? params.collectionId));
    if (Number.isFinite(collectionId) && collectionId > 0) {
      const collection = await this.knexBook('book_collection')
        .where({ id: collectionId })
        .first()
        .catch(() => null);
      if (!collection) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      const uid = user && user.id ? Number(user.id) : 0;
      if (user && !userUtil.isAdmin(user) && uid && Number(collection.uid) !== Number(uid)) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
      const collectionPaths = parsePathListText(collection.path_list);
      finalPaths = intersectPaths(finalPaths, collectionPaths);
    }

    if (!finalPaths || finalPaths.length === 0) {
      return { book: 0, comic: 0, total: 0 };
    }

    const rows = await this.knexBook('book_index as b')
      .whereIn('b.show_type', ['book', 'series'])
      .modify(qb => _applyBookIndexPathPrefixFilter(qb, finalPaths))
      .groupBy('b.type')
      .select('b.type')
      .count({ total: '*' })
      .catch(() => []);

    let book = 0;
    let comic = 0;
    for (const r of rows || []) {
      const t = r && r.type ? String(r.type).trim() : '';
      const cnt = Number(r && r.total);
      const v = Number.isFinite(cnt) ? cnt : Number(String(r && r.total ? r.total : 0)) || 0;
      if (t === 'book') book = v;
      if (t === 'comic') comic = v;
    }
    return { book, comic, total: book + comic };
  }

  async listPaged(params, user) {
    const uid = user && user.id ? Number(user.id) : 0;
    const safePage = Math.max(1, Number(params.page || 1) || 1);
    const safeLimit = Math.min(200, Math.max(1, Number(params.page_size ?? params.pageSize ?? 30) || 30));
    const offset = (safePage - 1) * safeLimit;

    const search = params.search === undefined || params.search === null ? '' : String(params.search).trim();
    const typeList = _normalizeTypeList(params.type ?? params.types);
    const sortBy = _normalizeSortBy(params.sort_by ?? params.sortBy);
    const sortOrder = _normalizeSortOrder(params.sort_order ?? params.sortOrder);
    const isFavoriteList = Number(params.is_favorite ?? params.isFavorite) === 1;

    const validPaths = await this.getValidPaths(user);
    let finalPaths = validPaths;

    const sourceList = Array.isArray(params.sourceList) ? params.sourceList : Array.isArray(params.source_list) ? params.source_list : null;
    if (sourceList && sourceList.length > 0) {
      finalPaths = intersectPaths(finalPaths, sourceList);
    }

    const collectionId = Number(params && (params.collection_id ?? params.collectionId));
    if (Number.isFinite(collectionId) && collectionId > 0) {
      const collection = await this.knexBook('book_collection')
        .where({ id: collectionId })
        .first()
        .catch(() => null);
      if (!collection) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      if (user && !userUtil.isAdmin(user) && uid && Number(collection.uid) !== Number(uid)) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
      const collectionPaths = parsePathListText(collection.path_list);
      finalPaths = intersectPaths(finalPaths, collectionPaths);
    }

    const validPathsWithStatus = (validPaths || []).map(p => ({
      path: p,
      valid: fs.existsSync(p),
    }));

    const knex = this.knexBook;

    const listId = Number(params && (params.list_id ?? params.listId));
    if (Number.isFinite(listId) && listId > 0) {
      const listRow = await knex('book_list')
        .where({ id: listId })
        .first('id', 'uid')
        .catch(() => null);
      if (!listRow || !listRow.id) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      if (!userUtil.isAdmin(user) && uid && Number(listRow.uid) !== Number(uid)) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
    }

    const seriesIndexId = Number(params && (params.series_index_id ?? params.seriesIndexId));
    let seriesIndexBasePath = '';
    if (Number.isFinite(seriesIndexId) && seriesIndexId > 0) {
      const seriesRow = await knex('book_index')
        .where({ id: seriesIndexId })
        .first('id', 'path', 'filename', 'show_type')
        .catch(() => null);
      if (!seriesRow || !seriesRow.id) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      const showType = seriesRow.show_type ? String(seriesRow.show_type) : '';
      if (showType !== 'series') {
        const err = new Error('common.PARAM_ERROR');
        err.statusCode = 400;
        throw err;
      }
      const full = path.join(String(seriesRow.path || ''), String(seriesRow.filename || ''));
      if (!full) {
        const err = new Error('common.PARAM_ERROR');
        err.statusCode = 400;
        throw err;
      }
      if (!_isUnderAnyRoot({ filePath: full, roots: validPaths })) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
      seriesIndexBasePath = full;
    }

    const baseQuery = knex('book_index as b')
      .whereIn('b.show_type', seriesIndexBasePath ? ['book', 'series', 'subbook'] : ['book', 'series'])
      .modify(qb => {
        if (isFavoriteList) {
          qb.join('book_favorite as fav', function () {
            this.on('fav.index_id', '=', 'b.id').andOn('fav.uid', '=', knex.raw('?', [uid]));
          });
        }
      })
      .modify(qb => {
        if (seriesIndexBasePath) {
          qb.andWhere('b.path', seriesIndexBasePath);
        }
      })
      .modify(qb => {
        if (typeList.length > 0) qb.andWhere(builder => builder.whereIn('b.type', typeList));
      })
      .modify(qb => {
        if (Number.isFinite(listId) && listId > 0) {
          qb.join('book_list2index as m', function () {
            this.on('m.index_id', '=', 'b.id').andOn('m.list_id', '=', knex.raw('?', [listId]));
          });
        }
      });

    if (finalPaths.length === 0) {
      baseQuery.whereRaw('1 = 0');
    } else {
      _applyBookIndexPathPrefixFilter(baseQuery, finalPaths);
    }

    if (search) {
      const chars = Array.from(search);
      const first = chars[0] || '';
      if (chars.length === 1 && (first === '#' || /[a-z]/i.test(first))) {
        const fl = first === '#' ? '#' : first.toUpperCase();
        baseQuery.andWhere(builder => {
          builder.where('b.title_fl', fl).orWhere('b.filename_fl', fl);
        });
      } else {
        const escaped = _escapeLikeValue(search);
        baseQuery.andWhere(builder => {
          builder.whereRaw("b.title LIKE ? ESCAPE '\\'", [`%${escaped}%`]).orWhereRaw("b.filename LIKE ? ESCAPE '\\'", [`%${escaped}%`]);
        });
      }
    }

    const countRow = await baseQuery
      .clone()
      .clearSelect()
      .clearOrder()
      .countDistinct({ cnt: 'b.id' })
      .first()
      .catch(() => null);
    const total = Math.max(0, Number((countRow && (countRow.cnt ?? countRow['count(`b`.`id`)'] ?? countRow['count(*)'])) || 0) || 0);

    const query = baseQuery
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
        'b.book_count'
      );

    query.select(
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
    );

    if (sortBy === 'view_time') {
      query.orderBy('b.view_time', sortOrder);
    } else if (sortBy === 'favorite_time' && isFavoriteList) {
      query.orderBy('fav.create_time', sortOrder);
      query.orderBy('fav.id', 'desc');
    } else if (sortBy === 'name' || sortBy === 'title') {
      query.orderByRaw(`lower(case when b.title is not null and trim(b.title) != '' then b.title else b.filename end) ${sortOrder}`);
    } else if (sortBy === 'artist') {
      query.orderByRaw(`lower(case when b.artist is not null and trim(b.artist) != '' then b.artist else '' end) ${sortOrder}`);
    } else if (sortBy === 'year') {
      query.orderByRaw(`lower(case when b.year is not null and trim(b.year) != '' then b.year else '' end) ${sortOrder}`);
    } else {
      query.orderBy('b.create_time', sortOrder);
    }
    query.orderBy('b.id', 'desc');

    const rows = await query
      .limit(safeLimit)
      .offset(offset)
      .catch(() => []);
    const items = (rows || []).map(r => _normalizeListRow(r));
    if (isFavoriteList) {
      for (const item of items) {
        if (item && typeof item === 'object') item.is_favorite = true;
      }
    } else if (uid && items.length > 0) {
      for (const item of items) {
        if (item && typeof item === 'object') item.is_favorite = false;
      }
      const ids = items.map(r => Number(r && r.id) || 0).filter(v => v > 0);
      if (ids.length > 0) {
        const favRows = await knex('book_favorite')
          .where({ uid })
          .whereIn('index_id', ids)
          .select('index_id')
          .catch(() => []);
        const favSet = new Set((favRows || []).map(r => Number(r && r.index_id) || 0).filter(v => v > 0));
        for (const item of items) {
          const id = Number(item && item.id) || 0;
          if (item && typeof item === 'object') item.is_favorite = favSet.has(id);
        }
      }
    }
    const totalPages = Math.ceil(total / safeLimit);
    return {
      items,
      validPaths: validPathsWithStatus,
      pagination: {
        total,
        page: safePage,
        limit: safeLimit,
        totalPages,
        hasNextPage: safePage < totalPages,
        hasPrevPage: safePage > 1,
      },
    };
  }

  async getIndexByFileHash({ fileHash }) {
    const fh = fileHash === undefined || fileHash === null ? '' : String(fileHash).trim();
    if (!fh) return null;
    return await this.knexBook('book_index')
      .where({ file_hash: fh, is_file: 1 })
      .first('id', 'path', 'filename', 'file_hash', 'cover_state')
      .catch(() => null);
  }

  async deleteIndexesByFullPaths(fullPaths) {
    const input = Array.isArray(fullPaths) ? fullPaths : [];
    const normalized = input
      .map(v => String(v || '').trim())
      .filter(Boolean)
      .map(p => path.resolve(p));
    const targets = Array.from(new Set(normalized));
    if (targets.length === 0) return 0;

    const sep = path.sep;
    return await this.knexBook.transaction(async trx => {
      let affectedTotal = 0;

      for (const fullPath of targets) {
        const resolved = fullPath ? path.resolve(String(fullPath)) : '';
        if (!resolved) continue;

        const ext = path.extname(resolved);
        if (ext) {
          const dir = path.dirname(resolved);
          const name = path.basename(resolved);
          if (!dir || !name) continue;
          const affected = await trx('book_index')
            .where({ path: dir, filename: name })
            .delete()
            .catch(() => 0);
          affectedTotal += Number(affected || 0) || 0;
          continue;
        }

        const targetDir = resolved;
        const prefix = targetDir.endsWith(sep) ? targetDir : `${targetDir}${sep}`;
        const affectedSubtree = await trx('book_index')
          .where(qb => {
            qb.where('path', targetDir).orWhere('path', 'like', `${prefix}%`);
          })
          .delete()
          .catch(() => 0);
        affectedTotal += Number(affectedSubtree || 0) || 0;

        const parentDir = path.dirname(targetDir);
        const folderName = path.basename(targetDir);
        if (parentDir && folderName) {
          const affectedSeries = await trx('book_index')
            .where({ path: parentDir, filename: folderName })
            .delete()
            .catch(() => 0);
          affectedTotal += Number(affectedSeries || 0) || 0;
        }
      }

      return affectedTotal;
    });
  }

  async canUserAccessIndex({ user, indexRow }) {
    if (!indexRow || !indexRow.path || !indexRow.filename) return false;
    const roots = await this.getValidPaths(user);
    const full = path.join(String(indexRow.path), String(indexRow.filename));
    return _isUnderAnyRoot({ filePath: full, roots });
  }
}

module.exports = BookListService;
