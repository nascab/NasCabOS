import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { AppImage } from '../../../common/components/AppImage';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { BookListItem } from '../models/BookModels';
import { BookListApiService } from '../services/BookApiServices';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { BookLocalCacheService } from '../services/BookLocalCacheService';
import { BookListController } from '../controllers/BookControllers';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DIAG_DOM: number = 0xB00C;

/** 封面占位图（对齐 Flutter _fallbackAssets） */
const FALLBACK_COVERS: ResourceStr[] = [
  $rawfile('icons/book/book_blue.jpg'),
  $rawfile('icons/book/book_brown.jpg'),
  $rawfile('icons/book/book_red.jpg'),
  $rawfile('icons/book/book_green.jpg')
];
const PDF_COVER: ResourceStr = $rawfile('icons/book/pdf.jpg');
const SERIES_BOOKS_PNG: ResourceStr = $rawfile('icons/book/books.png');

/** 稳定 hash（对齐 Flutter _stableIndex：p*31+e 取 31 位正数取模） */
function stableIndex(seed: string, count: number): number {
  if (seed.length === 0) {
    return 0;
  }
  let h = 0;
  for (let i = 0; i < seed.length; i++) {
    h = (h * 31 + seed.charCodeAt(i)) & 0x7fffffff;
  }
  return h % count;
}

function endsWithPdf(path: string): boolean {
  return path.trim().toLowerCase().endsWith('.pdf');
}

/** 展示用元信息行文本（对齐 Flutter BookItemCard meta 行） */
function metaText(item: BookListItem, cached: boolean): string {
  let text = '';
  if (item.isSeries) {
    const params = new Map<string, string>();
    params.set('count', `${item.bookCount}`);
    text = L10n.t('book_item_books', '', params);
  } else if (item.isComicType) {
    if (item.totalPage > 0) {
      if (item.currentPage > 0 && item.currentPage < item.totalPage) {
        text = `${item.currentPage}/${item.totalPage}`;
      } else {
        const p = new Map<string, string>();
        p.set('count', `${item.totalPage}`);
        text = L10n.t('book_item_pages', '', p);
      }
    }
  } else if (item.fraction > 0) {
    // book 类型：已读显示百分比
    text = `${Math.round(item.fraction * 100)}%`;
  }
  if (cached && text.length > 0) {
    return `${L10n.t('book_item_downloaded', '已下载')} ${text}`;
  }
  return text;
}

/**
 * 图书列表项卡片（对齐 Flutter BookItemCard mobile layout）：
 * 纵向封面（3:4 圆角 8）+ 标题（2 行）+ 元信息行；左上收藏钮、右上 more 钮；
 * 系列封面 = 4 色底图 + books.png 居中；pdf 用 pdf.jpg；
 * 无封面按 hash 取 4 色占位图 + 黑遮罩白字标题；网络图 primary→secondary→占位。
 */
@ComponentV2
export struct BookItemCard {
  @Param item: BookListItem = new BookListItem();
  /** 列表控制器：非可选，首次 build 即存在，保证本 item 对 isMultiSelectMode
   *  的读取一定建立订阅（严格对齐 PhotoTimelineItem）。历史等 Lite 用法不传时
   *  使用默认实例（isMultiSelectMode 恒 false，不显示勾选）。 */
  @Param ctrl: BookListController = new BookListController();
  @Param selectionMode: boolean = false;
  @Param selected: boolean = false;
  @Param isInCustomList: boolean = false;
  @Param onToggleSelected: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Param onToggleFavorite: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Param onMore: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Param onOpen: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Local primaryUrl: string = '';
  @Local secondaryUrl: string = '';
  @Local useSecondary: boolean = false;
  /** 封面实测宽/高（vp）：多选框用固定数值定位右下角（对齐照片 item） */
  @Local coverW: number = 0;
  @Local coverH: number = 0;
  private cacheSvc: BookLocalCacheService = BookLocalCacheService.getInstance();

  aboutToAppear(): void {
    void this.resolveCoverUrls();
  }

  @Monitor('item')
  onItemChange(): void {
    this.useSecondary = false;
    void this.resolveCoverUrls();
  }

  @Monitor('ctrl')
  onCtrlChange(): void {
    hilog.info(DIAG_DOM, 'BOOKITEM', 'ctrl param CHANGED id=%{public}d mode=%{public}s',
      this.item.id, this.ctrl.isMultiSelectMode ? 'T' : 'F');
  }

  @Monitor('selectionMode')
  onSelModeChange(): void {
    hilog.info(DIAG_DOM, 'BOOKITEM', 'selectionMode param CHANGED id=%{public}d v=%{public}s',
      this.item.id, this.selectionMode ? 'T' : 'F');
  }

  private isPdfCover(): boolean {
    const item = this.item;
    const ext = item.ext.trim().toLowerCase();
    if (ext === 'pdf' || ext === '.pdf') {
      return true;
    }
    return endsWithPdf(item.fullPath) || endsWithPdf(item.filename) || endsWithPdf(item.firstFilePath);
  }

  /** 是否处于多选：直接读控制器可观察字段（item 自身建立订阅） */
  private inSelection(): boolean {
    const v: boolean = this.ctrl.isMultiSelectMode;
    hilog.info(DIAG_DOM, 'BOOKITEM', 'read inSel id=%{public}d v=%{public}s selParam=%{public}s',
      this.item.id, v ? 'T' : 'F', this.selectionMode ? 'T' : 'F');
    return v;
  }

  /** 本 item 是否选中：直接读控制器（订阅 @Trace selectedItems） */
  private isItemSelected(): boolean {
    return this.ctrl.isSelected(this.item.id);
  }

  /** 封面类型：folder / pdf / fallback / network（对齐 Flutter _coverForActionSheet 分支） */
  private coverKind(): string {
    const item = this.item;
    if (item.isSeries) {
      return 'folder';
    }
    if (this.isPdfCover()) {
      return 'pdf';
    }
    const shouldFallback = item.coverState === 2 ||
      (item.fileHash.trim().length === 0 && item.fullPath.trim().length === 0);
    return shouldFallback ? 'fallback' : 'network';
  }

  private async resolveCoverUrls(): Promise<void> {
    const kind = this.coverKind();
    if (kind !== 'network') {
      this.primaryUrl = '';
      this.secondaryUrl = '';
      return;
    }
    const item = this.item;
    const hash = item.fileHash.trim();
    const fullPath = item.fullPath.trim();
    const firstFilePath = item.firstFilePath.trim();
    let primary = '';
    if (hash.length > 0) {
      primary = BookListApiService.buildTinyUrl(hash, 500);
    } else if (fullPath.length > 0) {
      primary = await ApiUrls.getTinyUrl(fullPath, 500);
    } else if (firstFilePath.length > 0) {
      primary = await ApiUrls.getTinyUrl(firstFilePath, 500);
    }
    let secondary = '';
    if (fullPath.length > 0) {
      secondary = await ApiUrls.getTinyUrl(fullPath, 500);
    } else if (firstFilePath.length > 0) {
      secondary = await ApiUrls.getTinyUrl(firstFilePath, 500);
    }
    this.primaryUrl = primary;
    this.secondaryUrl = secondary;
  }

  private onPrimaryFail(): void {
    if (this.useSecondary) {
      // secondary 也失败：清空走占位封面
      this.useSecondary = false;
      this.primaryUrl = '';
      this.secondaryUrl = '';
      return;
    }
    if (this.secondaryUrl.length > 0) {
      this.useSecondary = true;
    } else {
      this.primaryUrl = '';
    }
  }

  private fallbackBgIndex(): number {
    const item = this.item;
    const seed = item.fileHash.trim().length > 0 ? item.fileHash : item.fullPath;
    return stableIndex(seed, FALLBACK_COVERS.length);
  }

  private folderBgIndex(): number {
    const item = this.item;
    const seed = item.fullPath.trim().length > 0 ? item.fullPath.trim()
      : (item.firstFilePath.trim().length > 0 ? item.firstFilePath.trim() : `${item.id}`);
    return stableIndex(seed, FALLBACK_COVERS.length);
  }

  /** 当前下载进度（观察缓存服务 @Trace Map） */
  private downloadProgressOf(): number {
    const v = this.cacheSvc.downloadProgress.get(this.item.fileHash.trim());
    return v !== undefined ? v : 0;
  }

  @Builder
  CoverInner() {
    Stack() {
      if (this.coverKind() === 'folder') {
        // 系列封面：4 色底图 + books.png 居中
        Image(FALLBACK_COVERS[this.folderBgIndex()])
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
        Image(SERIES_BOOKS_PNG)
          .width(72)
          .height(72)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      } else if (this.coverKind() === 'pdf') {
        Image(PDF_COVER)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else if (this.coverKind() === 'fallback') {
        // 占位封面：底图 + 黑 35% 遮罩 + 白字标题
        Image(FALLBACK_COVERS[this.fallbackBgIndex()])
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
        Column() {
          Text(this.item.displayTitle)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(10)
        .backgroundColor('#59000000')
      } else if (!this.useSecondary && this.primaryUrl.length > 0) {
        AppImage({
          url: this.primaryUrl,
          showLoadingSpin: false,
          onLoaded: (ok: boolean): void => {
            if (!ok) {
              this.onPrimaryFail();
            }
          }
        })
      } else if (this.useSecondary && this.secondaryUrl.length > 0) {
        AppImage({
          url: this.secondaryUrl,
          showLoadingSpin: false,
          onLoaded: (ok: boolean): void => {
            if (!ok) {
              this.onPrimaryFail();
            }
          }
        })
      } else {
        Image(FALLBACK_COVERS[this.fallbackBgIndex()])
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      }

      // 下载进度遮罩（对齐 Flutter 下载中胶囊条）
      if (this.downloadProgressOf() > 0 && this.downloadProgressOf() < 1) {
        Column() {
          Progress({ value: Math.round(this.downloadProgressOf() * 100), type: ProgressType.Linear })
            .width(140)
            .height(6)
            .color('#FFFFFF')
            .backgroundColor('#80000000')
          Text(`${Math.round(this.downloadProgressOf() * 100)}%`)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .margin({ top: 4 })
        }
        .width(160)
        .padding({ top: 8, bottom: 8 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#88000000')
        .borderRadius(20)
      }
    }
    .width('100%')
    .aspectRatio(3 / 4)
    .borderRadius(8)
    .clip(true)
  }

  build() {
    Column() {
      // 封面区
      Stack({ alignContent: Alignment.TopEnd }) {
        this.CoverInner()

        // 右上 ext 徽标（系列显示“系列”）
        Text(this.item.isSeries ? L10n.t('series', '系列') : this.item.extLabel)
          .fontSize(10)
          .fontColor('#FFFFFF')
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .backgroundColor('#88000000')
          .borderRadius(4)
          .margin({ top: 4, right: 4 })

        // 左上收藏钮
        Column() {
          SymbolGlyph($r(this.item.isFavorite ? 'sys.symbol.heart_fill' : 'sys.symbol.heart'))
            .fontSize(17)
            .fontColor([this.item.isFavorite ? AppTheme.current().error : '#FFFFFF'])
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#59000000')
        .borderRadius(15)
        .position({ x: 6, y: 6 })
        .onClick(() => {
          this.onToggleFavorite(this.item);
        })

        // 右上 more 钮
        Column() {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(18)
            .fontColor(['#FFFFFF'])
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#59000000')
        .borderRadius(15)
        .position({ x: '100%', y: 6 })
        .markAnchor({ x: '100%', y: 0 })
        .translate({ x: -6, y: 0 })
        .onClick(() => {
          this.onMore(this.item);
        })

        // 多选勾选框（右下角：CircleCheckbox 直接作为 Stack 子节点 + 固定数值定位，
        // 严格对齐照片 PhotoTimelineItem，避免 if 新挂载的“包裹 Column + 百分比定位”不显示）
        if (this.inSelection()) {
          CircleCheckbox({
            value: this.isItemSelected(),
            boxSize: 22,
            uncheckedBorderColor: '#FFFFFF',
            onChanged: (checked: boolean): void => {
              if (checked !== this.isItemSelected()) {
                this.onToggleSelected(this.item);
              }
            }
          })
            .position({ x: this.coverW - 28, y: this.coverH - 28 })
        }
      }
      .width('100%')
      .onAreaChange((_o: Area, n: Area): void => {
        this.coverW = n.width as number;
        this.coverH = n.height as number;
      })

      // 标题
      Text(this.item.displayTitle)
        .fontSize(13)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .height(38)
        .margin({ top: 2 })
        .textAlign(TextAlign.Start)

      // 元信息行
      Text(metaText(this.item, this.cacheSvc.isCached(this.item.fileHash)))
        .fontSize(11)
        .fontColor(AppTheme.current().hint)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .height(16)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    // 点击与长按放入 Exclusive 互斥手势组：
    // 避免“长按进入多选并选中 → 抬手 Click 又触发取消 → 选中集为空自动退出多选”，
    // 导致长按后右下角 checkbox 一闪即逝。对齐 Flutter：多选态点击=切换选中，
    // 非多选态点击=打开，长按=进入多选。
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 1 })
          .onAction((_e: GestureEvent): void => {
            if (this.inSelection()) {
              this.onToggleSelected(this.item);
            } else {
              this.onOpen(this.item);
            }
          }),
        LongPressGesture({ repeat: false, fingers: 1, duration: 500 })
          .onAction((_e: GestureEvent): void => {
            if (!this.inSelection()) {
              this.onToggleSelected(this.item);
            }
          })
      )
    )
  }
}
