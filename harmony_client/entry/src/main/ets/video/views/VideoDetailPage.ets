import { window } from '@kit.ArkUI';
import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil } from '../../common/DialogUtil';
import { AppEventBus } from '../../common/AppEventBus';
import { ThemeManager } from '../../core/theme/ThemeManager';
import { asNum, asStr } from '../models/VideoModels';
import { VideoDetailController } from '../controllers/VideoDetailController';
import { VideoDetailPageParam } from '../router/VideoRoutes';
import {
  DetailColors, VideoDetailActionsSection, VideoDetailDiscContentSection,
  VideoDetailEpisodeSection, VideoDetailFileInfoSection, VideoDetailPeopleSection,
  VideoDetailSeasonSection, VideoDetailStorylineSection, VideoDetailTopSection,
  detailResolutionLabel
} from '../components/VideoDetailSections';

/**
 * 视频详情页（对齐 Flutter VideoDetailPage + AppVideoDetailBody，移动端版式）：
 * 全屏深色沉浸布局，顶部大图区 + 剧情简介/操作/季/剧集/原盘/演职人员/文件信息区块；
 * 顶部浮层：左侧分辨率标签 + 右侧关闭按钮；加载失败弹窗提示并返回。
 */
@ComponentV2
export struct VideoDetailPage {
  @Param param: VideoDetailPageParam = new VideoDetailPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: VideoDetailController = new VideoDetailController(0);
  @Local bodyWidth: number = 0;
  @Local bodyHeight: number = 0;
  @Local themeTick: number = 0;
  private errorDialogShown: boolean = false;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
  };

  aboutToAppear(): void {
    this.ctrl = new VideoDetailController(this.param.indexId);
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.applyStatusBar();
    void this.ctrl.refreshDetail();
  }

  /** 加载结束后检查失败弹窗（对齐 Flutter Obx 内 addPostFrameCallback 逻辑） */
  @Monitor('ctrl.loading')
  onLoadingChange(): void {
    if (!this.ctrl.loading) {
      this.maybeShowErrorDialog();
    }
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 恢复主题默认状态栏
    const p = AppTheme.current();
    VideoDetailPage.setStatusBar(getContext(this), p.statusBarContent, '#00000000');
  }

  private applyStatusBar(): void {
    // 详情页锁定深色：白色状态栏文字 + 透明背景
    VideoDetailPage.setStatusBar(getContext(this), '#FFFFFF', '#00000000');
  }

  private static setStatusBar(ctx: Context, contentColor: string, bgColor: string): void {
    try {
      window.getLastWindow(ctx).then((w) => {
        w.setWindowSystemBarProperties({
          statusBarContentColor: contentColor,
          statusBarColor: bgColor
        });
      });
    } catch (_e) {
      // 状态栏设置失败不阻塞页面
    }
  }

  /** 顶部大图高度（对齐 AppVideoDetailBody：竖屏 min(460, h*0.62)，横屏 min(360, h*0.78)） */
  private topHeight(): number {
    const h = this.bodyHeight > 0 ? this.bodyHeight : 800;
    const portrait = this.bodyHeight >= this.bodyWidth;
    return portrait ? Math.min(460.0, h * 0.62) : Math.min(360.0, h * 0.78);
  }

  /** 顶部浮层分辨率标签（tv 取第一集分辨率，其余取条目自身，对齐 VideoDetailPage） */
  private resLabel(): string {
    if (this.ctrl.mediaType === 'tv') {
      if (this.ctrl.episodes.length > 0) {
        const e = this.ctrl.episodes[0];
        return detailResolutionLabel(asNum(e['width']), asNum(e['height']));
      }
      return '';
    }
    return detailResolutionLabel(asNum(this.ctrl.item['width']), asNum(this.ctrl.item['height']));
  }

  private pageTitle(): string {
    const m = this.ctrl.item;
    const nfoName = asStr(m['nfo_name']).trim();
    return nfoName.length > 0 ? nfoName : asStr(m['filename']).trim();
  }

  /** 加载失败信息弹窗（仅弹一次，按钮关闭页面，对齐 Flutter _errorDialogShown 逻辑） */
  private maybeShowErrorDialog(): void {
    if (this.errorDialogShown || this.ctrl.loading || this.ctrl.hasItem) {
      return;
    }
    this.errorDialogShown = true;
    DialogUtil.showInfoDialog(L10n.tip, L10n.t('video_detail_load_failed', '视频详情加载失败'),
      '', (): void => {
        this.popPage();
      });
  }

  build() {
    NavDestination() {
      Stack() {
        // 沉浸式深色背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(DetailColors.surface)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll() {
          Column() {
            Column() {
              VideoDetailTopSection({ ctrl: this.ctrl })
            }
            .width('100%')
            .height(this.topHeight())

            Column() {
              VideoDetailStorylineSection({ ctrl: this.ctrl })
              Row()
                .height(12)
              VideoDetailActionsSection({
                ctrl: this.ctrl,
                onDeleted: (): void => {
                  this.popPage();
                }
              })
              Row()
                .height(14)
              if (this.ctrl.seasonList.length > 0) {
                VideoDetailSeasonSection({ ctrl: this.ctrl })
                Row()
                  .height(10)
              }
              if (this.ctrl.showEpisodeSection) {
                VideoDetailEpisodeSection({ ctrl: this.ctrl })
                Row()
                  .height(10)
              }
              if (this.ctrl.showDiscContentSection) {
                VideoDetailDiscContentSection({ ctrl: this.ctrl })
                Row()
                  .height(10)
              }
              VideoDetailPeopleSection({ ctrl: this.ctrl })
              Row()
                .height(14)
              VideoDetailFileInfoSection({ ctrl: this.ctrl })
            }
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 10, right: 10, top: 12, bottom: 20 })
            .width('100%')
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
        .onAreaChange((_o: Area, n: Area): void => {
          this.bodyWidth = Number(n.width);
          this.bodyHeight = Number(n.height);
        })
        .align(Alignment.Top)
        .opacity(this.themeTick >= 0 ? 1 : 1)

        // 顶部浮层：左侧分辨率标签 + 右侧关闭按钮（对齐 Flutter Positioned 顶栏）
        Row() {
          if (this.resLabel().length > 0) {
            Text(this.resLabel())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(DetailColors.onSurface)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(999)
              .border({ width: 1, color: DetailColors.alpha(0.22) })
              .backgroundColor(AppTheme.withAlpha('#000000', 0.45))
          }
          Blank()
          Column() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .fontColor([DetailColors.onSurface])
          }
          .justifyContent(FlexAlign.Center)
          .width(40)
          .height(40)
          .borderRadius(999)
          .backgroundColor(AppTheme.withAlpha('#000000', 0.35))
          .onClick(() => {
            this.popPage();
          })
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12, top: 56 })

        // 加载中
        if (this.ctrl.loading && !this.ctrl.hasItem) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(DetailColors.onSurface)
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
        }
        // 加载失败
        if (!this.ctrl.loading && !this.ctrl.hasItem) {
          Column() {
            Text(L10n.t('video_detail_load_failed', '视频详情加载失败'))
              .fontSize(15)
              .fontColor(DetailColors.alpha(0.85))
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
          .onClick(() => {
            this.maybeShowErrorDialog();
          })
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.themeTick >= 0 ? 1 : 1)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      this.popPage();
      return true;
    })
  }
}
