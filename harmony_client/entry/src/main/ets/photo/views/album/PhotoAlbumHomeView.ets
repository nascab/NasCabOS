import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { DialogUtil } from '../../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { AppEventBus, EVENT_PHOTO_ALBUM_OVERVIEW_CHANGED } from '../../../common/AppEventBus';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import {
  PhotoAlbumItem, PhotoAlbumPreviewItem, PhotoCollectionItem, PhotoSmartAlbumItem
} from '../../models/PhotoAlbumModels';
import {
  PhotoAlbumApiService, PhotoCollectionApiService, PhotoSmartAlbumApiService
} from '../../service/PhotoAlbumApiService';
import { SmartAlbumTooltip } from '../../utils/SmartAlbumTooltip';
import { PhotoTimelinePageParam } from '../timeline/PhotoTimelinePage';
import { PhotoAlbumEditDialog } from './PhotoAlbumEditDialog';

/**
 * 相册主页（对齐 Flutter _AppPhotoAlbumHomePageState）：
 * 三个分区（自建相册/智能相册/照片合集），每区标题行 + 最多 6 张横向卡片，
 * 下拉刷新 + 操作弹层（打开/编辑/删除）。
 */

// ===== 卡片操作弹层参数（对齐 Flutter showModalBottomSheet 三个 ListTiles） =====

class AlbumActionSheetParams extends SheetParamsBase {
  onOpen: () => void = (): void => {
  };
  onEdit: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function AlbumActionSheetContent(p: AlbumActionSheetParams) {
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

/**
 * 相册封面卡片（对齐 Flutter _AlbumCard/_SmartAlbumCard/_CollectionCard）：
 * 封面图（异步 tiny URL）+ 底部黑色渐变 + 左下图标与名称 + 右上更多按钮，
 * 可选左上信息按钮（智能相册/合集）与选择勾选框（相册列表选择模式）。
 */
@ComponentV2
export struct PhotoAlbumCardView {
  /** 封面预览图 fullpath（内部异步换取 tiny URL） */
  @Param fullpath: string = '';
  @Param name: string = '';
  /** 左下角小图标（相册: eye/lock；智能相册: calendar/slider_horizontal_2；合集: folder） */
  @Param icon: Resource = $r('sys.symbol.eye');
  /** 名称右侧附加文本（合集显示路径数） */
  @Param trailingText: string = '';
  /** 左上信息按钮（智能相册/合集） */
  @Param showInfo: boolean = false;
  /** 右上更多按钮 */
  @Param showMore: boolean = true;
  /** 选择模式勾选框（相册列表选择模式） */
  @Param showSelection: boolean = false;
  @Param selected: boolean = false;
  @Param onCardTap: () => void = (): void => {
  };
  @Param onMoreTap: () => void = (): void => {
  };
  @Param onInfoTap: () => void = (): void => {
  };
  @Param onSelectTap: () => void = (): void => {
  };
  @Local coverUrl: string = '';

  aboutToAppear(): void {
    this.resolveCover();
  }

  @Monitor('fullpath')
  onFullpathChange(): void {
    this.resolveCover();
  }

  /** 异步获取缩略图 URL（对齐 Flutter ApiController.getTinyUrl） */
  private resolveCover(): void {
    const fp = this.fullpath;
    if (fp.length === 0) {
      this.coverUrl = '';
      return;
    }
    ApiUrls.getTinyUrl(fp).then((url: string) => {
      if (fp === this.fullpath) {
        this.coverUrl = url;
      }
    }).catch(() => {
    });
  }

  build() {
    Stack() {
      // 封面：空时占位背景 + no_data 图（对齐 Flutter _PreviewImage）
      if (this.coverUrl.length > 0) {
        Image(this.coverUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else {
        Column() {
          Image($rawfile('icons/no_data.png'))
            .width(54)
            .height(54)
            .objectFit(ImageFit.Contain)
            .draggable(false)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppTheme.current().inputFill)
      }

      // 内容层：顶部按钮区 + 底部渐变（渐变作为信息行背景，紧贴卡片最下方）+ 左下信息行
      Column() {
        Row({ space: 6 }) {
          if (this.showSelection) {
            this.CornerButton(this.selected ? $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'),
              (): void => {
                this.onSelectTap();
              }, this.selected ? AppTheme.current().primary : '#FFFFFF')
          }
          if (this.showInfo) {
            this.CornerButton($r('sys.symbol.info_circle'), (): void => {
              this.onInfoTap();
            }, '#FFFFFF')
          }
          Blank()
          if (this.showMore) {
            this.CornerButton($r('sys.symbol.more'), (): void => {
              this.onMoreTap();
            }, '#FFFFFF')
          }
        }
        .width('100%')
        .padding(6)

        Blank()

        Row({ space: 6 }) {
          SymbolGlyph(this.icon)
            .fontSize(16)
            .fontColor([Color.White])
          Text(this.name)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.trailingText.length > 0) {
            Text(this.trailingText)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
        }
        .width('100%')
        // 顶部 44 内边距容纳上方渐变过渡，渐变背景直达卡片底部（对齐 Flutter Positioned bottom:0 渐变）
        .padding({ left: 10, right: 10, top: 44, bottom: 10 })
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#00000000', 0.0], ['#CC000000', 1.0]]
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .borderRadius(14)
    .clip(true)
    .onClick(() => {
      this.onCardTap();
    })
  }

  /** 顶部圆形半透明小按钮（对齐 Flutter Material black 30% 圆形 InkWell） */
  @Builder
  CornerButton(icon: Resource, onTap: () => void, iconColor: string) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([iconColor])
    }
    .width(30)
    .height(30)
    .borderRadius(15)
    .backgroundColor('#4D000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      onTap();
    })
  }
}

/**
 * 相册主页视图（对齐 Flutter AppPhotoAlbumHomePage）。
 */
@ComponentV2
export struct PhotoAlbumHomeView {
  @Local albums: PhotoAlbumItem[] = [];
  @Local smartAlbums: PhotoSmartAlbumItem[] = [];
  @Local collections: PhotoCollectionItem[] = [];
  @Local albumTotal: number = 0;
  @Local smartAlbumTotal: number = 0;
  @Local collectionTotal: number = 0;
  @Local isLoading: boolean = false;
  @Local refreshing: boolean = false;
  /** 新建/编辑相册弹窗状态 */
  @Local showCreateDialog: boolean = false;
  @Local editAlbum: PhotoAlbumItem | undefined = undefined;
  private albumApi: PhotoAlbumApiService = new PhotoAlbumApiService();
  private collectionApi: PhotoCollectionApiService = new PhotoCollectionApiService();
  private smartAlbumApi: PhotoSmartAlbumApiService = new PhotoSmartAlbumApiService();
  /** 列表页返回后刷新概览（对齐 Flutter push 返回后的 _ctrl.refreshOverview） */
  private overviewListener: () => void = (): void => {
    void this.loadOverview();
  };

  aboutToAppear(): void {
    AppEventBus.on(EVENT_PHOTO_ALBUM_OVERVIEW_CHANGED, this.overviewListener);
    void this.loadOverview();
  }

  aboutToDisappear(): void {
    AppEventBus.off(EVENT_PHOTO_ALBUM_OVERVIEW_CHANGED, this.overviewListener);
  }

  /** 加载概览（对齐 Flutter PhotoAlbumOverviewController.refreshOverview，limit=6） */
  private async loadOverview(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await this.albumApi.getAlbumOverview(6);
      if (res.success && res.data !== undefined) {
        this.albums = res.data.albums.items;
        this.albumTotal = res.data.albums.total;
        this.smartAlbums = res.data.smartAlbums.items;
        this.smartAlbumTotal = res.data.smartAlbums.total;
        this.collections = res.data.collections.items;
        this.collectionTotal = res.data.collections.total;
      }
    } finally {
      this.isLoading = false;
    }
  }

  private allEmpty(): boolean {
    return this.albums.length === 0 && this.smartAlbums.length === 0 && this.collections.length === 0;
  }

  private coverFullpathOf(previews: PhotoAlbumPreviewItem[]): string {
    return previews.length > 0 ? previews[0].fullpath : '';
  }

  private collectionPathCount(collection: PhotoCollectionItem): number {
    let count = 0;
    for (const p of collection.pathList) {
      if (p.trim().length > 0) {
        count++;
      }
    }
    return count;
  }

  // ===== 打开时间线（对齐 Flutter AppPhotoAlbumTimelinePage，title: '${name} · ${typeLabel}'） =====

  private openTimeline(title: string, albumId: number, collectionId: number, smartAlbumId: number): void {
    const p = new PhotoTimelinePageParam();
    p.title = title;
    p.listType = 'timeline';
    p.albumId = albumId;
    p.collectionId = collectionId;
    p.smartAlbumId = smartAlbumId;
    NavUtil.push(AppRouter.PHOTO_TIMELINE, p);
  }

  private openAlbumTimeline(album: PhotoAlbumItem): void {
    this.openTimeline(`${album.name} · ${L10n.t('photo_menu_album_normal', '自建相册')}`, album.id, 0, 0);
  }

  private openSmartAlbumTimeline(album: PhotoSmartAlbumItem): void {
    this.openTimeline(`${album.name} · ${L10n.t('photo_menu_album_smart', '智能相册')}`, 0, 0, album.id);
  }

  private openCollectionTimeline(collection: PhotoCollectionItem): void {
    this.openTimeline(`${collection.name} · ${L10n.t('photo_menu_album_collection', '照片合集')}`, 0, collection.id, 0);
  }

  // ===== 操作弹层 =====

  private showAlbumActions(album: PhotoAlbumItem): void {
    const p = new AlbumActionSheetParams();
    p.onOpen = (): void => {
      this.openAlbumTimeline(album);
    };
    p.onEdit = (): void => {
      this.editAlbum = album;
    };
    p.onDelete = (): void => {
      void this.confirmDeleteAlbum(album);
    };
    SheetUtil.present(p, wrapBuilder(AlbumActionSheetContent));
  }

  private showSmartAlbumActions(album: PhotoSmartAlbumItem): void {
    const p = new AlbumActionSheetParams();
    p.onOpen = (): void => {
      this.openSmartAlbumTimeline(album);
    };
    p.onEdit = (): void => {
      // 智能相册编辑流程由列表页承载（后续任务），先打开列表页
      NavUtil.push(AppRouter.PHOTO_SMART_ALBUM_LIST);
    };
    p.onDelete = (): void => {
      void this.confirmDeleteSmartAlbum(album);
    };
    SheetUtil.present(p, wrapBuilder(AlbumActionSheetContent));
  }

  private showCollectionActions(collection: PhotoCollectionItem): void {
    const p = new AlbumActionSheetParams();
    p.onOpen = (): void => {
      this.openCollectionTimeline(collection);
    };
    p.onEdit = (): void => {
      // 合集编辑流程由列表页承载（后续任务），先打开列表页
      NavUtil.push(AppRouter.PHOTO_COLLECTION_LIST);
    };
    p.onDelete = (): void => {
      void this.confirmDeleteCollection(collection);
    };
    SheetUtil.present(p, wrapBuilder(AlbumActionSheetContent));
  }

  /** 删除相册（对齐 Flutter _showAlbumActions delete 分支） */
  private async confirmDeleteAlbum(album: PhotoAlbumItem): Promise<void> {
    const content = L10n.t('photo_album_delete_confirm', '确定删除相册「@name」？', L10n.paramsOf('name', album.name));
    const ok = await DialogUtil.showConfirmDialog(L10n.tip, content);
    if (ok !== true) {
      return;
    }
    const res = await this.albumApi.deleteAlbum(album.id);
    if (!res.success) {
      if (res.message !== undefined && res.message.length > 0) {
        await DialogUtil.showInfoDialog(L10n.tip, res.message);
      }
      return;
    }
    void this.loadOverview();
  }

  /** 删除智能相册 */
  private async confirmDeleteSmartAlbum(album: PhotoSmartAlbumItem): Promise<void> {
    const content = `${L10n.t('delete', '删除')} "${album.name}" ?`;
    const ok = await DialogUtil.showConfirmDialog(L10n.tip, content);
    if (ok !== true) {
      return;
    }
    const res = await this.smartAlbumApi.deleteSmartAlbum(album.id);
    if (!res.success) {
      if (res.message !== undefined && res.message.length > 0) {
        await DialogUtil.showInfoDialog(L10n.tip, res.message);
      }
      return;
    }
    void this.loadOverview();
  }

  /** 删除照片合集 */
  private async confirmDeleteCollection(collection: PhotoCollectionItem): Promise<void> {
    const content = `${L10n.t('delete', '删除')} "${collection.name}" ?`;
    const ok = await DialogUtil.showConfirmDialog(L10n.tip, content);
    if (ok !== true) {
      return;
    }
    const res = await this.collectionApi.deleteCollection(collection.id);
    if (!res.success) {
      if (res.message !== undefined && res.message.length > 0) {
        await DialogUtil.showInfoDialog(L10n.tip, res.message);
      }
      return;
    }
    void this.loadOverview();
  }

  // ===== UI =====

  build() {
    Stack() {
      Refresh({ refreshing: this.refreshing }) {
        if (this.isLoading && this.allEmpty()) {
          // 首次加载且全空时显示加载圈（对齐 Flutter isLoading && isEmpty）
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(AppTheme.current().primary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              this.SectionHeader(L10n.t('photo_menu_album_normal', '自建相册'), this.albumTotal, (): void => {
                NavUtil.push(AppRouter.PHOTO_ALBUM_LIST);
              })
              this.AlbumSection()
              Blank().height(10)
              this.SectionHeader(L10n.t('photo_menu_album_smart', '智能相册'), this.smartAlbumTotal, (): void => {
                NavUtil.push(AppRouter.PHOTO_SMART_ALBUM_LIST);
              })
              this.SmartAlbumSection()
              Blank().height(10)
              this.SectionHeader(L10n.t('photo_menu_album_collection', '照片合集'), this.collectionTotal, (): void => {
                NavUtil.push(AppRouter.PHOTO_COLLECTION_LIST);
              })
              this.CollectionSection()
              Blank().height(6)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 12, top: 10, bottom: 16 })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
      }
      .onRefreshing(() => {
        this.refreshing = true;
        this.loadOverview().finally(() => {
          this.refreshing = false;
        });
      })
      .width('100%')
      .height('100%')

      // 新建相册弹窗
      if (this.showCreateDialog) {
        PhotoAlbumEditDialog({
          album: undefined,
          onDismiss: (): void => {
            this.showCreateDialog = false;
          },
          onSaved: (): void => {
            void this.loadOverview();
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
            void this.loadOverview();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 分区标题行（对齐 Flutter _Section：标题 + 总数 + chevron_right） */
  @Builder
  SectionHeader(title: string, total: number, onTap: () => void) {
    Row({ space: 2 }) {
      Text(total > 0 ? `${title} (${total})` : title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(20)
        .fontColor([AppTheme.current().hint])
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .borderRadius(8)
    .onClick(() => {
      onTap();
    })
  }

  /** 横向卡片列表空态（对齐 Flutter _HorizontalAlbumList 空分支） */
  @Builder
  EmptyHorizontal() {
    Row() {
      Text(L10n.t('no_data', '暂无数据'))
        .fontSize(14)
        .fontColor(AppTheme.current().subText)
    }
    .width('100%')
    .height(148)
    .justifyContent(FlexAlign.Center)
  }

  /** 自建相册横向卡片（对齐 Flutter _AlbumCard 用法） */
  @Builder
  AlbumSection() {
    if (this.albums.length === 0) {
      this.EmptyHorizontal()
    } else {
      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.albums.slice(0, 6), (album: PhotoAlbumItem) => {
            PhotoAlbumCardView({
              fullpath: this.coverFullpathOf(album.previews),
              name: album.name,
              icon: album.isPublic ? $r('sys.symbol.eye') : $r('sys.symbol.lock'),
              onCardTap: (): void => {
                this.openAlbumTimeline(album);
              },
              onMoreTap: (): void => {
                this.showAlbumActions(album);
              }
            })
              .width(160)
              .height(148)
          }, (album: PhotoAlbumItem) => `album_${album.id}_${album.name}`)
        }
        .padding({ top: 6, bottom: 6, left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      // 内容不足一屏时靠左排列（Scroll 默认居中）
      .align(Alignment.Start)
      .width('100%')
      .height(160)
    }
  }

  /** 智能相册横向卡片（对齐 Flutter _SmartAlbumCard 用法） */
  @Builder
  SmartAlbumSection() {
    if (this.smartAlbums.length === 0) {
      this.EmptyHorizontal()
    } else {
      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.smartAlbums.slice(0, 6), (album: PhotoSmartAlbumItem) => {
            PhotoAlbumCardView({
              fullpath: this.coverFullpathOf(album.previews),
              name: album.name,
              icon: album.type === 'smart_date' ? $r('sys.symbol.calendar') : $r('sys.symbol.slider_horizontal_2'),
              showInfo: true,
              onCardTap: (): void => {
                this.openSmartAlbumTimeline(album);
              },
              onInfoTap: (): void => {
                this.showSmartAlbumInfo(album);
              },
              onMoreTap: (): void => {
                this.showSmartAlbumActions(album);
              }
            })
              .width(160)
              .height(148)
          }, (album: PhotoSmartAlbumItem) => `smart_${album.id}_${album.name}`)
        }
        .padding({ top: 6, bottom: 6, left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      // 内容不足一屏时靠左排列（Scroll 默认居中）
      .align(Alignment.Start)
      .width('100%')
      .height(160)
    }
  }

  /** 照片合集横向卡片（对齐 Flutter _CollectionCard 用法） */
  @Builder
  CollectionSection() {
    if (this.collections.length === 0) {
      this.EmptyHorizontal()
    } else {
      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.collections.slice(0, 6), (collection: PhotoCollectionItem) => {
            PhotoAlbumCardView({
              fullpath: this.coverFullpathOf(collection.previews),
              name: collection.name,
              icon: $r('sys.symbol.folder'),
              trailingText: `${this.collectionPathCount(collection)}`,
              showInfo: true,
              onCardTap: (): void => {
                this.openCollectionTimeline(collection);
              },
              onInfoTap: (): void => {
                this.showCollectionInfo(collection);
              },
              onMoreTap: (): void => {
                this.showCollectionActions(collection);
              }
            })
              .width(160)
              .height(148)
          }, (collection: PhotoCollectionItem) => `collection_${collection.id}_${collection.name}`)
        }
        .padding({ top: 6, bottom: 6, left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      // 内容不足一屏时靠左排列（Scroll 默认居中）
      .align(Alignment.Start)
      .width('100%')
      .height(160)
    }
  }

  /** 智能相册信息弹窗（对齐 Flutter onInfo → buildAlbumTooltipText） */
  private showSmartAlbumInfo(album: PhotoSmartAlbumItem): void {
    const tooltip = SmartAlbumTooltip.build(album);
    DialogUtil.showInfoDialog(album.name,
      tooltip.trim().length > 0 ? tooltip : L10n.t('no_data', '暂无数据'));
  }

  /** 合集信息弹窗（对齐 Flutter onInfo → pathList 逐行展示） */
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
}
