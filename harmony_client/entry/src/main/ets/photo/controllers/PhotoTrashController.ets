import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { TrashPhotoItem } from '../models/PhotoModels';
import { PhotoTimelineApiService } from '../service/PhotoTimelineApiService';

/** 每页数量（对齐 Flutter PhotoTrashController.pageSize = 200） */
const TRASH_PAGE_SIZE = 200;
/** 网格单元目标尺寸（对齐 Flutter AppPhotoTrashBody 固定 cellSize = 100） */
const TRASH_CELL_SIZE = 100;
/** 网格间距（对齐 Flutter _spacing = 2） */
const TRASH_GRID_SPACING = 2;
/** 网格左右内边距（对齐 Flutter _horizontalPadding = 6） */
const TRASH_GRID_H_PADDING = 6;
/** 搜索防抖时长（对齐 Flutter onSearchChanged 500ms） */
const TRASH_SEARCH_DEBOUNCE = 500;

/**
 * 照片回收站控制器（对齐 Flutter PhotoTrashController 及其 parts：
 * base/data/selection/restore/delete/view_settings 的移动端相关状态）：
 * 分页加载（按 id 去重）+ 搜索防抖 + 类型过滤 + 排序 + 多选 + 恢复/删除/清空。
 */
@ObservedV2
export class PhotoTrashController {
  private api: PhotoTimelineApiService = new PhotoTimelineApiService();
  private searchTimer: number = -1;

  // ---- 数据状态 ----
  @Trace items: TrashPhotoItem[] = [];
  @Trace total: number = 0;
  @Trace page: number = 1;
  readonly pageSize: number = TRASH_PAGE_SIZE;
  @Trace keyword: string = '';
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;

  // ---- 过滤/排序 ----
  /** 文件类型过滤：all/photo/video/livephoto（对齐 Flutter fileType 取值） */
  @Trace fileType: string = 'all';
  /** 排序字段（Flutter 默认 in_trash_time） */
  @Trace sortField: string = 'in_trash_time';
  /** 排序顺序（Flutter 默认 desc） */
  @Trace sortOrder: string = 'desc';

  // ---- 多选状态 ----
  @Trace isMultiSelectMode: boolean = false;
  @Trace selectedIds: number[] = [];

  // ---- 布局信息（视图测量回填，对齐 TimelineController.updateLayout 模式） ----
  contentWidth: number = 0;
  @Trace crossAxisCount: number = 3;
  @Trace cellExtent: number = TRASH_CELL_SIZE;

  /** 初始化并加载首页（对齐 Flutter onInit → _initBase） */
  init(): void {
    void this.refresh();
  }

  // ================= 布局 =================

  /** 视图测量内容宽度后调用：按 cellSize=100/spacing=2 计算列数（对齐 AppPhotoTrashBody） */
  updateLayout(contentWidth: number): void {
    if (contentWidth <= 0) {
      return;
    }
    this.contentWidth = contentWidth;
    const inner = Math.max(0, contentWidth - TRASH_GRID_H_PADDING * 2);
    const count = Math.max(1, Math.floor((inner + TRASH_GRID_SPACING)
      / (TRASH_CELL_SIZE + TRASH_GRID_SPACING)));
    this.crossAxisCount = count;
    const usable = Math.max(0, inner - (count - 1) * TRASH_GRID_SPACING);
    this.cellExtent = usable / count;
  }

  // ================= 搜索 =================

  /** 搜索输入（500ms 防抖，对齐 Flutter onSearchChanged） */
  onSearchChanged(value: string): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      this.keyword = value;
      void this.refresh();
    }, TRASH_SEARCH_DEBOUNCE);
  }

  /** 清空搜索（对齐 Flutter clearSearch） */
  clearSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    this.keyword = '';
    void this.refresh();
  }

  // ================= 过滤/排序 =================

  /** 切换文件类型过滤（对齐 Flutter changeFileType） */
  changeFileType(type: string): void {
    if (this.fileType === type) {
      return;
    }
    this.fileType = type;
    void this.refresh();
  }

  /** 切换排序顺序（对齐 Flutter toggleSortOrder） */
  toggleSortOrder(): void {
    this.sortOrder = this.sortOrder === 'desc' ? 'asc' : 'desc';
    void this.refresh();
  }

  // ================= 数据加载 =================

  /** 刷新：重置分页从第一页加载（对齐 Flutter refreshList） */
  refresh(): Promise<void> {
    this.hasMore = true;
    this.page = 1;
    return this.loadPage(1, false);
  }

  /** 加载更多：追加下一页并按 id 去重（对齐 Flutter fetchTrashPhotos(loadMore: true)） */
  loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return Promise.resolve();
    }
    return this.loadPage(this.page + 1, true);
  }

  private async loadPage(pageNumber: number, append: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const fileTypeParam = this.fileType === 'all' ? '' : this.fileType;
      const res = await this.api.getTrashPhotoList(pageNumber, this.pageSize, fileTypeParam,
        this.keyword, this.sortField, this.sortOrder);
      if (!res.success || res.data === undefined) {
        if (append) {
          this.page = pageNumber - 1;
        }
        ToastUtil.show(res.message !== undefined && res.message.length > 0
          ? res.message : L10n.t('operation_failed', '操作失败'));
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
      this.page = pageNumber;
      // hasMore = 已加载数量 < 总数（对齐 Flutter photoItems.length < total）
      this.hasMore = this.items.length < this.total;
    } catch (_e) {
      if (append) {
        this.page = pageNumber - 1;
      }
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    } finally {
      this.isLoading = false;
    }
  }

  // ================= 多选 =================

  isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  /** 切换多选模式（对齐 Flutter toggleMultiSelectMode） */
  toggleMultiSelectMode(): void {
    this.isMultiSelectMode = !this.isMultiSelectMode;
    if (!this.isMultiSelectMode) {
      this.selectedIds = [];
    }
  }

  /** 强制退出多选并清空选中（对齐 Flutter exitMultiSelectMode） */
  exitMultiSelectMode(): void {
    this.isMultiSelectMode = false;
    this.selectedIds = [];
  }

  /** 切换单个选中（对齐 Flutter toggleSelection：空时自动退出多选） */
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

  /** 点击未选中项/长按：进入多选并选中（对齐 Flutter PhotoTrashItem onTap/onLongPress 非多选分支） */
  selectSingle(id: number): void {
    if (this.selectedIds.indexOf(id) < 0) {
      this.selectedIds = this.selectedIds.concat([id]);
    }
    this.isMultiSelectMode = true;
  }

  /** 全选/取消全选（对齐 Flutter toggleSelectAll） */
  toggleSelectAll(): void {
    if (this.items.length > 0 && this.selectedIds.length === this.items.length) {
      this.selectedIds = [];
      this.isMultiSelectMode = false;
    } else {
      const ids: number[] = [];
      for (const it of this.items) {
        ids.push(it.id);
      }
      this.selectedIds = ids;
      this.isMultiSelectMode = true;
    }
  }

  /** 已选中的照片条目（按 items 顺序） */
  getSelectedItems(): TrashPhotoItem[] {
    const ids = new Set<number>(this.selectedIds);
    const out: TrashPhotoItem[] = [];
    for (const it of this.items) {
      if (ids.has(it.id)) {
        out.push(it);
      }
    }
    return out;
  }

  /** 选中项中是否包含 livephoto 关联文件（删除弹窗显示用，对齐 Flutter hasLivePhoto） */
  hasLivePhotoSelected(): boolean {
    for (const it of this.getSelectedItems()) {
      if (it.liveFilename.length > 0) {
        return true;
      }
    }
    return false;
  }

  /** 选中项中是否包含 raw 关联文件（删除弹窗显示用，对齐 Flutter hasRawFile） */
  hasRawFileSelected(): boolean {
    for (const it of this.getSelectedItems()) {
      if (it.rawFilename.length > 0) {
        return true;
      }
    }
    return false;
  }

  // ================= 恢复/删除/清空 =================

  /** 恢复选中的照片（对齐 Flutter restoreSelected：无确认直接恢复） */
  async restoreSelected(ids: number[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    try {
      const ok = await this.api.restoreFromTrash(ids);
      if (ok) {
        ToastUtil.show(L10n.t('operation_success', '操作成功'));
        this.exitMultiSelectMode();
        await this.refresh();
      } else {
        ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      }
    } catch (_e) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 恢复全部照片（对齐 Flutter restoreAll 的确认后逻辑；确认弹窗由页面调用 DialogUtil 实现） */
  async restoreAll(): Promise<void> {
    try {
      const ok = await this.api.restoreAllFromTrash();
      if (ok) {
        ToastUtil.show(L10n.t('operation_success', '操作成功'));
        await this.refresh();
      } else {
        ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      }
    } catch (_e) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 物理删除选中的照片（对齐 Flutter _deleteSelectedPhotos；确认弹窗由页面实现） */
  async deleteSelected(ids: number[], recycle: boolean, deleteLivePhotoFile: boolean,
    deleteRawFile: boolean): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    try {
      const res = await this.api.deleteFromTrash(ids, recycle, deleteLivePhotoFile, deleteRawFile);
      if (res.success) {
        ToastUtil.show(L10n.t('delete_success', '删除成功'));
        this.exitMultiSelectMode();
        await this.refresh();
      } else {
        ToastUtil.show(res.code === 403
          ? L10n.t('permission_denied', '权限被拒绝')
          : L10n.t('delete_failed', '删除失败'));
      }
    } catch (_e) {
      ToastUtil.show(L10n.t('delete_failed', '删除失败'));
    }
  }

  /** 清空回收站（对齐 Flutter _performEmptyTrash；确认弹窗由页面实现） */
  async emptyTrash(recycle: boolean, deleteLivePhotoFile: boolean, deleteRawFile: boolean): Promise<void> {
    try {
      const res = await this.api.emptyTrash(recycle, deleteLivePhotoFile, deleteRawFile);
      if (res.success) {
        ToastUtil.show(L10n.t('delete_success', '删除成功'));
        await this.refresh();
      } else {
        ToastUtil.show(res.code === 403
          ? L10n.t('permission_denied', '权限被拒绝')
          : L10n.t('delete_failed', '删除失败'));
      }
    } catch (_e) {
      ToastUtil.show(L10n.t('delete_failed', '删除失败'));
    }
  }
}
