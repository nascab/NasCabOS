/**
 * 音乐子列表控制器（对齐 Flutter MusicSubListController）：
 * 专辑/艺人/歌单/合集等打开的 Overlay 歌曲列表。
 * - 分页（300/页）/ 搜索防抖 / 排序持久化（全局键）
 * - playAll 携带 paging（续传下一页）
 * - 多选：收藏 / 加入歌单 / 移出歌单 / 删除；单曲：收藏 / 加入歌单 / 移出歌单 / 删除
 * - 下载依赖传输模块（未迁移）
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../../../core/localization/L10n';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { CacheKeys } from '../../../core/storage/CacheKeys';
import { ToastUtil } from '../../../common/ToastUtil';
import { MusicListItem } from '../models/MusicModels';
import { MusicListApiService, MusicListQuery, MusicListQueryFactory, PlayListApiService } from '../services/MusicApiServices';
import { MusicPlayService } from '../service/MusicPlayService';

const TAG = 'MusicSubListController';

export enum MusicSubListSortBy {
  filename = 0,
  title = 1,
  artist = 2,
  album = 3,
  year = 4,
  duration = 5,
  ctime = 6,
  mtime = 7,
  favoriteTime = 8
}

export enum MusicSubListSortOrder {
  asc = 0,
  desc = 1
}

export function subListSortByParam(by: MusicSubListSortBy): string {
  switch (by) {
    case MusicSubListSortBy.title:
      return 'title';
    case MusicSubListSortBy.artist:
      return 'artist';
    case MusicSubListSortBy.album:
      return 'album';
    case MusicSubListSortBy.year:
      return 'year';
    case MusicSubListSortBy.duration:
      return 'duration';
    case MusicSubListSortBy.ctime:
      return 'ctime';
    case MusicSubListSortBy.mtime:
      return 'mtime';
    case MusicSubListSortBy.favoriteTime:
      return 'favorite_time';
    default:
      return 'filename';
  }
}

export function parseSubListSortBy(s: string): MusicSubListSortBy | undefined {
  switch (s) {
    case 'filename':
      return MusicSubListSortBy.filename;
    case 'title':
      return MusicSubListSortBy.title;
    case 'artist':
      return MusicSubListSortBy.artist;
    case 'album':
      return MusicSubListSortBy.album;
    case 'year':
      return MusicSubListSortBy.year;
    case 'duration':
      return MusicSubListSortBy.duration;
    case 'ctime':
      return MusicSubListSortBy.ctime;
    case 'mtime':
      return MusicSubListSortBy.mtime;
    case 'favorite_time':
      return MusicSubListSortBy.favoriteTime;
    default:
      return undefined;
  }
}

/** SubList 打开参数（对齐 MusicSubListPayload） */
export class MusicSubListPayload {
  keyType: string;
  name: string;
  seriesIndexId: number;
  listId: number;
  listType: string;
  collectionId: number;
  isFavorite: boolean;
  isHistory: boolean;

  constructor(keyType: string = '', name: string = '', seriesIndexId: number = 0, listId: number = 0,
    listType: string = '', collectionId: number = 0, isFavorite: boolean = false, isHistory: boolean = false) {
    this.keyType = keyType.trim();
    this.name = name.trim();
    this.seriesIndexId = seriesIndexId;
    this.listId = listId;
    this.listType = listType;
    this.collectionId = collectionId;
    this.isFavorite = isFavorite;
    this.isHistory = isHistory;
  }
}

@ObservedV2
export class MusicSubListController {
  readonly keyType: string;
  readonly name: string;
  readonly isFavorite: boolean;
  readonly isHistory: boolean;
  readonly listId: number;
  readonly seriesIndexId: number;
  readonly collectionId: number;
  readonly listType: string;
  readonly initialSortBy: MusicSubListSortBy;
  readonly initialSortOrder: MusicSubListSortOrder;

  @Trace items: MusicListItem[] = [];
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace autoLoadFailed: boolean = false;
  @Trace total: number = 0;
  @Trace isMultiSelectMode: boolean = false;
  @Trace selectedItems: Set<number> = new Set<number>();
  @Trace sortBy: MusicSubListSortBy = MusicSubListSortBy.filename;
  @Trace sortOrder: MusicSubListSortOrder = MusicSubListSortOrder.asc;
  @Trace searchText: string = '';

  private page: number = 1;
  private readonly pageSize: number = 300;
  private searchDebounce: number = -1;

  constructor(payload: MusicSubListPayload, initialSortBy: MusicSubListSortBy = MusicSubListSortBy.filename,
    initialSortOrder: MusicSubListSortOrder = MusicSubListSortOrder.asc) {
    this.keyType = payload.keyType;
    this.name = payload.name;
    this.isFavorite = payload.isFavorite;
    this.isHistory = payload.isHistory;
    this.listId = payload.listId;
    this.seriesIndexId = payload.seriesIndexId;
    this.collectionId = payload.collectionId;
    this.listType = payload.listType;
    this.initialSortBy = initialSortBy;
    this.initialSortOrder = initialSortOrder;
  }

  private buildQuery(page: number): MusicListQuery {
    const q = MusicListQueryFactory.default();
    q.page = page;
    q.pageSize = this.pageSize;
    q.listType = this.listType;
    q.listId = this.listId;
    q.seriesIndexId = this.seriesIndexId;
    q.collectionId = this.collectionId;
    q.isFavorite = this.isFavorite;
    q.isHistory = this.isHistory;
    q.search = this.searchText;
    // artist/album 分组维度（历史/歌单等场景不带）
    if (!this.isHistory && this.keyType.trim().toLowerCase() === 'artist' && this.name.length > 0) {
      q.artists = [this.name];
    }
    if (!this.isHistory && this.keyType.trim().toLowerCase() === 'album' && this.name.length > 0) {
      q.albums = [this.name];
    }
    q.sortBy = subListSortByParam(this.sortBy);
    q.sortOrder = this.sortOrder === MusicSubListSortOrder.asc ? 'asc' : 'desc';
    return q;
  }

  private applyInitialSortFromCache(): void {
    const store = PreferencesStore.getInstance();
    const cachedBy = parseSubListSortBy(store.getString(CacheKeys.MUSIC_SUB_LIST_SORT_BY, '') ?? '');
    const cachedOrder = store.getString(CacheKeys.MUSIC_SUB_LIST_SORT_ORDER, '');
    if (cachedBy !== undefined && (cachedOrder === 'asc' || cachedOrder === 'desc')) {
      this.sortBy = cachedBy;
      this.sortOrder = cachedOrder === 'asc' ? MusicSubListSortOrder.asc : MusicSubListSortOrder.desc;
    } else {
      this.sortBy = this.initialSortBy;
      this.sortOrder = this.initialSortOrder;
    }
  }

  private saveSortToCache(): void {
    const store = PreferencesStore.getInstance();
    store.setString(CacheKeys.MUSIC_SUB_LIST_SORT_BY, subListSortByParam(this.sortBy));
    store.setString(CacheKeys.MUSIC_SUB_LIST_SORT_ORDER,
      this.sortOrder === MusicSubListSortOrder.asc ? 'asc' : 'desc');
  }

  onInit(): void {
    this.applyInitialSortFromCache();
    this.refreshList(true);
  }

  onClose(): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
  }

  // ===== 头部封面 =====

  get headerCoverPath(): string {
    if (this.items.length === 0) {
      return '';
    }
    return this.items[0].coverFilePath();
  }

  /** 封面 URL（ApiUrls.getMusicCoverUrl 为异步 AES 构造，UI 层 await） */
  async headerCoverUrl(): Promise<string> {
    if (this.items.length === 0) {
      return '';
    }
    if (this.items[0].hasInnerCover !== 1) {
      return '';
    }
    const p = this.headerCoverPath;
    if (p.length === 0) {
      return '';
    }
    return await ApiUrls.getMusicCoverUrl(p, 500);
  }

  // ===== 播放 =====

  async playAll(initialIndex: number = 0): Promise<void> {
    if (this.items.length === 0) {
      return;
    }
    const idx = Math.min(Math.max(initialIndex, 0), this.items.length - 1);
    await MusicPlayService.getInstance().playFromList(this.items.slice(), this.items[idx], true, this.buildQuery(this.page));
  }

  async playAt(index: number): Promise<void> {
    await this.playAll(index);
  }

  // ===== 多选 =====

  /** 多选模式变化回调（页面用于隐藏悬浮播放条等） */
  onMultiSelectChanged: ((v: boolean) => void) | undefined = undefined;

  private notifyMultiMode(): void {
    if (this.onMultiSelectChanged !== undefined) {
      this.onMultiSelectChanged(this.isMultiSelectMode);
    }
  }

  toggleMultiSelectMode(): void {
    this.isMultiSelectMode = !this.isMultiSelectMode;
    if (!this.isMultiSelectMode) {
      this.selectedItems = new Set<number>();
    }
    this.notifyMultiMode();
  }

  toggleSelection(id: number): void {
    if (id <= 0) {
      return;
    }
    const next = new Set<number>(this.selectedItems);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    this.selectedItems = next;
    if (next.size > 0 && !this.isMultiSelectMode) {
      this.isMultiSelectMode = true;
    }
    if (next.size === 0) {
      this.exitMultiSelectMode();
      return;
    }
    this.notifyMultiMode();
  }

  get isAllCurrentSelected(): boolean {
    const ids = this.items.map((e: MusicListItem): number => e.id).filter((e: number): boolean => e > 0);
    if (ids.length === 0) {
      return false;
    }
    return ids.every((e: number): boolean => this.selectedItems.has(e));
  }

  toggleSelectAllCurrent(): void {
    const ids = this.items.map((e: MusicListItem): number => e.id).filter((e: number): boolean => e > 0);
    if (ids.length === 0) {
      return;
    }
    if (this.isAllCurrentSelected) {
      const next = new Set<number>(this.selectedItems);
      for (const id of ids) {
        next.delete(id);
      }
      this.selectedItems = next;
      this.exitMultiSelectMode();
      return;
    }
    const next = new Set<number>(this.selectedItems);
    for (const id of ids) {
      next.add(id);
    }
    this.selectedItems = next;
    if (!this.isMultiSelectMode) {
      this.isMultiSelectMode = true;
    }
    this.notifyMultiMode();
  }

  exitMultiSelectMode(): void {
    this.isMultiSelectMode = false;
    this.selectedItems = new Set<number>();
    this.notifyMultiMode();
  }

  get isSelectedAllFavorited(): boolean {
    const selected = this.items.filter((e: MusicListItem): boolean => this.selectedItems.has(e.id));
    if (selected.length === 0) {
      return false;
    }
    return selected.every((e: MusicListItem): boolean => e.isFavorite);
  }

  // ===== 排序 / 搜索 =====

  setSort(by: MusicSubListSortBy, order: MusicSubListSortOrder): void {
    if (this.sortBy === by && this.sortOrder === order) {
      return;
    }
    this.sortBy = by;
    this.sortOrder = order;
    this.saveSortToCache();
    this.refreshList(true);
  }

  onSearchChanged(v: string): void {
    this.searchText = v;
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout((): void => {
      this.searchDebounce = -1;
      this.refreshList(false);
    }, 320);
  }

  setSearchImmediate(v: string): void {
    this.searchText = v;
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshList(false);
  }

  clearSearch(): void {
    this.searchText = '';
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshList(false);
  }

  // ===== 列表 =====

  async refreshList(showLoading: boolean = false): Promise<void> {
    if (showLoading) {
      this.loading = true;
    }
    this.autoLoadFailed = false;
    try {
      this.page = 1;
      const res = await MusicListApiService.listPaged(this.buildQuery(1));
      if (res.success && res.data !== undefined) {
        this.items = res.data.items;
        this.total = res.data.pagination.total;
        this.hasMore = res.data.pagination.hasNextPage;
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'refreshList failed: %{public}s', JSON.stringify(e));
    } finally {
      this.loading = false;
    }
  }

  async loadMore(fromAuto: boolean = false): Promise<void> {
    if (this.loadingMore || this.loading) {
      return;
    }
    if (!this.hasMore) {
      return;
    }
    if (fromAuto && this.autoLoadFailed) {
      return;
    }
    this.loadingMore = true;
    try {
      const nextPage = this.page + 1;
      const res = await MusicListApiService.listPaged(this.buildQuery(nextPage));
      if (res.success && res.data !== undefined) {
        this.page = nextPage;
        this.items = this.items.concat(res.data.items);
        this.total = res.data.pagination.total;
        this.hasMore = res.data.pagination.hasNextPage;
        this.autoLoadFailed = false;
      }
    } catch (e) {
      this.autoLoadFailed = true;
      hilog.error(0x0000, TAG, 'loadMore failed: %{public}s', JSON.stringify(e));
    } finally {
      this.loadingMore = false;
    }
  }

  private autoLoadMoreIfNeeded(): void {
    if (!this.hasMore || this.loading || this.loadingMore) {
      return;
    }
    if (this.items.length >= this.pageSize) {
      return;
    }
    setTimeout((): void => {
      if (!this.hasMore || this.loading || this.loadingMore) {
        return;
      }
      if (this.items.length >= this.pageSize) {
        return;
      }
      this.loadMore(false);
    }, 0);
  }

  // ===== 收藏 =====

  async toggleFavorite(item: MusicListItem): Promise<void> {
    const id = item.id;
    if (id <= 0) {
      return;
    }
    const next = !item.isFavorite;
    const ok = next
      ? await MusicListApiService.addFavorite(id)
      : await MusicListApiService.removeFavorite(id);
    if (!ok) {
      return;
    }
    this.updateFavoriteState(id, next);
  }

  async toggleFavoriteSelected(): Promise<void> {
    const ids = Array.from(this.selectedItems).filter((e: number): boolean => e > 0).sort();
    if (ids.length === 0) {
      return;
    }
    const next = !this.isSelectedAllFavorited;
    const ok = await MusicListApiService.batchFavorite(ids, next);
    if (!ok) {
      ToastUtil.show(L10n.operationFailed);
      return;
    }
    for (const id of ids) {
      this.updateFavoriteState(id, next);
    }
    ToastUtil.show(L10n.t('operation_success'));
    this.exitMultiSelectMode();
  }

  updateFavoriteState(indexId: number, nextIsFavorite: boolean): void {
    const id = indexId;
    if (id <= 0) {
      return;
    }
    if (this.isFavorite && !nextIsFavorite) {
      this.items = this.items.filter((e: MusicListItem): boolean => e.id !== id);
      this.total = Math.max(0, this.total - 1);
      return;
    }
    const idx = this.items.findIndex((e: MusicListItem): boolean => e.id === id);
    if (idx < 0) {
      return;
    }
    this.items[idx].isFavorite = nextIsFavorite;
  }

  // ===== 歌单 =====

  get isInPlayList(): boolean {
    return this.listId > 0;
  }

  async addToPlayListItem(item: MusicListItem, listId: number): Promise<boolean> {
    const indexId = item.id;
    if (indexId <= 0 || listId <= 0) {
      return false;
    }
    const res = await PlayListApiService.addIndexes(listId, [indexId]);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
      return true;
    }
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    return false;
  }

  async addToPlayListSelected(listId: number): Promise<boolean> {
    const ids = Array.from(this.selectedItems).filter((e: number): boolean => e > 0).sort();
    if (ids.length === 0 || listId <= 0) {
      return false;
    }
    const res = await PlayListApiService.addIndexes(listId, ids);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
      this.exitMultiSelectMode();
      return true;
    }
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    return false;
  }

  async removeFromPlayListItem(item: MusicListItem): Promise<void> {
    const currentListId = this.listId;
    const indexId = item.id;
    if (currentListId <= 0 || indexId <= 0) {
      return;
    }
    const res = await PlayListApiService.removeIndexes(currentListId, [indexId]);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
      const before = this.items.length;
      this.items = this.items.filter((e: MusicListItem): boolean => e.id !== indexId);
      const removed = before - this.items.length;
      if (removed > 0) {
        this.total = Math.max(0, this.total - removed);
        this.autoLoadMoreIfNeeded();
      }
    } else {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    }
  }

  async removeFromPlayListSelected(): Promise<void> {
    const currentListId = this.listId;
    if (currentListId <= 0) {
      return;
    }
    const ids = Array.from(this.selectedItems).filter((e: number): boolean => e > 0).sort();
    if (ids.length === 0) {
      return;
    }
    const res = await PlayListApiService.removeIndexes(currentListId, ids);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
      const before = this.items.length;
      this.items = this.items.filter((e: MusicListItem): boolean => !ids.includes(e.id));
      const removed = before - this.items.length;
      if (removed > 0) {
        this.total = Math.max(0, this.total - removed);
      }
      this.exitMultiSelectMode();
      this.autoLoadMoreIfNeeded();
    } else {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    }
  }

  // ===== 删除（对齐 Flutter deleteItem/deleteSelected） =====

  async deleteItem(item: MusicListItem, recycle: boolean): Promise<boolean> {
    const p = this.resolveItemPath(item);
    if (p.length === 0) {
      return false;
    }
    const res = await MusicListApiService.deleteMusic([p], recycle);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return false;
    }
    if (item.id > 0) {
      this.items = this.items.filter((e: MusicListItem): boolean => e.id !== item.id);
      this.total = Math.max(0, this.total - 1);
    }
    ToastUtil.show(L10n.t('delete_success'));
    this.autoLoadMoreIfNeeded();
    return true;
  }

  async deleteSelected(recycle: boolean): Promise<boolean> {
    const selected = this.items.filter((e: MusicListItem): boolean => this.selectedItems.has(e.id));
    const pathSet = new Set<string>();
    const ids = new Set<number>();
    for (const e of selected) {
      const resolved = this.resolveItemPath(e);
      if (resolved.length === 0) {
        continue;
      }
      pathSet.add(resolved);
      if (e.id > 0) {
        ids.add(e.id);
      }
    }
    const paths = Array.from(pathSet).sort();
    if (paths.length === 0) {
      return false;
    }
    const res = await MusicListApiService.deleteMusic(paths, recycle);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return false;
    }
    if (ids.size > 0) {
      this.items = this.items.filter((e: MusicListItem): boolean => !ids.has(e.id));
      this.total = Math.max(0, this.total - ids.size);
    }
    ToastUtil.show(L10n.t('delete_success'));
    this.exitMultiSelectMode();
    this.autoLoadMoreIfNeeded();
    return true;
  }

  // ===== 下载（依赖传输模块，迁移后接入） =====

  downloadSelected(): void {
    // 下载依赖传输模块（未迁移）
    ToastUtil.show(L10n.featureComingSoon);
  }

  downloadItem(_item: MusicListItem): void {
    // 下载依赖传输模块（未迁移）
    ToastUtil.show(L10n.featureComingSoon);
  }

  private resolveItemPath(item: MusicListItem): string {
    return item.resolvePlayablePath();
  }
}
