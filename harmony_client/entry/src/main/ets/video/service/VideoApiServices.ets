import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import {
  VideoAlbumDetail, VideoAlbumItem, VideoAlbumListResult, VideoAlbumOverviewResult,
  VideoCollectionItem, VideoCollectionListResult, VideoHomeData, VideoHomeItemBean,
  VideoIndexCountResult, VideoListPagedResult, VideoSmartAlbumDetail, VideoSmartAlbumItem,
  VideoSmartAlbumListResult, VideoSource, VideoTmdbSearchResult,
  parseVideoAlbumDetail, parseVideoAlbumListResult, parseVideoAlbumOverviewResult,
  parseVideoCollectionItem, parseVideoCollectionListResult, parseVideoHomeData,
  parseVideoHomeItemBean, parseVideoIndexCountResult, parseVideoListPagedResult,
  parseVideoSmartAlbumDetail, parseVideoSmartAlbumListResult, parseVideoSource,
  parseVideoTmdbSearchResult
} from '../models/VideoModels';

/**
 * 影音管理 API 服务集合（对齐 Flutter video 模块各 *_api_service.dart）。
 */

function jsonRecordParser(): (data: Object, code: number) => Record<string, Object> {
  return (d: Object, _c: number) => JSON.parse(JSON.stringify(d)) as Record<string, Object>;
}

/** 空 POST body（显式类型，避免无类型对象字面量报错） */
const EMPTY_BODY: Record<string, Object> = {};

// ===== 相册（对齐 video_album_api_service.dart） =====

export class VideoAlbumApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async listAlbums(page: number = 1, pageSize: number = 50, keyword: string = '',
    sortField: string = 'create_time', sortOrder: string = 'desc', previewLimit: number = 0):
    Promise<APIResponse<VideoAlbumListResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'pageSize': pageSize,
      'sortField': sortField,
      'sortOrder': sortOrder
    };
    if (keyword.trim().length > 0) {
      body['keyword'] = keyword.trim();
    }
    if (previewLimit > 0) {
      body['previewLimit'] = previewLimit;
    }
    return this.api().apiPost<VideoAlbumListResult>('/api/video/album/list', body,
      undefined, undefined, undefined, parseVideoAlbumListResult);
  }

  async getAlbumOverview(limit: number = 6): Promise<APIResponse<VideoAlbumOverviewResult>> {
    const safeLimit = Math.min(Math.max(limit, 1), 12);
    const body: Record<string, Object> = { 'limit': safeLimit };
    return this.api().apiPost<VideoAlbumOverviewResult>('/api/video/album/overview', body,
      undefined, undefined, undefined, parseVideoAlbumOverviewResult);
  }

  async getAlbum(id: number): Promise<APIResponse<VideoAlbumDetail>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<VideoAlbumDetail>('/api/video/album/get', body,
      undefined, undefined, undefined, parseVideoAlbumDetail);
  }

  async createAlbum(name: string, isPublic: boolean): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'name': name, 'is_public': isPublic ? 1 : 0 };
    return this.api().apiPost<Record<string, Object>>('/api/video/album/create', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async updateAlbum(id: number, name: string, isPublic: boolean): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = {
      'id': id,
      'name': name,
      'is_public': isPublic ? 1 : 0
    };
    return this.api().apiPost<boolean>('/api/video/album/update', body, undefined, undefined,
      undefined, undefined);
  }

  async deleteAlbum(id: number): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<Record<string, Object>>('/api/video/album/delete', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async addAlbumIndexes(albumId: number, indexIds: number[]):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'album_id': albumId, 'index_ids': indexIds };
    return this.api().apiPost<Record<string, Object>>('/api/video/album/index/add', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async removeAlbumIndexes(albumId: number, indexIds: number[]):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'album_id': albumId, 'index_ids': indexIds };
    return this.api().apiPost<Record<string, Object>>('/api/video/album/index/remove', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async setAlbumCover(albumId: number, indexId: number): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'album_id': albumId, 'index_id': indexId };
    return this.api().apiPost<boolean>('/api/video/album/cover/set', body, undefined,
      undefined, undefined, undefined);
  }
}

// ===== 合集（对齐 video_collection_api_service.dart） =====

export class VideoCollectionApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async listCollections(page: number = 1, pageSize: number = 20, keyword: string = '',
    sortField: string = 'create_time', sortOrder: string = 'desc'):
    Promise<APIResponse<VideoCollectionListResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'pageSize': pageSize,
      'sortField': sortField,
      'sortOrder': sortOrder
    };
    if (keyword.trim().length > 0) {
      body['keyword'] = keyword.trim();
    }
    return this.api().apiPost<VideoCollectionListResult>('/api/video/collection/list', body,
      undefined, undefined, undefined, parseVideoCollectionListResult);
  }

  async getCollection(id: number): Promise<APIResponse<VideoCollectionItem>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<VideoCollectionItem>('/api/video/collection/get', body,
      undefined, undefined, undefined, parseVideoCollectionItem);
  }

  async createCollection(name: string, pathList: string[]):
    Promise<APIResponse<VideoCollectionItem>> {
    const body: Record<string, Object> = { 'name': name, 'path_list': pathList };
    return this.api().apiPost<VideoCollectionItem>('/api/video/collection/create', body,
      undefined, undefined, undefined, parseVideoCollectionItem);
  }

  async updateCollection(id: number, name: string, pathList: string[]):
    Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'id': id, 'name': name, 'path_list': pathList };
    return this.api().apiPost<boolean>('/api/video/collection/update', body, undefined,
      undefined, undefined, undefined);
  }

  async deleteCollection(id: number): Promise<APIResponse<number>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<number>('/api/video/collection/delete', body, undefined,
      undefined, undefined, (d: Object, _c: number) => {
        const map = JSON.parse(JSON.stringify(d)) as Record<string, Object>;
        const affected = map['affected'];
        return typeof affected === 'number' ? affected : Number(`${affected ?? 0}`) || 0;
      });
  }
}

// ===== 智能相册（对齐 video_smart_album_api_service.dart） =====

export class VideoSmartAlbumApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async listSmartAlbums(page: number, pageSize: number, keyword: string = '',
    sortField: string = '', sortOrder: string = ''):
    Promise<APIResponse<VideoSmartAlbumListResult>> {
    const body: Record<string, Object> = { 'page': page, 'pageSize': pageSize };
    if (keyword.length > 0) {
      body['keyword'] = keyword;
    }
    if (sortField.length > 0) {
      body['sortField'] = sortField;
    }
    if (sortOrder.length > 0) {
      body['sortOrder'] = sortOrder;
    }
    return this.api().apiPost<VideoSmartAlbumListResult>('/api/video/smart_album/list', body,
      undefined, undefined, undefined, parseVideoSmartAlbumListResult);
  }

  async getSmartAlbum(id: number): Promise<APIResponse<VideoSmartAlbumDetail>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<VideoSmartAlbumDetail>('/api/video/smart_album/get', body,
      undefined, undefined, undefined, parseVideoSmartAlbumDetail);
  }

  async createSmartAlbum(name: string, filterContent: Record<string, Object>):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'name': name,
      'type': 'condition',
      'filter_content': filterContent
    };
    return this.api().apiPost<Record<string, Object>>('/api/video/smart_album/create', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async updateSmartAlbum(id: number, name: string, filterContent: Record<string, Object>):
    Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = {
      'id': id,
      'name': name,
      'type': 'condition',
      'filter_content': filterContent
    };
    return this.api().apiPost<boolean>('/api/video/smart_album/update', body, undefined,
      undefined, undefined, undefined);
  }

  async deleteSmartAlbum(id: number): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<Record<string, Object>>('/api/video/smart_album/delete', body,
      undefined, undefined, undefined, jsonRecordParser());
  }
}

// ===== 首页（对齐 video_home_api_service.dart） =====

export class VideoHomeApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async getHomeData(recommendLimit: number = 11, recentPlayLimit: number = 20,
    recentAddLimit: number = 20): Promise<APIResponse<VideoHomeData>> {
    const body: Record<string, Object> = {
      'recommend_limit': recommendLimit,
      'recent_play_limit': recentPlayLimit,
      'recent_add_limit': recentAddLimit
    };
    return this.api().apiPost<VideoHomeData>('/api/video/home/data', body,
      undefined, undefined, undefined, parseVideoHomeData);
  }
}

// ===== 视频列表（对齐 video_list_api_service.dart） =====

export class VideoListApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async getIndexCounts(sourceList?: string[]): Promise<APIResponse<VideoIndexCountResult>> {
    const body: Record<string, Object> = {};
    if (sourceList !== undefined) {
      body['sourceList'] = sourceList;
    }
    return this.api().apiPost<VideoIndexCountResult>('/api/video/list/count', body,
      undefined, undefined, undefined, parseVideoIndexCountResult);
  }

  /** 分页列表（参数对齐 Flutter listPaged，空串/空数组不下发） */
  async listPaged(page: number, pageSize: number, listType: string = '',
    mediaType: string = '', albumId: number = 0, collectionId: number = 0,
    smartAlbumId: number = 0, search: string = '', genres: string[] | undefined = undefined,
    regions: string[] | undefined = undefined, actors: string[] | undefined = undefined,
    directors: string[] | undefined = undefined, years: number[] | undefined = undefined,
    sourceList: string[] | undefined = undefined, sortBy: string = '',
    sortOrder: string = ''): Promise<VideoListPagedResult> {
    const body: Record<string, Object> = {
      'page': page,
      'page_size': pageSize
    };
    if (listType.trim().length > 0) {
      body['listType'] = listType.trim();
    }
    if (mediaType.trim().length > 0) {
      body['media_type'] = mediaType.trim();
    }
    if (albumId > 0) {
      body['album_id'] = albumId;
    }
    if (collectionId > 0) {
      body['collection_id'] = collectionId;
    }
    if (smartAlbumId > 0) {
      body['smart_album_id'] = smartAlbumId;
    }
    body['search'] = search;
    body['genres'] = genres ?? [];
    body['regions'] = regions ?? [];
    body['actors'] = actors ?? [];
    body['directors'] = directors ?? [];
    body['years'] = years ?? [];
    body['sourceList'] = sourceList ?? [];
    if (sortBy.length > 0) {
      body['sort_by'] = sortBy;
    }
    if (sortOrder.length > 0) {
      body['sort_order'] = sortOrder;
    }
    const res = await this.api().apiPost<VideoListPagedResult>('/api/video/list', body,
      undefined, undefined, undefined, parseVideoListPagedResult);
    if (!res.success || res.data === undefined) {
      return new VideoListPagedResult();
    }
    return res.data;
  }
}

// ===== 播放历史（对齐 video_history_api_service.dart） =====

export class VideoHistoryApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async listHistory(): Promise<VideoHomeItemBean[]> {
    const res = await this.api().apiPost<Record<string, Object>>('/api/video/history/list', EMPTY_BODY,
      undefined, undefined, undefined, jsonRecordParser());
    if (!res.success || res.data === undefined) {
      return [];
    }
    const items: VideoHomeItemBean[] = [];
    const raw = res.data['items'];
    if (Array.isArray(raw)) {
      for (const e of raw as Object[]) {
        const item = parseVideoHomeItemBean(e);
        if (item.id > 0) {
          items.push(item);
        }
      }
    }
    return items;
  }

  async clearHistory(): Promise<number> {
    const res = await this.api().apiPost<Record<string, Object>>('/api/video/history/clear', EMPTY_BODY,
      undefined, undefined, undefined, jsonRecordParser());
    if (!res.success || res.data === undefined) {
      return 0;
    }
    const deleted = res.data['deleted'];
    return typeof deleted === 'number' ? deleted : Number(`${deleted ?? 0}`) || 0;
  }
}

// ===== 收藏（对齐 video_favorite_api_service.dart） =====

export class VideoFavoriteApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async addFavorite(indexId: number): Promise<boolean> {
    const body: Record<string, Object> = { 'index_id': indexId };
    const res = await this.api().apiPost<Object>('/api/video/favorite/add', body);
    return res.success;
  }

  async removeFavorite(indexId: number): Promise<boolean> {
    const body: Record<string, Object> = { 'index_id': indexId };
    const res = await this.api().apiPost<Object>('/api/video/favorite/remove', body);
    return res.success;
  }
}

// ===== 详情（对齐 video_detail_api_service.dart） =====

export class VideoDetailApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async getDetail(indexId: number): Promise<APIResponse<Record<string, Object>>> {
    const query = new Map<string, string>();
    query.set('index_id', `${indexId}`);
    return this.api().apiGet<Record<string, Object>>('/api/video/detail', query,
      undefined, undefined, jsonRecordParser());
  }

  async getEpisodes(indexId: number, page: number = 1, pageSize: number = 50,
    sortOrder: string = 'asc'): Promise<APIResponse<Record<string, Object>>> {
    const query = new Map<string, string>();
    query.set('index_id', `${indexId}`);
    query.set('page', `${page}`);
    query.set('page_size', `${pageSize}`);
    query.set('sort_order', sortOrder);
    return this.api().apiGet<Record<string, Object>>('/api/video/episodes', query,
      undefined, undefined, jsonRecordParser());
  }

  async getTvPlayInfo(indexId: number): Promise<APIResponse<Record<string, Object>>> {
    const query = new Map<string, string>();
    query.set('index_id', `${indexId}`);
    return this.api().apiGet<Record<string, Object>>('/api/video/tvPlayInfo', query,
      undefined, undefined, jsonRecordParser());
  }

  async setOpenSkip(indexId: number, openSkipStartSec: number, openSkipEndSec: number):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'index_id': indexId,
      'open_skip_start_sec': openSkipStartSec,
      'open_skip_end_sec': openSkipEndSec
    };
    return this.api().apiPost<Record<string, Object>>('/api/video/detail/open_skip/set', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async getDiscContents(indexId: number): Promise<APIResponse<Record<string, Object>>> {
    const query = new Map<string, string>();
    query.set('index_id', `${indexId}`);
    return this.api().apiGet<Record<string, Object>>('/api/video/discContents', query,
      undefined, undefined, jsonRecordParser());
  }

  /** 光盘内容缩略图 URL（明文 query，对齐 Flutter getDiscContentThumbUrl） */
  getDiscContentThumbUrl(indexId: number, internalPath: string, size: number = 320): string {
    const api = this.api();
    const token = api.accessToken ?? '';
    let url = `${api.baseUrl}/api/video/discContents/thumb?index_id=${encodeURIComponent(`${indexId}`)}`;
    url += `&internal_path=${encodeURIComponent(internalPath)}`;
    url += `&size=${encodeURIComponent(`${size}`)}`;
    if (token.trim().length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }
}

// ===== 来源设置（对齐 video_source_api_service.dart） =====

export class VideoSourceApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async listSources(): Promise<VideoSource[]> {
    const res = await this.api().apiPost<VideoSource[]>('/api/video/source/list', EMPTY_BODY,
      undefined, undefined, undefined, (d: Object, _c: number) => {
        const arr = JSON.parse(JSON.stringify(d)) as Object[];
        const out: VideoSource[] = [];
        for (const e of arr) {
          out.push(parseVideoSource(e));
        }
        return out;
      });
    return res.data ?? [];
  }

  async addSource(path: string, mediaType: string, matchNfo: number):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'path': path,
      'media_type': mediaType,
      'match_nfo': matchNfo
    };
    return this.api().apiPost<Record<string, Object>>('/api/video/source/add', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async updateSource(id: number, payload: Record<string, Object>):
    Promise<APIResponse<Record<string, Object>>> {
    return this.api().apiPost<Record<string, Object>>(`/api/video/source/update/${id}`, payload,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async updateMediaType(id: number, mediaType: string):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'media_type': mediaType };
    return this.api().apiPost<Record<string, Object>>(`/api/video/source/media_type/${id}`, body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async updateMatchNfo(id: number, matchNfo: number):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'match_nfo': matchNfo };
    return this.api().apiPost<Record<string, Object>>(`/api/video/source/match_nfo/${id}`, body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async deleteSource(id: number): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<Record<string, Object>>('/api/video/source/delete', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async relocateSource(id: number, newPath: string):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'new_path': newPath };
    return this.api().apiPost<Record<string, Object>>(`/api/video/source/relocate/${id}`, body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async scanSource(path: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'path': path };
    return this.api().apiPost<Record<string, Object>>('/api/video/source/scan', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async scanIndex(indexId: number): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'index_id': indexId };
    return this.api().apiPost<Record<string, Object>>('/api/video/source/scan_index', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  /** 预生成缩略图（对齐 Flutter preGenerateThumbnails，端点复用 photo 模块） */
  async preGenerateThumbnails(): Promise<APIResponse<Record<string, Object>>> {
    return this.api().apiPost<Record<string, Object>>('/api/photo/source/regenerate_thumbnails', EMPTY_BODY,
      undefined, undefined, undefined, jsonRecordParser());
  }
}

// ===== 刮削（对齐 video_scrape_api_service.dart） =====

export class VideoScrapeApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async startScrape(indexId: number, tmdbId: number = 0, mode: string = ''):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'index_id': indexId };
    if (tmdbId > 0) {
      body['tmdb_id'] = tmdbId;
    }
    if (mode.trim().length > 0) {
      body['mode'] = mode.trim();
    }
    return this.api().apiPost<Record<string, Object>>('/api/video/scrape/start', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async cleanupScrape(indexId: number): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'index_id': indexId };
    return this.api().apiPost<Record<string, Object>>('/api/video/scrape/cleanup', body,
      undefined, undefined, undefined, jsonRecordParser());
  }
}

// ===== TMDB 搜索（对齐 video_tmdb_api_service.dart） =====

export class VideoTmdbApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async search(mediaType: string, searchMode: string, query: string = '',
    tmdbId: string = '', page: number = 1): Promise<VideoTmdbSearchResult> {
    const body: Record<string, Object> = {
      'media_type': mediaType,
      'search_mode': searchMode,
      'page': page
    };
    if (query.trim().length > 0) {
      body['query'] = query.trim();
    }
    if (tmdbId.trim().length > 0) {
      body['tmdb_id'] = tmdbId.trim();
    }
    const res = await this.api().apiPost<VideoTmdbSearchResult>('/api/video/tmdb/search', body,
      undefined, undefined, undefined, parseVideoTmdbSearchResult);
    if (!res.success || res.data === undefined) {
      return new VideoTmdbSearchResult();
    }
    return res.data;
  }
}

// ===== TMDB/转码/字幕设置（对齐 video_tmdb_settings_api_service.dart） =====

export class VideoTmdbSettingsApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async getTmdbConfig(): Promise<APIResponse<Record<string, Object>>> {
    return this.api().apiPost<Record<string, Object>>('/api/video/getTmdbConfig', EMPTY_BODY,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async setTmdbConfig(accessToken: string, proxyEnable: boolean, proxyUrl: string,
    language: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'accessToken': accessToken,
      'proxyEnable': proxyEnable ? 1 : 0,
      'proxyUrl': proxyUrl,
      'language': language
    };
    return this.api().apiPost<Record<string, Object>>('/api/video/setTmdbConfig', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async getTranscodeConfig(): Promise<APIResponse<Record<string, Object>>> {
    return this.api().apiPost<Record<string, Object>>('/api/video/getTranscodeConfig', EMPTY_BODY,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async getSubtitleConfig(): Promise<APIResponse<Record<string, Object>>> {
    return this.api().apiPost<Record<string, Object>>('/api/video/getSubtitleConfig', EMPTY_BODY,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async setSubtitleConfig(preExtractEnable: boolean): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'preExtractEnable': preExtractEnable ? 1 : 0 };
    return this.api().apiPost<Record<string, Object>>('/api/video/setSubtitleConfig', body,
      undefined, undefined, undefined, jsonRecordParser());
  }

  async setTranscodeConfig(tempDir: string, preferredHwDecoder: string):
    Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'tempDir': tempDir,
      'preferredHwDecoder': preferredHwDecoder
    };
    return this.api().apiPost<Record<string, Object>>('/api/video/setTranscodeConfig', body,
      undefined, undefined, undefined, jsonRecordParser());
  }
}
