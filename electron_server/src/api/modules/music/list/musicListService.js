const path = require('path');
const fs = require('fs');
const MusicSourceService = require('../source/musicSourceService');
const { intersectPaths, parsePathListText } = require('../../photo/timeline/photoPathQueryUtil');
const userUtil = require('../../../../utils/userUtil');

function _escapeLikeValue(input) {
  return String(input || '')
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
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

function _normalizeKeyList(input) {
  if (Array.isArray(input)) {
    return input.map(v => String(v || '').trim()).filter(Boolean);
  }
  const s = input === undefined || input === null ? '' : String(input).trim();
  if (!s) return [];
  if (s.startsWith('[')) {
    try {
      const arr = JSON.parse(s);
      return Array.isArray(arr) ? arr.map(v => String(v || '').trim()).filter(Boolean) : [];
    } catch (_) {
      return [];
    }
  }
  return s
    .split(',')
    .map(v => String(v || '').trim())
    .filter(Boolean);
}

function _normalizeSortBy(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  if (v === 'title' || v === 'name' || v === 'artist' || v === 'album' || v === 'year' || v === 'duration' || v === 'ctime' || v === 'mtime' || v === 'favorite_time') return v;
  return 'mtime';
}

function _normalizeKeySortBy(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  if (v === 'name') return v;
  if (v === 'count' || v === 'index_count' || v === 'indexcount') return 'count';
  return 'name';
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

class MusicListService {
  constructor(knexMusic) {
    this.knexMusic = knexMusic;
  }

  async getValidPaths(user) {
    const service = new MusicSourceService(this.knexMusic);
    return await service.getValidPaths(user);
  }

  async getLibraryCounts(params, user) {
    const validPaths = await this.getValidPaths(user);
    let finalPaths = validPaths;

    const sourceList = Array.isArray(params.sourceList) ? params.sourceList : Array.isArray(params.source_list) ? params.source_list : null;
    if (sourceList && sourceList.length > 0) {
      finalPaths = intersectPaths(finalPaths, sourceList);
    }

    const knex = this.knexMusic;

    const songCountRow = await knex('music_index as m')
      .whereIn('m.show_type', ['music', 'submusic'])
      .modify(qb => {
        if (!finalPaths || finalPaths.length === 0) {
          qb.whereRaw('1 = 0');
          return;
        }
        _applyMusicIndexPathPrefixFilter(qb, finalPaths);
      })
      .count({ cnt: '*' })
      .first()
      .catch(() => null);
    const songs = Math.max(0, Number((songCountRow && (songCountRow.cnt ?? songCountRow['count(*)'])) || 0) || 0);

    return { songs };
  }

  async listPaged(params, user) {
    const uid = user && user.id ? Number(user.id) : 0;
    const safePage = Math.max(1, Number(params.page || 1) || 1);
    const safeLimit = Math.min(200, Math.max(1, Number(params.page_size ?? params.pageSize ?? 30) || 30));
    const offset = (safePage - 1) * safeLimit;

    const search = params.search === undefined || params.search === null ? '' : String(params.search).trim();
    const listType = String(params.listType ?? params.list_type ?? '')
      .trim()
      .toLowerCase();
    const artists = _normalizeKeyList(params.artists ?? params.artist);
    const albums = _normalizeKeyList(params.albums ?? params.album);
    const genres = _normalizeKeyList(params.genres ?? params.genre);
    const sortBy = _normalizeSortBy(params.sort_by ?? params.sortBy);
    const sortOrder = _normalizeSortOrder(params.sort_order ?? params.sortOrder);
    const isFavoriteList = Number(params.is_favorite ?? params.isFavorite) === 1;
    const historyRaw = params.isHistory ?? params.is_history ?? params.isHistoryList ?? params.is_history_list;
    const isHistoryList = historyRaw === true || historyRaw === 1 || historyRaw === '1';

    const validPaths = await this.getValidPaths(user);
    let finalPaths = validPaths;

    const collectionId = Number(params && (params.collection_id ?? params.collectionId));
    if (Number.isFinite(collectionId) && collectionId > 0) {
      const collection = await this.knexMusic('music_collection').where({ id: collectionId }).first();
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

    const sourceList = Array.isArray(params.sourceList) ? params.sourceList : Array.isArray(params.source_list) ? params.source_list : null;
    if (sourceList && sourceList.length > 0) {
      finalPaths = intersectPaths(finalPaths, sourceList);
    }
    const validPathsWithStatus = (validPaths || []).map(p => ({
      path: p,
      valid: fs.existsSync(p),
    }));

    const knex = this.knexMusic;

    const listId = Number(params && (params.list_id ?? params.listId));
    if (Number.isFinite(listId) && listId > 0) {
      const listRow = await knex('play_list')
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

    let seriesIndexBasePath = '';
    const seriesIndexId = Number(params && (params.series_index_id ?? params.seriesIndexId));
    if (Number.isFinite(seriesIndexId) && seriesIndexId > 0) {
      const seriesRow = await knex('music_index')
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
        const err = new Error('validation.VALIDATION_ERROR');
        err.statusCode = 400;
        throw err;
      }
      const full = path.join(String(seriesRow.path || ''), String(seriesRow.filename || ''));
      if (!full) {
        const err = new Error('validation.VALIDATION_ERROR');
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

    let showTypeList = ['music', 'series'];
    if (seriesIndexBasePath) {
      showTypeList = ['submusic'];
    } else if (artists.length > 0 || albums.length > 0 || genres.length > 0) {
      showTypeList = ['music', 'submusic'];
    } else if (isHistoryList) {
      showTypeList = ['music', 'submusic'];
    } else if (listType === 'series') {
      showTypeList = ['series'];
    } else if (listType === 'music') {
      showTypeList = ['music'];
    } else if (isFavoriteList) {
      showTypeList = ['music', 'series', 'submusic'];
    } else if (Number.isFinite(listId) && listId > 0) {
      showTypeList = ['music', 'submusic'];
    } else if (Number.isFinite(collectionId) && collectionId > 0) {
      showTypeList = ['music', 'submusic'];
    }

    const baseQuery = knex('music_index as m')
      .whereIn('m.show_type', showTypeList)
      .modify(qb => {
        if (isHistoryList) {
          qb.join('music_history as h', function () {
            this.on('h.index_id', '=', 'm.id').andOn('h.uid', '=', knex.raw('?', [uid]));
          });
        } else if (isFavoriteList) {
          qb.join('music_favorite as fav', function () {
            this.on('fav.index_id', '=', 'm.id').andOn('fav.uid', '=', knex.raw('?', [uid]));
          });
        }
      })
      .modify(qb => {
        if (!isHistoryList && Number.isFinite(listId) && listId > 0) {
          qb.join('play_list2index as pl', function () {
            this.on('pl.index_id', '=', 'm.id').andOn('pl.list_id', '=', knex.raw('?', [listId]));
          });
        }
      })
      .modify(qb => {
        if (seriesIndexBasePath) {
          qb.andWhere('m.path', seriesIndexBasePath);
        }
      });

    if (finalPaths.length === 0) {
      baseQuery.whereRaw('1 = 0');
    } else {
      _applyMusicIndexPathPrefixFilter(baseQuery, finalPaths);
    }

    if (search) {
      const isSingleLetter = search.length === 1 && /[a-z]/i.test(search);
      const isHash = search === '#';
      if (isHash || isSingleLetter) {
        const fl = isHash ? '#' : search.toUpperCase();
        baseQuery.andWhere(builder => {
          builder.where('m.title_fl', fl).orWhere('m.artist_fl', fl);
        });
      } else {
        const escaped = _escapeLikeValue(search);
        baseQuery.andWhere(builder => {
          builder
            .whereRaw("m.title LIKE ? ESCAPE '\\'", [`%${escaped}%`])
            .orWhereRaw("m.filename LIKE ? ESCAPE '\\'", [`%${escaped}%`])
            .orWhereRaw("m.artist LIKE ? ESCAPE '\\'", [`%${escaped}%`])
            .orWhereRaw("m.album LIKE ? ESCAPE '\\'", [`%${escaped}%`]);
        });
      }
    }

    for (const a of artists) {
      baseQuery.whereExists(function () {
        this.select(1).from('music_index2key as k').whereRaw('k.index_id = m.id').andWhere('k.key_type', 'artist').andWhere('k.key', a);
      });
    }
    for (const a of albums) {
      baseQuery.whereExists(function () {
        this.select(1).from('music_index2key as k').whereRaw('k.index_id = m.id').andWhere('k.key_type', 'album').andWhere('k.key', a);
      });
    }
    for (const g of genres) {
      baseQuery.whereExists(function () {
        this.select(1).from('music_index2key as k').whereRaw('k.index_id = m.id').andWhere('k.key_type', 'genre').andWhere('k.key', g);
      });
    }

    const countRow = await baseQuery
      .clone()
      .clearSelect()
      .clearOrder()
      .countDistinct({ cnt: 'm.id' })
      .first()
      .catch(() => null);
    const total = Math.max(0, Number((countRow && (countRow.cnt ?? countRow['count(`m`.`id`)'] ?? countRow['count(*)'])) || 0) || 0);

    const query = baseQuery
      .clone()
      .select(
        'm.id',
        'm.path',
        'm.filename',
        'm.file_hash',
        'm.title',
        'm.artist',
        'm.album',
        'm.year',
        'm.genre',
        'm.duration',
        'm.size',
        'm.ext',
        'm.has_inner_cover',
        'm.show_type',
        'm.ctime',
        'm.mtime',
        'm.birthtime',
        'm.music_count',
        'm.bitrate',
        'm.sample_rate',
        'm.bit_depth'
      );

    query.select(
      knex.raw(
        `
        case
          when m.show_type = 'series' then (
            select path || ? || filename
            from music_index as s
            where s.show_type = 'submusic'
              and s.path = (m.path || ? || m.filename)
            order by s.id asc
            limit 1
          )
          else ''
        end as first_file_path
        `,
        [path.sep, path.sep]
      )
    );

    if (isHistoryList) {
      query.orderBy('h.last_listen_at', 'desc');
    } else if (sortBy === 'filename' || sortBy === 'file_name') {
      query.orderByRaw(`lower(m.filename) ${sortOrder}`);
    } else if (sortBy === 'title' || sortBy === 'name') {
      query.orderByRaw(`lower(case when m.title is not null and trim(m.title) != '' then m.title else m.filename end) ${sortOrder}`);
    } else if (sortBy === 'artist') {
      query.orderByRaw(`lower(case when m.artist is not null and trim(m.artist) != '' then m.artist else '' end) ${sortOrder}`);
    } else if (sortBy === 'album') {
      query.orderByRaw(`lower(case when m.album is not null and trim(m.album) != '' then m.album else '' end) ${sortOrder}`);
    } else if (sortBy === 'year') {
      query.orderByRaw(`lower(case when m.year is not null and trim(m.year) != '' then m.year else '' end) ${sortOrder}`);
    } else if (sortBy === 'favorite_time' && isFavoriteList) {
      query.orderBy('fav.create_time', sortOrder);
      query.orderBy('fav.id', 'desc');
    } else if (sortBy === 'duration') {
      query.orderBy('m.duration', sortOrder);
    } else if (sortBy === 'ctime') {
      query.orderBy('m.ctime', sortOrder);
    } else {
      query.orderBy('m.mtime', sortOrder);
    }
    query.orderBy('m.id', 'desc');

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
        const favRows = await knex('music_favorite')
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
    return await this.knexMusic('music_index')
      .where({ file_hash: fh })
      .first('id', 'path', 'filename', 'file_hash', 'has_inner_cover', 'show_type')
      .catch(() => null);
  }

  async getIndexByFilePath({ filePath }) {
    const fp = filePath === undefined || filePath === null ? '' : String(filePath).trim();
    if (!fp) return null;
    const resolved = path.resolve(fp);
    const dir = path.dirname(resolved);
    const name = path.basename(resolved);
    if (!dir || !name) return null;
    return await this.knexMusic('music_index')
      .where({ path: dir, filename: name })
      .first('id', 'path', 'filename', 'file_hash', 'has_inner_cover', 'show_type')
      .catch(() => null);
  }

  async canUserAccessIndex({ user, indexRow }) {
    if (!indexRow || !indexRow.path || !indexRow.filename) return false;
    const roots = await this.getValidPaths(user);
    const full = path.join(String(indexRow.path), String(indexRow.filename));
    return _isUnderAnyRoot({ filePath: full, roots });
  }

  async listKeyGroupsPaged(params, user) {
    const keyType = String(params.key_type ?? params.keyType ?? '')
      .trim()
      .toLowerCase();
    if (keyType !== 'album' && keyType !== 'artist') {
      const err = new Error('validation.VALIDATION_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const safePage = Math.max(1, Number(params.page || 1) || 1);
    const safeLimit = Math.min(200, Math.max(1, Number(params.page_size ?? params.pageSize ?? 30) || 30));
    const offset = (safePage - 1) * safeLimit;

    const search = params.search === undefined || params.search === null ? '' : String(params.search).trim();
    const sortBy = _normalizeKeySortBy(params.sort_by ?? params.sortBy);
    const sortOrder = _normalizeSortOrder(params.sort_order ?? params.sortOrder);

    const validPaths = await this.getValidPaths(user);
    let finalPaths = validPaths;

    const collectionId = Number(params && (params.collection_id ?? params.collectionId));
    if (Number.isFinite(collectionId) && collectionId > 0) {
      const collection = await this.knexMusic('music_collection').where({ id: collectionId }).first();
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

    const sourceList = Array.isArray(params.sourceList) ? params.sourceList : Array.isArray(params.source_list) ? params.source_list : null;
    if (sourceList && sourceList.length > 0) {
      finalPaths = intersectPaths(finalPaths, sourceList);
    }
    const validPathsWithStatus = (validPaths || []).map(p => ({
      path: p,
      valid: fs.existsSync(p),
    }));

    const knex = this.knexMusic;
    const baseQuery = knex('music_index2key as k')
      .join('music_index as m', 'm.id', 'k.index_id')
      .where('k.key_type', keyType)
      .whereIn('m.show_type', ['music', 'submusic'])
      .andWhereRaw("k.key is not null and trim(k.key) != ''");

    if (finalPaths.length === 0) {
      baseQuery.whereRaw('1 = 0');
    } else {
      _applyMusicIndexPathPrefixFilter(baseQuery, finalPaths);
    }

    if (search) {
      const isSingleLetter = search.length === 1 && /[a-z]/i.test(search);
      const isHash = search === '#';
      if (isHash || isSingleLetter) {
        const fl = isHash ? '#' : search.toUpperCase();
        baseQuery.andWhere('k.key_fl', fl);
      } else {
        const escaped = _escapeLikeValue(search);
        baseQuery.andWhereRaw("k.key LIKE ? ESCAPE '\\'", [`%${escaped}%`]);
      }
    }

    const countRow = await baseQuery
      .clone()
      .clearSelect()
      .clearOrder()
      .countDistinct({ cnt: 'k.key' })
      .first()
      .catch(() => null);
    const total = Math.max(0, Number((countRow && (countRow.cnt ?? countRow['count(`k`.`key`)'] ?? countRow['count(*)'])) || 0) || 0);

    const groups = await baseQuery
      .clone()
      .clearSelect()
      .select('k.key as name')
      .countDistinct({ cnt: 'k.index_id' })
      .groupBy('k.key')
      .modify(qb => {
        if (sortBy === 'count') {
          qb.orderBy('cnt', sortOrder);
          qb.orderByRaw(`lower(k.key) asc`);
          return;
        }
        qb.orderByRaw(`lower(k.key) ${sortOrder}`);
      })
      .limit(safeLimit)
      .offset(offset)
      .catch(() => []);

    const items = [];
    for (const row of groups || []) {
      const name = row && row.name !== undefined && row.name !== null ? String(row.name).trim() : '';
      if (!name) continue;
      const cnt = Math.max(0, Number(row && (row.cnt ?? row['count(`k`.`index_id`)'] ?? row['count(*)']) ? (row.cnt ?? row['count(`k`.`index_id`)'] ?? row['count(*)']) : 0) || 0);

      const coverRow = await baseQuery
        .clone()
        .clearSelect()
        .clearOrder()
        .where('k.key', name)
        .andWhere('m.has_inner_cover', 1)
        .select('m.path', 'm.filename', 'm.has_inner_cover', 'm.id')
        .orderBy('m.has_inner_cover', 'desc')
        .orderBy('m.id', 'desc')
        .first()
        .catch(() => null);

      const coverPath = coverRow && coverRow.path ? String(coverRow.path) : '';
      const coverName = coverRow && coverRow.filename ? String(coverRow.filename) : '';
      const firstFilePath = coverPath && coverName ? path.join(coverPath, coverName) : '';

      items.push({
        key_type: keyType,
        name,
        first_file_path: firstFilePath,
        index_count: cnt,
      });
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

  async deleteIndexesByFullPaths(fullPaths) {
    const input = Array.isArray(fullPaths) ? fullPaths : [];
    const normalized = input
      .map(v => String(v || '').trim())
      .filter(Boolean)
      .map(p => path.resolve(p));
    const targets = Array.from(new Set(normalized));
    if (targets.length === 0) return 0;

    const sep = path.sep;
    return await this.knexMusic.transaction(async trx => {
      let affectedTotal = 0;

      for (const fullPath of targets) {
        const resolved = fullPath ? path.resolve(String(fullPath)) : '';
        if (!resolved) continue;

        const ext = path.extname(resolved);
        if (ext) {
          const dir = path.dirname(resolved);
          const name = path.basename(resolved);
          if (!dir || !name) continue;
          const affected = await trx('music_index')
            .where({ path: dir, filename: name })
            .delete()
            .catch(() => 0);
          affectedTotal += Number(affected || 0) || 0;
          continue;
        }

        const targetDir = resolved;
        const prefix = targetDir.endsWith(sep) ? targetDir : `${targetDir}${sep}`;
        const affectedSubtree = await trx('music_index')
          .where(qb => {
            qb.where('path', targetDir).orWhere('path', 'like', `${prefix}%`);
          })
          .delete()
          .catch(() => 0);
        affectedTotal += Number(affectedSubtree || 0) || 0;

        const parentDir = path.dirname(targetDir);
        const folderName = path.basename(targetDir);
        if (parentDir && folderName) {
          const affectedSeries = await trx('music_index')
            .where({ path: parentDir, filename: folderName })
            .delete()
            .catch(() => 0);
          affectedTotal += Number(affectedSeries || 0) || 0;
        }
      }

      return affectedTotal;
    });
  }
}

module.exports = MusicListService;
