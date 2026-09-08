import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../../core/localization/L10n';
import { WindowStore } from '../../common/WindowStore';
import { AppRouter } from '../../router/AppRouter';
import { NavUtil } from '../../common/NavUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../common/SheetUtil';
import { ZoomableImage } from '../../common/components/ZoomableImage';
import { GalleryController } from '../controllers/GalleryController';
import { GalleryItem, GalleryPageParam } from '../models/GalleryModels';
import { GalleryInfoPanel } from '../components/GalleryInfoPanel';
import { LivePhotoInlinePlayer } from '../components/LivePhotoInlinePlayer';

const TAG = 'GalleryPage';
const GALLERY_WHITE = '#FFFFFF';
const GALLERY_BLUE = '#2196F3';

/** 全景页参数 */
export class PanoramaPageParam {
  imageUrl: string = '';
}

/** 手机端信息底部 sheet 参数 */
class GalleryInfoSheetParams extends SheetParamsBase {
  ctrl: GalleryController = new GalleryController();
  bottomPadding: number = 0;
}

/** 手机端信息底部 sheet 内容（黑 95% 圆角 16，高度 62%，对齐 Flutter showModalBottomSheet） */
@Builder
function GalleryInfoSheetContent(p: GalleryInfoSheetParams) {
  Column() {
    SheetHandle()
    GalleryInfoPanel({
      ctrl: p.ctrl,
      sheetMode: true,
      onClose: (): void => {
        p.close();
      }
    })
  }
  .width('100%')
  .height('62%')
  .backgroundColor('#F2000000')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .padding({ bottom: p.bottomPadding })
  .clip(true)
}

/**
 * 图片浏览器页（对齐 Flutter CustomGallery 手机端版式）：
 * 全屏黑底 + Swiper 翻页 + 双指/双击缩放 + 旋转 + 顶部控件（信息/旋转/删除/下载/自动播放）+
 * 底部文件名与 LIVE/360 chips + 导航箭头（桌面）+ 手机左上角常驻关闭 + 信息侧栏/底部 sheet +
 * Live Photo 页内循环播放（长按或点击 LIVE 开始，切页自动停止）。
 */
@ComponentV2
export struct GalleryPage {
  @Param param: GalleryPageParam = new GalleryPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: GalleryController = new GalleryController();
  @Local ready: boolean = false;
  @Local isPhoneLayout: boolean = true;
  @Local pageWidth: number = 0;
  @Local statusBarHeight: number = 0;
  @Local navBarHeight: number = 0;
  private swiperController: SwiperController = new SwiperController();
  private retryTimer: number = -1;

  aboutToAppear(): void {
    this.setFullScreen(true);
    this.fetchSafeArea();
    GalleryPage.setStatusBar('#FFFFFF', '#00000000');
    this.ctrl.gotoPage = (index: number): void => {
      this.swiperController.changeIndex(index, false);
    };
    this.ctrl.closePage = (): void => {
      this.popPage();
    };
    void this.ctrl.configure(this.param).then((): void => {
      this.ready = true;
    });
  }

  aboutToDisappear(): void {
    this.clearRetryTimer();
    this.ctrl.destroy();
    // 返回目标是常规页（照片首页/AI 相似页等 PageScaffold 页），退出时恢复避让布局，
    // 否则下层页面不重建、aboutToAppear 不会再执行，窗口停留在全屏导致安全区丢失
    this.setFullScreen(false);
  }

  // ================================ 窗口 ================================

  private setFullScreen(full: boolean): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      hilog.error(0x0000, TAG, 'mainWindow undefined');
      return;
    }
    w.setWindowLayoutFullScreen(full).catch((e: Object): void => {
      hilog.error(0x0000, TAG, 'setFullScreen failed: %{public}s', JSON.stringify(e));
    });
  }

  private scheduleFullScreenRetry(): void {
    this.clearRetryTimer();
    this.retryTimer = setTimeout((): void => {
      this.setFullScreen(true);
    }, 120);
  }

  private clearRetryTimer(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private fetchSafeArea(): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    const system = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    this.statusBarHeight = px2vp(system.topRect.height);
    const nav = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.navBarHeight = px2vp(nav.bottomRect.height);
  }

  private static setStatusBar(contentColor: string, bgColor: string): void {
    try {
      const ctx = getContext() as Context;
      window.getLastWindow(ctx).then((w: window.Window): void => {
        w.setWindowSystemBarProperties({
          statusBarContentColor: contentColor,
          statusBarColor: bgColor
        });
      });
    } catch (_e) {
      // 状态栏设置失败不阻塞页面
    }
  }

  // ================================ 交互 ================================

  /** 点击图片区域：手机切换控制栏；桌面 30% 分区翻页（对齐 Flutter onTapUp） */
  private handleImageTap(localX: number): void {
    if (this.isPhoneLayout) {
      this.ctrl.toggleControls();
      return;
    }
    const w = this.pageWidth;
    if (w <= 0) {
      return;
    }
    if (localX < w * 0.3) {
      this.ctrl.previousImage();
    } else if (localX > w * 0.7) {
      this.ctrl.nextImage();
    } else {
      this.ctrl.toggleControls();
    }
  }

  private openInfo(): void {
    if (this.isPhoneLayout) {
      void this.ctrl.fetchCurrentImageInfo(true);
      const p = new GalleryInfoSheetParams();
      p.ctrl = this.ctrl;
      p.bottomPadding = this.navBarHeight;
      SheetUtil.present(p, wrapBuilder(GalleryInfoSheetContent));
    } else {
      this.ctrl.toggleInfoPanel();
    }
  }

  private currentScale(): number {
    return this.ctrl.getScale(this.ctrl.currentIndex);
  }

  // ================================ 子视图 ================================

  /** 顶部控制按钮（渐变遮罩，右上排列，对齐 Flutter GalleryTopControls） */
  @Builder
  TopControls() {
    Column() {
      Row({ space: this.isPhoneLayout ? 4 : 10 }) {
        if (!this.isPhoneLayout) {
          this.CircleIconButton($r('sys.symbol.questionmark_circle'), (): void => {
            this.showShortcutsHelp();
          })
        }
        if (this.ctrl.showInfoButton) {
          this.CircleIconButton($r('sys.symbol.info_circle'), (): void => {
            this.openInfo();
          })
        }
        this.CircleIconButton($r('sys.symbol.arrow_counterclockwise'), (): void => {
          this.ctrl.rotateLeft(this.ctrl.currentIndex);
        })
        this.CircleIconButton($r('sys.symbol.arrow_clockwise'), (): void => {
          this.ctrl.rotateRight(this.ctrl.currentIndex);
        })
        this.CircleIconButton($r('sys.symbol.trash'), (): void => {
          void this.ctrl.deleteCurrentImage();
        })
        this.CircleIconButton($r('sys.symbol.square_and_arrow_down'), (): void => {
          void this.ctrl.downloadCurrentImage();
        })
        this.CircleIconButton(
          this.ctrl.isAutoPlaying ? $r('sys.symbol.pause_circle') : $r('sys.symbol.play_circle'),
          (): void => {
            this.ctrl.toggleAutoPlay();
          }, this.ctrl.isAutoPlaying ? GALLERY_BLUE : GALLERY_WHITE)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.End)
      .width('100%')
      .padding({ right: 20 })
    }
    .width('100%')
    .height(100)
    .position({ x: 0, y: 0 })
    .padding({ top: this.isPhoneLayout ? this.statusBarHeight + 20 : 30 })
    .linearGradient({
      angle: 180,
      colors: [['#B3000000', 0], ['#4D000000', 0.5], ['#00000000', 1]]
    })
  }

  @Builder
  CircleIconButton(icon: Resource, onTap: () => void, color: string = GALLERY_WHITE) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([color])
    }
    .justifyContent(FlexAlign.Center)
    .width(this.isPhoneLayout ? 40 : 30)
    .height(this.isPhoneLayout ? 40 : 30)
    .onClick(() => {
      onTap();
    })
  }

  private showShortcutsHelp(): void {
    DialogUtilHelp.show();
  }

  /** 底部文件名 + LIVE/360 chips（对齐 Flutter GalleryFileName） */
  @Builder
  FileNameBar() {
    Column({ space: 2 }) {
      Text(this.currentFileName())
        .fontSize(16)
        .fontColor(GALLERY_WHITE)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor('#80000000')
        .borderRadius(20)
      if (this.currentIsLivePhoto() || this.showPanoramaChip()) {
        Row({ space: 8 }) {
          if (this.currentIsLivePhoto()) {
            Row({ space: 6 }) {
              Text('LIVE')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#F2FFFFFF')
              SymbolGlyph($r('sys.symbol.play_circle'))
                .fontSize(20)
                .fontColor(['#F2FFFFFF'])
            }
            .padding({ left: 12, right: 12, top: 2, bottom: 2 })
            .backgroundColor('#80000000')
            .borderRadius(16)
            .onClick((): void => {
              this.ctrl.startLivePlayback(this.ctrl.currentIndex);
            })
          }
          if (this.showPanoramaChip()) {
            Row({ space: 6 }) {
              Text('360')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#F2FFFFFF')
              SymbolGlyph($r('sys.symbol.a_360_degree_rotation'))
                .fontSize(20)
                .fontColor(['#F2FFFFFF'])
            }
            .padding({ left: 12, right: 12, top: 2, bottom: 2 })
            .backgroundColor('#80000000')
            .borderRadius(16)
            .onClick((): void => {
              this.openPanorama();
            })
          }
        }
      }
    }
    .alignItems(HorizontalAlign.Center)
    .constraintSize({ maxWidth: this.pageWidth * 0.85 || 320 })
    .position({ x: '50%', y: '100%' })
    .markAnchor({ x: '50%', y: '100%' })
    .translate({ y: this.isPhoneLayout ? -58 : -24 })
  }

  private currentFileName(): string {
    const it = this.ctrl.currentItem();
    return it !== undefined ? it.name : '';
  }

  private currentIsLivePhoto(): boolean {
    const it = this.ctrl.currentItem();
    return it !== undefined && it.liveVideoUrl.length > 0;
  }

  private showPanoramaChip(): boolean {
    const it = this.ctrl.currentItem();
    return it !== undefined && it.url.length > 0 &&
      this.ctrl.isPanoramaCandidate(this.ctrl.currentIndex);
  }

  private openPanorama(): void {
    const it = this.ctrl.currentItem();
    if (it === undefined || it.url.length === 0) {
      return;
    }
    const p = new PanoramaPageParam();
    p.imageUrl = it.url;
    NavUtil.push(AppRouter.PHOTO_PANORAMA, p);
  }

  /** 导航箭头（桌面端 20% 宽点击区，圆形箭头定位在侧边，对齐 Flutter GalleryNavigationArrow） */
  @Builder
  NavigationArrow(isLeft: boolean) {
    Row() {
      if (isLeft) {
        this.ArrowCircle(true)
        Blank()
      } else {
        Blank()
        this.ArrowCircle(false)
      }
    }
    .width('20%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .position({ x: isLeft ? '0%' : '80%' })
    .opacity(this.ctrl.isControlsVisible ? 1 : 0)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .hitTestBehavior(this.ctrl.isControlsVisible ? HitTestMode.Default : HitTestMode.None)
    .onClick((): void => {
      if (isLeft) {
        this.ctrl.previousImage();
      } else {
        this.ctrl.nextImage();
      }
    })
  }

  @Builder
  ArrowCircle(isLeft: boolean) {
    Row() {
      SymbolGlyph(isLeft ? $r('sys.symbol.chevron_left') : $r('sys.symbol.chevron_right'))
        .fontSize(48)
        .fontColor([GALLERY_WHITE])
    }
    .justifyContent(FlexAlign.Center)
    .width(80)
    .height(80)
    .borderRadius(40)
    .backgroundColor('#80000000')
    .margin({ left: isLeft ? 20 : 0, right: isLeft ? 0 : 20 })
  }

  /** 手机左上角常驻关闭按钮（对齐 Flutter SafeArea+24/12） */
  @Builder
  CloseButton() {
    Column() {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(24)
        .fontColor([GALLERY_WHITE])
    }
    .justifyContent(FlexAlign.Center)
    .width(44)
    .height(44)
    .position({ x: 12, y: this.statusBarHeight + 24 })
    .onClick((): void => {
      this.popPage();
    })
  }

  /** 单页：缩放图 + Live Photo 页内播放覆盖层 */
  @Builder
  GalleryItemView(item: GalleryItem, index: number) {
    Stack() {
      ZoomableImage({
        url: item.url,
        initScale: this.ctrl.getScale(index),
        minScale: 0.5,
        maxScale: 10,
        doubleTapScale: 3,
        quarterTurns: this.ctrl.getRotation(index),
        onSingleTap: (x: number, _y: number): void => {
          this.handleImageTap(x);
        },
        onLongPress: (): void => {
          if (item.liveVideoUrl.length > 0 && !this.ctrl.isLivePhotoPlaying) {
            this.ctrl.startLivePlayback(index);
          }
        },
        onScaleChanged: (s: number): void => {
          this.ctrl.setScale(index, s);
        }
      })
      if (item.liveVideoUrl.length > 0 && this.ctrl.livePlayingIndex === index) {
        LivePhotoInlinePlayer({
          videoUrl: item.liveVideoUrl,
          onClose: (): void => {
            this.ctrl.stopLivePlayback();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      if (!this.ready) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(GALLERY_WHITE)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#000000')
      } else if (this.ctrl.items.length === 0) {
        Column() {
          Text(L10n.t('gallery_no_images', '暂无图片'))
            .fontSize(15)
            .fontColor(GALLERY_WHITE)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
      } else {
        Row() {
          // 桌面端信息侧栏（300px）
          if (!this.isPhoneLayout && this.ctrl.isInfoPanelVisible) {
            Column() {
              GalleryInfoPanel({
                ctrl: this.ctrl,
                sheetMode: false,
                onClose: (): void => {
                  this.ctrl.toggleInfoPanel();
                }
              })
            }
            .width(300)
            .height('100%')
          }
          // 主区域
          Stack() {
            Swiper(this.swiperController) {
              ForEach(this.ctrl.items, (item: GalleryItem, index: number) => {
                this.GalleryItemView(item, index)
              }, (item: GalleryItem, index: number): string => `${index}_${item.path}_${item.url.length}`)
            }
            .index(this.ctrl.currentIndex)
            .loop(false)
            .indicator(false)
            .duration(200)
            .disableSwipe(this.currentScale() > 1.001)
            .onChange((idx: number): void => {
              this.ctrl.onPageChanged(idx);
            })

            // 顶部控件（渐变遮罩 + 按钮行）
            if (this.ctrl.isControlsVisible) {
              this.TopControls()
            }

            // 底部文件名 + chips
            if (this.ctrl.isControlsVisible) {
              this.FileNameBar()
            }

            // 导航箭头（桌面端）
            if (!this.isPhoneLayout) {
              this.NavigationArrow(true)
              this.NavigationArrow(false)
            }

            // 手机左上角常驻关闭按钮
            if (this.isPhoneLayout) {
              this.CloseButton()
            }
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .onAreaChange((_o: Area, n: Area): void => {
            this.pageWidth = Number(n.width);
            this.isPhoneLayout = Math.min(Number(n.width), Number(n.height)) < 600;
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .hideTitleBar(true)
    .backgroundColor('#000000')
    .onShown((): void => {
      this.setFullScreen(true);
      this.scheduleFullScreenRetry();
    })
    .onHidden((): void => {
      this.clearRetryTimer();
    })
    .onBackPressed((): boolean => {
      this.popPage();
      return true;
    })
  }
}

/** 快捷键帮助弹窗（对齐 Flutter _showShortcutsHelp，桌面端显示） */
class DialogUtilHelp {
  static show(): void {
    DialogUtil.showInfoDialog(L10n.t('gallery_shortcuts_title', '快捷键'),
      L10n.t('gallery_shortcuts_content',
        '方向键左/右：上一张/下一张\n空格键：播放视频或 Live Photo 视频\nCtrl+I：查看图片信息'));
  }
}
