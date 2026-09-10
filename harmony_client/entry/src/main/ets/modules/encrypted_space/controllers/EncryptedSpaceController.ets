import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { EncryptedSpaceActiveSpace } from '../models/EncryptedSpaceModels';
import {
  EncryptedSpaceApiService, encryptedExportTaskStatusLabel
} from '../services/EncryptedSpaceApiService';

/** 导出任务条目（对齐 Flutter exportTasks Map 的常用字段） */
@ObservedV2
export class EncryptedExportTaskItem {
  @Trace id: number = 0;
  @Trace spaceId: number = 0;
  @Trace targetPath: string = '';
  @Trace statusRaw: string = '';
  @Trace progress: string = '';
  @Trace doneFiles: number = 0;
  @Trace totalFiles: number = 0;
  @Trace lastError: string = '';

  statusLabel(): string {
    return encryptedExportTaskStatusLabel(this.statusRaw);
  }

  countText(): string {
    if (this.totalFiles > 0) {
      return `${this.doneFiles}/${this.totalFiles}`;
    }
    return this.doneFiles > 0 ? `${this.doneFiles}` : '';
  }

  subtitle(): string {
    const parts: string[] = [];
    if (this.progress.length > 0) {
      parts.push(this.progress);
    }
    const count = this.countText();
    if (count.length > 0) {
      parts.push(count);
    }
    parts.push(this.statusLabel());
    return parts.join(' · ');
  }
}

/** 空间条目（对齐 Flutter spaces Map 的常用字段） */
@ObservedV2
export class EncryptedSpaceEntry {
  @Trace id: number = 0;
  @Trace name: string = '';
  @Trace path: string = '';

  displayTitle(): string {
    return this.name.trim().length > 0 ? this.name : L10n.t('name', '名称');
  }
}

export function encryptedSpaceEntryFrom(rec: Record<string, Object>): EncryptedSpaceEntry {
  const it = new EncryptedSpaceEntry();
  it.id = EncryptedSpaceController.toInt(rec['id']);
  it.name = `${rec['space_name'] ?? ''}`.trim();
  it.path = `${rec['folderPath'] ?? rec['folder_path'] ?? rec['path'] ?? rec['space_path'] ?? ''}`.trim();
  return it;
}

/**
 * 加密空间主控制器（对齐 Flutter EncryptedSpaceController）：
 * 空间列表刷新、打开/关闭活动空间、创建/导入/重命名/删除/导出空间、导出任务管理。
 * 创建/导入/导出对话框由组件层弹出并调用本控制器的 submit 方法（对齐 Flutter 对话框 onSubmit 回调）。
 */
@ObservedV2
export class EncryptedSpaceController {
  @Trace spaces: EncryptedSpaceEntry[] = [];
  @Trace isLoading: boolean = false;
  @Trace errorText: string = '';
  @Trace activeSpace: EncryptedSpaceActiveSpace | undefined = undefined;
  @Trace exportTasks: EncryptedExportTaskItem[] = [];
  @Trace exportTasksLoading: boolean = false;
  @Trace exportTasksErrorText: string = '';
  /** 导出任务弹层轮询定时器 */
  private exportTaskTimerId: number = -1;

  static toInt(v: Object | undefined | null): number {
    if (v === undefined || v === null) {
      return 0;
    }
    if (typeof v === 'number') {
      return Math.trunc(v);
    }
    const n = Number(`${v}`);
    return Number.isFinite(n) ? Math.trunc(n) : 0;
  }

  /** 页面销毁时调用：关闭活动空间并静默释放 token（对齐 onClose） */
  release(): void {
    this.stopExportTaskTimer();
    const closingSpaceId = this.activeSpace?.spaceId ?? 0;
    this.activeSpace = undefined;
    if (closingSpaceId > 0) {
      void this.deleteTokenSilently(closingSpaceId);
    }
  }

  async refreshList(showLoading: boolean = true): Promise<void> {
    this.isLoading = true;
    this.errorText = '';
    try {
      if (showLoading) {
        await DialogUtil.showLoading(L10n.loading);
      }
      const res = await EncryptedSpaceApiService.list();
      if (!res.success) {
        this.errorText = res.message.length > 0 ? res.message : L10n.operationFailed;
        this.spaces = [];
        return;
      }
      const list: EncryptedSpaceEntry[] = [];
      for (const raw of res.data ?? []) {
        list.push(encryptedSpaceEntryFrom(raw as Record<string, Object>));
      }
      this.spaces = list;
      const currentActiveId = this.activeSpace?.spaceId;
      if (currentActiveId !== undefined) {
        let found = false;
        for (const s of list) {
          if (s.id === currentActiveId) {
            found = true;
            break;
          }
        }
        if (!found) {
          this.activeSpace = undefined;
        }
      }
    } catch (_e) {
      this.errorText = L10n.operationFailed;
      this.spaces = [];
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading(true);
      }
      this.isLoading = false;
    }
  }

  async refreshExportTasks(showLoading: boolean = false): Promise<void> {
    this.exportTasksLoading = true;
    this.exportTasksErrorText = '';
    try {
      if (showLoading) {
        await DialogUtil.showLoading(L10n.loading);
      }
      const res = await EncryptedSpaceApiService.exportTaskList();
      if (!res.success) {
        this.exportTasksErrorText = res.message.length > 0 ? res.message : L10n.operationFailed;
        this.exportTasks = [];
        return;
      }
      const list: EncryptedExportTaskItem[] = [];
      for (const raw of res.data ?? []) {
        const rec = raw as Record<string, Object>;
        const it = new EncryptedExportTaskItem();
        it.id = EncryptedSpaceController.toInt(rec['id']);
        it.spaceId = EncryptedSpaceController.toInt(rec['space_id']);
        it.targetPath = `${rec['target_path'] ?? ''}`.trim();
        it.statusRaw = `${rec['status'] ?? ''}`.trim();
        it.progress = `${rec['progress'] ?? ''}`.trim();
        it.doneFiles = EncryptedSpaceController.toInt(rec['done_files']);
        it.totalFiles = EncryptedSpaceController.toInt(rec['total_files']);
        it.lastError = `${rec['last_error'] ?? ''}`.trim();
        list.push(it);
      }
      this.exportTasks = list;
    } catch (_e) {
      this.exportTasksErrorText = L10n.operationFailed;
      this.exportTasks = [];
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading(true);
      }
      this.exportTasksLoading = false;
    }
  }

  openActiveSpace(space: EncryptedSpaceActiveSpace): void {
    this.activeSpace = space;
  }

  /** 关闭活动空间并静默释放 token（对齐 closeActiveSpace / detail 页返回） */
  closeActiveSpace(): void {
    const closingSpaceId = this.activeSpace?.spaceId ?? 0;
    this.activeSpace = undefined;
    if (closingSpaceId > 0) {
      void this.deleteTokenSilently(closingSpaceId);
    }
  }

  private async deleteTokenSilently(spaceId: number): Promise<void> {
    try {
      await EncryptedSpaceApiService.deleteToken(spaceId);
    } catch (_e) {
      // 静默失败（对齐 Flutter _deleteTokenSilently）
    }
  }

  // ===== 导出任务弹层轮询（对齐 showExportTasksDialog 的 Timer.periodic） =====

  startExportTaskTimer(onTick: () => void): void {
    this.stopExportTaskTimer();
    this.exportTaskTimerId = setInterval((): void => {
      void this.refreshExportTasks(false);
      onTick();
    }, 1200);
  }

  stopExportTaskTimer(): void {
    if (this.exportTaskTimerId >= 0) {
      clearInterval(this.exportTaskTimerId);
      this.exportTaskTimerId = -1;
    }
  }

  // ===== 提交类方法（由对话框组件调用，对齐 Flutter 对话框 onSubmit 内逻辑） =====

  /** 提交创建空间（对齐 createSpaceFlow onSubmit） */
  async submitCreateSpace(name: string, pwd: string, folderPath: string): Promise<boolean> {
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.addSpace(folderPath.trim(), name, pwd);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return false;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.refreshList(false);
      return true;
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  /** 提交导入空间（对齐 importSpaceFlow onSubmit） */
  async submitImportSpace(name: string, pwd: string, folderPath: string): Promise<boolean> {
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.importSpace(folderPath.trim(), name, pwd);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return false;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.refreshList(false);
      return true;
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  /** 提交导出任务（对齐 exportSpaceFlow onSubmit） */
  async submitExportSpace(spaceId: number, pwd: string, targetPath: string): Promise<boolean> {
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.addExportTask(spaceId, pwd, targetPath);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return false;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.refreshExportTasks(false);
      return true;
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  async deleteExportTaskFlow(id: number): Promise<void> {
    if (id <= 0) {
      return;
    }
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      `${L10n.t('confirm_delete', '确认删除')} #${id}`,
      undefined, L10n.t('delete', '删除'), L10n.cancel);
    if (ok !== true) {
      return;
    }
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.deleteExportTask(id);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.refreshExportTasks(false);
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  async clearFinishedExportTasksFlow(): Promise<void> {
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('encrypted_space_export_clear_finished_confirm', '清理已完成的导出任务？'),
      undefined, L10n.t('delete', '删除'), L10n.cancel);
    if (ok !== true) {
      return;
    }
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.clearFinishedExportTasks();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.refreshExportTasks(false);
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  /** 打开空间：密码校验成功后回调（对齐 openSpaceFlow） */
  openSpaceFlow(space: EncryptedSpaceEntry, onSuccess: (data: Record<string, Object>) => void): void {
    const id = space.id;
    if (id <= 0) {
      return;
    }
    DialogUtil.showPasswordInputDialog(
      L10n.t('password', '密码'), L10n.inputPlease, (pwd: string): void => {
        const p = pwd.trim();
        if (p.length === 0) {
          return;
        }
        void this.checkPwdAndOpen(id, p, onSuccess);
      },
      L10n.ok, L10n.cancel);
  }

  private async checkPwdAndOpen(id: number, pwd: string,
    onSuccess: (data: Record<string, Object>) => void): Promise<void> {
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.checkPwd(id, pwd);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      if (res.data !== undefined) {
        onSuccess(res.data);
      }
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  /** 重命名空间（对齐 renameSpaceFlow） */
  async renameSpaceFlow(space: EncryptedSpaceEntry): Promise<void> {
    const id = space.id;
    if (id <= 0) {
      return;
    }
    const currentName = space.name.trim();
    const name = await DialogUtil.showInputDialog(
      L10n.t('rename', '重命名'), L10n.inputPlease, currentName, L10n.ok, L10n.cancel,
      (v: string): string | undefined => {
        const t = v.trim();
        if (t.length === 0) {
          return L10n.t('name_cannot_be_empty', '名称不能为空');
        }
        if (t.length > 30) {
          return L10n.operationFailed;
        }
        return undefined;
      });
    const next = (typeof name === 'string' ? name : '').trim();
    if (next.length === 0 || next === currentName) {
      return;
    }
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.updateSpaceName(id, next);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.refreshList(false);
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }

  /** 删除空间（对齐 deleteSpaceFlow） */
  async deleteSpaceFlow(space: EncryptedSpaceEntry): Promise<void> {
    const id = space.id;
    if (id <= 0) {
      return;
    }
    const name = space.name.trim();
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      `${L10n.t('confirm_delete', '确认删除')}[${name.length > 0 ? name : id}]`,
      undefined, L10n.t('delete', '删除'), L10n.cancel);
    if (ok !== true) {
      return;
    }
    await DialogUtil.showLoading(L10n.loading);
    try {
      const res = await EncryptedSpaceApiService.deleteSpace(id);
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed', '删除失败'));
        return;
      }
      ToastUtil.show(L10n.t('delete_success', '删除成功'));
      if (this.activeSpace?.spaceId === id) {
        this.activeSpace = undefined;
      }
      await this.refreshList(false);
    } finally {
      await DialogUtil.dismissLoading(true);
    }
  }
}
