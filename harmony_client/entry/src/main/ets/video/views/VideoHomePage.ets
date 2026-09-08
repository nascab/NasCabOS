import { AppTheme } from '../../core/theme/AppTheme';
import { L10n } from '../../core/localization/L10n';
import { EmptyState } from '../../common/components/EmptyState';
import { AppEventBus } from '../../common/AppEventBus';
import { VideoHomeController } from '../controllers/VideoHomeController';
import { VideoHomeItemBean } from '../models/VideoModels';
import { VideoItemSyncService } from '../utils/VideoItemUtils';
import { VideoHomeSection } from '../components/VideoHomeSection';
import { VideoRecommendSwiper } from '../components/VideoRecommendSwiper';

/**
 * 影音主页内容（对齐 Flutter AppVideoHomePage）：
 * 推荐轮播 + 最近播放/最近添加电影/电视剧横向区块，支持下拉刷新与外部删除联动；
 * 管理员未配置来源路径时弹提示（由控制器处理）。
 */
@ComponentV2
export struct VideoHomePage {
  /** 打开电影列表（由主入口注入） */
  @Param onOpenMovie: () => void = (): void => {
  };
  /** 打开电视剧列表 */
  @Param onOpenTv: () => void = (): void => {
  };
  /** 打开历史列表 */
  @Param onOpenHistory: () => void = (): void => {
  };
  /** 打开影音设置页（来源为空提示后跳转，由主入口注入） */
  @Param onOpenSettings: () => void = (): void => {
  };
  @Local tick: number = 0;
  private ctrl: VideoHomeController = new VideoHomeController(true);
  private deletedListener: (data: string) => void = (data: string): void => {
    const id = Number(data);
    if (Number.isFinite(id)) {
      this.ctrl.handleExternalDelete(id);
    }
  };

  aboutToAppear(): void {
    this.ctrl.onDataChanged = (): void => {
      this.tick++;
    };
    this.ctrl.onOpenSettings = this.onOpenSettings;
    AppEventBus.on(VideoItemSyncService.EVENT_VIDEO_ITEM_DELETED, this.deletedListener);
    void this.ctrl.refreshAll(false);
  }

  aboutToDisappear(): void {
    AppEventBus.off(VideoItemSyncService.EVENT_VIDEO_ITEM_DELETED, this.deletedListener);
  }

  build() {
    Stack() {
      Refresh({
        refreshing: false
      }) {
        Scroll() {
          Column() {
            if (this.ctrl.recommend.length > 0) {
              Column() {
                VideoRecommendSwiper({ items: this.ctrl.recommend })
              }
              // 轮播沉浸式：背景图绘制延伸到状态栏后面（对齐 Flutter 首页全屏轮播）
              .width('100%')
              .height('52%')
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
            } else if (!this.ctrl.isEmpty()) {
              Column().width('100%').height(38)
            }

            if (this.ctrl.isEmpty() && this.ctrl.loading) {
              Column({ space: 10 }) {
                LoadingProgress()
                  .width(36)
                  .height(36)
                  .color(AppTheme.current().primary)
              }
              .width('100%')
              .padding({ top: 86 })
              .justifyContent(FlexAlign.Center)
            }

            if (this.ctrl.recentPlay.length > 0) {
              VideoHomeSection({
                title: L10n.t('video_home_recent_play', '最近播放'),
                items: this.ctrl.recentPlay,
                showProgress: true,
                onTapTitle: (): void => {
                  this.onOpenHistory();
                },
                onDeleted: (deleted: VideoHomeItemBean): void => {
                  this.ctrl.handleExternalDelete(deleted.id);
                },
                onFavoriteChanged: (item: VideoHomeItemBean, isFav: boolean): void => {
                  this.ctrl.handleFavoriteChanged(item.id, isFav);
                }
              })
            }

            if (this.ctrl.recentAddMovie.length > 0) {
              VideoHomeSection({
                title: L10n.t('video_home_recent_add_movie', '最近添加的电影'),
                items: this.ctrl.recentAddMovie,
                onTapTitle: (): void => {
                  this.onOpenMovie();
                },
                onDeleted: (deleted: VideoHomeItemBean): void => {
                  this.ctrl.handleExternalDelete(deleted.id);
                },
                onFavoriteChanged: (item: VideoHomeItemBean, isFav: boolean): void => {
                  this.ctrl.handleFavoriteChanged(item.id, isFav);
                }
              })
            }

            if (this.ctrl.recentAddTv.length > 0) {
              VideoHomeSection({
                title: L10n.t('video_home_recent_add_tv', '最近添加的电视剧'),
                items: this.ctrl.recentAddTv,
                onTapTitle: (): void => {
                  this.onOpenTv();
                },
                onDeleted: (deleted: VideoHomeItemBean): void => {
                  this.ctrl.handleExternalDelete(deleted.id);
                },
                onFavoriteChanged: (item: VideoHomeItemBean, isFav: boolean): void => {
                  this.ctrl.handleFavoriteChanged(item.id, isFav);
                }
              })
            }

            if (this.ctrl.isEmpty() && !this.ctrl.loading) {
              Column() {
                EmptyState({ message: L10n.t('no_data', '暂无数据') })
              }
              .width('100%')
              .padding({ top: 86 })
            }

            // 底部留白（避开悬浮模式条，对齐 Flutter padding bottom 70）
            Column().width('100%').height(70)
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
      .onStateChange((state: RefreshStatus) => {
        if (state === RefreshStatus.Refresh) {
          void this.ctrl.refreshAll(false);
        }
      })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
    .opacity(this.tick >= 0 ? 1 : 1)
  }
}
