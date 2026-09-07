import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { EmptyState } from '../../../common/components/EmptyState';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { PageScaffold } from '../../../common/PageScaffold';
import { PhotoCollectionItem } from '../../models/PhotoAlbumModels';
import { PhotoCollectionListController } from '../../controllers/PhotoCollectionListController';
import { PhotoTimelinePageParam } from '../timeline/PhotoTimelinePage';
import { PhotoAlbumCardView } from '../album/PhotoAlbumHomeView';
import { PhotoCollectionEditDialog } from './PhotoCollectionEditDialog';

/**
 * 照片合集列表页（对齐 Flutter AppPhotoCollectionListPage + PhotoCollectionController）：
 * 分页网格 + 搜索/新建 + 合集操作弹层（打开/编辑/删除）。
 */

// ===== 合集行操作弹层（对齐 Flutter _showCollectionActions） =====

class CollectionRowActionSheetParams extends SheetParamsBase {
  onOpen: () => void = (): void => {
  };
  onEdit: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function CollectionRowActionSheetContent(p: CollectionRowActionSheetParams) {
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

/** 照片合集列表路由参数（对齐 Flutter AppPhotoCollectionListPage.autoOpenCreate） */
export class PhotoCollectionListPageParam {
  autoOpenCreate: boolean = false;
}

@ComponentV2
export struct PhotoCollectionListPage {
  @Param param: PhotoCollectionListPageParam = new PhotoCollectionListPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local refreshing: boolean = false;
  @Local showCreateDialog: boolean = false;
  @Local editCollection: PhotoCollectionItem | undefined = undefined;
  /** 视口宽度（用于计算网格列数） */
  @Local viewWidth: number = 0;
  private ctrl: PhotoCollectionListController = new PhotoCollectionListController();
  private didAutoOpenCreate: boolean = false;

  aboutToAppear(): void {
    this.ctrl.init();
    // 自动弹出创建合集弹窗（对齐 Flutter autoOpenCreate + addPostFrameCallback）
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

  private openTimeline(collection: PhotoCollectionItem): void {
    const p = new PhotoTimelinePageParam();
    p.title = `${collection.name} · ${L10n.t('photo_menu_album_collection', '照片合集')}`;
    p.listType = 'timeline';
    p.collectionId = collection.id;
    NavUtil.push(AppRouter.PHOTO_TIMELINE, p);
  }

  /** 信息弹窗：路径逐行展示（对齐 Flutter onInfo） */
  private showCollectionInfo(collection: PhotoCollectionItem): void {
    const lines: string[] = [];
    for (const p of collection.pathList) {
      const t = p.trim();
      if (t.length > 0) {
        lines.push(t);
      }
    }
    DialogUtil.showInfoDialog(collection.name,
      lines.length > 0 ? lines.join('\n') : L10n.t('no_data', '暂无数据'));
  }

  private showCollectionActions(collection: PhotoCollectionItem): void {
    const p = new CollectionRowActionSheetParams();
    p.onOpen = (): void => {
      this.openTimeline(collection);
    };
    p.onEdit = (): void => {
      this.editCollection = collection;
    };
    p.onDelete = (): void => {
      void this.confirmDelete(collection);
    };
    SheetUtil.present(p, wrapBuilder(CollectionRowActionSheetContent));
  }

  /** 删除确认（对齐 Flutter confirmDelete：'删除 "名称" ?'） */
  private async confirmDelete(collection: PhotoCollectionItem): Promise<void> {
    const content = `${L10n.t('delete', '删除')} "${collection.name}" ?`;
    const ok = await DialogUtil.showConfirmDialog(L10n.tip, content);
    if (ok !== true) {
      return;
    }
    await this.ctrl.deleteCollection(collection.id);
  }

  // ===== UI =====

  build() {
    PageScaffold({
      title: L10n.t('photo_menu_album_collection', '照片合集'),
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

  /** 新建/编辑合集弹窗浮层 */
  @Builder
  EditDialogOverlay() {
    // 新建合集弹窗
    if (this.showCreateDialog) {
      PhotoCollectionEditDialog({
        collection: undefined,
        onSubmit: (name: string, pathList: string[]): Promise<boolean> => {
          return this.ctrl.createCollection(name, pathList);
        },
        onDismiss: (): void => {
          this.showCreateDialog = false;
        }
      })
    }
    // 编辑合集弹窗
    if (this.editCollection !== undefined) {
      PhotoCollectionEditDialog({
        collection: this.editCollection,
        onSubmit: (name: string, pathList: string[]): Promise<boolean> => {
          return this.ctrl.updateCollection(this.editCollection!.id, name, pathList);
        },
        onDismiss: (): void => {
          this.editCollection = undefined;
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

  /** 合集网格（对齐 Flutter SliverGrid：宽<=750 单列，否则 floor(width/340) 限制 2~6 列） */
  @Builder
  GridContent() {
    Grid() {
      ForEach(this.ctrl.items, (collection: PhotoCollectionItem) => {
        GridItem() {
          PhotoAlbumCardView({
            fullpath: collection.previews.length > 0 ? collection.previews[0].fullpath : '',
            name: collection.name,
            icon: $r('sys.symbol.folder'),
            trailingText: `${this.pathCount(collection)}`,
            showInfo: true,
            onCardTap: (): void => {
              this.openTimeline(collection);
            },
            onInfoTap: (): void => {
              this.showCollectionInfo(collection);
            },
            onMoreTap: (): void => {
              this.showCollectionActions(collection);
            }
          })
            .aspectRatio(this.gridColumnCount() === 1 ? 2.3 : 1.25)
        }
      }, (collection: PhotoCollectionItem) => `collection_${collection.id}_${collection.name}`)
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

  /** 非空路径数（对齐 Flutter pathCount 计算） */
  private pathCount(collection: PhotoCollectionItem): number {
    let count = 0;
    for (const p of collection.pathList) {
      if (p.trim().length > 0) {
        count++;
      }
    }
    return count;
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
