import { request } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { fileUri, fileShare, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { WindowStore } from '../../common/WindowStore';
import { APIClient } from '../../core/network/APIClient';
import { FileApiService } from '../../files/service/FileApiService';
import { FileItem, FileModelAccess } from '../../files/models/FileModels';
import { L10n } from '../../core/localization/L10n';
import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { DialogUtil } from '../../common/DialogUtil';
import { ToastUtil } from '../../common/ToastUtil';
import { DownloadTarget, DownloadTaskItem } from '../models/DownloadModels';
import { TransferStatus } from '../models/TransferModels';
import { DownloadHistoryStorage } from '../storage/DownloadHistoryStorage';

/** 下载保存根目录名（应用 filesDir 下，对齐 Flutter getApplicationDocumentsDirectory/NasCabDownload） */
const DOWNLOAD_DIR_NAME: string = 'NasCabDownload';
/** 下载中临时文件后缀（完成后 rename 去后缀，对齐 Flutter） */
const TMP_SUFFIX: string = '.nascab_tmp';
/** 同时运行的系统下载任务数上限（其余排队等待） */
const MAX_RUNNING: number = 2;
/** 偏好：系统下载目录 URI（DOWNLOAD 模式返回，授权已持久化） */
const PREF_SYSTEM_DIR_URI: string = 'dl_system_dir_uri';

/**
 * 下载服务（单例）。
 *
 * 基于系统下载代理 @ohos.request：background:true 时系统托管通知与网络，
 * 应用退出/切后台后仍可继续下载，天然符合鸿蒙后台下载规范。
 *
 * 职责：
 * - 文件/文件夹（递归展开）批量入队
 * - 下载队列调度（等待 → 运行 → 完成/失败）
 * - 暂停 / 恢复 / 重试 / 删除
 * - 完成记录写入 DownloadHistoryStorage（下载中心「已完成」页数据源）
 */
@ObservedV2
export class DownloadService {
  static instance: DownloadService | undefined = undefined;

  static getInstance(): DownloadService {
    if (!DownloadService.instance) {
      DownloadService.instance = new DownloadService();
    }
    return DownloadService.instance;
  }

  /** 全部下载任务（UI 观察；按时间自然有序） */
  @Trace tasks: DownloadTaskItem[] = [];

  /** 等待创建系统任务的项（PENDING） */
  private waiting: DownloadTaskItem[] = [];
  /** 正在运行的系统任务 id 集合（暂停/完成/失败/删除时移除） */
  private running: Set<string> = new Set();
  /** 队列泵是否已在调度（避免重复调度） */
  private pumpInFlight: boolean = false;
  /** 下载暂存根目录（始终在应用沙箱，系统代理实际落盘位置） */
  private stagingRoot: string = '';
  /** 最终下载根目录绝对路径（系统 Download/包名 目录；UI 观察，未授权前为空串） */
  @Trace downloadRoot: string = '';
  /** 系统下载目录 URI（DOWNLOAD 模式返回，授权已持久化） */
  private systemDirUri: string = '';
  /** 任务 id 自增序列（保证同毫秒创建的任务 id 唯一） */
  private seq: number = 0;
  /** 通知授权是否已请求（每次安装期内只请求一次） */
  private notifRequested: boolean = false;
  /** 单个文件下载完成监听（下载中心页注册，防抖刷新已完成列表） */
  private completionListener: (() => void) | undefined = undefined;
  /** 下载历史存储（无状态实例，方法内部自管数据库连接） */
  private history: DownloadHistoryStorage = new DownloadHistoryStorage();

  private constructor() {
  }

  /** 注册/清除单文件完成监听（页面退出时必须清除，避免泄漏） */
  setCompletionListener(cb: (() => void) | undefined): void {
    this.completionListener = cb;
  }

  /** 通知监听者：一个文件已下载完成（异常不影响主流程） */
  private notifyCompletion(): void {
    const cb = this.completionListener;
    if (cb) {
      try {
        cb();
      } catch (_e) {
        // 监听者异常忽略
      }
    }
  }

  // ==================== 入队入口 ====================

  /**
   * 批量下载入口。
   *
   * @param targets 远端文件/文件夹目标列表
   * @returns 实际新增的任务数（空目标/重复入队不计）
   */
  async enqueue(targets: DownloadTarget[]): Promise<number> {
    if (targets.length === 0) {
      return 0;
    }
    try {
      await this.ensureStagingRoot();
    } catch (e) {
      console.error('[Download] 初始化暂存目录失败: ' + `${e}`);
      return 0;
    }
    // 触发下载时检测系统下载目录授权，未授权则引导开通；用户取消则中止本次下载
    const granted: boolean = await this.ensureSystemAccess();
    if (!granted) {
      return 0;
    }
    void this.requestNotificationPermission();

    let added: number = 0;
    for (const t of targets) {
      const remote: string = t.path;
      if (remote.trim().length === 0) {
        continue;
      }
      // 去重：同一远端路径存在未终结任务时跳过
      if (this.hasUnfinished(remote)) {
        continue;
      }
      const baseName: string = DownloadService.pathBaseName(remote);
      if (t.isDirHint) {
        await this.expandFolder(remote, baseName, baseName);
        added += 1;
      } else {
        this.addFileItem(remote, baseName, '', 0);
        added += 1;
      }
    }

    if (added > 0) {
      this.schedulePump();
    }
    return added;
  }

  /** 是否存在运行中/等待中/暂停的下载（「清理历史」前置校验，对齐 Flutter） */
  hasActiveTasks(): boolean {
    return this.tasks.some((it: DownloadTaskItem): boolean =>
      it.status === TransferStatus.PENDING ||
      it.status === TransferStatus.UPLOADING ||
      it.status === TransferStatus.PAUSED);
  }

  private hasUnfinished(remote: string): boolean {
    return this.tasks.some((it: DownloadTaskItem): boolean =>
      it.remotePath === remote &&
      (it.status === TransferStatus.PENDING ||
        it.status === TransferStatus.UPLOADING ||
        it.status === TransferStatus.PAUSED));
  }

  // ==================== 暂存目录 / 系统下载目录授权 ====================

  /** 确保暂存根目录 {filesDir}/NasCabDownload 存在（系统代理实际落盘位置，保证后台下载） */
  private async ensureStagingRoot(): Promise<void> {
    if (this.stagingRoot.length > 0) {
      return;
    }
    const ctx = WindowStore.appContext;
    if (!ctx) {
      throw new Error('download_context_missing');
    }
    const root: string = `${ctx.filesDir}/${DOWNLOAD_DIR_NAME}`;
    if (!fs.accessSync(root)) {
      fs.mkdirSync(root, true);
    }
    this.stagingRoot = root;
  }

  /**
   * 确保已获得系统下载目录授权（每次下载触发时检测）：
   * 1. 已有持久化 URI 且目录仍可访问 → 直接通过
   * 2. 静默发起 DOWNLOAD 授权（正常无界面）
   * 3. 仍失败 → 弹窗说明用途并引导用户「去开通」
   *
   * @returns 是否已获得授权（用户取消为 false，调用方应中止本次下载）
   */
  private async ensureSystemAccess(): Promise<boolean> {
    // 1. 内存中的授权仍有效
    if (this.systemDirUri.length > 0 && this.verifySystemDir(this.systemDirUri)) {
      return true;
    }
    // 持久化的授权仍有效（checkPersistentPermission 确认重启后授权未失效）
    const persistedUri: string =
      PreferencesStore.getInstance().getString(PREF_SYSTEM_DIR_URI) ?? '';
    if (persistedUri.length > 0 && this.verifySystemDir(persistedUri) &&
      await DownloadService.isPermissionPersisted(persistedUri)) {
      this.systemDirUri = persistedUri;
      this.downloadRoot = DownloadService.uriToPath(persistedUri);
      return true;
    }

    // 2. 静默尝试获取授权（DOWNLOAD 模式无选择界面，直接返回目录）
    if (await this.acquireSystemDir()) {
      return true;
    }

    // 3. 引导弹窗：说明用途，用户点「去开通」后再发起一次授权
    const r = await DialogUtil.showConfirmDialog(
      L10n.t('download_permission_guide_title', '需要下载目录权限'),
      L10n.t('download_permission_guide_message',
        '下载的文件将保存到系统「文件管理」的 Download/应用包名 目录中。需要您授权访问该目录，点击「去开通」完成授权。'),
      undefined,
      L10n.t('go_grant', '去开通'));
    if (r === true) {
      if (await this.acquireSystemDir()) {
        return true;
      }
      ToastUtil.show(L10n.t('download_permission_grant_failed', '授权失败，请重试'));
    }
    return false;
  }

  /** 校验系统下载目录 URI 当前仍可访问 */
  private verifySystemDir(uri: string): boolean {
    try {
      return fs.accessSync(DownloadService.uriToPath(uri));
    } catch (_e) {
      return false;
    }
  }

  /** 系统目录 URI → 物理路径（fileUri 转换，与官方示例一致） */
  private static uriToPath(uri: string): string {
    return new fileUri.FileUri(uri).path;
  }

  /** 查询 URI 是否已完成持久化授权（失败按未持久化处理，触发重新授权） */
  private static async isPermissionPersisted(uri: string): Promise<boolean> {
    try {
      const policy: fileShare.PolicyInfo = {
        uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      };
      const results: boolean[] = await fileShare.checkPersistentPermission([policy]);
      return results.length > 0 && results[0];
    } catch (_e) {
      return false;
    }
  }

  /**
   * 将目录授权持久化（重启后仍可读写）。
   * 部分设备/权限配置可能不支持，失败不阻断本次下载（临时授权在本次前台仍有效）。
   */
  private async persistDirPermission(uri: string): Promise<void> {
    try {
      const policy: fileShare.PolicyInfo = {
        uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      };
      await fileShare.persistPermission([policy]);
    } catch (e) {
      console.warn('[Download] 目录授权持久化失败，本次运行仍可下载: ' + `${e}`);
    }
  }

  /**
   * 通过 FilePicker DOWNLOAD 模式获取系统下载目录：
   * 无需在 module.json5 声明权限、无文件选择界面；
   * 返回 URI 自带持久化授权，目录为 Download/包名/。
   * 成功时写入偏好并更新 downloadRoot。
   */
  private async acquireSystemDir(): Promise<boolean> {
    const ctx = WindowStore.appContext;
    if (!ctx) {
      return false;
    }
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      const result: string[] = await viewPicker.save(options);
      if (result.length === 0 || result[0].length === 0) {
        return false;
      }
      const uri: string = result[0];
      const path: string = DownloadService.uriToPath(uri);
      if (!fs.accessSync(path)) {
        return false;
      }
      // 尝试将授权持久化（重启后免再授权；设备不支持时降级为本次临时授权）
      await this.persistDirPermission(uri);
      await PreferencesStore.getInstance().setString(PREF_SYSTEM_DIR_URI, uri);
      this.systemDirUri = uri;
      this.downloadRoot = path;
      return true;
    } catch (e) {
      console.error('[Download] 获取系统下载目录授权失败: ' + `${e}`);
      return false;
    }
  }

  /** 最终下载根目录绝对路径（已完成页顶部目录说明使用；未授权前为空串） */
  getDownloadRoot(): string {
    return this.downloadRoot;
  }

  /** 首次下载时静默请求通知授权（系统代理通知的兜底，拒绝不阻断下载） */
  private async requestNotificationPermission(): Promise<void> {
    if (this.notifRequested) {
      return;
    }
    this.notifRequested = true;
    const ctx = WindowStore.appContext;
    if (!ctx) {
      return;
    }
    try {
      await notificationManager.requestEnableNotification(ctx);
    } catch (_e) {
      // 用户拒绝：系统代理通知可能不展示，不影响下载本身
    }
  }

  // ==================== 文件夹递归展开 ====================

  /**
   * 递归列举文件夹并为每个文件创建下载项（对齐 Flutter downloadFolder）。
   *
   * @param remoteDir 当前远端目录
   * @param relPrefix 相对根前缀（首层为文件夹根名，逐层累积）
   * @param rootName  文件夹根名
   */
  private async expandFolder(remoteDir: string, relPrefix: string,
    rootName: string): Promise<void> {
    let items: FileItem[] = [];
    try {
      const data = await FileApiService.getInstance().listDirectory(
        remoteDir, false, false, 'normal', '');
      items = (data.items ?? []) as FileItem[];
    } catch (e) {
      // 列举失败：生成文件夹级错误占位项，用户重试时重新展开
      const item = this.addFileItem(remoteDir, rootName, rootName, 0);
      item.isFolderRoot = true;
      item.status = TransferStatus.ERROR;
      item.error = L10n.t('network_error', '网络错误');
      return;
    }

    for (const it of items) {
      const name: string = FileModelAccess.fileName(it);
      if (!DownloadService.isSafeSegment(name)) {
        // 非法文件名：按 Flutter 直接置文件夹失败
        const item = this.addFileItem(remoteDir, rootName, rootName, 0);
        item.isFolderRoot = true;
        item.status = TransferStatus.ERROR;
        item.error = L10n.t('api_code_file_invalid_params', '参数错误');
        return;
      }
      const childRemote: string = DownloadService.joinRemote(remoteDir, name);
      const childRel: string = `${relPrefix}/${name}`;
      if (FileModelAccess.isDir(it)) {
        await this.expandFolder(childRemote, childRel, rootName);
      } else {
        const size: number = FileModelAccess.size(it);
        this.addFileItem(childRemote, childRel, rootName, size > 0 ? size : 0);
      }
    }
  }

  // ==================== 任务项创建 ====================

  /**
   * 创建一个文件下载项并加入任务列表与等待队列。
   *
   * @param remotePath  远端完整路径
   * @param displayName 展示名（单文件=文件名；文件夹内=根名/相对路径）
   * @param rootName    文件夹根名（空串=单文件任务）
   * @param totalSize   文件总字节（未知传 0，由进度回调回填）
   */
  private addFileItem(remotePath: string, displayName: string, rootName: string,
    totalSize: number): DownloadTaskItem {
    const now: number = Date.now();
    const id: string = `dl_${now}_${this.seq++}`;
    const localPath: string = `${this.downloadRoot}/${displayName}`;
    const item: DownloadTaskItem = new DownloadTaskItem(
      id, displayName, remotePath, localPath, TransferStatus.PENDING, now);
    item.rootName = rootName;
    item.totalSize = totalSize;
    this.tasks.push(item);
    this.waiting.push(item);
    return item;
  }

  // ==================== 队列调度 ====================

  /** 请求一次队列调度（异步、幂等） */
  private schedulePump(): void {
    if (this.pumpInFlight) {
      return;
    }
    this.pumpInFlight = true;
    setTimeout((): void => {
      void this.pump();
    }, 0);
  }

  /** 从等待队列取下一个可运行项，直到并发槽占满或队列清空 */
  private async pump(): Promise<void> {
    try {
      while (this.running.size < MAX_RUNNING) {
        const next: DownloadTaskItem | undefined = this.takeNext();
        if (!next) {
          break;
        }
        this.running.add(next.id);
        await this.startItem(next);
      }
    } finally {
      this.pumpInFlight = false;
      // 调度间隙若有新增等待项，再补一次
      if (this.running.size < MAX_RUNNING && this.waiting.length > 0) {
        this.schedulePump();
      }
    }
  }

  /** 取出队首仍为 PENDING 且尚未创建系统任务的项 */
  private takeNext(): DownloadTaskItem | undefined {
    while (this.waiting.length > 0) {
      const item: DownloadTaskItem | undefined = this.waiting.shift();
      if (item && item.status === TransferStatus.PENDING && !item.sysTask) {
        return item;
      }
    }
    return undefined;
  }

  // ==================== 单任务执行 ====================

  /**
   * 创建系统下载任务并绑定事件。
   * resolve 仅代表系统任务已创建（非下载完成）。
   */
  private async startItem(item: DownloadTaskItem): Promise<void> {
    // 已存在同大小文件：跳过下载，直接记完成（对齐 Flutter skip already on disk）
    try {
      if (item.totalSize > 0 && fs.accessSync(item.localPath) &&
        fs.statSync(item.localPath).size === item.totalSize) {
        await this.completeItem(item, item.localPath);
        return;
      }
    } catch (_e) {
      // 访问失败则正常走下载
    }

    // 确保暂存目录存在（系统代理要求 filePath 父目录已存在）
    const tmpPath: string = this.stagingPathOf(item);
    try {
      const dir: string = DownloadService.dirName(tmpPath);
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      this.markError(item, L10n.t('error', '错误') + `: ${e}`);
      return;
    }

    const ctx = WindowStore.appContext;
    if (!ctx) {
      this.markError(item, 'download_context_missing');
      return;
    }

    // background:true → 系统托管：自带下载通知、后台继续、重启后仍可查询
    const config: request.DownloadConfig = {
      url: this.buildDownloadUrl(item.remotePath),
      title: item.name,
      description: L10n.t('downloading', '下载中...'),
      filePath: tmpPath,
      background: true,
      enableMetered: true,
      enableRoaming: true
    };

    let sysTask: request.DownloadTask;
    try {
      sysTask = await request.downloadFile(ctx, config);
    } catch (e) {
      this.markError(item, `${e}`);
      return;
    }
    item.sysTask = sysTask;
    item.status = TransferStatus.UPLOADING;
    this.bindSysEvents(item, sysTask);
  }

  /** 绑定系统任务的进度/完成/暂停/失败/删除事件 */
  private bindSysEvents(item: DownloadTaskItem, sysTask: request.DownloadTask): void {
    sysTask.on('progress', (receivedSize: number, totalSize: number): void => {
      item.processedSize = receivedSize;
      if (totalSize > 0) {
        item.totalSize = totalSize;
      }
    });
    sysTask.on('complete', (): void => {
      void this.onSysComplete(item);
    });
    sysTask.on('pause', (): void => {
      if (item.status === TransferStatus.PAUSED) {
        return;
      }
      item.status = TransferStatus.PAUSED;
      this.running.delete(item.id);
      this.schedulePump();
    });
    sysTask.on('fail', (err: number): void => {
      this.markError(item, this.friendlyError(err));
    });
    sysTask.on('remove', (): void => {
      // 系统侧删除（如系统下载管理中清除）：同步移除本任务
      this.discardItem(item);
    });
  }

  /**
   * 系统下载完成：暂存文件发布到最终目录（重名加 (1)(2)）。
   * 最终目录与暂存目录跨文件系统时 rename 失败，自动降级 copy + 删除暂存。
   */
  private async onSysComplete(item: DownloadTaskItem): Promise<void> {
    const stagingPath: string = this.stagingPathOf(item);
    let finalPath: string = item.localPath;
    try {
      if (fs.accessSync(stagingPath)) {
        const actualSize: number = fs.statSync(stagingPath).size;
        finalPath = this.uniqueFinalPath(item.localPath);
        this.publishFile(stagingPath, finalPath);
        item.totalSize = actualSize;
        item.processedSize = actualSize;
      }
    } catch (e) {
      this.markError(item, L10n.t('error', '错误') + `: ${e}`);
      return;
    }
    await this.completeItem(item, finalPath);
  }

  /**
   * 暂存文件 → 最终文件：优先 rename（同卷高效）；
   * 跨卷/失败时 copy 后删除暂存文件。
   */
  private publishFile(stagingPath: string, finalPath: string): void {
    // 确保最终目录存在（系统 Download 目录下的多级子目录）
    const dir: string = DownloadService.dirName(finalPath);
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
    try {
      fs.renameSync(stagingPath, finalPath);
    } catch (_e) {
      // 跨文件系统 rename 不支持：复制后清理暂存
      fs.copyFileSync(stagingPath, finalPath);
      try {
        fs.unlinkSync(stagingPath);
      } catch (_ignore) {
        // 暂存清理失败不阻断完成
      }
    }
  }

  /** 任务暂存文件路径：{暂存根}/{展示名}.nascab_tmp */
  private stagingPathOf(item: DownloadTaskItem): string {
    return `${this.stagingRoot}/${item.name}${TMP_SUFFIX}`;
  }

  /** 置完成态并写入下载历史（历史库失败不影响任务完成） */
  private async completeItem(item: DownloadTaskItem, finalPath: string): Promise<void> {
    item.localPath = finalPath;
    item.status = TransferStatus.COMPLETED;
    item.error = '';
    try {
      await this.history.recordCompletedFile(
        finalPath, item.remotePath, DownloadService.pathBaseName(finalPath),
        item.totalSize, item.id);
    } catch (e) {
      console.error('[Download] 写入下载历史失败: ' + `${e}`);
    }
    this.notifyCompletion();
    this.release(item);
  }

  /** 置失败态并释放并发槽 */
  private markError(item: DownloadTaskItem, message: string): void {
    if (item.status === TransferStatus.COMPLETED) {
      return;
    }
    item.status = TransferStatus.ERROR;
    item.error = message;
    this.release(item);
  }

  /** 从任务列表与等待队列中丢弃（系统 'remove' 事件） */
  private discardItem(item: DownloadTaskItem): void {
    const idx: number = this.tasks.findIndex((t: DownloadTaskItem): boolean => t.id === item.id);
    if (idx >= 0) {
      this.tasks.splice(idx, 1);
    }
    this.removeFromWaiting(item);
    this.release(item);
  }

  /** 释放并发槽并补调度 */
  private release(item: DownloadTaskItem): void {
    if (this.running.delete(item.id)) {
      this.schedulePump();
    }
  }

  // ==================== 用户操作：暂停/恢复/删除/重试 ====================

  /** 暂停任务（等待中的任务直接置暂停；运行中的任务调系统 pause） */
  async pauseItem(item: DownloadTaskItem): Promise<void> {
    const sysTask = item.sysTask;
    if (!sysTask) {
      if (item.status === TransferStatus.PENDING) {
        this.removeFromWaiting(item);
        item.status = TransferStatus.PAUSED;
      }
      return;
    }
    try {
      await sysTask.pause();
      item.status = TransferStatus.PAUSED;
      this.running.delete(item.id);
      this.schedulePump();
    } catch (e) {
      console.warn('[Download] 暂停失败: ' + `${e}`);
    }
  }

  /** 恢复任务（暂停于等待态的重新排队；运行态的调系统 resume） */
  async resumeItem(item: DownloadTaskItem): Promise<void> {
    const sysTask = item.sysTask;
    if (!sysTask) {
      if (item.status === TransferStatus.PAUSED) {
        item.status = TransferStatus.PENDING;
        this.waiting.push(item);
        this.schedulePump();
      }
      return;
    }
    try {
      await sysTask.resume();
      item.status = TransferStatus.UPLOADING;
      this.running.add(item.id);
    } catch (e) {
      console.warn('[Download] 恢复失败: ' + `${e}`);
    }
  }

  /**
   * 删除任务：从列表/队列移除，系统任务调 remove（同时清理临时/已下载文件）；
   * 无系统任务的残留临时文件手动清理。
   */
  async removeItem(item: DownloadTaskItem): Promise<void> {
    const idx: number = this.tasks.findIndex((t: DownloadTaskItem): boolean => t.id === item.id);
    if (idx >= 0) {
      this.tasks.splice(idx, 1);
    }
    this.removeFromWaiting(item);
    this.running.delete(item.id);

    const sysTask = item.sysTask;
    item.sysTask = undefined;
    if (sysTask) {
      try {
        sysTask.off('progress');
        sysTask.off('complete');
        sysTask.off('pause');
        sysTask.off('fail');
        sysTask.off('remove');
        await sysTask.remove();
      } catch (e) {
        console.warn('[Download] 删除系统任务失败: ' + `${e}`);
      }
    } else {
      const tmpPath: string = this.stagingPathOf(item);
      try {
        if (fs.accessSync(tmpPath)) {
          fs.unlinkSync(tmpPath);
        }
      } catch (_e) {
        // 忽略清理失败
      }
    }
    this.schedulePump();
  }

  /**
   * 重试失败任务（对齐 Flutter 的「删除旧任务 → 重新入队」）：
   * - 文件夹占位：重新递归展开
   * - 单文件：清理临时文件后全新入队
   */
  async retryItem(item: DownloadTaskItem): Promise<void> {
    const remotePath: string = item.remotePath;
    const rootName: string = item.rootName;
    const displayName: string = item.name;
    const isFolder: boolean = item.isFolderRoot;
    await this.removeItem(item);

    if (isFolder) {
      await this.ensureStagingRoot();
      await this.expandFolder(remotePath, rootName.length > 0 ? rootName : displayName,
        rootName.length > 0 ? rootName : displayName);
      this.schedulePump();
      return;
    }
    this.addFileItem(remotePath, displayName, rootName, 0);
    this.schedulePump();
  }

  // ==================== 下载 URL / 错误文案 / 路径辅助 ====================

  /**
   * 构造下载 URL（与 Flutter 一致）：
   * {baseUrl}/api/file/download?path={encodeURIComponent}&accessToken={token}
   */
  private buildDownloadUrl(remotePath: string): string {
    const client: APIClient = APIClient.getInstance();
    const base: string = client.baseUrl;
    const token: string = client.accessToken ?? '';
    return `${base}/api/file/download?path=${encodeURIComponent(remotePath)}&accessToken=${token}`;
  }

  /** 系统下载失败码 → 可读文案 */
  private friendlyError(code: number): string {
    if (code === request.ERROR_CANNOT_RESUME ||
      code === request.ERROR_HTTP_DATA_ERROR ||
      code === request.ERROR_TOO_MANY_REDIRECTS ||
      code === request.ERROR_OFFLINE ||
      code === request.ERROR_UNSUPPORTED_NETWORK_TYPE) {
      return L10n.t('network_error', '网络错误');
    }
    if (code === request.ERROR_INSUFFICIENT_SPACE) {
      return L10n.t('insufficient_storage', '存储空间不足');
    }
    if (code === request.ERROR_DEVICE_NOT_FOUND ||
      code === request.ERROR_FILE_ERROR) {
      return L10n.t('error', '错误') + ` (${code})`;
    }
    if (code === request.ERROR_UNHANDLED_HTTP_CODE) {
      return L10n.t('server_error', '服务器错误');
    }
    if (code === request.ERROR_FILE_ALREADY_EXISTS) {
      return L10n.t('error', '错误') + ` (${code})`;
    }
    return L10n.t('error', '错误') + ` (${code})`;
  }

  /** 重名最终路径：name.txt → name (1).txt，自增直至不冲突（对齐 Flutter） */
  private uniqueFinalPath(path: string): string {
    if (!fs.accessSync(path)) {
      return path;
    }
    const dir: string = DownloadService.dirName(path);
    const base: string = DownloadService.pathBaseName(path);
    const dot: number = base.lastIndexOf('.');
    const stem: string = dot > 0 ? base.substring(0, dot) : base;
    const ext: string = dot > 0 ? base.substring(dot) : '';
    let i: number = 1;
    while (true) {
      const candidate: string = `${dir}/${stem} (${i})${ext}`;
      if (!fs.accessSync(candidate)) {
        return candidate;
      }
      i++;
    }
  }

  private removeFromWaiting(item: DownloadTaskItem): void {
    const idx: number = this.waiting.findIndex((w: DownloadTaskItem): boolean => w.id === item.id);
    if (idx >= 0) {
      this.waiting.splice(idx, 1);
    }
  }

  /** 取路径最后一段作为文件名（空路径名兜底 download） */
  private static pathBaseName(path: string): string {
    const norm: string = path.replace(/\\/g, '/');
    const i: number = norm.lastIndexOf('/');
    const name: string = i >= 0 ? norm.substring(i + 1) : norm;
    return name.length > 0 ? name : 'download';
  }

  /** 取所在目录（无分隔符时返回 '.'） */
  private static dirName(path: string): string {
    const i: number = path.lastIndexOf('/');
    return i >= 0 ? path.substring(0, i) : '.';
  }

  /** 拼接远端目录与文件名 */
  private static joinRemote(dir: string, name: string): string {
    const d: string = dir.trim();
    if (d.length === 0 || d === '/') {
      return `/${name}`;
    }
    return d.endsWith('/') ? `${d}${name}` : `${d}/${name}`;
  }

  /** 文件名段合法性（非空、非 . / ..、不含路径分隔符） */
  private static isSafeSegment(name: string): boolean {
    const n: string = name.trim();
    if (n.length === 0 || n === '.' || n === '..') {
      return false;
    }
    if (n.includes('/') || n.includes('\\')) {
      return false;
    }
    return true;
  }

  /** 文件名后缀（小写、不含点；无后缀返回 ''） */
  private static extOfName(name: string): string {
    const i: number = name.lastIndexOf('.');
    const ext: string = i > 0 ? name.substring(i + 1) : '';
    return ext.trim().toLowerCase();
  }

  /** 去掉后缀的名称（写入图库时作为标题） */
  private static stripExt(name: string): string {
    const i: number = name.lastIndexOf('.');
    return i > 0 ? name.substring(0, i) : name;
  }

  /** 判断媒体类型：1=图片，2=视频，0=非媒体（仅枚举图库支持的常见格式） */
  private static mediaKind(name: string): number {
    const ext: string = DownloadService.extOfName(name);
    if (ext.length === 0) {
      return 0;
    }
    const images: string[] =
      ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif', 'tif', 'tiff', 'dng'];
    const videos: string[] =
      ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp', '3g2', 'flv', 'ts', 'mpg', 'mpeg', 'rm', 'rmvb', 'f4v'];
    if (images.indexOf(ext) >= 0) {
      return 1;
    }
    if (videos.indexOf(ext) >= 0) {
      return 2;
    }
    return 0;
  }

  /**
   * 将已下载的图片/视频手动保存到系统图库（相册）。
   *
   * 鸿蒙中 Download 目录与图库天然隔离，需通过
   * PhotoAccessHelper.showAssetsCreationDialog 弹出系统保存对话框，用户确认后
   * 写入图库（无需申请 ACL 受限权限）。
   *
   * 官方约定（关键）：
   * 1. 对话框的源文件 URI 必须是「应用沙箱路径」生成的 URI，公共目录路径不支持；
   * 2. 对话框只负责创建空的媒体资源并返回目标 URI，文件内容需要应用自行
   *    用 fs.copyFileSync(srcFd, desFd) 写入。
   *
   * @param srcPath     源文件绝对路径（系统 Download 目录内）
   * @param displayName 文件名（含后缀，用于判断媒体类型与写入标题）
   * @returns true=已保存；false=非媒体/文件缺失/用户取消/失败
   */
  async saveToGallery(srcPath: string, displayName: string): Promise<boolean> {
    const kind: number = DownloadService.mediaKind(displayName);
    if (kind === 0) {
      return false;
    }
    const ctx = WindowStore.appContext;
    if (!ctx) {
      return false;
    }
    // 沙箱临时文件：{cacheDir}/gallery_publish/{文件名}
    const tmpDir: string = `${ctx.cacheDir}/gallery_publish`;
    const tmpPath: string = `${tmpDir}/${displayName}`;
    let srcFile: fs.File | undefined = undefined;
    let desFile: fs.File | undefined = undefined;
    try {
      if (!fs.accessSync(srcPath)) {
        return false;
      }
      if (!fs.accessSync(tmpDir)) {
        fs.mkdirSync(tmpDir, true);
      }
      // 1. 复制到应用沙箱（公共目录文件 → 沙箱临时文件）
      fs.copyFileSync(srcPath, tmpPath);

      // 2. 弹出系统保存确认框（源 URI 必须是沙箱文件 URI）
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: DownloadService.stripExt(displayName),
        fileNameExtension: DownloadService.extOfName(displayName),
        photoType: kind === 1 ? photoAccessHelper.PhotoType.IMAGE : photoAccessHelper.PhotoType.VIDEO
      };
      const srcUri: string = fileUri.getUriFromPath(tmpPath);
      const helper: photoAccessHelper.PhotoAccessHelper =
        photoAccessHelper.getPhotoAccessHelper(ctx);
      const desUris: string[] = await helper.showAssetsCreationDialog([srcUri], [config]);
      // 用户点取消：返回空列表
      if (desUris.length === 0) {
        return false;
      }

      // 3. 对话框只创建了空媒体资源，需自行把内容写入目标 URI
      srcFile = fs.openSync(tmpPath, fs.OpenMode.READ_ONLY);
      desFile = fs.openSync(desUris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.copyFileSync(srcFile.fd, desFile.fd);
      console.info('[Download] 已保存到系统图库: ' + desUris[0]);
      return true;
    } catch (e) {
      console.warn('[Download] 保存到图库失败: ' + `${e}`);
      return false;
    } finally {
      if (srcFile) {
        try {
          fs.closeSync(srcFile);
        } catch (_e) {
          // 关闭失败忽略
        }
      }
      if (desFile) {
        try {
          fs.closeSync(desFile);
        } catch (_e) {
          // 关闭失败忽略
        }
      }
      // 清理沙箱临时文件
      try {
        if (fs.accessSync(tmpPath)) {
          fs.unlinkSync(tmpPath);
        }
      } catch (_e) {
        // 清理失败忽略
      }
    }
  }

  /** 是否为可保存到图库的图片/视频（bottom 菜单按此决定是否展示该项） */
  static isSavableMedia(displayName: string): boolean {
    return DownloadService.mediaKind(displayName) !== 0;
  }
}
