import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../../common/SheetUtil';
import { BookListController, BookListSortBy, BookListSortOrder } from '../controllers/BookControllers';
import { BookListPathItem } from '../models/BookModels';

/**
 * 图书列表排序 / 来源筛选底部弹层（对齐 Flutter _openSortSheet / _openSourceSheet）。
 * 抽成公共组件供书库主视图与系列子列表页复用。
 */

interface SortEntry {
  by: BookListSortBy;
  order: BookListSortOrder;
  label: string;
}

class SortSheetParams extends SheetParamsBase {
  ctrl: BookListController = new BookListController();
  entries: SortEntry[] = [];
}

@Builder
function SortSheetContent(p: SortSheetParams) {
  Column() {
    SheetHandle()
    Text(L10n.t('sort', '排序'))
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.current().onSurface)
      .margin({ top: 4, bottom: 4 })
    ForEach(p.entries, (e: SortEntry) => {
      Row({ space: 12 }) {
        Text(e.label)
          .fontSize(15)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        if (p.ctrl.sortBy === e.by && p.ctrl.sortOrder === e.order) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(18)
            .fontColor([AppTheme.current().primary])
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 13, bottom: 13 })
      .onClick(() => {
        p.ctrl.setSort(e.by, e.order);
        p.close();
      })
    }, (e: SortEntry) => `${e.by}_${e.order}`)
  }
  .width('100%')
  .backgroundColor(AppTheme.current().surfaceBg)
  .borderRadius({ topLeft: 16, topRight: 16 })
  .padding({ bottom: 24 })
}

const sortSheetBuilder: WrappedBuilder<[SortSheetParams]> = wrapBuilder(SortSheetContent);

/** 构建排序条目（对齐 Flutter _bookSortEntries；收藏列表多收藏时间两项） */
export function bookSortEntries(ctrl: BookListController): SortEntry[] {
  const entries: SortEntry[] = [
    { by: BookListSortBy.createTime, order: BookListSortOrder.desc, label: L10n.t('create_time_desc', '添加时间 ↓') },
    { by: BookListSortBy.createTime, order: BookListSortOrder.asc, label: L10n.t('create_time_asc', '添加时间 ↑') },
    { by: BookListSortBy.name, order: BookListSortOrder.asc, label: L10n.t('name_asc', '名称 ↑') },
    { by: BookListSortBy.name, order: BookListSortOrder.desc, label: L10n.t('name_desc', '名称 ↓') }
  ];
  if (ctrl.isFavoriteList) {
    entries.push(
      { by: BookListSortBy.favoriteTime, order: BookListSortOrder.desc, label: L10n.t('book_list_sort_favorite_time_desc', '收藏时间 ↓') },
      { by: BookListSortBy.favoriteTime, order: BookListSortOrder.asc, label: L10n.t('book_list_sort_favorite_time_asc', '收藏时间 ↑') }
    );
  }
  return entries;
}

/** 当前排序的显示文案（对齐 Flutter _currentSortLabel） */
export function currentSortLabel(ctrl: BookListController): string {
  const entries = bookSortEntries(ctrl);
  for (const e of entries) {
    if (ctrl.sortBy === e.by && ctrl.sortOrder === e.order) {
      return e.label;
    }
  }
  return L10n.t('sort', '排序');
}

/** 弹出排序弹层 */
export function showBookSortSheet(ctrl: BookListController): void {
  const p = new SortSheetParams();
  p.ctrl = ctrl;
  p.entries = bookSortEntries(ctrl);
  SheetUtil.present<SortSheetParams>(p, sortSheetBuilder);
}

// ===== 来源筛选弹层 =====

class SourceSheetParams extends SheetParamsBase {
  ctrl: BookListController = new BookListController();
}

@Builder
function SourceSheetContent(p: SourceSheetParams) {
  Column() {
    SheetHandle()
    Row() {
      Text(L10n.t('source', '来源'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .layoutWeight(1)
      Text(L10n.t('reset', '重置'))
        .fontSize(14)
        .fontColor(AppTheme.current().primary)
        .onClick(() => {
          p.ctrl.resetSelectedPaths();
          p.close();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 8 })

    if (p.ctrl.availablePaths.length === 0) {
      Text(L10n.t('no_path', '暂无路径'))
        .fontSize(14)
        .fontColor(AppTheme.current().hint)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 20, bottom: 20 })
    } else {
      Scroll() {
        Column() {
          ForEach(p.ctrl.availablePaths, (path: BookListPathItem) => {
            Row({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(16)
                .fontColor([p.ctrl.selectedPaths.includes(path.path)
                  ? AppTheme.current().primary : '#00000000'])
              Text(path.path)
                .fontSize(14)
                .fontColor(AppTheme.current().onSurface)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .onClick(() => {
              p.ctrl.togglePath(path.path);
            })
          }, (path: BookListPathItem) => `${path.path}_${p.ctrl.selectedPaths.includes(path.path) ? 1 : 0}`)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 360 })
      .width('100%')
    }
  }
  .width('100%')
  .backgroundColor(AppTheme.current().surfaceBg)
  .borderRadius({ topLeft: 16, topRight: 16 })
  .padding({ bottom: 24 })
}

const sourceSheetBuilder: WrappedBuilder<[SourceSheetParams]> = wrapBuilder(SourceSheetContent);

/** 弹出来源筛选弹层 */
export function showBookSourceSheet(ctrl: BookListController): void {
  const p = new SourceSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present<SourceSheetParams>(p, sourceSheetBuilder);
}
