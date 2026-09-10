import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { DialogUtil, DialogParamsBase } from '../../../common/DialogUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import {
  BackupRecord, BackupRecordError, BackupRecordsPayload,
  formatBackupBytes, formatBackupDurationMs, formatBackupLocalTime
} from '../models/FileBackupModels';
import { FileBackupController } from '../controllers/FileBackupController';

/**
 * 磁盘间备份 弹窗集合（对齐 Flutter _BackupRecordsDialog 与失败文件子弹窗）：
 * 备份记录（标题 + 最多保留说明 + 记录卡片列表 + OK）与失败文件列表（路径/原因）。
 * 统一通过 DialogUtil.openCustom 实现。
 */

// ============================================================
// 备份记录弹窗（对齐 Flutter _BackupRecordsDialog）
// ============================================================

class BackupRecordsDialogParams extends DialogParamsBase {
  ctrl: FileBackupController = new FileBackupController();
  taskId: number = 0;
}

@Builder
function BackupRecordsDialogContent(p: BackupRecordsDialogParams) {
  BackupRecordsDialogInner({ p: p })
}

@ComponentV2
struct BackupRecordsDialogInner {
  @Param p: BackupRecordsDialogParams = new BackupRecordsDialogParams();
  @Local loading: boolean = true;
  @Local loadFailed: boolean = false;
  @Local payload: BackupRecordsPayload = new BackupRecordsPayload();

  aboutToAppear(): void {
    void this.fetch();
  }

  private async fetch(): Promise<void> {
    this.loading = true;
    this.loadFailed = false;
    const data = await this.p.ctrl.fetchBackupRecords(this.p.taskId);
    this.loading = false;
    if (data === undefined) {
      this.loadFailed = true;
      return;
    }
    this.payload = data;
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private na(): string {
    return L10n.t('file_backup_run_records_na', '—');
  }

  private recordStatusText(raw: string): string {
    const s = raw.trim().toLowerCase();
    if (s === 'running') {
      return L10n.t('file_backup_record_status_running', '运行中');
    }
    if (s === 'success') {
      return L10n.t('file_backup_record_status_success', '成功');
    }
    if (s === 'failed') {
      return L10n.t('file_backup_record_status_failed', '失败');
    }
    if (s === 'stopped') {
      return L10n.t('file_backup_record_status_stopped', '已停止');
    }
    return raw.trim().length === 0 ? this.na() : raw.trim();
  }

  build() {
    Column() {
      // 标题行：任务 #@id · 备份历史 + 关闭
      Row({ space: 8 }) {
        Text(L10n.t('file_backup_run_records_title', '任务 #@id · 备份历史',
          L10n.paramsOf('id', `${this.p.taskId}`)))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([this.palette().hint])
          .onClick((): void => {
            this.p.onResult(undefined);
          })
      }
      .width('100%')

      Divider()
        .color(AppTheme.withAlpha(this.palette().divider, 0.5))
        .margin({ top: 10, bottom: 4 })

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.palette().primary)
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
      } else if (this.loadFailed) {
        Column() {
          Text(L10n.t('file_backup_run_records_load_failed', '加载备份记录失败'))
            .fontSize(14)
            .fontColor(this.palette().error)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else if (this.payload.items.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('file_backup_run_records_empty', '暂无备份记录') })
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text(L10n.t('file_backup_run_record_max_kept_note', '每个任务最多保留最近 @n 次运行记录',
            L10n.paramsOf('n', `${this.payload.maxKept}`)))
            .fontSize(11)
            .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.65))
            .width('100%')
            .padding({ left: 2, right: 2, top: 2, bottom: 4 })

          List({ space: 4 }) {
            ForEach(this.payload.items, (rec: BackupRecord, index: number) => {
              ListItem() {
                this.RecordCard(rec, index)
              }
            }, (rec: BackupRecord, index: number): string =>
              `${rec.idPresent ? rec.id : `n${this.payload.items.length - index}`}_${index}`)
          }
          .width('100%')
          .constraintSize({ maxHeight: 400 })
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .padding({ top: 2, bottom: 2 })
        }
        .width('100%')
      }

      // 底部 OK
      Row() {
        Button(L10n.ok)
          .fontSize(14)
          .fontColor(this.palette().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick((): void => {
            this.p.onResult(undefined);
          })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 8 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(this.palette().surfaceBg)
    .borderRadius(24)
    .width('92%')
    .constraintSize({ maxWidth: 560 })
  }

  /** 记录卡片（对齐 Flutter 记录 Card：编号 + kv 信息 + 失败文件摘要行） */
  @Builder
  RecordCard(rec: BackupRecord, index: number) {
    Column() {
      Text(L10n.t('file_backup_run_record_heading', '记录 #@id',
        L10n.paramsOf('id', rec.idPresent ? `${rec.id}` : `${this.payload.items.length - index}`)))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
      this.KvRow(L10n.t('file_backup_run_record_start', '开始时间'),
        formatBackupLocalTime(rec.startTime, this.na()))
      this.KvRow(L10n.t('file_backup_run_record_end', '结束时间'),
        rec.endTime === undefined || rec.endTime === null
          ? this.na()
          : formatBackupLocalTime(rec.endTime, this.na()))
      this.KvRow(L10n.t('file_backup_run_record_status', '状态'), this.recordStatusText(rec.status))
      this.KvRow(L10n.t('file_backup_run_record_duration_ms', '耗时'),
        formatBackupDurationMs(rec.durationMs, this.na()))
      this.KvRow(L10n.t('file_backup_run_record_files_copied', '已复制文件数'), `${rec.filesCopied}`)
      this.KvRow(L10n.t('file_backup_run_record_files_skipped', '已跳过文件数'), `${rec.filesSkipped}`)
      this.KvRow(L10n.t('file_backup_run_record_files_removed', '已删除文件数'), `${rec.filesRemoved}`)
      this.KvRow(L10n.t('file_backup_run_record_bytes_copied', '已复制字节数'),
        formatBackupBytes(rec.bytesCopied))
      this.ErrorFilesRow(rec.errors)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(8)
    .backgroundColor(AppTheme.withAlpha(this.palette().onSurface, 0.05))
    .border({
      width: 1,
      color: AppTheme.withAlpha(this.palette().divider, 0.45)
    })
  }

  /** kv 信息行（对齐 Flutter _kv：120 标签列，最多 4 行） */
  @Builder
  KvRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(11)
        .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.7))
        .width(120)
      Text(value)
        .fontSize(12.5)
        .fontColor(this.palette().onSurface)
        .lineHeight(15)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 1 })
  }

  /** 失败文件摘要行（对齐 Flutter _errorFilesSummaryRow：预览 + 更多数，点击弹列表） */
  @Builder
  ErrorFilesRow(errors: BackupRecordError[]) {
    if (errors.length === 0) {
      this.KvRow(L10n.t('file_backup_run_record_error_files', '失败文件'), this.na())
    } else {
      Row() {
        Text(L10n.t('file_backup_run_record_error_files', '失败文件'))
          .fontSize(11)
          .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.7))
          .width(120)
        Row({ space: 4 }) {
          Text(this.errorPreview(errors))
            .fontSize(12.5)
            .fontColor(this.palette().onSurface)
            .lineHeight(15)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (errors.length - 1 > 0) {
            Text(L10n.t('file_backup_run_record_error_more', '+@n',
              L10n.paramsOf('n', `${errors.length - 1}`)))
              .fontSize(12.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().primary)
          }
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
        .onClick((): void => {
          showBackupErrorFilesDialog(errors);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 1 })
    }
  }

  private errorPreview(errors: BackupRecordError[]): string {
    const first = errors[0];
    const path = first.path.trim();
    const err = first.error.trim();
    if (path.length === 0 && err.length === 0) {
      return this.na();
    }
    if (path.length === 0) {
      return err;
    }
    if (err.length === 0) {
      return path;
    }
    return `${path}: ${err}`;
  }
}

/** 打开备份记录弹窗（对齐 Flutter _showBackupRecordsDialog） */
export function showBackupRecordsDialog(ctrl: FileBackupController, taskId: number): void {
  const p = new BackupRecordsDialogParams();
  p.ctrl = ctrl;
  p.taskId = taskId;
  DialogUtil.openCustom<BackupRecordsDialogParams>(p, wrapBuilder(BackupRecordsDialogContent), true);
}

// ============================================================
// 失败文件列表弹窗（对齐 Flutter _showErrorFilesDialog）
// ============================================================

class BackupErrorFilesDialogParams extends DialogParamsBase {
  errors: BackupRecordError[] = [];
}

@Builder
function BackupErrorFilesDialogContent(p: BackupErrorFilesDialogParams) {
  BackupErrorFilesDialogInner({ p: p })
}

@ComponentV2
struct BackupErrorFilesDialogInner {
  @Param p: BackupErrorFilesDialogParams = new BackupErrorFilesDialogParams();

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private na(): string {
    return L10n.t('file_backup_run_records_na', '—');
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(L10n.t('file_backup_run_record_error_files_dialog_title', '失败文件列表'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([this.palette().hint])
          .onClick((): void => {
            this.p.onResult(undefined);
          })
      }
      .width('100%')

      Divider()
        .color(AppTheme.withAlpha(this.palette().divider, 0.5))
        .margin({ top: 10, bottom: 2 })

      List({ space: 0 }) {
        ForEach(this.p.errors, (e: BackupRecordError, index: number) => {
          ListItem() {
            this.ErrorRow(e, index === this.p.errors.length - 1)
          }
        }, (e: BackupRecordError, index: number): string => `${index}_${e.path}_${e.error.length}`)
      }
      .width('100%')
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Auto)
      .padding({ top: 2, bottom: 2 })

      Row() {
        Button(L10n.ok)
          .fontSize(14)
          .fontColor(this.palette().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick((): void => {
            this.p.onResult(undefined);
          })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 6 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 12, bottom: 10 })
    .backgroundColor(this.palette().surfaceBg)
    .borderRadius(24)
    .width('92%')
    .constraintSize({ maxWidth: 520 })
  }

  /** 失败文件条目（路径 + 原因，对齐 Flutter 列表项结构） */
  @Builder
  ErrorRow(e: BackupRecordError, isLast: boolean) {
    Column() {
      Text(L10n.t('file_backup_run_record_error_path', '路径'))
        .fontSize(11)
        .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.65))
        .width('100%')
      Text(e.path.trim().length > 0 ? e.path : this.na())
        .fontSize(12.5)
        .fontColor(this.palette().onSurface)
        .lineHeight(15)
        .width('100%')
      Text(L10n.t('file_backup_run_record_error_reason', '原因'))
        .fontSize(11)
        .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.65))
        .width('100%')
        .margin({ top: 6 })
      Text(e.error.trim().length > 0 ? e.error : this.na())
        .fontSize(12.5)
        .fontColor(this.palette().error)
        .lineHeight(15)
        .width('100%')
      if (!isLast) {
        Divider()
          .color(AppTheme.withAlpha(this.palette().divider, 0.35))
          .margin({ top: 8 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }
}

/** 打开失败文件列表弹窗（对齐 Flutter _showErrorFilesDialog） */
export function showBackupErrorFilesDialog(errors: BackupRecordError[]): void {
  const p = new BackupErrorFilesDialogParams();
  p.errors = errors;
  DialogUtil.openCustom<BackupErrorFilesDialogParams>(p, wrapBuilder(BackupErrorFilesDialogContent), true);
}
