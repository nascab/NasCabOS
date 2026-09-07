import { DialogUtil } from '../../common/DialogUtil';
import { L10n } from '../../core/localization/L10n';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { VideoHomeData, VideoHomeItemBean, parseVideoHomeItemBean } from '../models/VideoModels';
import { VideoHomeApiService } from '../service/VideoApiServices';

/**
 * 影音主页控制器（对齐 Flutter AppVideoHomePageController）：
 * 拉取首页数据（推荐/最近播放/最近添加电影/电视剧）；
 * 管理员且未配置来源路径时弹提示引导前往影音设置（仅提示一次）。
 */
export class VideoHomeController {
  /** 打开影音设置页（由视图注入，避免控制器依赖页面组件） */
  onOpenSettings: () => void = (): void => {
    NavUtil.push(AppRouter.VIDEO_SETTINGS, new Object());
  };
  /** 数据变化回调（由视图注入以刷新 UI） */
  onDataChanged: () => void = (): void => {
  };

  recommend: VideoHomeItemBean[] = [];
  recentPlay: VideoHomeItemBean[] = [];
  recentAddMovie: VideoHomeItemBean[] = [];
  recentAddTv: VideoHomeItemBean[] = [];
  loading: boolean = false;
  private alertWhenNoSourcePath: boolean;
  private sourceEmptyDialogShown: boolean = false;

  constructor(alertWhenNoSourcePath: boolean = false) {
    this.alertWhenNoSourcePath = alertWhenNoSourcePath;
  }

  async refreshAll(showLoading: boolean = false, recommendLimit: number = 11,
    recentPlayLimit: number = 20, recentAddLimit: number = 20): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.onDataChanged();
    try {
      const res = await new VideoHomeApiService().getHomeData(
        recommendLimit, recentPlayLimit, recentAddLimit);
      if (!res.success || res.data === undefined) {
        return;
      }
      const data: VideoHomeData = res.data;
      this.recommend = data.recommend;
      this.recentPlay = data.recentPlay;
      this.recentAddMovie = data.recentAddMovie;
      this.recentAddTv = data.recentAddTv;

      // 仅当接口成功且未设置来源时提示，避免网络失败时误弹（对齐 Flutter）
      if (data.sourceList.length === 0 && CurrentUserStore.getInstance().isAdmin) {
        if (this.alertWhenNoSourcePath && !this.sourceEmptyDialogShown) {
          this.sourceEmptyDialogShown = true;
          DialogUtil.showInfoDialog(L10n.t('tip', '提示'),
            L10n.t('path_no_set', '尚未设置媒体文件路径'), '', (): void => {
              this.onOpenSettings();
            });
        }
      } else {
        this.sourceEmptyDialogShown = false;
      }
    } finally {
      this.loading = false;
      this.onDataChanged();
    }
  }

  /** 外部删除事件：从各分区移除对应条目（对齐 _handleExternalDelete） */
  handleExternalDelete(indexId: number): void {
    if (indexId <= 0) {
      return;
    }
    this.recommend = this.removeFrom(this.recommend, indexId);
    this.recentPlay = this.removeFrom(this.recentPlay, indexId);
    this.recentAddMovie = this.removeFrom(this.recentAddMovie, indexId);
    this.recentAddTv = this.removeFrom(this.recentAddTv, indexId);
    this.onDataChanged();
  }

  /** 收藏状态变化：同步更新所有分区中的条目（对齐 handleFavoriteChanged） */
  handleFavoriteChanged(indexId: number, isFav: boolean): void {
    this.recommend = this.updateFavorite(this.recommend, indexId, isFav);
    this.recentPlay = this.updateFavorite(this.recentPlay, indexId, isFav);
    this.recentAddMovie = this.updateFavorite(this.recentAddMovie, indexId, isFav);
    this.recentAddTv = this.updateFavorite(this.recentAddTv, indexId, isFav);
    this.onDataChanged();
  }

  isEmpty(): boolean {
    return this.recommend.length === 0 && this.recentPlay.length === 0
      && this.recentAddMovie.length === 0 && this.recentAddTv.length === 0;
  }

  private removeFrom(list: VideoHomeItemBean[], id: number): VideoHomeItemBean[] {
    return list.filter((e: VideoHomeItemBean) => e.id !== id);
  }

  private updateFavorite(list: VideoHomeItemBean[], id: number, isFav: boolean): VideoHomeItemBean[] {
    let changed = false;
    const next = list.map((e: VideoHomeItemBean): VideoHomeItemBean => {
      if (e.id === id && e.isFavorite !== isFav) {
        changed = true;
        const copy = parseVideoHomeItemBean(e as Object);
        copy.isFavorite = isFav;
        return copy;
      }
      return e;
    });
    return changed ? next : list;
  }
}
