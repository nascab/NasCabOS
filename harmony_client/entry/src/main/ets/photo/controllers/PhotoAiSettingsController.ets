import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { APIResponse } from '../../core/network/APIResponse';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { PhotoAiSettingsApiService } from '../service/PhotoAiSettingsApiService';

type Obj = Record<string, Object>;

/** 解析 int 字段（对齐 Flutter controller 内 parseInt） */
function parseIntField(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Math.floor(v);
  }
  const parsed = parseInt(`${v}`, 10);
  return isNaN(parsed) ? 0 : parsed;
}

function clamp(v: number, min: number, max: number): number {
  return Math.min(Math.max(v, min), max);
}

/**
 * AI 设置控制器（对齐 Flutter PhotoAiSettingsController）：
 * 加载 AI 配置 + 各开关乐观更新（失败回滚）+ 重置去重 + 自动隐藏阈值。
 */
@ObservedV2
export class PhotoAiSettingsController {
  private api: PhotoAiSettingsApiService = new PhotoAiSettingsApiService();

  @Trace loading: boolean = false;
  @Trace ocrEnabled: boolean = false;
  @Trace faceEnabled: boolean = false;
  @Trace placeEnabled: boolean = false;
  @Trace similarEnabled: boolean = false;
  /** GPU 优先默认开启（对齐 Flutter gpuPrefer 默认 true） */
  @Trace gpuPrefer: boolean = true;
  @Trace faceMinShowCount: number = 0;

  @Trace ocrProgress: number = 0;
  @Trace placeProgress: number = 0;
  @Trace faceProgress: number = 0;
  @Trace similarScanProgress: number = 0;
  @Trace similarCompareProgress: number = 0;

  get canEdit(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  init(): void {
    void this.fetchSettings(false);
  }

  /** 拉取 AI 配置（对齐 Flutter fetchSettings） */
  async fetchSettings(showLoading: boolean = true): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    if (showLoading) {
      DialogUtil.showLoading(L10n.loading);
    }
    try {
      const res = await this.api.getAiConfig();
      if (!res.success) {
        if (showLoading) {
          ToastUtil.show(res.message ?? L10n.t('network_failure', '网络请求失败'));
        }
        return;
      }
      const data = (res.data ?? {}) as Obj;
      this.ocrEnabled = this.parseEnable(data['ocrEnable']);
      this.faceEnabled = this.parseEnable(data['faceEnable']);
      this.placeEnabled = this.parseEnable(data['placeEnable']);
      this.similarEnabled = this.parseEnable(data['similarEnable']);
      this.gpuPrefer = this.parseEnable(data['gpuPrefer']);
      const minCount = parseIntField(data['faceMinShowCount']);
      this.faceMinShowCount = minCount > 0 ? minCount : 0;

      const aiProgress = data['aiProgress'];
      if (aiProgress !== undefined && aiProgress !== null && typeof aiProgress === 'object') {
        const p = aiProgress as Obj;
        const face = p['face'];
        const place = p['place'];
        const ocr = p['ocr'];
        this.faceProgress = face !== undefined && face !== null && typeof face === 'object'
          ? clamp(parseIntField((face as Obj)['percent']), 0, 100) : 0;
        this.placeProgress = place !== undefined && place !== null && typeof place === 'object'
          ? clamp(parseIntField((place as Obj)['percent']), 0, 100) : 0;
        this.ocrProgress = ocr !== undefined && ocr !== null && typeof ocr === 'object'
          ? clamp(parseIntField((ocr as Obj)['percent']), 0, 100) : 0;
      } else {
        this.faceProgress = 0;
        this.placeProgress = 0;
        this.ocrProgress = 0;
      }

      const similarProgress = data['similarProgress'];
      if (similarProgress !== undefined && similarProgress !== null && typeof similarProgress === 'object') {
        const sp = similarProgress as Obj;
        const scan = sp['scan'];
        const compare = sp['compare'];
        this.similarScanProgress = scan !== undefined && scan !== null && typeof scan === 'object'
          ? clamp(parseIntField((scan as Obj)['percent']), 0, 100) : 0;
        this.similarCompareProgress = compare !== undefined && compare !== null && typeof compare === 'object'
          ? clamp(parseIntField((compare as Obj)['percent']), 0, 100) : 0;
      } else {
        this.similarScanProgress = 0;
        this.similarCompareProgress = 0;
      }
    } finally {
      this.loading = false;
      if (showLoading) {
        DialogUtil.dismissLoading();
      }
    }
  }

  private parseEnable(v: Object | undefined): boolean {
    return v !== undefined && v !== null && (`${v}` === '1' || `${v}` === 'true' || v === true);
  }

  private guardAdmin(): boolean {
    if (!this.canEdit) {
      ToastUtil.show(L10n.t('photo_ai_admin_only', '仅管理员可修改'));
      return false;
    }
    return true;
  }

  /** 通用开关切换：乐观更新 + 失败回滚（对齐 Flutter toggleXxx） */
  private async toggleWithRollback(current: boolean, next: boolean,
    apply: (v: boolean) => void, call: () => Promise<APIResponse<Record<string, Object>>>): Promise<void> {
    apply(next);
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await call();
      if (!res.success) {
        apply(current);
        ToastUtil.show(res.message ?? L10n.t('network_failure', '网络请求失败'));
      }
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  async toggleOcr(value: boolean): Promise<void> {
    if (!this.guardAdmin()) {
      return;
    }
    const prev = this.ocrEnabled;
    await this.toggleWithRollback(prev, value, (v: boolean) => {
      this.ocrEnabled = v;
    }, (): Promise<APIResponse<Record<string, Object>>> => this.api.setAiOcrEnable(value));
  }

  async toggleFace(value: boolean): Promise<void> {
    if (!this.guardAdmin()) {
      return;
    }
    const prev = this.faceEnabled;
    await this.toggleWithRollback(prev, value, (v: boolean) => {
      this.faceEnabled = v;
    }, (): Promise<APIResponse<Record<string, Object>>> => this.api.setAiFaceEnable(value));
  }

  async togglePlace(value: boolean): Promise<void> {
    if (!this.guardAdmin()) {
      return;
    }
    const prev = this.placeEnabled;
    await this.toggleWithRollback(prev, value, (v: boolean) => {
      this.placeEnabled = v;
    }, (): Promise<APIResponse<Record<string, Object>>> => this.api.setAiPlaceEnable(value));
  }

  async toggleSimilar(value: boolean): Promise<void> {
    if (!this.guardAdmin()) {
      return;
    }
    const prev = this.similarEnabled;
    await this.toggleWithRollback(prev, value, (v: boolean) => {
      this.similarEnabled = v;
    }, (): Promise<APIResponse<Record<string, Object>>> => this.api.setAiSimilarEnable(value));
  }

  async toggleGpu(value: boolean): Promise<void> {
    if (!this.guardAdmin()) {
      return;
    }
    const prev = this.gpuPrefer;
    await this.toggleWithRollback(prev, value, (v: boolean) => {
      this.gpuPrefer = v;
    }, (): Promise<APIResponse<Record<string, Object>>> => this.api.setAiGpuPrefer(value));
  }

  /** 重置相似照片去重扫描（确认弹窗由页面触发，对齐 Flutter resetSimilar 确认后逻辑） */
  async resetSimilar(): Promise<void> {
    if (!this.guardAdmin()) {
      return;
    }
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.resetSimilar();
      if (!res.success) {
        ToastUtil.show(res.message ?? L10n.t('network_failure', '网络请求失败'));
        return;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  /** 设置自动隐藏阈值（乐观更新 + 失败回滚，对齐 Flutter setFaceMinShowCount） */
  async setFaceMinShowCount(value: number): Promise<void> {
    if (!this.guardAdmin()) {
      return;
    }
    const next = value < 0 ? 0 : value;
    const prev = this.faceMinShowCount;
    this.faceMinShowCount = next;
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.setAiFaceMinShowCount(next);
      if (!res.success) {
        this.faceMinShowCount = prev;
        ToastUtil.show(res.message ?? L10n.t('network_failure', '网络请求失败'));
      }
    } finally {
      DialogUtil.dismissLoading();
    }
  }
}

