import { L10n } from '../../core/localization/L10n';
import { DialogUtil } from '../../common/DialogUtil';
import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { PhotoAlbumItem } from '../models/PhotoAlbumModels';
import { PhotoAlbumApiService } from '../service/PhotoAlbumApiService';

/** 排序偏好缓存 key（对齐 Flutter PhotoAlbumController.keySortField/keySortOrder + CacheManager） */
const KEY_SORT_FIELD: string = 'photo_album_sort_field';
const KEY_SORT_ORDER: string = 'photo_album_sort_order';

/**
 * 相册列表控制器（对齐 Flutter PhotoAlbumController）：
 * 分页加载 + 关键字搜索（500ms 防抖）+ 类型筛选 + 排序（持久化）+ 增删改后刷新。
 */
@ObservedV2
export class PhotoAlbumListController {
  @Trace items: PhotoAlbumItem[] = [];
  @Trace total: number = 0;
  @Trace page: number = 1;
  readonly pageSize: number = 20;
  @Trace keyword: string = '';
  @Trace typeFilter: string = 'all';
  @Trace sortField: string = 'create_time';
  @Trace sortOrder: string = 'desc';
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  private searchTimer: number = -1;
  private api: PhotoAlbumApiService = new PhotoAlbumApiService();

  /** 初始化：恢复排序偏好并加载首页数据（对齐 Flutter onInit） */
  init(): void {
    this.loadSortSettings();
    void this.refresh();
  }

  /** 恢复排序偏好（仅接受合法值，与 Flutter _loadSortSettings 一致） */
  private loadSortSettings(): void {
    const store = PreferencesStore.getInstance();
    const cachedField = store.getString(KEY_SORT_FIELD);
    const cachedOrder = store.getString(KEY_SORT_ORDER);
    if (cachedField === 'name' || cachedField === 'create_time') {
      this.sortField = cachedField;
    }
    if (cachedOrder === 'asc' || cachedOrder === 'desc') {
      this.sortOrder = cachedOrder;
    }
  }

  private saveSortSettings(): void {
    const store = PreferencesStore.getInstance();
    void store.setString(KEY_SORT_FIELD, this.sortField);
    void store.setString(KEY_SORT_ORDER, this.sortOrder);
  }

  /** 搜索输入（500ms 防抖，对齐 Flutter onSearchChanged） */
  onSearchChanged(value: string): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.keyword = value.trim();
      void this.refresh();
    }, 500);
  }

  /** 直接设置关键字并刷新（输入弹窗确认后调用） */
  setKeyword(value: string): void {
    this.keyword = value;
    void this.refresh();
  }

  setTypeFilter(value: string): void {
    if (this.typeFilter === value) {
      return;
    }
    this.typeFilter = value;
    void this.refresh();
  }

  setSort(field: string, order: string): void {
    if (this.sortField === field && this.sortOrder === order) {
      return;
    }
    this.sortField = field;
    this.sortOrder = order;
    this.saveSortSettings();
    void this.refresh();
  }

  /** 刷新：重置分页从第一页加载（对齐 Flutter refreshAlbums） */
  refresh(): Promise<void> {
    this.hasMore = true;
    this.page = 1;
    return this.loadAlbums(1, false);
  }

  /** 加载更多：追加下一页并按 id 去重（对齐 Flutter loadMore） */
  loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return Promise.resolve();
    }
    return this.loadAlbums(this.page + 1, true);
  }

  private async loadAlbums(pageNumber: number, append: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await this.api.listAlbums(pageNumber, this.pageSize, this.keyword,
        this.typeFilter, this.sortField, this.sortOrder);
      if (!res.success || res.data === undefined) {
        return;
      }
      const data = res.data;
      if (append) {
        for (const item of data.items) {
          let exists = false;
          for (const e of this.items) {
            if (e.id === item.id) {
              exists = true;
              break;
            }
          }
          if (!exists) {
            this.items.push(item);
          }
        }
      } else {
        this.items = data.items;
      }
      this.total = data.total;
      this.page = data.page > 0 ? data.page : pageNumber;
      // hasMore = page < ceil(total/pageSize)（对齐 Flutter 计算）
      this.hasMore = this.page < Math.ceil(this.total / this.pageSize);
    } finally {
      this.isLoading = false;
    }
  }

  /** 删除相册并刷新（对齐 Flutter PhotoAlbumController.deleteAlbum） */
  async deleteAlbum(id: number): Promise<void> {
    const res = await this.api.deleteAlbum(id);
    if (!res.success) {
      if (res.message !== undefined && res.message.length > 0) {
        await DialogUtil.showInfoDialog(L10n.tip, res.message);
      }
      return;
    }
    void this.refresh();
  }
}
