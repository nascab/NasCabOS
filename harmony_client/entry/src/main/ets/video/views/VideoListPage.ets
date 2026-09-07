import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { EmptyState } from '../../common/components/EmptyState';
import { SearchInputBar } from '../../common/components/SearchInputBar';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { PageScaffold } from '../../common/PageScaffold';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { AppEventBus } from '../../common/AppEventBus';
import { ThemeManager } from '../../core/theme/ThemeManager';
import { VideoHomeItemBean, VideoListPathItem, parseVideoHomeItemBean } from '../models/VideoModels';
import { VideoHistoryApiService } from '../service/VideoApiServices';
import {
  VideoListController, VideoListSortBy, VideoListSortOrder, VideoListYearGroup
} from '../controllers/VideoListController';
import { VideoItemPoster } from '../components/VideoItemPoster';
import { VideoItemSyncService } from '../utils/VideoItemUtils';
import { VideoListPageParam } from '../router/VideoRoutes';

/**
 * 视频列表页（对齐 Flutter AppVideoListPage）：
 * 顶部搜索 + 排序/来源/筛选按钮 + 海报网格（缩放记忆）+ 分页加载；
 * listType=history 时渲染历史网格（无工具栏，对齐 _isHistory 分支）。
 */
@ComponentV2
export struct VideoListPage {
  @Param param: VideoListPageParam = new VideoListPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 嵌入模式（影音主入口 Tab 内）：无标题栏，工具栏左侧显示"回到首页"图标 */
  @Param embedded: boolean = false;
  /** 嵌入模式下点击工具栏主页图标回调（回到影音首页模式） */
  @Param onBackHome: () => void = (): void => {
  };
  ctrl: VideoListController = new VideoListController();
  @Local historyItems: VideoHomeItemBean[] = [];
  @Local historyLoading: boolean = false;
  @Local gridWidth: number = 0;
  @Local themeTick: number = 0;
  private isHistory: boolean = false;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
  };
  private deletedListener: ((data: string) => void) | undefined = undefined;

  aboutToAppear(): void {
    this.isHistory = this.param.listType.trim().toLowerCase() === 'history';
    this.ctrl.configure(this.param.initialMediaType, this.param.listType,
      this.param.albumId, this.param.collectionId, this.param.smartAlbumId,
      this.param.initialGenres, this.param.initialRegions,
      this.param.initialActors, this.param.initialDirectors);
    if (!this.isHistory) {
      this.ctrl.init();
    } else {
      void this.refreshHistory();
      this.deletedListener = (_data: string): void => {
        void this.refreshHistory();
      };
      AppEventBus.on(VideoItemSyncService.EVENT_VIDEO_ITEM_DELETED, this.deletedListener);
    }
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  aboutToDisappear(): void {
    this.ctrl.dispose();
    if (this.deletedListener !== undefined) {
      AppEventBus.off(VideoItemSyncService.EVENT_VIDEO_ITEM_DELETED, this.deletedListener);
    }
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  private async refreshHistory(): Promise<void> {
    if (this.historyLoading) {
      return;
    }
    this.historyLoading = true;
    try {
      this.historyItems = await new VideoHistoryApiService().listHistory();
    } finally {
      this.historyLoading = false;
    }
  }

  /** 海报列数（对齐 _AppVideoListGrid：baseWidth×posterScale，clamp 2~6） */
  private gridColumns(): number {
    const maxWidth = this.gridWidth > 0 ? this.gridWidth : 360;
    const baseWidth = maxWidth < 420 ? 120 : 140;
    const desired = baseWidth * this.ctrl.posterScale;
    const raw = Math.floor(maxWidth / desired);
    return Math.min(Math.max(raw, 2), 6);
  }

  private gridSpacing(): number {
    return this.gridWidth > 0 && this.gridWidth < 420 ? 10 : 12;
  }

  private columnsTemplate(): string {
    const cols = this.gridColumns();
    const arr: string[] = [];
    for (let i = 0; i < cols; i++) {
      arr.push('1fr');
    }
    return arr.join(' ');
  }

  build() {
    PageScaffold({
      title: this.embedded ? '' : this.param.title,
      showBack: !this.embedded,
      onBack: (): void => {
        this.popPage();
      },
      actions: this.listActions,
      content: this.listContent
    })
  }

  @Builder
  listActions() {
  }

  @Builder
  listContent() {
    Column() {
      if (!this.isHistory) {
        this.ToolBar()
      }
      if (this.isHistory) {
        this.HistoryBody()
      } else if (this.ctrl.loading) {
        Column({ space: 10 }) {
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
          EmptyState({ message: L10n.t('no_data', '暂无数据') })
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        this.ListBody()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().cardBg)
  }

  @Builder
  ToolBar() {
    Row({ space: 8 }) {
      if (this.embedded) {
        BorderedIconButton({
          icon: $r('sys.symbol.house'),
          onTap: (): void => {
            this.onBackHome();
          }
        })
      }
      SearchInputBar({
        hintText: L10n.t('video_list_search_hint', '搜索影片'),
        text: this.ctrl.searchText,
        onChanged: (v: string): void => {
          this.ctrl.setSearchText(v);
        },
        onClear: (): void => {
          this.ctrl.clearSearch();
        }
      })
        .layoutWeight(1)
      BorderedIconButton({
        icon: $r('sys.symbol.text_arrow_up_and_down'),
        active: this.ctrl.hasCustomSort,
        onTap: (): void => {
          VideoListSortSheet.present(this.ctrl);
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.square_stack_3d'),
        active: this.ctrl.selectedPaths.length > 0,
        onTap: (): void => {
          VideoListSourceSheet.present(this.ctrl);
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.funnel'),
        active: this.ctrl.hasActiveFilters,
        onTap: (): void => {
          VideoListFilterSheet.present(this.ctrl);
        }
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 6 })
  }

  @Builder
  ListBody() {
    Scroll() {
      Column() {
        Grid() {
          ForEach(this.ctrl.items, (item: VideoHomeItemBean) => {
            GridItem() {
              VideoItemPoster({
                item: item,
                currentAlbumId: this.ctrl.albumId,
                onDeleted: (deleted: VideoHomeItemBean): void => {
                  this.ctrl.items = this.ctrl.items.filter(
                    (e: VideoHomeItemBean) => e.id !== deleted.id);
                  this.ctrl.total = Math.max(this.ctrl.total - 1, 0);
                },
                onFavoriteChanged: (isFav: boolean): void => {
                  this.ctrl.updateFavoriteState(item.id, isFav);
                },
                onRemovedFromCurrentAlbum: (): void => {
                  this.ctrl.removeFromCurrentAlbumState(item.id);
                }
              })
            }
          }, (item: VideoHomeItemBean) => `${item.id}`)
        }
        .columnsTemplate(this.columnsTemplate())
        .columnsGap(this.gridSpacing())
        .rowsGap(this.gridSpacing())
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 16 })
        .onAreaChange((_o: Area, n: Area) => {
          this.gridWidth = Number(n.width);
        })

        this.Footer()
      }
      .width('100%')
    }
    .scrollBar(BarState.Auto)
    .width('100%')
    .layoutWeight(1)
    .onReachEnd(() => {
      void this.ctrl.loadMore(true);
    })
  }

  @Builder
  HistoryBody() {
    if (this.historyLoading && this.historyItems.length === 0) {
      Column({ space: 10 }) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(AppTheme.current().primary)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.historyItems.length === 0) {
      Column() {
        EmptyState({ message: L10n.t('video_history_empty', '暂无播放历史') })
      }
      .width('100%')
      .layoutWeight(1)
    } else {
      Scroll() {
        Column() {
          Grid() {
            ForEach(this.historyItems, (item: VideoHomeItemBean, idx: number) => {
              GridItem() {
                VideoItemPoster({
                  item: item,
                  progress: item.progress,
                  onDeleted: (deleted: VideoHomeItemBean): void => {
                    this.historyItems = this.historyItems.filter(
                      (e: VideoHomeItemBean) => e.id !== deleted.id);
                  },
                  onFavoriteChanged: (isFav: boolean): void => {
                    const updated = this.historyItems.slice();
                    updated[idx] = parseVideoHomeItemBean(updated[idx] as Object);
                    updated[idx].isFavorite = isFav;
                    this.historyItems = updated;
                  }
                })
              }
            }, (item: VideoHomeItemBean) => `${item.id}`)
          }
          .columnsTemplate(this.columnsTemplate())
          .columnsGap(this.gridSpacing())
          .rowsGap(this.gridSpacing())
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 16 })
          .onAreaChange((_o: Area, n: Area) => {
            this.gridWidth = Number(n.width);
          })
        }
        .width('100%')
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  Footer() {
    if (this.ctrl.loadingMore) {
      Row() {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(AppTheme.current().primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding(12)
    } else if (!this.ctrl.hasMore) {
      Text(L10n.t('video_list_no_more', '没有更多了'))
        .fontSize(13)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(12)
    } else if (this.ctrl.autoLoadFailed) {
      Button(L10n.t('video_list_load_more', '加载更多'))
        .fontSize(14)
        .fontColor(AppTheme.current().primary)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: AppTheme.current().divider })
        .height(36)
        .margin({ bottom: 12 })
        .onClick(() => {
          void this.ctrl.loadMore(false);
        })
    }
  }
}

// ===== 排序弹层（对齐 _openSortSheet + getVideoListSortEntries） =====

class SortEntry {
  by: VideoListSortBy = 'view_time';
  order: VideoListSortOrder = 'desc';
  labelKey: string = '';
  divider: boolean = false;
}

function sortEntries(isFavorite: boolean): SortEntry[] {
  const out: SortEntry[] = [];
  const add = (by: VideoListSortBy, order: VideoListSortOrder, key: string): void => {
    const e = new SortEntry();
    e.by = by;
    e.order = order;
    e.labelKey = key;
    out.push(e);
  };
  const div = (): void => {
    const e = new SortEntry();
    e.divider = true;
    out.push(e);
  };
  if (isFavorite) {
    add('favorite_time', 'desc', 'video_list_sort_favorite_time_desc');
    add('favorite_time', 'asc', 'video_list_sort_favorite_time_asc');
    div();
  }
  add('view_time', 'desc', 'video_list_sort_view_time_desc');
  add('view_time', 'asc', 'video_list_sort_view_time_asc');
  div();
  add('create_time', 'desc', 'create_time_desc');
  add('create_time', 'asc', 'create_time_asc');
  div();
  add('year', 'desc', 'video_list_sort_year_desc');
  add('year', 'asc', 'video_list_sort_year_asc');
  div();
  add('score', 'desc', 'video_list_sort_score_desc');
  add('score', 'asc', 'video_list_sort_score_asc');
  div();
  add('name', 'asc', 'name_asc');
  add('name', 'desc', 'name_desc');
  return out;
}

class VideoListSortSheetParams extends SheetParamsBase {
  ctrl: VideoListController = new VideoListController();
}

@ComponentV2
struct VideoListSortSheetInner {
  @Param p: VideoListSortSheetParams = new VideoListSortSheetParams();

  build() {
    Column() {
      SheetHandle()
      Scroll() {
        Column() {
          ForEach(sortEntries(this.p.ctrl.isFavoriteList), (e: SortEntry) => {
            if (e.divider) {
              Row()
                .width('100%')
                .height(1)
                .backgroundColor(AppTheme.current().divider)
                .margin({ top: 4, bottom: 4 })
            } else {
              Row({ space: 12 }) {
                Column()
                  .width(20)
                Text(L10n.t(e.labelKey, e.labelKey))
                  .fontSize(15)
                  .fontColor(AppTheme.current().onSurface)
                  .layoutWeight(1)
                if (this.p.ctrl.sortBy === e.by && this.p.ctrl.sortOrder === e.order) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(18)
                    .fontColor([AppTheme.current().primary])
                }
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 13, bottom: 13 })
              .onClick(() => {
                this.p.close();
                this.p.ctrl.setSort(e.by, e.order);
              })
            }
          }, (e: SortEntry, idx: number) => `${idx}_${e.labelKey}`)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .constraintSize({ maxHeight: 480 })
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

export class VideoListSortSheet {
  static present(ctrl: VideoListController): void {
    const p = new VideoListSortSheetParams();
    p.ctrl = ctrl;
    SheetUtil.present(p, wrapBuilder(VideoListSortSheetContent));
  }
}

@Builder
function VideoListSortSheetContent(p: VideoListSortSheetParams) {
  VideoListSortSheetInner({ p: p })
}

// ===== 来源筛选弹层（对齐 VideoListSourcePanel） =====

class VideoListSourceSheetParams extends SheetParamsBase {
  ctrl: VideoListController = new VideoListController();
}

@ComponentV2
struct VideoListSourceSheetInner {
  @Param p: VideoListSourceSheetParams = new VideoListSourceSheetParams();

  build() {
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
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            void this.p.ctrl.clearSourcePathSelection();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: 6 })
      Row()
        .width('100%')
        .height(1)
        .backgroundColor(AppTheme.current().divider)
      if (this.p.ctrl.availablePaths.length === 0) {
        Text(L10n.t('no_path', '暂无路径'))
          .fontSize(14)
          .fontColor(AppTheme.current().subText)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(24)
      } else {
        Scroll() {
          Column() {
            ForEach(this.p.ctrl.availablePaths, (item: VideoListPathItem) => {
              Row({ space: 10 }) {
                SymbolGlyph(
                  this.p.ctrl.selectedPaths.includes(item.path)
                    ? $r('sys.symbol.checkmark_square_fill')
                    : $r('sys.symbol.square'))
                  .fontSize(20)
                  .fontColor([this.p.ctrl.selectedPaths.includes(item.path)
                    ? AppTheme.current().primary : AppTheme.current().hint])
                Text(item.path)
                  .fontSize(13)
                  .fontColor(AppTheme.current().onSurface)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                SymbolGlyph(item.valid
                  ? $r('sys.symbol.checkmark_circle_fill')
                  : $r('sys.symbol.xmark_circle_fill'))
                  .fontSize(16)
                  .fontColor([item.valid ? '#34C759' : '#FF3B30'])
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 11, bottom: 11 })
              .onClick(() => {
                const selected = this.p.ctrl.selectedPaths.includes(item.path);
                void this.p.ctrl.setSourcePathSelected(item.path, !selected);
              })
            }, (item: VideoListPathItem) => item.path)
          }
          .width('100%')
        }
        .scrollBar(BarState.Auto)
        .width('100%')
        .constraintSize({ maxHeight: 380 })
      }
      Blank().height(12)
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

export class VideoListSourceSheet {
  static present(ctrl: VideoListController): void {
    const p = new VideoListSourceSheetParams();
    p.ctrl = ctrl;
    SheetUtil.present(p, wrapBuilder(VideoListSourceSheetContent));
  }
}

@Builder
function VideoListSourceSheetContent(p: VideoListSourceSheetParams) {
  VideoListSourceSheetInner({ p: p })
}

// ===== 筛选弹层（对齐 VideoListFilterPanel） =====

class VideoListFilterSheetParams extends SheetParamsBase {
  ctrl: VideoListController = new VideoListController();
}

@ComponentV2
struct VideoListFilterSheetInner {
  @Param p: VideoListFilterSheetParams = new VideoListFilterSheetParams();
  @Local tick: number = 0;

  private toggle(): void {
    this.tick++;
  }

  @Builder
  Chip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor(selected ? AppTheme.current().primary : AppTheme.current().onSurface)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(8)
      .backgroundColor(selected ? AppTheme.withAlpha(AppTheme.current().primary, 0.14)
        : Color.Transparent)
      .border({ width: 1, color: selected ? AppTheme.withAlpha(AppTheme.current().primary, 0.4)
        : AppTheme.current().divider })
      .margin({ right: 10, bottom: 10 })
      .onClick(() => {
        onTap();
        this.toggle();
      })
  }

  @Builder
  GroupLabel(label: string) {
    Text(label)
      .fontSize(14)
      .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
      .width(64)
      .margin({ top: 8 })
  }

  build() {
    Column() {
      SheetHandle()
      Scroll() {
        Column() {
          if (this.p.ctrl.initialMediaType.trim().length === 0) {
            Row() {
              this.GroupLabel(L10n.t('type', '类型'))
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
                this.Chip(L10n.t('all', '全部'), this.p.ctrl.mediaType.trim().length === 0,
                  (): void => {
                    this.p.ctrl.setMediaType('');
                  })
                this.Chip(L10n.t('video_home_type_movie', '电影'),
                  this.p.ctrl.mediaType.trim() === 'movie', (): void => {
                    this.p.ctrl.setMediaType('movie');
                  })
                this.Chip(L10n.t('video_home_type_tv', '电视剧'),
                  this.p.ctrl.mediaType.trim() === 'tv', (): void => {
                    this.p.ctrl.setMediaType('tv');
                  })
              }
              .layoutWeight(1)
            }
            .alignItems(VerticalAlign.Top)
            .width('100%')
            .margin({ top: 8, bottom: 8 })
          }
          // 年份分组
          Row() {
            this.GroupLabel(L10n.t('video_list_filter_years', '年份'))
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
              if (this.p.ctrl.getYearGroups().length === 0) {
                Text(L10n.t('no_data', '暂无数据'))
                  .fontSize(14)
                  .fontColor(AppTheme.current().subText)
                  .margin({ top: 6 })
              } else {
                this.Chip(L10n.t('all', '全部'), this.p.ctrl.selectedYears.length === 0,
                  (): void => {
                    this.p.ctrl.selectedYears = [];
                    void this.p.ctrl.refreshList(true);
                  })
                ForEach(this.p.ctrl.getYearGroups(), (g: VideoListYearGroup) => {
                  this.Chip(g.label, g.single
                    ? this.p.ctrl.selectedYears.length === 1
                      && this.p.ctrl.selectedYears.includes(g.years[0])
                    : g.years.every((y: number) => this.p.ctrl.selectedYears.includes(y)),
                  (): void => {
                    if (g.single) {
                      this.p.ctrl.toggleYear(g.years[0]);
                    } else {
                      this.p.ctrl.toggleYearGroup(g.years);
                    }
                  })
                }, (g: VideoListYearGroup) => g.label)
              }
            }
            .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
          .margin({ top: 8, bottom: 8 })
          // 地区分组
          Row() {
            this.GroupLabel(L10n.t('video_list_filter_regions', '地区'))
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
              if (this.p.ctrl.availableRegions.length === 0) {
                Text(L10n.t('no_data', '暂无数据'))
                  .fontSize(14)
                  .fontColor(AppTheme.current().subText)
                  .margin({ top: 6 })
              } else {
                this.Chip(L10n.t('all', '全部'), this.p.ctrl.regions.length === 0,
                  (): void => {
                    this.p.ctrl.regions = [];
                    void this.p.ctrl.refreshList(true);
                  })
                ForEach(this.p.ctrl.availableRegions, (r: string) => {
                  this.Chip(r, this.p.ctrl.regions.includes(r), (): void => {
                    this.p.ctrl.toggleRegion(r);
                  })
                }, (r: string) => r)
              }
            }
            .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
          .margin({ top: 8, bottom: 8 })
          // 类型风格分组
          Row() {
            this.GroupLabel(L10n.t('video_list_filter_genres', '类型风格'))
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
              if (this.p.ctrl.availableGenres.length === 0) {
                Text(L10n.t('no_data', '暂无数据'))
                  .fontSize(14)
                  .fontColor(AppTheme.current().subText)
                  .margin({ top: 6 })
              } else {
                this.Chip(L10n.t('all', '全部'), this.p.ctrl.genres.length === 0,
                  (): void => {
                    this.p.ctrl.genres = [];
                    void this.p.ctrl.refreshList(true);
                  })
                ForEach(this.p.ctrl.availableGenres, (g: string) => {
                  this.Chip(g, this.p.ctrl.genres.includes(g), (): void => {
                    this.p.ctrl.toggleGenre(g);
                  })
                }, (g: string) => g)
              }
            }
            .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
          .margin({ top: 8, bottom: 8 })

          Row() {
            Blank()
            Button(L10n.t('reset', '重置'))
              .fontSize(14)
              .fontColor(AppTheme.current().primary)
              .backgroundColor(Color.Transparent)
              .height(34)
              .onClick(() => {
                this.p.ctrl.resetFilter();
                this.toggle();
              })
          }
          .width('100%')
          .margin({ top: 4 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 20 })
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .constraintSize({ maxHeight: 520 })
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

export class VideoListFilterSheet {
  static present(ctrl: VideoListController): void {
    const p = new VideoListFilterSheetParams();
    p.ctrl = ctrl;
    SheetUtil.present(p, wrapBuilder(VideoListFilterSheetContent));
  }
}

@Builder
function VideoListFilterSheetContent(p: VideoListFilterSheetParams) {
  VideoListFilterSheetInner({ p: p })
}
