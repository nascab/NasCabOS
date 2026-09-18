import { APIClient } from '../../../core/network/APIClient';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { L10n } from '../../../core/localization/L10n';
import { NetworkStatus } from '../../../core/network/NetworkStatus';
import { BackgroundWorkKeeper } from '../../../core/background/BackgroundWorkKeeper';
import { TransferNotificationHub } from '../../../core/notification/TransferNotificationHub';
import { ToastUtil } from '../../../common/ToastUtil';
import { UploadTransferHelper } from '../../../transfer/utils/UploadTransferHelper';
import { TransferStatus, TransferTask } from '../../../transfer/models/TransferModels';
import { UploadCancellationToken, UploadCore, ProcessFileParams } from '../../../transfer/controllers/UploadCore';
import {
  PhotoBackupCursor, PhotoBackupFileRecord, PhotoBackupRunRecord,
  PhotoBackupRunTrigger, PhotoBackupSourceType, PhotoBackupTask, PhotoSourceEntry
} from '../models/PhotoBackupModels';
import { PhotoBackupStorage } from '../storage/PhotoBackupStorage';
import { PhotoAlbumService } from '../services/PhotoAlbumService';

/**
 * 单次备份运行的计数器（对齐 Flutter _run 内局部变量 successCount/failedCount/consumedBytes）
 */
class RunCounters {
  successCount: number = 0;
  failedCount: number = 0;
  consumedBytes: number = 0;
}

/**
 * 相册备份运行时状态（对齐 Flutter PhotoBackupRuntime）：
 * progress 有总大小时按字节，否则按文件数；都未知时返回 undefined（UI 显示 indeterminate）。
 */
@ObservedV2
export class PhotoBackupRuntime {
  @Trace running: boolean = false;
  @Trace status: string = 'idle';
  @Trace currentFile: string = '';
  @Trace totalFiles: number = 0;
  @Trace doneFiles: number = 0;
  @Trace totalBytes: number = 0;
  @Trace doneBytes: number = 0;
  @Trace error: string = '';

  get progress(): number | undefined {
    if (this.totalBytes > 0) {
      if (this.doneBytes <= 0) {
        return 0;
      }
      if (this.doneBytes >= this.totalBytes) {
        return 1;
      }
      return this.doneBytes / this.totalBytes;
    }
    if (this.totalFiles > 0) {
      if (this.doneFiles <= 0) {
        return 0;
      }
      if (this.doneFiles >= this.totalFiles) {
        return 1;
      }
      return this.doneFiles / this.totalFiles;
    }
    return undefined;
  }
}

/**
 * 相册备份控制器（对齐 Flutter PhotoBackupController）：
 * - 任务 CRUD 走 PhotoBackupStorage（本地四表）
 * - 三条上传分支：相册+上传全部（流式分页80）、相册+上传新增有 cursor（Meta 按需解析）、其余（全量扫描）
 * - 后台保活 BackgroundWorkKeeper + 通知栏进度 TransferNotificationHub
 * - 自动备份仅在确认连接后且 WiFi 下触发
 */
@ObservedV2
export class PhotoBackupController {
  /** 模块级单例（对齐 Flutter Get.put(permanent: true)）：首页/登出等全局钩子与页面共用同一实例 */
  private static instance: PhotoBackupController | undefined = undefined;

  static getInstance(): PhotoBackupController {
    if (PhotoBackupController.instance === undefined) {
      PhotoBackupController.instance = new PhotoBackupController();
    }
    return PhotoBackupController.instance;
  }

  @Trace tasks: PhotoBackupTask[] = [];
  @Trace loading: boolean = false;

  private readonly storage: PhotoBackupStorage = new PhotoBackupStorage();
  private readonly runtimeMap: Map<number, PhotoBackupRuntime> = new Map();
  private readonly cancelTokens: Map<number, UploadCancellationToken> = new Map();
  private lastIdentityKey: string = '';
  private lastAutoTriggerIdentityKey: string = '';

  // ============================================================
  // 运行时 & 通知
  // ============================================================

  runtimeOf(taskId: number): PhotoBackupRuntime {
    let runtime = this.runtimeMap.get(taskId);
    if (runtime === undefined) {
      runtime = new PhotoBackupRuntime();
      this.runtimeMap.set(taskId, runtime);
    }
    return runtime;
  }

  private syncBackupWorkNotification(runtime: PhotoBackupRuntime): void {
    void TransferNotificationHub.photoBackupProgressThrottled(
      runtime.currentFile, runtime.progress, runtime.doneFiles, runtime.totalFiles);
  }

  /** 从异常中取错误文案，取消类统一返回“用户已取消”（对齐 Flutter _errorMessage） */
  private errorMessage(e: Error): string {
    if (e.message === 'upload_cancelled') {
      return L10n.t('photo_backup_manual_cancel', '已手动取消');
    }
    return UploadTransferHelper.getDisplayMessage(e.message);
  }

  // ============================================================
  // 身份 & 会话
  // ============================================================

  private identityServerId(): string {
    return APIClient.getInstance().state.serverId.trim();
  }

  private identityUserId(): number {
    return CurrentUserStore.getInstance().current?.id ?? 0;
  }

  async refreshTasks(): Promise<void> {
    this.loading = true;
    try {
      const list = await this.storage.listTasks(this.identityServerId(), this.identityUserId());
      this.tasks = list;
    } finally {
      this.loading = false;
    }
  }

  private async autoStartTasksOnLaunch(): Promise<void> {
    const ids: number[] = [];
    for (const t of this.tasks) {
      if (t.autoStartOnLaunch) {
        ids.push(t.id);
      }
    }
    for (const taskId of ids) {
      await this.runUploadNew(taskId, PhotoBackupRunTrigger.AUTO_START);
    }
  }

  /**
   * 会话（服务器/用户）可能变化时：只刷新任务列表，不触发自动开始备份。
   * 自动开始备份仅在 onConnectionConfirmed 中触发，确保在登录/连接成功后再执行。
   */
  async onSessionMaybeChanged(): Promise<void> {
    const key = `${this.identityServerId()}#${this.identityUserId()}`;
    const changed = key !== this.lastIdentityKey;
    if (changed) {
      this.lastIdentityKey = key;
      await this.refreshTasks();
    } else if (this.tasks.length === 0) {
      await this.refreshTasks();
    }
  }

  /**
   * 在确认当前服务器连接可用后调用（登录成功或首页加载成功），
   * 「APP 打开时自动开启备份」开启的任务在此触发；移动端仅在 WiFi 下自动备份。
   */
  async onConnectionConfirmed(): Promise<void> {
    if (!APIClient.getInstance().isAuthenticated) {
      return;
    }
    const serverId = this.identityServerId();
    const userId = this.identityUserId();
    const key = `${serverId}#${userId}`;
    if (serverId.length === 0 || userId <= 0) {
      return;
    }
    if (this.lastAutoTriggerIdentityKey === key) {
      return;
    }
    if (!NetworkStatus.isOnWifi()) {
      return;
    }
    this.lastAutoTriggerIdentityKey = key;
    await this.refreshTasks();
    await this.autoStartTasksOnLaunch();
  }

  // ============================================================
  // 任务 CRUD
  // ============================================================

  async saveTask(id: number, sourceType: PhotoBackupSourceType, sourceId: string, sourceName: string,
    targetDir: string, nameStrategy: string, saveType: string, uploadLivePhotoVideo: boolean,
    autoStartOnLaunch: boolean): Promise<boolean> {
    if (sourceId.trim().length === 0 || sourceName.trim().length === 0 || targetDir.trim().length === 0) {
      ToastUtil.show(L10n.t('photo_backup_required', '请填写完整信息'));
      return false;
    }
    if (this.identityServerId().length === 0 || this.identityUserId() <= 0) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return false;
    }
    const task = new PhotoBackupTask();
    task.id = id;
    task.serverId = this.identityServerId();
    task.userId = this.identityUserId();
    task.name = sourceName.trim();
    task.sourceType = sourceType;
    task.sourceId = sourceId.trim();
    task.sourceName = sourceName.trim();
    task.targetDir = targetDir.trim();
    task.nameStrategy = nameStrategy.trim().length === 0 ? 'skip' : nameStrategy.trim();
    task.saveType = saveType.trim();
    task.uploadLivePhotoVideo = uploadLivePhotoVideo;
    task.autoStartOnLaunch = autoStartOnLaunch;
    if (id > 0) {
      const old = this.tasks.find((t: PhotoBackupTask): boolean => t.id === id);
      if (old !== undefined) {
        task.createdAtMs = old.createdAtMs;
      }
    }
    await this.storage.upsertTask(task);
    await this.refreshTasks();
    return true;
  }

  async deleteTask(taskId: number): Promise<void> {
    this.cancelTask(taskId);
    await this.storage.deleteTask(taskId);
    const idx = this.tasks.findIndex((t: PhotoBackupTask): boolean => t.id === taskId);
    if (idx >= 0) {
      this.tasks.splice(idx, 1);
    }
  }

  cancelTask(taskId: number): void {
    const token = this.cancelTokens.get(taskId);
    if (token !== undefined && !token.isCancelled()) {
      token.cancel();
    }
  }

  /** 登出或切换服务器前调用：取消所有进行中的相册备份上传（对齐 Flutter cancelAllRunning） */
  cancelAllRunning(): void {
    for (const t of this.tasks) {
      if (this.runtimeOf(t.id).running) {
        this.cancelTask(t.id);
      }
    }
  }

  async listRuns(taskId: number): Promise<PhotoBackupRunRecord[]> {
    return this.storage.listRuns(taskId);
  }

  async listRunFiles(runId: number): Promise<PhotoBackupFileRecord[]> {
    return this.storage.listRunFiles(runId);
  }

  async deleteRun(runId: number): Promise<void> {
    await this.storage.deleteRun(runId);
  }

  // ============================================================
  // 触发入口
  // ============================================================

  async runUploadNew(taskId: number, trigger: PhotoBackupRunTrigger = PhotoBackupRunTrigger.UPLOAD_NEW): Promise<void> {
    await this.run(taskId, false, trigger);
  }

  async runUploadAll(taskId: number): Promise<void> {
    await this.run(taskId, true, PhotoBackupRunTrigger.UPLOAD_ALL);
  }

  // ============================================================
  // 单文件上传（三分支共用，对齐 Flutter _run 中重复的 processFile 调用块）
  // ============================================================

  private async uploadOne(item: PhotoSourceEntry, task: PhotoBackupTask, runId: number,
    cancelToken: UploadCancellationToken, runtime: PhotoBackupRuntime,
    counters: RunCounters): Promise<boolean> {
    if (cancelToken.isCancelled()) {
      throw new Error('upload_cancelled');
    }
    runtime.currentFile = item.displayName;
    this.syncBackupWorkNotification(runtime);
    const uploadedAt = Date.now();
    let status = 'success';
    let error = '';
    try {
      const fileHash = await UploadTransferHelper.sha256Hex(
        `${item.sourceUniqueId}|${item.size}|${item.fileMtimeMs}`);
      const relPath = task.sourceName.length > 0 ? `${task.sourceName}/${item.relativePath}` : item.relativePath;
      const transferTask = new TransferTask('', item.displayName, item.localUri, task.targetDir,
        item.size, TransferStatus.PENDING, 0);
      transferTask.fileHash = fileHash;
      const params = new ProcessFileParams();
      params.task = transferTask;
      params.nameStrategy = task.nameStrategy;
      params.saveType = task.saveType;
      params.mtimeMs = item.fileMtimeMs;
      params.relativePath = relPath;
      params.birthtimeMs = item.orderMs > 0 ? item.orderMs : 0;
      params.onProgress = (increment: number): void => {
        runtime.doneBytes += increment;
        this.syncBackupWorkNotification(runtime);
      };
      params.onSkipped = (): void => {
        // FILE_EXISTS：视为成功跳过（与 Flutter 上传核心行为一致）
      };
      params.cancelToken = cancelToken;
      await UploadCore.processFile(params);
      counters.successCount += 1;
      counters.consumedBytes += item.size;
      await this.storage.upsertCursor(task.id, item.orderMs, item.sourceUniqueId);
    } catch (e) {
      status = 'error';
      error = this.errorMessage(e instanceof Error ? e : new Error(`${e}`));
      runtime.error = error;
      counters.failedCount += 1;
    } finally {
      const record = new PhotoBackupFileRecord();
      record.taskId = task.id;
      record.runId = runId;
      record.sourceUniqueId = item.sourceUniqueId;
      record.displayName = item.displayName;
      record.localPath = item.localUri;
      record.size = item.size;
      record.sourceCreateAtMs = item.orderMs;
      record.uploadedAtMs = uploadedAt;
      record.status = status;
      record.error = error;
      await this.storage.insertFileRecord(record);
      // 实况视频轨等沙盒临时文件用完即删
      await PhotoAlbumService.maybeDeleteSandboxTempFile(item.localUri);
      runtime.doneFiles += 1;
      if (runtime.totalBytes > 0 && runtime.doneBytes > runtime.totalBytes) {
        runtime.doneBytes = runtime.totalBytes;
      }
    }
    return status !== 'error';
  }

  private async finishRunSilently(runId: number, counters: RunCounters): Promise<void> {
    await this.storage.finishRun(runId, Date.now(), counters.successCount, counters.failedCount,
      counters.consumedBytes);
  }

  // ============================================================
  // 主流程（对齐 Flutter _run 三分支）
  // ============================================================

  private async run(taskId: number, modeAll: boolean, trigger: PhotoBackupRunTrigger): Promise<void> {
    const task = this.tasks.find((t: PhotoBackupTask): boolean => t.id === taskId);
    if (task === undefined) {
      return;
    }
    const runtime = this.runtimeOf(task.id);
    if (runtime.running) {
      return;
    }

    const token = APIClient.getInstance().accessToken?.trim() ?? '';
    if (token.length === 0) {
      runtime.error = L10n.t('network_failure', '网络连接失败');
      runtime.status = 'error';
      return;
    }

    runtime.running = true;
    runtime.status = 'running';
    runtime.error = '';
    runtime.currentFile = '';
    runtime.totalBytes = 0;
    runtime.doneBytes = 0;
    runtime.totalFiles = 0;
    runtime.doneFiles = 0;

    void BackgroundWorkKeeper.acquire();
    void TransferNotificationHub.backupWorkBegan();

    const cancelToken = new UploadCancellationToken();
    const prev = this.cancelTokens.get(task.id);
    if (prev !== undefined) {
      prev.cancel();
    }
    this.cancelTokens.set(task.id, cancelToken);

    let runId = 0;
    const counters = new RunCounters();
    try {
      if (modeAll) {
        await this.storage.clearTaskRecords(task.id);
      }
      runId = await this.storage.createRun(task.id, trigger, Date.now());
      const cursor = modeAll ? undefined : await this.storage.loadCursor(task.id);

      // 分支一：仅「上传全部」时按页流式上传，可随时开始、随时结束（对齐 Flutter album+uploadAll streaming）
      if (task.sourceType === PhotoBackupSourceType.ALBUM && modeAll) {
        runtime.totalFiles = 0;
        runtime.totalBytes = 0;
        await PhotoAlbumService.scanAlbumBatched(task, undefined, async (batch: PhotoSourceEntry[]): Promise<boolean> => {
          for (const item of batch) {
            const ok = await this.uploadOne(item, task, runId, cancelToken, runtime, counters);
            if (!ok) {
              break;
            }
          }
          return counters.failedCount === 0;
        });
        await this.finishRunSilently(runId, counters);
        runtime.status = counters.failedCount > 0 ? 'error' : 'idle';
        return;
      }

      // 分支二：相册 + 上传新增 + 有 cursor：只拉待上传 Meta 列表，上传时再按需解析（对齐 Flutter scanAlbumPendingMeta）
      if (task.sourceType === PhotoBackupSourceType.ALBUM && !modeAll && cursor !== undefined) {
        const pendingMetaList = await PhotoAlbumService.scanAlbumPendingMeta(task, cursor);
        if (pendingMetaList.length === 0) {
          await this.finishRunSilently(runId, counters);
          runtime.error = '';
          runtime.status = 'idle';
          runtime.running = false;
          if (trigger === PhotoBackupRunTrigger.UPLOAD_NEW) {
            ToastUtil.show(L10n.t('photo_backup_no_new_files', '没有新文件'));
          }
          return;
        }
        runtime.totalFiles = pendingMetaList.length;
        runtime.totalBytes = 0;
        for (const m of pendingMetaList) {
          if (cancelToken.isCancelled()) {
            throw new Error('upload_cancelled');
          }
          const entries: PhotoSourceEntry[] = await PhotoAlbumService.resolveAlbumMetaToEntries(m, task);
          for (const item of entries) {
            const ok = await this.uploadOne(item, task, runId, cancelToken, runtime, counters);
            if (!ok) {
              break;
            }
          }
          if (counters.failedCount > 0) {
            break;
          }
        }
        await this.finishRunSilently(runId, counters);
        runtime.status = counters.failedCount > 0 ? 'error' : 'idle';
        return;
      }

      // 分支三：相册全量 / 文件夹：先拿到完整条目列表再上传（对齐 Flutter scanAlbum/scanFolder）
      const sourceEntries = task.sourceType === PhotoBackupSourceType.ALBUM
        ? await PhotoAlbumService.scanAlbum(task)
        : await PhotoAlbumService.scanFolder(task.sourceId);
      if (sourceEntries.length === 0) {
        await this.finishRunSilently(runId, counters);
        runtime.error = task.sourceType === PhotoBackupSourceType.ALBUM
          ? L10n.t('photo_backup_no_files_album', '相册中没有文件')
          : L10n.t('photo_backup_no_files_folder', '文件夹中没有文件');
        runtime.status = 'idle';
        runtime.running = false;
        return;
      }

      const pending: PhotoSourceEntry[] = sourceEntries.filter((entry: PhotoSourceEntry): boolean => {
        if (cursor === undefined) {
          return true;
        }
        if (entry.orderMs > cursor.lastCreatedAtMs) {
          return true;
        }
        if (entry.orderMs < cursor.lastCreatedAtMs) {
          return false;
        }
        return entry.sourceUniqueId > cursor.lastUniqueId;
      });

      if (pending.length === 0) {
        await this.finishRunSilently(runId, counters);
        runtime.status = 'idle';
        runtime.running = false;
        return;
      }

      runtime.totalFiles = pending.length;
      runtime.totalBytes = 0;
      for (const item of pending) {
        const ok = await this.uploadOne(item, task, runId, cancelToken, runtime, counters);
        if (!ok) {
          break;
        }
      }

      await this.finishRunSilently(runId, counters);
      runtime.status = counters.failedCount > 0 ? 'error' : 'idle';
    } catch (e) {
      const err = e instanceof Error ? e : new Error(`${e}`);
      if (runId > 0) {
        await this.storage.finishRun(runId, Date.now(), counters.successCount,
          counters.failedCount > 0 ? counters.failedCount : 1, counters.consumedBytes);
      }
      if (err.message === 'photo_backup_permission_denied') {
        // 权限被拒已在扫描前 toast 引导，卡片上不显示错误（对齐 Flutter _PhotoBackupPermissionDeniedException）
        runtime.status = 'idle';
        runtime.error = '';
      } else if (err.message === 'upload_cancelled') {
        runtime.status = 'idle';
        runtime.error = L10n.t('photo_backup_manual_cancel', '已手动取消');
      } else {
        runtime.status = 'error';
        runtime.error = this.errorMessage(err);
      }
    } finally {
      void TransferNotificationHub.backupWorkEnded();
      runtime.running = false;
      runtime.currentFile = '';
      this.cancelTokens.delete(task.id);
      void BackgroundWorkKeeper.release();
    }
  }
}
