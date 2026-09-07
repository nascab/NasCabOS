import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { CacheKeys } from '../../core/storage/CacheKeys';
import { PhotoAiSettingsApiService } from '../service/PhotoAiSettingsApiService';

/**
 * 预览设置控制器（对齐 Flutter PhotoPreviewSettingsController）：
 * 预览尺寸服务端配置 + WiFi 下加载原图本地开关。
 */
@ObservedV2
export class PhotoPreviewSettingsController {
  static readonly allowedSizes: string[] = [
    'origin', '8000', '7000', '6000', '5000', '4000', '3000', '2000', '1000'
  ];

  private api: PhotoAiSettingsApiService = new PhotoAiSettingsApiService();

  @Trace loading: boolean = false;
  @Trace previewSize: string = 'origin';
  @Trace wifiOriginalEnabled: boolean = false;

  init(): void {
    void this.fetchSettings(false);
    this.wifiOriginalEnabled = PreferencesStore.getInstance()
      .getBool(CacheKeys.PHOTO_PREVIEW_WIFI_ORIGINAL, false);
  }

  setWifiOriginalEnabled(value: boolean): void {
    this.wifiOriginalEnabled = value;
    void PreferencesStore.getInstance().setBool(CacheKeys.PHOTO_PREVIEW_WIFI_ORIGINAL, value);
  }

  /** 拉取预览配置（对齐 Flutter fetchSettings） */
  async fetchSettings(showLoading: boolean = true): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    if (showLoading) {
      DialogUtil.showLoading(L10n.loading);
    }
    try {
      const res = await this.api.getPreviewConfig();
      if (!res.success) {
        if (showLoading) {
          ToastUtil.show(res.message ?? L10n.t('network_failure', '网络请求失败'));
        }
        return;
      }
      const raw = res.data?.['previewSize'];
      const s = raw === undefined || raw === null ? '' : `${raw}`.trim();
      this.previewSize = PhotoPreviewSettingsController.allowedSizes.includes(s) ? s : 'origin';
    } finally {
      this.loading = false;
      if (showLoading) {
        DialogUtil.dismissLoading();
      }
    }
  }

  /** 更新预览尺寸（对齐 Flutter updatePreviewSize：成功提示） */
  async updatePreviewSize(next: string): Promise<void> {
    const normalized = PhotoPreviewSettingsController.allowedSizes.includes(next) ? next : 'origin';
    const prev = this.previewSize;
    this.previewSize = normalized;
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.setPreviewSize(normalized);
      if (!res.success) {
        this.previewSize = prev;
        ToastUtil.show(res.message ?? L10n.t('network_failure', '网络请求失败'));
        return;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    } finally {
      DialogUtil.dismissLoading();
    }
  }
}
