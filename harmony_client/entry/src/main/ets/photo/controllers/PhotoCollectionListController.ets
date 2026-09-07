import { L10n } from '../../core/localization/L10n';
import { DialogUtil } from '../../common/DialogUtil';
import { AppEventBus, EVENT_PHOTO_ALBUM_OVERVIEW_CHANGED } from '../../common/AppEventBus';
import { PhotoCollectionItem } from '../models/PhotoAlbumModels';
import { PhotoCollectionApiService } from '../service/PhotoAlbumApiService';

/**
 * 照片合集列表控制器（对齐 Flutter PhotoCollectionController 的列表部分，
 * 结构镜像 PhotoAlbumListController）：
 * 分页加载 + 关键字搜索（500ms 防抖）+ 增删改后刷新并发出概览变更事件。
 */
@ObservedV2
export class PhotoCollectionListController {
  @Trace items: PhotoCollectionItem[] = [];
  @Trace total: number = 0;
  @Trace page: number = 1;
  readonly pageSize: number = 20;
  @Trace keyword: string = '';
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  private searchTimer: number = -1;
  private api: PhotoCollectionApiService = new PhotoCollectionApiService();

  /** 初始化并加载首页数据（对齐 Flutter onInit） */
  init(): void {
    void this.refresh();
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

  /** 刷新：重置分页从第一页加载（对齐 Flutter refreshCollections） */
  refresh(): Promise<void> {
    this.hasMore = true;
    this.page = 1;
    return this.loadCollections(1, false);
  }

  /** 加载更多：追加下一页并按 id 去重（对齐 Flutter loadMore） */
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
      const res = await this.api.listCollections(pageNumber, this.pageSize, this.keyword);
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

  /** 创建合集并刷新（对齐 Flutter PhotoCollectionController.createCollection） */
  async createCollection(name: string, pathList: string[]): Promise<boolean> {
    const trimmed = name.trim();
    const cleaned: string[] = [];
    for (const p of pathList) {
      const t = p.trim();
      if (t.length > 0) {
        cleaned.push(t);
      }
    }
    if (trimmed.length === 0 || cleaned.length === 0) {
      return false;
    }
    const res = await this.api.createCollection(trimmed, cleaned);
    if (res.success) {
      AppEventBus.emit(EVENT_PHOTO_ALBUM_OVERVIEW_CHANGED);
      void this.refresh();
      return true;
    }
    if (res.message !== undefined && res.message.length > 0) {
      await DialogUtil.showInfoDialog(L10n.tip, res.message);
    }
    return false;
  }

  /** 更新合集并刷新（对齐 Flutter PhotoCollectionController.updateCollection） */
  async updateCollection(id: number, name: string, pathList: string[]): Promise<boolean> {
    const trimmed = name.trim();
    const cleaned: string[] = [];
    for (const p of pathList) {
      const t = p.trim();
      if (t.length > 0) {
        cleaned.push(t);
      }
    }
    if (trimmed.length === 0 || cleaned.length === 0) {
      return false;
    }
    const res = await this.api.updateCollection(id, trimmed, cleaned);
    if (res.success) {
      AppEventBus.emit(EVENT_PHOTO_ALBUM_OVERVIEW_CHANGED);
      void this.refresh();
      return true;
    }
    if (res.message !== undefined && res.message.length > 0) {
      await DialogUtil.showInfoDialog(L10n.tip, res.message);
    }
    return false;
  }

  /** 删除合集并刷新（对齐 Flutter PhotoCollectionController.deleteCollection） */
  async deleteCollection(id: number): Promise<void> {
    const res = await this.api.deleteCollection(id);
    if (!res.success) {
      if (res.message !== undefined && res.message.length > 0) {
        await DialogUtil.showInfoDialog(L10n.tip, res.message);
      }
      return;
    }
    AppEventBus.emit(EVENT_PHOTO_ALBUM_OVERVIEW_CHANGED);
    void this.refresh();
  }
}
