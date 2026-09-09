import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { PageScaffold } from '../../../common/PageScaffold';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { BookListController, BookListSortBy, BookListSortOrder } from '../controllers/BookControllers';
import { BookListItem } from '../models/BookModels';
import { BookSubListPageParam } from '../router/BookRoutes';
import { BookListGrid } from '../components/BookListGrid';
import { showBookSortSheet, showBookSourceSheet } from '../components/BookFilterSheets';
import { openBookItem, showBookItemActionSheet, BookItemActionHandlers, resolveBookFilePath } from '../components/BookItemActions';
import { BookMultiSelectBar } from '../components/BookMultiSelectBar';
import { BookLocalCacheService } from '../services/BookLocalCacheService';

/**
 * 图书子列表页（对齐 Flutter AppBookSubListPage）：
 * 系列 / 自建书单 / 合集三种形态共用；顶栏 + 操作栏（搜索/排序/来源）+ 网格 + 下拉刷新 +
 * 多选（顶部计数条 + 底部操作栏悬浮）。
 */
@ComponentV2
export struct BookSubListPage {
  @Param param: BookSubListPageParam = new BookSubListPageParam();
  @Param popPage: () => void = (): void => {
  };
  ctrl: BookListController = new BookListController();
  @Local refreshing: boolean = false;

  aboutToAppear(): void {
    const p = this.param;
    // 对齐 Flutter：仅系列子列表沿用传入 type，其余为空（全部类型）
    const effectiveType = p.seriesId > 0 ? p.type : '';
    this.ctrl = new BookListController(effectiveType, false,
      p.listId > 0 ? p.listId : 0, p.seriesId > 0 ? p.seriesId : 0, p.collectionId > 0 ? p.collectionId : 0);
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private buildHandlers(): BookItemActionHandlers {
    const h = new BookItemActionHandlers();
    h.isInCustomList = this.ctrl.isInCustomList;
    h.onToggleFavorite = (i: BookListItem): void => {
      this.ctrl.selectedItems = new Set<number>([i.id]);
      void this.ctrl.toggleFavoriteSelected();
    };
    h.onDownload = (i: BookListItem): void => {
      void BookLocalCacheService.getInstance()
        .ensureCached(i.fileHash.trim(), i.filename.trim(), resolveBookFilePath(i));
    };
    h.onDeleteLocalCache = (i: BookListItem): void => {
      BookLocalCacheService.getInstance().deleteCache(i.fileHash.trim());
      ToastUtil.show(L10n.t('delete_success', '删除成功'));
    };
    h.onAddToBookList = (i: BookListItem): void => {
      void this.ctrl.addToBookListItem(i);
    };
    h.onRemoveFromBookList = (i: BookListItem): void => {
      void this.ctrl.removeFromBookListItem(i);
    };
    h.onDelete = (i: BookListItem): void => {
      void this.ctrl.deleteItem(i);
    };
    return h;
  }

  build() {
    PageScaffold({
      title: '',
      showBack: false,
      content: (): void => {
        this.PageBody()
      }
    })
  }

  @Builder
  PageBody() {
    Stack() {
      Column() {
        this.TopBar()
        this.OperationBar()

        Refresh({ refreshing: this.refreshing }) {
          BookListGrid({
            items: this.ctrl.items,
            loading: this.ctrl.loading,
            loadingMore: this.ctrl.loadingMore,
            hasMore: this.ctrl.hasMore,
            autoLoadFailed: this.ctrl.autoLoadFailed,
            selectionMode: this.ctrl.isMultiSelectMode,
            selectedIds: this.ctrl.selectedItems,
            isInCustomList: this.ctrl.isInCustomList,
            bottomPadding: this.ctrl.isMultiSelectMode ? 86 : 30,
            onLoadMore: (): void => {
              void this.ctrl.loadMore(true);
            },
            onToggleSelected: (i: BookListItem): void => {
              this.ctrl.toggleSelection(i.id);
            },
            onToggleFavorite: (i: BookListItem): void => {
              this.ctrl.selectedItems = new Set<number>([i.id]);
              void this.ctrl.toggleFavoriteSelected();
            },
            onMore: (i: BookListItem): void => {
              showBookItemActionSheet(i, this.buildHandlers());
            },
            onOpen: (i: BookListItem): void => {
              void openBookItem(i);
            }
          })
        }
        .onRefreshing(() => {
          this.refreshing = true;
          this.ctrl.refreshList(false).finally(() => {
            this.refreshing = false;
          });
        })
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      // 多选底部操作栏（悬浮，对齐 Flutter Positioned bottom:0）
      if (this.ctrl.isMultiSelectMode) {
        Column() {
          BookMultiSelectBar({
            selectedCount: this.ctrl.selectedItems.size,
            inCustomList: this.ctrl.isInCustomList,
            allFavorited: this.ctrl.isSelectedAllFavorited,
            onDelete: (): void => {
              void this.ctrl.deleteSelected();
            },
            onToggleFavorite: (): void => {
              void this.ctrl.toggleFavoriteSelected();
            },
            onAddToList: (): void => {
              void this.ctrl.addToBookListSelected();
            },
            onRemoveFromList: (): void => {
              void this.ctrl.removeFromBookListSelected();
            }
          })
        }
        .width('100%')
        .position({ x: 0, y: '100%' })
        .markAnchor({ y: '100%' })
        .border({ width: { top: 0.8 }, color: AppTheme.current().divider })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 顶栏：常规（返回+标题居中）/ 多选（关闭+计数），对齐 Flutter AppBar 与多选覆盖层 */
  @Builder
  TopBar() {
    if (this.ctrl.isMultiSelectMode) {
      Row({ space: 12 }) {
        BorderedIconButton({
          icon: $r('sys.symbol.xmark'),
          btnSize: 36,
          iconSize: 18,
          corner: 18,
          onTap: (): void => {
            this.ctrl.exitMultiSelectMode();
          }
        })
        Text(`${this.ctrl.selectedItems.size} ${L10n.t('selected', '已选择')}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 16 })
      .backgroundColor(AppTheme.current().appBarBg)
    } else {
      Row() {
        BorderedIconButton({
          icon: $r('sys.symbol.arrow_left'),
          btnSize: 36,
          iconSize: 18,
          corner: 18,
          onTap: (): void => {
            this.popPage();
          }
        })
        Text(this.param.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().appBarFg)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
        // 右侧占位使标题居中（对齐 Flutter centerTitle: true）
        Row()
          .width(36)
          .height(36)
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .backgroundColor(AppTheme.current().appBarBg)
    }
  }

  /** 操作栏：搜索 + 排序 + 来源（对齐 Flutter _buildOperationBar，52 高） */
  @Builder
  OperationBar() {
    Row({ space: 8 }) {
      Column() {
        SearchInputBar({
          hintText: L10n.t('book_list_search_hint', '搜索名称'),
          text: this.ctrl.searchText,
          onChanged: (v: string): void => {
            this.ctrl.setSearchText(v);
          },
          onClear: (): void => {
            this.ctrl.clearSearch();
          }
        })
      }
      .layoutWeight(1)

      BorderedIconButton({
        icon: $r('sys.symbol.sort'),
        isEnabled: !this.ctrl.isMultiSelectMode,
        active: this.ctrl.sortBy !== BookSortDefault.by || this.ctrl.sortOrder !== BookSortDefault.order,
        onTap: (): void => {
          showBookSortSheet(this.ctrl);
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.externaldrive'),
        isEnabled: !this.ctrl.isMultiSelectMode,
        active: this.ctrl.selectedPaths.length > 0,
        onTap: (): void => {
          showBookSourceSheet(this.ctrl);
        }
      })
    }
    .width('100%')
    .height(52)
    .padding({ left: 10, right: 10 })
    .backgroundColor(AppTheme.current().appBarBg)
  }
}

/** 默认排序（createTime desc），用于排序按钮 active 态 */
class BookSortDefault {
  static readonly by: BookListSortBy = BookListSortBy.createTime;
  static readonly order: BookListSortOrder = BookListSortOrder.desc;
}
