/**
 * 图书馆模块控制器（对齐 Flutter book 模块各 controller）：
 * - BookListController：分页/搜索/排序/源路径筛选/多选/收藏/删除/加书单
 * - BookHistoryController / BookCustomListController / BookCollectionController
 * - BookSourceSettingsController / BookMainController
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { CacheKeys } from '../../../core/storage/CacheKeys';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import {
  BookListItem, BookListPathItem, BookApiResult, BookCustomListItem,
  BookCollectionItem, BookSource, BookIndexCountResult
} from '../models/BookModels';
import {
  BookListApiService, BookListQuery, BookCustomListApiService,
  BookCollectionApiService, BookFavoriteApiService, BookSourceApiService
} from '../services/BookApiServices';
import { pickBookCustomListId } from '../components/BookListSelectSheet';

const TAG = 'BookControllers';

// ===== 封面缩放（全局共享，对齐 Flutter sharedCoverScale） =====

@ObservedV2
export class BookCoverScaleHolder {
  @Trace value: number = 1.0;
}

export const bookCoverScale = new BookCoverScaleHolder();
export const BOOK_COVER_SCALE_MIN = 0.9;
export const BOOK_COVER_SCALE_MAX = 1.6;
export const BOOK_COVER_SCALE_STEP = 0.1;

export function normalizeBookCoverScale(value: number): number {
  let v = value;
  if (v < BOOK_COVER_SCALE_MIN) {
    v = BOOK_COVER_SCALE_MIN;
  }
  if (v > BOOK_COVER_SCALE_MAX) {
    v = BOOK_COVER_SCALE_MAX;
  }
  return Math.round(v * 100) / 100;
}

export function ensureBookCoverScaleLoaded(): void {
  // 以字符串存取 double（对齐 Flutter CacheManager.setDouble）
  const raw = PreferencesStore.getInstance().getString(CacheKeys.BOOK_LIST_COVER_SCALE, '');
  if (raw !== undefined && raw.length > 0) {
    const parsed = Number(raw);
    if (!Number.isNaN(parsed) && Number.isFinite(parsed)) {
      bookCoverScale.value = normalizeBookCoverScale(parsed);
      return;
    }
  }
  bookCoverScale.value = 1.0;
}

function saveBookCoverScale(): void {
  bookCoverScale.value = normalizeBookCoverScale(bookCoverScale.value);
  PreferencesStore.getInstance().setString(CacheKeys.BOOK_LIST_COVER_SCALE, `${bookCoverScale.value}`);
}

// ===== 排序枚举（对齐 Flutter BookListSortBy/BookListSortOrder） =====

export enum BookListSortBy {
  viewTime = 0,
  createTime = 1,
  favoriteTime = 2,
  name = 3
}

export enum BookListSortOrder {
  asc = 0,
  desc = 1
}

export function bookSortByParam(by: BookListSortBy): string {
  switch (by) {
    case BookListSortBy.viewTime:
      return 'view_time';
    case BookListSortBy.createTime:
      return 'create_time';
    case BookListSortBy.favoriteTime:
      return 'favorite_time';
    default:
      return 'name';
  }
}

export function parseBookSortBy(s: string): BookListSortBy | undefined {
  switch (s) {
    case 'view_time':
      return BookListSortBy.viewTime;
    case 'create_time':
      return BookListSortBy.createTime;
    case 'favorite_time':
      return BookListSortBy.favoriteTime;
    case 'name':
      return BookListSortBy.name;
    default:
      return undefined;
  }
}

// ===== 图书列表控制器 =====

@ObservedV2
export class BookListController {
  readonly type: string;
  readonly isFavoriteList: boolean;
  readonly listId: number;
  readonly seriesIndexId: number;
  readonly collectionId: number;
  readonly alertWhenNoSourcePath: boolean;

  @Trace items: BookListItem[] = [];
  @Trace loading: boolean = false;
  @Trace firstLoaded: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace autoLoadFailed: boolean = false;
  @Trace total: number = 0;
  @Trace searchText: string = '';
  @Trace availablePaths: BookListPathItem[] = [];
  @Trace selectedPaths: string[] = [];
  @Trace sortBy: BookListSortBy = BookListSortBy.createTime;
  @Trace sortOrder: BookListSortOrder = BookListSortOrder.desc;
  @Trace isMultiSelectMode: boolean = false;
  @Trace selectedItems: Set<number> = new Set<number>();

  private page: number = 1;
  private readonly pageSize: number = 60;
  private searchDebounce: number = -1;
  private allAvailablePathsCache: BookListPathItem[] = [];
  private restoringSelectedPaths: boolean = false;
  private sourceEmptyDialogShown: boolean = false;

  /** 点击来源设置按钮（页面注入跳转） */
  onOpenSourceSettings: (() => void) | undefined = undefined;

  constructor(type: string = '', isFavorite: boolean = false, listId: number = 0,
    seriesIndexId: number = 0, collectionId: number = 0, alertWhenNoSourcePath: boolean = false) {
    this.type = type;
    this.isFavoriteList = isFavorite;
    this.listId = listId;
    this.seriesIndexId = seriesIndexId;
    this.collectionId = collectionId;
    this.alertWhenNoSourcePath = alertWhenNoSourcePath;
  }

  get isInCustomList(): boolean {
    return this.listId > 0;
  }

  // ===== 持久化 =====

  private get sortCacheScope(): string {
    if (this.seriesIndexId > 0) {
      const t = this.type.length > 0 ? this.type : 'book';
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
    if (this.type.length > 0) {
      return `lib_${this.type}`;
    }
    return 'lib_default';
  }

  private get shouldUseSelectedPathsCache(): boolean {
    return this.listId <= 0 && this.collectionId <= 0 && this.seriesIndexId <= 0;
  }

  private applyInitialSortFromCache(): void {
    let defBy = BookListSortBy.createTime;
    let defOrder = BookListSortOrder.desc;
    if (this.seriesIndexId > 0) {
      defBy = BookListSortBy.name;
      defOrder = BookListSortOrder.asc;
    } else if (this.isFavoriteList) {
      defBy = BookListSortBy.favoriteTime;
      defOrder = BookListSortOrder.desc;
    }
    const store = PreferencesStore.getInstance();
    const cachedBy = parseBookSortBy(store.getString(`${CacheKeys.BOOK_LIST_SORT_BY}_${this.sortCacheScope}`, '') ?? '');
    const cachedOrder = store.getString(`${CacheKeys.BOOK_LIST_SORT_ORDER}_${this.sortCacheScope}`, '');
    if (cachedBy !== undefined && (cachedOrder === 'asc' || cachedOrder === 'desc')) {
      this.sortBy = cachedBy;
      this.sortOrder = cachedOrder === 'asc' ? BookListSortOrder.asc : BookListSortOrder.desc;
    } else {
      this.sortBy = defBy;
      this.sortOrder = defOrder;
    }
  }

  private saveSortToCache(): void {
    const store = PreferencesStore.getInstance();
    store.setString(`${CacheKeys.BOOK_LIST_SORT_BY}_${this.sortCacheScope}`, bookSortByParam(this.sortBy));
    store.setString(`${CacheKeys.BOOK_LIST_SORT_ORDER}_${this.sortCacheScope}`,
      this.sortOrder === BookListSortOrder.asc ? 'asc' : 'desc');
  }

  private loadSelectedPathsFromCache(): void {
    if (!this.shouldUseSelectedPathsCache) {
      return;
    }
    this.restoringSelectedPaths = true;
    const cached = PreferencesStore.getInstance().getString(
      `${CacheKeys.BOOK_LIST_SELECTED_PATHS}_${this.sortCacheScope}`, '') ?? '';
    if (cached.length > 0) {
      const parts = cached.split('\n').map((e: string): string => e.trim())
        .filter((e: string): boolean => e.length > 0);
      const uniq = Array.from(new Set<string>(parts)).sort();
      if (uniq.length > 0) {
        this.selectedPaths = uniq;
      }
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
      store.remove(`${CacheKeys.BOOK_LIST_SELECTED_PATHS}_${this.sortCacheScope}`);
      return;
    }
    store.setString(`${CacheKeys.BOOK_LIST_SELECTED_PATHS}_${this.sortCacheScope}`, uniq.join('\n'));
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
    const current = this.selectedPaths.map((e: string): string => e.trim())
      .filter((e: string): boolean => e.length > 0);
    const next = current.filter((e: string): boolean => availableSet.has(e)).sort();
    if (next.length === current.length && current.every((e: string): boolean => availableSet.has(e))) {
      return false;
    }
    this.selectedPaths = next;
    return true;
  }

  onInit(): void {
    ensureBookCoverScaleLoaded();
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

  // ===== 查询参数 =====

  private buildQuery(page: number): BookListQuery {
    return {
      page: page,
      pageSize: this.pageSize,
      type: this.type,
      listId: this.listId,
      seriesIndexId: this.seriesIndexId,
      collectionId: this.collectionId,
      isFavorite: this.isFavoriteList,
      search: this.searchText.trim(),
      sourceList: this.selectedPaths.length > 0 ? this.selectedPaths.slice() : undefined,
      sortBy: bookSortByParam(this.sortBy),
      sortOrder: this.sortOrder === BookListSortOrder.asc ? 'asc' : 'desc'
    };
  }

  // ===== 列表加载 =====

  private autoLoadMoreIfNeeded(): void {
    if (!this.hasMore || this.loading || this.loadingMore) {
      return;
    }
    if (this.items.length >= this.pageSize) {
      return;
    }
    setTimeout((): void => {
      if (!this.hasMore || this.loading || this.loadingMore || this.items.length >= this.pageSize) {
        return;
      }
      this.loadMore();
    }, 50);
  }

  async refreshList(showLoading: boolean = false): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.autoLoadFailed = false;
    try {
      let didReconcile = false;
      for (let pass = 0; pass < 2; pass++) {
        this.page = 1;
        const res = await BookListApiService.listPaged(this.buildQuery(1));
        if (!res.success || res.data === undefined) {
          this.autoLoadFailed = true;
          return;
        }
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
      }
      this.maybeAlertNoSourcePath();
    } finally {
      this.loading = false;
      this.firstLoaded = true;
    }
  }

  private maybeAlertNoSourcePath(): void {
    if (this.selectedPaths.length > 0 || this.availablePaths.length > 0) {
      this.sourceEmptyDialogShown = false;
      return;
    }
    if (!this.alertWhenNoSourcePath || this.sourceEmptyDialogShown) {
      return;
    }
    if (!CurrentUserStore.getInstance().isAdmin) {
      return;
    }
    this.sourceEmptyDialogShown = true;
    DialogUtil.showInfoDialog(L10n.t('tip'), L10n.t('path_no_set'), L10n.ok, (): void => {
      if (this.onOpenSourceSettings !== undefined) {
        this.onOpenSourceSettings();
      }
    });
  }

  async loadMore(fromAuto: boolean = false): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMore) {
      return;
    }
    if (fromAuto && this.autoLoadFailed) {
      return;
    }
    this.loadingMore = true;
    try {
      const nextPage = this.page + 1;
      const res = await BookListApiService.listPaged(this.buildQuery(nextPage));
      if (!res.success || res.data === undefined) {
        this.autoLoadFailed = true;
        return;
      }
      this.page = nextPage;
      this.items = this.items.concat(res.data.items);
      this.total = res.data.pagination.total;
      this.hasMore = res.data.pagination.hasNextPage;
      this.autoLoadFailed = false;
    } catch (e) {
      this.autoLoadFailed = true;
      hilog.error(0x0000, TAG, 'loadMore failed: %{public}s', JSON.stringify(e));
    } finally {
      this.loadingMore = false;
    }
  }

  setSearchText(v: string): void {
    this.searchText = v;
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout((): void => {
      this.searchDebounce = -1;
      this.refreshList(false);
    }, 350) as number;
  }

  clearSearch(): void {
    if (this.searchText.length === 0) {
      return;
    }
    this.searchText = '';
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshList(true);
  }

  setSort(by: BookListSortBy, order: BookListSortOrder): void {
    if (this.sortBy === by && this.sortOrder === order) {
      return;
    }
    this.sortBy = by;
    this.sortOrder = order;
    this.saveSortToCache();
    this.refreshList(true);
  }

  toggleSortOrder(): void {
    this.sortOrder = this.sortOrder === BookListSortOrder.asc
      ? BookListSortOrder.desc
      : BookListSortOrder.asc;
    this.saveSortToCache();
    this.refreshList(true);
  }

  // ===== 源路径 =====

  resetSelectedPaths(): void {
    this.selectedPaths = [];
    this.saveSelectedPathsToCache();
    this.refreshList(false);
  }

  togglePath(path: string): void {
    if (this.selectedPaths.includes(path)) {
      this.selectedPaths = this.selectedPaths.filter((e: string): boolean => e !== path);
    } else {
      this.selectedPaths = this.selectedPaths.concat([path]);
    }
    this.saveSelectedPathsToCache();
    this.refreshList(false);
  }

  // ===== 封面缩放 =====

  increaseCoverScale(): void {
    bookCoverScale.value = normalizeBookCoverScale(bookCoverScale.value + BOOK_COVER_SCALE_STEP);
    saveBookCoverScale();
  }

  decreaseCoverScale(): void {
    bookCoverScale.value = normalizeBookCoverScale(bookCoverScale.value - BOOK_COVER_SCALE_STEP);
    saveBookCoverScale();
  }

  // ===== 多选 =====

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
    }
  }

  get isAllCurrentSelected(): boolean {
    const ids = this.items.map((e: BookListItem): number => e.id).filter((e: number): boolean => e > 0);
    if (ids.length === 0) {
      return false;
    }
    return ids.every((e: number): boolean => this.selectedItems.has(e));
  }

  toggleSelectAllCurrent(): void {
    const ids = this.items.map((e: BookListItem): number => e.id).filter((e: number): boolean => e > 0);
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
      this.isMultiSelectMode = true;
    }
  }

  exitMultiSelectMode(): void {
    this.isMultiSelectMode = false;
    this.selectedItems = new Set<number>();
  }

  get isSelectedAllFavorited(): boolean {
    const selected = this.items.filter((e: BookListItem): boolean => this.selectedItems.has(e.id));
    if (selected.length === 0) {
      return false;
    }
    return selected.every((e: BookListItem): boolean => e.isFavorite);
  }

  async toggleFavoriteSelected(): Promise<void> {
    const ids = Array.from(this.selectedItems).filter((e: number): boolean => e > 0).sort();
    if (ids.length === 0) {
      return;
    }
    const next = !this.isSelectedAllFavorited;
    const ok = await BookFavoriteApiService.batchFavorite(ids, next);
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

  async favoriteSelected(): Promise<void> {
    if (this.isFavoriteList) {
      return;
    }
    const ids = Array.from(this.selectedItems).filter((e: number): boolean => e > 0).sort();
    if (ids.length === 0) {
      return;
    }
    const ok = await BookFavoriteApiService.batchFavorite(ids, true);
    if (!ok) {
      ToastUtil.show(L10n.operationFailed);
      return;
    }
    for (const id of ids) {
      this.updateFavoriteState(id, true);
    }
    ToastUtil.show(L10n.t('operation_success'));
    this.exitMultiSelectMode();
  }

  async unfavoriteSelected(): Promise<void> {
    if (!this.isFavoriteList) {
      return;
    }
    const ids = Array.from(this.selectedItems).filter((e: number): boolean => e > 0).sort();
    if (ids.length === 0) {
      return;
    }
    const ok = await BookFavoriteApiService.batchFavorite(ids, false);
    if (!ok) {
      ToastUtil.show(L10n.operationFailed);
      return;
    }
    for (const id of ids) {
      this.updateFavoriteState(id, false);
    }
    ToastUtil.show(L10n.t('operation_success'));
    this.exitMultiSelectMode();
  }

  updateFavoriteState(indexId: number, nextIsFavorite: boolean): void {
    const id = indexId;
    if (id <= 0) {
      return;
    }
    if (this.isFavoriteList && !nextIsFavorite) {
      this.items = this.items.filter((e: BookListItem): boolean => e.id !== id);
      this.total = Math.max(0, this.total - 1);
      return;
    }
    const i = this.items.findIndex((e: BookListItem): boolean => e.id === id);
    if (i < 0) {
      return;
    }
    this.items[i].isFavorite = nextIsFavorite;
  }

  // ===== 书单 =====

  async addToBookListSelected(): Promise<void> {
    const ids = Array.from(this.selectedItems).filter((e: number): boolean => e > 0).sort();
    if (ids.length === 0) {
      return;
    }
    try {
      const listId = await pickBookCustomListId();
      if (listId <= 0) {
        return;
      }
      const res = await BookCustomListApiService.addIndexes(listId, ids);
      if (res.success) {
        ToastUtil.show(L10n.t('operation_success'));
        this.exitMultiSelectMode();
      } else {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      }
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    }
  }

  async addToBookListItem(item: BookListItem): Promise<void> {
    this.selectedItems = new Set<number>([item.id]);
    await this.addToBookListSelected();
  }

  async removeFromBookListSelected(): Promise<void> {
    if (!this.isInCustomList) {
      return;
    }
    const ids = Array.from(this.selectedItems).filter((e: number): boolean => e > 0).sort();
    if (ids.length === 0) {
      return;
    }
    const res = await BookCustomListApiService.removeIndexes(this.listId, ids);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
      const before = this.items.length;
      this.items = this.items.filter((e: BookListItem): boolean => !ids.includes(e.id));
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

  async removeFromBookListItem(item: BookListItem): Promise<void> {
    if (!this.isInCustomList || item.id <= 0) {
      return;
    }
    const res = await BookCustomListApiService.removeIndexes(this.listId, [item.id]);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
      const before = this.items.length;
      this.items = this.items.filter((e: BookListItem): boolean => e.id !== item.id);
      if (before !== this.items.length) {
        this.total = Math.max(0, this.total - 1);
      }
      this.autoLoadMoreIfNeeded();
    } else {
      ToastUtil.show(L10n.operationFailed);
    }
  }

  // ===== 删除 =====

  private resolveItemPath(item: BookListItem): string {
    return item.fullPath.trim();
  }

  private static deleteConfirmContent(paths: string[], count: number): string {
    if (count > 5) {
      const params = new Map<string, string>();
      params.set('count', `${count}`);
      return L10n.t('book_delete_confirm_count', '', params);
    }
    const lines: string[] = [L10n.t('book_delete_confirm_list')];
    for (const p of paths) {
      const params = new Map<string, string>();
      params.set('path', p);
      lines.push(L10n.t('book_delete_confirm_path_line', '', params));
    }
    return lines.join('\n');
  }

  private async showDeleteConfirmDialog(paths: string[]): Promise<boolean | undefined> {
    if (paths.length === 0) {
      return undefined;
    }
    const count = paths.length;
    const content = BookListController.deleteConfirmContent(paths, count);
    const isShellSupported = APIClient.getInstance().state.shellSupported === true;
    if (!isShellSupported) {
      const ok = await DialogUtil.showConfirmDialog(L10n.t('need_confirm'), content);
      return ok === true ? false : undefined;
    }
    const r = await DialogUtil.showConfirmThreeButtonsDialog(L10n.t('need_confirm'), content,
      undefined, undefined,
      L10n.cancel, L10n.t('put_in_recycle_bin'), L10n.t('delete'));
    if (r === undefined) {
      return undefined;
    }
    return r === 0;
  }

  private async deletePathsAndRemoveItems(paths: string[], removeIds: Set<number>, recycle: boolean): Promise<boolean> {
    if (paths.length === 0) {
      return false;
    }
    const res = await BookListApiService.deleteEntries(paths, recycle);
    if (!res.success) {
      DialogUtil.showErrorDialog(res.message.length > 0 ? res.message : L10n.operationFailed, L10n.error);
      return false;
    }
    if (removeIds.size > 0) {
      this.items = this.items.filter((e: BookListItem): boolean => !removeIds.has(e.id));
      this.total = Math.max(0, this.total - removeIds.size);
    }
    ToastUtil.show(L10n.t('delete_success'));
    this.autoLoadMoreIfNeeded();
    return true;
  }

  async deleteItem(item: BookListItem): Promise<void> {
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

  async deleteSelected(): Promise<void> {
    const selected = this.items.filter((e: BookListItem): boolean => this.selectedItems.has(e.id));
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

  // ===== 下载（依赖传输模块，迁移后接入） =====

  downloadSelected(): void {
    ToastUtil.show(L10n.featureComingSoon);
  }

  downloadItem(_item: BookListItem): void {
    ToastUtil.show(L10n.featureComingSoon);
  }
}

// ===== 阅读历史控制器 =====

@ObservedV2
export class BookHistoryController {
  @Trace items: BookListItem[] = [];
  @Trace loading: boolean = false;
  @Trace firstLoaded: boolean = false;

  onInit(): void {
    this.refreshHistory(true);
  }

  async refreshHistory(showLoading: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      const res = await BookListApiService.listHistory();
      this.items = res.items;
      this.firstLoaded = true;
    } finally {
      this.loading = false;
    }
  }

  async clearHistory(): Promise<void> {
    const confirmed = await DialogUtil.showConfirmDialog(L10n.t('need_confirm'), L10n.t('book_history_clear_confirm'));
    if (confirmed !== true) {
      return;
    }
    this.loading = true;
    try {
      await BookListApiService.clearHistory(true);
      this.items = [];
      ToastUtil.show(L10n.t('operation_success'));
    } finally {
      this.loading = false;
    }
  }
}

// ===== 自建书单控制器 =====

@ObservedV2
export class BookCustomListController {
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace items: BookCustomListItem[] = [];
  @Trace page: number = 1;
  @Trace pageSize: number = 30;
  @Trace total: number = 0;
  @Trace keyword: string = '';
  @Trace sortBy: string = 'create_time';
  @Trace sortOrder: string = 'desc';

  private searchDebounce: number = -1;

  onInit(): void {
    this.loadSortSettings();
    this.refreshLists();
  }

  onClose(): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
  }

  onSearchChanged(v: string): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout((): void => {
      this.searchDebounce = -1;
      this.keyword = v.trim();
      this.refreshLists();
    }, 450) as number;
  }

  clearSearch(): void {
    this.keyword = '';
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshLists();
  }

  setSort(field: string, order: string): void {
    const nextField = field === 'name' || field === 'create_time' ? field : 'create_time';
    const nextOrder = order === 'asc' ? 'asc' : 'desc';
    if (this.sortBy === nextField && this.sortOrder === nextOrder) {
      return;
    }
    this.sortBy = nextField;
    this.sortOrder = nextOrder;
    this.saveSortSettings();
    this.refreshLists();
  }

  private loadSortSettings(): void {
    const store = PreferencesStore.getInstance();
    const cachedField = store.getString(CacheKeys.BOOK_CUSTOM_LIST_SORT_FIELD, '') ?? '';
    const cachedOrder = store.getString(CacheKeys.BOOK_CUSTOM_LIST_SORT_ORDER, '') ?? '';
    if (cachedField === 'name' || cachedField === 'create_time') {
      this.sortBy = cachedField;
    }
    if (cachedOrder === 'asc' || cachedOrder === 'desc') {
      this.sortOrder = cachedOrder;
    }
  }

  private saveSortSettings(): void {
    const store = PreferencesStore.getInstance();
    store.setString(CacheKeys.BOOK_CUSTOM_LIST_SORT_FIELD, this.sortBy);
    store.setString(CacheKeys.BOOK_CUSTOM_LIST_SORT_ORDER, this.sortOrder);
  }

  async refreshLists(): Promise<void> {
    this.hasMore = true;
    await this.loadLists(1, false);
  }

  async loadLists(pageNumber: number, append: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await BookCustomListApiService.listLists(pageNumber, this.pageSize,
        this.keyword, this.sortBy, this.sortOrder);
      if (!res.success || res.data === undefined) {
        return;
      }
      const data = res.data;
      if (append) {
        const existingIds = new Set<number>();
        for (const e of this.items) {
          existingIds.add(e.id);
        }
        const next = data.items.filter((e: BookCustomListItem): boolean => !existingIds.has(e.id));
        this.items = this.items.concat(next);
      } else {
        this.items = data.items;
      }
      this.total = data.pagination.total;
      this.page = data.pagination.page;
      this.pageSize = data.pagination.pageSize;
      this.hasMore = data.pagination.hasNextPage;
    } finally {
      this.isLoading = false;
    }
  }

  async loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return;
    }
    await this.loadLists(this.page + 1, true);
  }

  async createList(name: string): Promise<boolean> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return false;
    }
    const res = await BookCustomListApiService.createList(trimmed);
    if (!res.success) {
      return false;
    }
    await this.refreshLists();
    return true;
  }

  /** 创建书单并返回新建项（选择模式空列表时创建后直接选用） */
  async createListReturnItem(name: string): Promise<BookCustomListItem | undefined> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return undefined;
    }
    const res = await BookCustomListApiService.createList(trimmed);
    if (!res.success || res.data === undefined) {
      return undefined;
    }
    const item = res.data;
    if (item.id <= 0) {
      return undefined;
    }
    await this.refreshLists();
    return item;
  }

  async updateList(id: number, name: string): Promise<boolean> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return false;
    }
    const res = await BookCustomListApiService.updateList(id, trimmed);
    if (!res.success) {
      return false;
    }
    await this.refreshLists();
    return true;
  }

  async deleteList(id: number): Promise<boolean> {
    const res = await BookCustomListApiService.deleteList(id);
    if (!res.success) {
      return false;
    }
    await this.refreshLists();
    return true;
  }
}

// ===== 合集控制器 =====

@ObservedV2
export class BookCollectionController {
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace items: BookCollectionItem[] = [];
  @Trace page: number = 1;
  @Trace pageSize: number = 20;
  @Trace total: number = 0;
  @Trace keyword: string = '';
  @Trace sortField: string = 'create_time';
  @Trace sortOrder: string = 'desc';

  private searchDebounce: number = -1;

  onInit(): void {
    this.loadSortSettings();
    this.refreshCollections();
  }

  onClose(): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
  }

  onSearchChanged(val: string): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout((): void => {
      this.searchDebounce = -1;
      this.keyword = val.trim();
      this.refreshCollections();
    }, 500) as number;
  }

  clearSearch(): void {
    this.keyword = '';
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshCollections();
  }

  setSort(field: string, order: string): void {
    if (this.sortField === field && this.sortOrder === order) {
      return;
    }
    this.sortField = field;
    this.sortOrder = order;
    this.saveSortSettings();
    this.refreshCollections();
  }

  private loadSortSettings(): void {
    const store = PreferencesStore.getInstance();
    const cachedField = store.getString(CacheKeys.BOOK_COLLECTION_SORT_FIELD, '') ?? '';
    const cachedOrder = store.getString(CacheKeys.BOOK_COLLECTION_SORT_ORDER, '') ?? '';
    if (cachedField === 'name' || cachedField === 'create_time') {
      this.sortField = cachedField;
    }
    if (cachedOrder === 'asc' || cachedOrder === 'desc') {
      this.sortOrder = cachedOrder;
    }
  }

  private saveSortSettings(): void {
    const store = PreferencesStore.getInstance();
    store.setString(CacheKeys.BOOK_COLLECTION_SORT_FIELD, this.sortField);
    store.setString(CacheKeys.BOOK_COLLECTION_SORT_ORDER, this.sortOrder);
  }

  async refreshCollections(): Promise<void> {
    this.hasMore = true;
    await this.loadCollections(1, false);
  }

  async loadCollections(pageNumber: number, append: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await BookCollectionApiService.listCollections(pageNumber, this.pageSize,
        this.keyword, this.sortField, this.sortOrder);
      if (!res.success || res.data === undefined) {
        return;
      }
      const data = res.data;
      if (append) {
        const existingIds = new Set<number>();
        for (const e of this.items) {
          existingIds.add(e.id);
        }
        const next = data.items.filter((e: BookCollectionItem): boolean => !existingIds.has(e.id));
        this.items = this.items.concat(next);
      } else {
        this.items = data.items;
      }
      this.total = data.total;
      this.page = data.page;
      this.pageSize = data.pageSize;
      const size = this.pageSize <= 0 ? 20 : this.pageSize;
      const maxPage = this.total <= 0 ? 1 : Math.floor((this.total + size - 1) / size);
      this.hasMore = this.page < maxPage;
    } finally {
      this.isLoading = false;
    }
  }

  async loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return;
    }
    await this.loadCollections(this.page + 1, true);
  }

  async createCollection(name: string, pathList: string[]): Promise<boolean> {
    const trimmed = name.trim();
    const cleanedPaths = pathList.map((e: string): string => e.trim())
      .filter((e: string): boolean => e.length > 0);
    if (trimmed.length === 0 || cleanedPaths.length === 0) {
      return false;
    }
    const res = await BookCollectionApiService.createCollection(trimmed, cleanedPaths);
    if (res.success) {
      await this.refreshCollections();
      return true;
    }
    if (res.message.length > 0) {
      DialogUtil.showInfoDialog(L10n.t('tip'), res.message);
    }
    return false;
  }

  async updateCollection(id: number, name: string, pathList: string[]): Promise<boolean> {
    const trimmed = name.trim();
    const cleanedPaths = pathList.map((e: string): string => e.trim())
      .filter((e: string): boolean => e.length > 0);
    if (trimmed.length === 0 || cleanedPaths.length === 0) {
      return false;
    }
    const res = await BookCollectionApiService.updateCollection(id, trimmed, cleanedPaths);
    if (res.success) {
      await this.refreshCollections();
      return true;
    }
    if (res.message.length > 0) {
      DialogUtil.showInfoDialog(L10n.t('tip'), res.message);
    }
    return false;
  }

  async deleteCollection(id: number): Promise<boolean> {
    const res = await BookCollectionApiService.deleteCollection(id);
    if (!res.success) {
      if (res.message.length > 0) {
        DialogUtil.showInfoDialog(L10n.t('tip'), res.message);
      }
      return false;
    }
    await this.refreshCollections();
    return true;
  }
}

// ===== 来源路径设置控制器 =====

@ObservedV2
export class BookSourceSettingsController {
  @Trace sources: BookSource[] = [];
  @Trace loadingSources: boolean = false;
  @Trace scanning: boolean = false;

  onInit(): void {
    this.fetchSources();
  }

  getIntervalHours(source: BookSource): number {
    const ms = source.scanIntervalMs;
    if (ms <= 0) {
      return 2;
    }
    let hours = Math.round(ms / (3600 * 1000));
    if (hours < 1) {
      hours = 1;
    }
    if (hours > 24) {
      hours = 24;
    }
    return hours;
  }

  getIntervalEnabled(source: BookSource): boolean {
    return source.scanInterval === 1 || source.scanIntervalMs > 0;
  }

  async fetchSources(): Promise<void> {
    if (this.loadingSources) {
      return;
    }
    this.loadingSources = true;
    try {
      const list = await BookSourceApiService.listSources();
      this.sources = list;
    } finally {
      this.loadingSources = false;
    }
  }

  async addSources(paths: string[]): Promise<boolean> {
    const uniq = Array.from(new Set<string>(paths.map((e: string): string => e.trim())
      .filter((e: string): boolean => e.length > 0)));
    if (uniq.length === 0) {
      return false;
    }
    await DialogUtil.showLoading(L10n.t('loading'));
    try {
      for (const p of uniq) {
        const res = await BookSourceApiService.addSource(p);
        if (!res.success) {
          await DialogUtil.dismissLoading();
          ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
          return false;
        }
      }
      await this.fetchSources();
      ToastUtil.show(L10n.t('operation_success'));
      return true;
    } finally {
      await DialogUtil.dismissLoading();
    }
  }

  async updateSourceOptimistic(source: BookSource, scanWhenStart?: number, scanWhenChange?: number,
    scanInterval?: number, scanIntervalMs?: number, showType?: string): Promise<void> {
    const idx = this.sources.findIndex((e: BookSource): boolean => e.id === source.id);
    if (idx < 0) {
      return;
    }
    const prev = this.sources[idx];
    const next = BookSourceSettingsController.copyWith(prev, scanWhenStart, scanWhenChange,
      scanInterval, scanIntervalMs, showType);
    const nextList = this.sources.slice();
    nextList[idx] = next;
    this.sources = nextList;

    const payload: Record<string, Object> = {};
    if (scanWhenStart !== undefined) {
      payload['scan_when_start'] = scanWhenStart;
    }
    if (scanWhenChange !== undefined) {
      payload['scan_when_change'] = scanWhenChange;
    }
    if (scanInterval !== undefined) {
      payload['scan_interval'] = scanInterval;
    }
    if (scanIntervalMs !== undefined) {
      payload['scan_interval_ms'] = scanIntervalMs;
    }
    if (showType !== undefined) {
      payload['show_type'] = showType;
    }

    const res = await BookSourceApiService.updateSource(source.id, payload);
    if (!res.success) {
      const rollback = this.sources.slice();
      rollback[idx] = prev;
      this.sources = rollback;
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    if (res.data !== undefined) {
      const updated = BookSource.fromJson(res.data);
      const cur = this.sources.slice();
      cur[idx] = updated;
      this.sources = cur;
    }
  }

  private static copyWith(src: BookSource, scanWhenStart?: number, scanWhenChange?: number,
    scanInterval?: number, scanIntervalMs?: number, showType?: string): BookSource {
    const r = new BookSource();
    r.id = src.id;
    r.path = src.path;
    r.exists = src.exists;
    r.scanWhenStart = scanWhenStart !== undefined ? scanWhenStart : src.scanWhenStart;
    r.scanWhenChange = scanWhenChange !== undefined ? scanWhenChange : src.scanWhenChange;
    r.isShow = src.isShow;
    r.ctime = src.ctime;
    r.scanInterval = scanInterval !== undefined ? scanInterval : src.scanInterval;
    r.scanIntervalMs = scanIntervalMs !== undefined ? scanIntervalMs : src.scanIntervalMs;
    r.scanIntervalConfig = src.scanIntervalConfig;
    r.lastScanTime = src.lastScanTime;
    r.showType = showType !== undefined ? showType : src.showType;
    return r;
  }

  async relocateSource(source: BookSource, newPath: string): Promise<void> {
    await DialogUtil.showLoading(L10n.t('loading'));
    try {
      const res = await BookSourceApiService.relocateSource(source.id, newPath);
      if (!res.success) {
        await DialogUtil.dismissLoading();
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      await this.fetchSources();
      await DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success'));
    } catch (_e) {
      await DialogUtil.dismissLoading();
      ToastUtil.show(L10n.operationFailed);
    }
  }

  async deleteSourceOptimistic(source: BookSource): Promise<void> {
    const idx = this.sources.findIndex((e: BookSource): boolean => e.id === source.id);
    if (idx < 0) {
      return;
    }
    const removed = this.sources[idx];
    this.sources = this.sources.filter((e: BookSource): boolean => e.id !== source.id);

    await DialogUtil.showLoading(L10n.t('loading'));
    try {
      const res = await BookSourceApiService.deleteSource(source.id);
      if (!res.success) {
        const cur = this.sources.slice();
        cur.splice(idx, 0, removed);
        this.sources = cur;
        await DialogUtil.dismissLoading();
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      await DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success'));
    } catch (_e) {
      const cur = this.sources.slice();
      cur.splice(idx, 0, removed);
      this.sources = cur;
      await DialogUtil.dismissLoading();
      ToastUtil.show(L10n.operationFailed);
    }
  }

  async scanSource(path: string): Promise<void> {
    const p = path.trim();
    if (p.length === 0 || this.scanning) {
      return;
    }
    this.scanning = true;
    await DialogUtil.showLoading(L10n.t('loading'));
    try {
      const res = await BookSourceApiService.scanSource(p);
      if (!res.success) {
        await DialogUtil.dismissLoading();
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      await DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success'));
      await this.fetchSources();
    } catch (_e) {
      await DialogUtil.dismissLoading();
      ToastUtil.show(L10n.operationFailed);
    } finally {
      this.scanning = false;
    }
  }
}

// ===== 主框架控制器 =====

@ObservedV2
export class BookMainController {
  @Trace currentPageKey: string = 'library.book';
  @Trace bookCount: number = 0;
  @Trace comicCount: number = 0;

  onInit(): void {
    this.fetchIndexCounts();
  }

  async fetchIndexCounts(): Promise<void> {
    const res: BookApiResult<BookIndexCountResult> = await BookListApiService.getIndexCounts();
    if (res.success && res.data !== undefined) {
      this.bookCount = res.data.book;
      this.comicCount = res.data.comic;
    }
  }
}
