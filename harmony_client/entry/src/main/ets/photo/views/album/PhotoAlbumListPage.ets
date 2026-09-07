import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { AppEventBus, EVENT_PHOTO_ALBUM_OVERVIEW_CHANGED } from '../../../common/AppEventBus';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { EmptyState } from '../../../common/components/EmptyState';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { PageScaffold } from '../../../common/PageScaffold';
import { PhotoAlbumItem } from '../../models/PhotoAlbumModels';
import { PhotoAlbumListController } from '../../controllers/PhotoAlbumListController';
import { PhotoTimelinePageParam } from '../timeline/PhotoTimelinePage';
import { PhotoAlbumCardView } from './PhotoAlbumHomeView';
import { PhotoAlbumEditDialog } from './PhotoAlbumEditDialog';

/**
 * 相册列表页（对齐 Flutter _AppPhotoAlbumListPageState + PhotoAlbumController）：
 * 分页网格 + 搜索/筛选排序/新建 + 相册操作弹层；支持选择模式（返回所选相册）。
 */

// ===== 筛选/排序弹层（对齐 Flutter _showMobileFilterSortSheet） =====

class AlbumFilterSortSheetParams extends SheetParamsBase {
  ctrl: PhotoAlbumListController = new PhotoAlbumListController();
}

@Builder
function AlbumFilterSortSheetContent(p: AlbumFilterSortSheetParams) {
  AlbumFilterSortSheetInner({ p: p })
}

@ComponentV2
struct AlbumFilterSortSheetInner {
  @Param p: AlbumFilterSortSheetParams = new AlbumFilterSortSheetParams();
  @Local typeFilter: string = 'all';
  @Local sortField: string = 'create_time';
  @Local sortOrder: string = 'desc';

  aboutToAppear(): void {
    this.typeFilter = this.p.ctrl.typeFilter;
    this.sortField = this.p.ctrl.sortField;
    this.sortOrder = this.p.ctrl.sortOrder;
  }

  build() {
    Column() {
      SheetHandle()
      Scroll() {
        Column() {
          Text(L10n.t('filter', '筛选'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
            .padding({ left: 20, right: 20, top: 6, bottom: 4 })
          this.OptionRow(L10n.t('photo_album_filter_all', '全部相册'), this.typeFilter === 'all', (): void => {
            this.typeFilter = 'all';
          })
          this.OptionRow(L10n.t('photo_album_filter_my_shared', '我分享的'), this.typeFilter === 'my_shared',
            (): void => {
              this.typeFilter = 'my_shared';
            })
          this.OptionRow(L10n.t('photo_album_filter_shared_to_me', '分享给我的'),
            this.typeFilter === 'shared_to_me', (): void => {
              this.typeFilter = 'shared_to_me';
            })

          Text(L10n.t('sort', '排序'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
            .padding({ left: 20, right: 20, top: 10, bottom: 4 })
          this.OptionRow(L10n.t('photo_album_sort_name_asc', '名称 ↑'),
            this.sortField === 'name' && this.sortOrder === 'asc', (): void => {
              this.sortField = 'name';
              this.sortOrder = 'asc';
            })
          this.OptionRow(L10n.t('photo_album_sort_name_desc', '名称 ↓'),
            this.sortField === 'name' && this.sortOrder === 'desc', (): void => {
              this.sortField = 'name';
              this.sortOrder = 'desc';
            })
          this.OptionRow(L10n.t('photo_album_sort_create_time_asc', '创建时间 ↑'),
            this.sortField === 'create_time' && this.sortOrder === 'asc', (): void => {
              this.sortField = 'create_time';
              this.sortOrder = 'asc';
            })
          this.OptionRow(L10n.t('photo_album_sort_create_time_desc', '创建时间 ↓'),
            this.sortField === 'create_time' && this.sortOrder === 'desc', (): void => {
              this.sortField = 'create_time';
              this.sortOrder = 'desc';
            })

          Button(L10n.t('ok', '确定'))
            .fontSize(15)
            .fontColor(AppTheme.current().buttonText)
            .backgroundColor(AppTheme.current().buttonBg)
            .height(42)
            .width('100%')
            .margin({ left: 20, right: 20, top: 12, bottom: 20 })
            .onClick(() => {
              this.p.ctrl.setTypeFilter(this.typeFilter);
              this.p.ctrl.setSort(this.sortField, this.sortOrder);
              this.p.close();
            })
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  /** 单个选项行（选中行尾显示勾选，对齐 Flutter item ListTile） */
  @Builder
  OptionRow(label: string, selected: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(15)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([AppTheme.current().primary])
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 })
    .onClick(() => {
      onTap();
    })
  }
}

// ===== 相册行操作弹层（对齐 Flutter _showAlbumActions） =====

class AlbumRowActionSheetParams extends SheetParamsBase {
  /** 编辑/删除仅非选择模式显示 */
  showEdit: boolean = false;
  /** 非创建者显示“信息”行 */
  showInfo: boolean = false;
  showDelete: boolean = false;
  onOpen: () => void = (): void => {
  };
  onInfo: () => void = (): void => {
  };
  onEdit: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function AlbumRowActionSheetContent(p: AlbumRowActionSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.arrow_right'),
      title: L10n.t('open', '打开'),
      onSelect: (): void => {
        p.close();
        p.onOpen();
      }
    })
    if (p.showInfo) {
      SheetListItem({
        icon: $r('sys.symbol.info_circle'),
        title: L10n.t('info', '信息'),
        onSelect: (): void => {
          p.close();
          p.onInfo();
        }
      })
    }
    if (p.showEdit) {
      SheetListItem({
        icon: $r('sys.symbol.square_and_pencil'),
        title: L10n.t('edit', '编辑'),
        onSelect: (): void => {
          p.close();
          p.onEdit();
        }
      })
    }
    if (p.showDelete) {
      SheetListItem({
        icon: $r('sys.symbol.trash'),
        title: L10n.t('delete', '删除'),
        onSelect: (): void => {
          p.close();
          p.onDelete();
        }
      })
    }
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

/** 相册列表路由参数（对齐 Flutter AppPhotoAlbumListPage 构造参数） */
export class PhotoAlbumListPageParam {
  /** 相册类型过滤：all/my_shared/shared_to_me */
  type: string = 'all';
  /** 选择模式：点击选择相册并返回 */
  selectionMode: boolean = false;
  /** 进入页面后自动弹出创建相册弹窗 */
  autoOpenCreate: boolean = false;
  /** 选择模式确认回调（返回所选相册） */
  onSelected: ((album: PhotoAlbumItem) => void) | undefined = undefined;
}

@ComponentV2
export struct PhotoAlbumListPage {
  @Param param: PhotoAlbumListPageParam = new PhotoAlbumListPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local selectedAlbumId: number = 0;
  @Local refreshing: boolean = false;
  @Local showCreateDialog: boolean = false;
  @Local editAlbum: PhotoAlbumItem | undefined = undefined;
  /** 视口宽度（用于计算网格列数） */
  @Local viewWidth: number = 0;
  private ctrl: PhotoAlbumListController = new PhotoAlbumListController();
  private didAutoOpenCreate: boolean = false;

  aboutToAppear(): void {
    this.ctrl.typeFilter = this.param.type;
    this.ctrl.init();
    // 自动弹出创建相册（对齐 Flutter autoOpenCreate + addPostFrameCallback）
    if (this.param.autoOpenCreate && !this.param.selectionMode && !this.didAutoOpenCreate) {
      this.didAutoOpenCreate = true;
      this.showCreateDialog = true;
    }
  }

  aboutToDisappear(): void {
    // 返回相册主页时刷新概览（对齐 Flutter push 返回后的 refreshOverview）
    AppEventBus.emit(EVENT_PHOTO_ALBUM_OVERVIEW_CHANGED);
  }

  // ===== 交互 =====

  private gridColumnCount(): number {
    const width = this.viewWidth;
    if (width <= 0 || width <= 750) {
      return 1;
    }
    return Math.min(6, Math.max(2, Math.floor(width / 340)));
  }

  private columnsTemplate(): string {
    const count = this.gridColumnCount();
    const parts: string[] = [];
    for (let i = 0; i < count; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  private openSearch(): void {
    DialogUtil.showInputDialog(L10n.t('search', '搜索'), '', this.ctrl.keyword)
      .then((r: DialogResult | undefined) => {
        if (typeof r === 'string') {
          this.ctrl.setKeyword(r.trim());
        }
      });
  }

  private openFilterSortSheet(): void {
    const p = new AlbumFilterSortSheetParams();
    p.ctrl = this.ctrl;
    SheetUtil.present(p, wrapBuilder(AlbumFilterSortSheetContent));
  }

  private openTimeline(album: PhotoAlbumItem): void {
    const p = new PhotoTimelinePageParam();
    p.title = `${album.name} · ${L10n.t('photo_menu_album_normal', '自建相册')}`;
    p.listType = 'timeline';
    p.albumId = album.id;
    NavUtil.push(AppRouter.PHOTO_TIMELINE, p);
  }

  private toggleSelection(albumId: number): void {
    this.selectedAlbumId = this.selectedAlbumId === albumId ? 0 : albumId;
  }

  private handleCardTap(album: PhotoAlbumItem): void {
    if (this.param.selectionMode) {
      this.toggleSelection(album.id);
      return;
    }
    this.openTimeline(album);
  }

  /** 选择模式确认：回调所选相册后返回 */
  private confirmSelection(): void {
    if (this.selectedAlbumId <= 0) {
      return;
    }
    for (const album of this.ctrl.items) {
      if (album.id === this.selectedAlbumId) {
        if (this.param.onSelected !== undefined) {
          this.param.onSelected(album);
        }
        break;
      }
    }
    this.popPage();
  }

  private showAlbumActions(album: PhotoAlbumItem): void {
    const p = new AlbumRowActionSheetParams();
    p.showEdit = !this.param.selectionMode;
    p.showInfo = !album.isOwner;
    p.showDelete = !this.param.selectionMode;
    p.onOpen = (): void => {
      if (this.param.selectionMode) {
        // 选择模式下“打开”即确认选择并返回（对齐 Flutter pop(album)）
        this.selectedAlbumId = album.id;
        this.confirmSelection();
        return;
      }
      this.openTimeline(album);
    };
    p.onInfo = (): void => {
      const content = L10n.t('photo_album_creator_with_name', '创建人：@name',
        L10n.paramsOf('name', album.ownerUsername));
      DialogUtil.showInfoDialog(L10n.t('info', '信息'), content);
    };
    p.onEdit = (): void => {
      this.editAlbum = album;
    };
    p.onDelete = (): void => {
      void this.confirmDelete(album);
    };
    SheetUtil.present(p, wrapBuilder(AlbumRowActionSheetContent));
  }

  private async confirmDelete(album: PhotoAlbumItem): Promise<void> {
    const content = `${L10n.t('delete', '删除')} "${album.name}" ?`;
    const ok = await DialogUtil.showConfirmDialog(L10n.tip, content);
    if (ok !== true) {
      return;
    }
    await this.ctrl.deleteAlbum(album.id);
  }

  // ===== UI =====

  build() {
    Stack() {
      PageScaffold({
        title: L10n.t('photo_menu_album_normal', '自建相册'),
        showBack: true,
        onBack: (): void => {
          this.popPage();
        },
        actions: (): void => {
          this.TitleActions()
        },
        content: (): void => {
          this.PageContent()
        }
      })

      // 新建相册弹窗
      if (this.showCreateDialog) {
        PhotoAlbumEditDialog({
          album: undefined,
          onDismiss: (): void => {
            this.showCreateDialog = false;
          },
          onSaved: (): void => {
            void this.ctrl.refresh();
          }
        })
      }
      // 编辑相册弹窗
      if (this.editAlbum !== undefined) {
        PhotoAlbumEditDialog({
          album: this.editAlbum,
          onDismiss: (): void => {
            this.editAlbum = undefined;
          },
          onSaved: (): void => {
            void this.ctrl.refresh();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 标题栏右侧操作：搜索 / 筛选排序 / 新建或确认选择 */
  @Builder
  TitleActions() {
    Row({ space: 8 }) {
      BorderedIconButton({
        icon: $r('sys.symbol.magnifyingglass'),
        onTap: (): void => {
          this.openSearch();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.slider_horizontal_2'),
        onTap: (): void => {
          this.openFilterSortSheet();
        }
      })
      if (this.param.selectionMode) {
        BorderedIconButton({
          icon: $r('sys.symbol.checkmark'),
          isEnabled: this.selectedAlbumId > 0,
          onTap: (): void => {
            this.confirmSelection();
          }
        })
      } else {
        BorderedIconButton({
          icon: $r('sys.symbol.plus'),
          onTap: (): void => {
            this.showCreateDialog = true;
          }
        })
      }
    }
  }

  @Builder
  PageContent() {
    Refresh({ refreshing: this.refreshing }) {
      if (this.ctrl.isLoading && this.ctrl.items.length === 0) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.items.length === 0) {
        // 空态：选择模式给出创建按钮，否则空状态占位
        Column() {
          if (this.param.selectionMode) {
            Button() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(18)
                  .fontColor([AppTheme.current().buttonText])
                Text(L10n.t('create', '创建'))
                  .fontSize(15)
                  .fontColor(AppTheme.current().buttonText)
              }
            }
            .height(44)
            .borderRadius(12)
            .backgroundColor(AppTheme.current().buttonBg)
            .onClick(() => {
              this.showCreateDialog = true;
            })
          } else {
            EmptyState({ message: L10n.t('no_data', '暂无数据') })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        this.GridContent()
      }
    }
    .onRefreshing(() => {
      this.refreshing = true;
      this.ctrl.refresh().finally(() => {
        this.refreshing = false;
      });
    })
    .width('100%')
    .height('100%')
  }

  /** 相册网格（对齐 Flutter SliverGrid：宽<=750 单列，否则 floor(width/340) 限制 2~6 列） */
  @Builder
  GridContent() {
    Grid() {
      ForEach(this.ctrl.items, (album: PhotoAlbumItem) => {
        GridItem() {
          PhotoAlbumCardView({
            fullpath: album.previews.length > 0 ? album.previews[0].fullpath : '',
            name: album.name,
            icon: album.isPublic ? $r('sys.symbol.eye') : $r('sys.symbol.lock'),
            showMore: !this.param.selectionMode,
            showSelection: this.param.selectionMode,
            selected: this.param.selectionMode && this.selectedAlbumId === album.id,
            onCardTap: (): void => {
              this.handleCardTap(album);
            },
            onSelectTap: (): void => {
              this.toggleSelection(album.id);
            },
            onMoreTap: (): void => {
              this.showAlbumActions(album);
            }
          })
            .aspectRatio(this.gridColumnCount() === 1 ? 2.3 : 1.25)
        }
      }, (album: PhotoAlbumItem) => `album_${album.id}_${album.name}_${album.isPublic}`)
      // 页脚：加载中 / 没有更多 / 加载更多
      GridItem() {
        this.Footer()
      }
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(10)
    .rowsGap(10)
    .padding(12)
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewWidth = Number(newArea.width);
    })
    // 滚动到接近底部自动加载更多（对齐 Flutter 滚动监听）
    .onScrollIndex((_start: number, end: number) => {
      if (end >= this.ctrl.items.length - 2) {
        void this.ctrl.loadMore();
      }
    })
  }

  @Builder
  Footer() {
    Row() {
      if (this.ctrl.isLoading) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(AppTheme.current().primary)
      } else if (!this.ctrl.hasMore) {
        Text(L10n.t('no_more', '没有更多'))
          .fontSize(12)
          .fontColor(AppTheme.current().hint)
      } else {
        Text(L10n.t('load_more', '加载更多'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .onClick(() => {
            void this.ctrl.loadMore();
          })
      }
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
  }
}
