import pasteboard from '@ohos.pasteboard';
import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import {
  DockerApiResult, DockerApiService
} from '../services/DockerApiService';
import { DockerImage, DockerContainer, DockerTask, DockerTaskLog } from '../models/DockerModels';

/** 服务器版本要求（对齐 Flutter DockerController._requiredServerVersion） */
const REQUIRED_SERVER_VERSION = 5;
/** 轮询间隔（对齐 Flutter _pollInterval 4s） */
const POLL_INTERVAL_MS = 4000;

/** 区间裁剪 */
function clampNum(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

/**
 * Docker 控制器（对齐 Flutter DockerController；@ObservedV2 + @Trace 驱动 V2 刷新）。
 * 控制器随页面创建销毁（对齐 Flutter GetBuilder init/dispose 生命周期），含 4s 轮询与当前页签自动刷新。
 */
@ObservedV2
export class DockerController {
  @Trace currentTab: string = 'overview';
  @Trace containerStatusFilter: string = '';
  @Trace images: DockerImage[] = [];
  @Trace containers: DockerContainer[] = [];
  @Trace tasks: DockerTask[] = [];
  @Trace taskLogs: DockerTaskLog[] = [];

  @Trace status: Record<string, Object> = {};
  @Trace config: Record<string, Object> = {};
  @Trace dockerAvailable: boolean = false;

  @Trace loadingOverview: boolean = false;
  @Trace loadingImages: boolean = false;
  @Trace loadingContainers: boolean = false;
  @Trace loadingTasks: boolean = false;
  @Trace loadingLogs: boolean = false;
  @Trace savingConfig: boolean = false;
  @Trace dockerServiceOperating: boolean = false;
  @Trace selectedTaskId: string = '';
  @Trace taskLogsPollingEnabled: boolean = false;
  @Trace errorText: string = '';

  private pollTimer: number = -1;
  private lowVersionDialogShown: boolean = false;
  private pollInFlight: boolean = false;

  /** 页面挂载（对齐 Flutter onInit） */
  onInit(): void {
    if (this.isServerVersionTooLow()) {
      this.applyUnsupportedServerVersion();
      this.showLowVersionDialogOnce();
      return;
    }
    void this.refreshAll(false);
    this.startPolling();
  }

  /** 页面销毁（对齐 Flutter onClose） */
  onClose(): void {
    this.cancelPollTimer();
  }

  // ===== 服务器版本（对齐 ServerVersionUtil.isAtLeast(serverVersion, 5)） =====

  isServerVersionTooLow(): boolean {
    const ver = `${APIClient.getInstance().state.serverVersion ?? ''}`.trim();
    const parts = ver.split('.');
    const major = parts.length > 0 ? Number(parts[0]) : 0;
    return !(Number.isFinite(major) && major >= REQUIRED_SERVER_VERSION);
  }

  private applyUnsupportedServerVersion(): void {
    this.dockerAvailable = false;
    this.errorText = L10n.t('server_version_too_low',
      '您的服务端版本过低，请升级到最新版本并重新登录后再使用此功能');
    this.clearDockerData();
  }

  private showLowVersionDialogOnce(): void {
    if (this.lowVersionDialogShown) {
      return;
    }
    this.lowVersionDialogShown = true;
    DialogUtil.showInfoDialog(L10n.tip,
      L10n.t('server_version_too_low', '您的服务端版本过低，请升级到最新版本并重新登录后再使用此功能'));
  }

  // ===== 轮询（对齐 _startPolling） =====

  private cancelPollTimer(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private startPolling(): void {
    this.cancelPollTimer();
    this.pollTimer = setInterval((): void => {
      if (this.pollInFlight) {
        return;
      }
      this.pollInFlight = true;
      this.runPollTick().finally((): void => {
        this.pollInFlight = false;
      });
    }, POLL_INTERVAL_MS);
  }

  private async runPollTick(): Promise<void> {
    const tab = this.currentTab.trim();
    if (tab === 'overview') {
      await this.refreshStatus(false);
      return;
    }
    await this.recoverStatusIfNeeded();
    if (tab === 'tasks') {
      await this.refreshTasks(false);
      const taskId = this.selectedTaskId.trim();
      if (this.taskLogsPollingEnabled && taskId.length > 0) {
        await this.refreshTaskLogs(taskId, false);
      }
    }
  }

  // ===== 页签切换刷新（对齐 ever(currentTab, _refreshCurrentTab)） =====

  /** 切换页签并触发对应数据刷新（页签变更统一入口） */
  changeTab(tab: string): void {
    this.currentTab = tab;
    void this.refreshCurrentTab(tab);
  }

  private async refreshCurrentTab(tab: string): Promise<void> {
    const t = tab.trim();
    if (t === 'overview') {
      await this.refreshStatus(false);
      return;
    }
    if (t === 'images') {
      await this.recoverStatusIfNeeded();
      await this.refreshImages(false);
      return;
    }
    if (t === 'containers') {
      await this.recoverStatusIfNeeded();
      await this.refreshContainers(false);
      return;
    }
    if (t === 'tasks') {
      await this.recoverStatusIfNeeded();
      await this.refreshTasks(false);
      const taskId = this.selectedTaskId.trim();
      if (this.taskLogsPollingEnabled && taskId.length > 0) {
        await this.refreshTaskLogs(taskId, false);
      }
      return;
    }
    if (t === 'settings') {
      await this.recoverStatusIfNeeded();
      await this.refreshConfig(false);
    }
  }

  private async recoverStatusIfNeeded(): Promise<void> {
    if (this.dockerAvailable && this.errorText.trim().length === 0) {
      return;
    }
    await this.refreshStatus(false);
  }

  // ===== 数据刷新（对齐 refreshAll / refreshStatus / refreshConfig / refreshImages /
  // refreshContainers / refreshTasks / refreshTaskLogs） =====

  async refreshAll(showLoading: boolean): Promise<void> {
    if (this.isServerVersionTooLow()) {
      this.applyUnsupportedServerVersion();
      this.showLowVersionDialogOnce();
      return;
    }
    await this.refreshStatus(showLoading);
    if (!this.dockerAvailable) {
      this.clearDockerData();
      return;
    }
    await Promise.all([
      this.refreshConfig(showLoading),
      this.refreshImages(showLoading),
      this.refreshContainers(showLoading),
      this.refreshTasks(showLoading)
    ]);
  }

  async refreshStatus(showLoading: boolean): Promise<void> {
    this.loadingOverview = showLoading;
    const res = await DockerApiService.getStatus();
    if (res.success) {
      this.dockerAvailable = true;
      this.status = res.data ?? {};
      this.errorText = '';
    } else {
      this.status = {};
      this.applyRequestError(res, true);
    }
    this.loadingOverview = false;
  }

  async refreshConfig(showLoading: boolean): Promise<void> {
    const res = await DockerApiService.getConfig();
    if (res.success) {
      this.config = res.data ?? {};
    } else {
      this.config = {};
      this.applyRequestError(res, false);
    }
  }

  async refreshImages(showLoading: boolean): Promise<void> {
    this.loadingImages = showLoading;
    const res = await DockerApiService.listImages();
    if (res.success) {
      this.images = res.data ?? [];
    } else {
      this.images = [];
      this.applyRequestError(res, this.isDockerAvailabilityError(res));
    }
    this.loadingImages = false;
  }

  async refreshContainers(showLoading: boolean): Promise<void> {
    this.loadingContainers = showLoading;
    const res = await DockerApiService.listContainers(this.containerStatusFilter);
    if (res.success) {
      this.containers = res.data ?? [];
    } else {
      this.containers = [];
      this.applyRequestError(res, this.isDockerAvailabilityError(res));
    }
    this.loadingContainers = false;
  }

  async refreshTasks(showLoading: boolean): Promise<void> {
    this.loadingTasks = showLoading;
    const res = await DockerApiService.listTasks();
    if (res.success) {
      this.tasks = res.data ?? [];
      const currentTaskId = this.selectedTaskId.trim();
      if (currentTaskId.length > 0) {
        const found = this.tasks.some((item: DockerTask): boolean => item.id === currentTaskId);
        if (!found) {
          this.selectedTaskId = '';
          this.taskLogsPollingEnabled = false;
          this.taskLogs = [];
        }
      }
    } else {
      this.tasks = [];
      this.selectedTaskId = '';
      this.taskLogsPollingEnabled = false;
      this.taskLogs = [];
      this.applyRequestError(res, this.isDockerAvailabilityError(res));
    }
    this.loadingTasks = false;
  }

  selectTask(taskId: string, clearLogs: boolean = false): void {
    this.selectedTaskId = taskId.trim();
    if (clearLogs) {
      this.taskLogs = [];
    }
  }

  setTaskLogsPolling(enabled: boolean): void {
    this.taskLogsPollingEnabled = enabled;
  }

  async openTaskLogs(taskId: string, showLoading: boolean = false,
    enablePolling: boolean = false): Promise<void> {
    this.selectTask(taskId, true);
    this.setTaskLogsPolling(enablePolling);
    await this.refreshTaskLogs(taskId, showLoading);
  }

  async refreshTaskLogs(taskId: string, showLoading: boolean = false): Promise<void> {
    const trimmed = taskId.trim();
    if (trimmed.length === 0) {
      this.selectedTaskId = '';
      this.taskLogs = [];
      return;
    }
    this.loadingLogs = showLoading;
    this.selectedTaskId = trimmed;
    const res = await DockerApiService.getTaskLogs(trimmed);
    if (res.success) {
      this.taskLogs = res.data ?? [];
    } else {
      this.taskLogs = [];
      this.applyRequestError(res, this.isDockerAvailabilityError(res));
    }
    this.loadingLogs = false;
  }

  private clearDockerData(): void {
    this.status = {};
    this.config = {};
    this.images = [];
    this.containers = [];
    this.tasks = [];
    this.taskLogs = [];
    this.selectedTaskId = '';
    this.taskLogsPollingEnabled = false;
  }

  private applyRequestError(res: DockerApiResult<Object>, clearDockerData: boolean): void {
    this.errorText = this.friendlyErrorMessage(res);
    if (clearDockerData || this.isDockerAvailabilityError(res)) {
      this.dockerAvailable = false;
      this.clearDockerData();
    }
  }

  // ===== 镜像操作（对齐 pullImage / importImage / deleteImage / tagImage） =====

  async pullImage(image: string, registry: string, tag: string, username: string,
    password: string): Promise<boolean> {
    const res = await DockerApiService.pullImage(image, registry, tag, username, password);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    this.currentTab = 'tasks';
    await this.refreshTasks(false);
    const taskId = this.taskIdOf(res);
    if (taskId.length > 0) {
      this.selectTask(taskId, true);
    }
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  async importImage(archivePath: string): Promise<boolean> {
    const res = await DockerApiService.importImage(archivePath);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    this.currentTab = 'tasks';
    await this.refreshTasks(false);
    const taskId = this.taskIdOf(res);
    if (taskId.length > 0) {
      this.selectTask(taskId, true);
    }
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  async deleteImage(imageId: string, reference: string = ''): Promise<boolean> {
    const res = await DockerApiService.deleteImage(imageId, reference);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    await this.refreshImages(false);
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_success', '删除成功'));
    return true;
  }

  async tagImage(imageId: string, repository: string, tag: string,
    sourceReference: string = ''): Promise<boolean> {
    const res = await DockerApiService.tagImage(imageId, repository, tag, sourceReference);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    await this.refreshImages(false);
    await this.refreshContainers(false);
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  // ===== 容器操作（对齐 createContainer / startContainer / stopContainer / deleteContainer） =====

  async createContainer(body: Record<string, Object>): Promise<boolean> {
    const res = await DockerApiService.createContainer(body);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    await this.refreshContainers(false);
    let command = '';
    if (res.data !== undefined) {
      command = dockerRecStr(res.data, 'command').trim();
    }
    if (command.length > 0) {
      await this.copyCommand(command, L10n.t('docker_copy_command_success', '命令已复制'));
    }
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  async startContainer(id: string): Promise<boolean> {
    const res = await DockerApiService.startContainer(id);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    await this.refreshContainers(false);
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  async stopContainer(id: string, timeout: number = 10): Promise<boolean> {
    const res = await DockerApiService.stopContainer(id, timeout);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    await this.refreshContainers(false);
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  async deleteContainer(id: string, force: boolean = false): Promise<boolean> {
    const res = await DockerApiService.deleteContainer(id, force);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    await this.refreshContainers(false);
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_success', '删除成功'));
    return true;
  }

  /** 拉取容器日志（streamOutput=true 时创建跟踪任务并跳到任务页签） */
  async fetchContainerLogs(containerId: string, since: string = '', until: string = '',
    tail: number = 200, streamOutput: boolean = false): Promise<Record<string, Object> | undefined> {
    const res = await DockerApiService.getContainerLogs(containerId, since, until, tail, streamOutput);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return undefined;
    }
    if (streamOutput) {
      this.currentTab = 'tasks';
      await this.refreshTasks(false);
      const taskId = this.taskIdOf(res);
      if (taskId.length > 0) {
        this.selectTask(taskId, true);
      }
    }
    return res.data;
  }

  // ===== 任务操作（对齐 cancelTask / deleteTask） =====

  async cancelTask(taskId: string): Promise<boolean> {
    const normalizedTaskId = taskId.trim();
    // 乐观更新：先本地置为 cancelled，失败回滚（对齐 Flutter 实现）
    let previousTask: DockerTask | undefined = undefined;
    let index = -1;
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id === normalizedTaskId) {
        index = i;
        break;
      }
    }
    if (index >= 0) {
      const snapshot = new DockerTask();
      snapshot.id = this.tasks[index].id;
      snapshot.title = this.tasks[index].title;
      snapshot.type = this.tasks[index].type;
      snapshot.status = this.tasks[index].status;
      snapshot.progress = this.tasks[index].progress;
      snapshot.command = this.tasks[index].command;
      previousTask = snapshot;
      const optimistic = new DockerTask();
      optimistic.id = this.tasks[index].id;
      optimistic.title = this.tasks[index].title;
      optimistic.type = this.tasks[index].type;
      optimistic.status = 'cancelled';
      optimistic.progress = this.tasks[index].progress;
      optimistic.command = this.tasks[index].command;
      this.tasks.splice(index, 1, optimistic);
    }
    const res = await DockerApiService.cancelTask(taskId);
    if (!res.success) {
      if (index >= 0 && previousTask !== undefined) {
        this.tasks.splice(index, 1, previousTask);
      }
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    if (index >= 0 && res.data !== undefined) {
      this.tasks.splice(index, 1, DockerTask.fromJson(res.data!));
    }
    await this.refreshTasks(false);
    if (this.taskLogsPollingEnabled && this.selectedTaskId.trim() === normalizedTaskId) {
      await this.refreshTaskLogs(taskId, false);
    }
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  async deleteTask(taskId: string): Promise<boolean> {
    const res = await DockerApiService.deleteTask(taskId);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    const trimmed = taskId.trim();
    const kept = this.tasks.filter((item: DockerTask): boolean => item.id !== trimmed);
    this.tasks = kept;
    if (this.selectedTaskId.trim() === trimmed) {
      this.selectedTaskId = '';
      this.taskLogsPollingEnabled = false;
      this.taskLogs = [];
    }
    await this.refreshTasks(false);
    ToastUtil.show(L10n.t('delete_success', '删除成功'));
    return true;
  }

  // ===== 配置与服务（对齐 saveProxyConfig / saveConfigContent / toggleDockerService） =====

  async saveProxyConfig(httpProxy: string, httpsProxy: string, noProxy: string): Promise<boolean> {
    const res = await DockerApiService.setProxyConfig(httpProxy, httpsProxy, noProxy);
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    await this.refreshConfig(false);
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  async saveConfigContent(content: string): Promise<boolean> {
    this.savingConfig = true;
    const res = await DockerApiService.saveConfig(content);
    this.savingConfig = false;
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    await this.refreshConfig(false);
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  async toggleDockerService(): Promise<boolean> {
    if (this.dockerServiceOperating) {
      return false;
    }
    this.dockerServiceOperating = true;
    const shouldStart = !this.dockerAvailable;
    const res = shouldStart ? await DockerApiService.startDocker() : await DockerApiService.stopDocker();
    this.dockerServiceOperating = false;
    if (!res.success) {
      this.applyRequestError(res, false);
      ToastUtil.show(this.friendlyErrorMessage(res));
      return false;
    }
    this.currentTab = 'tasks';
    await this.refreshTasks(false);
    const taskId = this.taskIdOf(res);
    if (taskId.length > 0) {
      this.selectTask(taskId, true);
      this.setTaskLogsPolling(true);
      await this.refreshTaskLogs(taskId, false);
    }
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('operation_success', '操作成功'));
    return true;
  }

  // ===== 剪贴板（对齐 copyCommand） =====

  async copyCommand(text: string, toastText: string = ''): Promise<void> {
    if (text.trim().length === 0) {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setPasteData(data);
    ToastUtil.show(toastText.length > 0 ? toastText
      : L10n.t('docker_copy_command_success', '命令已复制'));
  }

  // ===== 错误文案映射（对齐 _friendlyErrorMessage 及各类启发式判断） =====

  private taskIdOf(res: DockerApiResult<Record<string, Object>>): string {
    if (res.data === undefined) {
      return '';
    }
    return dockerRecStr(res.data, 'id').trim();
  }

  private friendlyErrorMessage(res: DockerApiResult<Object>): string {
    const apiErrorKey = res.apiErrorKey.trim();
    const message = res.message.trim();
    if (this.isDockerUnavailable(apiErrorKey, message)) {
      return this.translatedOrFallback('docker_error_daemon_unavailable',
        'Docker 守护进程未启动或无法连接，请先启动 Docker 服务后重试。', message);
    }
    if (this.isDockerCommandMissing(apiErrorKey, message)) {
      return this.translatedOrFallback('docker_error_command_not_found',
        '未检测到 Docker 命令，请先安装 Docker 后重试。', message);
    }
    if (this.isDockerPermissionDenied(message)) {
      return this.translatedOrFallback('docker_error_permission_denied',
        '当前用户无权访问 Docker 套接字，请检查 Docker 权限配置。', message);
    }
    if (this.isDockerImageInUse(apiErrorKey, message)) {
      return this.translatedOrFallback('docker_error_image_in_use',
        '该镜像正被容器使用，无法删除或重命名，请先停止并移除相关容器。', message);
    }
    if (apiErrorKey === 'docker.INVALID_CONFIG_JSON') {
      return this.translatedOrFallback('docker_invalid_config_json',
        'Docker 配置文件格式不正确，请确保内容是合法的 JSON 对象。', message);
    }
    if (apiErrorKey === 'docker.START_FAILED') {
      return this.translatedOrFallback('docker_start_failed',
        '启动 Docker 失败，请检查服务状态或当前用户权限。', message);
    }
    if (apiErrorKey === 'docker.STOP_FAILED') {
      return this.translatedOrFallback('docker_stop_failed',
        '停止 Docker 失败，请检查服务状态或当前用户权限。', message);
    }
    if (apiErrorKey === 'docker.RESTART_FAILED') {
      return this.translatedOrFallback('docker_restart_failed',
        '重启 Docker 失败，请检查服务状态或当前用户权限。', message);
    }
    if (message.length > 0) {
      return message;
    }
    return L10n.t('operation_failed', '操作失败');
  }

  private isDockerAvailabilityError(res: DockerApiResult<Object>): boolean {
    const apiErrorKey = res.apiErrorKey.trim();
    const message = res.message.trim();
    return this.isDockerUnavailable(apiErrorKey, message)
      || this.isDockerCommandMissing(apiErrorKey, message);
  }

  private isDockerUnavailable(apiErrorKey: string, message: string): boolean {
    if (apiErrorKey === 'docker.DOCKER_UNAVAILABLE') {
      return true;
    }
    const lower = message.toLowerCase();
    return lower.includes('cannot connect to the docker daemon')
      || lower.includes('cannot connect to the docker daemon at')
      || lower.includes('failed to connect to the docker api at')
      || lower.includes('check if the path is correct and if the daemon is running')
      || lower.includes('is the docker daemon running')
      || lower.includes('docker daemon is not running')
      || lower.includes('error during connect')
      || lower.includes('this error may indicate that the docker daemon is not running')
      || lower.includes('docker desktop is not running')
      || (lower.includes('dial unix') && lower.includes('docker.sock'))
      || (lower.includes('open //./pipe/docker_engine')
        && lower.includes('the system cannot find the file specified'));
  }

  private isDockerCommandMissing(apiErrorKey: string, message: string): boolean {
    if (apiErrorKey === 'docker.DOCKER_COMMAND_NOT_FOUND') {
      return true;
    }
    const lower = message.toLowerCase();
    return lower.includes('spawn docker enoent')
      || lower.includes('docker: command not found')
      || lower.includes('commandnotfoundexception')
      || (lower.includes('objectnotfound: (docker:string)') && lower.includes('fullyqualifiederrorid'));
  }

  private isDockerPermissionDenied(message: string): boolean {
    const lower = message.toLowerCase();
    return lower.includes('permission denied while trying to connect to the docker daemon socket')
      || lower.includes('dial unix /var/run/docker.sock: connect: permission denied')
      || lower.includes('got permission denied while trying to connect to the docker daemon socket');
  }

  private isDockerImageInUse(apiErrorKey: string, message: string): boolean {
    if (apiErrorKey === 'docker.IMAGE_IN_USE') {
      return true;
    }
    const lower = message.toLowerCase();
    return (lower.includes('conflict') && lower.includes('unable to remove repository reference'))
      || (lower.includes('conflict') && lower.includes('image is being used by running container'))
      || (lower.includes('conflict') && lower.includes('container')
        && lower.includes('is using its referenced image'));
  }

  private translatedOrFallback(key: string, fallback: string, message: string): string {
    const translated = L10n.t(key, fallback);
    if (translated !== key) {
      return translated;
    }
    if (message.length > 0) {
      return message;
    }
    return L10n.t('operation_failed', '操作失败');
  }
}

/** 从 Record 安全读取字符串字段 */
function dockerRecStr(rec: Record<string, Object>, key: string): string {
  const v = rec[key];
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}
