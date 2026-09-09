import { AppImageLoader } from './AppImage';
import { AppTheme } from '../../core/theme/AppTheme';
import { L10n } from '../../core/localization/L10n';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ZoomableImage';

/**
 * 通用可缩放图片组件（对齐 Flutter CustomExtendedImage gesture 模式）：
 * - AppImageLoader 加载（Bearer + 缓存 + 去重）
 * - 双指捏合缩放（min/max 可配）、拖动平移（放大后）、双击在点击位置 1↔3 倍缩放
 * - 单击 / 长按回调（供页面处理切换控制栏、Live Photo 播放等）
 * - 旋转 quarterTurns（0-3），奇数时按交换后的容器宽高适配
 * 尺寸由调用方约束（建议填满父容器）。
 */
@ComponentV2
export struct ZoomableImage {
  @Param url: string = '';
  /** 初始缩放（页面记录的上次缩放） */
  @Param initScale: number = 1.0;
  @Param minScale: number = 0.5;
  @Param maxScale: number = 10.0;
  /** 双击目标缩放 [当前, 目标]（对齐 Flutter doubleTapScales [1,3]） */
  @Param doubleTapScale: number = 3.0;
  @Param quarterTurns: number = 0;
  /** 单击回调（与双击互斥，约 300ms 延迟触发） */
  @Param onSingleTap: (localX: number, localY: number) => void = (_x: number, _y: number): void => {
  };
  @Param onLongPress: () => void = (): void => {
  };
  /** 缩放变化回调（页面用于放大时禁用 Swiper 滑动） */
  @Param onScaleChanged: (scale: number) => void = (_s: number): void => {
  };
  /**
   * 未放大时自身平移手势方向（另一个轴让给外层 Swiper 翻页）：
   * 水平 Swiper（图片浏览器）用 Vertical；垂直 Swiper（漫画竖读）用 Horizontal。
   */
  @Param idlePanDirection: PanDirection = PanDirection.Vertical;
  /**
   * 适应宽度模式（漫画阅读器）：图片加载后计算基础缩放使宽度铺满容器，
   * 初始顶对齐；缩放/平移均以基础缩放为基准（对齐 Flutter ExtendedImage fitWidth）。
   */
  @Param fitWidthMode: boolean = false;
  /** 是否处于放大状态回调（相对自身基础缩放），页面用于禁用外层 Swiper 滑动 */
  @Param onZoomChanged: (zoomed: boolean) => void = (_z: boolean): void => {
  };

  @Local pixelMap: PixelMap | undefined = undefined;
  @Local failed: boolean = false;
  @Local currentScale: number = 1.0;
  /** 基础缩放：普通模式 1.0；fitWidth 模式为宽度铺满所需的缩放 */
  @Local baseScale: number = 1.0;
  @Local offsetX: number = 0;
  @Local offsetY: number = 0;
  @Local containerW: number = 0;
  @Local containerH: number = 0;
  private loadSeq: number = 0;
  private pinchBase: number = 1.0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  /** fitWidth 基础缩放是否已应用（等待容器测量） */
  private baseApplied: boolean = false;

  aboutToAppear(): void {
    this.currentScale = this.initScale;
    void this.reload();
  }

  aboutToDisappear(): void {
    this.loadSeq++;
  }

  @Monitor('url')
  onUrlChange(): void {
    this.baseScale = 1.0;
    this.baseApplied = false;
    this.currentScale = this.initScale;
    this.offsetX = 0;
    this.offsetY = 0;
    void this.reload();
  }

  private async reload(): Promise<void> {
    const seq = ++this.loadSeq;
    const target = this.url.trim();
    if (target.length === 0) {
      this.pixelMap = undefined;
      this.failed = false;
      return;
    }
    try {
      const pm = await AppImageLoader.load(target);
      if (seq !== this.loadSeq) {
        return;
      }
      this.pixelMap = pm;
      this.failed = false;
      this.applyBaseScale();
    } catch (e) {
      hilog.error(0x0000, TAG, 'load failed: %{public}s, url: %{public}s', `${e}`, target);
      if (seq !== this.loadSeq) {
        return;
      }
      this.pixelMap = undefined;
      this.failed = true;
    }
  }

  /** fitWidth 模式：图片就绪后计算基础缩放（宽度铺满容器）并顶对齐 */
  private applyBaseScale(): void {
    if (!this.fitWidthMode) {
      this.baseScale = 1.0;
      this.baseApplied = true;
      this.applyInitialAlign();
      return;
    }
    if (this.containerW <= 0 || this.pixelMap === undefined) {
      return; // 等待 onAreaChange 后重试
    }
    const containW = this.displayWidth();
    if (containW <= 0) {
      return;
    }
    this.baseScale = this.clampScale(this.containerW / containW);
    this.currentScale = this.baseScale;
    this.baseApplied = true;
    this.applyInitialAlign();
  }

  /** 初始对齐：普通模式居中；fitWidth 模式顶对齐（图片高于容器时下移至顶边贴齐） */
  private applyInitialAlign(): void {
    this.offsetX = 0;
    this.offsetY = 0;
    if (this.fitWidthMode && this.baseScale > 1.001 && this.containerH > 0) {
      const dispH = this.displayHeight() * this.currentScale;
      if (dispH > this.containerH) {
        this.offsetY = (dispH - this.containerH) / 2;
      }
    }
    this.clampOffset(this.offsetX, this.offsetY);
    this.notifyZoom();
  }

  private notifyZoom(): void {
    this.onZoomChanged(this.currentScale > this.baseScale + 0.01);
  }

  private clampScale(v: number): number {
    return Math.min(Math.max(v, this.minScale), this.maxScale);
  }

  /** 缩放后限制平移范围，保证图片不会完全滑出视野（按图片实际显示尺寸计算） */
  private clampOffset(x: number, y: number): void {
    const w = this.containerW;
    const h = this.containerH;
    if (w <= 0 || h <= 0) {
      return;
    }
    const dispW = this.displayWidth() * this.currentScale;
    const dispH = this.displayHeight() * this.currentScale;
    const overflowX = Math.max(0, (dispW - w) / 2);
    const overflowY = Math.max(0, (dispH - h) / 2);
    this.offsetX = Math.min(Math.max(x, -overflowX), overflowX);
    this.offsetY = Math.min(Math.max(y, -overflowY), overflowY);
  }

  private onPinch(e: GestureEvent): void {
    const next = this.clampScale(this.pinchBase * e.scale);
    this.currentScale = next;
    this.onScaleChanged(next);
    this.notifyZoom();
    this.clampOffset(this.offsetX, this.offsetY);
  }

  private onPanStart(e: GestureEvent): void {
    this.panStartX = e.offsetX;
    this.panStartY = e.offsetY;
    this.panBaseX = this.offsetX;
    this.panBaseY = this.offsetY;
  }

  private onPanUpdate(e: GestureEvent): void {
    if (this.currentScale <= 1.001) {
      return;
    }
    this.clampOffset(this.panBaseX + (e.offsetX - this.panStartX),
      this.panBaseY + (e.offsetY - this.panStartY));
  }

  /** 双击：基础缩放 ↔ 基础×doubleTapScale，保持点击位置不动（对齐 ExtendedImage handleDoubleTap） */
  private onDoubleTap(e: GestureEvent): void {
    const zoomed = this.currentScale > this.baseScale + 0.01;
    if (zoomed) {
      this.currentScale = this.baseScale;
      this.applyInitialAlign();
      this.onScaleChanged(this.currentScale);
      return;
    }
    const target = this.clampScale(this.baseScale * this.doubleTapScale);
    const w = this.containerW > 0 ? this.containerW : 360;
    const h = this.containerH > 0 ? this.containerH : 640;
    const tapX = e.fingerList.length > 0 ? e.fingerList[0].localX : w / 2;
    const tapY = e.fingerList.length > 0 ? e.fingerList[0].localY : h / 2;
    // 点击点在未缩放图像坐标系中的位置；缩放前后保持该点屏幕位置不变
    const px = (tapX - w / 2 - this.offsetX) / this.currentScale;
    const py = (tapY - h / 2 - this.offsetY) / this.currentScale;
    this.offsetX = this.offsetX + px * (this.currentScale - target);
    this.offsetY = this.offsetY + py * (this.currentScale - target);
    this.currentScale = target;
    this.clampOffset(this.offsetX, this.offsetY);
    this.onScaleChanged(target);
    this.notifyZoom();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.pixelMap) {
        Image(this.pixelMap)
          .objectFit(ImageFit.Contain)
          .autoResize(true)
          .draggable(false)
          .width(this.displayWidth())
          .height(this.displayHeight())
          .rotate({ angle: this.quarterTurns * 90 })
          .scale({ x: this.currentScale, y: this.currentScale })
          .translate({ x: this.offsetX, y: this.offsetY })
      } else if (this.failed) {
        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(18)
            .fontColor([AppTheme.withAlpha('#FFFFFF', 0.4)])
          Text(L10n.t('tap_to_retry', '点击重试'))
            .fontSize(11)
            .fontColor(AppTheme.withAlpha('#FFFFFF', 0.4))
        }
        .onClick((): void => {
          this.failed = false;
          void this.reload();
        })
      } else {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(AppTheme.withAlpha('#FFFFFF', 0.35))
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, n: Area): void => {
      this.containerW = Number(n.width);
      this.containerH = Number(n.height);
      if (this.pixelMap !== undefined && !this.baseApplied) {
        this.applyBaseScale();
      }
    })
    .gesture(GestureGroup(GestureMode.Parallel,
      PinchGesture({ fingers: 2 })
        .onActionStart((_e: GestureEvent): void => {
          this.pinchBase = this.currentScale;
        })
        .onActionUpdate((e: GestureEvent): void => {
          this.onPinch(e);
        }),
      PanGesture({
        fingers: 1,
        // 未放大时仅响应 idlePanDirection 平移，另一轴滑动让给外层 Swiper 翻页（对齐 Flutter ExtendedImage 手势策略）
        direction: this.currentScale > 1.001 ? PanDirection.All : this.idlePanDirection,
        distance: 5
      })
        .onActionStart((e: GestureEvent): void => {
          this.onPanStart(e);
        })
        .onActionUpdate((e: GestureEvent): void => {
          this.onPanUpdate(e);
        }),
      LongPressGesture({ repeat: false, duration: 350 })
        .onAction((_e: GestureEvent): void => {
          this.onLongPress();
        }),
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 2 })
          .onAction((e: GestureEvent): void => {
            this.onDoubleTap(e);
          }),
        TapGesture({ count: 1 })
          .onAction((e: GestureEvent): void => {
            const x = e.fingerList.length > 0 ? e.fingerList[0].localX : 0;
            const y = e.fingerList.length > 0 ? e.fingerList[0].localY : 0;
            this.onSingleTap(x, y);
          })
      )
    ))
  }

  /** 旋转后适配容器的显示宽（奇数旋转交换容器宽高适配；高度=宽/图片比例） */
  private displayWidth(): number {
    const w = this.containerW > 0 ? this.containerW : 360;
    const h = this.containerH > 0 ? this.containerH : 640;
    const r = this.pixelRatio();
    if (this.quarterTurns % 2 === 0) {
      return Math.min(w, h * r);
    }
    return Math.min(h, w * r);
  }

  private displayHeight(): number {
    return this.displayWidth() / this.pixelRatio();
  }

  private pixelRatio(): number {
    if (this.pixelMap === undefined) {
      return 1;
    }
    try {
      const info = this.pixelMap.getImageInfoSync();
      if (info.size.height <= 0) {
        return 1;
      }
      return info.size.width / info.size.height;
    } catch (_e) {
      return 1;
    }
  }
}
