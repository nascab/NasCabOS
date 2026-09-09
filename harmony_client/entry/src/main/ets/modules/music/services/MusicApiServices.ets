import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { AppEventBus } from '../../../common/AppEventBus';
import {
  AlbumArtistGroupItem, AlbumArtistListPagedResult, LyricSearchItem,
  MusicApiResult, MusicCollectionItem, MusicCollectionListResult,
  MusicListCountResult, MusicListItem, MusicListPagedResult,
  MusicSource, PlayListItem, PlayListPagedResult,
  asArray, asNum, asRecord, asStr, musicItemFromJson
} from '../models/MusicModels';

/**
 * 音乐库全部 API 服务（对齐 Flutter music 模块各 *_api_service.dart）。
 * 统一走 APIClient（自动带 Authorization、401 刷新、P2P 通道）。
 */

class MusicApiBase {
  /** POST JSON 并解析响应 data 字段；失败/未登录返回 undefined */
  protected static async post(endpoint: string, body: Record<string, Object> | Array<Object> | undefined,
    showLoading: boolean = false): Promise<MusicApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return MusicApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiPost<Object>(endpoint, body as Object);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        return MusicApiResult.fail<Object>(msg.length > 0 ? msg : L10n.operationFailed);
      }
      return MusicApiResult.ok<Object>(res.data);
    } catch (e) {
      return MusicApiResult.fail<Object>(L10n.networkFailure);
    }
  }

  protected static strList(v: Object | undefined | null): string[] {
    const out: string[] = [];
    for (const e of asArray(v)) {
      const s = `${e}`.trim();
      if (s.length > 0) {
        out.push(s);
      }
    }
    return out;
  }
}

// ===== /api/music/list（歌曲列表，对齐 MusicListApiService.listPaged） =====

export interface MusicListQuery {
  page: number;
  pageSize: number;
  listType: string;
  listId: number;
  seriesIndexId: number;
  collectionId: number;
  isFavorite: boolean;
  isHistory: boolean;
  search: string;
  artists: string[];
  albums: string[];
  genres: string[];
  sourceList: string[];
  sortBy: string;
  sortOrder: string;
}

export class MusicListQueryFactory {
  static default(): MusicListQuery {
    return {
      page: 1, pageSize: 300, listType: '', listId: 0, seriesIndexId: 0,
      collectionId: 0, isFavorite: false, isHistory: false, search: '',
      artists: [], albums: [], genres: [], sourceList: [],
      sortBy: 'title', sortOrder: 'asc'
    };
  }
}

export class MusicListApiService extends MusicApiBase {
  static async listPaged(q: MusicListQuery): Promise<MusicApiResult<MusicListPagedResult>> {
    const body: Record<string, Object> = {
      'page': q.page,
      'page_size': q.pageSize,
      'sort_by': q.sortBy,
      'sort_order': q.sortOrder
    };
    if (q.listType.trim().length > 0) {
      body['listType'] = q.listType.trim();
    }
    if (q.listId > 0) {
      body['list_id'] = q.listId;
    }
    if (q.seriesIndexId > 0) {
      body['series_index_id'] = q.seriesIndexId;
    }
    if (q.collectionId > 0) {
      body['collection_id'] = q.collectionId;
    }
    if (q.isFavorite) {
      body['is_favorite'] = 1;
    }
    if (q.isHistory) {
      body['isHistory'] = 1;
    }
    const search = q.search.trim();
    if (search.length > 0) {
      body['search'] = search;
    }
    if (q.artists.length > 0) {
      body['artists'] = q.artists as Object;
    }
    if (q.albums.length > 0) {
      body['albums'] = q.albums as Object;
    }
    if (q.genres.length > 0) {
      body['genres'] = q.genres as Object;
    }
    if (q.sourceList.length > 0) {
      body['sourceList'] = q.sourceList as Object;
    }
    const res = await MusicApiBase.post('/api/music/list', body);
    if (!res.success) {
      return MusicApiResult.fail<MusicListPagedResult>(res.message);
    }
    return MusicApiResult.ok(MusicListPagedResult.fromJson(res.data));
  }

  /** 列表数量（对齐 /api/music/list/count，body 仅 sourceList） */
  static async listCount(sourceList: string[]): Promise<MusicListCountResult | undefined> {
    const body: Record<string, Object> = {};
    if (sourceList.length > 0) {
      body['sourceList'] = sourceList as Object;
    }
    const res = await MusicApiBase.post('/api/music/list/count', body);
    if (!res.success) {
      return undefined;
    }
    return MusicListCountResult.fromJson(res.data);
  }

  /** 批量收藏/取消收藏（对齐 MusicFavoriteApiService.batchFavorite） */
  static async batchFavorite(indexIds: number[], favorite: boolean): Promise<boolean> {
    const ids = Array.from(new Set<number>(indexIds.filter((e: number): boolean => e > 0)));
    if (ids.length === 0) {
      return false;
    }
    const body: Record<string, Object> = { 'index_ids': ids as Object, 'favorite': favorite };
    const res = await MusicApiBase.post('/api/music/favorite/batch', body, true);
    return res.success;
  }

  static async addFavorite(id: number): Promise<boolean> {
    const body: Record<string, Object> = { 'index_id': id };
    const res = await MusicApiBase.post('/api/music/favorite/add', body);
    return res.success;
  }

  static async removeFavorite(id: number): Promise<boolean> {
    const body: Record<string, Object> = { 'index_id': id };
    const res = await MusicApiBase.post('/api/music/favorite/remove', body);
    return res.success;
  }

  /** 删除歌曲（对齐 /api/music/delete body{paths[],recycle}） */
  static async deleteMusic(paths: string[], recycle: boolean): Promise<MusicApiResult<boolean>> {
    if (paths.length === 0) {
      return MusicApiResult.fail<boolean>(L10n.t('network_failure', '网络请求失败'));
    }
    const body: Record<string, Object> = { 'paths': paths as Object, 'recycle': recycle };
    const res = await MusicApiBase.post('/api/music/delete', body, true);
    if (!res.success) {
      return MusicApiResult.fail<boolean>(res.message);
    }
    return MusicApiResult.ok<boolean>(true);
  }

  /** 歌曲详情（对齐 /api/music/detail/get body{file_path}，返回 {item,lyrics}） */
  static async getDetail(filePath: string): Promise<MusicApiResult<MusicDetailResult>> {
    const p = filePath.trim();
    if (p.length === 0) {
      return MusicApiResult.fail<MusicDetailResult>('empty');
    }
    const body: Record<string, Object> = { 'file_path': p };
    const res = await MusicApiBase.post('/api/music/detail/get', body);
    if (!res.success) {
      return MusicApiResult.fail<MusicDetailResult>(res.message);
    }
    const r = asRecord(res.data);
    const out = new MusicDetailResult();
    out.item = musicItemFromJson(r['item']);
    out.lyrics = asStr(r['lyrics']);
    return MusicApiResult.ok(out);
  }

  /** 播放历史刷新（对齐 /api/music/history/refresh body{index_id?|file_path?}） */
  static async refreshHistoryByIndexId(indexId: number): Promise<void> {
    if (indexId <= 0) {
      return;
    }
    const body: Record<string, Object> = { 'index_id': indexId };
    await MusicApiBase.post('/api/music/history/refresh', body);
  }

  static async refreshHistoryByFilePath(filePath: string): Promise<void> {
    const p = filePath.trim();
    if (p.length === 0) {
      return;
    }
    const body: Record<string, Object> = { 'file_path': p };
    await MusicApiBase.post('/api/music/history/refresh', body);
  }

  static async searchLyric(keyword: string): Promise<LyricSearchItem[]> {
    const q = keyword.trim();
    if (q.length === 0) {
      return [];
    }
    const body: Record<string, Object> = { 'keyword': q };
    const res = await MusicApiBase.post('/api/music/lyric/search', body);
    if (!res.success) {
      return [];
    }
    const out: LyricSearchItem[] = [];
    for (const e of asArray(res.data)) {
      out.push(LyricSearchItem.fromJson(e));
    }
    return out;
  }

  static async setLyric(musicPath: string, lrc: string): Promise<boolean> {
    const p = musicPath.trim();
    const lyric = lrc.trim();
    if (p.length === 0 || lyric.length === 0) {
      return false;
    }
    const body: Record<string, Object> = { 'music_path': p, 'lrc': lyric };
    const res = await MusicApiBase.post('/api/music/lyric/set', body);
    return res.success;
  }
}

export class MusicDetailResult {
  item: MusicListItem = new MusicListItem();
  lyrics: string = '';
}

// ===== 专辑 / 艺人（对齐 AlbumArtistListApiService） =====

export class AlbumArtistListApiService extends MusicApiBase {
  static async listPaged(keyType: string, page: number, pageSize: number, search: string,
    sourceList: string[], sortBy: string, sortOrder: string): Promise<MusicApiResult<AlbumArtistListPagedResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'page_size': pageSize,
      'sort_by': sortBy,
      'sort_order': sortOrder
    };
    const s = search.trim();
    if (s.length > 0) {
      body['search'] = s;
    }
    if (sourceList.length > 0) {
      body['sourceList'] = sourceList as Object;
    }
    const path = keyType === 'artist' ? '/api/music/artist/list' : '/api/music/album/list';
    const res = await MusicApiBase.post(path, body);
    if (!res.success) {
      return MusicApiResult.fail<AlbumArtistListPagedResult>(res.message);
    }
    return MusicApiResult.ok(AlbumArtistListPagedResult.fromJson(res.data));
  }
}

// ===== 歌单（对齐 PlayListApiService） =====

export class PlayListApiService extends MusicApiBase {
  static async listLists(page: number = 1, pageSize: number = 30, search: string = '',
    sortBy: string = 'create_time', sortOrder: string = 'desc'): Promise<MusicApiResult<PlayListPagedResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'page_size': pageSize,
      'sort_by': sortBy,
      'sort_order': sortOrder
    };
    const s = search.trim();
    if (s.length > 0) {
      body['search'] = s;
    }
    const res = await MusicApiBase.post('/api/music/playlist/list', body);
    if (!res.success) {
      return MusicApiResult.fail<PlayListPagedResult>(res.message);
    }
    return MusicApiResult.ok(PlayListPagedResult.fromJson(res.data));
  }

  static async createList(name: string): Promise<MusicApiResult<PlayListItem>> {
    const body: Record<string, Object> = { 'name': name.trim() };
    const res = await MusicApiBase.post('/api/music/playlist/create', body, true);
    if (!res.success) {
      return MusicApiResult.fail<PlayListItem>(res.message);
    }
    return MusicApiResult.ok(PlayListItem.fromJson(res.data));
  }

  static async updateList(id: number, name: string): Promise<MusicApiResult<PlayListItem>> {
    const body: Record<string, Object> = { 'id': id, 'name': name.trim() };
    const res = await MusicApiBase.post('/api/music/playlist/update', body, true);
    if (!res.success) {
      return MusicApiResult.fail<PlayListItem>(res.message);
    }
    return MusicApiResult.ok(PlayListItem.fromJson(res.data));
  }

  static async deleteList(id: number): Promise<MusicApiResult<boolean>> {
    const body: Record<string, Object> = { 'id': id };
    const res = await MusicApiBase.post('/api/music/playlist/delete', body, true);
    if (!res.success) {
      return MusicApiResult.fail<boolean>(res.message);
    }
    return MusicApiResult.ok<boolean>(true);
  }

  static async addIndexes(listId: number, indexIds: number[]): Promise<MusicApiResult<boolean>> {
    const ids = Array.from(new Set<number>(indexIds.filter((e: number): boolean => e > 0))).sort();
    if (ids.length === 0) {
      return MusicApiResult.fail<boolean>(L10n.networkFailure);
    }
    const body: Record<string, Object> = { 'list_id': listId, 'index_ids': ids as Object };
    const res = await MusicApiBase.post('/api/music/playlist/index/add', body, true);
    if (!res.success) {
      return MusicApiResult.fail<boolean>(res.message);
    }
    return MusicApiResult.ok<boolean>(true);
  }

  static async removeIndexes(listId: number, indexIds: number[]): Promise<MusicApiResult<boolean>> {
    const ids = Array.from(new Set<number>(indexIds.filter((e: number): boolean => e > 0))).sort();
    if (ids.length === 0) {
      return MusicApiResult.fail<boolean>(L10n.networkFailure);
    }
    const body: Record<string, Object> = { 'list_id': listId, 'index_ids': ids as Object };
    const res = await MusicApiBase.post('/api/music/playlist/index/remove', body, true);
    if (!res.success) {
      return MusicApiResult.fail<boolean>(res.message);
    }
    return MusicApiResult.ok<boolean>(true);
  }
}

// ===== 合集（对齐 MusicCollectionApiService） =====

export class MusicCollectionApiService extends MusicApiBase {
  static async listCollections(page: number = 1, pageSize: number = 20, keyword: string = '',
    sortField: string = 'create_time', sortOrder: string = 'desc'): Promise<MusicApiResult<MusicCollectionListResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'pageSize': pageSize,
      'sortField': sortField,
      'sortOrder': sortOrder
    };
    const s = keyword.trim();
    if (s.length > 0) {
      body['keyword'] = s;
    }
    const res = await MusicApiBase.post('/api/music/collection/list', body);
    if (!res.success) {
      return MusicApiResult.fail<MusicCollectionListResult>(res.message);
    }
    return MusicApiResult.ok(MusicCollectionListResult.fromJson(res.data));
  }

  static async createCollection(name: string, pathList: string[]): Promise<MusicApiResult<number>> {
    const body: Record<string, Object> = { 'name': name, 'path_list': pathList as Object };
    const res = await MusicApiBase.post('/api/music/collection/create', body, true);
    if (!res.success) {
      return MusicApiResult.fail<number>(res.message);
    }
    return MusicApiResult.ok<number>(Math.trunc(asNum(asRecord(res.data)['id'])));
  }

  static async updateCollection(id: number, name: string, pathList: string[]): Promise<MusicApiResult<boolean>> {
    const body: Record<string, Object> = { 'id': id, 'name': name, 'path_list': pathList as Object };
    const res = await MusicApiBase.post('/api/music/collection/update', body, true);
    if (!res.success) {
      return MusicApiResult.fail<boolean>(res.message);
    }
    return MusicApiResult.ok<boolean>(true);
  }

  static async deleteCollection(id: number): Promise<MusicApiResult<number>> {
    const body: Record<string, Object> = { 'id': id };
    const res = await MusicApiBase.post('/api/music/collection/delete', body, true);
    if (!res.success) {
      return MusicApiResult.fail<number>(res.message);
    }
    return MusicApiResult.ok<number>(Math.trunc(asNum(asRecord(res.data)['affected'])));
  }
}

// ===== 音乐源（对齐 MusicSourceApiService） =====

export class MusicSourceApiService extends MusicApiBase {
  static async listSources(): Promise<MusicSource[]> {
    const res = await MusicApiBase.post('/api/music/source/list', {});
    if (!res.success) {
      return [];
    }
    const out: MusicSource[] = [];
    for (const e of asArray(res.data)) {
      out.push(MusicSource.fromJson(e));
    }
    return out;
  }

  static async addSource(path: string): Promise<MusicApiResult<Object>> {
    const body: Record<string, Object> = { 'path': path };
    return MusicApiBase.post('/api/music/source/add', body, true);
  }

  static async updateSource(id: number, payload: Record<string, Object>): Promise<MusicApiResult<Object>> {
    return MusicApiBase.post(`/api/music/source/update/${id}`, payload);
  }

  static async deleteSource(id: number): Promise<MusicApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return MusicApiBase.post('/api/music/source/delete', body);
  }

  static async relocateSource(id: number, newPath: string): Promise<MusicApiResult<Object>> {
    const body: Record<string, Object> = { 'new_path': newPath };
    return MusicApiBase.post(`/api/music/source/relocate/${id}`, body);
  }

  static async scanSource(path: string): Promise<MusicApiResult<Object>> {
    const body: Record<string, Object> = { 'path': path };
    return MusicApiBase.post('/api/music/source/scan', body);
  }
}

// ===== 文件属性（对齐 MusicPlayCtrlFullScreenFilePropertiesDialog._getFileProperties） =====

export class MusicFileAttributes {
  path: string = '';
  name: string = '';
  size: number = 0;
  birthtime: number = 0;
  mtime: number = 0;
}

export class MusicFileApiService extends MusicApiBase {
  static async getAttributes(filePath: string): Promise<MusicFileAttributes | undefined> {
    const p = filePath.trim();
    if (p.length === 0) {
      return undefined;
    }
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return undefined;
    }
    try {
      const queryParams = new Map<string, string>();
      queryParams.set('path', p);
      const res = await api.apiGet<Object>('/api/file/attributes', queryParams);
      if (!res.success) {
        return undefined;
      }
      const r = asRecord(res.data);
      const out = new MusicFileAttributes();
      out.path = asStr(r['path']);
      out.name = asStr(r['name']);
      out.size = Math.trunc(asNum(r['size']));
      out.birthtime = Math.trunc(asNum(r['birthtime']));
      out.mtime = Math.trunc(asNum(r['mtime']));
      return out;
    } catch (_e) {
      return undefined;
    }
  }
}

/** 分组项别名导出（view 层复用） */
export { AlbumArtistGroupItem };
export { asStr };
