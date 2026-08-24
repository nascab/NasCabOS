const path = require('path');
const fs = require('fs');
const VideoSourceService = require('../source/videoSourceService');
const userUtil = require('../../../../utils/userUtil');
const { intersectPaths, parsePathListText } = require('../../photo/timeline/photoPathQueryUtil');
const smartAlbumFilterUtil = require('../smartAlbum/videoSmartAlbumFilterUtil');

function _applyVideoIndexPathPrefixFilter(query, paths) {
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
        this.where('v.path', p).orWhere('v.path', 'like', `${prefix}%`);
      });
    }
    for (const pair of folderExactPairs) {
      builder.orWhere(function () {
        this.where('v.is_file', 0).andWhere('v.path', pair.parent).andWhere('v.filename', pair.name);
      });
    }
  });
}

function _resolveArtworkAbsolute({ baseDir, maybeRelative }) {
  const p = maybeRelative === undefined || maybeRelative === null ? '' : String(maybeRelative).trim();
  if (!p) return '';
  if (path.isAbsolute(p)) return p;
  const base = baseDir === undefined || baseDir === null ? '' : String(baseDir).trim();
  if (!base) return '';
  return path.resolve(base, p);
}

function _normalizeListRow(row) {
  if (!row || typeof row !== 'object') return row;
  const baseDir = row.path === undefined || row.path === null ? '' : String(row.path).trim();
  const poster = _resolveArtworkAbsolute({ baseDir, maybeRelative: row.poster_path });
  const fanart = _resolveArtworkAbsolute({ baseDir, maybeRelative: row.fanart_path });
  const logo = _resolveArtworkAbsolute({ baseDir, maybeRelative: row.logo_path });
  const fullPath = baseDir && row.filename ? path.join(baseDir, String(row.filename)) : '';
  const playRelPath = row.play_rel_path === undefined || row.play_rel_path === null ? '' : String(row.play_rel_path).trim();
  const playFilePath = row && (row.media_type === 'bdmv' || row.media_type === 'video_ts') && fullPath && playRelPath ? path.resolve(fullPath, playRelPath) : '';
  return {
    ...row,
    poster_path: poster,
    fanart_path: fanart,
    logo_path: logo,
    full_path: fullPath,
    play_file_path: playFilePath,
    first_file_path: row && (row.media_type === 'bdmv' || row.media_type === 'video_ts') && playFilePath ? playFilePath : row.first_file_path,
  };
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

async function _fillFirstFilePathForTvRows({ knex, rows }) {
  const list = Array.isArray(rows) ? rows : [];
  const tvRows = list.filter(r => r && r.media_type === 'tv');
  if (tvRows.length === 0) return;

  await Promise.all(
    tvRows.map(async r => {
      const poster = r.poster_path ? String(r.poster_path).trim() : '';
      const fanart = r.fanart_path ? String(r.fanart_path).trim() : '';
      if (poster || fanart) return;
      const baseDir = r.path ? String(r.path).trim() : '';
      const name = r.filename ? String(r.filename).trim() : '';
      if (!baseDir || !name) return;
      const showFolder = path.join(baseDir, name);

      const first = await _getFirstEpisodeRowUnderFolder({
        knex,
        rootFolder: showFolder,
      });
      const epPath = first && first.path ? String(first.path).trim() : '';
      const epName = first && first.filename ? String(first.filename).trim() : '';
      if (!epPath || !epName) return;
      r.first_file_path = path.join(epPath, epName);
    })
  );
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

function _escapeLikeValue(input) {
  return String(input || '')
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
}

function _applyCommaSeparatedFieldExactContains(query, columnName, value) {
  const v = String(value || '').trim();
  if (!v) return;
  const escaped = _escapeLikeValue(v);
  const pattern = `%,${escaped},%`;
  query.andWhereRaw(`(',' || replace(replace(replace(${columnName}, '，', ','), ', ', ','), ' ,', ',') || ',') LIKE ? ESCAPE '\\'`, [pattern]);
}

function _normalizeIntList(input) {
  if (Array.isArray(input)) {
    const nums = input
      .map(v => Number(v || 0) || 0)
      .map(v => Math.trunc(v))
      .filter(v => v > 0);
    return [...new Set(nums)];
  }
  const s = input === undefined || input === null ? '' : String(input).trim();
  if (!s) return [];
  if (s.startsWith('[')) {
    try {
      const arr = JSON.parse(s);
      if (!Array.isArray(arr)) return [];
      const nums = arr
        .map(v => Number(v || 0) || 0)
        .map(v => Math.trunc(v))
        .filter(v => v > 0);
      return [...new Set(nums)];
    } catch (_) {
      return [];
    }
  }
  const nums = s
    .split(',')
    .map(v => Number(String(v || '').trim() || 0) || 0)
    .map(v => Math.trunc(v))
    .filter(v => v > 0);
  return [...new Set(nums)];
}

function _normalizeMediaType(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  if (v === 'movie' || v === 'tv') return v;
  return '';
}

function _normalizeMediaTypeList(input) {
  if (Array.isArray(input)) {
    const list = input.map(v => _normalizeMediaType(v)).filter(Boolean);
    return [...new Set(list)];
  }
  const s = input === undefined || input === null ? '' : String(input).trim();
  if (!s) return [];
  if (s.startsWith('[')) {
    try {
      const arr = JSON.parse(s);
      if (!Array.isArray(arr)) return [];
      const list = arr.map(v => _normalizeMediaType(v)).filter(Boolean);
      return [...new Set(list)];
    } catch (_) {
      return [];
    }
  }
  const single = _normalizeMediaType(s);
  return single ? [single] : [];
}

function _normalizeSortBy(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  if (v === 'year' || v === 'score' || v === 'create_time' || v === 'name' || v === 'favorite_time' || v === 'view_time') return v;
  return 'create_time';
}

function _normalizeSortOrder(input) {
  const v = String(input || '')
    .trim()
    .toLowerCase();
  return v === 'asc' ? 'asc' : 'desc';
}

class VideoListService {
  constructor(knexVideo) {
    this.knexVideo = knexVideo;
  }

  async _getFilterOptions(baseQuery) {
    const idsSubQuery = baseQuery.clone().clearSelect().clearOrder().select('v.id');

    const yearRows = await baseQuery
      .clone()
      .clearSelect()
      .clearOrder()
      .distinct({ year: 'v.nfo_year' })
      .whereNotNull('v.nfo_year')
      .andWhere('v.nfo_year', '>', 0)
      .orderBy('v.nfo_year', 'desc')
      .limit(200)
      .catch(() => []);
    const years = (yearRows || [])
      .map(r => Number(r && (r.year ?? r.nfo_year)) || 0)
      .map(v => Math.trunc(v))
      .filter(v => v > 0);

    const regionRows = await this.knexVideo('video_index2key as k')
      .distinct('k.key')
      .whereIn('k.index_id', idsSubQuery)
      .andWhere('k.key_type', 'region')
      .orderBy('k.key', 'asc')
      .limit(500)
      .catch(() => []);
    const regions = (regionRows || []).map(r => (r && r.key ? String(r.key).trim() : '')).filter(Boolean);

    const genreRows = await this.knexVideo('video_index2key as k')
      .distinct('k.key')
      .whereIn('k.index_id', idsSubQuery)
      .andWhere('k.key_type', 'genres')
      .orderBy('k.key', 'asc')
      .limit(500)
      .catch(() => []);
    const genres = (genreRows || []).map(r => (r && r.key ? String(r.key).trim() : '')).filter(Boolean);

    return {
      years,
      regions,
      genres,
    };
  }

  async getValidPaths(user) {
    const sourceService = new VideoSourceService(this.knexVideo);
    return await sourceService.getValidPaths(user);
  }

  async getVisibleIndexCounts(params, user) {
    const validPaths = await this.getValidPaths(user);
    let finalPaths = validPaths;
    const knex = this.knexVideo;
    const uid = user && user.id ? Number(user.id) : 0;

    const albumId = Number(params && (params.album_id ?? params.albumId));
    if (Number.isFinite(albumId) && albumId > 0) {
      const album = await knex('video_album').where({ id: albumId }).first();
      if (!album) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      if (!userUtil.isAdmin(user) && uid && Number(album.uid) !== Number(uid) && Number(album.is_public) !== 1) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
    }

    const sourceList = Array.isArray(params && params.sourceList) ? params.sourceList : Array.isArray(params && params.source_list) ? params.source_list : null;
    if (sourceList && sourceList.length > 0) {
      finalPaths = intersectPaths(finalPaths, sourceList);
    }

    if (!finalPaths || finalPaths.length === 0) {
      return { movie: 0, tv: 0, total: 0 };
    }

    const rows = await knex('video_index as v')
      .whereIn('v.media_type', ['movie', 'tv', 'bdmv', 'video_ts'])
      .modify(qb => {
        if (!Number.isFinite(albumId) || albumId <= 0) return;
        qb.join('video_album_index as ai', function () {
          this.on('ai.index_id', '=', 'v.id').andOn('ai.album_id', '=', knex.raw('?', [albumId]));
        });
      })
      .modify(qb => _applyVideoIndexPathPrefixFilter(qb, finalPaths))
      .groupBy('v.media_type')
      .select('v.media_type')
      .count({ total: '*' })
      .catch(() => []);

    let movie = 0;
    let tv = 0;
    for (const r of rows || []) {
      const mt = r && r.media_type ? String(r.media_type).trim() : '';
      const cnt = Number(r && r.total);
      const v = Number.isFinite(cnt) ? cnt : Number(String(r && r.total ? r.total : 0)) || 0;
      if (mt === 'movie' || mt === 'bdmv' || mt === 'video_ts') movie += v;
      if (mt === 'tv') tv = v;
    }
    return { movie, tv, total: movie + tv };
  }

  async listPaged(params, user) {
    const uid = user && user.id ? Number(user.id) : 0;
    const safePage = Math.max(1, Number(params.page || 1) || 1);
    const safeLimit = Math.min(200, Math.max(1, Number(params.page_size ?? params.pageSize ?? 30) || 30));
    const offset = (safePage - 1) * safeLimit;

    const search = params.search === undefined || params.search === null ? '' : String(params.search).trim();
    const mediaTypeList = _normalizeMediaTypeList(params.media_type ?? params.mediaType);
    const rawSortBy = params.sort_by ?? params.sortBy;
    const rawSortOrder = params.sort_order ?? params.sortOrder;
    let sortBy = _normalizeSortBy(rawSortBy);
    let sortOrder = _normalizeSortOrder(rawSortOrder);
    const genres = _normalizeKeyList(params.genres);
    const regions = _normalizeKeyList(params.regions ?? params.region);
    const actors = _normalizeKeyList(params.actors ?? params.actor ?? params.nfo_actor ?? params.nfoActor);
    const directors = _normalizeKeyList(params.directors ?? params.director ?? params.nfo_director ?? params.nfoDirector);
    const years = _normalizeIntList(params.years ?? params.year);
    const listType = String(params.listType ?? params.list_type ?? '')
      .trim()
      .toLowerCase();
    const isFavoriteList = listType === 'favorite';

    const hasSortByParam = rawSortBy !== undefined && rawSortBy !== null && String(rawSortBy).trim() !== '';
    const hasSortOrderParam = rawSortOrder !== undefined && rawSortOrder !== null && String(rawSortOrder).trim() !== '';
    if (isFavoriteList) {
      if (!hasSortByParam) sortBy = 'favorite_time';
      if (!hasSortOrderParam) sortOrder = 'desc';
    }

    const validPaths = await this.getValidPaths(user);
    let finalPaths = validPaths;

    const albumId = Number(params && (params.album_id ?? params.albumId));
    if (Number.isFinite(albumId) && albumId > 0) {
      const album = await this.knexVideo('video_album').where({ id: albumId }).first();
      if (!album) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      if (!userUtil.isAdmin(user) && uid && Number(album.uid) !== Number(uid) && Number(album.is_public) !== 1) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
    }

    const collectionId = Number(params && (params.collection_id ?? params.collectionId));
    if (Number.isFinite(collectionId) && collectionId > 0) {
      const collection = await this.knexVideo('video_collection').where({ id: collectionId }).first();
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

    const knex = this.knexVideo;
    const includeSeason = isFavoriteList || (Number.isFinite(albumId) && albumId > 0);
    const baseQuery = knex('video_index as v')
      .whereIn('v.media_type', includeSeason ? ['movie', 'tv', 'season', 'bdmv', 'video_ts'] : ['movie', 'tv', 'bdmv', 'video_ts'])
      .modify(qb => {
        if (isFavoriteList) {
          qb.join('video_favorite as fav', function () {
            this.on('fav.index_id', '=', 'v.id').andOn('fav.uid', '=', knex.raw('?', [uid]));
          });
        }
      })
      .modify(qb => {
        if (!Number.isFinite(albumId) || albumId <= 0) return;
        qb.join('video_album_index as ai', function () {
          this.on('ai.index_id', '=', 'v.id').andOn('ai.album_id', '=', knex.raw('?', [albumId]));
        });
      })
      .modify(qb => {
        if (mediaTypeList.length > 0)
          qb.andWhere(function () {
            if (includeSeason && mediaTypeList.includes('tv') && !mediaTypeList.includes('season')) {
              this.whereIn('v.media_type', ['tv', 'season']);
            } else if (mediaTypeList.includes('movie') && !mediaTypeList.includes('bdmv') && !mediaTypeList.includes('video_ts')) {
              this.whereIn('v.media_type', ['movie', 'bdmv', 'video_ts']);
            } else {
              this.whereIn('v.media_type', mediaTypeList);
            }
          });
      });

    if (finalPaths.length === 0) {
      baseQuery.whereRaw('1 = 0');
    } else {
      _applyVideoIndexPathPrefixFilter(baseQuery, finalPaths);
    }

    const effectiveSearch = typeof search === 'string' ? search.trim() : '';
    if (effectiveSearch) {
      const isSingleLetterFilter = effectiveSearch.length === 1 && (effectiveSearch === '#' || /^[a-zA-Z]$/.test(effectiveSearch));
      if (isSingleLetterFilter) {
        const fl = effectiveSearch.toUpperCase();
        baseQuery.andWhere(builder => {
          builder.where({ 'v.nfo_name_fl': fl }).orWhere({ 'v.filename_fl': fl });
        });
      } else {
        baseQuery.andWhere(builder => {
          builder.where('v.nfo_name', 'like', `%${effectiveSearch}%`).orWhere('v.filename', 'like', `%${effectiveSearch}%`);
        });
      }
    }

    for (const a of actors) {
      _applyCommaSeparatedFieldExactContains(baseQuery, 'v.nfo_actor', a);
    }

    for (const d of directors) {
      _applyCommaSeparatedFieldExactContains(baseQuery, 'v.nfo_director', d);
    }

    for (const g of genres) {
      baseQuery.whereExists(function () {
        this.select(1).from('video_index2key as k').whereRaw('k.index_id = v.id').andWhere('k.key_type', 'genres').andWhere('k.key', g);
      });
    }

    for (const r of regions) {
      baseQuery.whereExists(function () {
        this.select(1).from('video_index2key as k').whereRaw('k.index_id = v.id').andWhere('k.key_type', 'region').andWhere('k.key', r);
      });
    }

    if (years.length > 0) {
      baseQuery.andWhere(builder => builder.whereIn('v.nfo_year', years));
    }

    const smartAlbumId = Number(params && (params.smart_album_id ?? params.smartAlbumId));
    if (Number.isFinite(smartAlbumId) && smartAlbumId > 0) {
      const smartAlbum = await this.knexVideo('video_smart_album').where({ id: smartAlbumId }).first();
      if (!smartAlbum) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      if (user && !userUtil.isAdmin(user) && uid && Number(smartAlbum.uid) !== Number(uid)) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }

      const filterContent = smartAlbumFilterUtil.parseFilterContentText(smartAlbum.filter_content);
      smartAlbumFilterUtil.applySmartAlbumFilter(baseQuery, smartAlbum.type, filterContent, 'v');
    }

    const countRow = await baseQuery
      .clone()
      .clearSelect()
      .clearOrder()
      .countDistinct({ cnt: 'v.id' })
      .first()
      .catch(() => null);
    const total = Math.max(0, Number((countRow && (countRow.cnt ?? countRow['count(`v`.`id`)'] ?? countRow['count(*)'])) || 0) || 0);

    const filters = await this._getFilterOptions(baseQuery);

    const query = baseQuery
      .clone()
      .select(
        'v.id',
        'v.media_type',
        'v.path',
        'v.filename',
        'v.nfo_name',
        'v.nfo_year',
        'v.nfo_score',
        'v.nfo_regions',
        'v.nfo_genres',
        'v.poster_path',
        'v.fanart_path',
        'v.logo_path',
        'v.play_rel_path',
        'v.view_time',
        'v.create_time'
      );

    if (sortBy === 'favorite_time' && isFavoriteList) {
      query.orderBy('fav.create_time', sortOrder);
      query.orderBy('fav.id', 'desc');
    } else if (sortBy === 'view_time') {
      query.orderBy('v.view_time', sortOrder);
    } else if (sortBy === 'year') {
      query.orderBy('v.nfo_year', sortOrder);
    } else if (sortBy === 'score') {
      query.orderBy('v.nfo_score', sortOrder);
    } else if (sortBy === 'name') {
      query.orderByRaw(`lower(case when v.nfo_name is not null and trim(v.nfo_name) != '' then v.nfo_name else v.filename end) ${sortOrder}`);
    } else {
      query.orderBy('v.create_time', sortOrder);
    }
    query.orderBy('v.id', 'desc');

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
        const favRows = await knex('video_favorite')
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
    await _fillFirstFilePathForTvRows({ knex: this.knexVideo, rows: items });
    const totalPages = Math.ceil(total / safeLimit);
    return {
      items,
      filters,
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

  async listHistory(user) {
    const uid = user && user.id ? Number(user.id) : 0;
    if (!uid) return { items: [] };

    const validPaths = await this.getValidPaths(user);
    if (!validPaths || validPaths.length === 0) return { items: [] };

    const prefRows = await this.knexVideo('video_play_preference as p')
      .join('video_index as v', 'v.file_hash', 'p.file_hash')
      .where('p.uid', uid)
      .modify(qb => _applyVideoIndexPathPrefixFilter(qb, validPaths))
      .orderBy('p.last_watched_at', 'desc')
      .orderBy('p.id', 'desc')
      .limit(200)
      .select(
        'p.last_watched_at',
        'p.playback_position',
        'p.file_hash',
        'v.id',
        'v.is_file',
        'v.media_type',
        'v.path',
        'v.filename',
        'v.nfo_name',
        'v.nfo_year',
        'v.nfo_score',
        'v.nfo_regions',
        'v.nfo_genres',
        'v.poster_path',
        'v.fanart_path',
        'v.logo_path',
        'v.play_rel_path',
        'v.view_time',
        'v.create_time',
        'v.duration'
      )
      .catch(() => []);

    const episodeFolders = new Set();
    for (const r of prefRows || []) {
      const mt = r && r.media_type ? String(r.media_type).trim() : '';
      if (mt === 'episod') {
        const epFolder = r.path ? String(r.path).trim() : '';
        if (epFolder) episodeFolders.add(epFolder);
      }
    }

    const seasonPairs = [];
    const tvPairs = [];
    for (const f of episodeFolders) {
      const parent = path.dirname(f);
      const name = path.basename(f);
      if (!parent || !name) continue;
      seasonPairs.push({ path: parent, filename: name });

      tvPairs.push({ path: parent, filename: name });
      const showFolder = parent;
      const showParent = showFolder ? path.dirname(showFolder) : '';
      const showName = showFolder ? path.basename(showFolder) : '';
      if (showParent && showName) {
        tvPairs.push({ path: showParent, filename: showName });
      }
    }

    const seasonMap = new Map();
    const tvMap = new Map();

    if (seasonPairs.length > 0) {
      const rows = await this.knexVideo('video_index as v')
        .where({ 'v.is_file': 0, 'v.media_type': 'season' })
        .modify(qb => {
          qb.andWhere(builder => {
            for (const p of seasonPairs) {
              builder.orWhere(function () {
                this.where('v.path', p.path).andWhere('v.filename', p.filename);
              });
            }
          });
        })
        .modify(qb => _applyVideoIndexPathPrefixFilter(qb, validPaths))
        .select(
          'v.id',
          'v.media_type',
          'v.path',
          'v.filename',
          'v.nfo_name',
          'v.nfo_year',
          'v.nfo_score',
          'v.nfo_regions',
          'v.nfo_genres',
          'v.poster_path',
          'v.fanart_path',
          'v.logo_path',
          'v.view_time',
          'v.create_time',
          'v.duration'
        )
        .catch(() => []);

      for (const r of rows || []) {
        const k = `${r.path}||${r.filename}`;
        seasonMap.set(k, r);
      }
    }

    if (tvPairs.length > 0) {
      const rows = await this.knexVideo('video_index as v')
        .where({ 'v.is_file': 0, 'v.media_type': 'tv' })
        .modify(qb => {
          qb.andWhere(builder => {
            for (const p of tvPairs) {
              builder.orWhere(function () {
                this.where('v.path', p.path).andWhere('v.filename', p.filename);
              });
            }
          });
        })
        .modify(qb => _applyVideoIndexPathPrefixFilter(qb, validPaths))
        .select(
          'v.id',
          'v.media_type',
          'v.path',
          'v.filename',
          'v.nfo_name',
          'v.nfo_year',
          'v.nfo_score',
          'v.nfo_regions',
          'v.nfo_genres',
          'v.poster_path',
          'v.fanart_path',
          'v.logo_path',
          'v.view_time',
          'v.create_time',
          'v.duration'
        )
        .catch(() => []);

      for (const r of rows || []) {
        const k = `${r.path}||${r.filename}`;
        tvMap.set(k, r);
      }
    }

    const out = [];
    const seen = new Set();

    for (const r of prefRows || []) {
      const mt = r && r.media_type ? String(r.media_type).trim() : '';
      let item = r;
      if (mt === 'episod') {
        const folder = r.path ? String(r.path).trim() : '';
        const parent = folder ? path.dirname(folder) : '';
        const name = folder ? path.basename(folder) : '';
        const k1 = parent && name ? `${parent}||${name}` : '';

        const showFolder = parent;
        const showParent = showFolder ? path.dirname(showFolder) : '';
        const showName = showFolder ? path.basename(showFolder) : '';
        const k2 = showParent && showName ? `${showParent}||${showName}` : '';

        item = (k1 && seasonMap.has(k1) ? seasonMap.get(k1) : null) || (k1 && tvMap.has(k1) ? tvMap.get(k1) : null) || (k2 && tvMap.has(k2) ? tvMap.get(k2) : null);
      } else if (mt !== 'movie' && mt !== 'tv' && mt !== 'season' && mt !== 'bdmv' && mt !== 'video_ts') {
        item = null;
      }

      if (!item || !item.id) continue;
      const id = Number(item.id) || 0;
      if (!id || seen.has(id)) continue;
      seen.add(id);

      const duration = item.duration === undefined || item.duration === null ? 0 : Number(item.duration);
      const playback_position = r.playback_position === undefined || r.playback_position === null ? 0 : Number(r.playback_position);
      let progress = 0;
      if (duration > 0 && playback_position > 0) {
        progress = Number((Math.min(playback_position, duration) / duration).toFixed(2));
      }

      out.push(
        _normalizeListRow({
          ...item,
          last_watched_at: r.last_watched_at,
          playback_position: r.playback_position,
          progress: progress >= 0 && progress <= 1 ? progress : 0,
        })
      );
    }

    await _fillFirstFilePathForTvRows({ knex: this.knexVideo, rows: out });
    return { items: out };
  }

  async clearHistory(user) {
    const uid = user && user.id ? Number(user.id) : 0;
    if (!uid) return { deleted: 0 };
    const deleted = await this.knexVideo('video_play_preference')
      .where({ uid })
      .del()
      .catch(() => 0);
    return { deleted: Number(deleted) || 0 };
  }
}

module.exports = VideoListService;
