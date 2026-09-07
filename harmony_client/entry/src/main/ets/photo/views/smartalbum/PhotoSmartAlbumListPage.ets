import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { EmptyState } from '../../../common/components/EmptyState';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { PageScaffold } from '../../../common/PageScaffold';
import { PhotoSmartAlbumItem } from '../../models/PhotoAlbumModels';
import { PhotoSmartAlbumListController } from '../../controllers/PhotoSmartAlbumListController';
import { SmartAlbumTooltip } from '../../utils/SmartAlbumTooltip';
import { PhotoTimelinePageParam } from '../timeline/PhotoTimelinePage';
import { PhotoAlbumCardView } from '../album/PhotoAlbumHomeView';
import { PhotoSmartAlbumEditDialog } from './PhotoSmartAlbumEditDialog';

/**
 * 智能相册列表页（对齐 Flutter AppPhotoSmartAlbumListPage + PhotoSmartAlbumController）：
 * 分页网格 + 搜索/新建 + 智能相册操作弹层（打开/编辑/删除）。
 */

// ===== 智能相册行操作弹层（对齐 Flutter _showSmartAlbumActions） =====

class SmartAlbumRowActionSheetParams extends SheetParamsBase {
  onOpen: () => void = (): void => {
  };
  onEdit: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function SmartAlbumRowActionSheetContent(p: SmartAlbumRowActionSheetParams) {
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
    SheetListItem({
      icon: $r('sys.symbol.square_and_pencil'),
      title: L10n.t('edit', '编辑'),
      onSelect: (): void => {
        p.close();
        p.onEdit();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.trash'),
      title: L10n.t('delete', '删除'),
      onSelect: (): void => {
        p.close();
        p.onDelete();
      }
    })
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

/** 智能相册列表路由参数（对齐 Flutter AppPhotoSmartAlbumListPage.autoOpenCreate） */
export class PhotoSmartAlbumListPageParam {
  autoOpenCreate: boolean = false;
}

@ComponentV2
export struct PhotoSmartAlbumListPage {
  @Param param: PhotoSmartAlbumListPageParam = new PhotoSmartAlbumListPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local refreshing: boolean = false;
  @Local showCreateDialog: boolean = false;
  @Local editAlbum: PhotoSmartAlbumItem | undefined = undefined;
  /** 视口宽度（用于计算网格列数） */
  @Local viewWidth: number = 0;
  private ctrl: PhotoSmartAlbumListController = new PhotoSmartAlbumListController();
  private didAutoOpenCreate: boolean = false;

  aboutToAppear(): void {
    this.ctrl.init();
    // 自动弹出创建智能相册弹窗（对齐 Flutter autoOpenCreate + addPostFrameCallback）
    if (this.param.autoOpenCreate && !this.didAutoOpenCreate) {
      this.didAutoOpenCreate = true;
      this.showCreateDialog = true;
    }
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

  private openTimeline(album: PhotoSmartAlbumItem): void {
    const p = new PhotoTimelinePageParam();
    p.title = `${album.name} · ${L10n.t('photo_menu_album_smart', '智能相册')}`;
    p.listType = 'timeline';
    p.smartAlbumId = album.id;
    NavUtil.push(AppRouter.PHOTO_TIMELINE, p);
  }

  /** 信息弹窗：筛选条件描述文本（对齐 Flutter onInfo → buildAlbumTooltipText） */
  private showSmartAlbumInfo(album: PhotoSmartAlbumItem): void {
    const tooltip = SmartAlbumTooltip.build(album);
    DialogUtil.showInfoDialog(album.name,
      tooltip.trim().length > 0 ? tooltip : L10n.t('no_data', '暂无数据'));
  }

  private showSmartAlbumActions(album: PhotoSmartAlbumItem): void {
    const p = new SmartAlbumRowActionSheetParams();
    p.onOpen = (): void => {
      this.openTimeline(album);
    };
    p.onEdit = (): void => {
      this.editAlbum = album;
    };
    p.onDelete = (): void => {
      void this.confirmDelete(album);
    };
    SheetUtil.present(p, wrapBuilder(SmartAlbumRowActionSheetContent));
  }

  /** 删除确认（对齐 Flutter _confirmDelete：need_confirm + confirm_delete[名称]） */
  private async confirmDelete(album: PhotoSmartAlbumItem): Promise<void> {
    const content = `${L10n.t('confirm_delete', '确定删除吗？')}[${album.name}]`;
    const ok = await DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'), content,
      undefined, L10n.confirm, L10n.cancel);
    if (ok !== true) {
      return;
    }
    await this.ctrl.deleteSmartAlbum(album.id);
  }

  // ===== UI =====

  build() {
    PageScaffold({
      title: L10n.t('photo_menu_album_smart', '智能相册'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageContent()
      },
      // 弹窗必须在 NavDestination 内部挂载；组件实例化只能放在 @Builder 方法中
      overlayContent: (): void => {
        this.EditDialogOverlay()
      }
    })
  }

  /** 新建/编辑智能相册弹窗浮层 */
  @Builder
  EditDialogOverlay() {
    // 新建智能相册弹窗
    if (this.showCreateDialog) {
      PhotoSmartAlbumEditDialog({
        album: undefined,
        onSubmit: (name: string, type: string, filterContent: Record<string, Object>): Promise<boolean> => {
          return this.ctrl.createSmartAlbum(name, type, filterContent);
        },
        onDismiss: (): void => {
          this.showCreateDialog = false;
        }
      })
    }
    // 编辑智能相册弹窗
    if (this.editAlbum !== undefined) {
      PhotoSmartAlbumEditDialog({
        album: this.editAlbum,
        onSubmit: (name: string, type: string, filterContent: Record<string, Object>): Promise<boolean> => {
          return this.ctrl.updateSmartAlbum(this.editAlbum!.id, name, type, filterContent);
        },
        onDismiss: (): void => {
          this.editAlbum = undefined;
        }
      })
    }
  }

  /** 标题栏右侧操作：搜索 / 新建 */
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
        icon: $r('sys.symbol.plus'),
        onTap: (): void => {
          this.showCreateDialog = true;
        }
      })
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
        Column() {
          EmptyState({ message: L10n.t('no_data', '暂无数据') })
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

  /** 智能相册网格（对齐 Flutter SliverGrid：宽<=750 单列，否则 floor(width/340) 限制 2~6 列） */
  @Builder
  GridContent() {
    Grid() {
      ForEach(this.ctrl.items, (album: PhotoSmartAlbumItem) => {
        GridItem() {
          PhotoAlbumCardView({
            fullpath: album.previews.length > 0 ? album.previews[0].fullpath : '',
            name: album.name,
            icon: album.type === 'smart_date' ? $r('sys.symbol.calendar')
              : $r('sys.symbol.slider_horizontal_2'),
            showInfo: true,
            onCardTap: (): void => {
              this.openTimeline(album);
            },
            onInfoTap: (): void => {
              this.showSmartAlbumInfo(album);
            },
            onMoreTap: (): void => {
              this.showSmartAlbumActions(album);
            }
          })
            .aspectRatio(this.gridColumnCount() === 1 ? 2.3 : 1.25)
        }
      }, (album: PhotoSmartAlbumItem) => `smart_${album.id}_${album.name}`)
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
