import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { AppRouter } from '../../router/AppRouter';
import { NavUtil } from '../../common/NavUtil';
import { ApiUrls } from '../../core/network/ApiUrls';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { AiFaceItem } from '../models/PhotoAiModels';
import { PhotoAiFacesApiService } from '../service/PhotoAiFacesApiService';
import { PhotoAiSettingsApiService } from '../service/PhotoAiSettingsApiService';
import { PhotoTimelinePageParam } from '../views/timeline/PhotoTimelinePage';

/** 每页数量（对齐 Flutter AiFacesController.pageSize = 60） */
const FACES_PAGE_SIZE = 60;
/** 搜索防抖时长（对齐 Flutter updateKeyword 300ms） */
const FACES_SEARCH_DEBOUNCE = 300;

/**
 * AI 人脸控制器（对齐 Flutter AiFacesController 的移动端状态）：
 * 分页加载 + 状态过滤（visiable/hide/all）+ 搜索防抖 + 多选 + 隐藏/合并/重命名/重置。
 */
@ObservedV2
export class PhotoAiFacesController {
  private api: PhotoAiFacesApiService = new PhotoAiFacesApiService();
  private settingsApi: PhotoAiSettingsApiService = new PhotoAiSettingsApiService();
  private searchTimer: number = -1;

  // ---- 数据状态 ----
  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace items: AiFaceItem[] = [];
  @Trace page: number = 1;
  @Trace total: number = 0;
  readonly pageSize: number = FACES_PAGE_SIZE;
  /** 人脸识别功能开关（服务端返回 faceEnable） */
  @Trace faceEnabled: boolean = true;
  /** 状态过滤：visiable/hide/all（对齐 Flutter statusFilter） */
  @Trace statusFilter: string = 'visiable';
  @Trace keyword: string = '';

  // ---- 多选状态 ----
  @Trace selectionMode: boolean = false;
  @Trace selectedFaceIds: number[] = [];

  init(): void {
    void this.refreshFaces();
  }

  // ================= 数据加载 =================

  /** 刷新（对齐 Flutter refreshFaces：刷新人脸头像时间戳 + 重置分页） */
  refreshFaces(): Promise<void> {
    ApiUrls.refreshFaceImageTimestamp();
    this.hasMore = true;
    this.page = 1;
    return this.loadFaces(1, false);
  }

  /** 加载更多（对齐 Flutter loadMore） */
  loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return Promise.resolve();
    }
    return this.loadFaces(this.page + 1, true);
  }

  private async loadFaces(pageNumber: number, append: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await this.api.listFaces(pageNumber, this.pageSize, this.statusFilter, this.keyword);
      if (!res.success || res.data === undefined) {
        return;
      }
      const data = res.data;
      this.faceEnabled = data.faceEnable;
      if (!data.faceEnable) {
        this.exitSelectionMode();
        this.items = [];
        this.total = 0;
        this.page = 1;
        this.hasMore = false;
        return;
      }
      if (append) {
        const existing = new Set<number>();
        for (const e of this.items) {
          existing.add(e.faceId);
        }
        const next = this.items.slice();
        for (const e of data.items) {
          if (!existing.has(e.faceId)) {
            next.push(e);
          }
        }
        this.items = next;
      } else {
        this.items = data.items;
      }
      this.total = data.total;
      this.page = data.page;
      const size = data.pageSize > 0 ? data.pageSize : this.pageSize;
      const maxPage = data.total <= 0 ? 1 : Math.floor((data.total + size - 1) / size);
      this.hasMore = data.page < maxPage;
    } finally {
      this.isLoading = false;
    }
  }

  // ================= 过滤/搜索 =================

  /** 切换状态过滤（对齐 Flutter setStatusFilter：退出多选并刷新） */
  setStatusFilter(status: string): void {
    if (this.statusFilter === status) {
      return;
    }
    this.statusFilter = status;
    this.exitSelectionMode();
    void this.refreshFaces();
  }

  /** 搜索输入（300ms 防抖，对齐 Flutter updateKeyword） */
  onSearchChanged(value: string): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      const next = value.trim();
      if (this.keyword === next) {
        return;
      }
      this.keyword = next;
      this.exitSelectionMode();
      void this.refreshFaces();
    }, FACES_SEARCH_DEBOUNCE);
  }

  /** 清空搜索（对齐 Flutter clearKeyword） */
  clearSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (this.keyword.length === 0) {
      return;
    }
    this.keyword = '';
    this.exitSelectionMode();
    void this.refreshFaces();
  }

  // ================= 功能开关 =================

  /** 开启人脸识别（对齐 Flutter enableFaceRecognition：仅管理员） */
  async enableFaceRecognition(): Promise<void> {
    if (!CurrentUserStore.getInstance().isAdmin) {
      ToastUtil.show(L10n.t('photo_ai_admin_only', '仅管理员可修改'));
      return;
    }
    const res = await this.settingsApi.setAiFaceEnable(true);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    await this.refreshFaces();
  }

  // ================= 多选 =================

  exitSelectionMode(): void {
    this.selectionMode = false;
    this.selectedFaceIds = [];
  }

  /** 切换单个人脸选中（对齐 Flutter toggleSelected：空时自动退出多选） */
  toggleSelected(faceId: number): void {
    if (faceId <= 0) {
      return;
    }
    const next = this.selectedFaceIds.slice();
    const idx = next.indexOf(faceId);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(faceId);
    }
    this.selectedFaceIds = next;
    if (next.length > 0) {
      this.selectionMode = true;
    }
    if (next.length === 0) {
      this.exitSelectionMode();
    }
  }

  isSelected(faceId: number): boolean {
    return this.selectedFaceIds.indexOf(faceId) >= 0;
  }

  // ================= 批量动作 =================

  /** 批量下载（对齐 Flutter downloadSelectedFaces：依赖下载中心，迁移后接入） */
  downloadSelected(): void {
    ToastUtil.show(L10n.t('feature_coming_soon', '功能开发中'));
  }

  /** 单个人脸重命名（对齐 Flutter renameFace：成功后原位更新条目） */
  async renameFace(face: AiFaceItem, name: string): Promise<void> {
    const v = name.trim();
    if (v.length === 0 || v.length > 30) {
      return;
    }
    const res = await this.api.updateFaceName(face.faceId, v);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    const next = this.items.slice();
    for (let i = 0; i < next.length; i++) {
      if (next[i].faceId === face.faceId) {
        const updated = new AiFaceItem();
        updated.faceId = face.faceId;
        updated.faceCount = face.faceCount;
        updated.coverFileHash = face.coverFileHash;
        updated.name = v;
        updated.isHide = face.isHide;
        next[i] = updated;
        break;
      }
    }
    this.items = next;
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 设置单个人脸显示/隐藏（对齐 Flutter setFaceHidden） */
  async setFaceHidden(face: AiFaceItem, hide: boolean): Promise<void> {
    const res = await this.api.setFaceStatus(face.faceId, hide);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    this.exitSelectionMode();
    await this.refreshFaces();
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 批量设置显示/隐藏（对齐 Flutter batchSetHidden：任一失败提示失败） */
  async batchSetHidden(hide: boolean): Promise<void> {
    const ids = this.selectedFaceIds.slice();
    if (ids.length === 0) {
      return;
    }
    let failed = false;
    for (const id of ids) {
      const res = await this.api.setFaceStatus(id, hide);
      if (!res.success) {
        failed = true;
      }
    }
    if (failed) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    } else {
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    }
    this.exitSelectionMode();
    await this.refreshFaces();
  }

  /** 合并选中人脸（对齐 Flutter confirmAndMergeSelected 的确认后逻辑，弹窗由页面实现） */
  async mergeSelected(): Promise<void> {
    const ids = this.selectedFaceIds.slice();
    if (ids.length < 2) {
      return;
    }
    const res = await this.api.mergeFaces(ids);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    this.exitSelectionMode();
    await this.refreshFaces();
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 重置人脸识别（对齐 Flutter confirmAndResetFaces 的确认后逻辑，弹窗由页面实现） */
  async resetFaces(): Promise<boolean> {
    const res = await this.api.resetFaces();
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return false;
    }
    this.exitSelectionMode();
    await this.refreshFaces();
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    return true;
  }

  /** 读取当前自动隐藏阈值（对齐 Flutter openAutoHideSettings 的加载逻辑） */
  async loadFaceMinShowCount(): Promise<number> {
    let current = 0;
    try {
      const res = await this.settingsApi.getAiConfig();
      if (res.success && res.data !== undefined) {
        const parsed = parseInt(`${res.data['faceMinShowCount']}`, 10);
        if (!isNaN(parsed) && parsed > 0) {
          current = parsed;
        }
      }
    } catch (_e) {
      current = 0;
    }
    return current;
  }

  /** 保存自动隐藏阈值（对齐 Flutter openAutoHideSettings 的保存逻辑，弹窗由页面实现） */
  async saveFaceMinShowCount(value: number): Promise<void> {
    const res = await this.settingsApi.setAiFaceMinShowCount(value);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    await this.refreshFaces();
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  // ================= 展示辅助 =================

  /** 人脸展示名（对齐 Flutter faceDisplayName：无名显示 "(未命名)"） */
  faceDisplayName(face: AiFaceItem): string {
    const name = face.name.trim();
    return name.length > 0 ? name : `(${L10n.t('face_unnamed', '未命名')})`;
  }

  /** 打开人脸照片时间线（对齐 Flutter openFace 移动端分支：推入时间线页） */
  openFace(face: AiFaceItem): void {
    const p = new PhotoTimelinePageParam();
    p.title = `${L10n.t('photo_menu_ai_face', '人脸识别')}-${this.faceDisplayName(face)}`;
    p.listType = 'timeline';
    p.faceId = face.faceId;
    NavUtil.push(AppRouter.PHOTO_TIMELINE, p);
  }
}
