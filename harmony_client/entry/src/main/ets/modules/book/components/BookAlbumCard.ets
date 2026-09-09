import { AppImage } from '../../../common/components/AppImage';
import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { BookListItem, BookCollectionPreviewItem } from '../models/BookModels';
import { BookListApiService } from '../services/BookApiServices';
import { ApiUrls } from '../../../core/network/ApiUrls';

/** 占位封面 4 色图（对齐 Flutter fallbackAssets） */
export const BOOK_FALLBACK_COVERS: ResourceStr[] = [
  $rawfile('icons/book/book_blue.jpg'),
  $rawfile('icons/book/book_brown.jpg'),
  $rawfile('icons/book/book_red.jpg'),
  $rawfile('icons/book/book_green.jpg')
];
const BG_BOOKLIST: ResourceStr = $rawfile('book/bg_booklist.jpg');

/** 稳定 hash（对齐 Flutter _stableIndex：p*31+e 取 31 位正数取模） */
export function stableCoverIndex(seed: string, count: number): number {
  if (seed.length === 0) {
    return 0;
  }
  let h = 0;
  for (let i = 0; i < seed.length; i++) {
    h = (h * 31 + seed.charCodeAt(i)) & 0x7fffffff;
  }
  return h % count;
}

/** 预览封面原始数据（书单 previews 与合集 previews 的统一描述） */
export class BookPreviewCoverSpec {
  showType: string = '';
  fileHash: string = '';
  fullPath: string = '';
  firstFilePath: string = '';
  coverState: number = 0;

  static fromBookItem(b: BookListItem): BookPreviewCoverSpec {
    const r = new BookPreviewCoverSpec();
    r.showType = b.showType;
    r.fileHash = b.fileHash;
    r.fullPath = b.fullPath;
    r.firstFilePath = b.firstFilePath;
    r.coverState = b.coverState;
    return r;
  }

  static fromCollectionPreview(b: BookCollectionPreviewItem): BookPreviewCoverSpec {
    const r = new BookPreviewCoverSpec();
    r.showType = b.showType;
    r.fileHash = b.fileHash;
    r.fullPath = b.fullPath;
    r.firstFilePath = b.firstFilePath;
    r.coverState = b.coverState;
    return r;
  }

  get isSeries(): boolean {
    return this.showType === 'series';
  }

  /** 占位封面 seed（对齐 Flutter fallbackCover） */
  get seed(): string {
    if (this.fileHash.trim().length > 0) {
      return this.fileHash.trim();
    }
    if (this.fullPath.trim().length > 0) {
      return this.fullPath.trim();
    }
    return this.firstFilePath.trim();
  }

  /** 是否直接走占位封面（对齐 Flutter shouldFallback） */
  get shouldFallback(): boolean {
    if (this.coverState === 2) {
      return true;
    }
    if (this.isSeries) {
      return this.firstFilePath.trim().length === 0;
    }
    return this.fileHash.trim().length === 0 && this.fullPath.trim().length === 0;
  }
}

/** 单格封面：解析 URL（series→firstFilePath tiny / hash→book tiny / fullPath tiny），失败回退占位图 */
@ComponentV2
struct BookPreviewCell {
  @Param spec: BookPreviewCoverSpec = new BookPreviewCoverSpec();
  @Local url: string = '';
  @Local failed: boolean = false;

  aboutToAppear(): void {
    void this.resolve();
  }

  @Monitor('spec')
  onSpecChange(): void {
    this.failed = false;
    void this.resolve();
  }

  private async resolve(): Promise<void> {
    const spec = this.spec;
    if (spec.shouldFallback) {
      this.url = '';
      return;
    }
    let u = '';
    if (spec.isSeries) {
      if (spec.firstFilePath.trim().length > 0) {
        u = await ApiUrls.getTinyUrl(spec.firstFilePath.trim(), 500);
      }
    } else if (spec.fileHash.trim().length > 0) {
      u = BookListApiService.buildTinyUrl(spec.fileHash.trim(), 500);
    } else if (spec.fullPath.trim().length > 0) {
      u = await ApiUrls.getTinyUrl(spec.fullPath.trim(), 500);
    }
    if (spec === this.spec) {
      this.url = u;
    }
  }

  private fallback(): ResourceStr {
    return BOOK_FALLBACK_COVERS[stableCoverIndex(this.spec.seed, BOOK_FALLBACK_COVERS.length)];
  }

  build() {
    Stack() {
      if (this.spec.shouldFallback || this.failed || this.url.length === 0) {
        Image(this.fallback())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else {
        AppImage({
          url: this.url,
          showLoadingSpin: false,
          onLoaded: (ok: boolean): void => {
            if (!ok) {
              this.failed = true;
            }
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * 书单/合集卡片（对齐 Flutter CustomAlbum 用法）：
 * 预览横条（最多 4 张封面并排，1px 分隔）+ 底部黑渐变标题栏（左名称右 more 钮）。
 * 空预览显示 bg_booklist.jpg。
 */
@ComponentV2
export struct BookAlbumCard {
  @Param covers: BookPreviewCoverSpec[] = [];
  @Param title: string = '';
  @Param showMore: boolean = true;
  /** 显示左上路径帮助按钮（合集卡片） */
  @Param showInfo: boolean = false;
  @Param onOpen: () => void = (): void => {
  };
  @Param onMore: () => void = (): void => {
  };
  @Param onInfo: () => void = (): void => {
  };

  @Builder
  PreviewStrip() {
    if (this.covers.length === 0) {
      Image(BG_BOOKLIST)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Row({ space: 1 }) {
        ForEach(this.covers.slice(0, 4), (spec: BookPreviewCoverSpec, idx: number) => {
          BookPreviewCell({ spec: spec })
            .layoutWeight(1)
        }, (spec: BookPreviewCoverSpec, idx: number): string =>
          `${idx}_${spec.fileHash}_${spec.fullPath}_${spec.firstFilePath}`)
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    Stack() {
      this.PreviewStrip()

      // 左上帮助按钮（对齐 Flutter app_book_collection_view Positioned left/top）
      if (this.showInfo) {
        Column() {
          Row() {
            Column() {
              SymbolGlyph($r('sys.symbol.questionmark_circle'))
                .fontSize(20)
                .fontColor(['#FFFFFF'])
                .shadow({ radius: 4, color: '#FF000000' })
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.onInfo();
            })
            Blank()
          }
          .width('100%')
          Blank()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 底部渐变标题栏（对齐 CustomAlbum headerPosition bottom height 50）
      Column() {
        Blank()
        Row() {
          Text(this.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 8 })
            .layoutWeight(1)
          if (this.showMore) {
            Column() {
              SymbolGlyph($r('sys.symbol.more'))
                .fontSize(18)
                .fontColor(['#FFFFFF'])
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.onMore();
            })
          }
        }
        .width('100%')
        .height(50)
        .alignItems(VerticalAlign.Center)
        .linearGradient({
          angle: 180,
          colors: [['#00000000', 0], ['#8C000000', 1]]
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .borderRadius(10)
    .onClick(() => {
      this.onOpen();
    })
  }
}
