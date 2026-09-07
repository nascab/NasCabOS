import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil } from '../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { ToastUtil } from '../../common/ToastUtil';
import { AppEventBus } from '../../common/AppEventBus';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { FileApiService } from '../../files/service/FileApiService';
import { VideoHomeItemBean } from '../models/VideoModels';
import { VideoAlbumApiService, VideoScrapeApiService, VideoSourceApiService } from '../service/VideoApiServices';
import { VideoFavoriteApiService } from '../service/VideoApiServices';
import {
  VideoItemSyncService, buildVideoHomeMeta, resolveVideoBrowsePath,
  resolveVideoDeletePath, resolveVideoDownloadPath, videoMediaTypeText
} from '../utils/VideoItemUtils';
import { VideoDetailPageParam, VideoListPageParam } from '../router/VideoRoutes';
import { presentAlbumSelectSheet } from './VideoAlbumSelectSheet';

/**
 * 视频条目共享操作（对齐 Flutter AppVideoItemPoster 的操作菜单与
 * VideoItemContextMenuRegion 桌面右键菜单 → 鸿蒙端统一为操作弹层）。
 */

function openDetailPage(item: VideoHomeItemBean): void {
  const param = new VideoDetailPageParam();
  param.indexId = item.id;
  NavUtil.push(AppRouter.VIDEO_DETAIL, param);
}

function openFileBrowse(item: VideoHomeItemBean): void {
  const path = resolveVideoBrowsePath(item);
  if (path.length === 0) {
    return;
  }
  const param = new VideoListPageParam();
  void param;
  NavUtil.push(AppRouter.FILES, { 'initialPath': path } as Record<string, string>);
}

function downloadItem(item: VideoHomeItemBean): void {
  // 下载依赖传输/下载模块（未迁移），对齐 files 模块处理方式
  void resolveVideoDownloadPath(item);
  ToastUtil.show(L10n.featureComingSoon);
}

export class VideoItemActions {
  /** 打开详情页 */
  static openDetail(item: VideoHomeItemBean): void {
    openDetailPage(item);
  }

  /** 切换收藏（对齐 _toggleFavorite） */
  static async toggleFavorite(item: VideoHomeItemBean, onDone?: (isFav: boolean) => void):
    Promise<void> {
    if (item.id <= 0) {
      return;
    }
    const next = !item.isFavorite;
    const api = new VideoFavoriteApiService();
    const ok = next ? await api.addFavorite(item.id) : await api.removeFavorite(item.id);
    if (!ok) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    if (onDone) {
      onDone(next);
    }
  }

  /** 自动刮削（对齐 _startAutoScrape） */
  static async startAutoScrape(item: VideoHomeItemBean): Promise<void> {
    if (item.id <= 0) {
      return;
    }
    const res = await new VideoScrapeApiService().startScrape(item.id, 0, 'auto');
    if (!res.success) {
      ToastUtil.show(L10n.t('video_scrape_start_failed', '启动刮削失败'));
      return;
    }
    const data = res.data ?? {};
    const started = data['started'] === true;
    const skipped = data['skipped'] === true;
    if (!started && skipped) {
      ToastUtil.show(L10n.t('video_scrape_skipped_existing_nfo', '已存在 NFO，已跳过刮削'));
      return;
    }
    if (!started) {
      ToastUtil.show(L10n.t('video_scrape_start_failed', '启动刮削失败'));
      return;
    }
    ToastUtil.show(L10n.t('video_scrape_started', '刮削已启动'));
  }

  /** 清理刮削信息（对齐 _cleanupScrapeInfo） */
  static async cleanupScrapeInfo(item: VideoHomeItemBean): Promise<void> {
    if (item.id <= 0) {
      return;
    }
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('video_scrape_cleanup_confirm', '确定清理该条目的刮削信息吗？'));
    if (ok !== true) {
      return;
    }
    const res = await new VideoScrapeApiService().cleanupScrape(item.id);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 扫描变更（对齐 _scanChanges） */
  static async scanChanges(item: VideoHomeItemBean): Promise<void> {
    if (item.id <= 0) {
      return;
    }
    const res = await new VideoSourceApiService().scanIndex(item.id);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 删除条目（带 刮削文件/回收站 选项，对齐 _deleteItem 自定义确认对话框） */
  static deleteItem(item: VideoHomeItemBean, shellSupported: boolean, onDeleted?: () => void): void {
    VideoItemActions.deletePath(resolveVideoDeletePath(item),
      ['movie', 'bdmv', 'video_ts'].includes(item.mediaType.toLowerCase().trim()),
      shellSupported, item.id, onDeleted);
  }

  /** 删除指定路径（详情页使用；支持 BDMV/VIDEO_TS 等特殊路径） */
  static deletePath(target: string, isMovie: boolean, shellSupported: boolean,
    indexId: number, onDeleted?: () => void): void {
    if (target.length === 0) {
      return;
    }
    const p = new VideoDeleteConfirmSheetParams();
    p.path = target;
    p.isMovie = isMovie;
    p.shellSupported = shellSupported;
    p.onConfirmed = (deleteScrapeFiles: boolean, recycle: boolean): void => {
      void VideoItemActions.deletePathRequest(target, isMovie, deleteScrapeFiles, recycle, indexId, onDeleted);
    };
    SheetUtil.present(p, wrapBuilder(VideoDeleteConfirmSheetContent));
  }

  private static async deletePathRequest(target: string, isMovie: boolean,
    deleteScrapeFiles: boolean, recycle: boolean, indexId: number, onDeleted?: () => void): Promise<void> {
    const res = await new FileApiService().deleteEntries([target], recycle, isMovie && deleteScrapeFiles);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    VideoItemSyncService.notifyDeleted(indexId);
    if (onDeleted) {
      onDeleted();
    }
  }

  /** 加入相册（弹出相册选择弹层，对齐 _addToAlbum + VideoAlbumSelectDialog） */
  static addToAlbum(item: VideoHomeItemBean, currentAlbumId: number,
    onRemovedFromCurrentAlbum?: () => void): void {
    if (item.id <= 0) {
      return;
    }
    presentAlbumSelectSheet(currentAlbumId, (albumId: number): void => {
      void VideoItemActions.addIndexes(albumId, item.id);
    });
  }

  private static async addIndexes(albumId: number, itemId: number): Promise<void> {
    const res = await new VideoAlbumApiService().addAlbumIndexes(albumId, [itemId]);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 从相册移除（对齐 _removeFromAlbum） */
  static async removeFromAlbum(item: VideoHomeItemBean, albumId: number,
    onRemoved?: () => void): Promise<void> {
    if (albumId <= 0 || item.id <= 0) {
      return;
    }
    const res = await new VideoAlbumApiService().removeAlbumIndexes(albumId, [item.id]);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    if (onRemoved) {
      onRemoved();
    }
  }

  /** 弹出条目操作弹层（对齐 _showActionMenu；桌面右键菜单项合并为移动端弹层） */
  static showActionSheet(item: VideoHomeItemBean, currentAlbumId: number = 0,
    opts?: VideoActionSheetOptions): void {
    const p = new VideoActionSheetParams();
    p.item = item;
    p.currentAlbumId = currentAlbumId;
    p.isAdmin = CurrentUserStore.getInstance().isAdmin;
    p.shellSupported = false;
    p.showOpen = opts?.showOpen ?? true;
    p.showFavorite = opts?.showFavorite ?? true;
    p.onDeleted = opts?.onDeleted;
    p.onFavoriteChanged = opts?.onFavoriteChanged;
    p.onRemovedFromCurrentAlbum = opts?.onRemovedFromCurrentAlbum;
    SheetUtil.present(p, wrapBuilder(VideoActionSheetContent));
  }
}

export class VideoActionSheetOptions {
  showOpen: boolean = true;
  showFavorite: boolean = true;
  onDeleted: (() => void) | undefined = undefined;
  onFavoriteChanged: ((isFav: boolean) => void) | undefined = undefined;
  onRemovedFromCurrentAlbum: (() => void) | undefined = undefined;
}

class VideoActionSheetParams extends SheetParamsBase {
  item: VideoHomeItemBean = new VideoHomeItemBean();
  currentAlbumId: number = 0;
  isAdmin: boolean = false;
  shellSupported: boolean = false;
  showOpen: boolean = true;
  showFavorite: boolean = true;
  onDeleted: (() => void) | undefined = undefined;
  onFavoriteChanged: ((isFav: boolean) => void) | undefined = undefined;
  onRemovedFromCurrentAlbum: (() => void) | undefined = undefined;
}

@Builder
function VideoActionSheetContent(p: VideoActionSheetParams) {
  Column() {
    SheetHandle()
    if (p.showOpen) {
      SheetListItem({
        icon: $r('sys.symbol.plus_square_on_square'),
        title: L10n.t('open', '打开'),
        onSelect: (): void => {
          p.close();
          openDetailPage(p.item);
        }
      })
    }
    SheetListItem({
      icon: $r('sys.symbol.folder'),
      title: L10n.t('file_browse', '浏览文件'),
      onSelect: (): void => {
        p.close();
        openFileBrowse(p.item);
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.square_and_arrow_down'),
      title: L10n.t('download', '下载'),
      onSelect: (): void => {
        p.close();
        downloadItem(p.item);
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.list_bullet'),
      title: L10n.t('video_add_to_album', '加入相册'),
      onSelect: (): void => {
        p.close();
        VideoItemActions.addToAlbum(p.item, p.currentAlbumId, p.onRemovedFromCurrentAlbum);
      }
    })
    if (p.currentAlbumId > 0) {
      SheetListItem({
        icon: $r('sys.symbol.minus_circle'),
        title: L10n.t('video_remove_from_album', '从相册移除'),
        onSelect: (): void => {
          p.close();
          void VideoItemActions.removeFromAlbum(p.item, p.currentAlbumId,
            p.onRemovedFromCurrentAlbum);
        }
      })
    }
    if (p.showFavorite) {
      SheetListItem({
        icon: p.item.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
        title: p.item.isFavorite ? L10n.t('unfavorite', '取消收藏') : L10n.t('folder_add_favorite', '收藏'),
        onSelect: (): void => {
          p.close();
          void VideoItemActions.toggleFavorite(p.item, (isFav: boolean): void => {
            if (p.onFavoriteChanged !== undefined) {
              p.onFavoriteChanged(isFav);
            }
          });
        }
      })
    }
    if (p.isAdmin) {
      Row()
        .width('100%')
        .height(1)
        .backgroundColor(AppTheme.current().divider)
        .margin({ top: 4, bottom: 4 })
      SheetListItem({
        icon: $r('sys.symbol.magnifyingglass'),
        title: L10n.t('video_search_media_info', '搜索媒体信息'),
        onSelect: (): void => {
          p.close();
          VideoSearchMediaHelper.open(p.item);
        }
      })
      SheetListItem({
        icon: $r('sys.symbol.wand_and_stars'),
        title: L10n.t('video_scrape_auto', '自动刮削'),
        onSelect: (): void => {
          p.close();
          void VideoItemActions.startAutoScrape(p.item);
        }
      })
      SheetListItem({
        icon: $r('sys.symbol.trash'),
        title: L10n.t('video_scrape_cleanup', '清理刮削信息'),
        onSelect: (): void => {
          p.close();
          void VideoItemActions.cleanupScrapeInfo(p.item);
        }
      })
      SheetListItem({
        icon: $r('sys.symbol.arrow_clockwise'),
        title: L10n.t('video_item_scan_changes', '扫描变更'),
        onSelect: (): void => {
          p.close();
          void VideoItemActions.scanChanges(p.item);
        }
      })
    }
    Row()
      .width('100%')
      .height(1)
      .backgroundColor(AppTheme.current().divider)
      .margin({ top: 4, bottom: 4 })
    SheetListItem({
      icon: $r('sys.symbol.trash'),
      title: L10n.t('delete', '删除'),
      titleColor: AppTheme.current().error,
      iconColor: AppTheme.current().error,
      onSelect: (): void => {
        p.close();
        VideoItemActions.deleteItem(p.item, p.shellSupported, (): void => {
          if (p.onDeleted !== undefined) {
            p.onDeleted();
          }
        });
      }
    })
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

/** 删除确认弹层参数（对齐 Flutter 删除对话框中的两个复选框） */
class VideoDeleteConfirmSheetParams extends SheetParamsBase {
  path: string = '';
  isMovie: boolean = false;
  shellSupported: boolean = false;
  onConfirmed: (deleteScrapeFiles: boolean, recycle: boolean) => void =
    (_d: boolean, _r: boolean): void => {
    };
}

@ComponentV2
struct VideoDeleteConfirmSheetInner {
  @Param p: VideoDeleteConfirmSheetParams = new VideoDeleteConfirmSheetParams();
  @Local deleteScrapeFiles: boolean = true;
  @Local recycle: boolean = false;

  aboutToAppear(): void {
    this.recycle = this.p.shellSupported;
  }

  @Builder
  CheckRow(label: string, checked: boolean, enabled: boolean, onTap: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph(checked ? $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'))
        .fontSize(20)
        .fontColor([enabled ? AppTheme.current().primary : AppTheme.current().hint])
      Text(label)
        .fontSize(14)
        .fontColor(enabled ? AppTheme.current().onSurface : AppTheme.current().hint)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('need_confirm', '需要确认'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
        .padding({ left: 20, right: 20, top: 8 })
      Text(L10n.t('video_delete_confirm_path', '确定删除 @path 吗？',
        L10n.paramsOf('path', this.p.path)))
        .fontSize(13)
        .fontColor(AppTheme.current().subText)
        .width('100%')
        .padding({ left: 20, right: 20, top: 8 })
      Scroll() {
        Column() {
          if (this.p.isMovie) {
            this.CheckRow(L10n.t('video_delete_with_scrape_files', '同时删除刮削文件'),
              this.deleteScrapeFiles, true, (): void => {
                this.deleteScrapeFiles = !this.deleteScrapeFiles;
              })
          }
          this.CheckRow(L10n.t('put_in_recycle_bin', '放入回收站'), this.recycle,
            this.p.shellSupported, (): void => {
              this.recycle = !this.recycle;
            })
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      Row({ space: 10 }) {
        Button(L10n.t('cancel', '取消'))
          .fontSize(15)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.p.close();
          })
        Button(L10n.t('ok', '确定'))
          .fontSize(15)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.p.close();
            this.p.onConfirmed(this.deleteScrapeFiles, this.recycle);
          })
      }
      .margin({ left: 20, right: 20, top: 8, bottom: 20 })
      .width('100%')
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

@Builder
function VideoDeleteConfirmSheetContent(p: VideoDeleteConfirmSheetParams) {
  VideoDeleteConfirmSheetInner({ p: p })
}

/** TMDB 搜索媒体信息弹层入口（VideoSearchMediaDialog 由设置页代理提供） */
export class VideoSearchMediaHelper {
  static opener: ((item: VideoHomeItemBean) => void) | undefined = undefined;

  static open(item: VideoHomeItemBean): void {
    if (VideoSearchMediaHelper.opener !== undefined) {
      VideoSearchMediaHelper.opener(item);
      return;
    }
    ToastUtil.show(L10n.featureComingSoon);
  }
}

void buildVideoHomeMeta;
void videoMediaTypeText;
void AppEventBus;
