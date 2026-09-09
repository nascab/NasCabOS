import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { AppImage } from '../../../common/components/AppImage';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { BookListItem } from '../models/BookModels';
import { BookListApiService } from '../services/BookApiServices';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { BookLocalCacheService } from '../services/BookLocalCacheService';

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
  private cacheSvc: BookLocalCacheService = BookLocalCacheService.getInstance();

  aboutToAppear(): void {
    void this.resolveCoverUrls();
  }

  @Monitor('item')
  onItemChange(): void {
    this.useSecondary = false;
    void this.resolveCoverUrls();
  }

  private isPdfCover(): boolean {
    const item = this.item;
    const ext = item.ext.trim().toLowerCase();
    if (ext === 'pdf' || ext === '.pdf') {
      return true;
    }
    return endsWithPdf(item.fullPath) || endsWithPdf(item.filename) || endsWithPdf(item.firstFilePath);
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

        // 多选勾选框（右下角）
        if (this.selectionMode) {
          Column() {
            CircleCheckbox({
              value: this.selected,
              boxSize: 22,
              uncheckedBorderColor: '#FFFFFF',
              onChanged: (checked: boolean): void => {
                if (checked !== this.selected) {
                  this.onToggleSelected(this.item);
                }
              }
            })
          }
          .position({ x: '100%', y: '100%' })
          .markAnchor({ x: '100%', y: '100%' })
          .translate({ x: -6, y: -6 })
        }
      }
      .width('100%')

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
    .onClick(() => {
      if (this.selectionMode) {
        this.onToggleSelected(this.item);
      } else {
        this.onOpen(this.item);
      }
    })
    .gesture(LongPressGesture({ repeat: false }).onAction((): void => {
      this.onToggleSelected(this.item);
    }))
  }
}
