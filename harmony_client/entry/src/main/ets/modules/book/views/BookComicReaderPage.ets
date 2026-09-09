import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { WindowStore } from '../../../common/WindowStore';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../../common/SheetUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { ZoomableImage } from '../../../common/components/ZoomableImage';
import { AppImage } from '../../../common/components/AppImage';
import { BookComicReaderParam } from '../router/BookRoutes';
import {
  BookComicReaderController,
  ComicFitMode,
  ComicPageLayout,
  ComicReadingMode
} from '../controllers/BookComicReaderController';
import { BookArchiveImage } from '../services/BookApiServices';

const TAG = 'BookComicReader';
const OVERLAY_BG = '#59000000';
const PILL_BG = '#80000000';
const PREVIEW_BG = '#F2000000';

/** 跨页数据源（LazyForEach：configKey 参与子组件 key，配置变化时整体重建） */
class SpreadDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  count: number = 0;
  configKey: string = '';

  totalCount(): number {
    return this.count;
  }

  getData(i: number): number {
    return i;
  }

  registerDataChangeListener(l: DataChangeListener): void {
    this.listeners.push(l);
  }

  unregisterDataChangeListener(l: DataChangeListener): void {
    const idx = this.listeners.indexOf(l);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  reload(count: number, configKey: string): void {
    this.count = count;
    this.configKey = configKey;
    this.listeners.forEach((l: DataChangeListener): void => {
      l.onDataReloaded();
    });
  }
}

/**
 * 漫画阅读器（对齐 Flutter BookComicReaderPage）：
 * 全屏阅读（适应屏幕/适应宽度、单双页、LTR/RTL/垂直、边距、背景色）+
 * 点击显隐控制栏（6s 自动隐藏）+ 导航按钮 + 自动播放 + 预览网格 +
 * 设置底部弹层与配色弹层，进度防抖上报服务器。
 */
@ComponentV2
export struct BookComicReaderPage {
  @Param param: BookComicReaderParam = new BookComicReaderParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: BookComicReaderController = new BookComicReaderController('', '', 0);
  @Local statusBarHeight: number = 0;
  @Local navBarHeight: number = 0;
  /** 当前跨页是否有图片处于放大状态（禁用 Swiper 滑动） */
  @Local zoomedSpread: boolean = false;
  @Local showPreview: boolean = false;
  @Local bodyW: number = 0;
  @Local isPhoneLayout: boolean = true;
  private swiperController: SwiperController = new SwiperController();
  private spreadSource: SpreadDataSource = new SpreadDataSource();
  private retryTimer: number = -1;
  private controlsTimer: number = -1;
  private didStartAutoHide: boolean = false;

  aboutToAppear(): void {
    this.ctrl = new BookComicReaderController(this.param.fileHash, this.param.title,
      this.param.initialPage);
    this.ctrl.gotoSpreadDisplay = (displayIndex: number): void => {
      this.swiperController.changeIndex(displayIndex, false);
    };
    this.ctrl.applySystemBars = (hidden: boolean): void => {
      this.setSystemBarsHidden(hidden);
    };
    this.setFullScreen(true);
    this.fetchSafeArea();
    BookComicReaderPage.applyReaderStatusBar();
    void this.ctrl.initLoad().then((): void => {
      this.reloadSpreadSource();
      const displayIdx = this.ctrl.takeInitialDisplayIndex();
      setTimeout((): void => {
        this.swiperController.changeIndex(displayIdx, false);
        this.ctrl.handleSpreadDisplayChanged(displayIdx);
        if (!this.didStartAutoHide) {
          this.didStartAutoHide = true;
          if (this.ctrl.isControlsVisible) {
            this.bumpControlsAutoHide();
          }
        }
      }, 60);
    });
  }

  aboutToDisappear(): void {
    this.clearRetryTimer();
    this.clearControlsTimer();
    this.ctrl.destroy();
    this.setSystemBarsHidden(false);
    // 不写 setWindowLayoutFullScreen(false)：返回目标是沉浸式图书主页（其 onShown 确保 true），
    // 此处写 false 会与主页 onShown 的 true 竞态，失败时主页停留避让布局被双重避让挤压
  }

  @Monitor('ctrl.fitMode', 'ctrl.pageLayout', 'ctrl.readingMode', 'ctrl.sideMarginPercent')
  onReaderConfigChanged(): void {
    this.zoomedSpread = false;
    this.reloadSpreadSource();
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

  private setSystemBarsHidden(hidden: boolean): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    try {
      w.setWindowSystemBarEnable(hidden ? [] : ['status', 'navigation'])
        .catch((_e: Object): void => {
        });
    } catch (_e) {
      // 系统条设置失败不阻塞阅读
    }
  }

  private static applyReaderStatusBar(): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    try {
      w.setWindowSystemBarProperties({
        statusBarContentColor: '#FFFFFF',
        statusBarColor: '#00000000'
      });
    } catch (_e) {
      // 忽略
    }
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

  // ================================ 控制栏显隐 ================================

  private bumpControlsAutoHide(): void {
    this.clearControlsTimer();
    this.controlsTimer = setTimeout((): void => {
      this.controlsTimer = -1;
      if (this.ctrl.isControlsVisible) {
        this.ctrl.isControlsVisible = false;
      }
    }, 6000);
  }

  private clearControlsTimer(): void {
    if (this.controlsTimer >= 0) {
      clearTimeout(this.controlsTimer);
      this.controlsTimer = -1;
    }
  }

  private toggleControlsFromTap(): void {
    this.ctrl.toggleControls();
    if (!this.ctrl.isControlsVisible) {
      this.clearControlsTimer();
      return;
    }
    this.bumpControlsAutoHide();
  }

  // ================================ 交互 ================================

  private reloadSpreadSource(): void {
    const key = `${this.ctrl.fitMode}|${this.ctrl.pageLayout}|${this.ctrl.readingMode}|` +
      `${this.ctrl.sideMarginPercent}`;
    this.spreadSource.reload(this.ctrl.spreadCount, key);
  }

  private onPageZoom(pageIndex: number, zoomed: boolean): void {
    if (this.ctrl.pageIndicesForSpread(this.ctrl.currentSpreadIndex).indexOf(pageIndex) >= 0) {
      this.zoomedSpread = zoomed;
    }
  }

  private tapGoLeft(): void {
    if (this.ctrl.isVertical) {
      this.ctrl.previousPage();
      return;
    }
    if (this.ctrl.isRtl) {
      this.ctrl.nextPage();
      return;
    }
    this.ctrl.previousPage();
  }

  private tapGoRight(): void {
    if (this.ctrl.isVertical) {
      this.ctrl.nextPage();
      return;
    }
    if (this.ctrl.isRtl) {
      this.ctrl.previousPage();
      return;
    }
    this.ctrl.nextPage();
  }

  private hPad(): number {
    if (this.ctrl.isFitWidth && this.bodyW > 0) {
      return this.bodyW * this.ctrl.sideMarginPercent / 2;
    }
    return 0;
  }

  private previewItemH(): number {
    const w = this.bodyW > 0 ? this.bodyW : 360;
    const itemW = (w - 24 - 16) / 3;
    return itemW / 0.7;
  }

  private shortcutDialogTitle(): string {
    const raw = L10n.t('comic_reader_shortcuts', '');
    const idxCn = raw.indexOf('：');
    const idxEn = raw.indexOf(':');
    const idx = idxCn >= 0 ? idxCn : idxEn;
    return idx > 0 ? raw.substring(0, idx).trim() : 'Shortcuts';
  }

  private async showShortcutHelp(): Promise<void> {
    await DialogUtil.showInfoDialog(this.shortcutDialogTitle(),
      L10n.t('comic_reader_shortcuts', ''));
  }

  private async promptNumber(title: string, hint: string, initial: number,
    onOk: (v: number) => void): Promise<void> {
    const r = await DialogUtil.showInputDialog(title, hint, `${initial}`);
    if (typeof r === 'string') {
      const v = parseInt(r.trim(), 10);
      if (!Number.isNaN(v)) {
        onOk(v);
      }
    }
  }

  private openSettingsSheet(): void {
    this.bumpControlsAutoHide();
    const p = new ComicSettingsSheetParams();
    p.ctrl = this.ctrl;
    p.onIntervalRequested = (): void => {
      p.close();
      void this.promptNumber(
        L10n.t('comic_reader_autoplay_interval', '自动播放间隔'),
        L10n.t('comic_reader_seconds', '秒'),
        Math.round(this.ctrl.autoPlayIntervalMs / 1000),
        (v: number): void => {
          this.ctrl.setAutoPlayIntervalSeconds(v);
        });
    };
    p.onJumpRequested = (): void => {
      p.close();
      void this.promptNumber(
        L10n.t('comic_reader_jump_to_page', '跳转页码'),
        L10n.t('comic_reader_page_hint', '请输入页码（1-@total）',
          L10n.paramsOf('total', `${this.ctrl.totalPages}`)),
        this.ctrl.primaryPageIndexForSpread(this.ctrl.currentSpreadIndex) + 1,
        (v: number): void => {
          this.ctrl.jumpToPageNumber(v);
        });
    };
    p.onColorRequested = (): void => {
      p.close();
      this.openColorPicker();
    };
    SheetUtil.present<ComicSettingsSheetParams>(p, comicSettingsSheetBuilder);
  }

  private openColorPicker(): void {
    const p = new ComicColorPickerParams();
    p.initial = this.ctrl.backgroundColor;
    p.onPick = (hex: string): void => {
      this.ctrl.setBackgroundColor(hex);
    };
    SheetUtil.present<ComicColorPickerParams>(p, comicColorPickerBuilder);
  }

  // ================================ 渲染 ================================

  build() {
    NavDestination() {
      Stack() {
        // 背景色层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.ctrl.backgroundColor)

        if (this.ctrl.isLoading) {
          this.CenterMessage(L10n.t('loading', '加载中...'))
        } else if (this.ctrl.pages.length === 0) {
          this.CenterMessage(L10n.t('no_data', '暂无数据'))
        } else {
          this.ReaderArea()
        }

        // 导航按钮（垂直：上下；水平：左右）
        if (this.ctrl.showNavButtons && this.ctrl.isControlsVisible &&
          !this.ctrl.isLoading && this.ctrl.pages.length > 0) {
          this.NavButtons()
        }

        // 顶部控制栏
        if (this.ctrl.isControlsVisible && !this.ctrl.isLoading) {
          this.TopControls()
        }

        // 右下角页码指示
        if (this.ctrl.isControlsVisible && this.ctrl.pages.length > 0) {
          this.PageIndicator()
        }

        // 预览浮层
        if (this.showPreview) {
          this.PreviewOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_o: Area, n: Area): void => {
        this.bodyW = Number(n.width);
        this.isPhoneLayout = Math.min(Number(n.width), Number(n.height)) < 600;
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.ctrl.backgroundColor)
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
  CenterMessage(msg: string) {
    Column() {
      Text(msg)
        .fontSize(14)
        .fontColor(AppTheme.withAlpha('#FFFFFF', 0.7))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ReaderArea() {
    Swiper(this.swiperController) {
      LazyForEach(this.spreadSource, (spreadIndex: number) => {
        Column() {
          this.SpreadContent(spreadIndex)
        }
        .width('100%')
        .height('100%')
      }, (spreadIndex: number): string => `${this.spreadSource.configKey}_${spreadIndex}`)
    }
    .vertical(this.ctrl.isVertical)
    .loop(false)
    .indicator(false)
    .cachedCount(1)
    .duration(240)
    .disableSwipe(this.zoomedSpread)
    .onChange((idx: number): void => {
      this.ctrl.handleSpreadDisplayChanged(idx);
      this.zoomedSpread = false;
      if (!this.ctrl.isAutoPlaying) {
        this.bumpControlsAutoHide();
      }
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  SpreadContent(spreadIndex: number) {
    Row() {
      ForEach(this.ctrl.pageIndicesForSpread(spreadIndex), (pageIndex: number, cellIdx: number) => {
        if (pageIndex >= 0) {
          Column() {
            this.ComicPageImage(pageIndex)
          }
          .layoutWeight(1)
          .height('100%')
        } else {
          Column()
            .layoutWeight(1)
            .height('100%')
        }
      }, (pageIndex: number, cellIdx: number): string => `c${cellIdx}_${pageIndex}`)
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.hPad(), right: this.hPad() })
  }

  @Builder
  ComicPageImage(pageIndex: number) {
    if (pageIndex >= 0 && pageIndex < this.ctrl.pages.length) {
      ZoomableImage({
        url: this.ctrl.pages[pageIndex].url,
        fitWidthMode: this.ctrl.isFitWidth,
        doubleTapScale: 3,
        idlePanDirection: this.ctrl.isVertical ? PanDirection.Horizontal : PanDirection.Vertical,
        onSingleTap: (_x: number, _y: number): void => {
          this.toggleControlsFromTap();
        },
        onZoomChanged: (zoomed: boolean): void => {
          this.onPageZoom(pageIndex, zoomed);
        }
      })
        .width('100%')
        .height('100%')
    }
  }

  @Builder
  NavButtons() {
    Stack() {
      if (this.ctrl.isVertical) {
        Column() {
          this.NavCircleButton($r('sys.symbol.chevron_up'), 40, (): void => {
            this.ctrl.previousPage();
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 8 })

        Column() {
          this.NavCircleButton($r('sys.symbol.chevron_down'), 40, (): void => {
            this.ctrl.nextPage();
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 8 })
      } else {
        Row() {
          this.NavCircleButton($r('sys.symbol.chevron_left'), 60, (): void => {
            this.tapGoLeft();
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 8 })

        Row() {
          this.NavCircleButton($r('sys.symbol.chevron_right'), 60, (): void => {
            this.tapGoRight();
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
        .padding({ right: 8 })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  NavCircleButton(icon: Resource, iconSize: number, onTap: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(iconSize)
        .fontColor(['#FFFFFF'])
    }
    .width(iconSize + 28)
    .height(iconSize + 28)
    .borderRadius(999)
    .backgroundColor(OVERLAY_BG)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      this.bumpControlsAutoHide();
      onTap();
    })
  }

  @Builder
  TopControls() {
    Row({ space: 4 }) {
      this.CircleIconButton($r('sys.symbol.arrow_left'), 22, (): void => {
        this.popPage();
      })
      if (!this.isPhoneLayout) {
        Text(this.ctrl.title)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 6 })
      }
      Blank()
      this.CircleIconButton($r('sys.symbol.questionmark_circle'), 20, (): void => {
        void this.showShortcutHelp();
      })
      this.CircleIconButton($r('sys.symbol.plus_magnifyingglass'), 20, (): void => {
        this.ctrl.toggleFullscreen();
      })
      this.CircleIconButton(this.ctrl.isAutoPlaying
        ? $r('sys.symbol.stop_circle') : $r('sys.symbol.play_fill'), 22, (): void => {
        this.ctrl.toggleAutoPlay();
      })
      this.CircleIconButton($r('sys.symbol.grid'), 20, (): void => {
        this.showPreview = true;
      })
      this.CircleIconButton($r('sys.symbol.gearshape'), 20, (): void => {
        this.openSettingsSheet();
      })
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .alignItems(VerticalAlign.Center)
    .padding({ top: this.statusBarHeight, left: 8, right: 8 })
    .backgroundColor(OVERLAY_BG)
    .position({ x: 0, y: 0 })
  }

  @Builder
  CircleIconButton(icon: Resource, iconSize: number, onTap: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(iconSize)
        .fontColor(['#FFFFFF'])
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      this.bumpControlsAutoHide();
      onTap();
    })
  }

  @Builder
  PageIndicator() {
    Text(this.ctrl.pageIndicatorText(this.ctrl.currentSpreadIndex))
      .fontSize(12)
      .fontColor('#FFFFFF')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(999)
      .backgroundColor(PILL_BG)
      .position({ x: '100%', y: '100%' })
      .markAnchor({ x: '100%', y: '100%' })
      .translate({ x: -12, y: -(this.navBarHeight + 12) })
  }

  @Builder
  PreviewOverlay() {
    Column() {
      Row({ space: 10 }) {
        this.CircleIconButton($r('sys.symbol.arrow_left'), 20, (): void => {
          this.showPreview = false;
        })
        Text(L10n.t('comic_reader_preview', '预览模式'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.ctrl.pageIndicatorText(this.ctrl.currentSpreadIndex))
          .fontSize(12)
          .fontColor(AppTheme.withAlpha('#FFFFFF', 0.7))
      }
      .width('100%')
      .height(52 + this.statusBarHeight)
      .alignItems(VerticalAlign.Center)
      .padding({ top: this.statusBarHeight, left: 8, right: 16 })

      Scroll() {
        Column() {
          Grid() {
            ForEach(this.ctrl.pages, (page: BookArchiveImage, index: number) => {
              GridItem() {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  AppImage({ url: page.url, showLoadingSpin: true })
                    .width('100%')
                    .height('100%')
                  Text(`${index + 1}`)
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(999)
                    .backgroundColor('#99000000')
                    .margin(6)
                }
                .width('100%')
                .height(this.previewItemH())
                .borderRadius(8)
                .clip(true)
                .onClick((): void => {
                  this.showPreview = false;
                  this.ctrl.jumpToPageNumber(index + 1);
                })
              }
            }, (page: BookArchiveImage): string => page.innerPath)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .width('100%')
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: this.navBarHeight + 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PREVIEW_BG)
    .onClick((): void => {
      this.showPreview = false;
    })
  }
}

// ===== 设置弹层（对齐 Flutter _showSettingsSheet） =====

const COMIC_MARGIN_LABELS: string[] = ['0%', '10%', '20%', '30%', '40%'];
const COMIC_BG_PRESETS: string[] = [
  '#FF000000', '#FFFFFFFF', '#FF212121', '#FF616161',
  '#FF263238', '#FF0F0F0F', '#FF1B263B', '#FF2D2A32'
];

class ComicSettingsSheetParams extends SheetParamsBase {
  ctrl: BookComicReaderController = new BookComicReaderController('', '', 0);
  onIntervalRequested: () => void = (): void => {
  };
  onJumpRequested: () => void = (): void => {
  };
  onColorRequested: () => void = (): void => {
  };
}

@ComponentV2
struct ComicSettingsSheet {
  @Param params: ComicSettingsSheetParams = new ComicSettingsSheetParams();

  private fitModeLabel(): string {
    return this.params.ctrl.isFitWidth
      ? L10n.t('comic_reader_fit_width', '适应宽度')
      : L10n.t('comic_reader_fit_screen', '适应屏幕');
  }

  private layoutLabel(): string {
    return this.params.ctrl.isDouble
      ? L10n.t('comic_reader_layout_double', '双页')
      : L10n.t('comic_reader_layout_single', '单页');
  }

  private marginSelected(idx: number): boolean {
    return Math.abs(idx * 0.1 - this.params.ctrl.sideMarginPercent) < 0.05;
  }

  build() {
    Column() {
      SheetHandle()
      Scroll() {
        Column() {
          // 自动播放
          this.SwitchRow($r('sys.symbol.play_fill'),
            L10n.t('comic_reader_autoplay', '自动播放'), this.params.ctrl.isAutoPlaying,
            (): void => {
              this.params.ctrl.toggleAutoPlay();
            })
          // 自动播放间隔
          this.NavRow($r('sys.symbol.timer'),
            L10n.t('comic_reader_autoplay_interval', '自动播放间隔'),
            `${Math.round(this.params.ctrl.autoPlayIntervalMs / 1000)} ${L10n.t('comic_reader_seconds', '秒')}`,
            (): void => {
              this.params.onIntervalRequested();
            })
          // 缩放模式
          this.NavRow($r('sys.symbol.square_grid_2x2'),
            L10n.t('comic_reader_fit_mode', '缩放模式'), this.fitModeLabel(),
            (): void => {
              this.params.ctrl.toggleFitMode();
            })
          // 两侧边距
          this.MarginRow()
          // 页面布局
          this.NavRow($r('sys.symbol.rectangle_stack'),
            L10n.t('comic_reader_page_layout', '页面布局'), this.layoutLabel(),
            (): void => {
              this.params.ctrl.togglePageLayout();
            })
          // 阅读模式
          this.ReadingModeRow()
          // 背景颜色
          this.ColorRow()
          // 翻页按钮
          this.SwitchRow($r('sys.symbol.arrow_left'),
            L10n.t('comic_reader_nav_buttons', '翻页按钮'), this.params.ctrl.showNavButtons,
            (): void => {
              this.params.ctrl.toggleNavButtons();
            })
          // 跳转页码
          this.NavRow($r('sys.symbol.list_number'),
            L10n.t('comic_reader_jump_to_page', '跳转页码'), '',
            (): void => {
              this.params.onJumpRequested();
            })
          // 重置设置
          this.NavRow($r('sys.symbol.arrow_counterclockwise'),
            L10n.t('comic_reader_reset_settings', '重置设置'), '',
            (): void => {
              this.params.ctrl.resetSettings();
            })
          // 快捷键说明
          Text(L10n.t('comic_reader_shortcuts', ''))
            .fontSize(11)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.5))
            .margin({ top: 10, bottom: 8 })
            .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 460 })
    }
    .width('100%')
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  @Builder
  SwitchRow(icon: Resource, label: string, on: boolean, onTap: () => void) {
    Row({ space: 14 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([AppTheme.current().onSurface])
      Text(label)
        .fontSize(15)
        .fontColor(AppTheme.current().onSurface)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(AppTheme.current().primary)
        .onChange((_on: boolean): void => {
          onTap();
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  NavRow(icon: Resource, label: string, value: string, onTap: () => void) {
    Row({ space: 14 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([AppTheme.current().onSurface])
      Text(label)
        .fontSize(15)
        .fontColor(AppTheme.current().onSurface)
        .layoutWeight(1)
      if (value.length > 0) {
        Text(value)
          .fontSize(13)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick((): void => {
      onTap();
    })
  }

  @Builder
  MarginRow() {
    Column({ space: 8 }) {
      Row({ space: 14 }) {
        SymbolGlyph($r('sys.symbol.text_alignleft'))
          .fontSize(20)
          .fontColor([AppTheme.current().onSurface])
        Column({ space: 2 }) {
          Text(L10n.t('comic_reader_side_margin', '两侧边距'))
            .fontSize(15)
            .fontColor(AppTheme.current().onSurface)
          if (!this.params.ctrl.isFitWidth) {
            Text(L10n.t('comic_reader_side_margin_hint', '仅在“适应宽度”下可用'))
              .fontSize(11)
              .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.5))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Row({ space: 8 }) {
        ForEach(COMIC_MARGIN_LABELS, (label: string, idx: number) => {
          Text(label)
            .fontSize(13)
            .fontColor(this.marginSelected(idx)
              ? AppTheme.current().buttonText : AppTheme.current().onSurface)
            .opacity(this.params.ctrl.isFitWidth ? 1 : 0.4)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(this.marginSelected(idx)
              ? AppTheme.current().primary : AppTheme.current().surfaceBg)
            .border({ width: 0.8, color: AppTheme.current().divider })
            .onClick((): void => {
              this.params.ctrl.setSideMargin(idx * 0.1);
            })
        }, (label: string): string => label)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  ReadingModeRow() {
    Column({ space: 8 }) {
      Row({ space: 14 }) {
        SymbolGlyph($r('sys.symbol.arrowtriangle_left_fill'))
          .fontSize(20)
          .fontColor([AppTheme.current().onSurface])
        Text(L10n.t('comic_reader_reading_mode', '阅读模式'))
          .fontSize(15)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.ModeChip(L10n.t('comic_reader_mode_ltr', '从左到右'), ComicReadingMode.Ltr)
        this.ModeChip(L10n.t('comic_reader_mode_rtl', '从右到左'), ComicReadingMode.Rtl)
        this.ModeChip(L10n.t('comic_reader_mode_vertical', '垂直'), ComicReadingMode.Vertical)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  ModeChip(label: string, mode: ComicReadingMode) {
    Text(label)
      .fontSize(13)
      .fontColor(this.params.ctrl.readingMode === mode
        ? AppTheme.current().buttonText : AppTheme.current().onSurface)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(999)
      .backgroundColor(this.params.ctrl.readingMode === mode
        ? AppTheme.current().primary : AppTheme.current().surfaceBg)
      .border({ width: 0.8, color: AppTheme.current().divider })
      .onClick((): void => {
        this.params.ctrl.setReadingMode(mode);
      })
  }

  @Builder
  ColorRow() {
    Row({ space: 14 }) {
      Column()
        .width(20)
        .height(20)
        .borderRadius(6)
        .backgroundColor(this.params.ctrl.backgroundColor)
        .border({ width: 0.8, color: AppTheme.current().divider })
      Text(L10n.t('comic_reader_background_color', '背景颜色'))
        .fontSize(15)
        .fontColor(AppTheme.current().onSurface)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick((): void => {
      this.params.onColorRequested();
    })
  }
}

const comicSettingsSheetBuilder: WrappedBuilder<[ComicSettingsSheetParams]> =
  wrapBuilder(ComicSettingsSheetBuilderFn);

@Builder
function ComicSettingsSheetBuilderFn(params: ComicSettingsSheetParams) {
  ComicSettingsSheet({ params: params })
}

// ===== 配色弹层（对齐 Flutter _showColorPickerDialog，移动端适配为底部弹层） =====

class ComicColorPickerParams extends SheetParamsBase {
  initial: string = '#FF000000';
  onPick: (hex: string) => void = (_h: string): void => {
  };
}

@ComponentV2
struct ComicColorPickerSheet {
  @Param params: ComicColorPickerParams = new ComicColorPickerParams();
  @Local current: string = '#FF000000';
  @Local hexText: string = 'FF000000';

  aboutToAppear(): void {
    this.current = this.params.initial;
    this.hexText = this.toHex8(this.params.initial);
  }

  private toHex8(hex: string): string {
    let h = hex.trim().replace('#', '').toUpperCase();
    if (h.length === 6) {
      h = `FF${h}`;
    }
    return h;
  }

  private applyHex(text: string): void {
    const cleaned = text.trim().replace('#', '').toUpperCase();
    if (!/^[0-9A-F]+$/.test(cleaned)) {
      return;
    }
    if (cleaned.length === 6) {
      this.current = `#FF${cleaned}`;
    } else if (cleaned.length === 8) {
      this.current = `#${cleaned}`;
    }
  }

  build() {
    Column({ space: 14 }) {
      SheetHandle()
      Text(L10n.t('comic_reader_background_color', '背景颜色'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')

      // 预设色（两行各 4 个）
      Row({ space: 10 }) {
        ForEach(COMIC_BG_PRESETS.slice(0, 4), (c: string) => {
          this.PresetDot(c)
        }, (c: string): string => c)
      }
      .width('100%')
      Row({ space: 10 }) {
        ForEach(COMIC_BG_PRESETS.slice(4), (c: string) => {
          this.PresetDot(c)
        }, (c: string): string => c)
      }
      .width('100%')

      TextInput({ text: this.hexText })
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .backgroundColor(AppTheme.current().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .height(42)
        .width('100%')
        .onChange((v: string): void => {
          this.applyHex(v);
        })

      // 预览
      Row({ space: 10 }) {
        Text(L10n.t('comic_reader_preview', '预览'))
          .fontSize(13)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        Column()
          .layoutWeight(1)
          .height(24)
          .borderRadius(6)
          .backgroundColor(this.current)
          .border({ width: 0.8, color: AppTheme.current().divider })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button(L10n.t('cancel', '取消'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick((): void => {
            this.params.close();
          })
        Button(L10n.t('ok', '确定'))
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(36)
          .onClick((): void => {
            this.params.close();
            this.params.onPick(this.current);
          })
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .width('100%')
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  @Builder
  PresetDot(color: string) {
    Column()
      .layoutWeight(1)
      .height(32)
      .borderRadius(8)
      .backgroundColor(color)
      .border({
        width: this.current === color ? 2 : 0.8,
        color: this.current === color ? AppTheme.current().primary : AppTheme.current().divider
      })
      .onClick((): void => {
        this.current = color;
        this.hexText = this.toHex8(color);
      })
  }
}

const comicColorPickerBuilder: WrappedBuilder<[ComicColorPickerParams]> =
  wrapBuilder(ComicColorPickerBuilderFn);

@Builder
function ComicColorPickerBuilderFn(params: ComicColorPickerParams) {
  ComicColorPickerSheet({ params: params })
}
