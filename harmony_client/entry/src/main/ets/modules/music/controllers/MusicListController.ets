/**
 * 音乐歌曲列表控制器（对齐 Flutter MusicListController）：
 * - 分页加载（300/页）/ 搜索防抖 / 排序持久化（scope 前缀）
 * - 源路径筛选（持久化 selectedPaths + 与 availablePaths 调和）
 * - 多选：收藏/移除歌单/删除（回收站可选）
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { CacheKeys } from '../../../core/storage/CacheKeys';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { MusicListItem, MusicListPathItem } from '../models/MusicModels';
import { MusicListApiService, MusicListQuery, MusicListQueryFactory, PlayListApiService } from '../services/MusicApiServices';
import { pickMusicPlayListId } from '../components/MusicPlayListSelectSheet';

const TAG = 'MusicListController';

export enum MusicListSortBy {
  title = 0,
  artist = 1,
  album = 2,
  year = 3,
  duration = 4,
  ctime = 5,
  mtime = 6,
  favoriteTime = 7
}

export enum MusicListSortOrder {
  asc = 0,
  desc = 1
}

export function musicSortByParam(by: MusicListSortBy): string {
  switch (by) {
    case MusicListSortBy.title:
      return 'title';
    case MusicListSortBy.artist:
      return 'artist';
    case MusicListSortBy.album:
      return 'album';
    case MusicListSortBy.year:
      return 'year';
    case MusicListSortBy.duration:
      return 'duration';
    case MusicListSortBy.ctime:
      return 'ctime';
    case MusicListSortBy.favoriteTime:
      return 'favorite_time';
    default:
      return 'mtime';
  }
}

export function parseMusicSortBy(s: string): MusicListSortBy | undefined {
  switch (s) {
    case 'title':
      return MusicListSortBy.title;
    case 'artist':
      return MusicListSortBy.artist;
    case 'album':
      return MusicListSortBy.album;
    case 'year':
      return MusicListSortBy.year;
    case 'duration':
      return MusicListSortBy.duration;
    case 'ctime':
      return MusicListSortBy.ctime;
    case 'mtime':
      return MusicListSortBy.mtime;
    case 'favorite_time':
      return MusicListSortBy.favoriteTime;
    default:
      return undefined;
  }
}

@ObservedV2
export class MusicListController {
  readonly listType: string;
  readonly listId: number;
  readonly seriesIndexId: number;
  readonly collectionId: number;
  readonly isFavoriteList: boolean;
  readonly initialSortBy: MusicListSortBy;
  readonly initialSortOrder: MusicListSortOrder;

  @Trace items: MusicListItem[] = [];
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace autoLoadFailed: boolean = false;
  @Trace total: number = 0;
  @Trace searchText: string = '';
  @Trace isMultiSelectMode: boolean = false;
  @Trace selectedItems: Set<number> = new Set<number>();
  @Trace availablePaths: MusicListPathItem[] = [];
  @Trace selectedPaths: string[] = [];
  @Trace sortBy: MusicListSortBy = MusicListSortBy.mtime;
  @Trace sortOrder: MusicListSortOrder = MusicListSortOrder.desc;

  private page: number = 1;
  private readonly pageSize: number = 300;
  private searchDebounce: number = -1;
  private allAvailablePathsCache: MusicListPathItem[] = [];
  private restoringSelectedPaths: boolean = false;

  constructor(listType: string = '', listId: number = 0, seriesIndexId: number = 0, collectionId: number = 0,
    isFavorite: boolean = false, initialSortBy: MusicListSortBy = MusicListSortBy.mtime,
    initialSortOrder: MusicListSortOrder = MusicListSortOrder.desc) {
    this.listType = listType;
    this.listId = listId;
    this.seriesIndexId = seriesIndexId;
    this.collectionId = collectionId;
    this.isFavoriteList = isFavorite;
    this.initialSortBy = initialSortBy;
    this.initialSortOrder = initialSortOrder;
  }

  // ===== 排序持久化 =====

  private get sortCacheScope(): string {
    if (this.seriesIndexId > 0) {
      const t = this.listType.length > 0 ? this.listType : 'all';
      return `series_${t}`;
    }
    if (this.isFavoriteList) {
      return 'favorite';
    }
    if (this.listId > 0) {
      return `list_${this.listId}`;
    }
    if (this.collectionId > 0) {
      return `collection_${this.collectionId}`;
    }
    if (this.listType.length > 0) {
      return `lib_${this.listType}`;
    }
    return 'lib_all';
  }

  private get shouldUseSelectedPathsCache(): boolean {
    return this.listId <= 0 && this.collectionId <= 0 && this.seriesIndexId <= 0;
  }

  private applyInitialSortFromCache(): void {
    const store = PreferencesStore.getInstance();
    const cachedBy = parseMusicSortBy(store.getString(`${CacheKeys.MUSIC_LIST_SORT_BY}_${this.sortCacheScope}`, '') ?? '');
    const cachedOrder = store.getString(`${CacheKeys.MUSIC_LIST_SORT_ORDER}_${this.sortCacheScope}`, '');
    if (cachedBy !== undefined && (cachedOrder === 'asc' || cachedOrder === 'desc')) {
      this.sortBy = cachedBy;
      this.sortOrder = cachedOrder === 'asc' ? MusicListSortOrder.asc : MusicListSortOrder.desc;
    } else {
      this.sortBy = this.initialSortBy;
      this.sortOrder = this.initialSortOrder;
    }
  }

  private saveSortToCache(): void {
    const store = PreferencesStore.getInstance();
    store.setString(`${CacheKeys.MUSIC_LIST_SORT_BY}_${this.sortCacheScope}`, musicSortByParam(this.sortBy));
    store.setString(`${CacheKeys.MUSIC_LIST_SORT_ORDER}_${this.sortCacheScope}`,
      this.sortOrder === MusicListSortOrder.asc ? 'asc' : 'desc');
  }

  private loadSelectedPathsFromCache(): void {
    if (!this.shouldUseSelectedPathsCache) {
      return;
    }
    this.restoringSelectedPaths = true;
    const cached = PreferencesStore.getInstance().getString(CacheKeys.MUSIC_LIST_SELECTED_PATHS, '') ?? '';
    if (cached.length > 0) {
      const parts = cached.split('\n').map((e: string): string => e.trim())
        .filter((e: string): boolean => e.length > 0);
      const uniq = Array.from(new Set<string>(parts)).sort();
      this.selectedPaths = uniq;
    }
    this.restoringSelectedPaths = false;
  }

  private saveSelectedPathsToCache(): void {
    if (!this.shouldUseSelectedPathsCache) {
      return;
    }
    const uniq = Array.from(new Set<string>(this.selectedPaths.map((e: string): string => e.trim())
      .filter((e: string): boolean => e.length > 0))).sort();
    const store = PreferencesStore.getInstance();
    if (uniq.length === 0) {
      store.remove(CacheKeys.MUSIC_LIST_SELECTED_PATHS);
      return;
    }
    store.setString(CacheKeys.MUSIC_LIST_SELECTED_PATHS, uniq.join('\n'));
  }

  private reconcileSelectedPathsWithAvailablePaths(): boolean {
    if (!this.shouldUseSelectedPathsCache || this.selectedPaths.length === 0 ||
      this.availablePaths.length === 0) {
      return false;
    }
    const availableSet = new Set<string>();
    for (const e of this.availablePaths) {
      const p = e.path.trim();
      if (p.length > 0) {
        availableSet.add(p);
      }
    }
    if (availableSet.size === 0) {
      return false;
    }
    const current = this.selectedPaths.map((e: string): string => e.trim()).filter((e: string): boolean => e.length > 0);
    const next = current.filter((e: string): boolean => availableSet.has(e)).sort();
    if (next.length === current.length && current.every((e: string): boolean => availableSet.has(e))) {
      return false;
    }
    this.selectedPaths = next;
    return true;
  }

  /** onInit（对齐 Flutter onInit） */
  onInit(): void {
    this.applyInitialSortFromCache();
    this.loadSelectedPathsFromCache();
    this.refreshList(true);
  }

  onClose(): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
  }

  // ===== 多选 =====

  /** 多选模式变化回调（页面用于隐藏悬浮播放条等） */
  onMultiSelectChanged: ((v: boolean) => void) | undefined = undefined;

  private notifyMultiMode(): void {
    if (this.onMultiSelectChanged !== undefined) {
      this.onMultiSelectChanged(this.isMultiSelectMode);
    }
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
    if (!this.isMultiSelectMode && next.size > 0) {
      this.isMultiSelectMode =
        true;
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

  get isInPlayList(): boolean {
    return this.listId > 0;
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
    } else {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    }
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
      if (before !== this.items.length) {
        this.total = Math.max(0, this.total - 1);
      }
    } else {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    }
  }

  /** 加入歌单（选中项 ids，选择歌单由调用方弹出 PlayListSelectSheet 后传入） */
  async addToPlayListSelected(listId: number): Promise<boolean> {
    const ids = Array.from(this.selectedItems).filter((e: number): boolean => e > 0).sort();
    if (ids.length === 0) {
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

  // ===== 删除 =====

  // ===== 下载（依赖传输模块，迁移后接入） =====

  downloadSelected(): void {
    ToastUtil.show(L10n.featureComingSoon);
  }

  downloadItem(_item: MusicListItem): void {
    ToastUtil.show(L10n.featureComingSoon);
  }

  private resolveItemPath(item: MusicListItem): string {
    const full = item.fullPath.trim();
    const base = item.path.trim();
    const name = item.filename.trim();
    if (full.length > 0) {
      return full;
    }
    if (base.length > 0 && name.length > 0) {
      return `${base}/${name}`;
    }
    return base;
  }

  /** 删除确认：返回 recycle（true 回收站 / false 永久），取消 undefined */
  private async showDeleteConfirmDialog(paths: string[]): Promise<boolean | undefined> {
    if (paths.length === 0) {
      return undefined;
    }
    const count = paths.length;
    const content = count <= 5
      ? [L10n.t('book_delete_confirm_list'), ...paths.map((p: string): string =>
        `${L10n.t('book_delete_confirm_path_line')}${p}`)].join('\n')
      : `${L10n.t('book_delete_confirm_count')}${count}`;
    const isShellSupported = APIClient.getInstance().state.shellSupported === true;
    if (!isShellSupported) {
      const ok = await DialogUtil.showConfirmDialog(L10n.t('need_confirm'), content);
      return ok === true ? false : undefined;
    }
    const r = await DialogUtil.showConfirmThreeButtonsDialog(L10n.t('need_confirm'), content,
      undefined, undefined,
      L10n.cancel, L10n.t('put_in_recycle_bin'), L10n.t('delete_permanently'));
    if (r === undefined) {
      return undefined;
    }
    return r === 0;
  }

  async deleteSelected(): Promise<void> {
    const selected = this.items.filter((e: MusicListItem): boolean => this.selectedItems.has(e.id));
    const paths: string[] = [];
    const idSet = new Set<number>();
    for (const item of selected) {
      const p = this.resolveItemPath(item);
      if (p.length === 0) {
        continue;
      }
      paths.push(p);
      if (item.id > 0) {
        idSet.add(item.id);
      }
    }
    paths.sort();
    const recycle = await this.showDeleteConfirmDialog(paths);
    if (recycle === undefined) {
      return;
    }
    const ok = await this.deletePathsAndRemoveItems(paths, idSet, recycle);
    if (ok) {
      this.exitMultiSelectMode();
    }
  }

  async deleteItem(item: MusicListItem): Promise<void> {
    const p = this.resolveItemPath(item);
    if (p.length === 0) {
      return;
    }
    const paths = [p];
    const idSet = new Set<number>();
    if (item.id > 0) {
      idSet.add(item.id);
    }
    const recycle = await this.showDeleteConfirmDialog(paths);
    if (recycle === undefined) {
      return;
    }
    await this.deletePathsAndRemoveItems(paths, idSet, recycle);
  }

  private async deletePathsAndRemoveItems(paths: string[], removeIds: Set<number>, recycle: boolean): Promise<boolean> {
    if (paths.length === 0) {
      return false;
    }
    const res = await MusicListApiService.deleteMusic(paths, recycle);
    if (!res.success) {
      DialogUtil.showErrorDialog(res.message.length > 0 ? res.message : L10n.operationFailed, L10n.error);
      return false;
    }
    if (removeIds.size > 0) {
      this.items = this.items.filter((e: MusicListItem): boolean => !removeIds.has(e.id));
      this.total = Math.max(0, this.total - removeIds.size);
    }
    ToastUtil.show(L10n.t('delete_success'));
    return true;
  }

  // ===== 列表加载 =====

  async refreshList(showLoading: boolean = false): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.autoLoadFailed = false;
    try {
      let effectiveShowLoading = showLoading;
      let didReconcile = false;
      for (let pass = 0; pass < 2; pass++) {
        this.page = 1;
        const res = await MusicListApiService.listPaged({
          page: 1,
          pageSize: this.pageSize,
          listType: this.listType,
          listId: this.listId,
          seriesIndexId: this.seriesIndexId,
          collectionId: this.collectionId,
          isFavorite: this.isFavoriteList,
          isHistory: false,
          search: this.searchText,
          artists: [],
          albums: [],
          genres: [],
          sourceList: this.selectedPaths.slice(),
          sortBy: musicSortByParam(this.sortBy),
          sortOrder: this.sortOrder === MusicListSortOrder.asc ? 'asc' : 'desc'
        });
        if (res.success && res.data !== undefined) {
          this.items = res.data.items;
          this.total = res.data.pagination.total;
          this.hasMore = res.data.pagination.hasNextPage;
          if (this.selectedPaths.length === 0) {
            this.allAvailablePathsCache = res.data.validPaths;
            this.availablePaths = res.data.validPaths;
          } else if (this.allAvailablePathsCache.length > 0) {
            this.availablePaths = this.allAvailablePathsCache;
          } else {
            this.availablePaths = res.data.validPaths;
          }
          const changed = this.reconcileSelectedPathsWithAvailablePaths();
          if (!changed || didReconcile) {
            break;
          }
          didReconcile = true;
          effectiveShowLoading = false;
        } else {
          break;
        }
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'refreshList failed: %{public}s', JSON.stringify(e));
    } finally {
      this.loading = false;
    }
  }

  async loadMore(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMore) {
      return;
    }
    this.loadingMore = true;
    try {
      const nextPage = this.page + 1;
      const res = await MusicListApiService.listPaged({
        page: nextPage,
        pageSize: this.pageSize,
        listType: this.listType,
        listId: this.listId,
        seriesIndexId: this.seriesIndexId,
        collectionId: this.collectionId,
        isFavorite: this.isFavoriteList,
        isHistory: false,
        search: this.searchText,
        artists: [],
        albums: [],
        genres: [],
        sourceList: this.selectedPaths.slice(),
        sortBy: musicSortByParam(this.sortBy),
        sortOrder: this.sortOrder === MusicListSortOrder.asc ? 'asc' : 'desc'
      });
      if (res.success && res.data !== undefined) {
        this.page = nextPage;
        this.items = this.items.concat(res.data.items);
        this.total = res.data.pagination.total;
        this.hasMore = res.data.pagination.hasNextPage;
        this.autoLoadFailed = false;
      }
    } catch (_e) {
      this.autoLoadFailed = true;
    } finally {
      this.loadingMore = false;
    }
  }

  setSort(by: MusicListSortBy, order: MusicListSortOrder): void {
    if (this.sortBy === by && this.sortOrder === order) {
      return;
    }
    this.sortBy = by;
    this.sortOrder = order;
    this.saveSortToCache();
    this.refreshList(true);
  }

  /** 播放续传分页 query（对齐 Flutter buildPagingQuery） */
  buildPagingQuery(): MusicListQuery {
    const q = MusicListQueryFactory.default();
    q.page = Math.max(1, this.page);
    q.pageSize = this.pageSize;
    q.listType = this.listType;
    q.listId = this.listId;
    q.seriesIndexId = this.seriesIndexId;
    q.collectionId = this.collectionId;
    q.isFavorite = this.isFavoriteList;
    q.isHistory = false;
    q.search = this.searchText;
    q.sourceList = this.selectedPaths.slice();
    q.sortBy = musicSortByParam(this.sortBy);
    q.sortOrder = this.sortOrder === MusicListSortOrder.asc ? 'asc' : 'desc';
    return q;
  }

  /** 弹出歌单选择弹层，返回选中的 listId（取消/关闭返回 0） */
  async pickPlayListId(): Promise<number> {
    return await pickMusicPlayListId();
  }

  togglePath(path: string): void {
    if (this.selectedPaths.includes(path)) {
      this.selectedPaths = this.selectedPaths.filter((e: string): boolean => e !== path);
    } else {
      this.selectedPaths = this.selectedPaths.concat([path]);
    }
    this.saveSelectedPathsToCache();
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
    }, 320) as number;
  }

  clearSearch(): void {
    this.searchText = '';
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshList(false);
  }

  updateFavoriteState(indexId: number, nextIsFavorite: boolean): void {
    const id = indexId;
    if (id <= 0) {
      return;
    }
    if (this.isFavoriteList && !nextIsFavorite) {
      this.items = this.items.filter((e: MusicListItem): boolean => e.id !== id);
      this.total = Math.max(0, this.total - 1);
      return;
    }
    const i = this.items.findIndex((e: MusicListItem): boolean => e.id === id);
    if (i < 0) {
      return;
    }
    this.items[i].isFavorite = nextIsFavorite;
  }
}
