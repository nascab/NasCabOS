import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { L10n } from '../../../core/localization/L10n';
import { BackupRecordsPayload, BackupTask } from '../models/FileBackupModels';
import { FileBackupApiService } from '../services/FileBackupApiService';

/**
 * 磁盘间备份控制器（对齐 Flutter FileBackupController）：
 * 页面创建时启动（立即刷新 + 3 秒轮询），页面销毁时停止（对齐 GetBuilder 生命周期）。
 */
@ObservedV2
export class FileBackupController {
  @Trace tasks: BackupTask[] = [];
  @Trace isLoading: boolean = false;
  @Trace errorText: string = '';
  /** 启停操作中的任务 id → loading（对齐 Flutter opLoadingById） */
  @Trace opLoadingById: Map<number, boolean> = new Map<number, boolean>();

  /** 轮询定时器（对齐 Flutter _pollTimer） */
  private pollTimer: number = -1;
  /** 进行中的刷新（对齐 Flutter _refreshCompleter 去重语义） */
  private refreshInflight: Promise<void> | undefined = undefined;

  /** 页面挂载（对齐 Flutter onInit：静默刷新一次 + 启动轮询） */
  start(): void {
    void this.refreshList(false, true, false);
    this.startPolling();
  }

  /** 页面销毁（对齐 Flutter onClose） */
  stop(): void {
    this.stopPolling();
  }

  private startPolling(): void {
    this.stopPolling();
    this.pollTimer = setInterval((): void => {
      void this.refreshList(false, false, false);
    }, 3000);
  }

  private stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  isOpLoading(id: number): boolean {
    return this.opLoadingById.get(id) === true;
  }

  /**
   * 刷新任务列表（对齐 Flutter refreshList）：
   * showLoading 是否弹加载框；clearOnFail 失败时是否清空列表；waitIfBusy 忙时是否等待。
   */
  async refreshList(showLoading: boolean = true, clearOnFail: boolean = true,
    waitIfBusy: boolean = true): Promise<void> {
    const inflight = this.refreshInflight;
    if (inflight !== undefined) {
      if (!waitIfBusy) {
        return;
      }
      await inflight;
    }
    const task = this.doRefresh(showLoading, clearOnFail);
    this.refreshInflight = task;
    try {
      await task;
    } finally {
      if (this.refreshInflight === task) {
        this.refreshInflight = undefined;
      }
    }
  }

  private async doRefresh(showLoading: boolean, clearOnFail: boolean): Promise<void> {
    this.isLoading = true;
    this.errorText = '';
    try {
      if (showLoading) {
        void DialogUtil.showLoading(L10n.loading);
      }
      const res = await FileBackupApiService.listTasks();
      if (!res.success) {
        this.errorText = res.message.length > 0 ? res.message : L10n.operationFailed;
        if (clearOnFail) {
          this.tasks = [];
        }
        return;
      }
      this.tasks = res.data !== undefined ? res.data : [];
    } catch (_e) {
      this.errorText = L10n.operationFailed;
      if (clearOnFail) {
        this.tasks = [];
      }
    } finally {
      if (showLoading) {
        void DialogUtil.dismissLoading(true);
      }
      this.isLoading = false;
    }
  }

  /** 新增/编辑任务（对齐 Flutter upsert：校验 → 提交 → 刷新 → toast） */
  async upsert(id: number | undefined, sourcePathList: string[], type: string,
    targetPath: string, frenquence: number, excludeList: string[]): Promise<boolean> {
    const sources: string[] = [];
    sourcePathList.forEach((e: string): void => {
      const v = e.trim();
      if (v.length > 0) {
        sources.push(v);
      }
    });
    const target = targetPath.trim();
    const t = type.trim();
    if (sources.length === 0 || target.length === 0 || frenquence <= 0) {
      ToastUtil.show(L10n.t('file_backup_required', '源目录/目标目录/频率不能为空'));
      return false;
    }
    if (t !== 'copy' && t !== 'sync') {
      ToastUtil.show(L10n.operationFailed);
      return false;
    }
    const excludes: string[] = [];
    excludeList.forEach((e: string): void => {
      const v = e.trim();
      if (v.length > 0) {
        excludes.push(v);
      }
    });
    const res = await FileBackupApiService.upsertTask(id, sources, t, target, frenquence, excludes);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return false;
    }
    await this.refreshList(false, true, true);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    return true;
  }

  /** 删除任务（确认弹窗 → 删除 → 刷新，对齐 Flutter remove） */
  async remove(id: number): Promise<boolean> {
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('file_backup_delete_confirm', '确定删除该备份任务吗？'),
      undefined, L10n.ok, L10n.cancel);
    if (confirmed !== true) {
      return false;
    }
    const res = await FileBackupApiService.deleteTask(id);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed', '删除失败'));
      return false;
    }
    await this.refreshList(false, true, true);
    ToastUtil.show(L10n.t('delete_success', '删除成功'));
    return true;
  }

  /** 启动任务（对齐 Flutter start：操作 loading → 刷新 → toast） */
  async startTask(id: number): Promise<void> {
    this.opLoadingById.set(id, true);
    const res = await FileBackupApiService.startTask(id);
    this.opLoadingById.set(id, false);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      await this.refreshList(false, false, true);
      return;
    }
    await this.refreshList(false, false, true);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 停止任务（对齐 Flutter stop） */
  async stopTask(id: number): Promise<void> {
    this.opLoadingById.set(id, true);
    const res = await FileBackupApiService.stopTask(id);
    this.opLoadingById.set(id, false);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      await this.refreshList(false, false, true);
      return;
    }
    await this.refreshList(false, false, true);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** 拉取备份记录（对齐 Flutter fetchBackupRecords：失败返回 undefined） */
  async fetchBackupRecords(taskId: number, page: number = 1,
    pageSize: number = 100): Promise<BackupRecordsPayload | undefined> {
    const res = await FileBackupApiService.listRecords(taskId, page, pageSize);
    if (!res.success) {
      return undefined;
    }
    return res.data;
  }
}
