import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { AppRouter } from '../../router/AppRouter';
import { NavUtil } from '../../common/NavUtil';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { AiSceneItem } from '../models/PhotoAiModels';
import { PhotoAiScenesApiService } from '../service/PhotoAiScenesApiService';
import { PhotoAiSettingsApiService } from '../service/PhotoAiSettingsApiService';
import { PhotoTimelinePageParam } from '../views/timeline/PhotoTimelinePage';

/** 搜索防抖时长（对齐 Flutter updateKeyword 300ms） */
const SCENES_SEARCH_DEBOUNCE = 300;

/**
 * AI 场景控制器（对齐 Flutter AiScenesController 的移动端状态）：
 * 一次加载全部 + 客户端状态/关键字过滤 + 隐藏/重置。
 */
@ObservedV2
export class PhotoAiScenesController {
  private api: PhotoAiScenesApiService = new PhotoAiScenesApiService();
  private settingsApi: PhotoAiSettingsApiService = new PhotoAiSettingsApiService();
  private searchTimer: number = -1;

  // ---- 数据状态 ----
  @Trace isLoading: boolean = false;
  /** 全量数据（对齐 Flutter allItems） */
  private allItems: AiSceneItem[] = [];
  /** 过滤后展示数据（对齐 Flutter items） */
  @Trace items: AiSceneItem[] = [];
  /** 场景识别功能开关（服务端返回 placeEnable） */
  @Trace placeEnabled: boolean = true;
  /** 状态过滤：visiable/hide/all（对齐 Flutter statusFilter） */
  @Trace statusFilter: string = 'visiable';
  @Trace keyword: string = '';

  init(): void {
    void this.refreshScenes();
  }

  // ================= 数据加载 =================

  /** 刷新（对齐 Flutter refreshScenes：拉取全部场景后客户端过滤） */
  async refreshScenes(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await this.api.listScenes('all');
      if (!res.success || res.data === undefined) {
        return;
      }
      const data = res.data;
      this.placeEnabled = data.placeEnable;
      if (!data.placeEnable) {
        this.allItems = [];
        this.items = [];
        return;
      }
      this.allItems = data.items;
      this.applyFilter();
    } finally {
      this.isLoading = false;
    }
  }

  /** 客户端过滤（对齐 Flutter _applyFilter：状态 + 关键字） */
  private applyFilter(): void {
    const filter = this.statusFilter;
    const q = this.keyword.trim().toLowerCase();
    const next: AiSceneItem[] = [];
    for (const e of this.allItems) {
      let match = true;
      if (filter !== 'all') {
        match = (filter === 'hide' || filter === 'hidden') ? e.isHide : !e.isHide;
      }
      if (match && q.length > 0) {
        match = e.placeName.toLowerCase().indexOf(q) >= 0;
      }
      if (match) {
        next.push(e);
      }
    }
    this.items = next;
  }

  // ================= 过滤/搜索 =================

  /** 切换状态过滤（对齐 Flutter setStatusFilter） */
  setStatusFilter(status: string): void {
    if (this.statusFilter === status) {
      return;
    }
    this.statusFilter = status;
    this.applyFilter();
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
      this.applyFilter();
    }, SCENES_SEARCH_DEBOUNCE);
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
    this.applyFilter();
  }

  // ================= 动作 =================

  /** 开启场景识别（对齐 Flutter enableSceneRecognition：仅管理员） */
  async enableSceneRecognition(): Promise<void> {
    if (!CurrentUserStore.getInstance().isAdmin) {
      ToastUtil.show(L10n.t('photo_ai_admin_only', '仅管理员可修改'));
      return;
    }
    const res = await this.settingsApi.setAiPlaceEnable(true);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    await this.refreshScenes();
  }

  /** 设置场景显示/隐藏（对齐 Flutter setSceneHidden：原位更新 allItems 后重过滤） */
  async setSceneHidden(scene: AiSceneItem, hide: boolean): Promise<void> {
    const res = await this.api.setSceneStatus(scene.placeNameRaw, hide);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    const next = this.allItems.slice();
    for (let i = 0; i < next.length; i++) {
      const e = next[i];
      if (e.placeNameRaw !== scene.placeNameRaw) {
        continue;
      }
      const updated = new AiSceneItem();
      updated.placeName = e.placeName;
      updated.placeNameRaw = e.placeNameRaw;
      updated.photoCount = e.photoCount;
      updated.isHide = hide;
      updated.coverFullpath = e.coverFullpath;
      next[i] = updated;
    }
    this.allItems = next;
    this.applyFilter();
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 重置场景识别（对齐 Flutter confirmAndResetScenes 的确认后逻辑，弹窗由页面实现） */
  async resetScenes(): Promise<boolean> {
    const res = await this.api.resetScenes();
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return false;
    }
    await this.refreshScenes();
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    return true;
  }

  // ================= 展示辅助 =================

  /** 场景展示名（对齐 Flutter openScene：无名显示 scene_unnamed） */
  sceneDisplayName(scene: AiSceneItem): string {
    const name = scene.placeName.trim();
    return name.length > 0 ? name : L10n.t('scene_unnamed', '未命名场景');
  }

  /** 打开场景照片时间线（对齐 Flutter openScene 移动端分支：推入时间线页） */
  openScene(scene: AiSceneItem): void {
    const p = new PhotoTimelinePageParam();
    p.title = `${L10n.t('photo_menu_ai_scene', '场景识别')}-${this.sceneDisplayName(scene)}`;
    p.listType = 'timeline';
    p.placeName = scene.placeNameRaw;
    NavUtil.push(AppRouter.PHOTO_TIMELINE, p);
  }
}
