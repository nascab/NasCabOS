import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { TimelinePhotoItem } from '../models/PhotoModels';
import { AiSimilarGroupItem } from '../models/PhotoAiModels';
import { PhotoAiSimilarApiService } from '../service/PhotoAiSimilarApiService';
import { PhotoAiSettingsApiService } from '../service/PhotoAiSettingsApiService';
import { PhotoTimelineApiService } from '../service/PhotoTimelineApiService';

/** 默认每页数量（对齐 Flutter AiSimilarController.pageSize = 20） */
const SIMILAR_PAGE_SIZE = 20;
/** 首页为空时最多自动补页次数（对齐 Flutter _loadNextPageIfEmpty tries < 8） */
const SIMILAR_EMPTY_RETRY_MAX = 8;

/**
 * AI 相似照片（照片去重）控制器（对齐 Flutter AiSimilarController 的移动端状态）：
 * 分组分页加载 + 每组默认勾选（保留最大文件）+ 批量放入回收站 + 重置扫描。
 */
@ObservedV2
export class PhotoAiSimilarController {
  private api: PhotoAiSimilarApiService = new PhotoAiSimilarApiService();
  private settingsApi: PhotoAiSettingsApiService = new PhotoAiSettingsApiService();
  private timelineApi: PhotoTimelineApiService = new PhotoTimelineApiService();

  // ---- 数据状态 ----
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace page: number = 1;
  @Trace pageSize: number = SIMILAR_PAGE_SIZE;
  @Trace total: number = 0;
  /** 去重功能开关（服务端返回 similarEnable） */
  @Trace similarEnabled: boolean = true;
  @Trace groups: AiSimilarGroupItem[] = [];

  // ---- 选择状态 ----
  @Trace selectedPhotoIds: number[] = [];
  /** 照片大小缓存（photoId → size，用于默认勾选与展示） */
  private photoSizeById: Map<number, number> = new Map();
  /** 已应用默认勾选的分组 id（对齐 Flutter _defaultAppliedGroupIds） */
  private defaultAppliedGroupIds: Set<number> = new Set<number>();
  /** 手动切换过的照片 id（对齐 Flutter _manuallyToggledPhotoIds） */
  private manuallyToggledPhotoIds: Set<number> = new Set<number>();

  get canEdit(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  init(): void {
    void this.refreshGroups(false);
  }

  // ================= 数据加载 =================

  /** 刷新（对齐 Flutter refreshGroups：首页加载 + 空页自动补页） */
  async refreshGroups(showLoading: boolean = true): Promise<void> {
    if (showLoading) {
      void DialogUtil.showLoading(L10n.loading);
    }
    try {
      await this.loadGroups(1, false);
      await this.loadNextPageIfEmpty();
    } finally {
      if (showLoading) {
        void DialogUtil.dismissLoading();
      }
    }
  }

  /** 加载更多（对齐 Flutter loadMore） */
  loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return Promise.resolve();
    }
    return this.loadGroups(this.page + 1, true);
  }

  /** 切换每页组数（对齐 Flutter setPageSize） */
  setPageSize(next: number): void {
    const v = next <= 0 ? SIMILAR_PAGE_SIZE : next;
    if (this.pageSize === v) {
      return;
    }
    this.pageSize = v;
    this.clearSelection();
    void this.refreshGroups(false);
  }

  /** 首页为空时继续翻页（对齐 Flutter _loadNextPageIfEmpty） */
  private async loadNextPageIfEmpty(): Promise<void> {
    let tries = 0;
    while (this.groups.length === 0 && this.similarEnabled && this.hasMore && tries < SIMILAR_EMPTY_RETRY_MAX) {
      tries++;
      await this.loadGroups(this.page + 1, false);
    }
  }

  private async loadGroups(pageNumber: number, append: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await this.api.listSimilarGroups(pageNumber, this.pageSize);
      if (!res.success || res.data === undefined) {
        return;
      }
      const data = res.data;
      this.similarEnabled = data.similarEnable;
      if (!data.similarEnable) {
        this.clearSelection();
        this.groups = [];
        this.total = 0;
        this.page = 1;
        this.hasMore = false;
        return;
      }
      const nextItems = data.items;
      if (append) {
        const existing = new Set<number>();
        for (const g of this.groups) {
          existing.add(g.id);
        }
        const filtered: AiSimilarGroupItem[] = [];
        for (const g of nextItems) {
          if (!existing.has(g.id)) {
            filtered.push(g);
          }
        }
        const next = this.groups.concat(filtered);
        this.groups = next;
        this.initGroups(filtered);
      } else {
        this.groups = nextItems;
        this.selectedPhotoIds = [];
        this.defaultAppliedGroupIds = new Set<number>();
        this.manuallyToggledPhotoIds = new Set<number>();
        this.initGroups(nextItems);
      }

      this.total = data.pagination.total;
      this.page = data.pagination.page <= 0 ? pageNumber : data.pagination.page;
      const size = data.pagination.pageSize > 0 ? data.pagination.pageSize : this.pageSize;
      this.pageSize = size;
      const maxPage = this.total <= 0 ? 1 : Math.floor((this.total + size - 1) / size);
      this.hasMore = this.page < maxPage;
    } finally {
      this.isLoading = false;
    }
  }

  // ================= 默认勾选 =================

  /** 初始化分组（对齐 Flutter _initGroups：拉取缺失大小并应用默认勾选） */
  private initGroups(items: AiSimilarGroupItem[]): void {
    for (const g of items) {
      void this.initGroup(g);
    }
  }

  private async initGroup(group: AiSimilarGroupItem): Promise<void> {
    if (group.photos.length <= 1) {
      return;
    }
    if (this.defaultAppliedGroupIds.has(group.id)) {
      return;
    }
    for (const p of group.photos) {
      if (p.size > 0) {
        this.photoSizeById.set(p.id, p.size);
      }
    }
    await this.ensurePhotoSizes(group.photos);
    this.applyDefaultSelectionForGroup(group);
  }

  /** 补齐缺失的照片大小（对齐 Flutter _ensurePhotoSizes：photo/properties/get） */
  private async ensurePhotoSizes(photos: TimelinePhotoItem[]): Promise<void> {
    for (const p of photos) {
      const existing = this.photoSizeById.get(p.id) ?? 0;
      if (existing > 0 || p.size > 0) {
        continue;
      }
      try {
        const res = await this.api.getPhotoProperties(p.fullpath);
        if (!res.success || res.data === undefined) {
          continue;
        }
        const size = parseInt(`${res.data['size']}`, 10);
        if (!isNaN(size) && size > 0) {
          this.photoSizeById.set(p.id, size);
        }
      } catch (_e) {
        // 单张大小获取失败不阻塞
      }
    }
  }

  /** 组内默认勾选：保留最大的照片，其余选中（对齐 Flutter _applyDefaultSelectionForGroup） */
  private applyDefaultSelectionForGroup(group: AiSimilarGroupItem): void {
    if (this.defaultAppliedGroupIds.has(group.id)) {
      return;
    }
    const ids: number[] = [];
    for (const p of group.photos) {
      ids.push(p.id);
    }
    for (const id of ids) {
      if (this.manuallyToggledPhotoIds.has(id)) {
        return;
      }
    }
    let keepId = ids.length > 0 ? ids[0] : 0;
    let keepSize = -1;
    for (const p of group.photos) {
      const s = this.photoSizeById.get(p.id) ?? p.size;
      if (s > keepSize) {
        keepSize = s;
        keepId = p.id;
      }
    }
    const keep = keepId;
    const next = this.selectedPhotoIds.filter((id: number): boolean => ids.indexOf(id) < 0);
    for (const id of ids) {
      if (id !== keep) {
        next.push(id);
      }
    }
    this.selectedPhotoIds = next;
    this.defaultAppliedGroupIds.add(group.id);
  }

  // ================= 选择 =================

  clearSelection(): void {
    this.selectedPhotoIds = [];
    this.manuallyToggledPhotoIds = new Set<number>();
  }

  isSelected(id: number): boolean {
    return this.selectedPhotoIds.indexOf(id) >= 0;
  }

  /** 手动切换单张照片选中（对齐 Flutter togglePhotoSelection） */
  togglePhotoSelection(id: number): void {
    this.manuallyToggledPhotoIds.add(id);
    const next = this.selectedPhotoIds.slice();
    const idx = next.indexOf(id);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(id);
    }
    this.selectedPhotoIds = next;
  }

  /** 照片展示大小（对齐 Flutter photoSizeById[id] ?? photo.size） */
  photoSize(photo: TimelinePhotoItem): number {
    return this.photoSizeById.get(photo.id) ?? photo.size;
  }

  // ================= 动作 =================

  /** 开启去重识别（对齐 Flutter enableSimilarRecognition：仅管理员） */
  async enableSimilarRecognition(): Promise<void> {
    if (!this.canEdit) {
      ToastUtil.show(L10n.t('photo_ai_admin_only', '仅管理员可修改'));
      return;
    }
    const res = await this.settingsApi.setAiSimilarEnable(true);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    await this.refreshGroups(false);
  }

  /** 选中照片放入回收站（对齐 Flutter trashSelectedPhotos，加载弹窗由页面实现） */
  async trashSelectedPhotos(): Promise<void> {
    const ids = this.selectedPhotoIds.slice();
    if (ids.length === 0) {
      return;
    }
    const res = await this.timelineApi.batchTrash(ids);
    if (!res.success) {
      ToastUtil.show(res.code === 403
        ? L10n.t('permission_denied', '权限被拒绝')
        : L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('photo_trashed_success', '已放入照片回收站'));
    this.clearSelection();
    await this.refreshGroups(false);
  }

  /** 重置去重扫描（对齐 Flutter resetSimilarScan：仅管理员） */
  async resetSimilarScan(): Promise<boolean> {
    if (!this.canEdit) {
      ToastUtil.show(L10n.t('photo_ai_admin_only', '仅管理员可修改'));
      return false;
    }
    const res = await this.settingsApi.resetSimilar();
    if (!res.success) {
      ToastUtil.show(res.message !== undefined && res.message.length > 0
        ? res.message : L10n.t('operation_failed', '操作失败'));
      return false;
    }
    return true;
  }
}
