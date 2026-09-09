import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { EmptyState } from '../../../common/components/EmptyState';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SheetUtil, SheetParamsBase, SheetHandle, SheetListItem } from '../../../common/SheetUtil';
import { MusicListController, MusicListSortBy, MusicListSortOrder } from '../controllers/MusicListController';
import { MusicListItem, MusicListPathItem } from '../models/MusicModels';
import { MusicItemCard } from '../components/MusicItemCard';
import { MusicMultiSelectBar } from '../components/MusicMultiSelectBar';

/** 歌曲列表页内嵌参数（对齐 Flutter MusicListPage 构造参数） */
export class MusicListPageParam {
  listType: string = '';
  listId: number = 0;
  seriesIndexId: number = 0;
  collectionId: number = 0;
  isFavorite: boolean = false;
  initialSortBy: MusicListSortBy = MusicListSortBy.mtime;
  initialSortOrder: MusicListSortOrder = MusicListSortOrder.desc;
}

class MusicListSortSheetParams extends SheetParamsBase {
  ctrl: MusicListController | undefined = undefined;
}

class MusicListSourceSheetParams extends SheetParamsBase {
  ctrl: MusicListController | undefined = undefined;
}

/**
 * 歌曲/收藏列表页（对齐 Flutter MusicListPage 移动端形态）：
 * 顶部搜索 + 排序 + 来源筛选（底部弹层），歌曲网格，滚动自动加载，
 * 多选底部操作栏（收藏/下载/删除/加入歌单/移出歌单）。
 */
@ComponentV2
export struct MusicListPage {
  @Param param: MusicListPageParam = new MusicListPageParam();
  /** 多选模式变化回调（主框架用于隐藏悬浮播放条） */
  @Param onMultiSelectChanged: (v: boolean) => void = (_v: boolean): void => {
  };
  @Param onOpenSeries: (item: MusicListItem) => void = (_item: MusicListItem): void => {
  };

  private ctrl: MusicListController = new MusicListController();
  @Local private gridWidth: number = 0;
  @Local private refreshing: boolean = false;

  aboutToAppear(): void {
    const p = this.param;
    this.ctrl = new MusicListController(p.listType, p.listId, p.seriesIndexId, p.collectionId,
      p.isFavorite, p.initialSortBy, p.initialSortOrder);
    this.ctrl.onMultiSelectChanged = (v: boolean): void => {
      this.onMultiSelectChanged(v);
    };
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private gridColumns(): number {
    const maxWidth = this.gridWidth > 0 ? this.gridWidth : 360;
    const content = Math.max(0, maxWidth - 32);
    const n = Math.floor(content / 115);
    return Math.min(Math.max(n, 2), 10);
  }

  private gridColumnsTemplate(): string {
    const n = this.gridColumns();
    const arr: string[] = [];
    for (let i = 0; i < n; i++) {
      arr.push('1fr');
    }
    return arr.join(' ');
  }

  private showSortSheet(): void {
    const params = new MusicListSortSheetParams();
    params.ctrl = this.ctrl;
    params.onDismissed = (): void => {
    };
    SheetUtil.present<MusicListSortSheetParams>(params, wrapBuilder(musicListSortSheetBuilder));
  }

  private showSourceSheet(): void {
    const params = new MusicListSourceSheetParams();
    params.ctrl = this.ctrl;
    SheetUtil.present<MusicListSourceSheetParams>(params, wrapBuilder(musicListSourceSheetBuilder));
  }

  build() {
    Column() {
      // 顶部操作栏（对齐 AppMusicListTopBar 移动端）
      Row({ space: 8 }) {
        SearchInputBar({
          hintText: L10n.t('music_list_search_hint'),
          text: this.ctrl.searchText,
          onChanged: (v: string): void => {
            this.ctrl.onSearchChanged(v);
          },
          onClear: (): void => {
            this.ctrl.clearSearch();
          }
        })
          .layoutWeight(1)

        BorderedIconButton({
          icon: $r('sys.symbol.slider_horizontal_2'),
          active: this.ctrl.sortBy !== MusicListSortBy.mtime || this.ctrl.sortOrder !== MusicListSortOrder.desc,
          onTap: (): void => {
            this.showSortSheet();
          }
        })
        BorderedIconButton({
          icon: $r('sys.symbol.grid'),
          active: this.ctrl.selectedPaths.length > 0,
          onTap: (): void => {
            this.showSourceSheet();
          }
        })
      }
      .width('100%')
      .height(60)
      .padding({ left: 12, right: 12 })

      Refresh({ refreshing: this.refreshing }) {
      if (this.ctrl.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.items.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('no_data') })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Stack() {
          // Grid + GridItem（对齐视频模块已验证模式）：FlowItem 内百分比/自适应宽度解析不可靠，
          // 会导致 item 撑满整屏宽、封面溢出
          Scroll() {
            Column() {
              Grid() {
                ForEach(this.ctrl.items, (item: MusicListItem) => {
                  GridItem() {
                    MusicItemCard({
                      controller: this.ctrl,
                      item: item,
                      selectionMode: this.ctrl.isMultiSelectMode,
                      selected: this.ctrl.selectedItems.has(item.id),
                      onToggleSelected: (): void => {
                        this.ctrl.toggleSelection(item.id);
                      },
                      onOpenSeries: (it: MusicListItem): void => {
                        this.onOpenSeries(it);
                      }
                    })
                  }
                }, (item: MusicListItem) => `${item.id}`)
              }
              .columnsTemplate(this.gridColumnsTemplate())
              .columnsGap(4)
              .rowsGap(4)
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 24 })
              .onAreaChange((_o: Area, n: Area) => {
                this.gridWidth = Number(n.width);
              })

              this.ListFooter()
            }
            .width('100%')
          }
          .scrollBar(BarState.Auto)
          .width('100%')
          .height('100%')
          .onReachEnd(() => {
            this.ctrl.loadMore();
          })

          if (this.ctrl.isMultiSelectMode) {
            Column() {
              MusicMultiSelectBar({
                selectedCount: this.ctrl.selectedItems.size,
                allSelected: this.ctrl.isAllCurrentSelected,
                allFavorited: this.ctrl.isSelectedAllFavorited,
                isInPlayList: this.ctrl.isInPlayList,
                onSelectAll: (): void => {
                  this.ctrl.toggleSelectAllCurrent();
                },
                onToggleFavorite: (): void => {
                  this.ctrl.toggleFavoriteSelected();
                },
                onDownload: (): void => {
                  this.ctrl.downloadSelected();
                },
                onDelete: (): void => {
                  this.ctrl.deleteSelected();
                },
                onAddToPlayList: (): void => {
                  this.addSelectedToPlayList();
                },
                onRemoveFromPlayList: (): void => {
                  this.ctrl.removeFromPlayListSelected();
                },
                onCancel: (): void => {
                  this.ctrl.exitMultiSelectMode();
                }
              })
            }
            .width('100%')
            .position({ x: 0, y: '100%' })
            .markAnchor({ y: '100%' })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      }
      .onRefreshing(() => {
        this.refreshing = true;
        this.ctrl.refreshList(false).finally(() => {
          this.refreshing = false;
        });
      })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  private async addSelectedToPlayList(): Promise<void> {
    const listId = await this.ctrl.pickPlayListId();
    if (listId > 0) {
      await this.ctrl.addToPlayListSelected(listId);
    }
  }

  @Builder
  ListFooter() {
    Column() {
      if (this.ctrl.loadingMore) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(AppTheme.current().primary)
          .margin(12)
      } else if (!this.ctrl.hasMore) {
        Text(L10n.t('music_list_no_more'))
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
          .padding({ top: 14, bottom: 14 })
      } else if (this.ctrl.autoLoadFailed) {
        Text(L10n.t('music_list_load_more'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .padding({ top: 14, bottom: 14 })
          .onClick(() => {
            this.ctrl.loadMore();
          })
      } else {
        Column().height(20)
      }
    }
    .width('100%')
  }
}

// ===== 排序弹层 =====

@Builder
function musicListSortSheetBuilder(params: MusicListSortSheetParams) {
  Column() {
    SheetHandle()
    Scroll() {
      Column() {
        MusicSortRow({ label: L10n.t('music_list_sort_title_asc'), by: MusicListSortBy.title, order: MusicListSortOrder.asc, params: params })
        MusicSortRow({ label: L10n.t('music_list_sort_title_desc'), by: MusicListSortBy.title, order: MusicListSortOrder.desc, params: params })
        MusicSortRow({ label: L10n.t('music_list_sort_year_desc'), by: MusicListSortBy.year, order: MusicListSortOrder.desc, params: params })
        MusicSortRow({ label: L10n.t('music_list_sort_year_asc'), by: MusicListSortBy.year, order: MusicListSortOrder.asc, params: params })
        MusicSortRow({ label: L10n.t('music_list_sort_duration_desc'), by: MusicListSortBy.duration, order: MusicListSortOrder.desc, params: params })
        MusicSortRow({ label: L10n.t('music_list_sort_duration_asc'), by: MusicListSortBy.duration, order: MusicListSortOrder.asc, params: params })
        MusicSortRow({ label: L10n.t('create_time_desc'), by: MusicListSortBy.ctime, order: MusicListSortOrder.desc, params: params })
        MusicSortRow({ label: L10n.t('create_time_asc'), by: MusicListSortBy.ctime, order: MusicListSortOrder.asc, params: params })
        if (params.ctrl !== undefined && params.ctrl.isFavoriteList) {
          MusicSortRow({ label: L10n.t('music_list_sort_favorite_time_desc'), by: MusicListSortBy.favoriteTime, order: MusicListSortOrder.desc, params: params })
          MusicSortRow({ label: L10n.t('music_list_sort_favorite_time_asc'), by: MusicListSortBy.favoriteTime, order: MusicListSortOrder.asc, params: params })
        }
      }
      .width('100%')
      .padding({ bottom: 16 })
    }
    .constraintSize({ maxHeight: 420 })
  }
  .width('100%')
  .backgroundColor(SheetUtil.panelBg())
  .borderRadius({ topLeft: 16, topRight: 16 })
}

@ComponentV2
struct MusicSortRow {
  @Param label: string = '';
  @Param by: MusicListSortBy = MusicListSortBy.mtime;
  @Param order: MusicListSortOrder = MusicListSortOrder.desc;
  @Param params: MusicListSortSheetParams | undefined = undefined;

  private selected(): boolean {
    return this.params !== undefined && this.params.ctrl !== undefined &&
      this.params.ctrl.sortBy === this.by && this.params.ctrl.sortOrder === this.order;
  }

  build() {
    SheetListItem({
      title: this.label,
      showIcon: false,
      showCheck: true,
      checked: this.selected(),
      onSelect: (): void => {
        if (this.params !== undefined && this.params.ctrl !== undefined) {
          this.params.ctrl.setSort(this.by, this.order);
        }
        this.params?.close();
      }
    })
  }
}

// ===== 来源筛选弹层 =====

@Builder
function musicListSourceSheetBuilder(params: MusicListSourceSheetParams) {
  Column() {
    SheetHandle()
    Row() {
      Text(L10n.t('source'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
      Blank()
      Text(L10n.t('reset'))
        .fontSize(14)
        .fontColor(AppTheme.current().primary)
        .onClick(() => {
          if (params.ctrl !== undefined) {
            params.ctrl.selectedPaths = [];
            params.ctrl.refreshList(false);
          }
          params.close();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 10 })

    if (params.ctrl !== undefined && params.ctrl.availablePaths.length === 0) {
      Text(L10n.t('no_path'))
        .fontSize(14)
        .fontColor(AppTheme.current().subText)
        .padding(20)
    } else {
      List() {
        if (params.ctrl !== undefined) {
          ForEach(params.ctrl.availablePaths, (e: MusicListPathItem) => {
            ListItem() {
              MusicSourceCheckRow({
                path: e.path,
                valid: e.valid,
                checked: params.ctrl !== undefined && params.ctrl.selectedPaths.includes(e.path),
                onToggle: (): void => {
                  if (params.ctrl !== undefined) {
                    params.ctrl.togglePath(e.path);
                  }
                }
              })
            }
          }, (e: MusicListPathItem) => e.path)
        }
      }
      .width('100%')
      .constraintSize({ maxHeight: 300 })
    }
    Column().height(16)
  }
  .width('100%')
  .backgroundColor(SheetUtil.panelBg())
  .borderRadius({ topLeft: 16, topRight: 16 })
}

@ComponentV2
struct MusicSourceCheckRow {
  @Param path: string = '';
  @Param valid: boolean = true;
  @Param checked: boolean = false;
  @Param onToggle: () => void = (): void => {
  };

  build() {
    Row({ space: 10 }) {
      if (this.checked) {
        SymbolGlyph($r('sys.symbol.checkmark_square_fill'))
          .fontSize(20)
          .fontColor([AppTheme.current().primary])
      } else {
        SymbolGlyph($r('sys.symbol.checkmark_square'))
          .fontSize(20)
          .fontColor([AppTheme.current().hint])
      }
      Text(this.path)
        .fontSize(12)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph(this.valid ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.xmark'))
        .fontSize(16)
        .fontColor([this.valid ? '#43A047' : '#E53935'])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .onClick(() => {
      this.onToggle();
    })
  }
}
