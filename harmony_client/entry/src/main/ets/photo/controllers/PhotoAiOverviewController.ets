import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { AiOverviewResult, PhotoAiOverviewApiService } from '../service/PhotoAiOverviewApiService';

/**
 * AI 概览控制器（对齐 Flutter AppPhotoAiController）：
 * 加载人脸/场景预览与去重开关，供 AI 主页展示。
 */
@ObservedV2
export class PhotoAiOverviewController {
  private api: PhotoAiOverviewApiService = new PhotoAiOverviewApiService();

  @Trace isLoading: boolean = false;
  @Trace overview: AiOverviewResult | undefined = undefined;

  get faceEnabled(): boolean {
    return this.overview ? this.overview.faces.faceEnable : true;
  }

  get sceneEnabled(): boolean {
    return this.overview ? this.overview.scenes.placeEnable : true;
  }

  get similarEnabled(): boolean {
    return this.overview ? this.overview.similarEnable : true;
  }

  init(): void {
    void this.refreshOverview(false);
  }

  /** 刷新概览（对齐 Flutter refreshOverview） */
  async refreshOverview(showToastOnError: boolean = true): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await this.api.fetchOverview(20);
      if (!res.success || res.data === undefined) {
        if (showToastOnError) {
          ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        }
        return;
      }
      this.overview = res.data;
    } finally {
      this.isLoading = false;
    }
  }
}
