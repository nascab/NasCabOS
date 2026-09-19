import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { AppEventBus } from '../../../common/AppEventBus';
import { LanguageService } from '../../../core/localization/LanguageService';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { NavUtil } from '../../../common/NavUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import { GlassCard } from '../../../common/components/GlassCard';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { UploadTransferHelper } from '../../../transfer/utils/UploadTransferHelper';
import { PhotoBackupController, PhotoBackupRuntime } from '../controllers/PhotoBackupController';
import { PhotoBackupSourceType, PhotoBackupTask } from '../models/PhotoBackupModels';
import { PhotoBackupRoutes, PhotoBackupPageParam, PhotoBackupTaskFormPageParam } from '../router/PhotoBackupRoutes';
import { showPhotoBackupRunsDialog } from '../components/PhotoBackupDialogs';

/**
 * 相册备份主页（对齐 Flutter AppPhotoBackupView）：
 * 标题栏（新增）+ 任务列表卡片；点击卡片弹出动作弹层
 * （编辑/上传新增/上传全部/备份记录/文件上传记录/停止/删除）。
 */
@ComponentV2
export struct PhotoBackupPage {
  @Param param: PhotoBackupPageParam = new PhotoBackupPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 控制器为模块级单例（对齐 Flutter Get.put(permanent: true)） */
  @Local ctrl: PhotoBackupController = PhotoBackupController.getInstance();
  /** 依赖 localeBump：切换语言后触发整页刷新 */
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string): void => {
    this.localeBump++;
  };

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    // 对齐 Flutter onInit：按当前会话身份刷新任务列表（身份变化或列表为空时拉取）
    void this.ctrl.onSessionMaybeChanged();
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private onCreate(): void {
    const p = new PhotoBackupTaskFormPageParam();
    NavUtil.push(PhotoBackupRoutes.PAGE_EDIT, p);
  }

  build() {
    PageScaffold({
      title: L10n.homePhotoBackup,
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  TitleActions() {
    SymbolGlyph($r('sys.symbol.plus'))
      .fontSize(22)
      .fontColor([AppTheme.current().appBarFg])
      .onClick((): void => {
        this.onCreate();
      })
  }

  @Builder
  PageContent() {
    Column() {
      if (this.ctrl.loading && this.ctrl.tasks.length === 0) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.palette().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.tasks.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('photo_backup_empty_hint', '还没有备份任务，点击右上角创建一个吧') })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.ctrl.tasks, (task: PhotoBackupTask) => {
            ListItem() {
              TaskCard({ task: task, ctrl: this.ctrl })
            }
          }, (task: PhotoBackupTask): string => `${task.id}_${task.name}_${task.targetDir.length}`
            + `_${task.sourceName.length}_${task.nameStrategy}_${task.saveType}`
            + `_${this.ctrl.runtimeOf(task.id).running}_${this.ctrl.runtimeOf(task.id).status}`
            + `_${this.ctrl.runtimeOf(task.id).error.length}`
            + `_${this.ctrl.runtimeOf(task.id).doneFiles}_${this.ctrl.runtimeOf(task.id).totalFiles}`
            + `_${this.ctrl.runtimeOf(task.id).doneBytes}_${this.ctrl.runtimeOf(task.id).totalBytes}`
            + `_${this.localeBump}`)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
    .opacity(this.localeBump >= 0 ? 1 : 1)
  }
}

/**
 * 任务卡片（对齐 Flutter _TaskCard）：
 * 标题行 名称 + 状态；kv 信息行（来源/目标/同名策略/保存类型）；
 * 运行中显示进度条与进度文本/当前文件；异常显示错误文案。点击卡片弹出动作弹层。
 */
@ComponentV2
struct TaskCard {
  @Require @Param task: PhotoBackupTask;
  @Require @Param ctrl: PhotoBackupController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private runtime(): PhotoBackupRuntime {
    return this.ctrl.runtimeOf(this.task.id);
  }

  private statusText(): string {
    const rt = this.runtime();
    if (rt.running) {
      return L10n.t('local_backup_status_running', '运行中');
    }
    if (rt.status === 'error') {
      return L10n.t('local_backup_status_error', '异常');
    }
    return L10n.t('local_backup_status_idle', '空闲');
  }

  private statusColor(): string {
    const rt = this.runtime();
    if (rt.running) {
      return this.palette().primary;
    }
    if (rt.status === 'error') {
      return this.palette().error;
    }
    return this.palette().subText;
  }

  private sourceTypeText(): string {
    return this.task.sourceType === PhotoBackupSourceType.ALBUM
      ? L10n.t('photo_backup_source_album', '相册')
      : L10n.t('photo_backup_source_folder', '文件夹');
  }

  /** 保存类型文案（对齐 Flutter _saveTypeText） */
  private saveTypeText(): string {
    const v = this.task.saveType.trim().toLowerCase();
    if (v === 'day') {
      return L10n.t('upload_center_save_type_day', '按年/月/日保存');
    }
    if (v === 'month') {
      return L10n.t('upload_center_save_type_month', '按年/月保存');
    }
    if (v === 'year') {
      return L10n.t('upload_center_save_type_year', '按年保存');
    }
    return L10n.t('upload_center_save_type_root', '保存到根目录(默认)');
  }

  /** 进度参数（对齐 Flutter photo_backup_progress @done/@total · @bytesDone / @bytesTotal） */
  private progressParams(): Map<string, string> {
    const rt = this.runtime();
    const params = new Map<string, string>();
    params.set('done', `${rt.doneFiles}`);
    params.set('total', rt.totalFiles > 0 ? `${rt.totalFiles}` : '-');
    params.set('bytesDone', UploadTransferHelper.formatBytes(rt.doneBytes));
    params.set('bytesTotal', rt.totalBytes > 0 ? UploadTransferHelper.formatBytes(rt.totalBytes) : '-');
    return params;
  }

  private progressText(): string {
    return L10n.t('photo_backup_progress', '@done/@total · @bytesDone / @bytesTotal',
      this.progressParams());
  }

  build() {
    GlassCard({ padValue: 12, cornerRadius: 14 }) {
      Column() {
        // 行 1：名称 + 状态
        Row() {
          Text(this.task.name)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.statusText())
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.statusColor())
            .margin({ left: 8 })
        }
        .width('100%')

        this.KvRow(L10n.t('photo_backup_source', '要备份的相册'),
          `${this.sourceTypeText()} · ${this.task.sourceName}`)
        this.KvRow(L10n.t('photo_backup_target', '目标文件夹'), this.task.targetDir)
        this.KvRow(L10n.t('folder_name_strategy', '同名文件策略'),
          L10n.t(this.task.nameStrategy, this.task.nameStrategy))
        this.KvRow(L10n.t('upload_center_save_type', '保存类型'), this.saveTypeText())

        if (this.runtime().running) {
          Progress({ value: this.runtime().progress ?? 0, total: 1, type: ProgressType.Linear })
            .color(this.palette().primary)
            .width('100%')
            .height(6)
            .margin({ top: 10 })
          Text(this.progressText())
            .fontSize(13)
            .fontColor(this.palette().subText)
            .width('100%')
            .margin({ top: 6 })
          if (this.runtime().currentFile.trim().length > 0) {
            Text(this.runtime().currentFile.trim())
              .fontSize(13)
              .fontColor(this.palette().subText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 2 })
          }
        }
        if (this.runtime().error.trim().length > 0 && !this.runtime().running) {
          Text(this.runtime().error.trim())
            .fontSize(13)
            .fontColor(this.palette().error)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 6 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .onClick((): void => {
        this.showActions();
      })
    }
  }

  @Builder
  KvRow(k: string, v: string) {
    Row() {
      Text(k)
        .fontSize(13)
        .fontColor(this.palette().subText)
        .width(100)
      Text(v)
        .fontSize(13)
        .fontColor(this.palette().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 4 })
  }

  /** 动作弹层（对齐 Flutter _showActions showModalBottomSheet） */
  private showActions(): void {
    const rt = this.ctrl.runtimeOf(this.task.id);
    const p = new TaskActionsSheetParams();
    p.task = this.task;
    p.running = rt.running;
    p.onEdit = (): void => {
      const pp = new PhotoBackupTaskFormPageParam();
      pp.initial = this.task;
      NavUtil.push(PhotoBackupRoutes.PAGE_EDIT, pp);
    };
    p.onUploadNew = (): void => {
      void this.ctrl.runUploadNew(this.task.id);
    };
    p.onUploadAll = (): void => {
      void this.confirmUploadAll();
    };
    p.onRuns = (): void => {
      showPhotoBackupRunsDialog(this.ctrl, this.task, false);
    };
    p.onFileLogs = (): void => {
      showPhotoBackupRunsDialog(this.ctrl, this.task, true);
    };
    p.onStop = (): void => {
      this.ctrl.cancelTask(this.task.id);
    };
    p.onDelete = (): void => {
      void this.confirmDelete();
    };
    SheetUtil.present(p, wrapBuilder(TaskActionsSheetContent));
  }

  /** 上传全部二次确认（对齐 Flutter DialogUtil.showConfirmDialog） */
  private async confirmUploadAll(): Promise<void> {
    await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('photo_backup_upload_all_confirm',
        '将尝试重新上传所有文件并清除本地已有上传记录，是否确认？'),
      (): void => {
        void this.ctrl.runUploadAll(this.task.id);
      });
  }

  /** 删除任务二次确认（对齐 Flutter photo_backup_delete_task_confirm） */
  private async confirmDelete(): Promise<void> {
    await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('photo_backup_delete_task_confirm', '确定删除备份任务“@name”吗？',
        L10n.paramsOf('name', this.task.name)),
      (): void => {
        void this.ctrl.deleteTask(this.task.id);
      });
  }
}

// ============================================================
// 任务动作底部弹层（对齐 Flutter showModalBottomSheet + ListTile）
// ============================================================

class TaskActionsSheetParams extends SheetParamsBase {
  task: PhotoBackupTask = new PhotoBackupTask();
  running: boolean = false;
  onEdit: () => void = (): void => {
  };
  onUploadNew: () => void = (): void => {
  };
  onUploadAll: () => void = (): void => {
  };
  onRuns: () => void = (): void => {
  };
  onFileLogs: () => void = (): void => {
  };
  onStop: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function TaskActionsSheetContent(p: TaskActionsSheetParams) {
  Column() {
    SheetHandle()
    Column() {
      ActionItem({
        icon: $r('sys.symbol.square_and_pencil'),
        title: L10n.t('edit', '编辑'),
        isEnabled: !p.running,
        onTap: (): void => {
          p.close();
          p.onEdit();
        }
      })
      ActionItem({
        icon: $r('sys.symbol.upload'),
        title: L10n.t('photo_backup_upload_new', '上传新增文件'),
        isEnabled: true,
        onTap: (): void => {
          p.close();
          p.onUploadNew();
        }
      })
      ActionItem({
        icon: $r('sys.symbol.cloud'),
        title: L10n.t('photo_backup_upload_all', '上传全部文件'),
        isEnabled: true,
        onTap: (): void => {
          p.close();
          p.onUploadAll();
        }
      })
      ActionItem({
        icon: $r('sys.symbol.clock'),
        title: L10n.t('photo_backup_runs', '查看备份记录'),
        isEnabled: true,
        onTap: (): void => {
          p.close();
          p.onRuns();
        }
      })
      ActionItem({
        icon: $r('sys.symbol.list_bullet'),
        title: L10n.t('photo_backup_file_logs', '查看文件上传记录'),
        isEnabled: true,
        onTap: (): void => {
          p.close();
          p.onFileLogs();
        }
      })
      if (p.running) {
        ActionItem({
          icon: $r('sys.symbol.stop_circle'),
          title: L10n.t('file_backup_stop', '停止'),
          isEnabled: true,
          onTap: (): void => {
            p.close();
            p.onStop();
          }
        })
      }
      ActionItem({
        icon: $r('sys.symbol.trash'),
        title: L10n.t('delete', '删除'),
        isEnabled: !p.running,
        onTap: (): void => {
          p.close();
          p.onDelete();
        }
      })
    }
    .width('100%')
    .padding({ top: 4, bottom: 24 })
  }
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

/** 弹层动作项：禁用时半透明且不可点（对齐 Flutter ListTile onTap: null） */
@ComponentV2
struct ActionItem {
  @Param icon: Resource = $r('sys.symbol.plus');
  @Param title: string = '';
  @Param isEnabled: boolean = true;
  @Param onTap: () => void = (): void => {
  };

  build() {
    Row({ space: 14 }) {
      SymbolGlyph(this.icon)
        .fontSize(22)
        .fontColor([AppTheme.current().onSurface])
      Text(this.title)
        .fontSize(15)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 13, bottom: 13 })
    .opacity(this.isEnabled ? 1 : 0.4)
    .onClick(() => {
      if (this.isEnabled) {
        this.onTap();
      }
    })
  }
}
