import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { APIClient } from '../../../core/network/APIClient';
import { BookArchiveImage, BookComicReaderApiService } from '../services/BookApiServices';

const TAG = 'BookComicReader';

/** 缩放模式（对齐 Flutter ComicFitMode） */
export enum ComicFitMode {
  FitScreen = 0,
  FitWidth = 1
}

/** 页面布局（对齐 Flutter ComicPageLayout） */
export enum ComicPageLayout {
  Single = 0,
  Double = 1
}

/** 阅读模式（对齐 Flutter ComicReadingMode） */
export enum ComicReadingMode {
  Ltr = 0,
  Rtl = 1,
  Vertical = 2
}

/**
 * 漫画阅读器控制器（对齐 Flutter BookComicReaderController）：
 * 页面列表加载 / 进度读取与防抖上报 / 适应模式·单双页·阅读方向·边距·背景色·自动播放等设置，
 * 设置按 baseUrl 隔离持久化。
 */
@ObservedV2
export class BookComicReaderController {
  readonly fileHash: string;
  readonly title: string;

  @Trace pages: BookArchiveImage[] = [];
  @Trace isLoading: boolean = true;
  @Trace isControlsVisible: boolean = true;
  @Trace errorMsg: string = '';
  @Trace fitMode: ComicFitMode = ComicFitMode.FitScreen;
  @Trace pageLayout: ComicPageLayout = ComicPageLayout.Single;
  @Trace readingMode: ComicReadingMode = ComicReadingMode.Ltr;
  @Trace sideMarginPercent: number = 0;
  @Trace backgroundColor: string = '#FF000000';
  @Trace autoPlayIntervalMs: number = 3000;
  @Trace showNavButtons: boolean = true;
  @Trace isAutoPlaying: boolean = false;
  @Trace isFullscreen: boolean = false;
  /** 当前逻辑跨页索引 */
  @Trace currentSpreadIndex: number = 0;

  /** 页面注入：跳转到指定逻辑跨页（参数为 Swiper 显示索引） */
  gotoSpreadDisplay: (displayIndex: number) => void = (_i: number): void => {
  };
  /** 页面注入：隐藏/恢复系统状态栏与导航条（全屏开关） */
  applySystemBars: (hidden: boolean) => void = (_h: boolean): void => {
  };

  /** 无服务器进度时的兜底页（路由参数 initialPage，0-based） */
  private fallbackInitialPage: number = 0;
  private initialPageIndex: number = -1;
  private saveDebounce: number = -1;
  private restoreTimer: number = -1;
  private autoPlayTimer: number = -1;
  private lastSavedSpread: number = -1;

  constructor(fileHash: string, title: string, fallbackPage: number) {
    this.fileHash = fileHash;
    this.title = title;
    this.fallbackInitialPage = Math.max(0, Math.floor(fallbackPage));
    this.loadLocalSettings();
  }

  // ================================ 派生状态 ================================

  get totalPages(): number {
    return this.pages.length;
  }

  get spreadCount(): number {
    if (this.pages.length === 0) {
      return 0;
    }
    return this.pageLayout === ComicPageLayout.Double
      ? Math.ceil(this.pages.length / 2) : this.pages.length;
  }

  get isVertical(): boolean {
    return this.readingMode === ComicReadingMode.Vertical;
  }

  get isRtl(): boolean {
    return this.readingMode === ComicReadingMode.Rtl;
  }

  get isDouble(): boolean {
    return this.pageLayout === ComicPageLayout.Double;
  }

  get isFitWidth(): boolean {
    return this.fitMode === ComicFitMode.FitWidth;
  }

  spreadIndexForPageIndex(pageIndex: number): number {
    if (this.pageLayout === ComicPageLayout.Double) {
      return Math.floor(pageIndex / 2);
    }
    return pageIndex;
  }

  primaryPageIndexForSpread(spreadIndex: number): number {
    if (this.pages.length === 0) {
      return 0;
    }
    if (this.pageLayout === ComicPageLayout.Double) {
      return Math.min(Math.max(spreadIndex * 2, 0), this.pages.length - 1);
    }
    return Math.min(Math.max(spreadIndex, 0), this.pages.length - 1);
  }

  /** 跨页包含的页索引（-1 表示空位）；双页 RTL 时主页在右（左页在前） */
  pageIndicesForSpread(spreadIndex: number): number[] {
    if (this.pages.length === 0) {
      return [];
    }
    const primary = this.primaryPageIndexForSpread(spreadIndex);
    if (this.pageLayout === ComicPageLayout.Single) {
      return [primary];
    }
    const second = primary + 1;
    const hasSecond = second < this.pages.length;
    if (this.readingMode === ComicReadingMode.Rtl) {
      return [hasSecond ? second : -1, primary];
    }
    return [primary, hasSecond ? second : -1];
  }

  /** Swiper 显示索引（RTL 时反转） */
  displayIndexOf(spreadIndex: number): number {
    if (!this.isRtl) {
      return spreadIndex;
    }
    return Math.max(0, this.spreadCount - 1 - spreadIndex);
  }

  spreadOfDisplayIndex(displayIndex: number): number {
    if (!this.isRtl) {
      return displayIndex;
    }
    return Math.max(0, this.spreadCount - 1 - displayIndex);
  }

  pageIndicatorText(spreadIndex: number): string {
    const count = this.spreadCount;
    if (count <= 0 || this.totalPages === 0) {
      return '0 / 0';
    }
    const idx = Math.min(Math.max(spreadIndex, 0), count - 1);
    const indices = this.pageIndicesForSpread(idx)
      .filter((v: number): boolean => v >= 0);
    if (indices.length === 0) {
      return `0 / ${this.totalPages}`;
    }
    if (indices.length === 1) {
      return `${indices[0] + 1} / ${this.totalPages}`;
    }
    return `${indices[0] + 1}-${indices[1] + 1} / ${this.totalPages}`;
  }

  // ================================ 加载 ================================

  async initLoad(): Promise<void> {
    this.isLoading = true;
    this.errorMsg = '';
    try {
      const progress = await BookComicReaderApiService.getProgress(this.fileHash);
      if (progress !== undefined) {
        const cp = Number(`${progress['current_page'] ?? -1}`);
        if (!Number.isNaN(cp) && cp >= 0) {
          this.initialPageIndex = Math.floor(cp);
        }
      }
      if (this.initialPageIndex < 0) {
        this.initialPageIndex = this.fallbackInitialPage;
      }
      this.pages = await BookComicReaderApiService.listArchiveImages(this.fileHash, true);
    } catch (e) {
      hilog.error(0x0000, TAG, 'initLoad failed: %{public}s', `${e}`);
      this.errorMsg = `${e}`;
    } finally {
      this.isLoading = false;
    }
  }

  /** 加载完成后取初始 Swiper 显示索引（只读，不消费） */
  takeInitialDisplayIndex(): number {
    if (this.pages.length === 0) {
      return 0;
    }
    const page = Math.min(Math.max(this.initialPageIndex, 0), this.pages.length - 1);
    return this.displayIndexOf(this.spreadIndexForPageIndex(page));
  }

  // ================================ 动作 ================================

  toggleControls(): void {
    this.isControlsVisible = !this.isControlsVisible;
    this.persistLocalSettings();
  }

  previousPage(): void {
    if (this.currentSpreadIndex <= 0) {
      return;
    }
    this.jumpToSpread(this.currentSpreadIndex - 1);
  }

  nextPage(): void {
    if (this.currentSpreadIndex >= this.spreadCount - 1) {
      return;
    }
    this.jumpToSpread(this.currentSpreadIndex + 1);
  }

  goToFirstPage(): void {
    if (this.spreadCount <= 0) {
      return;
    }
    this.jumpToSpread(0);
  }

  goToLastPage(): void {
    if (this.spreadCount <= 0) {
      return;
    }
    this.jumpToSpread(this.spreadCount - 1);
  }

  jumpToPageNumber(pageNumber1Based: number): void {
    if (this.pages.length === 0) {
      return;
    }
    const pageIndex = Math.min(Math.max(pageNumber1Based - 1, 0), this.pages.length - 1);
    this.jumpToSpread(this.spreadIndexForPageIndex(pageIndex));
  }

  private jumpToSpread(spreadIndex: number): void {
    if (this.spreadCount <= 0) {
      return;
    }
    const idx = Math.min(Math.max(spreadIndex, 0), this.spreadCount - 1);
    this.gotoSpreadDisplay(this.displayIndexOf(idx));
    this.handleSpreadDisplayChanged(this.displayIndexOf(idx));
  }

  toggleFitMode(): void {
    const keep = this.currentSpreadIndex;
    this.fitMode = this.fitMode === ComicFitMode.FitScreen
      ? ComicFitMode.FitWidth : ComicFitMode.FitScreen;
    if (this.fitMode !== ComicFitMode.FitWidth) {
      this.sideMarginPercent = 0;
    }
    this.scheduleRestoreSpread(keep);
    this.persistLocalSettings();
  }

  toggleAutoPlay(): void {
    this.isAutoPlaying = !this.isAutoPlaying;
    if (this.isAutoPlaying) {
      this.startAutoPlay();
    } else {
      this.stopAutoPlay();
    }
    this.persistLocalSettings();
  }

  private startAutoPlay(): void {
    this.stopAutoPlay();
    if (this.spreadCount <= 1) {
      return;
    }
    this.autoPlayTimer = setInterval((): void => {
      if (this.currentSpreadIndex >= this.spreadCount - 1) {
        this.isAutoPlaying = false;
        this.stopAutoPlay();
        return;
      }
      this.nextPage();
    }, this.autoPlayIntervalMs);
  }

  private stopAutoPlay(): void {
    if (this.autoPlayTimer >= 0) {
      clearInterval(this.autoPlayTimer);
      this.autoPlayTimer = -1;
    }
  }

  toggleFullscreen(): void {
    this.isFullscreen = !this.isFullscreen;
    this.applySystemBars(this.isFullscreen);
    this.persistLocalSettings();
  }

  togglePageLayout(): void {
    const keepPage = this.pages.length > 0
      ? this.primaryPageIndexForSpread(this.currentSpreadIndex) : 0;
    this.pageLayout = this.pageLayout === ComicPageLayout.Single
      ? ComicPageLayout.Double : ComicPageLayout.Single;
    this.scheduleRestoreSpread(this.spreadIndexForPageIndex(keepPage));
    this.persistLocalSettings();
  }

  setReadingMode(mode: ComicReadingMode): void {
    const keep = this.currentSpreadIndex;
    this.readingMode = mode;
    this.scheduleRestoreSpread(keep);
    this.persistLocalSettings();
  }

  cycleSideMargin(): void {
    if (this.fitMode !== ComicFitMode.FitWidth) {
      return;
    }
    const values: number[] = [0, 0.1, 0.2, 0.3, 0.4];
    const idx = values.findIndex((v: number): boolean =>
      Math.abs(v - this.sideMarginPercent) < 0.0001);
    const next = idx < 0 ? 0 : (idx + 1) % values.length;
    this.sideMarginPercent = values[next];
    this.persistLocalSettings();
  }

  setSideMargin(percent: number): void {
    if (this.fitMode !== ComicFitMode.FitWidth) {
      this.sideMarginPercent = 0;
    } else {
      this.sideMarginPercent = Math.min(Math.max(percent, 0), 0.4);
    }
    this.persistLocalSettings();
  }

  setBackgroundColor(hex: string): void {
    this.backgroundColor = hex;
    this.persistLocalSettings();
  }

  setAutoPlayIntervalSeconds(seconds: number): void {
    const safe = Math.min(Math.max(Math.round(seconds), 1), 120);
    this.autoPlayIntervalMs = safe * 1000;
    if (this.isAutoPlaying) {
      this.startAutoPlay();
    }
    this.persistLocalSettings();
  }

  toggleNavButtons(): void {
    this.showNavButtons = !this.showNavButtons;
    this.persistLocalSettings();
  }

  resetSettings(): void {
    this.fitMode = ComicFitMode.FitScreen;
    this.sideMarginPercent = 0;
    this.pageLayout = ComicPageLayout.Single;
    this.readingMode = ComicReadingMode.Ltr;
    this.backgroundColor = '#FF000000';
    this.autoPlayIntervalMs = 3000;
    this.showNavButtons = true;
    this.isAutoPlaying = false;
    this.stopAutoPlay();
    this.persistLocalSettings();
  }

  /** 模式切换后子组件按 key 重建，延迟恢复到原逻辑跨页 */
  private scheduleRestoreSpread(spreadIndex: number): void {
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (this.spreadCount <= 0) {
        return;
      }
      const idx = Math.min(Math.max(spreadIndex, 0), this.spreadCount - 1);
      this.gotoSpreadDisplay(this.displayIndexOf(idx));
    }, 80);
  }

  // ================================ 进度 ================================

  /** Swiper 显示索引变化（onChange）→ 逻辑跨页更新 + 防抖上报 */
  handleSpreadDisplayChanged(displayIndex: number): void {
    const logical = this.spreadOfDisplayIndex(displayIndex);
    const idx = Math.min(Math.max(logical, 0), Math.max(0, this.spreadCount - 1));
    this.currentSpreadIndex = idx;
    if (this.saveDebounce >= 0) {
      clearTimeout(this.saveDebounce);
    }
    this.saveDebounce = setTimeout((): void => {
      this.saveDebounce = -1;
      void this.saveProgress(idx);
    }, 600);
  }

  private async saveProgress(spreadIndex: number): Promise<void> {
    if (this.pages.length === 0) {
      return;
    }
    const idx = Math.min(Math.max(spreadIndex, 0), this.spreadCount - 1);
    if (idx === this.lastSavedSpread) {
      return;
    }
    this.lastSavedSpread = idx;
    await BookComicReaderApiService.upsertProgress(this.fileHash,
      this.primaryPageIndexForSpread(idx), this.pages.length);
  }

  // ================================ 本地设置 ================================

  private settingsKey(): string {
    return `comic_reader_settings_v1#${APIClient.getInstance().baseUrl.trim()}`;
  }

  private loadLocalSettings(): void {
    const raw = PreferencesStore.getInstance().getString(this.settingsKey());
    if (raw === undefined || raw.trim().length === 0) {
      return;
    }
    try {
      const m = JSON.parse(raw) as Record<string, Object>;
      const fm = `${m['fit_mode'] ?? ''}`;
      if (fm === 'fit_width') {
        this.fitMode = ComicFitMode.FitWidth;
      } else if (fm === 'fit_screen') {
        this.fitMode = ComicFitMode.FitScreen;
      }
      const pm = `${m['page_layout'] ?? ''}`;
      if (pm === 'double') {
        this.pageLayout = ComicPageLayout.Double;
      } else if (pm === 'single') {
        this.pageLayout = ComicPageLayout.Single;
      }
      const rm = `${m['reading_mode'] ?? ''}`;
      if (rm === 'rtl') {
        this.readingMode = ComicReadingMode.Rtl;
      } else if (rm === 'vertical') {
        this.readingMode = ComicReadingMode.Vertical;
      } else if (rm === 'ltr') {
        this.readingMode = ComicReadingMode.Ltr;
      }
      const sm = Number(`${m['side_margin_percent'] ?? 0}`);
      if (!Number.isNaN(sm)) {
        this.sideMarginPercent = Math.min(Math.max(sm, 0), 0.4);
      }
      const bg = `${m['background_color'] ?? ''}`;
      if (bg.length > 0) {
        this.backgroundColor = bg;
      }
      const ap = Number(`${m['autoplay_ms'] ?? 0}`);
      if (!Number.isNaN(ap) && ap > 0) {
        this.autoPlayIntervalMs = Math.min(Math.max(ap, 1000), 120000);
      }
      const sb = m['show_nav_buttons'];
      if (typeof sb === 'boolean') {
        this.showNavButtons = sb;
      }
    } catch (_e) {
      // 设置损坏时忽略，使用默认值
    }
  }

  private persistLocalSettings(): void {
    const m: Record<string, Object> = {
      'fit_mode': this.fitMode === ComicFitMode.FitWidth ? 'fit_width' : 'fit_screen',
      'side_margin_percent': this.sideMarginPercent,
      'page_layout': this.pageLayout === ComicPageLayout.Double ? 'double' : 'single',
      'reading_mode': this.readingMode === ComicReadingMode.Rtl ? 'rtl'
        : (this.readingMode === ComicReadingMode.Vertical ? 'vertical' : 'ltr'),
      'background_color': this.backgroundColor,
      'autoplay_ms': this.autoPlayIntervalMs,
      'show_nav_buttons': this.showNavButtons
    };
    void PreferencesStore.getInstance().setString(this.settingsKey(), JSON.stringify(m));
  }

  /** 页面销毁：停定时器 + 立即上报当前进度 */
  destroy(): void {
    this.stopAutoPlay();
    if (this.saveDebounce >= 0) {
      clearTimeout(this.saveDebounce);
      this.saveDebounce = -1;
    }
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
    if (this.pages.length > 0 && this.lastSavedSpread !== this.currentSpreadIndex) {
      void BookComicReaderApiService.upsertProgress(this.fileHash,
        this.primaryPageIndexForSpread(this.currentSpreadIndex), this.pages.length);
    }
  }
}
