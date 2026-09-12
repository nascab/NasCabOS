import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { FileOperationLog, formatLogTime } from '../models/UserModels';

/**
 * 文件操作日志条目（对齐 Flutter FileLogItem compact 移动端形态）：
 * 状态色图标 + 类型 + 状态标签 + 处理中进度环 + 源/目标路径 + 错误信息。
 */
@ComponentV2
export struct FileLogItem {
  @Require @Param log: FileOperationLog;
  /** 取消回调（对齐 Flutter onCancel：传入且进行中时显示取消按钮） */
  @Param onCancel: ((log: FileOperationLog) => void) | undefined = undefined;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private statusColor(): string {
    return this.log.isErrorState() ? this.palette().error : this.palette().primary;
  }

  /** 类型图标（对齐 FileLogItem._getIcon；Icons.copy/doc_on_doc 等无对应符号，按语义近似映射） */
  private typeIcon(): Resource {
    switch (this.log.type) {
      case 'copy':
        return $r('sys.symbol.doc_filled_on_doc');
      case 'move':
        return $r('sys.symbol.folder');
      case 'delete':
        return $r('sys.symbol.trash');
      case 'rename':
        return $r('sys.symbol.doc_text');
      default:
        return $r('sys.symbol.doc_plaintext');
    }
  }

  private typeLabel(): string {
    return L10n.t(this.log.type.toLowerCase(), this.log.type);
  }

  private stateLabel(): string {
    return L10n.t(this.log.state.toLowerCase(), this.log.state);
  }

  /** 源路径摘要：首个 + 剩余数量（对齐 FileLogItem 摘要逻辑），点击查看完整列表 */
  private sourceSummary(): string {
    if (this.log.sourcePath.length === 0) {
      return '-';
    }
    const first = this.log.sourcePath[0];
    if (this.log.sourcePath.length > 1) {
      return `${first} (+${this.log.sourcePath.length - 1})`;
    }
    return first;
  }

  /** 查看操作文件列表（对齐 _showSourcePaths） */
  private showSourcePaths(): void {
    DialogUtil.showInfoDialog(
      L10n.t('operation_file_list', '操作文件列表'),
      this.log.sourcePath.join('\n\n'));
  }

  @Builder
  ProgressRing() {
    Stack() {
      Progress({ value: Math.round(this.log.progress() * 100), total: 100,
        type: ProgressType.Ring })
        .width(32)
        .height(32)
        .color(this.statusColor())
      Text(`${Math.round(this.log.progress() * 100)}%`)
        .fontSize(9)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
    }
    .width(32)
    .height(32)
  }

  build() {
    Column() {
      // 行 1：图标 + 类型 + 状态标签 + 进度环
      Row({ space: 10 }) {
        Column() {
          SymbolGlyph(this.typeIcon())
            .fontSize(18)
            .fontColor([this.statusColor()])
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .width(36)
        .height(36)
        .borderRadius(8)
        .backgroundColor(AppTheme.withAlpha(this.statusColor(), 0.1))

        Text(this.typeLabel())
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.stateLabel())
          .fontSize(10)
          .fontColor(this.statusColor())
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor(AppTheme.withAlpha(this.statusColor(), 0.2))

        Blank()

        if (this.log.state === 'PROCESSING') {
          this.ProgressRing()
        }

        // 取消按钮（进行中且传入 onCancel 时显示，对齐 Flutter _buildCancelButton）
        if (this.log.state === 'PROCESSING' && this.onCancel !== undefined) {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(20)
            .fontColor([this.palette().subText])
            .margin({ left: 4 })
            .onClick((): void => {
              if (this.onCancel !== undefined) {
                this.onCancel(this.log);
              }
            })
        }

        if (this.log.createTime > 0) {
          Text(formatLogTime(this.log.createTime))
            .fontSize(10)
            .fontColor(this.palette().subText)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 行 2：源路径（点击查看完整列表）
      Text(this.sourceSummary())
        .fontSize(12)
        .fontColor(this.palette().subText)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
        .width('100%')
        .onClick((): void => {
          this.showSourcePaths();
        })

      // 行 3：目标路径
      if (this.log.targetPath.length > 0) {
        Text(this.log.targetPath)
          .fontSize(12)
          .fontColor(this.palette().subText)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
          .width('100%')
      }

      // 行 4：错误信息
      if (this.log.message.length > 0 && this.log.state === 'ERROR') {
        Text(this.log.message)
          .fontSize(12)
          .fontColor(this.palette().error)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 8, right: 8 })
  }
}
