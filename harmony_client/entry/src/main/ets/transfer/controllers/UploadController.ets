import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { CacheKeys } from '../../core/storage/CacheKeys';
import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { FileApiService, ServerDirAccessStatus } from '../../files/service/FileApiService';
import { MediaPickerUtil } from '../utils/MediaPickerUtil';
import { UriReader } from '../utils/UriReader';
import { TransferStatus, TransferTask } from '../models/TransferModels';
import { ProcessFileParams, UploadCancellationToken, UploadCore } from './UploadCore';
import { UploadTransferHelper } from '../utils/UploadTransferHelper';

const SAVE_TYPE_CACHE_KEY = 'app_upload_center_save_type';
const TARGET_DIR_CACHE_KEY = 'app_upload_center_target_dir';
const MAX_CONCURRENT = 1;

/**
 * 上传队列控制器（对齐 Flutter UploadController 移动端能力）：
 * - 任务列表响应式（@Trace），UI 自动刷新
 * - 串行队列（maxConcurrent=1）、暂停/继续/重试/删除/清空
 * - 同名文件策略（skip/overwrite/rename）与按日期保存类型持久化
 */
@ObservedV2
export class UploadController {
  static instance: UploadController | undefined = undefined;

  static getInstance(): UploadController {
    if (!UploadController.instance) {
      UploadController.instance = new UploadController();
    }
    return UploadController.instance;
  }

  @Trace tasks: TransferTask[] = [];
  @Trace nameStrategy: string = 'skip';
  @Trace saveType: string = '';
  @Trace isProcessingTargetCheck: boolean = false;

  private targetDir: string = '';
  private processingIds: string[] = [];
  private cancelTokens: Map<string, UploadCancellationToken> = new Map();
  private queueBusy: boolean = false;

  private constructor() {
    this.loadCachedOptions();
  }

  private loadCachedOptions(): void {
    const store = PreferencesStore.getInstance();
    const v = (store.getString(SAVE_TYPE_CACHE_KEY, '') ?? '').trim();
    if (v === 'year' || v === 'month' || v === 'day') {
      this.saveType = v;
    }
  }

  async setSaveType(type: string): Promise<void> {
    const v = type.trim().toLowerCase();
    if (v.length > 0 && v !== 'year' && v !== 'month' && v !== 'day') {
      return;
    }
    this.saveType = v;
    await PreferencesStore.getInstance().setString(SAVE_TYPE_CACHE_KEY, v);
  }

  // ===== 目标目录（对齐 MobileUploadCenterController） =====

  get currentTargetDir(): string {
    return this.targetDir;
  }

  get targetDirDisplay(): string {
    return this.targetDir.trim();
  }

  /** 初始化目标目录：优先使用入口带入目录，其次读缓存并校验 */
  async bootstrapTargetDir(dir: string): Promise<void> {
    const boot = dir.trim();
    if (boot.length > 0) {
      this.targetDir = boot;
      await PreferencesStore.getInstance().setString(TARGET_DIR_CACHE_KEY, boot);
      return;
    }
    await this.loadCachedTargetDir();
  }

  /** 校验并写入目标目录；不可写时弹提示引导重选（对齐 Flutter pickTargetDir） */
  async applyTargetDir(picked: string): Promise<void> {
    this.isProcessingTargetCheck = true;
    try {
      const status = await FileApiService.getInstance().checkServerDirAccess(picked);
      if (status === ServerDirAccessStatus.OK) {
        this.targetDir = picked;
        await PreferencesStore.getInstance().setString(TARGET_DIR_CACHE_KEY, picked);
        return;
      }
      await DialogUtil.showInfoDialog(L10n.tip,
        L10n.t('upload_center_target_cannot_upload', '此目录无法上传，请重新选择'));
    } finally {
      this.isProcessingTargetCheck = false;
    }
  }

  private async loadCachedTargetDir(): Promise<void> {
    const cached = (PreferencesStore.getInstance().getString(TARGET_DIR_CACHE_KEY, '') ?? '').trim();
    if (cached.length === 0) {
      return;
    }
    this.isProcessingTargetCheck = true;
    try {
      const status = await FileApiService.getInstance().checkServerDirAccess(cached);
      if (status !== ServerDirAccessStatus.OK) {
        await PreferencesStore.getInstance().remove(TARGET_DIR_CACHE_KEY);
        return;
      }
      this.targetDir = cached;
    } finally {
      this.isProcessingTargetCheck = false;
    }
  }

  // ===== 添加任务 =====

  /** 上传照片/视频（相册选择器） */
  async pickMediaAndEnqueue(): Promise<void> {
    const target = this.targetDir.trim();
    if (target.length === 0) {
      ToastUtil.show(L10n.t('quick_share_path_required', '请选择路径'));
      return;
    }
    const uris = await MediaPickerUtil.pickMedia();
    await this.enqueueUris(uris, target);
  }

  /** 上传任意文件（文档选择器） */
  async pickFilesAndEnqueue(): Promise<void> {
    const target = this.targetDir.trim();
    if (target.length === 0) {
      ToastUtil.show(L10n.t('quick_share_path_required', '请选择路径'));
      return;
    }
    const uris = await MediaPickerUtil.pickFiles();
    await this.enqueueUris(uris, target);
  }

  /** 选择结果入队（暂停态），确认后立即开始（对齐 Flutter _enqueueAndConfirm） */
  async enqueueUris(uris: string[], targetDir: string): Promise<void> {
    const target = targetDir.trim();
    if (target.length === 0 || uris.length === 0) {
      return;
    }
    const added: TransferTask[] = [];
    for (const uri of uris) {
      if (uri.trim().length === 0) {
        continue;
      }
      const name = MediaPickerUtil.uriDisplayName(uri);
      if (name.length === 0) {
        continue;
      }
      const size = UriReader.statSize(uri);
      if (size <= 0) {
        continue;
      }
      if (UploadTransferHelper.isTaskAlreadyExists(this.tasks, name, target)) {
        ToastUtil.show(L10n.t('file_allready_in_upload_queue', '文件已在队列中'));
        continue;
      }
      added.push(new TransferTask(`${Date.now()}_${name}`, name, uri, target,
        size, TransferStatus.PAUSED, UploadTransferHelper.calculateChunkSize(size)));
    }
    if (added.length === 0) {
      return;
    }
    for (const t of added) {
      this.tasks.push(t);
    }
    const ok = await DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
      L10n.t('upload_center_start_now_confirm', '是否立即开始上传？'));
    if (ok !== true) {
      return;
    }
    for (const t of added) {
      this.startTask(t);
    }
  }

  /** 文件浏览器"上传文件"入口：入队并立即开始 */
  async uploadPickedFilesHere(uris: string[], targetDir: string): Promise<void> {
    const target = targetDir.trim();
    if (target.length === 0) {
      return;
    }
    const added: TransferTask[] = [];
    for (const uri of uris) {
      const name = MediaPickerUtil.uriDisplayName(uri);
      if (name.length === 0) {
        continue;
      }
      const size = UriReader.statSize(uri);
      if (size <= 0) {
        continue;
      }
      if (UploadTransferHelper.isTaskAlreadyExists(this.tasks, name, target)) {
        ToastUtil.show(L10n.t('file_allready_in_upload_queue', '文件已在队列中'));
        continue;
      }
      added.push(new TransferTask(`${Date.now()}_${name}`, name, uri, target,
        size, TransferStatus.PENDING, UploadTransferHelper.calculateChunkSize(size)));
    }
    if (added.length === 0) {
      return;
    }
    for (const t of added) {
      this.tasks.push(t);
    }
    ToastUtil.show(L10n.t('file_task_upload_added', '文件已加入上传队列'));
    this.processQueue();
  }

  // ===== 任务操作（对齐 Flutter actions） =====

  startTask(task: TransferTask): void {
    if (task.status === TransferStatus.UPLOADING) {
      return;
    }
    this.cancelTokens.set(task.id, new UploadCancellationToken());
    task.status = TransferStatus.PENDING;
    task.error = '';
    this.processQueue();
  }

  pauseTask(task: TransferTask): void {
    if (task.status === TransferStatus.UPLOADING || task.status === TransferStatus.PENDING) {
      this.cancelTokens.get(task.id)?.cancel();
      const idx = this.processingIds.indexOf(task.id);
      if (idx >= 0) {
        this.processingIds.splice(idx, 1);
      }
    }
    task.status = TransferStatus.PAUSED;
    this.processQueue();
  }

  pauseAll(): void {
    for (const task of this.tasks) {
      if (task.status === TransferStatus.UPLOADING || task.status === TransferStatus.PENDING) {
        this.cancelTokens.get(task.id)?.cancel();
        const idx = this.processingIds.indexOf(task.id);
        if (idx >= 0) {
          this.processingIds.splice(idx, 1);
        }
        task.status = TransferStatus.PAUSED;
      }
    }
    this.processQueue();
  }

  startAll(): void {
    for (const task of this.tasks) {
      if (task.status === TransferStatus.PAUSED || task.status === TransferStatus.ERROR) {
        task.status = TransferStatus.PENDING;
      }
    }
    this.processQueue();
  }

  deleteTask(task: TransferTask): void {
    this.pauseTask(task);
    const idx = this.tasks.indexOf(task);
    if (idx >= 0) {
      this.tasks.splice(idx, 1);
    }
    this.cancelTokens.delete(task.id);
  }

  clearAll(): void {
    for (const task of this.tasks) {
      this.cancelTokens.get(task.id)?.cancel();
    }
    this.processingIds.splice(0, this.processingIds.length);
    this.cancelTokens.clear();
    this.tasks.splice(0, this.tasks.length);
  }

  clearCompleted(): void {
    for (let i = this.tasks.length - 1; i >= 0; i--) {
      if (this.tasks[i].status === TransferStatus.COMPLETED) {
        this.tasks.splice(i, 1);
      }
    }
  }

  hasCompleted(): boolean {
    return this.tasks.some((t: TransferTask) => t.status === TransferStatus.COMPLETED);
  }

  uploadingTasks(): TransferTask[] {
    return this.tasks
      .filter((t: TransferTask) => t.status !== TransferStatus.COMPLETED)
      .sort((a: TransferTask, b: TransferTask): number => {
        const aOrder = a.status === TransferStatus.UPLOADING ? 0 : 1;
        const bOrder = b.status === TransferStatus.UPLOADING ? 0 : 1;
        if (aOrder !== bOrder) {
          return aOrder - bOrder;
        }
        return b.createdTime - a.createdTime;
      });
  }

  completedTasks(): TransferTask[] {
    return this.tasks
      .filter((t: TransferTask) => t.status === TransferStatus.COMPLETED)
      .sort((a: TransferTask, b: TransferTask): number => b.createdTime - a.createdTime);
  }

  // ===== 队列调度（对齐 Flutter _processQueue） =====

  private processQueue(): void {
    if (this.queueBusy) {
      return;
    }
    this.queueBusy = true;
    try {
      while (this.processingIds.length < MAX_CONCURRENT) {
        let pending: TransferTask | undefined = undefined;
        for (const t of this.tasks) {
          if (t.status === TransferStatus.PENDING && !this.processingIds.includes(t.id)) {
            pending = t;
            break;
          }
        }
        if (pending === undefined) {
          return;
        }
        this.processingIds.push(pending.id);
        const task = pending;
        void this.uploadOne(task).finally((): void => {
          this.processQueue();
        });
      }
    } finally {
      this.queueBusy = false;
    }
  }

  private async uploadOne(task: TransferTask): Promise<void> {
    if (!this.tasks.includes(task)) {
      this.cancelTokens.delete(task.id);
      const idx = this.processingIds.indexOf(task.id);
      if (idx >= 0) {
        this.processingIds.splice(idx, 1);
      }
      return;
    }
    const cancelToken = this.cancelTokens.get(task.id) ?? new UploadCancellationToken();
    this.cancelTokens.set(task.id, cancelToken);
    task.status = TransferStatus.UPLOADING;
    task.error = '';

    try {
      if (this.nameStrategy.toLowerCase() === 'skip') {
        const exists = await FileApiService.getInstance().existsResolved(task.remotePath, task.name);
        if (exists) {
          task.error = L10n.t('upload_file_exists_skipped', '同名文件已存在，已跳过上传');
          task.status = TransferStatus.ERROR;
          return;
        }
      }

      if (task.fileHash.length === 0) {
        const meta = `${task.name}|${task.totalSize}|${UriReader.statMtimeMs(task.localUri)}`;
        task.fileHash = await UploadTransferHelper.sha256Hex(meta);
      }

      const params = new ProcessFileParams();
      params.task = task;
      params.nameStrategy = this.nameStrategy;
      params.saveType = this.saveType;
      params.mtimeMs = UriReader.statMtimeMs(task.localUri);
      params.onProgress = (increment: number): void => {
        task.processedSize += increment;
        if (task.processedSize > task.totalSize) {
          task.processedSize = task.totalSize;
        }
      };
      params.onSkipped = (): void => {
        task.error = L10n.t('upload_file_exists_skipped', '同名文件已存在，已跳过上传');
      };
      params.cancelToken = cancelToken;
      const processed = await UploadCore.processFile(params);
      task.processedSize = processed;
      task.status = task.error.length > 0 ? TransferStatus.ERROR : TransferStatus.COMPLETED;
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      if (msg === 'upload_cancelled') {
        task.status = TransferStatus.PAUSED;
      } else {
        task.status = TransferStatus.ERROR;
        task.error = UploadTransferHelper.getDisplayMessage(msg);
      }
    } finally {
      const idx = this.processingIds.indexOf(task.id);
      if (idx >= 0) {
        this.processingIds.splice(idx, 1);
      }
      this.cancelTokens.delete(task.id);
    }
  }
}
