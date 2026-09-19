import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { EmptyState } from '../../common/components/EmptyState';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { FileFormat } from '../../files/models/FileModels';
import { DownloadedFileEntry } from '../models/DownloadModels';
import { DownloadService } from '../services/DownloadService';
import { DownloadCenterController } from '../controllers/DownloadCenterController';

const IMAGE_EXTS: string[] = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'];
const VIDEO_EXTS: string[] = ['mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp', 'flv', 'ts'];

/** 取小写扩展名（无扩展名返回 ''） */
function extLower(path: string): string {
  const dot: number = path.lastIndexOf('.');
  if (dot <= 0 || dot >= path.length - 1) {
    return '';
  }
  return path.substring(dot + 1).toLowerCase();
}

/**
 * 已完成 Tab（对齐 Flutter download_center_downloaded_files_tab.dart）：
 * 下拉刷新 + 分页列表（触底自动加载更多）；点击 item 弹底部操作菜单。
 */
@ComponentV2
export struct DownloadCenterDownloadedTab {
  @Param ctrl: DownloadCenterController = new DownloadCenterController();
  @Local refreshing: boolean = false;

  build() {
    Column() {
      Refresh({ refreshing: this.refreshing, offset: 40 }) {
        if (this.ctrl.downloadedFiles.length === 0) {
          this.EmptyList()
        } else {
          this.FileList()
        }
      }
      .onRefreshing((): void => {
        this.refreshing = true;
        void this.ctrl.loadFirstPage().then((): void => {
          this.refreshing = false;
        });
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 空态（可下拉刷新） ====================

  @Builder
  EmptyList() {
    List() {
      ListItem() {
        Column() {
          EmptyState({ message: L10n.t('task_empty', '暂无任务') })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 120 })
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  // ==================== 文件列表 ====================

  @Builder
  FileList() {
    List({ space: 10 }) {
      ForEach(this.ctrl.downloadedFiles, (entry: DownloadedFileEntry): void => {
        ListItem() {
          DownloadedFileCard({ entry: entry, ctrl: this.ctrl })
        }
      }, (entry: DownloadedFileEntry): string => `${entry.id}`)

      // 底部加载更多小菊花
      if (this.ctrl.isLoadingMore) {
        ListItem() {
          Row() {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(AppTheme.current().primary)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 12, bottom: 12 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .padding({ left: 12, right: 12, top: 4, bottom: 12 })
    .onReachEnd((): void => {
      void this.ctrl.loadMore();
    })
  }
}

/**
 * 已下载文件卡片（对齐 Flutter download_center_downloaded_file_item.dart）：
 * 缩略图 + 名称/文件已删除 + 远端路径 + 大小/完成时间；点击卡片弹底部操作菜单。
 */
@ComponentV2
struct DownloadedFileCard {
  @Param entry: DownloadedFileEntry = new DownloadedFileEntry();
  @Param ctrl: DownloadCenterController = new DownloadCenterController();

  private palette() {
    return AppTheme.current();
  }

  build() {
    Row({ space: 12 }) {
      this.Thumb()
      Column({ space: 4 }) {
        Text(this.entry.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.entry.fileMissing) {
          Text(L10n.t('download_record_file_deleted', '文件已删除'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().error)
        }
        Text(this.entry.remotePath)
          .fontSize(12)
          .fontColor(this.palette().subText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
        Row() {
          Text(FileFormat.formatSize(this.entry.size))
            .fontSize(12)
            .fontColor(this.palette().subText)
          Text(FileFormat.formatMtime(this.entry.completedTimeMs))
            .fontSize(12)
            .fontColor(this.palette().hint)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 10 })
        }
        .width('100%')
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 右侧箭头，提示卡片可点击
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.palette().hint])
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding(12)
    .borderRadius(16)
    .backgroundColor(this.palette().surfaceBg)
    .onClick((): void => {
      this.showActions();
    })
  }

  /** 弹出底部操作菜单：图片/视频可保存到图库，任意条目可删除 */
  private showActions(): void {
    const p: DownloadedItemSheetParams = new DownloadedItemSheetParams();
    p.entry = this.entry;
    p.showGallery = !this.entry.fileMissing && DownloadService.isSavableMedia(this.entry.name);
    p.onSaveGallery = (): void => {
      void this.ctrl.saveEntryToGallery(this.entry);
    };
    p.onDelete = (): void => {
      void this.ctrl.promptDeleteEntry(this.entry);
    };
    SheetUtil.present(p, wrapBuilder(DownloadedItemSheetContent));
  }

  /** 缩略图：缺失=错误色文件图标；图片=本地图；视频=胶片+播放角标（对齐 Flutter） */
  @Builder
  Thumb() {
    Stack() {
      if (this.entry.fileMissing) {
        SymbolGlyph($r('sys.symbol.doc_plaintext'))
          .fontSize(26)
          .fontColor([this.palette().error])
      } else if (IMAGE_EXTS.includes(extLower(this.entry.path))) {
        Image(`file://${this.entry.path}`)
          .width(56)
          .height(56)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .alt($rawfile('icons/no_data.png'))
      } else if (VIDEO_EXTS.includes(extLower(this.entry.path))) {
        SymbolGlyph($r('sys.symbol.film'))
          .fontSize(26)
          .fontColor([this.palette().subText])
        // 播放角标
        Column() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(16)
            .fontColor(['#FFFFFF'])
        }
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor('#59000000')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        SymbolGlyph($r('sys.symbol.doc_plaintext'))
          .fontSize(26)
          .fontColor([this.palette().subText])
      }
    }
    .width(56)
    .height(56)
    .borderRadius(12)
    .backgroundColor(this.palette().inputFill)
    .alignContent(Alignment.Center)
  }
}

/** 已下载条目底部操作菜单参数 */
class DownloadedItemSheetParams extends SheetParamsBase {
  entry: DownloadedFileEntry = new DownloadedFileEntry();
  /** 是否展示「保存到图库」（仅图片/视频且文件存在） */
  showGallery: boolean = false;
  onSaveGallery: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

/** 已下载条目底部操作菜单：保存到图库（媒体）、删除 */
@Builder
function DownloadedItemSheetContent(p: DownloadedItemSheetParams) {
  Column() {
    SheetHandle()
    // 文件名（菜单上下文）
    Text(p.entry.name)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.current().subText)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ left: 20, right: 20, top: 4, bottom: 10 })

    if (p.showGallery) {
      SheetListItem({
        icon: $r('sys.symbol.rectangle_stack'),
        title: L10n.t('save_to_gallery', '保存到图库'),
        onSelect: (): void => {
          p.close();
          p.onSaveGallery();
        }
      })
    }
    SheetListItem({
      icon: $r('sys.symbol.trash'),
      title: L10n.t('delete', '删除'),
      titleColor: AppTheme.current().error,
      iconColor: AppTheme.current().error,
      onSelect: (): void => {
        p.close();
        p.onDelete();
      }
    })
  }
  .width('100%')
  .backgroundColor(AppTheme.current().surfaceBg)
  .borderRadius({ topLeft: 20, topRight: 20 })
  .padding({ bottom: 30 })
}
