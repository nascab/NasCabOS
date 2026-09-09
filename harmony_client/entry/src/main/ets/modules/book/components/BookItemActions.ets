import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { AppRouter } from '../../../router/AppRouter';
import { NavUtil } from '../../../common/NavUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../../common/SheetUtil';
import { AppImage } from '../../../common/components/AppImage';
import { BookListItem } from '../models/BookModels';
import { BookListApiService, BookScopedTokenApiService } from '../services/BookApiServices';
import { BookLocalCacheService } from '../services/BookLocalCacheService';
import { BookComicReaderParam, BookSubListPageParam, BookTxtReaderParam, BookWebReaderParam } from '../router/BookRoutes';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'BookOpen';

/** 拼接阅读文件路径（对齐 Flutter _resolveFilePath） */
export function resolveBookFilePath(item: BookListItem): string {
  if (item.fullPath.trim().length > 0) {
    return item.fullPath.trim();
  }
  if (item.path.trim().length > 0 && item.filename.trim().length > 0) {
    const p = item.path.trim();
    const sep = p.endsWith('/') ? '' : '/';
    return `${p}${sep}${item.filename.trim()}`;
  }
  return item.firstFilePath.trim();
}

function extOf(path: string): string {
  const dot = path.lastIndexOf('.');
  if (dot < 0) {
    return '';
  }
  return path.substring(dot + 1).toLowerCase();
}

/**
 * 打开图书（对齐 Flutter _handleOpen）：
 * 系列 → 子列表页；comic → 漫画阅读器；txt → 本地缓存 + TXT 阅读器；
 * pdf/epub/mobi/azw3 → Web 阅读器（foliate reader.html + scoped token）。
 */
export async function openBookItem(item: BookListItem): Promise<void> {
  if (item.isSeries) {
    const p = new BookSubListPageParam();
    p.seriesId = item.id;
    p.title = item.displayTitle;
    p.type = item.type;
    NavUtil.push(AppRouter.BOOK_SUB_LIST, p);
    return;
  }
  const filePath = resolveBookFilePath(item);
  if (filePath.length === 0) {
    ToastUtil.show(L10n.operationFailed);
    return;
  }
  const ext = extOf(item.filename.length > 0 ? item.filename : filePath);
  const isComic = item.isComicType || ext === 'cbz' || ext === 'cbr' || ext === 'rar' || ext === 'zip';
  try {
    if (isComic && item.fileHash.trim().length > 0) {
      const p = BookComicReaderParam.fromItem(item);
      NavUtil.push(AppRouter.BOOK_COMIC_READER, p);
      return;
    }
    if (ext === 'txt') {
      DialogUtil.showLoading(L10n.t('loading'));
      const ok = await BookLocalCacheService.getInstance()
        .ensureCached(item.fileHash.trim(), item.filename.trim(), filePath);
      DialogUtil.dismissLoading(true);
      if (!ok) {
        ToastUtil.show(L10n.networkFailure);
        return;
      }
      const localPath = BookLocalCacheService.getInstance().cachedFilePathOf(item.fileHash.trim());
      if (localPath === undefined) {
        ToastUtil.show(L10n.networkFailure);
        return;
      }
      const p = BookTxtReaderParam.fromItem(item, localPath);
      NavUtil.push(AppRouter.BOOK_TXT_READER, p);
      return;
    }
    // pdf / epub / mobi / azw3 → Web 阅读器（对齐 Flutter app 端：先下载图书再加载本地文件）
    DialogUtil.showLoading(L10n.t('loading'));
    const fileHash = item.fileHash.trim();
    if (fileHash.length > 0) {
      const cached = await BookLocalCacheService.getInstance()
        .ensureCached(fileHash, item.filename.trim(), filePath);
      if (!cached) {
        DialogUtil.dismissLoading(true);
        ToastUtil.show(L10n.networkFailure);
        return;
      }
    }
    const scopedToken = await BookScopedTokenApiService.createScopedToken(filePath);
    DialogUtil.dismissLoading(true);
    if (scopedToken.length === 0) {
      ToastUtil.show(L10n.networkFailure);
      return;
    }
    const p = BookWebReaderParam.fromItem(item, filePath);
    if (fileHash.length > 0) {
      const local = BookLocalCacheService.getInstance().cachedFilePathOf(fileHash);
      p.localPath = local !== undefined ? local : '';
    }
    p.url = scopedToken; // 暂存 scoped token，页面内重建完整 URL
    NavUtil.push(AppRouter.BOOK_WEB_READER, p);
  } catch (e) {
    hilog.error(0x0000, TAG, 'openBookItem failed: %{public}s', JSON.stringify(e));
    DialogUtil.dismissLoading(true);
    ToastUtil.show(L10n.networkFailure);
  }
}

/** 条目操作表回调集合 */
export class BookItemActionHandlers {
  onToggleFavorite: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  onDownload: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  onDeleteLocalCache: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  onAddToBookList: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  onRemoveFromBookList: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  onDelete: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  isInCustomList: boolean = false;
  canDelete: boolean = true;
  canDownload: boolean = true;
  /** 是否显示加书单/移出书单动作（历史页为 false，对齐 Flutter 历史页操作表） */
  showListActions: boolean = true;
}

interface SheetEntry {
  icon: Resource;
  label: string;
  danger: boolean;
  action: () => void;
}

class BookItemActionParams extends SheetParamsBase {
  item: BookListItem = new BookListItem();
  handlers: BookItemActionHandlers = new BookItemActionHandlers();
}

@ComponentV2
struct BookItemActionSheet {
  @Param params: BookItemActionParams = new BookItemActionParams();
  @Local entries: SheetEntry[] = [];

  aboutToAppear(): void {
    const h = this.params.handlers;
    const item = this.params.item;
    const list: SheetEntry[] = [];
    list.push({
      icon: $r('sys.symbol.book'),
      label: L10n.t('open'),
      danger: false,
      action: (): void => {
        openBookItem(item);
      }
    });
    if (h.canDownload) {
      list.push({
        icon: $r('sys.symbol.download'),
        label: L10n.t('download'),
        danger: false,
        action: (): void => {
          h.onDownload(item);
        }
      });
    }
    if (BookLocalCacheService.getInstance().isCached(item.fileHash)) {
      list.push({
        icon: $r('sys.symbol.trash_fill'),
        label: L10n.t('book_item_delete_local_cache', '删除本地缓存'),
        danger: true,
        action: (): void => {
          h.onDeleteLocalCache(item);
        }
      });
    }
    list.push({
      icon: $r(item.isFavorite ? 'sys.symbol.heart_slash' : 'sys.symbol.heart'),
      label: item.isFavorite ? L10n.t('unfavorite', '取消收藏') : L10n.t('favorites', '收藏'),
      danger: false,
      action: (): void => {
        h.onToggleFavorite(item);
      }
    });
    if (h.showListActions && !h.isInCustomList) {
      list.push({
        icon: $r('sys.symbol.plus_circle'),
        label: L10n.t('add_to_book_list', '添加到书单'),
        danger: false,
        action: (): void => {
          h.onAddToBookList(item);
        }
      });
    } else if (h.showListActions) {
      list.push({
        icon: $r('sys.symbol.xmark'),
        label: L10n.t('remove_from_book_list', '移出书单'),
        danger: false,
        action: (): void => {
          h.onRemoveFromBookList(item);
        }
      });
    }
    if (h.canDelete) {
      list.push({
        icon: $r('sys.symbol.trash_fill'),
        label: L10n.t('delete'),
        danger: true,
        action: (): void => {
          h.onDelete(item);
        }
      });
    }
    this.entries = list;
  }

  build() {
    Column() {
      SheetHandle()
      // 头部：52 封面 + 标题
      Row({ space: 12 }) {
        Stack() {
          AppImage({ url: BookListApiService.buildTinyUrl(this.params.item.fileHash, 200), showLoadingSpin: false })
        }
        .width(52)
        .height(52)
        .borderRadius(8)
        .clip(true)

        Text(this.params.item.displayTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 8 })

      ForEach(this.entries, (e: SheetEntry, idx: number) => {
        Row({ space: 14 }) {
          SymbolGlyph(e.icon)
            .fontSize(20)
            .fontColor([e.danger ? AppTheme.current().error : AppTheme.current().onSurface])
          Text(e.label)
            .fontSize(15)
            .fontColor(e.danger ? AppTheme.current().error : AppTheme.current().onSurface)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 13, bottom: 13 })
        .onClick(() => {
          this.params.close();
          e.action();
        })
        if (idx < this.entries.length - 1 && !e.danger && !this.entries[idx + 1].danger) {
          Divider()
            .color(AppTheme.current().divider)
            .strokeWidth(0.8)
            .margin({ left: 54, right: 20 })
        }
      }, (e: SheetEntry) => `${e.label}`)
    }
    .width('100%')
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: 24 })
  }
}

/** 弹出条目操作表（对齐 Flutter AppItemActionSheet） */
export function showBookItemActionSheet(item: BookListItem, handlers: BookItemActionHandlers): void {
  const p = new BookItemActionParams();
  p.item = item;
  p.handlers = handlers;
  SheetUtil.present<BookItemActionParams>(p, bookItemActionBuilder);
}

const bookItemActionBuilder: WrappedBuilder<[BookItemActionParams]> = wrapBuilder(BookItemActionBuilderFn);

@Builder
function BookItemActionBuilderFn(params: BookItemActionParams) {
  BookItemActionSheet({ params: params });
}
