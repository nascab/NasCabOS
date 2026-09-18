import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { DialogUtil, DialogParamsBase } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import { UploadTransferHelper } from '../../../transfer/utils/UploadTransferHelper';
import { PhotoBackupController } from '../controllers/PhotoBackupController';
import {
  formatPhotoBackupTime, PhotoBackupFileRecord, PhotoBackupRunRecord, PhotoBackupTask
} from '../models/PhotoBackupModels';

/**
 * 相册备份 弹窗集合（对齐 Flutter _RunRecordsDialog 与 _RunFilesDialog）：
 * 备份记录（运行列表：成功/失败数 + 时间区间 + 体积 + 文件记录/删除操作）
 * 与单次运行的文件上传记录（状态图标 + 文件名 + 体积/时间 + 错误）。
 * 统一通过 DialogUtil.openCustom 实现。
 */

// ============================================================
// 备份记录弹窗（对齐 Flutter _RunRecordsDialog）
// ============================================================

class PhotoBackupRunsDialogParams extends DialogParamsBase {
  ctrl: PhotoBackupController = new PhotoBackupController();
  task: PhotoBackupTask = new PhotoBackupTask();
  runs: PhotoBackupRunRecord[] = [];
}

@Builder
function PhotoBackupRunsDialogContent(p: PhotoBackupRunsDialogParams) {
  PhotoBackupRunsDialogInner({ p: p })
}

@ComponentV2
struct PhotoBackupRunsDialogInner {
  @Param p: PhotoBackupRunsDialogParams = new PhotoBackupRunsDialogParams();
  /** 本地可变副本：删除记录后从列表移除（对齐 Flutter setState _runs.removeWhere） */
  @Local runs: PhotoBackupRunRecord[] = [];
  /** 自增触发 ForEach 重建（删除项后键值集合变化） */
  @Local revision: number = 0;

  aboutToAppear(): void {
    this.runs = this.p.runs.slice();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 运行记录标题参数（成功 @success，失败 @failed） */
  private runItemParams(run: PhotoBackupRunRecord): Map<string, string> {
    const params = new Map<string, string>();
    params.set('success', `${run.successCount}`);
    params.set('failed', `${run.failedCount}`);
    return params;
  }

  /** 删除运行记录（对齐 Flutter onDeleteRun：deleteRun + refreshTasks + 本地移除） */
  private async removeRun(run: PhotoBackupRunRecord): Promise<void> {
    await this.p.ctrl.deleteRun(run.id);
    await this.p.ctrl.refreshTasks();
    this.runs = this.runs.filter((e: PhotoBackupRunRecord): boolean => e.id !== run.id);
    this.revision++;
  }

  build() {
    Column() {
      // 标题行：@name 的备份记录 + 关闭
      Row({ space: 8 }) {
        Text(L10n.t('photo_backup_runs_title', '@name 的备份记录',
          L10n.paramsOf('name', this.p.task.name)))
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

      if (this.runs.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('no_data', '暂无数据') })
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.runs, (run: PhotoBackupRunRecord, index: number) => {
            ListItem() {
              this.RunRow(run, index === this.runs.length - 1)
            }
          }, (run: PhotoBackupRunRecord): string => `${run.id}_${this.revision}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
        .padding({ top: 2, bottom: 2 })
      }

      Row() {
        Button(L10n.t('close', '关闭'))
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
    .padding(16)
    .backgroundColor(this.palette().surfaceBg)
    .borderRadius(24)
    .width('92%')
    .constraintSize({ maxWidth: 560 })
  }

  /** 运行记录行（对齐 Flutter ListTile：标题成功/失败数，副标题时间区间 + 体积，尾部两个操作） */
  @Builder
  RunRow(run: PhotoBackupRunRecord, isLast: boolean) {
    Row() {
      Column({ space: 2 }) {
        Text(L10n.t('photo_backup_run_item', '成功 @success，失败 @failed',
          this.runItemParams(run)))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${formatPhotoBackupTime(run.startedAtMs)} - ${formatPhotoBackupTime(run.finishedAtMs)}\n`
          + `${UploadTransferHelper.formatBytes(run.totalBytes)}`)
          .fontSize(12)
          .fontColor(this.palette().subText)
          .lineHeight(16)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(20)
          .fontColor([this.palette().subText])
          .onClick((): void => {
            showPhotoBackupRunFilesDialog(this.p.ctrl, run);
          })
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([this.palette().subText])
          .onClick((): void => {
            void this.removeRun(run);
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 10, bottom: 10 })
    .margin({ left: 2, right: 2 })

    if (!isLast) {
      Divider()
        .color(AppTheme.withAlpha(this.palette().divider, 0.35))
    }
  }
}

/** 打开备份记录弹窗（对齐 Flutter _showRunsDialog；openLatestFiles=true 时直接打开最近一次文件记录） */
export function showPhotoBackupRunsDialog(ctrl: PhotoBackupController, task: PhotoBackupTask,
  openLatestFiles: boolean): void {
  void ctrl.listRuns(task.id).then((runs: PhotoBackupRunRecord[]): void => {
    if (runs.length === 0) {
      ToastUtil.show(L10n.t('no_data', '暂无数据'));
      return;
    }
    if (openLatestFiles) {
      showPhotoBackupRunFilesDialog(ctrl, runs[0]);
      return;
    }
    const p = new PhotoBackupRunsDialogParams();
    p.ctrl = ctrl;
    p.task = task;
    p.runs = runs;
    DialogUtil.openCustom<PhotoBackupRunsDialogParams>(p, wrapBuilder(PhotoBackupRunsDialogContent), true);
  });
}

// ============================================================
// 文件上传记录弹窗（对齐 Flutter _RunFilesDialog）
// ============================================================

class PhotoBackupRunFilesDialogParams extends DialogParamsBase {
  ctrl: PhotoBackupController = new PhotoBackupController();
  run: PhotoBackupRunRecord = new PhotoBackupRunRecord();
  files: PhotoBackupFileRecord[] = [];
}

@Builder
function PhotoBackupRunFilesDialogContent(p: PhotoBackupRunFilesDialogParams) {
  PhotoBackupRunFilesDialogInner({ p: p })
}

@ComponentV2
struct PhotoBackupRunFilesDialogInner {
  @Param p: PhotoBackupRunFilesDialogParams = new PhotoBackupRunFilesDialogParams();

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(L10n.t('photo_backup_file_logs_title', '文件上传记录（@time）',
          L10n.paramsOf('time', formatPhotoBackupTime(this.p.run.startedAtMs))))
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

      if (this.p.files.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('no_data', '暂无数据') })
        }
        .width('100%')
        .height(220)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.p.files, (item: PhotoBackupFileRecord, index: number) => {
            ListItem() {
              this.FileRow(item, index === this.p.files.length - 1)
            }
          }, (item: PhotoBackupFileRecord): string => `${item.id}_${item.displayName.length}_${item.status}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .scrollBar(BarState.Auto)
        .padding({ top: 2, bottom: 2 })
      }

      Row() {
        Button(L10n.t('close', '关闭'))
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
    .padding(16)
    .backgroundColor(this.palette().surfaceBg)
    .borderRadius(24)
    .width('92%')
    .constraintSize({ maxWidth: 560 })
  }

  /** 文件记录行（对齐 Flutter ListTile：状态图标 + 文件名 + 体积·时间 + 错误行） */
  @Builder
  FileRow(item: PhotoBackupFileRecord, isLast: boolean) {
    Column() {
      Row({ space: 10 }) {
        if (item.status === 'error') {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(22)
            .fontColor([this.palette().error])
        } else {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(22)
            .fontColor(['#4CAF50'])
        }
        Column({ space: 2 }) {
          Text(item.displayName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(`${UploadTransferHelper.formatBytes(item.size)} · ${formatPhotoBackupTime(item.uploadedAtMs)}`
            + `${item.error.length === 0 ? '' : `\n${item.error}`}`)
            .fontSize(12)
            .fontColor(item.error.length === 0 ? this.palette().subText : this.palette().error)
            .lineHeight(16)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 8, bottom: 8 })

      if (!isLast) {
        Divider()
          .color(AppTheme.withAlpha(this.palette().divider, 0.35))
      }
    }
    .width('100%')
  }
}

/** 打开文件上传记录弹窗（对齐 Flutter _showRunFilesDialog） */
export function showPhotoBackupRunFilesDialog(ctrl: PhotoBackupController, run: PhotoBackupRunRecord): void {
  void ctrl.listRunFiles(run.id).then((files: PhotoBackupFileRecord[]): void => {
    const p = new PhotoBackupRunFilesDialogParams();
    p.ctrl = ctrl;
    p.run = run;
    p.files = files;
    DialogUtil.openCustom<PhotoBackupRunFilesDialogParams>(p,
      wrapBuilder(PhotoBackupRunFilesDialogContent), true);
  });
}
