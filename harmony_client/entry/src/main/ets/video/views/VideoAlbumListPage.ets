import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil, DialogResult } from '../../common/DialogUtil';
import { PageScaffold } from '../../common/PageScaffold';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { EmptyState } from '../../common/components/EmptyState';
import { PickOption, showOptionPickSheet } from '../../common/components/OptionPickSheet';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { VideoAlbumItem } from '../models/VideoModels';
import { VideoAlbumListPageParam, VideoAlbumVideosPageParam } from '../router/VideoRoutes';
import { VideoAlbumListController } from '../controllers/VideoAlbumListControllers';
import { VideoAlbumCard } from '../components/VideoAlbumCard';

/**
 * 自建相册列表页（对齐 Flutter AppVideoAlbumListPage 移动端版式）：
 * 顶栏（搜索/排序/创建）+ 纵向相册卡片列表（宽高比 1.7）+ 底部加载更多；
 * 进入时支持自动弹出指定相册的编辑弹窗（initialEditId）。
 */

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
      icon: $r('sys.symbol.plus_square_on_square'),
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
  }
  .width('100%')
  .padding({ bottom: 24 })
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

@ComponentV2
export struct VideoAlbumListPage {
  @Param param: VideoAlbumListPageParam = new VideoAlbumListPageParam();
  @Param popPage: () => void = (): void => {
  };
  ctrl: VideoAlbumListController = new VideoAlbumListController();
  @Local itemHeight: number = 200;
  @Local listWidth: number = 0;
  private didAutoEdit: boolean = false;
  private didAutoOpenCreate: boolean = false;

  aboutToAppear(): void {
    this.ctrl.init();
    if (this.param.autoOpenCreate && !this.didAutoOpenCreate) {
      this.didAutoOpenCreate = true;
      this.showCreateDialog();
    }
    this.tryAutoEdit(0);
  }

  /** 轮询等待列表加载后自动打开编辑弹窗（最多 10 次，对齐 Flutter addPostFrameCallback） */
  private tryAutoEdit(retries: number): void {
    if (this.didAutoEdit || this.param.initialEditId <= 0) {
      return;
    }
    for (const album of this.ctrl.items) {
      if (album.id === this.param.initialEditId) {
        this.didAutoEdit = true;
        this.showEditDialog(album);
        return;
      }
    }
    if (retries < 10) {
      setTimeout((): void => {
        this.tryAutoEdit(retries + 1);
      }, 300);
    }
  }

  /** 依据列表宽度换算卡片高度（宽高比 1.7，对齐 Flutter AspectRatio） */
  private updateItemHeight(): void {
    if (this.listWidth > 0) {
      this.itemHeight = (this.listWidth - 32) / 1.7;
    }
  }

  private openAlbumVideos(album: VideoAlbumItem): void {
    const p = new VideoAlbumVideosPageParam();
    p.albumId = album.id;
    p.title = album.name;
    NavUtil.push(AppRouter.VIDEO_ALBUM_VIDEOS, p);
  }

  private openSearch(): void {
    DialogUtil.showInputDialog(L10n.t('search', '搜索'), '', this.ctrl.keyword)
      .then((r: DialogResult | undefined) => {
        if (typeof r === 'string') {
          this.ctrl.onSearchChanged(r.trim());
        }
      });
  }

  private showSortSheet(): void {
    const options: PickOption[] = [
      new PickOption('name_asc', L10n.t('name_asc', '名称升序')),
      new PickOption('name_desc', L10n.t('name_desc', '名称降序')),
      new PickOption('create_time_asc', L10n.t('create_time_asc', '创建时间升序')),
      new PickOption('create_time_desc', L10n.t('create_time_desc', '创建时间降序'))
    ];
    const selected = `${this.ctrl.sortField}_${this.ctrl.sortOrder}`;
    showOptionPickSheet(L10n.t('sort', '排序'), options, selected, (key: string): void => {
      const idx = key.lastIndexOf('_');
      if (idx <= 0) {
        return;
      }
      this.ctrl.setSort(key.substring(0, idx), key.substring(idx + 1));
    });
  }

  private showCreateDialog(): void {
    DialogUtil.showInputDialog(L10n.t('create', '创建'), '', '',
      L10n.t('ok', '确定'), L10n.t('cancel', '取消'), (value: string): string | undefined => {
        return value.trim().length === 0 ? L10n.t('input_please', '请输入') : undefined;
      }).then((r: DialogResult | undefined): void => {
      if (typeof r !== 'string') {
        return;
      }
      void this.ctrl.createAlbum(r.trim(), false);
    });
  }

  private showEditDialog(album: VideoAlbumItem): void {
    DialogUtil.showInputDialog(L10n.t('edit', '编辑'), '', album.name,
      L10n.t('ok', '确定'), L10n.t('cancel', '取消'), (value: string): string | undefined => {
        return value.trim().length === 0 ? L10n.t('input_please', '请输入') : undefined;
      }).then((r: DialogResult | undefined): void => {
      if (typeof r !== 'string') {
        return;
      }
      void this.ctrl.updateAlbum(album.id, r.trim(), album.isPublic);
    });
  }

  private confirmDelete(album: VideoAlbumItem): void {
    DialogUtil.showConfirmDialog(L10n.t('tip', '提示'),
      `${L10n.t('delete', '删除')} "${album.name}" ?`, (): void => {
        void this.ctrl.deleteAlbum(album.id);
      });
  }

  private showActions(album: VideoAlbumItem): void {
    const p = new AlbumActionSheetParams();
    p.onOpen = (): void => {
      this.openAlbumVideos(album);
    };
    p.onEdit = (): void => {
      this.showEditDialog(album);
    };
    p.onDelete = (): void => {
      this.confirmDelete(album);
    };
    SheetUtil.present(p, wrapBuilder(AlbumActionSheetContent));
  }

  /** 底部加载区：加载中 / 没有更多 / 加载更多按钮 */
  @Builder
  FooterView() {
    Row() {
      if (this.ctrl.isLoading) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(AppTheme.current().subText)
      } else if (!this.ctrl.hasMore) {
        Text(L10n.t('no_more', '没有更多了'))
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
      } else {
        Button(L10n.t('load_more', '加载更多'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.25) })
          .onClick(() => {
            void this.ctrl.loadMore();
          })
      }
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .padding({ top: 10, bottom: 20 })
  }

  build() {
    PageScaffold({
      title: L10n.t('video_custom_album_title', '自建相册'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.ListContent()
      }
    })
  }

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
          this.showSortSheet();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.plus'),
        onTap: (): void => {
          this.showCreateDialog();
        }
      })
    }
  }

  @Builder
  ListContent() {
    Column() {
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
        EmptyState({ message: L10n.t('no_data', '暂无数据') })
      } else {
        List({ space: 14 }) {
          ForEach(this.ctrl.items, (album: VideoAlbumItem) => {
            ListItem() {
              Column() {
                VideoAlbumCard({
                  title: album.name,
                  titleIcon: $r('sys.symbol.video'),
                  previews: album.previews,
                  onTap: (): void => {
                    this.openAlbumVideos(album);
                  },
                  onMore: (): void => {
                    this.showActions(album);
                  }
                })
              }
              .width('100%')
              .height(this.itemHeight)
            }
            .padding({ left: 16, right: 16 })
          }, (album: VideoAlbumItem): string => `${album.id}`)
          ListItem() {
            this.FooterView()
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => {
          void this.ctrl.loadMore();
        })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, n: Area): void => {
      this.listWidth = Number(n.width);
      this.updateItemHeight();
    })
    .backgroundColor(AppTheme.current().cardBg)
  }
}
