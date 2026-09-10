import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WindowStore } from '../../../common/WindowStore';
import { ZoomableImage } from '../../../common/components/ZoomableImage';
import { EncryptedSpaceFileUtils } from '../services/EncryptedSpaceFileUtils';
import { EncryptedSpaceViewerPageParam, EncryptedViewerItem } from '../router/EncryptedSpaceRoutes';

const TAG = 'EncryptedSpaceViewer';
const WHITE = '#FFFFFF';

/**
 * 加密空间图片查看器（对齐 Flutter CustomGallery + encrypted 空间 handler）：
 * 全屏黑底 Swiper 翻页 + 缩放/旋转，右上 旋转/删除/下载，手机左上角常驻关闭，底部文件名。
 * 删除走空间删除接口（onDeleted 回调），下载走 download=1 解码地址。
 */
@ComponentV2
export struct EncryptedSpaceViewerPage {
  @Param param: EncryptedSpaceViewerPageParam = new EncryptedSpaceViewerPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local items: EncryptedViewerItem[] = [];
  @Local currentIndex: number = 0;
  @Local isControlsVisible: boolean = true;
  @Local rotations: Map<number, number> = new Map();
  @Local scales: Map<number, number> = new Map();
  @Local pageWidth: number = 0;
  @Local isPhoneLayout: boolean = true;
  @Local statusBarHeight: number = 0;
  private swiperController: SwiperController = new SwiperController();
  private retryTimer: number = -1;

  aboutToAppear(): void {
    this.items = this.param.items.slice();
    this.currentIndex = Math.min(Math.max(this.param.initialIndex, 0),
      Math.max(this.items.length - 1, 0));
    this.setFullScreen(true);
    this.fetchSafeArea();
    EncryptedSpaceViewerPage.setStatusBar('#FFFFFF', '#00000000');
  }

  aboutToDisappear(): void {
    this.clearRetryTimer();
    // 返回目标是常规页（PageScaffold），退出时恢复避让布局，避免安全区丢失
    this.setFullScreen(false);
  }

  // ================================ 窗口 ================================

  private setFullScreen(full: boolean): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      hilog.error(0x0000, TAG, 'mainWindow undefined');
      return;
    }
    w.setWindowLayoutFullScreen(full).catch((_e: Object): void => {
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

  // ================================ 操作 ================================

  private currentItem(): EncryptedViewerItem | undefined {
    return this.currentIndex >= 0 && this.currentIndex < this.items.length
      ? this.items[this.currentIndex] : undefined;
  }

  private toggleControls(): void {
    this.isControlsVisible = !this.isControlsVisible;
  }

  private currentScale(): number {
    return this.scales.get(this.currentIndex) ?? 1.0;
  }

  private rotateCurrent(delta: number): void {
    this.rotations.set(this.currentIndex, (this.rotations.get(this.currentIndex) ?? 0) + delta);
  }

  private deleteCurrent(): void {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
    const removedIndex = this.currentIndex;
    void this.param.onDeleted(item.indexId).then((ok: boolean): void => {
      if (!ok) {
        return;
      }
      const next: EncryptedViewerItem[] = [];
      for (let i = 0; i < this.items.length; i++) {
        if (i !== removedIndex) {
          next.push(this.items[i]);
        }
      }
      this.items = next;
      if (next.length === 0) {
        this.popPage();
        return;
      }
      const safeIndex = removedIndex >= next.length ? next.length - 1 : removedIndex;
      this.currentIndex = safeIndex;
      this.swiperController.changeIndex(safeIndex, false);
    });
  }

  private downloadCurrent(): void {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
    void EncryptedSpaceFileUtils.downloadAndSave(item.downloadUrl, item.name);
  }

  // ================================ UI ================================

  build() {
    NavDestination() {
      if (this.items.length === 0) {
        Column() {
          Text('')
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
      } else {
        Stack() {
          Swiper(this.swiperController) {
            ForEach(this.items, (item: EncryptedViewerItem, index: number) => {
              this.ItemView(item, index)
            }, (item: EncryptedViewerItem, index: number): string => `${index}_${item.indexId}`)
          }
          .index(this.currentIndex)
          .loop(false)
          .indicator(false)
          .duration(200)
          .disableSwipe(this.currentScale() > 1.001)
          .onChange((idx: number): void => {
            this.currentIndex = idx;
          })

          // 顶部控制按钮
          if (this.isControlsVisible) {
            this.TopControls()
          }

          // 底部文件名
          if (this.isControlsVisible) {
            this.FileNameBar()
          }

          // 手机左上角常驻关闭按钮
          this.CloseButton()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .onAreaChange((_o: Area, n: Area): void => {
          this.pageWidth = Number(n.width);
          this.isPhoneLayout = Math.min(Number(n.width), Number(n.height)) < 600;
        })
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

  @Builder
  ItemView(item: EncryptedViewerItem, index: number) {
    Stack() {
      ZoomableImage({
        url: item.url,
        initScale: this.scales.get(index) ?? 1.0,
        minScale: 0.5,
        maxScale: 10,
        doubleTapScale: 3,
        quarterTurns: this.rotations.get(index) ?? 0,
        onSingleTap: (_x: number, _y: number): void => {
          this.toggleControls();
        },
        onScaleChanged: (s: number): void => {
          this.scales.set(index, s);
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TopControls() {
    Row({ space: this.isPhoneLayout ? 4 : 10 }) {
      this.CircleIconButton($r('sys.symbol.arrow_counterclockwise'), (): void => {
        this.rotateCurrent(-1);
      })
      this.CircleIconButton($r('sys.symbol.arrow_clockwise'), (): void => {
        this.rotateCurrent(1);
      })
      this.CircleIconButton($r('sys.symbol.trash'), (): void => {
        this.deleteCurrent();
      })
      this.CircleIconButton($r('sys.symbol.square_and_arrow_down'), (): void => {
        this.downloadCurrent();
      })
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.End)
    .width('100%')
    .height(100)
    .position({ x: 0, y: 0 })
    .padding({ right: 20, top: this.isPhoneLayout ? this.statusBarHeight + 20 : 30 })
    .linearGradient({
      angle: 180,
      colors: [['#B3000000', 0], ['#4D000000', 0.5], ['#00000000', 1]]
    })
  }

  @Builder
  CircleIconButton(icon: Resource, onTap: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([WHITE])
    }
    .justifyContent(FlexAlign.Center)
    .width(this.isPhoneLayout ? 40 : 30)
    .height(this.isPhoneLayout ? 40 : 30)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  FileNameBar() {
    Text(this.currentItem()?.name ?? '')
      .fontSize(16)
      .fontColor(WHITE)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor('#80000000')
      .borderRadius(20)
      .constraintSize({ maxWidth: this.pageWidth * 0.85 || 320 })
      .position({ x: '50%', y: '100%' })
      .markAnchor({ x: '50%', y: '100%' })
      .translate({ y: this.isPhoneLayout ? -58 : -24 })
  }

  @Builder
  CloseButton() {
    Column() {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(24)
        .fontColor([WHITE])
    }
    .justifyContent(FlexAlign.Center)
    .width(44)
    .height(44)
    .position({ x: 12, y: this.statusBarHeight + 24 })
    .onClick((): void => {
      this.popPage();
    })
  }
}
