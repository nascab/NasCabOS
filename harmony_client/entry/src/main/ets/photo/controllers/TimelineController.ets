import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import {
  TimelineDateItem, TimelinePhotoItem, TimelinePathItem, TimelineDateInfo
} from '../models/PhotoModels';
import { TimelineFilter, PhotoTimelineApiService } from '../service/PhotoTimelineApiService';

/** 每次分页请求的照片数量下限（对齐 Flutter minGetCount） */
const MIN_GET_COUNT = 300;
/** 列表类型：timeline(默认)/favorite(收藏) */
const LIST_TIMELINE = 'timeline';
const LIST_FAVORITE = 'favorite';
/** 缓存 key（对齐 Flutter PhotoTimelineController 常量） */
const KEY_SORT_ORDER = 'timeline_sort_order';
const KEY_ITEM_SIZE = 'timeline_item_size';
const KEY_IS_COVER_MODE = 'timeline_is_cover_mode';
const KEY_SOURCE_PATHS = 'timeline_selected_source_paths';

/** 日期 header（扁平序列节点） */
export class TimelineListDateHeader {
  date: string = '';
  constructor(date: string) {
    this.date = date;
  }
}

/** 照片项（扁平序列节点） */
export class TimelineListPhoto {
  photo: TimelinePhotoItem;
  constructor(photo: TimelinePhotoItem) {
    this.photo = photo;
  }
}

type FlatItem = TimelineListDateHeader | TimelineListPhoto;

/** 渲染行：header 行或一行 N 个照片 */
@ObservedV2
export class TimelineRowItem {
  @Trace isHeader: boolean = false;
  @Trace date: string = '';
  @Trace photos: TimelinePhotoItem[] = [];
}

function startOfDayTs(dateStr: string): number {
  const m = dateStr.match(/^(\d+)-(\d+)-(\d+)/);
  if (m === null) {
    return 0;
  }
  return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10), 0, 0, 0, 0).getTime();
}

function endOfDayTs(dateStr: string): number {
  const m = dateStr.match(/^(\d+)-(\d+)-(\d+)/);
  if (m === null) {
    return 0;
  }
  return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10), 23, 59, 59, 999).getTime();
}

class FetchRange {
  startTime: number = 0;
  endTime: number = 0;
  startIndex: number = 0;
  endIndex: number = 0;
}

function mapPhoto(p: TimelinePhotoItem, isFavorite: boolean): TimelinePhotoItem {
  const np = new TimelinePhotoItem();
  np.id = p.id;
  np.path = p.path;
  np.filename = p.filename;
  np.size = p.size;
  np.isLvp = p.isLvp;
  np.isMergeLvp = p.isMergeLvp;
  np.type = p.type;
  np.width = p.width;
  np.height = p.height;
  np.originalDate = p.originalDate;
  np.originalTime = p.originalTime;
  np.fullpath = p.fullpath;
  np.duration = p.duration;
  np.fileHash = p.fileHash;
  np.liveFilename = p.liveFilename;
  np.rawFilename = p.rawFilename;
  np.rawShowExt = p.rawShowExt;
  np.isFavorite = isFavorite;
  return np;
}

/**
 * 照片时间轴控制器（对齐 Flutter PhotoTimelineController 及其 parts：
 * loading/pagination/settings/utils/scroll/selection/media；移动端交互）
 */
@ObservedV2
export class TimelineController {
  readonly minItemSize: number = 60;
  readonly maxItemSize: number = 400;
  /** 日期 header 行高（vp） */
  readonly headerExtent: number = 54;
  /** 未配置来源路径时是否弹出管理员提示 */
  alertWhenNoSourcePath: boolean = false;

  private apiService: PhotoTimelineApiService = new PhotoTimelineApiService();

  // ---- 响应式状态 ----
  @Trace dateList: TimelineDateItem[] = [];
  @Trace rows: TimelineRowItem[] = [];
  @Trace availablePaths: TimelinePathItem[] = [];
  @Trace selectedPaths: string[] = [];
  @Trace isLoadingDates: boolean = false;
  @Trace isLoadingUp: boolean = false;
  @Trace isLoadingDown: boolean = false;
  @Trace hasMoreUp: boolean = true;
  @Trace hasMoreDown: boolean = true;
  @Trace isTimelineVisible: boolean = false;
  @Trace isMultiSelectMode: boolean = false;
  @Trace selectedIds: number[] = [];
  @Trace topDate: string = '';
  @Trace sortOrder: string = 'desc';
  @Trace fileType: string = 'all';
  @Trace searchKeyword: string = '';
  @Trace itemSize: number = 140;
  @Trace isCoverMode: boolean = true;
  @Trace listType: string = LIST_TIMELINE;
  @Trace loadTheDay: boolean = false;
  /** 附近照片范围（km），仅在传入 geohash 时生效 */
  @Trace nearbyRangeKm: number = 2;

  albumId: number = 0;
  collectionId: number = 0;
  smartAlbumId: number = 0;
  faceId: number = 0;
  placeName: string = '';
  baseGeohash: string = '';
  year: number = 0;

  /** 日期信息（geo/camera），key=originalDate */
  @Trace dateInfoMap: Map<string, TimelineDateInfo> = new Map();
  /** 扁平渲染序列（与 Flutter photoItems 对齐） */
  private flat: FlatItem[] = [];

  // ---- 布局信息（由视图测量回填） ----
  contentWidth: number = 0;
  crossAxisCount: number = 4;
  cellExtent: number = 90;

  // ---- 内部 ----
  private scrollLoadLock: boolean = false;
  private timelineHideTimer: number = -1;
  private searchDebounce: number = -1;
  private lastScrollOffset: number = 0;
  private loadingTimeline: boolean = false;

  /** 用初始上下文初始化（视图 aboutToAppear 调用一次） */
  configure(initialListType: string, albumId: number, collectionId: number, smartAlbumId: number,
    faceId: number, placeName: string, loadTheDay: boolean, geohash: string, year: number,
    alertWhenNoSourcePath: boolean): void {
    this.albumId = albumId;
    this.collectionId = collectionId;
    this.smartAlbumId = smartAlbumId;
    this.faceId = faceId;
    this.placeName = placeName.trim();
    this.loadTheDay = loadTheDay;
    this.baseGeohash = geohash.trim();
    this.year = year;
    this.alertWhenNoSourcePath = alertWhenNoSourcePath;
    this.listType = initialListType;
    this.sortOrder = PreferencesStore.getInstance().getString(KEY_SORT_ORDER) ?? 'desc';
    this.itemSize = PreferencesStore.getInstance().getInt(KEY_ITEM_SIZE, 140);
    this.isCoverMode = PreferencesStore.getInstance().getBool(KEY_IS_COVER_MODE, true);
    if (this.itemSize < this.minItemSize || this.itemSize > this.maxItemSize) {
      this.itemSize = 140;
    }
    this.updateLayout(this.contentWidth);
  }

  get geohashForRequest(): string {
    const gh = this.baseGeohash.trim();
    if (gh.length === 0) {
      return '';
    }
    // 范围→geohash 精度（对齐 Flutter geohashForRequest）
    let precision = 6;
    switch (this.nearbyRangeKm) {
      case 5:
        precision = 5;
        break;
      case 10:
        precision = 4;
        break;
      case 50:
        precision = 3;
        break;
      case 80:
        precision = 2;
        break;
      default:
        precision = 6;
        break;
    }
    const len = Math.min(Math.max(precision, 2), gh.length);
    return gh.substring(0, len);
  }

  setNearbyRangeKm(km: number): void {
    this.nearbyRangeKm = km;
    void this.refreshTimeline();
  }

  private buildFilter(): TimelineFilter {
    const f = new TimelineFilter();
    f.sort = this.sortOrder;
    f.fileType = this.fileType;
    f.search = this.searchKeyword;
    f.geohash = this.geohashForRequest;
    f.sourceList = this.selectedPaths;
    f.listType = this.listType;
    f.albumId = this.albumId;
    f.collectionId = this.collectionId;
    f.smartAlbumId = this.smartAlbumId;
    f.faceId = this.faceId;
    f.placeName = this.placeName;
    f.loadTheDay = this.loadTheDay;
    f.year = this.year;
    return f;
  }

  // ================= 布局 =================

  /** 视图测量内容宽度后调用：计算列数与单元格尺寸 */
  updateLayout(contentWidth: number): void {
    if (contentWidth <= 0) {
      return;
    }
    this.contentWidth = contentWidth;
    const spacing = 1;
    const count = Math.max(1, Math.floor((contentWidth + spacing) / (this.itemSize + spacing)));
    const prevCount = this.crossAxisCount;
    this.crossAxisCount = count;
    const usable = Math.max(0, contentWidth - (count - 1) * spacing);
    this.cellExtent = usable / count;
    if (count !== prevCount) {
      this.rebuildRows();
    }
  }

  // ================= 搜索 =================

  onSearchChanged(val: string): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout((): void => {
      this.searchDebounce = -1;
      this.searchKeyword = val;
      void this.refreshTimeline();
    }, 500);
  }

  clearSearch(): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.searchKeyword = '';
    void this.refreshTimeline();
  }

  // ================= 加载 =================

  /** 手动刷新入口：重新拉取日期列表并重置页面数据 */
  async refreshTimeline(): Promise<void> {
    await this.loadDateList();
  }

  private async loadDateList(): Promise<void> {
    if (this.loadingTimeline) {
      return;
    }
    this.loadingTimeline = true;
    const requestedSelectedPaths = this.selectedPaths.slice();
    this.isLoadingDates = true;
    this.hasMoreUp = true;
    this.hasMoreDown = true;
    this.isMultiSelectMode = false;
    this.selectedIds = [];
    this.flat = [];
    this.rows = [];
    this.dateInfoMap.clear();
    this.topDate = '';
    try {
      const res = await this.apiService.getTimelineDateList(this.buildFilter());
      if (res.success && res.data !== undefined) {
        this.dateList = res.data.items;
        this.availablePaths = res.data.validPaths;
        const didRestore = await this.restoreSelectedPaths(res.data.validPaths);
        if (didRestore && !this.sameStrList(requestedSelectedPaths, this.selectedPaths)) {
          this.isLoadingDates = false;
          this.loadingTimeline = false;
          await this.loadDateList();
          return;
        }
        const invalidPaths = res.data.validPaths.filter((p: TimelinePathItem): boolean => !p.valid);
        if (invalidPaths.length > 0) {
          this.alertInvalidPaths(invalidPaths);
        }
        if (res.data.validPaths.length === 0 && this.alertWhenNoSourcePath
          && CurrentUserStore.getInstance().isAdmin) {
          DialogUtil.showConfirmDialog(L10n.t('tip', '提示'),
            L10n.t('path_no_set', '请先设置来源目录，以启用此模块'),
            (): void => {
            }, L10n.t('go_to', '前往'), L10n.t('i_know', '知道了'));
        }
        if (this.dateList.length > 0) {
          await this.loadPhotosFromAnchor(this.dateList[0].originalDate);
        }
        this.notifyTimelineReset();
      }
    } catch (_e) {
      // 网络错误：保留空态
    } finally {
      this.isLoadingDates = false;
      this.loadingTimeline = false;
    }
  }

  /** 以锚点日期为起点拉取首屏（对齐 _loadInitialPhotos / jumpToDate） */
  private async loadPhotosFromAnchor(anchorDate: string): Promise<void> {
    if (this.dateList.length === 0) {
      return;
    }
    this.isLoadingDown = true;
    try {
      const range = this.buildFetchRangeByMinCount(anchorDate, false, true);
      if (range === undefined) {
        this.hasMoreDown = false;
        this.hasMoreUp = false;
        return;
      }
      const hasData = await this.fetchAndProcessPhotos(range.startTime, range.endTime, false, true);
      if (!hasData) {
        this.hasMoreDown = false;
        this.hasMoreUp = false;
      } else {
        this.hasMoreUp = range.startIndex > 0;
        this.hasMoreDown = range.endIndex < this.dateList.length - 1;
      }
    } finally {
      this.isLoadingDown = false;
    }
  }

  /** 侧边栏跳转日期 */
  async jumpToDate(date: string): Promise<void> {
    this.showTimeline();
    this.hasMoreUp = true;
    this.hasMoreDown = true;
    this.isMultiSelectMode = false;
    this.selectedIds = [];
    this.flat = [];
    this.rows = [];
    this.isLoadingDown = true;
    try {
      const range = this.buildFetchRangeByMinCount(date, false, true);
      if (range === undefined) {
        this.hasMoreDown = false;
        this.hasMoreUp = false;
        return;
      }
      const hasData = await this.fetchAndProcessPhotos(range.startTime, range.endTime, false, true);
      if (!hasData) {
        this.hasMoreDown = false;
        this.hasMoreUp = false;
      } else {
        this.hasMoreUp = range.startIndex > 0;
        this.hasMoreDown = range.endIndex < this.dateList.length - 1;
      }
      if (this.rows.length > 0) {
        await this.loadMore(true);
      }
      this.notifyTimelineReset();
    } finally {
      this.isLoadingDown = false;
    }
  }

  private alertInvalidPaths(invalidPaths: TimelinePathItem[]): void {
    const pathStr = invalidPaths.map((e: TimelinePathItem): string => e.path).join('\n');
    const isAdmin = CurrentUserStore.getInstance().isAdmin;
    const params = new Map<string, string>();
    params.set('path', `\n${pathStr}`);
    if (isAdmin) {
      DialogUtil.showConfirmDialog(
        L10n.t('path_invalid_admin_title', '来源路径不可用'),
        L10n.t('path_invalid_admin_content',
          '来源路径: @path 已不可用, 请检查此路径在服务器上的状态', params),
        (): void => {
        }, L10n.t('check_now', '立即检查'), L10n.t('i_know', '知道了'));
    } else {
      DialogUtil.showInfoDialog(
        L10n.t('path_invalid_user_title', '来源路径不可用'),
        L10n.t('path_invalid_user_content', '来源路径 @path 已不可用, 请联系管理员检查', params),
        L10n.t('i_know', '知道了'));
    }
  }

  // ================= 分页 =================

  private async loadMore(up: boolean): Promise<void> {
    if (up) {
      if (this.isLoadingUp || !this.hasMoreUp) {
        return;
      }
    } else {
      if (this.isLoadingDown || !this.hasMoreDown) {
        return;
      }
    }

    // 从 flat 中查找边界照片
    let boundaryPhoto: TimelinePhotoItem | undefined = undefined;
    if (up) {
      for (const it of this.flat) {
        if (it instanceof TimelineListPhoto) {
          boundaryPhoto = it.photo;
          break;
        }
      }
    } else {
      for (let i = this.flat.length - 1; i >= 0; i--) {
        const it = this.flat[i];
        if (it instanceof TimelineListPhoto) {
          boundaryPhoto = it.photo;
          break;
        }
      }
    }
    if (boundaryPhoto === undefined) {
      return;
    }

    try {
      if (up) {
        this.isLoadingUp = true;
      } else {
        this.isLoadingDown = true;
      }
      const range = this.buildFetchRangeByMinCount(boundaryPhoto.originalDate, up, false);
      if (range === undefined) {
        if (up) {
          this.hasMoreUp = false;
        } else {
          this.hasMoreDown = false;
        }
        return;
      }
      const hasData = await this.fetchAndProcessPhotos(range.startTime, range.endTime, up, false);
      if (!hasData) {
        if (up) {
          this.hasMoreUp = false;
        } else {
          this.hasMoreDown = false;
        }
        return;
      }
      if (up) {
        this.hasMoreUp = range.startIndex > 0;
      } else {
        this.hasMoreDown = range.endIndex < this.dateList.length - 1;
      }
    } finally {
      if (up) {
        this.isLoadingUp = false;
        this.notifyRestoreAnchor();
      } else {
        this.isLoadingDown = false;
      }
    }
  }

  /** 拉取照片列表并合并到 flat；返回是否有数据 */
  private async fetchAndProcessPhotos(startTime: number, endTime: number, isUp: boolean,
    clear: boolean): Promise<boolean> {
    const res = await this.apiService.getTimelinePhotoList(this.buildFilter(), startTime, endTime);
    if (!res.success || res.data === undefined || res.data.photoList.length === 0) {
      return false;
    }
    for (const info of res.data.dateInfoList) {
      const date = info.originalDate.trim();
      if (date.length > 0) {
        this.dateInfoMap.set(date, info);
      }
    }
    const incoming = res.data.photoList;
    if (clear) {
      const next: FlatItem[] = [];
      let currentDate = '';
      for (const p of incoming) {
        if (p.originalDate !== currentDate) {
          currentDate = p.originalDate;
          next.push(new TimelineListDateHeader(currentDate));
        }
        next.push(new TimelineListPhoto(p));
      }
      this.flat = next;
      this.rebuildRows();
      return true;
    }
    this.mergeIncomingPhotos(incoming, isUp);
    return true;
  }

  /** 将新拉取的数据合并到 flat（对齐 Flutter _mergeIncomingPhotos） */
  private mergeIncomingPhotos(photos: TimelinePhotoItem[], isUp: boolean): void {
    if (photos.length === 0) {
      return;
    }
    const newItems: FlatItem[] = [];
    let currentDate = '';
    for (const p of photos) {
      if (p.originalDate !== currentDate) {
        currentDate = p.originalDate;
        newItems.push(new TimelineListDateHeader(currentDate));
      }
      newItems.push(new TimelineListPhoto(p));
    }

    if (isUp) {
      // 向上加载：插入头部
      if (this.flat.length > 0) {
        const firstExisting = this.flat[0];
        if (firstExisting instanceof TimelineListDateHeader) {
          const lastNewPhoto = photos[photos.length - 1];
          if (lastNewPhoto.originalDate === firstExisting.date) {
            // 日期重合：移除旧数据首 header
            this.flat.splice(0, 1);
          }
        }
      }
      this.flat = newItems.concat(this.flat);
    } else {
      // 向下加载：追加尾部
      let lastExistingPhoto: TimelinePhotoItem | undefined = undefined;
      for (let i = this.flat.length - 1; i >= 0; i--) {
        const it = this.flat[i];
        if (it instanceof TimelineListPhoto) {
          lastExistingPhoto = it.photo;
          break;
        }
      }
      if (lastExistingPhoto !== undefined) {
        const firstNewPhoto = photos[0];
        if (lastExistingPhoto.originalDate === firstNewPhoto.originalDate) {
          if (newItems.length > 0 && newItems[0] instanceof TimelineListDateHeader) {
            newItems.splice(0, 1);
          }
        }
      }
      this.flat = this.flat.concat(newItems);
    }
    this.rebuildRows();
  }

  /** 由 flat 重建 rows（header 行 + 每行 crossAxisCount 个照片） */
  onRowsChanged: (() => void) | undefined = undefined;

  private rebuildRows(): void {
    const cols = Math.max(1, this.crossAxisCount);
    const next: TimelineRowItem[] = [];
    let current: TimelineRowItem | undefined = undefined;
    for (const it of this.flat) {
      if (it instanceof TimelineListDateHeader) {
        const h = new TimelineRowItem();
        h.isHeader = true;
        h.date = it.date;
        next.push(h);
        current = undefined;
      } else {
        const p = (it as TimelineListPhoto).photo;
        if (current === undefined || current.photos.length >= cols) {
          current = new TimelineRowItem();
          next.push(current);
        }
        current.photos.push(p);
      }
    }
    this.rows = next;
    if (this.onRowsChanged !== undefined) {
      this.onRowsChanged();
    }
  }

  /** 带节流的触发分页 */
  async triggerLoadMore(up: boolean): Promise<void> {
    if (this.scrollLoadLock) {
      return;
    }
    this.scrollLoadLock = true;
    try {
      await this.loadMore(up);
    } finally {
      setTimeout((): void => {
        this.scrollLoadLock = false;
      }, 200);
    }
  }

  /** 根据锚点日期与方向构造一次拉取的日期范围（对齐 _buildFetchRangeByMinCount） */
  private buildFetchRangeByMinCount(anchorDate: string, up: boolean, includeAnchor: boolean):
    FetchRange | undefined {
    if (this.dateList.length === 0) {
      return undefined;
    }
    let anchorIndex = -1;
    for (let i = 0; i < this.dateList.length; i++) {
      if (this.dateList[i].originalDate === anchorDate) {
        anchorIndex = i;
        break;
      }
    }
    if (anchorIndex < 0) {
      return undefined;
    }
    const range = new FetchRange();
    if (up) {
      const from = anchorIndex - (includeAnchor ? 0 : 1);
      if (from < 0) {
        return undefined;
      }
      let total = 0;
      let startIndex = from;
      let endIndex = from;
      for (let i = from; i >= 0; i--) {
        total += this.dateList[i].count;
        startIndex = i;
        if (total >= MIN_GET_COUNT) {
          break;
        }
      }
      range.startTime = startOfDayTs(this.dateList[startIndex].originalDate);
      range.endTime = endOfDayTs(this.dateList[endIndex].originalDate);
      range.startIndex = startIndex;
      range.endIndex = endIndex;
      return range;
    }
    const from = anchorIndex + (includeAnchor ? 0 : 1);
    if (from >= this.dateList.length) {
      return undefined;
    }
    let total = 0;
    let startIndex = from;
    let endIndex = from;
    for (let i = from; i < this.dateList.length; i++) {
      total += this.dateList[i].count;
      endIndex = i;
      if (total >= MIN_GET_COUNT) {
        break;
      }
    }
    range.startTime = startOfDayTs(this.dateList[startIndex].originalDate);
    range.endTime = endOfDayTs(this.dateList[endIndex].originalDate);
    range.startIndex = startIndex;
    range.endIndex = endIndex;
    return range;
  }

  private sameStrList(a: string[], b: string[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  // ================= 设置项 =================

  toggleSortOrder(): void {
    this.sortOrder = this.sortOrder === 'desc' ? 'asc' : 'desc';
    void PreferencesStore.getInstance().setString(KEY_SORT_ORDER, this.sortOrder);
    void this.refreshTimeline();
  }

  setFileType(type: string): void {
    this.fileType = type;
    void this.refreshTimeline();
  }

  setTimelineMode(nextListType: string, nextLoadTheDay: boolean): void {
    if (this.listType === nextListType && this.loadTheDay === nextLoadTheDay) {
      return;
    }
    this.listType = nextListType;
    this.loadTheDay = nextLoadTheDay;
    void this.refreshTimeline();
  }

  /** 设置年份筛选（年视图点击卡片进入该年时间线；year=0 表示全部年份） */
  setYearFilter(y: number): void {
    if (this.year === y) {
      return;
    }
    this.year = y;
    void this.refreshTimeline();
  }

  changeItemSize(delta: number): void {
    this.setItemSize(this.itemSize + delta);
  }

  setItemSize(newSize: number, save: boolean = true): void {
    if (newSize < this.minItemSize) {
      newSize = this.minItemSize;
    }
    if (newSize > this.maxItemSize) {
      newSize = this.maxItemSize;
    }
    this.itemSize = Math.round(newSize);
    this.updateLayout(this.contentWidth);
    if (save) {
      void PreferencesStore.getInstance().setInt(KEY_ITEM_SIZE, this.itemSize);
    }
  }

  toggleCoverMode(): void {
    this.isCoverMode = !this.isCoverMode;
    void PreferencesStore.getInstance().setBool(KEY_IS_COVER_MODE, this.isCoverMode);
  }

  private async restoreSelectedPaths(availablePathItems: TimelinePathItem[]): Promise<boolean> {
    const available = availablePathItems.map((it: TimelinePathItem): string => it.path);
    let saved: string[] = [];
    try {
      saved = PreferencesStore.getInstance().getJson<string[]>(KEY_SOURCE_PATHS) ?? [];
    } catch (_e) {
      return false;
    }
    const normalized = saved.map((p: string): string => p.trim())
      .filter((p: string): boolean => p.length > 0);
    if (normalized.length === 0) {
      return false;
    }
    const availableSet = new Set<string>(available);
    const restored = normalized.filter((p: string): boolean => availableSet.has(p));
    if (this.sameStrList(this.selectedPaths, restored)) {
      return false;
    }
    this.selectedPaths = restored;
    await this.saveSelectedPaths(restored);
    return true;
  }

  private async saveSelectedPaths(paths: string[]): Promise<void> {
    if (paths.length === 0) {
      await PreferencesStore.getInstance().remove(KEY_SOURCE_PATHS);
      return;
    }
    await PreferencesStore.getInstance().setJson(KEY_SOURCE_PATHS, paths);
  }

  async setSourcePathSelected(path: string, isSelected: boolean): Promise<void> {
    const normalizedPath = path.trim();
    if (normalizedPath.length === 0) {
      return;
    }
    const next = this.selectedPaths.slice();
    const has = next.indexOf(normalizedPath) >= 0;
    if (isSelected && !has) {
      next.push(normalizedPath);
    } else if (!isSelected && has) {
      next.splice(next.indexOf(normalizedPath), 1);
    } else {
      return;
    }
    this.selectedPaths = next;
    await this.saveSelectedPaths(next);
    await this.refreshTimeline();
  }

  async clearSourcePathSelection(refresh: boolean = true): Promise<void> {
    this.selectedPaths = [];
    await this.saveSelectedPaths([]);
    if (refresh) {
      await this.refreshTimeline();
    }
  }

  // ================= 多选与批量操作 =================

  isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  toggleMultiSelectMode(): void {
    this.isMultiSelectMode = !this.isMultiSelectMode;
    if (!this.isMultiSelectMode) {
      this.selectedIds = [];
    }
  }

  exitMultiSelectMode(): void {
    this.isMultiSelectMode = false;
    this.selectedIds = [];
  }

  toggleSelection(id: number): void {
    const next = this.selectedIds.slice();
    const idx = next.indexOf(id);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(id);
    }
    this.selectedIds = next;
    if (next.length > 0 && !this.isMultiSelectMode) {
      this.isMultiSelectMode = true;
    }
    if (next.length === 0) {
      this.exitMultiSelectMode();
    }
  }

  isDateSelected(date: string): boolean {
    const photos = this.dateRowPhotos(date);
    if (photos.length === 0) {
      return false;
    }
    return photos.every((p: TimelinePhotoItem): boolean => this.isSelected(p.id));
  }

  toggleDateSelection(date: string): void {
    const photos = this.dateRowPhotos(date);
    if (photos.length === 0) {
      return;
    }
    const allSelected = this.isDateSelected(date);
    const next = this.selectedIds.slice();
    if (allSelected) {
      for (const p of photos) {
        const idx = next.indexOf(p.id);
        if (idx >= 0) {
          next.splice(idx, 1);
        }
      }
    } else {
      for (const p of photos) {
        if (next.indexOf(p.id) < 0) {
          next.push(p.id);
        }
      }
      this.isMultiSelectMode = true;
    }
    this.selectedIds = next;
    if (next.length === 0) {
      this.exitMultiSelectMode();
    }
  }

  /** 找出某日期下所有已加载照片（沿 flat 扫描） */
  private dateRowPhotos(date: string): TimelinePhotoItem[] {
    const photos: TimelinePhotoItem[] = [];
    let found = false;
    for (const it of this.flat) {
      if (it instanceof TimelineListDateHeader && it.date === date) {
        found = true;
        continue;
      }
      if (found) {
        if (it instanceof TimelineListDateHeader) {
          break;
        }
        photos.push((it as TimelineListPhoto).photo);
      }
    }
    return photos;
  }

  getSelectedPhotoItems(): TimelinePhotoItem[] {
    if (this.selectedIds.length === 0) {
      return [];
    }
    const ids = new Set<number>(this.selectedIds);
    const photos: TimelinePhotoItem[] = [];
    for (const it of this.flat) {
      if (it instanceof TimelineListPhoto && ids.has(it.photo.id)) {
        photos.push(it.photo);
      }
    }
    return photos;
  }

  private selectedFileHashes(): string[] {
    return this.getSelectedPhotoItems()
      .map((p: TimelinePhotoItem): string => p.fileHash)
      .filter((h: string): boolean => h.length > 0);
  }

  /** 批量收藏/取消收藏 */
  async favoriteSelected(): Promise<void> {
    const hashes = this.selectedFileHashes();
    if (hashes.length === 0) {
      return;
    }
    try {
      const isFavoriteList = this.listType === LIST_FAVORITE;
      const targetState = !isFavoriteList;
      const ok = await this.apiService.batchFavorite(hashes, targetState);
      ToastUtil.show(ok ? L10n.t('operation_success', '操作成功')
        : L10n.t('operation_failed', '操作失败'));
      if (ok) {
        const ids = new Set<number>(this.selectedIds);
        if (isFavoriteList) {
          this.removeIdsAndCleanUp(ids);
        } else {
          this.updatePhotosInRows(ids, (p: TimelinePhotoItem): TimelinePhotoItem =>
            mapPhoto(p, targetState));
        }
      }
      this.exitMultiSelectMode();
    } catch (_e) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 单个收藏切换（乐观更新，对齐 toggleFavorite） */
  async toggleFavorite(item: TimelinePhotoItem): Promise<void> {
    try {
      const newStatus = !item.isFavorite;
      this.updateSinglePhoto(item.id, (p: TimelinePhotoItem): TimelinePhotoItem =>
        mapPhoto(p, newStatus));
      const res = await this.apiService.toggleFavorite(item.fileHash);
      if (res.success && res.data !== undefined) {
        if (res.data !== newStatus) {
          const finalStatus = res.data;
          this.updateSinglePhoto(item.id, (p: TimelinePhotoItem): TimelinePhotoItem =>
            mapPhoto(p, finalStatus));
        }
      } else {
        this.updateSinglePhoto(item.id, (p: TimelinePhotoItem): TimelinePhotoItem =>
          mapPhoto(p, !newStatus));
      }
    } catch (_e) {
      // 忽略
    }
  }

  /** 执行删除（放入回收站）并同步本地数据 */
  async deleteSelected(): Promise<void> {
    const ids = this.selectedIds.slice();
    if (ids.length === 0) {
      return;
    }
    try {
      const res = await this.apiService.batchTrash(ids);
      if (!res.success) {
        ToastUtil.show(res.code === 403
          ? L10n.t('permission_denied', '权限被拒绝')
          : L10n.t('operation_failed', '操作失败'));
        return;
      }
      this.removeIdsAndCleanUp(new Set<number>(ids));
      this.exitMultiSelectMode();
      ToastUtil.show(L10n.t('photo_trashed_success', '已放入照片回收站'));
    } catch (_e) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  private updateSinglePhoto(id: number, mapper: (p: TimelinePhotoItem) => TimelinePhotoItem): void {
    this.updatePhotosInRows(new Set<number>([id]), mapper);
  }

  private updatePhotosInRows(ids: Set<number>, mapper: (p: TimelinePhotoItem) => TimelinePhotoItem):
    void {
    for (const row of this.rows) {
      if (row.isHeader) {
        continue;
      }
      let changed = false;
      const next: TimelinePhotoItem[] = [];
      for (const p of row.photos) {
        if (ids.has(p.id)) {
          next.push(mapper(p));
          changed = true;
        } else {
          next.push(p);
        }
      }
      if (changed) {
        row.photos = next;
      }
    }
  }

  /** 移除指定照片并清理空日期 header、更新 dateList 计数（对齐 _removeItemsAndCleanUp） */
  private removeIdsAndCleanUp(ids: Set<number>): void {
    const removedCountByDate = new Map<string, number>();
    const nextFlat: FlatItem[] = [];
    for (const it of this.flat) {
      if (it instanceof TimelineListPhoto) {
        if (ids.has(it.photo.id)) {
          const c = removedCountByDate.get(it.photo.originalDate) ?? 0;
          removedCountByDate.set(it.photo.originalDate, c + 1);
          continue;
        }
      }
      nextFlat.push(it);
    }
    // 更新 dateList 计数并移除空日期
    const nextDates: TimelineDateItem[] = [];
    for (const d of this.dateList) {
      const nc = d.count - (removedCountByDate.get(d.originalDate) ?? 0);
      if (nc > 0) {
        const nd = new TimelineDateItem();
        nd.originalDate = d.originalDate;
        nd.count = nc;
        nextDates.push(nd);
      }
    }
    this.dateList = nextDates;
    // 清理空 header（其后无照片）
    const cleaned: FlatItem[] = [];
    for (let i = 0; i < nextFlat.length; i++) {
      const it = nextFlat[i];
      if (it instanceof TimelineListDateHeader) {
        const nextIt = nextFlat[i + 1];
        if (nextIt === undefined || nextIt instanceof TimelineListDateHeader) {
          continue;
        }
      }
      cleaned.push(it);
    }
    this.flat = cleaned;
    this.rebuildRows();
  }

  // ================= 媒体 =================

  /** 打开媒体预览（图片浏览器/视频播放器为独立模块，迁移前给出提示） */
  openMedia(_item: TimelinePhotoItem): void {
    ToastUtil.show(L10n.t('feature_coming_soon', '敬请期待'));
  }

  // ================= 日期信息 =================

  getDateInfo(date: string): TimelineDateInfo | undefined {
    return this.dateInfoMap.get(date);
  }

  // ================= 滚动/时间轴侧栏 =================

  /** 滚动回调：视图在 onScrollIndex/onDidScroll 时调用 */
  onListScroll(firstIndex: number, lastIndex: number, offset: number): void {
    this.showTimeline();
    if (this.rows.length === 0) {
      this.lastScrollOffset = offset;
      return;
    }
    const delta = offset - this.lastScrollOffset;
    this.lastScrollOffset = offset;
    // 当前顶部日期
    const row = this.rows[Math.min(firstIndex, this.rows.length - 1)];
    if (row !== undefined) {
      this.topDate = row.isHeader ? row.date
        : (row.photos.length > 0 ? row.photos[0].originalDate : '');
    }
    if (this.scrollLoadLock) {
      return;
    }
    if (delta < 0 && firstIndex <= 1) {
      void this.triggerLoadMore(true);
    } else if (delta > 0 && lastIndex >= this.rows.length - 2) {
      void this.triggerLoadMore(false);
    }
  }

  /** 显示右侧时间轴悬浮 UI（2 秒后自动隐藏） */
  showTimeline(): void {
    this.isTimelineVisible = true;
    if (this.timelineHideTimer >= 0) {
      clearTimeout(this.timelineHideTimer);
    }
    this.timelineHideTimer = setTimeout((): void => {
      this.timelineHideTimer = -1;
      this.isTimelineVisible = false;
    }, 2000);
  }

  keepTimelineVisible(): void {
    this.isTimelineVisible = true;
    if (this.timelineHideTimer >= 0) {
      clearTimeout(this.timelineHideTimer);
      this.timelineHideTimer = -1;
    }
  }

  // ---- 锚点恢复（视图实现具体滚动，控制器发通知） ----
  onRestoreAnchor: (() => void) | undefined = undefined;
  /** 数据整体重置（刷新/跳转日期）后通知视图回到顶部 */
  onTimelineReset: (() => void) | undefined = undefined;

  private notifyRestoreAnchor(): void {
    if (this.onRestoreAnchor !== undefined) {
      this.onRestoreAnchor();
    }
  }

  private notifyTimelineReset(): void {
    if (this.onTimelineReset !== undefined) {
      this.onTimelineReset();
    }
  }

  // ================= 批量动作（相册/下载在对应模块迁移后接入） =================

  get isFaceAlbum(): boolean {
    return this.faceId > 0 && CurrentUserStore.getInstance().isAdmin;
  }

  /** 批量下载选中项（依赖下载中心，迁移后接入） */
  async downloadSelected(): Promise<void> {
    if (this.selectedFileHashes().length === 0) {
      return;
    }
    ToastUtil.show(L10n.t('feature_coming_soon', '功能开发中'));
  }

  /** 添加到相册（依赖相册列表选择页，Phase2 接入） */
  async addToAlbumSelected(): Promise<void> {
    if (this.selectedFileHashes().length === 0) {
      return;
    }
    ToastUtil.show(L10n.t('feature_coming_soon', '功能开发中'));
  }

  /** 从当前相册移除（依赖相册 API，Phase2 接入） */
  async removeFromAlbumSelected(): Promise<void> {
    if (this.albumId <= 0 || this.selectedFileHashes().length === 0) {
      return;
    }
    ToastUtil.show(L10n.t('feature_coming_soon', '功能开发中'));
  }
}
