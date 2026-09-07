import { JsonCodec } from '../../common/JsonTypes';

/**
 * 影音管理模块数据模型（对齐 Flutter video 模块各 model/bean 文件）。
 */

// ===== 解析辅助（对齐 Flutter fromJson 的空值兜底策略） =====

export function asStr(v: Object | undefined | null, fallback: string = ''): string {
  if (v === undefined || v === null) {
    return fallback;
  }
  const t = `${v}`;
  return t;
}

export function asNum(v: Object | undefined | null, fallback: number = 0): number {
  if (v === undefined || v === null) {
    return fallback;
  }
  if (typeof v === 'number') {
    return v;
  }
  const parsed = Number(`${v}`);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function asBool(v: Object | undefined | null, fallback: boolean = false): boolean {
  if (v === undefined || v === null) {
    return fallback;
  }
  if (typeof v === 'boolean') {
    return v;
  }
  if (typeof v === 'number') {
    return v === 1;
  }
  return fallback;
}

export function asArray(v: Object | undefined | null): Object[] {
  if (v === undefined || v === null || !Array.isArray(v)) {
    return [];
  }
  return v as Object[];
}

export function asRecord(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null || typeof v !== 'object' || Array.isArray(v)) {
    return {};
  }
  return v as Record<string, Object>;
}

function asStringArray(v: Object | undefined | null): string[] {
  const out: string[] = [];
  for (const e of asArray(v)) {
    const s = `${e}`.trim();
    if (s.length > 0) {
      out.push(s);
    }
  }
  return out;
}

function asNumberArray(v: Object | undefined | null): number[] {
  const out: number[] = [];
  for (const e of asArray(v)) {
    const n = asNum(e, 0);
    if (n > 0) {
      out.push(n);
    }
  }
  return out;
}

// ===== 视频条目（对齐 base/beans/video_item_bean.dart VideoHomeItemBean） =====

export class VideoHomeItemBean {
  id: number = 0;
  mediaType: string = '';
  path: string = '';
  filename: string = '';
  firstFilePath: string = '';
  nfoName: string = '';
  nfoYear: number = 0;
  nfoScore: number = 0;
  nfoRegions: string = '';
  nfoGenres: string = '';
  posterPath: string = '';
  fanartPath: string = '';
  logoPath: string = '';
  progress: number = 0;
  isFavorite: boolean = false;
  viewTime: string = '';
  createTime: string = '';
  fullPath: string = '';
  playFilePath: string = '';
}

export function parseVideoHomeItemBean(e: Object): VideoHomeItemBean {
  const map = e as Record<string, Object>;
  const item = new VideoHomeItemBean();
  item.id = asNum(map['id']);
  item.mediaType = asStr(map['media_type']);
  item.path = asStr(map['path']);
  item.filename = asStr(map['filename']);
  item.firstFilePath = asStr(map['first_file_path'] ?? map['firstFilePath']);
  item.fullPath = asStr(map['full_path'] ?? map['fullPath']);
  item.playFilePath = asStr(map['play_file_path'] ?? map['playFilePath']);
  item.nfoName = asStr(map['nfo_name']);
  item.nfoYear = asNum(map['nfo_year']);
  item.nfoScore = asNum(map['nfo_score']);
  item.nfoRegions = asStr(map['nfo_regions']);
  item.nfoGenres = asStr(map['nfo_genres']);
  item.posterPath = asStr(map['poster_path']);
  item.fanartPath = asStr(map['fanart_path']);
  item.logoPath = asStr(map['logo_path']);
  item.progress = asNum(map['progress']);
  // 对齐 Flutter：is_favorite 兼容 bool/1/'1'
  const rawFav = map['is_favorite'];
  item.isFavorite = rawFav === true || rawFav === 1 || rawFav === '1';
  item.viewTime = asStr(map['view_time']);
  item.createTime = asStr(map['create_time']);
  return item;
}

function parseVideoItemList(v: Object | undefined | null): VideoHomeItemBean[] {
  const out: VideoHomeItemBean[] = [];
  for (const e of asArray(v)) {
    const item = parseVideoHomeItemBean(e);
    if (item.id > 0) {
      out.push(item);
    }
  }
  return out;
}

// ===== 首页聚合数据（对齐 home/service/video_home_api_service.dart VideoHomeData） =====

export class VideoHomeData {
  sourceList: Record<string, Object>[] = [];
  recommend: VideoHomeItemBean[] = [];
  recentPlay: VideoHomeItemBean[] = [];
  recentAddMovie: VideoHomeItemBean[] = [];
  recentAddTv: VideoHomeItemBean[] = [];
}

export function parseVideoHomeData(e: Object): VideoHomeData {
  const map = asRecord(e);
  const data = new VideoHomeData();
  const sources: Record<string, Object>[] = [];
  for (const s of asArray(map['sourceList'] ?? map['source_list'])) {
    sources.push(asRecord(s));
  }
  data.sourceList = sources;
  data.recommend = parseVideoItemList(map['recommend']);
  data.recentPlay = parseVideoItemList(map['recentPlay'] ?? map['recent_play']);
  data.recentAddMovie = parseVideoItemList(map['recentAddMovie'] ?? map['recent_add_movie']);
  data.recentAddTv = parseVideoItemList(map['recentAddTv'] ?? map['recent_add_tv']);
  return data;
}

// ===== 分页结构（album/collection/smart_album 通用） =====

function parsePagination(e: Object | undefined | null): VideoPageInfo {
  const map = asRecord(e);
  const page = new VideoPageInfo();
  page.total = asNum(map['total']);
  page.page = asNum(map['page'], 1);
  page.pageSize = asNum(map['pageSize'], 20);
  return page;
}

export class VideoPageInfo {
  total: number = 0;
  page: number = 1;
  pageSize: number = 20;
}

// ===== 相册（对齐 album/models/video_album_model.dart） =====

export class VideoAlbumPreviewItem {
  fullpath: string = '';
  firstFilePath: string = '';
}

export class VideoAlbumItem {
  id: number = 0;
  ownerId: number = 0;
  name: string = '';
  isPublic: boolean = false;
  isOwner: boolean = false;
  previews: VideoAlbumPreviewItem[] = [];
}

export class VideoAlbumListResult {
  items: VideoAlbumItem[] = [];
  page: VideoPageInfo = new VideoPageInfo();
}

export class VideoAlbumDetail {
  id: number = 0;
  ownerId: number = 0;
  name: string = '';
  isPublic: boolean = false;
}

export class VideoAlbumOverviewResult {
  albums: VideoAlbumItem[] = [];
  albumTotal: number = 0;
  collections: VideoCollectionItem[] = [];
  collectionTotal: number = 0;
  smartAlbums: VideoSmartAlbumItem[] = [];
  smartAlbumTotal: number = 0;
}

function parseAlbumPreview(e: Object): VideoAlbumPreviewItem {
  const map = asRecord(e);
  const item = new VideoAlbumPreviewItem();
  item.fullpath = asStr(map['fullpath']);
  item.firstFilePath = asStr(map['first_file_path']);
  return item;
}

export function parseVideoAlbumItem(e: Object): VideoAlbumItem {
  const map = asRecord(e);
  const item = new VideoAlbumItem();
  item.id = asNum(map['id']);
  item.ownerId = asNum(map['owner_id']);
  item.name = asStr(map['name']);
  item.isPublic = asNum(map['is_public']) === 1 || map['is_public'] === true;
  item.isOwner = map['is_owner'] === true;
  const previews: VideoAlbumPreviewItem[] = [];
  for (const p of asArray(map['previews'])) {
    const pv = parseAlbumPreview(p);
    if (pv.fullpath.length > 0 || pv.firstFilePath.length > 0) {
      previews.push(pv);
    }
  }
  item.previews = previews;
  return item;
}

export function parseVideoAlbumListResult(e: Object): VideoAlbumListResult {
  const map = asRecord(e);
  const result = new VideoAlbumListResult();
  for (const item of asArray(map['items'])) {
    const album = parseVideoAlbumItem(item);
    if (album.id > 0) {
      result.items.push(album);
    }
  }
  result.page = parsePagination(map['pagination']);
  return result;
}

export function parseVideoAlbumDetail(e: Object): VideoAlbumDetail {
  const map = asRecord(e);
  const detail = new VideoAlbumDetail();
  detail.id = asNum(map['id']);
  detail.ownerId = asNum(map['owner_id']);
  detail.name = asStr(map['name']);
  detail.isPublic = asNum(map['is_public']) === 1 || map['is_public'] === true;
  return detail;
}

export function parseVideoAlbumOverviewResult(e: Object): VideoAlbumOverviewResult {
  const map = asRecord(e);
  const result = new VideoAlbumOverviewResult();
  const albumsBlock = asRecord(map['albums']);
  for (const a of asArray(albumsBlock['items'])) {
    const album = parseVideoAlbumItem(a);
    if (album.id > 0) {
      result.albums.push(album);
    }
  }
  result.albumTotal = asNum(albumsBlock['total']);
  const collectionsBlock = asRecord(map['collections']);
  for (const c of asArray(collectionsBlock['items'])) {
    const col = parseVideoCollectionItem(c);
    if (col.id > 0) {
      result.collections.push(col);
    }
  }
  result.collectionTotal = asNum(collectionsBlock['total']);
  const smartBlock = asRecord(map['smart_albums']);
  for (const s of asArray(smartBlock['items'])) {
    const sa = parseVideoSmartAlbumItem(s);
    if (sa.id > 0) {
      result.smartAlbums.push(sa);
    }
  }
  result.smartAlbumTotal = asNum(smartBlock['total']);
  return result;
}

// ===== 合集（对齐 collection/models/video_collection_model.dart） =====

export class VideoCollectionPreviewItem {
  fullpath: string = '';
  firstFilePath: string = '';
}

export class VideoCollectionItem {
  id: number = 0;
  ownerId: number = 0;
  name: string = '';
  pathList: string[] = [];
  createTime: string = '';
  previews: VideoCollectionPreviewItem[] = [];
}

export class VideoCollectionListResult {
  items: VideoCollectionItem[] = [];
  page: VideoPageInfo = new VideoPageInfo();
}

function parseCollectionPreview(e: Object): VideoCollectionPreviewItem {
  const map = asRecord(e);
  const item = new VideoCollectionPreviewItem();
  item.fullpath = asStr(map['fullpath']);
  item.firstFilePath = asStr(map['first_file_path']);
  return item;
}

export function parseVideoCollectionItem(e: Object): VideoCollectionItem {
  const map = asRecord(e);
  const item = new VideoCollectionItem();
  item.id = asNum(map['id']);
  item.ownerId = asNum(map['uid']);
  item.name = asStr(map['name']);
  item.pathList = asStringArray(map['path_list']);
  item.createTime = asStr(map['create_time']);
  const previews: VideoCollectionPreviewItem[] = [];
  for (const p of asArray(map['previews'])) {
    const pv = parseCollectionPreview(p);
    if (pv.fullpath.length > 0) {
      previews.push(pv);
    }
  }
  item.previews = previews;
  return item;
}

export function parseVideoCollectionListResult(e: Object): VideoCollectionListResult {
  const map = asRecord(e);
  const result = new VideoCollectionListResult();
  for (const item of asArray(map['items'])) {
    const col = parseVideoCollectionItem(item);
    if (col.id > 0) {
      result.items.push(col);
    }
  }
  result.page = parsePagination(map['pagination']);
  return result;
}

// ===== 智能相册（对齐 smart_album/models/video_smart_album_model.dart） =====

export class VideoSmartAlbumPreviewItem {
  fullpath: string = '';
  firstFilePath: string = '';
}

export class VideoSmartAlbumItem {
  id: number = 0;
  uid: number = 0;
  name: string = '';
  type: string = 'condition';
  filterContent: Record<string, Object> = {};
  previews: VideoSmartAlbumPreviewItem[] = [];
}

export class VideoSmartAlbumListResult {
  items: VideoSmartAlbumItem[] = [];
  page: VideoPageInfo = new VideoPageInfo();
}

export class VideoSmartAlbumDetail {
  id: number = 0;
  uid: number = 0;
  name: string = '';
  type: string = 'condition';
  filterContent: Record<string, Object> = {};
}

function parseSmartAlbumPreview(e: Object): VideoSmartAlbumPreviewItem {
  const map = asRecord(e);
  const item = new VideoSmartAlbumPreviewItem();
  item.fullpath = asStr(map['fullpath']);
  item.firstFilePath = asStr(map['first_file_path']);
  return item;
}

export function parseVideoSmartAlbumItem(e: Object): VideoSmartAlbumItem {
  const map = asRecord(e);
  const item = new VideoSmartAlbumItem();
  item.id = asNum(map['id']);
  item.uid = asNum(map['uid']);
  item.name = asStr(map['name']);
  item.type = asStr(map['type'], 'condition');
  item.filterContent = asRecord(map['filter_content']);
  const previews: VideoSmartAlbumPreviewItem[] = [];
  for (const p of asArray(map['previews'])) {
    const pv = parseSmartAlbumPreview(p);
    if (pv.fullpath.length > 0 || pv.firstFilePath.length > 0) {
      previews.push(pv);
    }
  }
  item.previews = previews;
  return item;
}

export function parseVideoSmartAlbumListResult(e: Object): VideoSmartAlbumListResult {
  const map = asRecord(e);
  const result = new VideoSmartAlbumListResult();
  for (const item of asArray(map['items'])) {
    const sa = parseVideoSmartAlbumItem(item);
    if (sa.id > 0) {
      result.items.push(sa);
    }
  }
  result.page = parsePagination(map['pagination']);
  return result;
}

export function parseVideoSmartAlbumDetail(e: Object): VideoSmartAlbumDetail {
  const map = asRecord(e);
  const detail = new VideoSmartAlbumDetail();
  detail.id = asNum(map['id']);
  detail.uid = asNum(map['uid']);
  detail.name = asStr(map['name']);
  detail.type = asStr(map['type'], 'condition');
  detail.filterContent = asRecord(map['filter_content']);
  return detail;
}

// ===== 视频列表（对齐 list/service/video_list_api_service.dart） =====

export class VideoIndexCountResult {
  movie: number = 0;
  tv: number = 0;

  get total(): number {
    return this.movie + this.tv;
  }
}

export class VideoListPagination {
  total: number = 0;
  page: number = 1;
  limit: number = 30;
  totalPages: number = 0;
  hasNextPage: boolean = false;
  hasPrevPage: boolean = false;
}

export class VideoListFilterOptions {
  genres: string[] = [];
  regions: string[] = [];
  years: number[] = [];
}

export class VideoListPathItem {
  path: string = '';
  valid: boolean = false;
}

export class VideoListPagedResult {
  items: VideoHomeItemBean[] = [];
  pagination: VideoListPagination = new VideoListPagination();
  filters: VideoListFilterOptions | undefined = undefined;
  validPaths: VideoListPathItem[] = [];
}

export function parseVideoIndexCountResult(e: Object): VideoIndexCountResult {
  const map = asRecord(e);
  const result = new VideoIndexCountResult();
  result.movie = asNum(map['movie']);
  result.tv = asNum(map['tv']);
  return result;
}

export function parseVideoListPagedResult(e: Object): VideoListPagedResult {
  const map = asRecord(e);
  const result = new VideoListPagedResult();
  result.items = parseVideoItemList(map['items']);
  const p = asRecord(map['pagination']);
  result.pagination.total = asNum(p['total']);
  result.pagination.page = asNum(p['page'], 1);
  result.pagination.limit = asNum(p['limit'], 30);
  result.pagination.totalPages = asNum(p['totalPages']);
  result.pagination.hasNextPage = asBool(p['hasNextPage']);
  result.pagination.hasPrevPage = asBool(p['hasPrevPage']);
  const filtersRaw = map['filters'] ?? map['filterOptions'];
  if (filtersRaw !== undefined && filtersRaw !== null) {
    const f = asRecord(filtersRaw);
    const options = new VideoListFilterOptions();
    options.genres = asStringArray(f['genres']);
    options.regions = asStringArray(f['regions']);
    options.years = asNumberArray(f['years']);
    result.filters = options;
  }
  const validPathsRaw = map['validPaths'] ?? map['valid_paths'];
  for (const e2 of asArray(validPathsRaw)) {
    if (typeof e2 === 'string') {
      const path = e2.trim();
      if (path.length > 0) {
        const item = new VideoListPathItem();
        item.path = path;
        item.valid = true;
        result.validPaths.push(item);
      }
    } else {
      const m = asRecord(e2);
      const path = asStr(m['path']).trim();
      if (path.length > 0) {
        const item = new VideoListPathItem();
        item.path = path;
        item.valid = asBool(m['valid']);
        result.validPaths.push(item);
      }
    }
  }
  return result;
}

// ===== 视频来源（对齐 source_setting/models/video_source.dart） =====

export class VideoSource {
  id: number = 0;
  path: string = '';
  exists: boolean = true;
  mediaType: string = '';
  matchNfo: number = 0;
  scanWhenStart: number = 0;
  scanWhenChange: number = 1;
  isShow: number = 1;
  ctime: string = '';
  scanInterval: number = 0;
  scanIntervalMs: number = 0;
  scanIntervalConfig: string = '';
  lastScanTime: number = 0;
}

export function parseVideoSource(e: Object): VideoSource {
  const map = asRecord(e);
  const item = new VideoSource();
  item.id = asNum(map['id']);
  item.path = asStr(map['path']);
  item.exists = asBool(map['exists'], true);
  item.mediaType = asStr(map['media_type']);
  item.matchNfo = asNum(map['match_nfo']);
  item.scanWhenStart = asNum(map['scan_when_start']);
  item.scanWhenChange = asNum(map['scan_when_change'], 1);
  item.isShow = asNum(map['is_show'], 1);
  item.ctime = asStr(map['ctime']);
  item.scanInterval = asNum(map['scan_interval']);
  item.scanIntervalMs = asNum(map['scan_interval_ms']);
  item.scanIntervalConfig = asStr(map['scan_interval_config']);
  item.lastScanTime = asNum(map['last_scan_time']);
  return item;
}

// ===== TMDB 搜索（对齐 tmdb/service/video_tmdb_api_service.dart） =====

export class VideoTmdbSearchItem {
  id: number = 0;
  mediaType: string = '';
  title: string = '';
  originalTitle: string = '';
  overview: string = '';
  year: number = 0;
  posterUrl: string = '';
  backdropUrl: string = '';
  voteAverage: number = 0;
  actors: string[] = [];
  genres: string[] = [];
}

export class VideoTmdbSearchResult {
  page: number = 1;
  totalPages: number = 0;
  results: VideoTmdbSearchItem[] = [];
}

export function parseVideoTmdbSearchResult(e: Object): VideoTmdbSearchResult {
  const map = asRecord(e);
  const result = new VideoTmdbSearchResult();
  result.page = asNum(map['page'], 1);
  result.totalPages = asNum(map['total_pages']);
  for (const item of asArray(map['results'])) {
    const m = asRecord(item);
    const entry = new VideoTmdbSearchItem();
    entry.id = asNum(m['id']);
    entry.mediaType = asStr(m['media_type']).trim();
    entry.title = asStr(m['title']).trim();
    entry.originalTitle = asStr(m['original_title']).trim();
    entry.overview = asStr(m['overview']).trim();
    entry.year = asNum(m['year']);
    entry.posterUrl = asStr(m['poster_url']).trim();
    entry.backdropUrl = asStr(m['backdrop_url']).trim();
    entry.voteAverage = asNum(m['vote_average']);
    entry.actors = asStringArray(m['actors']);
    entry.genres = asStringArray(m['genres']);
    result.results.push(entry);
  }
  return result;
}

/** 通用 JSON 兜底解析（用于 Map<String, dynamic> 响应） */
export function parseJsonObject(e: Object): Record<string, Object> {
  return JsonCodec.parse<Record<string, Object>>(e);
}
