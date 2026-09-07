import { DialogUtil } from '../../common/DialogUtil';
import { L10n } from '../../core/localization/L10n';
import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { VideoAlbumItem, VideoCollectionItem, VideoSmartAlbumItem } from '../models/VideoModels';
import {
  VideoAlbumApiService, VideoCollectionApiService, VideoSmartAlbumApiService
} from '../service/VideoApiServices';

/**
 * 影音相册三类列表控制器（对齐 Flutter VideoAlbumController /
 * VideoSmartAlbumController / VideoCollectionController）：
 * 分页加载（pageSize 20，按 id 去重）+ 关键字搜索（500ms 防抖）+
 * 排序（create_time/name × asc/desc，偏好持久化）+ 增删改。
 */

/** 自建相册列表控制器（仅展示 isOwner 的相册，对齐 Flutter 过滤逻辑） */
@ObservedV2
export class VideoAlbumListController {
  private static readonly KEY_SORT_FIELD: string = 'video_album_sort_field';
  private static readonly KEY_SORT_ORDER: string = 'video_album_sort_order';

  @Trace items: VideoAlbumItem[] = [];
  @Trace total: number = 0;
  @Trace page: number = 1;
  @Trace pageSize: number = 20;
  @Trace keyword: string = '';
  @Trace sortField: string = 'create_time';
  @Trace sortOrder: string = 'desc';
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  private searchTimer: number = -1;
  private api: VideoAlbumApiService = new VideoAlbumApiService();

  init(): void {
    this.loadSortSettings();
    void this.refresh();
  }

  private loadSortSettings(): void {
    const store = PreferencesStore.getInstance();
    const cachedField = store.getString(VideoAlbumListController.KEY_SORT_FIELD);
    const cachedOrder = store.getString(VideoAlbumListController.KEY_SORT_ORDER);
    if (cachedField === 'name' || cachedField === 'create_time') {
      this.sortField = cachedField;
    }
    if (cachedOrder === 'asc' || cachedOrder === 'desc') {
      this.sortOrder = cachedOrder;
    }
  }

  private saveSortSettings(): void {
    const store = PreferencesStore.getInstance();
    void store.setString(VideoAlbumListController.KEY_SORT_FIELD, this.sortField);
    void store.setString(VideoAlbumListController.KEY_SORT_ORDER, this.sortOrder);
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

  clearSearch(): void {
    this.keyword = '';
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

  refresh(): Promise<void> {
    this.hasMore = true;
    this.page = 1;
    return this.loadAlbums(1, false);
  }

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
        this.sortField, this.sortOrder, 1);
      if (!res.success || res.data === undefined) {
        return;
      }
      const data = res.data;
      // 仅保留自己的相册（对齐 Flutter where((e) => e.isOwner)）
      const owned = data.items.filter((e: VideoAlbumItem) => e.isOwner);
      if (append) {
        for (const item of owned) {
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
        this.items = owned;
      }
      this.total = data.page.total;
      this.page = data.page.page > 0 ? data.page.page : pageNumber;
      this.pageSize = data.page.pageSize > 0 ? data.page.pageSize : this.pageSize;
      const size = this.pageSize <= 0 ? 20 : this.pageSize;
      const maxPage = this.total <= 0 ? 1 : Math.ceil(this.total / size);
      this.hasMore = this.page < maxPage;
    } finally {
      this.isLoading = false;
    }
  }

  async createAlbum(name: string, isPublic: boolean): Promise<boolean> {
    const res = await this.api.createAlbum(name, isPublic);
    if (!res.success) {
      ToastError(res.message);
      return false;
    }
    await this.refresh();
    return true;
  }

  async updateAlbum(id: number, name: string, isPublic: boolean): Promise<boolean> {
    const res = await this.api.updateAlbum(id, name, isPublic);
    if (!res.success) {
      ToastError(res.message);
      return false;
    }
    await this.refresh();
    return true;
  }

  async deleteAlbum(id: number): Promise<void> {
    const res = await this.api.deleteAlbum(id);
    if (!res.success) {
      ToastError(res.message);
      return;
    }
    await this.refresh();
  }
}

/** 智能相册列表控制器 */
@ObservedV2
export class VideoSmartAlbumListController {
  private static readonly KEY_SORT_FIELD: string = 'video_smart_album_sort_field';
  private static readonly KEY_SORT_ORDER: string = 'video_smart_album_sort_order';

  @Trace items: VideoSmartAlbumItem[] = [];
  @Trace total: number = 0;
  @Trace page: number = 1;
  @Trace pageSize: number = 20;
  @Trace keyword: string = '';
  @Trace sortField: string = 'create_time';
  @Trace sortOrder: string = 'desc';
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  private searchTimer: number = -1;
  private api: VideoSmartAlbumApiService = new VideoSmartAlbumApiService();

  init(): void {
    this.loadSortSettings();
    void this.refresh();
  }

  private loadSortSettings(): void {
    const store = PreferencesStore.getInstance();
    const cachedField = store.getString(VideoSmartAlbumListController.KEY_SORT_FIELD);
    const cachedOrder = store.getString(VideoSmartAlbumListController.KEY_SORT_ORDER);
    if (cachedField === 'name' || cachedField === 'create_time') {
      this.sortField = cachedField;
    }
    if (cachedOrder === 'asc' || cachedOrder === 'desc') {
      this.sortOrder = cachedOrder;
    }
  }

  private saveSortSettings(): void {
    const store = PreferencesStore.getInstance();
    void store.setString(VideoSmartAlbumListController.KEY_SORT_FIELD, this.sortField);
    void store.setString(VideoSmartAlbumListController.KEY_SORT_ORDER, this.sortOrder);
  }

  onSearchChanged(value: string): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.keyword = value.trim();
      void this.refresh();
    }, 500);
  }

  clearSearch(): void {
    this.keyword = '';
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

  refresh(): Promise<void> {
    this.hasMore = true;
    this.page = 1;
    return this.loadAlbums(1, false);
  }

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
      const res = await this.api.listSmartAlbums(pageNumber, this.pageSize, this.keyword,
        this.sortField, this.sortOrder);
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
      this.total = data.page.total;
      this.page = data.page.page > 0 ? data.page.page : pageNumber;
      this.pageSize = data.page.pageSize > 0 ? data.page.pageSize : this.pageSize;
      const size = this.pageSize <= 0 ? 20 : this.pageSize;
      const maxPage = this.total <= 0 ? 1 : Math.ceil(this.total / size);
      this.hasMore = this.page < maxPage;
    } finally {
      this.isLoading = false;
    }
  }

  async createSmartAlbum(name: string, filterContent: Record<string, Object>): Promise<boolean> {
    const res = await this.api.createSmartAlbum(name, filterContent);
    if (!res.success) {
      ToastError(res.message);
      return false;
    }
    await this.refresh();
    return true;
  }

  async updateSmartAlbum(id: number, name: string,
    filterContent: Record<string, Object>): Promise<boolean> {
    const res = await this.api.updateSmartAlbum(id, name, filterContent);
    if (!res.success) {
      ToastError(res.message);
      return false;
    }
    await this.refresh();
    return true;
  }

  async deleteSmartAlbum(id: number): Promise<void> {
    const res = await this.api.deleteSmartAlbum(id);
    if (!res.success) {
      ToastError(res.message);
      return;
    }
    await this.refresh();
  }
}

/** 照片合集列表控制器 */
@ObservedV2
export class VideoCollectionListController {
  private static readonly KEY_SORT_FIELD: string = 'video_collection_sort_field';
  private static readonly KEY_SORT_ORDER: string = 'video_collection_sort_order';

  @Trace items: VideoCollectionItem[] = [];
  @Trace total: number = 0;
  @Trace page: number = 1;
  @Trace pageSize: number = 20;
  @Trace keyword: string = '';
  @Trace sortField: string = 'create_time';
  @Trace sortOrder: string = 'desc';
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  private searchTimer: number = -1;
  private api: VideoCollectionApiService = new VideoCollectionApiService();

  init(): void {
    this.loadSortSettings();
    void this.refresh();
  }

  private loadSortSettings(): void {
    const store = PreferencesStore.getInstance();
    const cachedField = store.getString(VideoCollectionListController.KEY_SORT_FIELD);
    const cachedOrder = store.getString(VideoCollectionListController.KEY_SORT_ORDER);
    if (cachedField === 'name' || cachedField === 'create_time') {
      this.sortField = cachedField;
    }
    if (cachedOrder === 'asc' || cachedOrder === 'desc') {
      this.sortOrder = cachedOrder;
    }
  }

  private saveSortSettings(): void {
    const store = PreferencesStore.getInstance();
    void store.setString(VideoCollectionListController.KEY_SORT_FIELD, this.sortField);
    void store.setString(VideoCollectionListController.KEY_SORT_ORDER, this.sortOrder);
  }

  onSearchChanged(value: string): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.keyword = value.trim();
      void this.refresh();
    }, 500);
  }

  clearSearch(): void {
    this.keyword = '';
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

  refresh(): Promise<void> {
    this.hasMore = true;
    this.page = 1;
    return this.loadCollections(1, false);
  }

  loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return Promise.resolve();
    }
    return this.loadCollections(this.page + 1, true);
  }

  private async loadCollections(pageNumber: number, append: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await this.api.listCollections(pageNumber, this.pageSize, this.keyword,
        this.sortField, this.sortOrder);
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
      this.total = data.page.total;
      this.page = data.page.page > 0 ? data.page.page : pageNumber;
      this.pageSize = data.page.pageSize > 0 ? data.page.pageSize : this.pageSize;
      const size = this.pageSize <= 0 ? 20 : this.pageSize;
      const maxPage = this.total <= 0 ? 1 : Math.ceil(this.total / size);
      this.hasMore = this.page < maxPage;
    } finally {
      this.isLoading = false;
    }
  }

  async createCollection(name: string, pathList: string[]): Promise<boolean> {
    const res = await this.api.createCollection(name, pathList);
    if (!res.success) {
      ToastError(res.message);
      return false;
    }
    await this.refresh();
    return true;
  }

  async updateCollection(id: number, name: string, pathList: string[]): Promise<boolean> {
    const res = await this.api.updateCollection(id, name, pathList);
    if (!res.success) {
      ToastError(res.message);
      return false;
    }
    await this.refresh();
    return true;
  }

  async deleteCollection(id: number): Promise<void> {
    const res = await this.api.deleteCollection(id);
    if (!res.success) {
      ToastError(res.message);
      return;
    }
    await this.refresh();
  }
}

/** 失败提示（对齐 Flutter 控制器失败 Toast） */
function ToastError(message: string | undefined): void {
  DialogUtil.showErrorDialog(message !== undefined && message.length > 0
    ? message : L10n.t('operation_failed', '操作失败'));
}
