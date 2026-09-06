import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { ToastUtil } from '../../common/ToastUtil';
import { TransferStatus, TransferTask } from '../models/TransferModels';
import { UploadTransferHelper } from '../utils/UploadTransferHelper';
import { UploadController } from '../controllers/UploadController';

const IMAGE_EXTS: string[] = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'];
const VIDEO_EXTS: string[] = ['mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp'];

function extLower(path: string): string {
  const dot = path.lastIndexOf('.');
  if (dot <= 0 || dot >= path.length - 1) {
    return '';
  }
  return path.substring(dot + 1).toLowerCase();
}

/**
 * 上传任务卡片（对齐 Flutter upload_center_task_card.dart）：
 * 缩略图 + 名称/路径/信息 + 进度条 + 状态行 + 暂停/继续/重试/删除操作。
 */
@ComponentV2
export struct UploadTaskCard {
  @Param task: TransferTask = new TransferTask('', '', '', '', 0, 0, 0);
  @Param ctrl: UploadController = UploadController.getInstance();

  private palette() {
    return AppTheme.current();
  }

  private statusColor(): string {
    return this.task.status === TransferStatus.ERROR ? this.palette().error : this.palette().subText;
  }

  private messageColor(): string {
    const isError = this.task.status === TransferStatus.ERROR;
    return isError ? this.palette().error : this.palette().primary;
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        this.TaskThumb()
        Column({ space: 4 }) {
          Text(this.task.name)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.task.remotePath)
            .fontSize(12)
            .fontColor(this.palette().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.task.error.length > 0) {
            Text(this.task.error)
              .fontSize(12)
              .fontColor(this.messageColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Progress({ value: Math.round(this.task.progress * 100), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(6)
            .borderRadius(3)
            .color(this.palette().primary)
            .backgroundColor(this.palette().inputFill)
          Row() {
            Text(UploadTransferHelper.statusText(this.task.status))
              .fontSize(12)
              .fontColor(this.statusColor())
            Text(`${UploadTransferHelper.formatBytes(this.task.processedSize)} / ${UploadTransferHelper.formatBytes(this.task.totalSize)}`)
              .fontSize(12)
              .fontColor(this.palette().subText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 8 })
              .layoutWeight(1)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        this.TaskActions()
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(16)
    .backgroundColor(this.palette().surfaceBg)
  }

  @Builder
  TaskThumb() {
    Column() {
      if (extLower(this.task.localUri) !== '' && IMAGE_EXTS.includes(extLower(this.task.localUri)) &&
        this.task.localUri.startsWith('file://')) {
        Image(this.task.localUri)
          .width(56)
          .height(56)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .alt($rawfile('icons/no_data.png'))
          .onError(() => {
            // 加载失败时退化为占位图（本 Builder 内无法条件切换，alt 已兜底）
          })
      } else {
        SymbolGlyph(this.thumbSymbol())
          .fontSize(26)
          .fontColor([this.palette().subText])
      }
    }
    .width(56)
    .height(56)
    .borderRadius(12)
    .backgroundColor(this.palette().inputFill)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private thumbSymbol(): Resource {
    const ext = extLower(this.task.localUri);
    if (VIDEO_EXTS.includes(ext)) {
      return $r('sys.symbol.film');
    }
    if (IMAGE_EXTS.includes(ext)) {
      return $r('sys.symbol.picture');
    }
    return $r('sys.symbol.doc_plaintext');
  }

  @Builder
  TaskActions() {
    Row({ space: 2 }) {
      if (this.task.status === TransferStatus.UPLOADING || this.task.status === TransferStatus.PENDING) {
        SymbolGlyph($r('sys.symbol.pause'))
          .fontSize(22)
          .fontColor([this.palette().onSurface])
          .onClick(() => {
            this.ctrl.pauseTask(this.task);
          })
      } else if (this.task.status === TransferStatus.PAUSED) {
        SymbolGlyph($r('sys.symbol.play'))
          .fontSize(22)
          .fontColor([this.palette().primary])
          .onClick(() => {
            this.ctrl.startTask(this.task);
          })
      } else if (this.task.status === TransferStatus.ERROR) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(22)
          .fontColor([this.palette().onSurface])
          .onClick(() => {
            this.ctrl.startTask(this.task);
          })
      }
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor([this.palette().subText])
        .margin({ left: 6 })
        .onClick(() => {
          this.ctrl.deleteTask(this.task);
        })
    }
  }
}

/** 已完成任务卡片（对齐 Flutter upload_center_completed_tab.dart 列表项） */
@ComponentV2
export struct UploadCompletedCard {
  @Param task: TransferTask = new TransferTask('', '', '', '', 0, 0, 0);
  @Param ctrl: UploadController = UploadController.getInstance();
  @Param savedPath: string = '';

  private palette() {
    return AppTheme.current();
  }

  build() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor(['#4CAF50'])
      Column({ space: 4 }) {
        Text(this.task.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.savedPath)
          .fontSize(12)
          .fontColor(this.palette().subText)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Column() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(16)
          .fontColor([this.palette().subText])
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(36)
      .height(36)
      .borderRadius(10)
      .border({ width: 1, color: this.palette().divider })
      .onClick(() => {
        this.ctrl.deleteTask(this.task);
      })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding(12)
    .borderRadius(16)
    .backgroundColor(this.palette().surfaceBg)
    .onClick(() => {
      ToastUtil.show(this.savedPath);
    })
  }
}

export function joinUploadRemotePath(dir: string, name: string): string {
  const d = dir.trim().length === 0 ? '/' : dir.trim();
  if (d.endsWith('/')) {
    return `${d}${name}`;
  }
  return `${d}/${name}`;
}
