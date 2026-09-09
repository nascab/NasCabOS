import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { PageScaffold } from '../../../common/PageScaffold';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../../common/SheetUtil';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { BookTxtReaderParam } from '../router/BookRoutes';
import { BookComicReaderApiService } from '../services/BookApiServices';
import { BookTxtPaginator, TxtPage, TxtLine, TxtReadStyle } from '../reader/BookTxtPaginator';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'BookTxtReader';

/** 页数据源（LazyForEach） */
class TxtPagesDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  pages: TxtPage[] = [];

  totalCount(): number {
    return this.pages.length;
  }

  getData(i: number): TxtPage | undefined {
    return i >= 0 && i < this.pages.length ? this.pages[i] : undefined;
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

  reload(pages: TxtPage[]): void {
    this.pages = pages;
    this.listeners.forEach((l: DataChangeListener): void => {
      l.onDataReloaded();
    });
  }
}

/**
 * TXT 阅读器（对齐 Flutter BookTxtReaderPage）：
 * 标题栏（进度条滑块 + 重排 + 设置）+ 分页阅读区（左右点击翻页/中间弹菜单），
 * 字体/行距/颜色/背景/编码/显示进度设置弹层，本地进度 + 服务器进度上报。
 */
@ComponentV2
export struct BookTxtReaderPage {
  @Param param: BookTxtReaderParam = new BookTxtReaderParam();
  @Param popPage: () => void = (): void => {
  };

  @Local loading: boolean = true;
  @Local errorText: string = '';
  @Local pageTotal: number = 0;
  @Local pageIndex: number = 0;
  @Local showProgressBar: boolean = true;
  @Local encoding: string = 'auto';
  @Local style: TxtReadStyle = new TxtReadStyle();
  /** 进度滑块拖动中的临时值（1-based，null 表示未拖动） */
  @Local navScrubPage1: number = -1;

  private paginator: BookTxtPaginator = new BookTxtPaginator();
  private dataSource: TxtPagesDataSource = new TxtPagesDataSource();
  private swiperController: SwiperController = new SwiperController();
  private bodyW: number = 0;
  private bodyH: number = 0;
  private contentReady: boolean = false;
  private pendingOffset: number = 0;
  private persistTimer: number = -1;
  private styleDebounceTimer: number = -1;
  private lastUploadedPage: number = -1;

  // ================================ 生命周期 ================================

  aboutToAppear(): void {
    this.style = this.loadStyle();
    this.showProgressBar = PreferencesStore.getInstance()
      .getBool('book_txt_show_progress', true);
    this.encoding = (PreferencesStore.getInstance()
      .getString(`book_txt_encoding:${this.param.fileHash}`, 'auto') ?? 'auto').trim();
    if (this.encoding.length === 0) {
      this.encoding = 'auto';
    }
    this.pendingOffset = this.loadSavedOffset();
    void this.initLoad();
  }

  aboutToDisappear(): void {
    this.clearTimer(this.persistTimer);
    this.clearTimer(this.styleDebounceTimer);
    void this.flushPersist();
  }

  private clearTimer(t: number): void {
    if (t >= 0) {
      clearTimeout(t);
    }
  }

  // ================================ 持久化 ================================

  private loadStyle(): TxtReadStyle {
    const raw = PreferencesStore.getInstance().getString('book_txt_style');
    if (raw === undefined || raw.trim().length === 0) {
      return new TxtReadStyle();
    }
    try {
      return TxtReadStyle.fromJson(JSON.parse(raw) as Object);
    } catch (_e) {
      return new TxtReadStyle();
    }
  }

  private loadSavedOffset(): number {
    const raw = PreferencesStore.getInstance()
      .getString(`book_txt_progress:${this.param.fileHash}`);
    if (raw === undefined || raw.trim().length === 0) {
      return 0;
    }
    try {
      const m = JSON.parse(raw) as Record<string, Object>;
      const off = Number(`${m['charOffset'] ?? 0}`);
      return Number.isNaN(off) ? 0 : Math.max(0, Math.floor(off));
    } catch (_e) {
      return 0;
    }
  }

  private persistLocal(): void {
    if (this.pageTotal <= 0) {
      return;
    }
    const page = this.paginator.pages[this.pageIndex];
    const off = page !== undefined ? page.charStart : 0;
    const m: Record<string, Object> = {
      'chapterIndex': page !== undefined ? page.chapterIndex : 0,
      'sentenceIndex': 0,
      'wordIndex': 0,
      'pageIndex': this.pageIndex,
      'pageTotal': this.pageTotal,
      'charOffset': off
    };
    void PreferencesStore.getInstance()
      .setString(`book_txt_progress:${this.param.fileHash}`, JSON.stringify(m));
  }

  private persistServer(): void {
    if (this.pageTotal <= 0) {
      return;
    }
    const idx = Math.min(Math.max(this.pageIndex, 0), this.pageTotal - 1);
    if (idx === this.lastUploadedPage) {
      return;
    }
    this.lastUploadedPage = idx;
    void BookComicReaderApiService.upsertProgress(this.param.fileHash, idx, this.pageTotal);
  }

  private async flushPersist(): Promise<void> {
    this.clearTimer(this.persistTimer);
    this.persistTimer = -1;
    this.persistLocal();
    this.persistServer();
  }

  private schedulePersist(): void {
    this.clearTimer(this.persistTimer);
    this.persistTimer = setTimeout((): void => {
      this.persistTimer = -1;
      this.persistLocal();
      this.persistServer();
    }, 600);
  }

  // ================================ 加载与分页 ================================

  private async initLoad(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const ok = await this.paginator.load(this.param.localFilePath, this.encoding);
      if (!ok) {
        this.errorText = L10n.operationFailed;
        this.loading = false;
        return;
      }
      this.paginator.splitChapters();
      this.contentReady = true;
      this.runPaginate();
      this.loading = false;
    } catch (e) {
      hilog.error(0x0000, TAG, 'initLoad failed: %{public}s', JSON.stringify(e));
      this.errorText = L10n.networkFailure;
      this.loading = false;
    }
  }

  /** 内容与视口均就绪后执行分页并定位进度 */
  private runPaginate(): void {
    if (!this.contentReady || this.bodyW <= 0 || this.bodyH <= 0) {
      return;
    }
    this.paginator.setViewport(this.bodyW, this.bodyH);
    this.paginator.paginate(this.style);
    this.pageTotal = this.paginator.pages.length;
    this.pageIndex = this.paginator.findPageByCharOffset(this.pendingOffset);
    this.dataSource.reload(this.paginator.pages);
    this.lastUploadedPage = -1;
    if (this.pageIndex === this.swiperCurrent()) {
      // index 相同不触发 onPageChanged，手动补一次进度
      this.schedulePersist();
    }
  }

  private swiperCurrent(): number {
    // Swiper index 由 @Local pageIndex 驱动，重排后一致
    return this.pageIndex;
  }

  private scheduleApplyStyle(next: TxtReadStyle): void {
    this.clearTimer(this.styleDebounceTimer);
    this.styleDebounceTimer = setTimeout((): void => {
      this.styleDebounceTimer = -1;
      this.applyStyleNow(next);
    }, 280);
  }

  private applyStyleNow(next: TxtReadStyle): void {
    this.clearTimer(this.styleDebounceTimer);
    this.styleDebounceTimer = -1;
    // 记录当前页首偏移用于重排恢复
    const cur = this.paginator.pages[this.pageIndex];
    if (cur !== undefined) {
      this.pendingOffset = cur.charStart;
    }
    this.style = next;
    void PreferencesStore.getInstance()
      .setString('book_txt_style', JSON.stringify(next.toJson()));
    this.runPaginate();
  }

  private async reloadWithEncoding(encoding: string): Promise<void> {
    const next = encoding.trim();
    if (next.length === 0 || next === this.encoding) {
      return;
    }
    this.encoding = next;
    void PreferencesStore.getInstance()
      .setString(`book_txt_encoding:${this.param.fileHash}`, next);
    const cur = this.paginator.pages[this.pageIndex];
    if (cur !== undefined) {
      this.pendingOffset = cur.charStart;
    }
    this.loading = true;
    const ok = await this.paginator.load(this.param.localFilePath, next);
    if (ok) {
      this.paginator.splitChapters();
      this.runPaginate();
    }
    // 失败保持旧内容（对齐 Flutter 静默处理）
    this.loading = false;
  }

  private reflow(): void {
    const cur = this.paginator.pages[this.pageIndex];
    if (cur !== undefined) {
      this.pendingOffset = cur.charStart;
    }
    this.runPaginate();
  }

  // ================================ 交互 ================================

  private onPageChanged(index: number): void {
    if (index === this.pageIndex) {
      return;
    }
    this.pageIndex = Math.min(Math.max(index, 0), Math.max(0, this.pageTotal - 1));
    this.navScrubPage1 = -1;
    this.schedulePersist();
  }

  private handleTap(localX: number): void {
    const w = this.bodyW;
    if (w > 0 && localX < w * 0.3) {
      this.jumpRelative(-1);
    } else if (w > 0 && localX > w * 0.7) {
      this.jumpRelative(1);
    } else {
      this.openMenu();
    }
  }

  private jumpRelative(delta: number): void {
    const target = this.pageIndex + delta;
    if (target < 0 || target > this.pageTotal - 1) {
      return;
    }
    this.swiperController.changeIndex(target, true);
  }

  private jumpToPage(page1: number): void {
    if (this.pageTotal <= 0) {
      return;
    }
    const target = Math.min(Math.max(page1, 1), this.pageTotal) - 1;
    this.swiperController.changeIndex(target, true);
  }

  private progressText(): string {
    if (this.pageTotal <= 0) {
      return '';
    }
    const idx = Math.min(Math.max(this.pageIndex, 0), this.pageTotal - 1) + 1;
    return `${idx}/${this.pageTotal}`;
  }

  private openMenu(): void {
    const p = new TxtSettingsSheetParams();
    p.style = this.style;
    p.pageTotal = this.pageTotal;
    p.currentPage1 = Math.min(Math.max(this.pageIndex, 0), Math.max(0, this.pageTotal - 1)) + 1;
    p.showProgressBar = this.showProgressBar;
    p.encoding = this.encoding;
    p.onStyleChange = (next: TxtReadStyle, immediate: boolean): void => {
      if (immediate) {
        this.applyStyleNow(next);
      } else {
        this.scheduleApplyStyle(next);
      }
    };
    p.onShowProgress = (v: boolean): void => {
      this.showProgressBar = v;
      void PreferencesStore.getInstance().setBool('book_txt_show_progress', v);
    };
    p.onEncoding = (v: string): void => {
      void this.reloadWithEncoding(v);
    };
    p.onJump = (page1: number): void => {
      this.jumpToPage(page1);
    };
    SheetUtil.present<TxtSettingsSheetParams>(p, txtSettingsSheetBuilder);
  }

  // ================================ 渲染 ================================

  build() {
    PageScaffold({
      title: this.param.title,
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TopActions()
      },
      content: (): void => {
        this.PageBody()
      }
    })
  }

  @Builder
  TopActions() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(20)
        .fontColor([AppTheme.current().appBarFg])
        .onClick((): void => {
          this.reflow();
        })
      SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
        .fontSize(20)
        .fontColor([AppTheme.current().appBarFg])
        .onClick((): void => {
          this.openMenu();
        })
    }
  }

  @Builder
  PageBody() {
    Column() {
      // 进度条行（可开关，对齐 Flutter AppBar.bottom）
      if (this.showProgressBar && this.progressText().length > 0) {
        this.ProgressSlider()
      }
      if (this.errorText.length > 0) {
        Column({ space: 12 }) {
          Text(this.errorText)
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
            .textAlign(TextAlign.Center)
          Text(L10n.t('retry', '重试'))
            .fontSize(14)
            .fontColor(AppTheme.current().buttonText)
            .padding({ left: 20, right: 20, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor(AppTheme.current().primary)
            .onClick((): void => {
              void this.initLoad();
            })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height('100%')
      } else {
        Stack() {
          Swiper(this.swiperController) {
            LazyForEach(this.dataSource, (page: TxtPage) => {
              Column() {
                this.ReaderPageContent(page)
              }
              .width('100%')
              .height('100%')
              .backgroundColor(this.style.bgColor)
              .onClick((e: ClickEvent): void => {
                this.handleTap(e.x);
              })
            }, (page: TxtPage): string => `p${page.charStart}`)
          }
          .index(this.pageIndex)
          .loop(false)
          .indicator(false)
          .cachedCount(1)
          .duration(240)
          .vertical(false)
          .onChange((index: number): void => {
            this.onPageChanged(index);
          })
          .width('100%')
          .height('100%')

          if (this.loading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(AppTheme.current().primary)
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .height('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .onAreaChange((_o: Area, n: Area): void => {
          this.bodyW = Number(n.width);
          this.bodyH = Number(n.height);
          this.runPaginate();
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ProgressSlider() {
    Row({ space: 12 }) {
      Slider({
        value: this.navScrubPage1 >= 0
          ? this.navScrubPage1
          : Math.min(Math.max(this.pageIndex + 1, 1), Math.max(this.pageTotal, 1)),
        min: 1,
        max: Math.max(this.pageTotal, 1),
        step: 1,
        style: SliderStyle.OutSet
      })
        .selectedColor(AppTheme.current().primary)
        .trackThickness(2)
        .blockSize({ width: 12, height: 12 })
        .layoutWeight(1)
        .onChange((value: number, mode: SliderChangeMode): void => {
          if (mode === SliderChangeMode.Moving || mode === SliderChangeMode.Begin) {
            this.navScrubPage1 = value;
          } else if (mode === SliderChangeMode.End) {
            this.jumpToPage(Math.round(value));
            this.navScrubPage1 = -1;
          }
        })
      Text(this.navScrubPage1 >= 0
        ? `${Math.round(this.navScrubPage1)}/${this.pageTotal}`
        : this.progressText())
        .fontSize(11)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        .width(56)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 4 })
  }

  @Builder
  ReaderPageContent(page: TxtPage) {
    Column() {
      ForEach(page.lines, (line: TxtLine, idx: number) => {
        this.ReaderLine(line, idx === 0)
      }, (line: TxtLine): string => `${line.charStart}_${line.text.length}`)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: this.style.padL,
      right: this.style.padR,
      top: this.style.padT,
      bottom: this.style.padB
    })
  }

  @Builder
  ReaderLine(line: TxtLine, isFirst: boolean) {
    if (line.text.length === 0) {
      // 空段落间隔
      Row()
        .height(Math.ceil(BookTxtPaginator.lineHeightOf(this.style, false) * 0.45))
        .width('100%')
    } else if (line.isTitle) {
      Text(line.text)
        .fontSize(this.style.fontSize + 2)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.style.textColor)
        .lineHeight(BookTxtPaginator.lineHeightOf(this.style, true))
        .width('100%')
    } else {
      Text(line.text)
        .fontSize(this.style.fontSize)
        .fontColor(this.style.textColor)
        .lineHeight(BookTxtPaginator.lineHeightOf(this.style, false))
        .margin({ top: line.isParaStart && !isFirst ? Math.ceil(this.style.fontSize * 0.35) : 0 })
        .width('100%')
    }
  }
}

// ===== 设置弹层（对齐 Flutter _openMenu bottom sheet） =====

class TxtSettingsSheetParams extends SheetParamsBase {
  style: TxtReadStyle = new TxtReadStyle();
  pageTotal: number = 0;
  currentPage1: number = 1;
  showProgressBar: boolean = true;
  encoding: string = 'auto';
  onStyleChange: (style: TxtReadStyle, immediate: boolean) => void = (_s: TxtReadStyle, _i: boolean): void => {
  };
  onShowProgress: (v: boolean) => void = (_v: boolean): void => {
  };
  onEncoding: (v: string) => void = (_v: string): void => {
  };
  onJump: (page1: number) => void = (_p: number): void => {
  };
}

const TXT_BG_CANDIDATES: string[] = ['#E2E8DC', '#FFFFFF', '#F6EBD5', '#000000'];
const TXT_FG_CANDIDATES: string[] =
  ['#000000', '#2B2B2B', '#404040', '#666666', '#888888', '#5B4636', '#FFFFFF'];

@ComponentV2
struct TxtSettingsSheet {
  @Param params: TxtSettingsSheetParams = new TxtSettingsSheetParams();
  @Local menuFontSize: number = 16;
  @Local menuLineSpacing: number = 4;
  @Local menuEncoding: string = 'auto';
  @Local menuBg: string = '#FFFFFF';
  @Local menuFg: string = '#000000';
  @Local menuShowProgress: boolean = true;
  @Local menuJumpPage: number = 1;

  aboutToAppear(): void {
    this.menuFontSize = Math.min(Math.max(this.params.style.fontSize, 10), 32);
    this.menuLineSpacing = Math.min(Math.max(this.params.style.lineSpacing, 0), 24);
    this.menuEncoding = this.params.encoding;
    this.menuBg = this.params.style.bgColor;
    this.menuFg = this.params.style.textColor;
    this.menuShowProgress = this.params.showProgressBar;
    this.menuJumpPage = Math.min(Math.max(this.params.currentPage1, 1), Math.max(this.params.pageTotal, 1));
  }

  private buildNext(): TxtReadStyle {
    const next = this.params.style.clone();
    next.fontSize = this.menuFontSize;
    next.textColor = this.menuFg;
    next.bgColor = this.menuBg;
    next.lineSpacing = this.menuLineSpacing;
    return next;
  }

  private label(key: string, fallback: string): string {
    return L10n.t(key, fallback);
  }

  build() {
    Column({ space: 12 }) {
      SheetHandle()
      Text(this.label('txt_reader_settings', '阅读设置'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')

      Scroll() {
        Column({ space: 12 }) {
          // 显示进度
          Row() {
            Text(this.label('txt_reader_show_progress', '显示进度条'))
              .fontSize(15)
              .fontColor(AppTheme.current().onSurface)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.menuShowProgress })
              .selectedColor(AppTheme.current().primary)
              .onChange((on: boolean): void => {
                this.menuShowProgress = on;
                this.params.onShowProgress(on);
              })
          }
          .width('100%')

          // 编码
          Row({ space: 8 }) {
            Text(this.label('txt_reader_encoding', '文件编码'))
              .fontSize(15)
              .fontColor(AppTheme.current().onSurface)
              .layoutWeight(1)
            this.EncChip('auto', this.label('auto', '自动'))
            this.EncChip('utf8', 'UTF-8')
            this.EncChip('gbk', 'GBK')
          }
          .width('100%')

          // 字号
          Text(this.label('txt_reader_font_size', '字号'))
            .fontSize(15)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
          Row({ space: 12 }) {
            Slider({
              value: this.menuFontSize,
              min: 10,
              max: 32,
              step: 1,
              style: SliderStyle.OutSet
            })
              .selectedColor(AppTheme.current().primary)
              .layoutWeight(1)
              .onChange((value: number, mode: SliderChangeMode): void => {
                this.menuFontSize = Math.round(value);
                this.params.onStyleChange(this.buildNext(), false);
                if (mode === SliderChangeMode.End) {
                  this.params.onStyleChange(this.buildNext(), true);
                }
              })
            Text(`${this.menuFontSize}`)
              .fontSize(13)
              .fontColor(AppTheme.current().onSurface)
              .width(28)
              .textAlign(TextAlign.End)
          }
          .width('100%')

          // 行距
          Text(this.label('txt_reader_line_spacing', '行间距'))
            .fontSize(15)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
          Row({ space: 12 }) {
            Slider({
              value: this.menuLineSpacing,
              min: 0,
              max: 24,
              step: 1,
              style: SliderStyle.OutSet
            })
              .selectedColor(AppTheme.current().primary)
              .layoutWeight(1)
              .onChange((value: number, mode: SliderChangeMode): void => {
                this.menuLineSpacing = Math.round(value);
                this.params.onStyleChange(this.buildNext(), false);
                if (mode === SliderChangeMode.End) {
                  this.params.onStyleChange(this.buildNext(), true);
                }
              })
            Text(`${this.menuLineSpacing}`)
              .fontSize(13)
              .fontColor(AppTheme.current().onSurface)
              .width(28)
              .textAlign(TextAlign.End)
          }
          .width('100%')

          // 文字颜色
          Text(this.label('txt_reader_text_color', '文字颜色'))
            .fontSize(15)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
          Row({ space: 10 }) {
            ForEach(TXT_FG_CANDIDATES, (c: string) => {
              this.ColorDot(c, this.menuFg === c, (): void => {
                this.menuFg = c;
                this.params.onStyleChange(this.buildNext(), true);
              })
            }, (c: string): string => c)
          }
          .width('100%')

          // 背景
          Text(this.label('txt_reader_background', '背景颜色'))
            .fontSize(15)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
          Row({ space: 10 }) {
            ForEach(TXT_BG_CANDIDATES, (c: string) => {
              this.ColorDot(c, this.menuBg === c, (): void => {
                this.menuBg = c;
                this.params.onStyleChange(this.buildNext(), true);
              })
            }, (c: string): string => c)
          }
          .width('100%')

          // 跳转页码
          if (this.params.pageTotal > 0) {
            Text(this.label('comic_reader_jump_to_page', '跳转到页'))
              .fontSize(15)
              .fontColor(AppTheme.current().onSurface)
              .width('100%')
            Row({ space: 12 }) {
              Slider({
                value: this.menuJumpPage,
                min: 1,
                max: this.params.pageTotal,
                step: 1,
                style: SliderStyle.OutSet
              })
                .selectedColor(AppTheme.current().primary)
                .layoutWeight(1)
                .onChange((value: number, mode: SliderChangeMode): void => {
                  this.menuJumpPage = Math.round(value);
                  if (mode === SliderChangeMode.End) {
                    this.params.onJump(Math.round(value));
                  }
                })
              Text(`${Math.round(this.menuJumpPage)}/${this.params.pageTotal}`)
                .fontSize(12)
                .fontColor(AppTheme.current().onSurface)
                .width(56)
                .textAlign(TextAlign.End)
            }
            .width('100%')
          }
        }
        .width('100%')
      }
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 420 })
    }
    .width('100%')
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  @Builder
  EncChip(value: string, label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.menuEncoding === value ? AppTheme.current().buttonText : AppTheme.current().onSurface)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(999)
      .backgroundColor(this.menuEncoding === value ? AppTheme.current().primary : AppTheme.current().surfaceBg)
      .border({ width: 0.8, color: AppTheme.current().divider })
      .onClick((): void => {
        this.menuEncoding = value;
        this.params.close();
        this.params.onEncoding(value);
      })
  }

  @Builder
  ColorDot(color: string, selected: boolean, onTap: () => void) {
    Column()
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor(color)
      .border({
        width: selected ? 2 : 1,
        color: selected ? AppTheme.current().primary : AppTheme.current().divider
      })
      .onClick((): void => {
        onTap();
      })
  }
}

const txtSettingsSheetBuilder: WrappedBuilder<[TxtSettingsSheetParams]> =
  wrapBuilder(TxtSettingsSheetBuilderFn);

@Builder
function TxtSettingsSheetBuilderFn(params: TxtSettingsSheetParams) {
  TxtSettingsSheet({ params: params })
}
