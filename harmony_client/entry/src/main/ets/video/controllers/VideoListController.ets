import { L10n } from '../../core/localization/L10n';
import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { AppEventBus } from '../../common/AppEventBus';
import { VideoHomeItemBean, VideoListPathItem, parseVideoHomeItemBean } from '../models/VideoModels';
import { VideoListApiService } from '../service/VideoApiServices';
import { VideoItemSyncService } from '../utils/VideoItemUtils';

/**
 * 视频列表控制器（对齐 Flutter video_list_controller.dart）：
 * 分页加载 / 搜索防抖 / 筛选 / 排序持久化 / 来源路径筛选 / 海报缩放。
 */

/** 排序字段（对齐 VideoListSortBy） */
export type VideoListSortBy = 'favorite_time' | 'view_time' | 'year' | 'score'
  | 'create_time' | 'name';
/** 排序方向 */
export type VideoListSortOrder = 'asc' | 'desc';

export class VideoListYearGroup {
  label: string = '';
  years: number[] = [];
  single: boolean = false;
}

const KEY_SORT_BY = 'video_list_sort_by';
const KEY_SORT_ORDER = 'video_list_sort_order';
const KEY_POSTER_SCALE = 'video_list_poster_scale';
const KEY_SOURCE_PREFIX = 'video_list_selected_source_paths';

/** 海报缩放范围（移动端对齐 DeviceUtils.isMobile） */
export const POSTER_SCALE_MIN: number = 0.9;
export const POSTER_SCALE_MAX: number = 1.6;
export const POSTER_SCALE_STEP: number = 0.1;

function normalizePosterScale(value: number): number {
  const clamped = Math.min(Math.max(value, POSTER_SCALE_MIN), POSTER_SCALE_MAX);
  return Math.round(clamped * 100) / 100;
}

function normalizePaths(paths: string[]): string[] {
  const out: string[] = [];
  for (const raw of paths) {
    const p = raw.trim();
    if (p.length > 0 && !out.includes(p)) {
      out.push(p);
    }
  }
  return out;
}

@ObservedV2
export class VideoListController {
  /** 共享海报缩放（全局记忆，对齐 sharedPosterScale） */
  static sharedPosterScale: number = 1.0;
  private static posterScaleLoaded: boolean = false;

  static ensureSharedPosterScaleLoaded(): void {
    if (VideoListController.posterScaleLoaded) {
      return;
    }
    try {
      const raw = PreferencesStore.getInstance().getString(KEY_POSTER_SCALE);
      const parsed = raw !== undefined ? Number(raw) : 1.0;
      VideoListController.sharedPosterScale = normalizePosterScale(
        Number.isFinite(parsed) && parsed > 0 ? parsed : 1.0);
    } catch (_e) {
      VideoListController.sharedPosterScale = 1.0;
    }
    VideoListController.posterScaleLoaded = true;
  }

  static saveSharedPosterScale(value: number): void {
    VideoListController.sharedPosterScale = normalizePosterScale(value);
    try {
      PreferencesStore.getInstance().setString(KEY_POSTER_SCALE,
        `${VideoListController.sharedPosterScale}`);
    } catch (_e) {
    }
  }

  // ===== 构造参数（对齐 Flutter 构造函数） =====
  initialMediaType: string = '';
  listType: string = '';
  albumId: number = 0;
  collectionId: number = 0;
  smartAlbumId: number = 0;
  initialGenres: string[] = [];
  initialRegions: string[] = [];
  initialActors: string[] = [];
  initialDirectors: string[] = [];

  // ===== 列表状态 =====
  @Trace items: VideoHomeItemBean[] = [];
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace autoLoadFailed: boolean = false;
  @Trace total: number = 0;

  @Trace mediaType: string = '';
  @Trace searchText: string = '';
  @Trace genres: string[] = [];
  @Trace regions: string[] = [];
  @Trace actors: string[] = [];
  @Trace directors: string[] = [];
  @Trace selectedYears: number[] = [];

  @Trace availableGenres: string[] = [];
  @Trace availableRegions: string[] = [];
  @Trace availableYears: number[] = [];
  @Trace baseAvailableYears: number[] = [];

  @Trace availablePaths: VideoListPathItem[] = [];
  @Trace selectedPaths: string[] = [];

  @Trace sortBy: VideoListSortBy = 'view_time';
  @Trace sortOrder: VideoListSortOrder = 'desc';
  @Trace posterScale: number = 1.0;

  private page: number = 1;
  private readonly pageSize: number = 30;
  private searchDebounceId: number = -1;
  private deletedListener: ((data: string) => void) | undefined = undefined;
  private inited: boolean = false;

  get isFavoriteList(): boolean {
    return this.listType.trim().toLowerCase() === 'favorite';
  }

  get isAlbumList(): boolean {
    return this.albumId > 0;
  }

  get hasActiveFilters(): boolean {
    return this.genres.length > 0 || this.regions.length > 0
      || this.actors.length > 0 || this.directors.length > 0
      || this.selectedYears.length > 0;
  }

  get hasCustomSort(): boolean {
    const defaultBy: VideoListSortBy = this.isFavoriteList ? 'favorite_time' : 'create_time';
    return this.sortBy !== defaultBy || this.sortOrder !== 'desc';
  }

  configure(initialMediaType: string, listType: string, albumId: number,
    collectionId: number, smartAlbumId: number, initialGenres: string[],
    initialRegions: string[], initialActors: string[], initialDirectors: string[]): void {
    this.initialMediaType = initialMediaType;
    this.listType = listType;
    this.albumId = albumId;
    this.collectionId = collectionId;
    this.smartAlbumId = smartAlbumId;
    this.initialGenres = initialGenres;
    this.initialRegions = initialRegions;
    this.initialActors = initialActors;
    this.initialDirectors = initialDirectors;
  }

  /** 初始化（对齐 onInit；幂等，供页面 aboutToAppear 调用） */
  init(): void {
    if (this.inited) {
      return;
    }
    this.inited = true;
    this.mediaType = this.initialMediaType;
    if (this.isFavoriteList) {
      this.sortBy = 'favorite_time';
      this.sortOrder = 'desc';
    }
    this.loadSortSettings();
    VideoListController.ensureSharedPosterScaleLoaded();
    this.posterScale = VideoListController.sharedPosterScale;
    this.genres = this.initialGenres.map((e: string) => e.trim()).filter((e: string) => e.length > 0);
    this.regions = this.initialRegions.map((e: string) => e.trim()).filter((e: string) => e.length > 0);
    this.actors = this.initialActors.map((e: string) => e.trim()).filter((e: string) => e.length > 0);
    this.directors = this.initialDirectors.map((e: string) => e.trim()).filter((e: string) => e.length > 0);
    this.deletedListener = (data: string): void => {
      this.handleExternalDelete(Number(data));
    };
    AppEventBus.on(VideoItemSyncService.EVENT_VIDEO_ITEM_DELETED, this.deletedListener);
    void this.refreshList(true);
  }

  dispose(): void {
    if (this.deletedListener !== undefined) {
      AppEventBus.off(VideoItemSyncService.EVENT_VIDEO_ITEM_DELETED, this.deletedListener);
      this.deletedListener = undefined;
    }
    if (this.searchDebounceId >= 0) {
      clearTimeout(this.searchDebounceId);
      this.searchDebounceId = -1;
    }
  }

  private handleExternalDelete(indexId: number): void {
    if (indexId <= 0) {
      return;
    }
    const before = this.items.length;
    this.items = this.items.filter((e: VideoHomeItemBean) => e.id !== indexId);
    const removed = before - this.items.length;
    if (removed > 0) {
      this.total = Math.max(this.total - removed, 0);
    }
  }

  /** 排序持久化后缀（仅按 listType 区分） */
  private sortSuffix(): string {
    const t = this.listType.trim();
    return t.length > 0 ? t : 'default';
  }

  private loadSortSettings(): void {
    try {
      const suf = this.sortSuffix();
      const byStr = PreferencesStore.getInstance().getString(`${KEY_SORT_BY}_${suf}`);
      const orderStr = PreferencesStore.getInstance().getString(`${KEY_SORT_ORDER}_${suf}`);
      if (byStr === undefined || orderStr === undefined
        || byStr.trim().length === 0 || orderStr.trim().length === 0) {
        return;
      }
      const by = byStr.trim() as VideoListSortBy;
      const order = orderStr.trim() as VideoListSortOrder;
      const byValues: string[] = ['favorite_time', 'view_time', 'year', 'score', 'create_time', 'name'];
      if (!byValues.includes(by)) {
        return;
      }
      if (order !== 'asc' && order !== 'desc') {
        return;
      }
      this.sortBy = by;
      this.sortOrder = order;
    } catch (_e) {
    }
  }

  private saveSortSettings(): void {
    const suf = this.sortSuffix();
    try {
      PreferencesStore.getInstance().setString(`${KEY_SORT_BY}_${suf}`, this.sortBy);
      PreferencesStore.getInstance().setString(`${KEY_SORT_ORDER}_${suf}`, this.sortOrder);
    } catch (_e) {
    }
  }

  private sourceCacheKey(mediaType: string): string {
    const lt = this.listType.trim().length > 0 ? this.listType.trim() : 'default';
    const mt = mediaType.trim().length > 0 ? mediaType.trim() : 'all';
    return `${KEY_SOURCE_PREFIX}_${lt}_${mt}`;
  }

  private effectiveMediaType(): string {
    return this.initialMediaType.trim().length > 0
      ? this.initialMediaType.trim() : this.mediaType.trim();
  }

  private restoreSelectedPaths(mediaType: string): boolean {
    try {
      const raw = PreferencesStore.getInstance().getString(this.sourceCacheKey(mediaType));
      const saved = raw !== undefined ? normalizePaths(JSON.parse(raw) as string[]) : [];
      const available = this.availablePaths.map((e: VideoListPathItem) => e.path);
      const restored = saved.filter((p: string) => available.includes(p));
      const current = normalizePaths(this.selectedPaths);
      if (current.length === restored.length && current.every((p: string, i: number) => p === restored[i])) {
        return false;
      }
      this.selectedPaths = restored;
      return true;
    } catch (_e) {
      return false;
    }
  }

  private saveSelectedPaths(mediaType: string): void {
    try {
      const normalized = normalizePaths(this.selectedPaths);
      if (normalized.length === 0) {
        PreferencesStore.getInstance().remove(this.sourceCacheKey(mediaType));
        return;
      }
      PreferencesStore.getInstance().setString(this.sourceCacheKey(mediaType), JSON.stringify(normalized));
    } catch (_e) {
    }
  }

  async refreshList(showLoading: boolean = false): Promise<void> {
    const requestedSelectedPaths = this.selectedPaths.slice();
    this.loading = true;
    this.autoLoadFailed = false;
    try {
      this.page = 1;
      const res = await new VideoListApiService().listPaged(
        this.page, this.pageSize, this.listType, this.effectiveMediaType(),
        this.albumId, this.collectionId, this.smartAlbumId, this.searchText,
        this.genres, this.regions, this.actors, this.directors, this.selectedYears,
        requestedSelectedPaths.length > 0 ? requestedSelectedPaths : undefined,
        this.sortBy, this.sortOrder);
      this.items = res.items;
      this.total = res.pagination.total;
      this.hasMore = res.pagination.hasNextPage;
      this.availablePaths = res.validPaths;
      if (this.restoreSelectedPaths(this.effectiveMediaType())
        && !this.samePaths(requestedSelectedPaths, this.selectedPaths)) {
        await this.refreshList(false);
        return;
      }
      const filters = res.filters;
      if (filters !== undefined) {
        this.availableGenres = filters.genres;
        this.availableRegions = filters.regions;
        this.availableYears = filters.years;
        if (this.selectedYears.length === 0) {
          this.baseAvailableYears = filters.years;
        }
      }
    } finally {
      this.loading = false;
    }
  }

  private samePaths(left: string[], right: string[]): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let i = 0; i < left.length; i++) {
      if (left[i] !== right[i]) {
        return false;
      }
    }
    return true;
  }

  async setSourcePathSelected(path: string, isSelected: boolean): Promise<void> {
    const normalized = path.trim();
    if (normalized.length === 0) {
      return;
    }
    const has = this.selectedPaths.includes(normalized);
    if (isSelected && !has) {
      this.selectedPaths = this.selectedPaths.concat([normalized]);
    } else if (!isSelected && has) {
      this.selectedPaths = this.selectedPaths.filter((p: string) => p !== normalized);
    } else {
      return;
    }
    this.saveSelectedPaths(this.effectiveMediaType());
    await this.refreshList(false);
  }

  async clearSourcePathSelection(): Promise<void> {
    this.selectedPaths = [];
    this.saveSelectedPaths(this.effectiveMediaType());
    await this.refreshList(false);
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
      const res = await new VideoListApiService().listPaged(
        nextPage, this.pageSize, this.listType, this.effectiveMediaType(),
        this.albumId, this.collectionId, this.smartAlbumId, this.searchText,
        this.genres, this.regions, this.actors, this.directors, this.selectedYears,
        this.selectedPaths.length > 0 ? this.selectedPaths : undefined,
        this.sortBy, this.sortOrder);
      this.page = nextPage;
      this.items = this.items.concat(res.items);
      this.total = res.pagination.total;
      this.hasMore = res.pagination.hasNextPage;
      this.autoLoadFailed = false;
    } catch (_e) {
      this.autoLoadFailed = true;
    } finally {
      this.loadingMore = false;
    }
  }

  setMediaType(type: string): void {
    if (this.mediaType === type) {
      return;
    }
    this.mediaType = type;
    void this.refreshList(true);
  }

  updateFavoriteState(indexId: number, isFavorite: boolean): void {
    if (indexId <= 0) {
      return;
    }
    if (this.isFavoriteList && !isFavorite) {
      this.items = this.items.filter((e: VideoHomeItemBean) => e.id !== indexId);
      this.total = Math.max(this.total - 1, 0);
      return;
    }
    const idx = this.items.findIndex((e: VideoHomeItemBean) => e.id === indexId);
    if (idx < 0) {
      return;
    }
    const updated = this.items.slice();
    updated[idx] = parseVideoHomeItemBean(updated[idx] as Object);
    updated[idx].isFavorite = isFavorite;
    this.items = updated;
  }

  removeFromCurrentAlbumState(indexId: number): void {
    if (!this.isAlbumList || indexId <= 0) {
      return;
    }
    this.items = this.items.filter((e: VideoHomeItemBean) => e.id !== indexId);
    this.total = Math.max(this.total - 1, 0);
  }

  setSearchText(v: string): void {
    this.searchText = v;
    if (this.searchDebounceId >= 0) {
      clearTimeout(this.searchDebounceId);
    }
    this.searchDebounceId = setTimeout((): void => {
      void this.refreshList(false);
    }, 350);
  }

  clearSearch(): void {
    if (this.searchText.length === 0) {
      return;
    }
    this.searchText = '';
    void this.refreshList(false);
  }

  toggleGenre(g: string): void {
    const v = g.trim();
    if (v.length === 0) {
      return;
    }
    this.genres = this.genres.includes(v)
      ? this.genres.filter((e: string) => e !== v)
      : this.genres.concat([v]);
    void this.refreshList(true);
  }

  toggleRegion(r: string): void {
    const v = r.trim();
    if (v.length === 0) {
      return;
    }
    this.regions = this.regions.includes(v)
      ? this.regions.filter((e: string) => e !== v)
      : this.regions.concat([v]);
    void this.refreshList(true);
  }

  toggleYear(year: number): void {
    if (year <= 0) {
      return;
    }
    if (this.selectedYears.length === 1 && this.selectedYears[0] === year) {
      this.selectedYears = [];
    } else {
      this.selectedYears = [year];
    }
    void this.refreshList(true);
  }

  toggleYearGroup(years: number[]): void {
    const ys = years.filter((e: number) => e > 0)
      .filter((e: number, i: number, arr: number[]) => arr.indexOf(e) === i)
      .sort((a: number, b: number) => b - a);
    if (ys.length === 0) {
      return;
    }
    const isSame = this.selectedYears.length === ys.length
      && ys.every((e: number) => this.selectedYears.includes(e));
    this.selectedYears = isSame ? [] : ys;
    void this.refreshList(true);
  }

  /** 年代分组（对齐 getYearGroups：最新年份 + 年代窗口 + 更早） */
  getYearGroups(): VideoListYearGroup[] {
    const source = this.baseAvailableYears.length > 0 ? this.baseAvailableYears : this.availableYears;
    const years = source.filter((e: number) => e > 0)
      .filter((e: number, i: number, arr: number[]) => arr.indexOf(e) === i)
      .sort((a: number, b: number) => b - a);
    if (years.length === 0) {
      return [];
    }
    const latest = years[0];
    const groups: VideoListYearGroup[] = [];
    const g1 = new VideoListYearGroup();
    g1.label = `${latest}`;
    g1.years = [latest];
    g1.single = true;
    groups.push(g1);

    const latestDecade = Math.floor(latest / 10) * 10;
    const minDecade = latestDecade - 4 * 10;
    for (let d = latestDecade; d >= minDecade; d -= 10) {
      const decadeYears = years.filter((y: number) => y >= d && y < d + 10);
      if (decadeYears.length === 0) {
        continue;
      }
      if (d === latestDecade && decadeYears.length === 1 && decadeYears[0] === latest) {
        continue;
      }
      const g = new VideoListYearGroup();
      g.label = `${d}s`;
      g.years = decadeYears;
      g.single = false;
      groups.push(g);
    }
    const older = years.filter((y: number) => y < minDecade);
    if (older.length > 0) {
      const g = new VideoListYearGroup();
      g.label = L10n.t('video_list_older', '更早');
      g.years = older;
      g.single = false;
      groups.push(g);
    }
    return groups;
  }

  resetFilter(): void {
    this.genres = [];
    this.regions = [];
    this.selectedYears = [];
    void this.refreshList(true);
  }

  setSort(by: VideoListSortBy, order: VideoListSortOrder): void {
    this.sortBy = by;
    this.sortOrder = order;
    this.saveSortSettings();
    void this.refreshList(true);
  }

  increasePosterScale(): void {
    const next = normalizePosterScale(this.posterScale + POSTER_SCALE_STEP);
    this.posterScale = next;
    VideoListController.saveSharedPosterScale(next);
  }

  decreasePosterScale(): void {
    const next = normalizePosterScale(this.posterScale - POSTER_SCALE_STEP);
    this.posterScale = next;
    VideoListController.saveSharedPosterScale(next);
  }
}
