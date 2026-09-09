import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { EmptyState } from '../../../common/components/EmptyState';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../../common/SheetUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { APIClient } from '../../../core/network/APIClient';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { MusicSubListController } from '../controllers/MusicSubListController';
import { MusicListItem, browseMusicFolder } from '../models/MusicModels';
import { MusicPlayService } from '../service/MusicPlayService';
import { MusicCoverThumb } from '../components/MusicCoverThumb';
import { MusicMultiSelectBar } from '../components/MusicMultiSelectBar';
import { FileBrowserParam } from '../../../files/views/FileBrowserPage';
import { pickMusicPlayListId } from '../components/MusicPlayListSelectSheet';
import { MusicSubListPageParam } from '../router/MusicRoutes';
import { MusicSubListPayload } from '../controllers/MusicSubListController';

class MusicSubRowSheetParams extends SheetParamsBase {
  ctrl: MusicSubListController | undefined = undefined;
  item: MusicListItem = new MusicListItem();
}

/**
 * 音乐子列表主体（对齐 Flutter MusicSubListOverlayBody + _MobileDataRow）：
 * 固定 62 高数据行（封面缩略图 + 标题/副标题 + 更多操作），当前播放高亮，
 * 多选模式切换为复选框行；底部多选操作栏（inset 由调用方决定）。
 */
@ComponentV2
export struct MusicSubListBody {
  @Param ctrl: MusicSubListController = new MusicSubListController(new MusicSubListPayload());
  /** 多选操作栏底部 inset（pushed 页面为悬浮条预留高度） */
  @Param multiBarBottomInset: number = 0;
  /** 列表底部 inset（悬浮播放条显示时给最后几行留出空间） */
  @Param listBottomInset: number = 0;
  /** series 行点击（打开子列表） */
  @Param onOpenSeries: (item: MusicListItem) => void = (_item: MusicListItem): void => {
  };

  private svc: MusicPlayService = MusicPlayService.getInstance();

  private isCurrentRow(item: MusicListItem): boolean {
    const cur = this.svc.currentItem;
    if (cur === undefined) {
      return false;
    }
    const a = cur.resolvePlayablePath().trim();
    const b = item.resolvePlayablePath().trim();
    return a.length > 0 && a === b;
  }

  // ===== 文件浏览（对齐 browseFolderPathMusic） =====

  private openInFileBrowser(item: MusicListItem): void {
    const target = browseMusicFolder(item.resolvePlayablePath());
    if (target.length === 0) {
      return;
    }
    const p = new FileBrowserParam();
    p.initialPath = target;
    NavUtil.push(AppRouter.FILES, p);
  }

  // ===== 删除确认（对齐 MusicListController 三键确认） =====

  private async confirmDelete(paths: string[]): Promise<boolean | undefined> {
    if (paths.length === 0) {
      return undefined;
    }
    const count = paths.length;
    const content = count <= 5
      ? [L10n.t('book_delete_confirm_list'), ...paths.map((p: string): string =>
        `${L10n.t('book_delete_confirm_path_line')}${p}`)].join('\n')
      : `${L10n.t('book_delete_confirm_count')}${count}`;
    const isShellSupported = APIClient.getInstance().state.shellSupported === true;
    if (!isShellSupported) {
      const ok = await DialogUtil.showConfirmDialog(L10n.t('need_confirm'), content);
      return ok === true ? false : undefined;
    }
    const r = await DialogUtil.showConfirmThreeButtonsDialog(L10n.t('need_confirm'), content,
      undefined, undefined, L10n.cancel, L10n.t('put_in_recycle_bin'), L10n.t('delete_permanently'));
    if (r === undefined) {
      return undefined;
    }
    return r === 0;
  }

  private async deleteRow(item: MusicListItem): Promise<void> {
    const recycle = await this.confirmDelete([item.resolvePlayablePath()]);
    if (recycle === undefined) {
      return;
    }
    await this.ctrl.deleteItem(item, recycle);
  }

  private async deleteRows(): Promise<void> {
    const selected = this.ctrl.items.filter((e: MusicListItem): boolean => this.ctrl.selectedItems.has(e.id));
    const paths = selected.map((e: MusicListItem): string => e.resolvePlayablePath())
      .filter((e: string): boolean => e.length > 0).sort();
    const recycle = await this.confirmDelete(paths);
    if (recycle === undefined) {
      return;
    }
    await this.ctrl.deleteSelected(recycle);
  }

  private async addRowToPlayList(item: MusicListItem): Promise<void> {
    const listId = await pickMusicPlayListId();
    if (listId > 0) {
      await this.ctrl.addToPlayListItem(item, listId);
    }
  }

  private async addRowsToPlayList(): Promise<void> {
    const listId = await pickMusicPlayListId();
    if (listId > 0) {
      await this.ctrl.addToPlayListSelected(listId);
    }
  }

  // ===== 行操作弹层（对齐 _MobileDataRow action sheet） =====

  private showRowSheet(item: MusicListItem): void {
    const params = new MusicSubRowSheetParams();
    params.ctrl = this.ctrl;
    params.item = item;
    SheetUtil.present<MusicSubRowSheetParams>(params, wrapBuilder(musicSubRowSheetBuilder));
  }

  build() {
    if (this.ctrl.loading) {
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
        EmptyState({ message: L10n.t('no_data') })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Stack() {
        List() {
          ForEach(this.ctrl.items, (item: MusicListItem, index: number) => {
            ListItem() {
              this.SubRow(item, index)
            }
          }, (item: MusicListItem) => `${item.id}`)

          ListItem() {
            this.ListFooter()
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .padding({ bottom: this.listBottomInset })
        .onReachEnd(() => {
          this.ctrl.loadMore(true);
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
                this.deleteRows();
              },
              onAddToPlayList: (): void => {
                this.addRowsToPlayList();
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
          .margin({ bottom: this.multiBarBottomInset })
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 数据行（对齐 _MobileDataRow） */
  @Builder
  SubRow(item: MusicListItem, index: number) {
    Row({ space: 12 }) {
      if (this.ctrl.isMultiSelectMode) {
        if (this.ctrl.selectedItems.has(item.id)) {
          SymbolGlyph($r('sys.symbol.checkmark_square_fill'))
            .fontSize(20)
            .fontColor([AppTheme.current().primary])
        } else {
          SymbolGlyph($r('sys.symbol.checkmark_square'))
            .fontSize(20)
            .fontColor([AppTheme.current().hint])
        }
      }

      Stack() {
        MusicCoverThumb({
          filePath: item.coverFilePath(),
          hasInnerCover: item.hasInnerCover,
          genre: item.genre,
          seedId: item.id,
          boxSize: 46,
          radius: 8
        })
        if (this.isCurrentRow(item) && this.svc.isPlaying && !this.ctrl.isMultiSelectMode) {
          Column() {
            SymbolGlyph($r('sys.symbol.pause_fill'))
              .fontSize(16)
              .fontColor(['#FFFFFF'])
          }
          .width(46)
          .height(46)
          .borderRadius(8)
          .backgroundColor('rgba(0,0,0,0.35)')
          .justifyContent(FlexAlign.Center)
        }
      }

      Column() {
        Text(item.displayTitle)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isCurrentRow(item) ? AppTheme.current().primary : AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (item.displaySubtitle.trim().length > 0) {
          Text(item.displaySubtitle)
            .fontSize(12)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.65))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.ctrl.isMultiSelectMode) {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(18)
          .fontColor([AppTheme.current().subText])
          .onClick(() => {
            this.showRowSheet(item);
          })
      }
    }
    .width('100%')
    .height(62)
    .padding({ left: 15, right: 15 })
    .backgroundColor(this.ctrl.isMultiSelectMode && this.ctrl.selectedItems.has(item.id)
      ? AppTheme.withAlpha(AppTheme.current().primary, 0.08)
      : Color.Transparent)
    .onClick(() => {
      if (this.ctrl.isMultiSelectMode) {
        this.ctrl.toggleSelection(item.id);
        return;
      }
      this.openRow(item, index);
    })
  }

  private openRow(item: MusicListItem, index: number): void {
    if (item.isSeries) {
      this.onOpenSeries(item);
      return;
    }
    if (this.isCurrentRow(item)) {
      if (this.svc.isPlaying) {
        this.svc.pause();
      } else {
        this.svc.play();
      }
      return;
    }
    this.ctrl.playAt(index);
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
            this.ctrl.loadMore(false);
          })
      } else {
        Column().height(20)
      }
    }
    .width('100%')
  }
}

// ===== 行操作弹层 =====

@Builder
function musicSubRowSheetBuilder(params: MusicSubRowSheetParams) {
  Column() {
    SheetHandle()
    if (params.ctrl !== undefined) {
      MusicSubRowSheet({ params: params })
    }
  }
  .width('100%')
  .backgroundColor(SheetUtil.panelBg())
  .borderRadius({ topLeft: 16, topRight: 16 })
}

/** 行操作弹层内容（对齐 AppItemActionSheet：头部 + 动作列表） */
@ComponentV2
struct MusicSubRowSheet {
  @Param params: MusicSubRowSheetParams = new MusicSubRowSheetParams();

  private body(): MusicSubListBody | undefined {
    return undefined;
  }

  build() {
    Column() {
      SheetHandle()
      Row({ space: 12 }) {
        MusicCoverThumb({
          filePath: this.params.item.coverFilePath(),
          hasInnerCover: this.params.item.hasInnerCover,
          genre: this.params.item.genre,
          seedId: this.params.item.id,
          boxSize: 52,
          radius: 10
        })
        Column() {
          Text(this.params.item.displayTitle)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.params.item.displaySubtitle.trim().length > 0) {
            Text(this.params.item.displaySubtitle)
              .fontSize(12)
              .fontColor(AppTheme.current().subText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 3 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 10 })

      this.SheetAction($r('sys.symbol.doc_plaintext'), L10n.t('open'), false, (): void => {
        this.params.close();
        const ctrl = this.params.ctrl;
        const item = this.params.item;
        if (ctrl === undefined) {
          return;
        }
        if (item.isSeries) {
          ctrlOpenSeries(ctrl, item);
          return;
        }
        const svc = MusicPlayService.getInstance();
        const cur = svc.currentItem;
        const isCur = cur !== undefined &&
          cur.resolvePlayablePath().trim() === item.resolvePlayablePath().trim() &&
          item.resolvePlayablePath().trim().length > 0;
        if (isCur) {
          if (svc.isPlaying) {
            svc.pause();
          } else {
            svc.play();
          }
          return;
        }
        ctrl.playAt(this.indexOfItem(item));
      })
      this.SheetAction($r('sys.symbol.folder'), L10n.t('file_browse'), false, (): void => {
        this.params.close();
        const ctrl = this.params.ctrl;
        if (ctrl === undefined) {
          return;
        }
        const target = browseMusicFolder(this.params.item.resolvePlayablePath());
        if (target.length === 0) {
          return;
        }
        const p = new FileBrowserParam();
        p.initialPath = target;
        NavUtil.push(AppRouter.FILES, p);
      })
      Divider().color(AppTheme.current().divider).margin({ left: 16 })
      this.SheetAction(this.params.item.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
        this.params.item.isFavorite ? L10n.t('unfavorite') : L10n.t('favorites'), false, (): void => {
          const ctrl = this.params.ctrl;
          this.params.close();
          if (ctrl !== undefined) {
            ctrl.toggleFavorite(this.params.item);
          }
        })
      this.SheetAction($r('sys.symbol.download'), L10n.t('download'), false, (): void => {
        this.params.close();
        const ctrl = this.params.ctrl;
        if (ctrl !== undefined) {
          ctrl.downloadItem(this.params.item);
        }
      })
      Divider().color(AppTheme.current().divider).margin({ left: 16 })
      this.SheetAction($r('sys.symbol.music_note_list'), L10n.t('add_to_play_list'), false, (): void => {
        const ctrl = this.params.ctrl;
        this.params.close();
        if (ctrl !== undefined) {
          rowAddToPlayList(ctrl, this.params.item);
        }
      })
      if (this.params.ctrl !== undefined && this.params.ctrl.isInPlayList) {
        this.SheetAction($r('sys.symbol.xmark'), L10n.t('remove_from_play_list'), false, (): void => {
          const ctrl = this.params.ctrl;
          this.params.close();
          if (ctrl !== undefined) {
            ctrl.removeFromPlayListItem(this.params.item);
          }
        })
      }
      Divider().color(AppTheme.current().divider).margin({ left: 16 })
      this.SheetAction($r('sys.symbol.trash_fill'), L10n.t('delete'), true, (): void => {
        this.params.close();
        rowDelete(this.params.ctrl, this.params.item);
      })
    }
    .width('100%')
    .padding({ bottom: 24 })
  }

  private indexOfItem(item: MusicListItem): number {
    const ctrl = this.params.ctrl;
    if (ctrl === undefined) {
      return 0;
    }
    return ctrl.items.findIndex((e: MusicListItem): boolean => e.id === item.id);
  }

  @Builder
  private SheetAction(icon: Resource, label: string, danger: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([danger ? '#E53935' : AppTheme.current().onSurface])
      Text(label)
        .fontSize(15)
        .fontColor(danger ? '#E53935' : AppTheme.current().onSurface)
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      onTap();
    })
  }
}

/** series 打开：push 子列表页（seriesIndexId） */
function ctrlOpenSeries(ctrl: MusicSubListController, item: MusicListItem): void {
  const seriesIndexId = item.id;
  if (seriesIndexId <= 0) {
    return;
  }
  const p = new MusicSubListPageParam();
  p.keyType = 'series';
  p.name = item.displayTitle;
  p.seriesIndexId = seriesIndexId;
  NavUtil.push(AppRouter.MUSIC_SUB_LIST, p);
}

async function rowAddToPlayList(ctrl: MusicSubListController, item: MusicListItem): Promise<void> {
  const listId = await pickMusicPlayListId();
  if (listId > 0) {
    await ctrl.addToPlayListItem(item, listId);
  }
}

async function rowDelete(ctrl: MusicSubListController | undefined, item: MusicListItem): Promise<void> {
  if (ctrl === undefined) {
    return;
  }
  const recycle = await confirmMusicDelete([item.resolvePlayablePath()]);
  if (recycle === undefined) {
    return;
  }
  await ctrl.deleteItem(item, recycle);
}

/** 删除三键确认（回收站/永久），取消 undefined */
export async function confirmMusicDelete(paths: string[]): Promise<boolean | undefined> {
  if (paths.length === 0) {
    return undefined;
  }
  const count = paths.length;
  const content = count <= 5
    ? [L10n.t('book_delete_confirm_list'), ...paths.map((p: string): string =>
      `${L10n.t('book_delete_confirm_path_line')}${p}`)].join('\n')
    : `${L10n.t('book_delete_confirm_count')}${count}`;
  const isShellSupported = APIClient.getInstance().state.shellSupported === true;
  if (!isShellSupported) {
    const ok = await DialogUtil.showConfirmDialog(L10n.t('need_confirm'), content);
    return ok === true ? false : undefined;
  }
  const r = await DialogUtil.showConfirmThreeButtonsDialog(L10n.t('need_confirm'), content,
    undefined, undefined, L10n.cancel, L10n.t('put_in_recycle_bin'), L10n.t('delete_permanently'));
  if (r === undefined) {
    return undefined;
  }
  return r === 0;
}
