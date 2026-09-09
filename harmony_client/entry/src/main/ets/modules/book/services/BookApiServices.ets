import { APIClient } from '../../../core/network/APIClient';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { L10n } from '../../../core/localization/L10n';
import { AppEventBus } from '../../../common/AppEventBus';
import {
  BookApiResult, BookIndexCountResult, BookListItem, BookListPagedResult,
  BookCustomListItem, BookCustomListPagedResult, BookCollectionItem,
  BookCollectionListResult, BookSource, bRecord, bArray, bStr, bNum
} from '../models/BookModels';

/**
 * 图书馆全部 API 服务（对齐 Flutter book 模块各 *_api_service.dart）。
 * 统一走 APIClient（自动带 Authorization、401 刷新、P2P 通道）。
 */

class BookApiBase {
  /** POST JSON 并解析响应 data 字段；失败/未登录返回 fail */
  public static async post(endpoint: string, body: Record<string, Object> | undefined,
    showLoading: boolean = false): Promise<BookApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return BookApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiPost<Object>(endpoint, body as Object);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        return BookApiResult.fail<Object>(msg.length > 0 ? msg : L10n.operationFailed);
      }
      return BookApiResult.ok<Object>(res.data);
    } catch (e) {
      return BookApiResult.fail<Object>(L10n.networkFailure);
    }
  }

  public static async get(endpoint: string, query: Map<string, string>,
    showLoading: boolean = false): Promise<BookApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return BookApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiGet<Object>(endpoint, query);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        return BookApiResult.fail<Object>(msg.length > 0 ? msg : L10n.operationFailed);
      }
      return BookApiResult.ok<Object>(res.data);
    } catch (e) {
      return BookApiResult.fail<Object>(L10n.networkFailure);
    }
  }

  static accessToken(): string {
    return (APIClient.getInstance().accessToken ?? '').trim();
  }
}

// ===== 图书列表（对齐 BookListApiService） =====

export class BookListApiService {
  /** 封面 URL：/api/book/tiny（同步拼接，对齐 Flutter getBookTinyUrl） */
  static buildTinyUrl(fileHash: string, size: number = 500): string {
    const fh = fileHash.trim();
    let safeSize = Math.round(size);
    if (safeSize < 50) {
      safeSize = 50;
    }
    if (safeSize > 2000) {
      safeSize = 2000;
    }
    const base = APIClient.getInstance().baseUrl;
    const token = BookApiBase.accessToken();
    let url = `${base}/api/book/tiny?file_hash=${encodeURIComponent(fh)}&size=${safeSize}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }

  /** 普通文件缩略图 URL（对齐 Flutter getTinyUrl） */
  static async buildFileTinyUrl(filePath: string, size?: number): Promise<string> {
    return ApiUrls.getTinyUrl(filePath, size);
  }

  static async getIndexCounts(sourceList?: string[]): Promise<BookApiResult<BookIndexCountResult>> {
    const body: Record<string, Object> = {};
    if (sourceList !== undefined) {
      body['sourceList'] = sourceList as Object;
    }
    const res = await BookApiBase.post('/api/book/list/count', body);
    if (!res.success) {
      return BookApiResult.fail<BookIndexCountResult>(res.message);
    }
    return BookApiResult.ok<BookIndexCountResult>(BookIndexCountResult.fromJson(res.data!));
  }

  static async listPaged(params: BookListQuery): Promise<BookApiResult<BookListPagedResult>> {
    const body: Record<string, Object> = {
      'page': params.page,
      'page_size': params.pageSize,
      'type': params.type.trim()
    };
    if (params.listId > 0) {
      body['list_id'] = params.listId;
    }
    if (params.seriesIndexId > 0) {
      body['series_index_id'] = params.seriesIndexId;
    }
    if (params.collectionId > 0) {
      body['collection_id'] = params.collectionId;
    }
    if (params.isFavorite) {
      body['is_favorite'] = 1;
    }
    if (params.search !== undefined) {
      body['search'] = params.search;
    }
    if (params.sourceList !== undefined) {
      body['sourceList'] = params.sourceList as Object;
    }
    if (params.sortBy !== undefined) {
      body['sort_by'] = params.sortBy;
    }
    if (params.sortOrder !== undefined) {
      body['sort_order'] = params.sortOrder;
    }
    const res = await BookApiBase.post('/api/book/list', body);
    if (!res.success) {
      return BookApiResult.fail<BookListPagedResult>(res.message);
    }
    return BookApiResult.ok<BookListPagedResult>(BookListPagedResult.fromJson(res.data!));
  }

  static async listHistory(showLoading: boolean = false): Promise<BookListPagedResult> {
    const res = await BookApiBase.post('/api/book/history/list', {});
    if (!res.success) {
      return BookListPagedResult.empty();
    }
    return BookListPagedResult.fromJson(res.data!);
  }

  static async clearHistory(showLoading: boolean = false): Promise<number> {
    const res = await BookApiBase.post('/api/book/history/clear', {});
    if (!res.success) {
      return 0;
    }
    const data = bRecord(res.data);
    return bNum(data['deleted']);
  }

  static async deleteEntries(paths: string[], recycle: boolean = false,
    showLoading: boolean = true): Promise<BookApiResult<Object>> {
    const targets = paths.map((e: string): string => e.trim()).filter((e: string): boolean => e.length > 0);
    targets.sort();
    if (targets.length === 0) {
      return BookApiResult.fail<Object>(L10n.networkFailure);
    }
    const body: Record<string, Object> = {
      'paths': targets as Object,
      'recycle': recycle
    };
    return BookApiBase.post('/api/book/delete', body);
  }
}

export interface BookListQuery {
  page: number;
  pageSize: number;
  type: string;
  listId: number;
  seriesIndexId: number;
  collectionId: number;
  isFavorite: boolean;
  search?: string;
  sourceList?: string[];
  sortBy?: string;
  sortOrder?: string;
}

// ===== 自建书单（对齐 BookCustomListApiService） =====

export class BookCustomListApiService {
  static async listLists(page: number = 1, pageSize: number = 30, search?: string,
    sortBy: string = 'create_time', sortOrder: string = 'desc'):
    Promise<BookApiResult<BookCustomListPagedResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'page_size': pageSize,
      'sort_by': sortBy,
      'sort_order': sortOrder
    };
    const s = search !== undefined ? search.trim() : '';
    if (s.length > 0) {
      body['search'] = s;
    }
    const res = await BookApiBase.post('/api/book/book_list/list', body);
    if (!res.success) {
      return BookApiResult.fail<BookCustomListPagedResult>(res.message);
    }
    return BookApiResult.ok<BookCustomListPagedResult>(BookCustomListPagedResult.fromJson(res.data!));
  }

  static async createList(name: string): Promise<BookApiResult<BookCustomListItem>> {
    const body: Record<string, Object> = { 'name': name.trim() };
    const res = await BookApiBase.post('/api/book/book_list/create', body);
    if (!res.success) {
      return BookApiResult.fail<BookCustomListItem>(res.message);
    }
    return BookApiResult.ok<BookCustomListItem>(BookCustomListItem.fromJson(res.data!));
  }

  static async updateList(id: number, name: string): Promise<BookApiResult<BookCustomListItem>> {
    const body: Record<string, Object> = { 'id': id, 'name': name.trim() };
    const res = await BookApiBase.post('/api/book/book_list/update', body);
    if (!res.success) {
      return BookApiResult.fail<BookCustomListItem>(res.message);
    }
    return BookApiResult.ok<BookCustomListItem>(BookCustomListItem.fromJson(res.data!));
  }

  static async deleteList(id: number): Promise<BookApiResult<boolean>> {
    const body: Record<string, Object> = { 'id': id };
    const res = await BookApiBase.post('/api/book/book_list/delete', body);
    if (!res.success) {
      return BookApiResult.fail<boolean>(res.message);
    }
    return BookApiResult.ok<boolean>(true);
  }

  static async addIndexes(listId: number, indexIds: number[]): Promise<BookApiResult<boolean>> {
    const ids = indexIds.filter((e: number): boolean => e > 0);
    const unique = BookCustomListApiService.dedupeSort(ids);
    if (unique.length === 0) {
      return BookApiResult.fail<boolean>(L10n.networkFailure);
    }
    const body: Record<string, Object> = { 'list_id': listId, 'index_ids': unique as Object };
    const res = await BookApiBase.post('/api/book/book_list/index/add', body);
    if (!res.success) {
      return BookApiResult.fail<boolean>(res.message);
    }
    return BookApiResult.ok<boolean>(true);
  }

  static async removeIndexes(listId: number, indexIds: number[]): Promise<BookApiResult<boolean>> {
    const ids = indexIds.filter((e: number): boolean => e > 0);
    const unique = BookCustomListApiService.dedupeSort(ids);
    if (unique.length === 0) {
      return BookApiResult.fail<boolean>(L10n.networkFailure);
    }
    const body: Record<string, Object> = { 'list_id': listId, 'index_ids': unique as Object };
    const res = await BookApiBase.post('/api/book/book_list/index/remove', body);
    if (!res.success) {
      return BookApiResult.fail<boolean>(res.message);
    }
    return BookApiResult.ok<boolean>(true);
  }

  private static dedupeSort(ids: number[]): number[] {
    const set = new Set<number>();
    for (const id of ids) {
      set.add(id);
    }
    const out: number[] = [];
    set.forEach((v: number) => {
      out.push(v);
    });
    out.sort((a: number, b: number): number => a - b);
    return out;
  }
}

// ===== 合集（对齐 BookCollectionApiService） =====

export class BookCollectionApiService {
  static async listCollections(page: number = 1, pageSize: number = 20, keyword?: string,
    sortField: string = 'create_time', sortOrder: string = 'desc'):
    Promise<BookApiResult<BookCollectionListResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'pageSize': pageSize,
      'sortField': sortField,
      'sortOrder': sortOrder
    };
    const kw = keyword !== undefined ? keyword.trim() : '';
    if (kw.length > 0) {
      body['keyword'] = kw;
    }
    const res = await BookApiBase.post('/api/book/collection/list', body);
    if (!res.success) {
      return BookApiResult.fail<BookCollectionListResult>(res.message);
    }
    return BookApiResult.ok<BookCollectionListResult>(BookCollectionListResult.fromJson(res.data!));
  }

  static async getCollection(id: number): Promise<BookApiResult<BookCollectionItem>> {
    const body: Record<string, Object> = { 'id': id };
    const res = await BookApiBase.post('/api/book/collection/get', body);
    if (!res.success) {
      return BookApiResult.fail<BookCollectionItem>(res.message);
    }
    return BookApiResult.ok<BookCollectionItem>(BookCollectionItem.fromJson(res.data!));
  }

  static async createCollection(name: string, pathList: string[]): Promise<BookApiResult<number>> {
    const body: Record<string, Object> = { 'name': name, 'path_list': pathList as Object };
    const res = await BookApiBase.post('/api/book/collection/create', body);
    if (!res.success) {
      return BookApiResult.fail<number>(res.message);
    }
    const data = bRecord(res.data);
    return BookApiResult.ok<number>(bNum(data['id']));
  }

  static async updateCollection(id: number, name: string, pathList: string[]):
    Promise<BookApiResult<boolean>> {
    const body: Record<string, Object> = { 'id': id, 'name': name, 'path_list': pathList as Object };
    const res = await BookApiBase.post('/api/book/collection/update', body);
    if (!res.success) {
      return BookApiResult.fail<boolean>(res.message);
    }
    return BookApiResult.ok<boolean>(true);
  }

  static async deleteCollection(id: number): Promise<BookApiResult<number>> {
    const body: Record<string, Object> = { 'id': id };
    const res = await BookApiBase.post('/api/book/collection/delete', body);
    if (!res.success) {
      return BookApiResult.fail<number>(res.message);
    }
    const data = bRecord(res.data);
    return BookApiResult.ok<number>(bNum(data['affected']));
  }
}

// ===== 收藏（对齐 BookFavoriteApiService） =====

export class BookFavoriteApiService {
  static async addFavorite(indexId: number): Promise<boolean> {
    return BookFavoriteApiService.batchFavorite([indexId], true);
  }

  static async removeFavorite(indexId: number): Promise<boolean> {
    return BookFavoriteApiService.batchFavorite([indexId], false);
  }

  static async batchFavorite(indexIds: number[], isFavorite: boolean): Promise<boolean> {
    const set = new Set<number>();
    for (const id of indexIds) {
      if (id > 0) {
        set.add(id);
      }
    }
    if (set.size === 0) {
      return false;
    }
    const ids: number[] = [];
    set.forEach((v: number) => {
      ids.push(v);
    });
    ids.sort((a: number, b: number): number => a - b);
    const body: Record<string, Object> = {
      'index_ids': ids as Object,
      'is_favorite': isFavorite
    };
    const res = await BookApiBase.post('/api/book/favorite/batch', body);
    return res.success;
  }
}

// ===== 漫画阅读器（对齐 BookComicReaderApiService） =====

export class BookArchiveImage {
  innerPath: string = '';
  url: string = '';
  raw: Record<string, Object> = {};

  get name(): string {
    const slash = this.innerPath.lastIndexOf('/');
    return slash >= 0 ? this.innerPath.substring(slash + 1) : this.innerPath;
  }
}

export class BookComicReaderApiService {
  static async getProgress(fileHash: string): Promise<Record<string, Object> | undefined> {
    const fh = fileHash.trim();
    if (fh.length === 0) {
      return undefined;
    }
    const query = new Map<string, string>();
    query.set('file_hash', fh);
    const res = await BookApiBase.get('/api/book/history', query);
    if (!res.success) {
      return undefined;
    }
    return bRecord(res.data);
  }

  static async upsertProgress(fileHash: string, currentPage: number, totalPage: number):
    Promise<Record<string, Object> | undefined> {
    const fh = fileHash.trim();
    if (fh.length === 0) {
      return undefined;
    }
    const body: Record<string, Object> = {
      'file_hash': fh,
      'current_page': currentPage,
      'total_page': totalPage
    };
    const res = await BookApiBase.post('/api/book/history', body);
    if (!res.success) {
      return undefined;
    }
    return bRecord(res.data);
  }

  static async listArchiveImages(fileHash: string, onlyImg: boolean = true):
    Promise<BookArchiveImage[]> {
    const fh = fileHash.trim();
    if (fh.length === 0) {
      return [];
    }
    const body: Record<string, Object> = {
      'file_hash': fh,
      'only_img': onlyImg
    };
    const res = await BookApiBase.post('/api/book/archive/list', body);
    if (!res.success) {
      return [];
    }
    const data = bRecord(res.data);
    const items = bArray(data['items']);
    const out: BookArchiveImage[] = [];
    for (const it of items) {
      const m = bRecord(it);
      const innerPath = bStr(m['path']);
      if (innerPath.length === 0) {
        continue;
      }
      const img = new BookArchiveImage();
      img.innerPath = innerPath;
      img.raw = m;
      img.url = BookComicReaderApiService.buildArchiveFileUrl(fh, innerPath);
      out.push(img);
    }
    return out;
  }

  static buildArchiveFileUrl(fileHash: string, innerPath: string): string {
    const fh = fileHash.trim();
    const base = APIClient.getInstance().baseUrl;
    const token = BookApiBase.accessToken();
    let url = `${base}/api/book/archive/file?file_hash=${encodeURIComponent(fh)}` +
      `&inner_path=${encodeURIComponent(innerPath)}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }
}

// ===== 来源路径（对齐 BookSourceApiService） =====

export class BookSourceApiService {
  static async listSources(): Promise<BookSource[]> {
    const res = await BookApiBase.post('/api/book/source/list', {});
    if (!res.success) {
      return [];
    }
    return BookSource.listFrom(res.data);
  }

  static async addSource(path: string): Promise<BookApiResult<Object>> {
    const body: Record<string, Object> = { 'path': path };
    return BookApiBase.post('/api/book/source/add', body);
  }

  static async updateSource(id: number, payload: Record<string, Object>): Promise<BookApiResult<Object>> {
    return BookApiBase.post(`/api/book/source/update/${id}`, payload);
  }

  static async deleteSource(id: number): Promise<BookApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return BookApiBase.post('/api/book/source/delete', body);
  }

  static async relocateSource(id: number, newPath: string): Promise<BookApiResult<Object>> {
    const body: Record<string, Object> = { 'new_path': newPath };
    return BookApiBase.post(`/api/book/source/relocate/${id}`, body);
  }

  static async scanSource(path: string): Promise<BookApiResult<Object>> {
    const body: Record<string, Object> = { 'path': path };
    return BookApiBase.post('/api/book/source/scan', body);
  }
}

// ===== 阅读器作用域 token（对齐 Flutter UserApiService.createScopedToken） =====

export class BookScopedTokenApiService {
  /**
   * 创建受限访问 token（阅读器 WebView 加载文件用）：
   * allowApi=[/api/book/history,/api/book/preference,/api/file/rawFile]，allowPath=[filePath]。
   */
  static async createScopedToken(filePath: string): Promise<string> {
    const body: Record<string, Object> = {
      'allow_api': ['/api/book/history', '/api/book/preference', '/api/file/rawFile'] as Object,
      'allow_path': [filePath] as Object,
      'expiresIn': '1440m'
    };
    const res = await BookApiBase.post('/api/user/token/scoped', body);
    if (!res.success || res.data === undefined) {
      return '';
    }
    return bStr(bRecord(res.data)['accessToken']);
  }
}
