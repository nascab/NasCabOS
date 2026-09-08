import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../../core/localization/L10n';
import { WindowStore } from '../../common/WindowStore';
import { VideoPlayerController } from '../VideoPlayerController';
import { PlayerPlaylistItem } from '../models/PlayerModels';
import { VideoPlayerPageParam } from '../router/PlayerRoutes';
import {
  showAudioSheet, showInfoDrawer, showMoreSheet, showQualitySheet,
  showSpeedSheet, showSubtitleSheet
} from './PlayerMenus';

const TAG = 'VideoPlayerPage';
/** 播放器主色（对齐 Flutter Colors.blueAccent） */
const PLAYER_ACCENT = '#448AFF';
const PLAYER_WHITE = '#FFFFFF';

/** 毫秒 → h:mm:ss（对齐 Flutter _formatDuration，小时恒显示） */
function formatMs(ms: number): string {
  const totalSec = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  return `${h}:${`${m}`.padStart(2, '0')}:${`${s}`.padStart(2, '0')}`;
}

/**
 * 视频播放器页（对齐 Flutter AppVideoPlayerPage 移动端版式）：
 * 全屏黑底 XComponent + 手势层（点击/长按加速/横向滑动 scrub）+
 * 顶栏（返回/标题/信息）+ 中央播放锁定按钮 + 底栏（进度/控制按钮）+
 * 字幕叠层 / scrub 预览 / 加速提示。
 */
@ComponentV2
export struct VideoPlayerPage {
  @Param param: VideoPlayerPageParam = new VideoPlayerPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: VideoPlayerController = new VideoPlayerController();
  /** 页面尺寸（vp），scrub 比例与字幕字号用 */
  @Local pageWidth: number = 0;
  @Local pageHeight: number = 0;
  @Local statusBarHeight: number = 0;
  @Local navBarHeight: number = 0;
  /** scrub 预览进度（<0 表示未在 scrub） */
  @Local scrubPreviewMs: number = -1;
  @Local scrubCancelZone: boolean = false;
  private scrubOriginMs: number = 0;
  private retryTimer: number = -1;
  private xcController: XComponentController = new XComponentController();
  private playlistOpened: boolean = false;

  aboutToAppear(): void {
    this.setFullScreen(true);
    this.fetchSafeArea();
    VideoPlayerPage.setStatusBar('#FFFFFF', '#00000000');
  }

  aboutToDisappear(): void {
    this.clearRetryTimer();
    void this.ctrl.close();
  }

  // ================================ 窗口 ================================

  /** 全屏沉浸布局：同步调用，写顺序=调用顺序 */
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

  /** onShown 后延迟重设全屏：纠正 push 转场期间系统对全屏设置的回滚 */
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

  // ================================ 退出 ================================

  private async exitPlayer(): Promise<void> {
    await this.ctrl.prepareExitIfLandscape();
    await this.ctrl.close();
    this.popPage();
  }

  // ================================ 手势 ================================

  /** 手势事件的全局 Y 坐标（fingerList 为空返回 -1） */
  private static globalYOf(e: GestureEvent | undefined): number {
    if (e === undefined || e.fingerList.length === 0) {
      return -1;
    }
    return e.fingerList[0].globalY;
  }

  private onScrubStart(e: GestureEvent): void {
    if (this.ctrl.isLocked || this.ctrl.isCtrlSpeedBoost) {
      return;
    }
    if (!this.ctrl.isInitialized || this.ctrl.durationMs <= 0) {
      return;
    }
    this.scrubOriginMs = this.ctrl.positionMs;
    this.scrubCancelZone = false;
    this.scrubPreviewMs = this.scrubOriginMs;
  }

  private onScrubUpdate(e: GestureEvent): void {
    if (this.scrubPreviewMs < 0) {
      return;
    }
    const gy = VideoPlayerPage.globalYOf(e);
    this.scrubCancelZone = gy >= 0 && gy <= this.pageHeight * 0.25;
    const w = this.pageWidth;
    if (w < 1) {
      return;
    }
    const deltaMs = Math.round(e.offsetX / w * this.ctrl.durationMs);
    let ms = this.scrubOriginMs + deltaMs;
    ms = Math.min(Math.max(ms, 0), this.ctrl.durationMs);
    this.scrubPreviewMs = ms;
  }

  private onScrubEnd(e: GestureEvent | undefined, apply: boolean): void {
    if (this.scrubPreviewMs < 0) {
      return;
    }
    const gy = VideoPlayerPage.globalYOf(e);
    const cancel = apply && gy >= 0 && gy <= this.pageHeight * 0.25;
    const target = this.scrubPreviewMs;
    this.scrubPreviewMs = -1;
    this.scrubCancelZone = false;
    if (apply && !cancel && target >= 0) {
      this.ctrl.seekTo(target);
    }
  }

  // ================================ 子视图 ================================

  /** 顶栏：返回 + 标题 + 信息按钮（黑87→透明渐变） */
  @Builder
  TopBar() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([PLAYER_WHITE])
      }
      .justifyContent(FlexAlign.Center)
      .width(40)
      .height(40)
      .onClick(() => {
        void this.exitPlayer();
      })
      Text(this.currentTitle())
        .fontSize(18)
        .fontColor(PLAYER_WHITE)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ right: this.ctrl.isUrlSource ? 8 : 0 })
      if (!this.ctrl.isUrlSource) {
        Column() {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(20)
            .fontColor([PLAYER_WHITE])
        }
        .justifyContent(FlexAlign.Center)
        .width(40)
        .height(40)
        .onClick(() => {
          showInfoDrawer(this.ctrl);
        })
      }
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
  }

  private currentTitle(): string {
    const item = this.ctrl.currentPlaylistItem();
    return item !== undefined ? item.name : '';
  }

  /** 中央播放/暂停大按钮（圆形黑底白边） */
  @Builder
  CenterPlayButton() {
    Column() {
      SymbolGlyph(this.ctrl.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(44)
        .fontColor([PLAYER_WHITE])
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(88)
    .height(88)
    .borderRadius(44)
    .backgroundColor('#73000000')
    .border({ width: 2, color: PLAYER_WHITE })
    .onClick(() => {
      this.ctrl.togglePlay();
    })
  }

  /** 底栏：横竖屏 + 续播提示 + 时间/进度 + 控制按钮行（黑87→透明渐变） */
  @Builder
  BottomBar() {
    Column() {
      Row() {
        Blank()
        Column() {
          SymbolGlyph($r('sys.symbol.rotate_left'))
            .fontSize(22)
            .fontColor([PLAYER_WHITE])
        }
        .justifyContent(FlexAlign.Center)
        .width(40)
        .height(40)
        .onClick(() => {
          void this.ctrl.toggleOrientation();
        })
      }
      .width('100%')
      if (this.ctrl.resumeTipCountdown > 0) {
        Row() {
          Text(L10n.t('player_resume_tip', '已为您继续播放，点我从头开始'))
            .fontSize(12)
            .fontColor(PLAYER_ACCENT)
          Text(` ${this.ctrl.resumeTipCountdown} s`)
            .fontSize(12)
            .fontColor(PLAYER_ACCENT)
        }
        .width('100%')
        .margin({ bottom: 8 })
        .onClick(() => {
          this.ctrl.onResumeTipTap();
        })
      }
      Row() {
        Text(formatMs(this.ctrl.positionMs))
          .fontSize(13)
          .fontColor(PLAYER_ACCENT)
        Slider({
          value: Math.min(Math.max(this.ctrl.positionMs, 0),
            this.ctrl.durationMs > 0 ? this.ctrl.durationMs : 1),
          min: 0,
          max: this.ctrl.durationMs > 0 ? this.ctrl.durationMs : 1,
          step: 1,
          style: SliderStyle.OutSet
        })
          .selectedColor(PLAYER_ACCENT)
          .trackColor('#3DFFFFFF')
          .blockColor(PLAYER_ACCENT)
          .blockSize({ width: 12, height: 12 })
          .trackThickness(3)
          .layoutWeight(1)
          .margin({ left: 8, right: 8 })
          .onChange((value: number, _mode: SliderChangeMode): void => {
            if (this.ctrl.durationMs <= 0) {
              return;
            }
            this.ctrl.seekTo(Math.round(value));
          })
        Text(formatMs(this.ctrl.durationMs))
          .fontSize(13)
          .fontColor(PLAYER_WHITE)
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      Scroll() {
        Row({ space: 4 }) {
          this.BarIconButton(
            this.ctrl.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
            28, (): void => {
              this.ctrl.togglePlay();
            })
          this.BarIconButton($r('sys.symbol.backward_end_fill'), 22, (): void => {
            this.ctrl.playPrev();
          })
          this.BarIconButton($r('sys.symbol.forward_end_fill'), 22, (): void => {
            this.ctrl.playNext();
          })
          if (this.ctrl.isLandscape) {
            this.BarIconButton($r('sys.symbol.gobackward_10'), 24, (): void => {
              this.ctrl.rewind(10);
            })
            this.BarIconButton($r('sys.symbol.goforward_30'), 24, (): void => {
              this.ctrl.fastForward(30);
            })
          }
          this.BarTextButton(`${this.ctrl.playbackSpeed}x`, (): void => {
            showSpeedSheet(this.ctrl);
          })
          if (!this.ctrl.isUrlSource) {
            this.BarTextButton(this.ctrl.qualityLabel(this.ctrl.currentQuality), (): void => {
              showQualitySheet(this.ctrl);
            })
          }
          if (this.ctrl.isLandscape && !this.ctrl.isUrlSource) {
            this.BarIconButton($r('sys.symbol.AI_subtitles'), 22, (): void => {
              showSubtitleSheet(this.ctrl);
            })
            this.BarIconButton($r('sys.symbol.music_note_list'), 22, (): void => {
              showAudioSheet(this.ctrl);
            })
          }
          this.BarIconButton($r('sys.symbol.more'), 22, (): void => {
            showMoreSheet(this.ctrl);
          })
        }
        .padding({ right: 8 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      bottom: 20 + this.navBarHeight
    })
  }

  @Builder
  BarIconButton(icon: Resource, size: number, onTap: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(size)
        .fontColor([PLAYER_WHITE])
    }
    .justifyContent(FlexAlign.Center)
    .width(44)
    .height(44)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  BarTextButton(label: string, onTap: () => void) {
    Column() {
      Text(label)
        .fontSize(15)
        .fontColor(PLAYER_WHITE)
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .constraintSize({ minWidth: 44 })
    .height(44)
    .padding({ left: 8, right: 8 })
    .onClick(() => {
      onTap();
    })
  }

  /** 字幕叠层（客户端 VTT 渲染，字号随屏幕短边缩放） */
  @Builder
  SubtitleOverlay() {
    Column() {
      Blank()
      if (this.ctrl.webActiveSubtitleText.trim().length > 0) {
        Text(this.ctrl.webActiveSubtitleText)
          .fontSize(this.subtitleFontSize())
          .fontColor(PLAYER_WHITE)
          .textAlign(TextAlign.Center)
          .maxLines(4)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 88 })
    .justifyContent(FlexAlign.End)
    .hitTestBehavior(HitTestMode.None)
  }

  private subtitleFontSize(): number {
    const shortestSide = Math.min(
      this.pageWidth > 0 ? this.pageWidth : 360,
      this.pageHeight > 0 ? this.pageHeight : 640);
    return Math.min(Math.max(shortestSide / 28, 14), 28);
  }

  /** scrub 覆盖层：顶部取消区渐变提示 + 中央预览卡片 */
  @Builder
  ScrubOverlay() {
    Stack() {
      Column() {
        Text(L10n.t('player_scrub_cancel_zone_hint', '滑动到此取消'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F0FFFFFF')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('25%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 20, right: 20, top: this.statusBarHeight + 6, bottom: 8 })
      .linearGradient({
        angle: 180,
        colors: [['#D1000000', 0], ['#7A000000', 0.42], ['#00000000', 1]]
      })

      Column() {
        Row({ space: 14 }) {
          SymbolGlyph(this.scrubPreviewMs >= this.scrubOriginMs
            ? $r('sys.symbol.forward_end_fill') : $r('sys.symbol.backward_end_fill'))
            .fontSize(24)
            .fontColor(['#D9FFFFFF'])
          Text(`${formatMs(this.scrubPreviewMs)} / ${formatMs(this.ctrl.durationMs)}`)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(PLAYER_WHITE)
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .height(4)
            .width('100%')
            .borderRadius(3)
            .backgroundColor('#2EFFFFFF')
          Row()
            .height(4)
            .width(`${this.scrubProgressPercent()}%`)
            .borderRadius(3)
            .backgroundColor(PLAYER_ACCENT)
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ maxWidth: 320 })
      .padding({ left: 22, right: 22, top: 18, bottom: 18 })
      .borderRadius(16)
      .border({ width: 1, color: '#1FFFFFFF' })
      .backgroundColor('#CC0D0D0D')
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  private scrubProgressPercent(): number {
    if (this.ctrl.durationMs <= 0) {
      return 0;
    }
    const p = this.scrubPreviewMs / this.ctrl.durationMs * 100;
    return Math.min(Math.max(p, 0), 100);
  }

  /** 视频 letterbox 适配宽（保持宽高比取 min-scale，尺寸未知时占满容器） */
  private fitVideoWidth(): number {
    const cw = this.pageWidth > 0 ? this.pageWidth : 360;
    const ch = this.pageHeight > 0 ? this.pageHeight : 640;
    const vw = this.ctrl.videoWidth;
    const vh = this.ctrl.videoHeight;
    if (vw <= 0 || vh <= 0) {
      return cw;
    }
    return Math.min(cw / vw, ch / vh) * vw;
  }

  /** 视频 letterbox 适配高 */
  private fitVideoHeight(): number {
    const cw = this.pageWidth > 0 ? this.pageWidth : 360;
    const ch = this.pageHeight > 0 ? this.pageHeight : 640;
    const vw = this.ctrl.videoWidth;
    const vh = this.ctrl.videoHeight;
    if (vw <= 0 || vh <= 0) {
      return ch;
    }
    return Math.min(cw / vw, ch / vh) * vh;
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        // 视频渲染层（按视频宽高比 letterbox 居中，黑边由外层背景提供）
        XComponent({ id: 'nascab_player_surface', type: 'surface', controller: this.xcController })
          .width(this.fitVideoWidth())
          .height(this.fitVideoHeight())
          .onLoad((): void => {
            this.onSurfaceReady();
          })

        // 字幕叠层
        this.SubtitleOverlay()

        // 手势层（点击/长按加速/横向 scrub）
        Column()
          .width('100%')
          .height('100%')
          .gesture(GestureGroup(GestureMode.Parallel,
            TapGesture({ count: 1 })
              .onAction((_e: GestureEvent): void => {
                this.ctrl.handlePlayerTap();
              }),
            LongPressGesture({ repeat: false, duration: 450 })
              .onAction((_e: GestureEvent): void => {
                if (!this.ctrl.isLocked) {
                  this.ctrl.setCtrlSpeedBoost(true);
                }
              })
              .onActionEnd((_e: GestureEvent): void => {
                this.ctrl.setCtrlSpeedBoost(false);
              })
              .onActionCancel((): void => {
                this.ctrl.setCtrlSpeedBoost(false);
              }),
            PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 10 })
              .onActionStart((e: GestureEvent): void => {
                this.onScrubStart(e);
              })
              .onActionUpdate((e: GestureEvent): void => {
                this.onScrubUpdate(e);
              })
              .onActionEnd((e: GestureEvent): void => {
                this.onScrubEnd(e, true);
              })
              .onActionCancel((): void => {
                this.onScrubEnd(undefined, false);
              })
          ))

        // 顶栏
        Column() {
          this.TopBar()
        }
        .width('100%')
        .padding({ top: this.statusBarHeight })
        .linearGradient({ angle: 180, colors: [['#8F000000', 0], ['#00000000', 1]] })
        .position({ x: 0, y: 0 })
        .opacity(this.ctrl.showControls ? 1 : 0)
        .animation({ duration: 300, curve: Curve.EaseOut })
        .hitTestBehavior(this.ctrl.showControls ? HitTestMode.Default : HitTestMode.None)

        // 中央播放按钮
        if (this.ctrl.showControls && !this.ctrl.isLocked) {
          this.CenterPlayButton()
        }

        // 锁定按钮（左侧，未锁定时显示 lock_open；锁定后短暂显示 lock）
        if (!this.ctrl.isLocked) {
          Column() {
            SymbolGlyph($r('sys.symbol.lock_open'))
              .fontSize(24)
              .fontColor([PLAYER_WHITE])
          }
          .justifyContent(FlexAlign.Center)
          .width(48)
          .height(48)
          .position({ x: 20, y: '50%' })
          .markAnchor({ y: '50%' })
          .opacity(this.ctrl.showControls ? 1 : 0)
          .animation({ duration: 300, curve: Curve.EaseOut })
          .hitTestBehavior(this.ctrl.showControls ? HitTestMode.Default : HitTestMode.None)
          .onClick(() => {
            this.ctrl.lockScreen();
          })
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.lock'))
              .fontSize(24)
              .fontColor([PLAYER_WHITE])
          }
          .justifyContent(FlexAlign.Center)
          .width(48)
          .height(48)
          .position({ x: 20, y: '50%' })
          .markAnchor({ y: '50%' })
          .opacity(this.ctrl.showLockedIcon ? 1 : 0)
          .animation({ duration: 200, curve: Curve.EaseOut })
          .hitTestBehavior(this.ctrl.showLockedIcon ? HitTestMode.Default : HitTestMode.None)
          .onClick(() => {
            this.ctrl.unlockScreen();
          })
        }

        // 底栏
        Column() {
          this.BottomBar()
        }
        .width('100%')
        .position({ x: 0, y: '100%' })
        .markAnchor({ y: '100%' })
        .linearGradient({ angle: 0, colors: [['#8F000000', 0], ['#00000000', 1]] })
        .opacity(this.ctrl.showControls ? 1 : 0)
        .animation({ duration: 300, curve: Curve.EaseOut })
        .hitTestBehavior(this.ctrl.showControls ? HitTestMode.Default : HitTestMode.None)

        // 加载中
        if (!this.ctrl.isInitialized) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(PLAYER_WHITE)
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
        }

        // scrub 预览覆盖层
        if (this.scrubPreviewMs >= 0) {
          this.ScrubOverlay()
        }

        // 长按加速提示
        if (this.ctrl.isCtrlSpeedBoost) {
          Text(L10n.t('player_speed_boost_tip', '正在加速播放...'))
            .fontSize(14)
            .fontColor(PLAYER_WHITE)
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .borderRadius(8)
            .backgroundColor('#8A000000')
            .position({ x: 0, y: this.statusBarHeight + 12 })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .onAreaChange((_o: Area, n: Area): void => {
        this.pageWidth = Number(n.width);
        this.pageHeight = Number(n.height);
      })
    }
    .hideTitleBar(true)
    .onShown((): void => {
      this.setFullScreen(true);
      this.scheduleFullScreenRetry();
    })
    .onHidden((): void => {
      this.clearRetryTimer();
    })
    .onBackPressed((): boolean => {
      void this.exitPlayer();
      return true;
    })
  }

  private onSurfaceReady(): void {
    try {
      if (this.playlistOpened) {
        return;
      }
      const sid: string = this.xcController.getXComponentSurfaceId();
      this.playlistOpened = true;
      this.ctrl.attachSurface(sid);
      this.ctrl.ignoreFindSub = this.param.ignoreFindSub === 0 ? 0 : 1;
      const items: PlayerPlaylistItem[] = this.param.playlist;
      if (items.length > 0) {
        void this.ctrl.openPlaylist(items, this.param.initialIndex);
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'getSurfaceId failed: %{public}s', JSON.stringify(e));
    }
  }
}
