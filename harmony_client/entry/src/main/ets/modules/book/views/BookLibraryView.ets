import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import {
  BookListController, BookHistoryController, BookListSortBy, BookListSortOrder
} from '../controllers/BookControllers';
import { BookListItem } from '../models/BookModels';
import { BookFavoriteApiService } from '../services/BookApiServices';
import { BookListGrid } from '../components/BookListGrid';
import { BookItemCard } from '../components/BookItemCard';
import { showBookSortSheet, showBookSourceSheet, currentSortLabel } from '../components/BookFilterSheets';
import { openBookItem, showBookItemActionSheet, BookItemActionHandlers, resolveBookFilePath } from '../components/BookItemActions';
import { BookLocalCacheService } from '../services/BookLocalCacheService';

/**
 * 书库视图（对齐 Flutter AppBookMainView tab0 _AppBookLibraryTabsBody + 顶栏 + 悬浮 chips）：
 * 顶栏（主页/搜索/清空历史或排序/来源/设置）+ 4 子视图（图书/漫画/收藏/历史 IndexedStack）+
 * 底部悬浮 chips 条。多选底部操作栏由主框架渲染（对齐 Flutter bottomNavigationBar 隐藏）。
 */
@ComponentV2
export struct BookLibraryView {
  @Param statusBarHeight: number = 0;
  @Param ctrlBook: BookListController = new BookListController();
  @Param ctrlComic: BookListController = new BookListController();
  @Param ctrlFav: BookListController = new BookListController();
  @Param ctrlHistory: BookHistoryController = new BookHistoryController();
  @Param popPage: () => void = (): void => {
  };
  @Param onOpenSettings: () => void = (): void => {
  };
  /** 库内子视图切换回写（主框架同步多选栏显隐用） */
  @Param onLibraryIndexChanged: (index: number) => void = (_i: number): void => {
  };
  /** 当前子视图：0 图书 1 漫画 2 收藏 3 历史（对齐 Flutter _libraryIndex） */
  @Local activeIndex: number = 0;

  /** 当前激活的列表控制器（历史视图除外） */
  private activeCtrl(): BookListController {
    if (this.activeIndex === 1) {
      return this.ctrlComic;
    }
    if (this.activeIndex === 2) {
      return this.ctrlFav;
    }
    return this.ctrlBook;
  }

  private openItem(item: BookListItem): void {
    void openBookItem(item);
  }

  private buildHandlers(ctrl: BookListController): BookItemActionHandlers {
    const h = new BookItemActionHandlers();
    h.isInCustomList = ctrl.isInCustomList;
    h.onToggleFavorite = (i: BookListItem): void => {
      ctrl.selectedItems = new Set<number>([i.id]);
      void ctrl.toggleFavoriteSelected();
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
      void ctrl.addToBookListItem(i);
    };
    h.onRemoveFromBookList = (i: BookListItem): void => {
      void ctrl.removeFromBookListItem(i);
    };
    h.onDelete = (i: BookListItem): void => {
      void ctrl.deleteItem(i);
    };
    return h;
  }

  private showItemMore(item: BookListItem): void {
    showBookItemActionSheet(item, this.buildHandlers(this.activeCtrl()));
  }

  /** 历史项操作表（对齐 Flutter 历史页 BookItemCard：无加书单/删除） */
  private showHistoryItemMore(item: BookListItem): void {
    const h = new BookItemActionHandlers();
    h.canDelete = false;
    h.showListActions = false;
    h.onToggleFavorite = (i: BookListItem): void => {
      void BookFavoriteApiService.batchFavorite([i.id], !i.isFavorite).then((ok: boolean): void => {
        if (!ok) {
          ToastUtil.show(L10n.operationFailed);
          return;
        }
        i.isFavorite = !i.isFavorite;
        ToastUtil.show(L10n.t('operation_success'));
      });
    };
    h.onDownload = (i: BookListItem): void => {
      void BookLocalCacheService.getInstance()
        .ensureCached(i.fileHash.trim(), i.filename.trim(), resolveBookFilePath(i));
    };
    h.onDeleteLocalCache = (i: BookListItem): void => {
      BookLocalCacheService.getInstance().deleteCache(i.fileHash.trim());
      ToastUtil.show(L10n.t('delete_success', '删除成功'));
    };
    showBookItemActionSheet(item, h);
  }

  @Builder
  TopBar() {
    if (this.activeIndex !== 3 && this.activeCtrl().isMultiSelectMode) {
      // 多选顶栏（对齐 Flutter isMultiSelect 分支）
      Row({ space: 12 }) {
        BorderedIconButton({
          icon: $r('sys.symbol.xmark'),
          btnSize: 36,
          iconSize: 18,
          corner: 18,
          onTap: (): void => {
            this.activeCtrl().exitMultiSelectMode();
          }
        })
        Text(`${this.activeCtrl().selectedItems.size} ${L10n.t('selected', '已选择')}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 16 })
    } else {
      Row({ space: 8 }) {
        BorderedIconButton({
          icon: $r('sys.symbol.house'),
          btnSize: 36,
          iconSize: 18,
          corner: 18,
          onTap: (): void => {
            this.popPage();
          }
        })
        Column() {
          SearchInputBar({
            hintText: L10n.t('book_list_search_hint', '搜索名称'),
            text: this.activeCtrl().searchText,
            onChanged: (v: string): void => {
              this.activeCtrl().setSearchText(v);
            },
            onClear: (): void => {
              this.activeCtrl().clearSearch();
            }
          })
        }
        .layoutWeight(1)

        if (this.activeIndex === 3) {
          BorderedIconButton({
            icon: $r('sys.symbol.trash_fill'),
            btnSize: 36,
            iconSize: 18,
            corner: 18,
            onTap: (): void => {
              void this.ctrlHistory.clearHistory();
            }
          })
        } else {
          BorderedIconButton({
            icon: $r('sys.symbol.sort'),
            btnSize: 36,
            iconSize: 18,
            corner: 18,
            active: this.activeCtrl().sortBy !== BookSortDefault.by || this.activeCtrl().sortOrder !== BookSortDefault.order,
            onTap: (): void => {
              showBookSortSheet(this.activeCtrl());
            }
          })
          BorderedIconButton({
            icon: $r('sys.symbol.externaldrive'),
            btnSize: 36,
            iconSize: 18,
            corner: 18,
            active: this.activeCtrl().selectedPaths.length > 0,
            onTap: (): void => {
              showBookSourceSheet(this.activeCtrl());
            }
          })
        }
        if (CurrentUserStore.getInstance().isAdmin) {
          BorderedIconButton({
            icon: $r('sys.symbol.gearshape'),
            btnSize: 36,
            iconSize: 18,
            corner: 18,
            onTap: (): void => {
              this.onOpenSettings();
            }
          })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 12 })
    }
  }

  @Builder
  ListBody() {
    if (this.activeIndex === 3) {
      // 历史视图（对齐 Flutter BookHistoryListView：一次性返回不分页）
      HistoryGrid({
        ctrl: this.ctrlHistory,
        onOpen: (i: BookListItem): void => {
          this.openItem(i);
        },
        onMore: (i: BookListItem): void => {
          this.showHistoryItemMore(i);
        }
      })
    } else {
      this.LibraryListSection()
    }
  }

  /** 图书/漫画/收藏三个列表段（对齐 Flutter _AppBookListSection） */
  @Builder
  LibraryListSection() {
    BookListGrid({
      items: this.activeCtrl().items,
      loading: this.activeCtrl().loading,
      loadingMore: this.activeCtrl().loadingMore,
      hasMore: this.activeCtrl().hasMore,
      autoLoadFailed: this.activeCtrl().autoLoadFailed,
      selectionMode: this.activeCtrl().isMultiSelectMode,
      selectedIds: this.activeCtrl().selectedItems,
      isInCustomList: this.activeCtrl().isInCustomList,
      bottomPadding: 92,
      onLoadMore: (): void => {
        void this.activeCtrl().loadMore(true);
      },
      onToggleSelected: (i: BookListItem): void => {
        this.activeCtrl().toggleSelection(i.id);
      },
      onToggleFavorite: (i: BookListItem): void => {
        this.activeCtrl().selectedItems = new Set<number>([i.id]);
        void this.activeCtrl().toggleFavoriteSelected();
      },
      onMore: (i: BookListItem): void => {
        this.showItemMore(i);
      },
      onOpen: (i: BookListItem): void => {
        this.openItem(i);
      }
    })
  }

  /** 底部悬浮 chips（多选模式隐藏，对齐 Flutter _buildFloatingLibraryTabs） */
  @Builder
  FloatingChips() {
    if (!(this.activeIndex !== 3 && this.activeCtrl().isMultiSelectMode)) {
      Row({ space: 4 }) {
        this.Chip(L10n.t('book_menu_library_book', '图书'), 0)
        this.Chip(L10n.t('book_menu_library_comic', '漫画'), 1)
        this.Chip(L10n.t('favorites', '收藏'), 2)
        this.Chip(L10n.t('book_menu_library_history', '历史'), 3)
      }
      .height(45)
      .borderRadius(22.5)
      .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.92))
      .border({ width: 1, color: AppTheme.current().divider })
      .padding({ left: 8, right: 8 })
      .shadow({ radius: 12, color: '#1F000000', offsetY: 2 })
    }
  }

  @Builder
  Chip(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.activeIndex === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.activeIndex === index ? AppTheme.current().buttonText : AppTheme.current().onSurface)
      .maxLines(1)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 6, bottom: 6 })
      .margin({ left: 4, right: 4 })
      .borderRadius(16)
      .backgroundColor(this.activeIndex === index ? AppTheme.current().primary : '#00000000')
      .onClick(() => {
        if (this.activeIndex === index) {
          return;
        }
        this.activeIndex = index;
        this.onLibraryIndexChanged(index);
        if (index === 3) {
          // 切到历史时刷新（对齐 Flutter chips onTap）
          void this.ctrlHistory.refreshHistory(true);
        }
      })
  }

  build() {
    Stack() {
      Column() {
        Column() {
          this.TopBar()
        }
        .width('100%')
        .padding({ top: this.statusBarHeight })
        .backgroundColor(AppTheme.current().surfaceBg)

        Column() {
          this.ListBody()
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      // 底部悬浮 chips（对齐 Flutter Positioned bottom:5；Stack 子项默认居中，须显式钉到底部）
      Column() {
        this.FloatingChips()
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 5 })
      .hitTestBehavior(HitTestMode.Transparent)
      .position({ x: 0, y: '100%' })
      .markAnchor({ y: '100%' })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }
}

/** 默认排序（createTime desc），用于排序按钮 active 态 */
class BookSortDefault {
  static readonly by: BookListSortBy = BookListSortBy.createTime;
  static readonly order: BookListSortOrder = BookListSortOrder.desc;
}

/** 历史视图网格（对齐 Flutter _HistoryGrid，itemScale 1.7） */
@ComponentV2
struct HistoryGrid {
  @Param ctrl: BookHistoryController = new BookHistoryController();
  @Param onOpen: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Param onMore: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Local contentWidth: number = 0;

  private spacing(): number {
    return this.contentWidth < 520 ? 10 : 12;
  }

  private columnCount(): number {
    if (this.contentWidth <= 0) {
      return 3;
    }
    const narrow = this.contentWidth < 520;
    const baseWidth = (narrow ? 72 : 84) * 1.7;
    const n = Math.floor(this.contentWidth / baseWidth);
    return Math.min(Math.max(n, 2), 12);
  }

  private repeatTemplate(): string {
    const n = this.columnCount();
    const arr: string[] = [];
    for (let i = 0; i < n; i++) {
      arr.push('1fr');
    }
    return arr.join(' ');
  }

  build() {
    Scroll() {
      Column() {
        if (this.ctrl.loading && !this.ctrl.firstLoaded) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(AppTheme.current().primary)
          }
          .width('100%')
          .margin({ top: 80 })
        } else if (this.ctrl.items.length === 0) {
          Column() {
            EmptyState({ message: L10n.t('no_data', '暂无数据') })
          }
          .width('100%')
          .margin({ top: 80 })
        } else {
          Grid() {
            ForEach(this.ctrl.items, (item: BookListItem) => {
              GridItem() {
                BookItemCardLite({
                  item: item,
                  onOpen: this.onOpen,
                  onMore: this.onMore
                })
              }
            }, (item: BookListItem) => `${item.id}_${item.viewTime}_${item.isFavorite ? 1 : 0}`)
          }
          .columnsTemplate(this.repeatTemplate())
          .columnsGap(this.spacing())
          .rowsGap(this.spacing())
          .width('100%')
        }
        Column()
          .width('100%')
          .height(24)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .onAreaChange((_o: Area, n: Area) => {
        this.contentWidth = n.width as number - 32;
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}

/** 历史卡片：复用 BookItemCard（mobileLayout，无选择框，对齐 Flutter 历史页用法） */
@ComponentV2
struct BookItemCardLite {
  @Param item: BookListItem = new BookListItem();
  @Param onOpen: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Param onMore: (item: BookListItem) => void = (_i: BookListItem): void => {
  };

  build() {
    Column() {
      BookItemCard({
        item: this.item,
        onOpen: (i: BookListItem): void => {
          this.onOpen(i);
        },
        onMore: (i: BookListItem): void => {
          this.onMore(i);
        }
      })
    }
  }
}

// re-export 供主框架引用排序 active 判断
export { currentSortLabel };
