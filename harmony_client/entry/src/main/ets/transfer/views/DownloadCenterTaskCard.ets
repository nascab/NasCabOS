import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil } from '../../common/DialogUtil';
import { FileFormat } from '../../files/models/FileModels';
import { DownloadTaskItem } from '../models/DownloadModels';
import { TransferStatus } from '../models/TransferModels';
import { DownloadService } from '../services/DownloadService';

/** 蓝色下载图标底色（对齐 Flutter Colors.blue[50]） */
const ICON_BG_BLUE: string = '#E3F2FD';
/** 下载图标蓝色（对齐 Flutter Colors.blue） */
const ICON_BLUE: string = '#2196F3';

/**
 * 下载任务卡片（对齐 Flutter task_download_item.dart）：
 * 蓝色下载图标 + 名称/状态标签 + 下载至路径 + 错误（含重试）/字节信息
 * + 环形进度（百分比）+ 暂停/恢复 + 删除。
 */
@ComponentV2
export struct DownloadCenterTaskCard {
  @Param task: DownloadTaskItem = new DownloadTaskItem('', '', '', '', 0, 0);

  private palette() {
    return AppTheme.current();
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        this.IconBox()
        Column({ space: 5 }) {
          this.NameRow()
          Text(`${L10n.t('download_to', '下载至')} ${this.task.localPath}`)
            .fontSize(12)
            .fontColor(this.palette().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.task.status === TransferStatus.ERROR) {
            this.ErrorRow()
          } else {
            this.BytesRow()
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        this.TrailingArea()
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(16)
    .backgroundColor(this.palette().surfaceBg)
  }

  // ==================== 左侧图标 ====================

  @Builder
  IconBox() {
    Column() {
      SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
        .fontSize(22)
        .fontColor([ICON_BLUE])
    }
    .width(40)
    .height(40)
    .borderRadius(10)
    .backgroundColor(ICON_BG_BLUE)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ==================== 名称 + 状态标签 ====================

  @Builder
  NameRow() {
    Row({ space: 8 }) {
      Text(this.task.name)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.task.status === TransferStatus.COMPLETED) {
        this.StatusTag(L10n.t('success', '成功'), '#4CAF50')
      } else if (this.task.status === TransferStatus.ERROR) {
        this.StatusTag(L10n.t('failed', '已失败'), this.palette().error)
      }
    }
    .width('100%')
  }

  /** 小状态标签（成功绿/失败红，对齐 Flutter CustomTag） */
  @Builder
  StatusTag(label: string, color: string) {
    Text(label)
      .fontSize(10)
      .fontColor(color)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(4)
      .backgroundColor(color === this.palette().error ? '#FDEDED' : '#E8F5E9')
  }

  // ==================== 错误 / 字节 ====================

  @Builder
  ErrorRow() {
    Row({ space: 8 }) {
      Text(this.task.error.length > 0 ? this.task.error : L10n.t('error', '错误'))
        .fontSize(12)
        .fontColor(this.palette().error)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Row({ space: 2 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(14)
          .fontColor([ICON_BLUE])
        Text(L10n.t('retry', '重试'))
          .fontSize(12)
          .fontColor(ICON_BLUE)
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .onClick((): void => {
        void DownloadService.getInstance().retryItem(this.task);
      })
    }
    .width('100%')
  }

  @Builder
  BytesRow() {
    Text(this.task.totalSize > 0
      ? `${FileFormat.formatSize(this.task.processedSize)} / ${FileFormat.formatSize(this.task.totalSize)}`
      : FileFormat.formatSize(this.task.processedSize))
      .fontSize(12)
      .fontColor(this.palette().subText)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  // ==================== 右侧：环形进度 + 操作 ====================

  @Builder
  TrailingArea() {
    Row({ space: 6 }) {
      if (this.task.status === TransferStatus.UPLOADING ||
        this.task.status === TransferStatus.PENDING) {
        this.ProgressRing()
      }
      if (this.task.status === TransferStatus.UPLOADING ||
        this.task.status === TransferStatus.PENDING) {
        SymbolGlyph($r('sys.symbol.pause'))
          .fontSize(22)
          .fontColor([this.palette().onSurface])
          .onClick((): void => {
            void DownloadService.getInstance().pauseItem(this.task);
          })
      } else if (this.task.status === TransferStatus.PAUSED) {
        SymbolGlyph($r('sys.symbol.play'))
          .fontSize(22)
          .fontColor([ICON_BLUE])
          .onClick((): void => {
            void DownloadService.getInstance().resumeItem(this.task);
          })
      }
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor([this.palette().subText])
        .onClick((): void => {
          this.confirmDelete();
        })
    }
    .alignItems(VerticalAlign.Center)
  }

  /** 环形进度（有总大小显示百分比；未知总大小显示不确定转圈） */
  @Builder
  ProgressRing() {
    Stack() {
      Progress({
        value: this.task.totalSize > 0 ? Math.round(this.task.progress * 100) : 0,
        total: 100,
        type: ProgressType.Ring
      })
        .width(45)
        .height(45)
        .color(ICON_BLUE)
        .backgroundColor('#EEEEEE')
      if (this.task.totalSize > 0) {
        Text(`${Math.round(this.task.progress * 100)}%`)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
      }
    }
    .width(45)
    .height(45)
    .alignContent(Alignment.Center)
  }

  /** 删除前确认（对齐 Flutter confirmRemoveTask） */
  private confirmDelete(): void {
    void DialogUtil.showConfirmDialog(
      L10n.t('confirm_delete_task', '确定删除任务吗？'),
      this.task.name,
      (): void => {
        void DownloadService.getInstance().removeItem(this.task);
      });
  }
}
