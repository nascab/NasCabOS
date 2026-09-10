import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { TransmissionApiService, TransmissionApiResult } from '../services/TransmissionApiService';
import {
  TorrentRecord, TorrentFileEntry, TORRENT_FIELDS, TORRENT_SORT_KEYS, TORRENT_SORT_LABEL_KEYS
} from '../models/TransmissionModels';

/** 服务器版本要求（对齐 Flutter _requiredServerVersion） */
const REQUIRED_SERVER_VERSION = 9;
/** 最近一次下载目录缓存 key 前缀 */
const LAST_DOWNLOAD_DIR_KEY_PREFIX = 'transmission_last_download_dir';
/** 轮询间隔：运行中 3s；停止后退避 3s*2^n，上限 60s（对齐 Flutter 常量） */
const POLL_INTERVAL_RUNNING_MS = 3000;
const POLL_INTERVAL_STOPPED_BASE_MS = 3000;
const POLL_INTERVAL_STOPPED_MAX_MS = 60000;

/** 区间裁剪 */
function clampNum(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

/** 从记录中取第一个存在的数字字段 */
function firstNum(rec: Record<string, Object>, keys: string[]): number {
  for (const k of keys) {
    const v = rec[k];
    if (typeof v === 'number' && Number.isFinite(v)) {
      return v;
    }
  }
  return 0;
}

/** 读取本地 .torrent 文件并 base64 编码（对齐 Flutter metainfo = base64Encode(bytes)） */
async function readTorrentBase64(uri: string): Promise<string> {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const stat = fileIo.statSync(file.fd);
    const buf = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buf);
    return new util.Base64Helper().encodeToStringSync(new Uint8Array(buf));
  } finally {
    fileIo.closeSync(file);
  }
}

/**
 * Transmission 控制器（对齐 Flutter TransmissionController；@ObservedV2 + @Trace 驱动 V2 刷新）。
 * 控制器随页面创建销毁（对齐 Flutter GetBuilder init/dispose 生命周期），含 3s 轮询与退避。
 */
@ObservedV2
export class TransmissionController {
  @Trace currentTab: string = 'overview';
  @Trace status: Record<string, Object> = {};
  @Trace config: Record<string, Object> = {};
  @Trace session: Record<string, Object> = {};
  @Trace sessionStats: Record<string, Object> = {};
  @Trace torrents: TorrentRecord[] = [];

  @Trace serviceOperating: boolean = false;
  @Trace loadingTorrents: boolean = false;
  @Trace savingConfig: boolean = false;
  @Trace torrentFilter: string = 'all';
  @Trace torrentSortKey: string = 'added_desc';
  @Trace errorText: string = '';
  /** 单任务操作 loading（对齐 Flutter opLoadingById；整体替换触发刷新） */
  @Trace opLoadingById: Map<number, boolean> = new Map<number, boolean>();

  private pollTimer: number = -1;
  private closed: boolean = false;
  private lowVersionDialogShown: boolean = false;
  private pollIntervalMs: number = POLL_INTERVAL_RUNNING_MS;
  private stoppedPollBackoffStep: number = 0;

  onInit(): void {
    this.closed = false;
    if (this.isServerVersionTooLow()) {
      this.errorText = L10n.t('server_version_too_low',
        '您的服务端版本过低，请升级到最新版本并重新登录后再使用此功能');
      this.showLowVersionDialogOnce();
      return;
    }
    void this.refreshAll(false);
    this.startPolling();
  }

  onClose(): void {
    this.closed = true;
    this.cancelPollTimer();
  }

  // ===== 服务器版本（对齐 ServerVersionUtil.isAtLeast(serverVersion, 9)） =====

  isServerVersionTooLow(): boolean {
    const ver = `${APIClient.getInstance().state.serverVersion ?? ''}`.trim();
    const parts = ver.split('.');
    const major = parts.length > 0 ? Number(parts[0]) : 0;
    return !(Number.isFinite(major) && major >= REQUIRED_SERVER_VERSION);
  }

  private showLowVersionDialogOnce(): void {
    if (this.lowVersionDialogShown) {
      return;
    }
    this.lowVersionDialogShown = true;
    DialogUtil.showInfoDialog(L10n.tip,
      L10n.t('server_version_too_low', '您的服务端版本过低，请升级到最新版本并重新登录后再使用此功能'));
  }

  // ===== 轮询（对齐 _startPolling / _runPollTick / 退避策略） =====

  private resetPollInterval(): void {
    this.stoppedPollBackoffStep = 0;
    this.pollIntervalMs = POLL_INTERVAL_RUNNING_MS;
  }

  private cancelPollTimer(): void {
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private startPolling(): void {
    this.cancelPollTimer();
    this.resetPollInterval();
    this.scheduleNextPoll();
  }

  private scheduleNextPoll(): void {
    this.cancelPollTimer();
    if (this.closed) {
      return;
    }
    this.pollTimer = setTimeout((): void => {
      this.pollTimer = -1;
      void this.runPollTick();
    }, this.pollIntervalMs);
  }

  private async runPollTick(): Promise<void> {
    if (this.closed) {
      return;
    }
    try {
      if (this.isServerVersionTooLow()) {
        return;
      }
      if (this.isRunning()) {
        this.resetPollInterval();
        await this.refreshTorrents(false);
        await this.refreshSession();
      } else {
        await this.refreshStatus(false);
        if (!this.isRunning()) {
          this.stoppedPollBackoffStep = Math.min(this.stoppedPollBackoffStep + 1, 5);
          const seconds = Math.min(POLL_INTERVAL_STOPPED_MAX_MS / 1000,
            POLL_INTERVAL_STOPPED_BASE_MS / 1000 * (1 << (this.stoppedPollBackoffStep - 1)));
          this.pollIntervalMs = seconds * 1000;
        } else {
          this.resetPollInterval();
        }
      }
    } catch (_e) {
      // 轮询失败不中断循环（对齐 Flutter 仅 debug 打日志）
    } finally {
      this.scheduleNextPoll();
    }
  }

  // ===== 派生状态 =====

  isRunning(): boolean {
    return this.status['running'] === true;
  }

  /** 配置端口展示（configured_rpc_port → rpc_port → '-'） */
  get configuredPortText(): string {
    return this.portText(['configured_rpc_port', 'rpc_port']);
  }

  /** 实际端口展示（actual_rpc_port → '-'） */
  get actualPortText(): string {
    return this.portText(['actual_rpc_port']);
  }

  get portMismatch(): boolean {
    return this.status['port_mismatch'] === true;
  }

  get lastError(): string {
    const v = this.status['last_error'];
    if (v === undefined || v === null) {
      return '';
    }
    return `${v}`;
  }

  private portText(keys: string[]): string {
    for (const k of keys) {
      const v = this.status[k];
      if (typeof v === 'number' && Number.isFinite(v)) {
        return `${v}`;
      }
      if (typeof v === 'string' && v.length > 0) {
        return v;
      }
    }
    return '-';
  }

  isOpLoading(id: number): boolean {
    return this.opLoadingById.get(id) === true;
  }

  private setOpLoading(id: number, loading: boolean): void {
    const next = new Map<number, boolean>(this.opLoadingById);
    if (loading) {
      next.set(id, true);
    } else {
      next.delete(id);
    }
    this.opLoadingById = next;
  }

  // ===== 最近下载目录（对齐 loadLastDownloadDir / validateAndSaveLastDownloadDir） =====

  private lastDownloadDirKey(): string {
    const serverId = `${APIClient.getInstance().state.serverId ?? ''}`.trim();
    return serverId.length === 0
      ? LAST_DOWNLOAD_DIR_KEY_PREFIX
      : `${LAST_DOWNLOAD_DIR_KEY_PREFIX}_${serverId}`;
  }

  /** 读取缓存目录；不可写时清缓存并返回 '' */
  async loadLastDownloadDir(): Promise<string> {
    const cached = (PreferencesStore.getInstance().getString(this.lastDownloadDirKey()) ?? '').trim();
    if (cached.length === 0) {
      return '';
    }
    if (!await this.isDownloadDirUsable(cached)) {
      await PreferencesStore.getInstance().remove(this.lastDownloadDirKey());
      return '';
    }
    return cached;
  }

  /** 校验目录可写并缓存为最近使用 */
  async validateAndSaveLastDownloadDir(dir: string): Promise<boolean> {
    const path = dir.trim();
    if (path.length === 0) {
      return false;
    }
    if (!await this.isDownloadDirUsable(path)) {
      return false;
    }
    await PreferencesStore.getInstance().setString(this.lastDownloadDirKey(), path);
    return true;
  }

  private isDownloadDirUsable(dir: string): Promise<boolean> {
    return TransmissionApiService.isServerDirWritable(dir);
  }

  // ===== 刷新（对齐 refreshAll / refreshStatus / refreshConfig / refreshSession / refreshTorrents） =====

  async refreshAll(showLoading: boolean): Promise<void> {
    await this.refreshStatus(showLoading);
    await this.refreshConfig(false);
    if (this.isRunning()) {
      await this.refreshSession();
      await this.refreshTorrents(false);
    }
  }

  async refreshStatus(showLoading: boolean = false): Promise<void> {
    try {
      if (showLoading) {
        void DialogUtil.showLoading(L10n.loading);
      }
      const res = await TransmissionApiService.getStatus();
      if (res.success) {
        this.status = res.data as Record<string, Object>;
      }
    } catch (_e) {
      // 静默（对齐 Flutter _logRefreshError）
    } finally {
      if (showLoading) {
        void DialogUtil.dismissLoading(true);
      }
    }
  }

  async refreshConfig(showLoading: boolean = false): Promise<void> {
    try {
      if (showLoading) {
        void DialogUtil.showLoading(L10n.loading);
      }
      const res = await TransmissionApiService.getConfig();
      if (res.success) {
        this.config = res.data as Record<string, Object>;
      }
    } catch (_e) {
      // 静默
    } finally {
      if (showLoading) {
        void DialogUtil.dismissLoading(true);
      }
    }
  }

  async refreshSession(): Promise<void> {
    if (!this.isRunning()) {
      return;
    }
    try {
      const res = await TransmissionApiService.getSession();
      if (res.success) {
        const data = res.data as Record<string, Object>;
        const s = data['session'];
        const stats = data['stats'];
        if (s !== undefined && s !== null && typeof s === 'object' && !Array.isArray(s)) {
          this.session = s as Record<string, Object>;
        }
        if (stats !== undefined && stats !== null && typeof stats === 'object' && !Array.isArray(stats)) {
          this.sessionStats = stats as Record<string, Object>;
        }
      }
    } catch (_e) {
      // 静默
    }
  }

  async refreshTorrents(showLoading: boolean = false): Promise<void> {
    if (!this.isRunning()) {
      this.torrents = [];
      return;
    }
    if (this.loadingTorrents && !showLoading) {
      return;
    }
    this.loadingTorrents = true;
    try {
      if (showLoading) {
        void DialogUtil.showLoading(L10n.loading);
      }
      const res = await TransmissionApiService.listTorrents([], TORRENT_FIELDS);
      if (res.success) {
        const list = (res.data as Record<string, Object>)['torrents'];
        if (Array.isArray(list)) {
          const next: TorrentRecord[] = [];
          (list as Object[]).forEach((e: Object): void => {
            next.push(TorrentRecord.fromJson(e as Record<string, Object>));
          });
          this.torrents = next;
        } else {
          this.torrents = [];
        }
      }
    } catch (_e) {
      // 静默
    } finally {
      this.loadingTorrents = false;
      if (showLoading) {
        void DialogUtil.dismissLoading(true);
      }
    }
  }

  // ===== 筛选与排序（对齐 filteredTorrents / displayTorrents / _compareTorrents） =====

  get filteredTorrents(): TorrentRecord[] {
    const filter = this.torrentFilter;
    return this.torrents.filter((t: TorrentRecord): boolean => {
      const s = t.status;
      if (filter === 'downloading') {
        return s === 4;
      }
      if (filter === 'seeding') {
        return s === 6;
      }
      if (filter === 'paused') {
        return s === 0;
      }
      if (filter === 'error') {
        return t.error !== 0;
      }
      return true;
    });
  }

  get displayTorrents(): TorrentRecord[] {
    const list = this.filteredTorrents.slice();
    return list.sort((a: TorrentRecord, b: TorrentRecord): number => this.compareTorrents(a, b));
  }

  torrentSortLabel(key: string): string {
    const labelKey = TORRENT_SORT_LABEL_KEYS[key];
    return labelKey === undefined ? key : L10n.t(labelKey);
  }

  get torrentSortKeys(): string[] {
    return TORRENT_SORT_KEYS;
  }

  private compareTorrents(a: TorrentRecord, b: TorrentRecord): number {
    const sort = this.torrentSortKey;
    let cmp = 0;
    if (sort === 'added_asc') {
      cmp = a.addedDate - b.addedDate;
    } else if (sort === 'name_asc') {
      cmp = TransmissionController.cmpText(a.name.toLowerCase(), b.name.toLowerCase());
    } else if (sort === 'name_desc') {
      cmp = TransmissionController.cmpText(b.name.toLowerCase(), a.name.toLowerCase());
    } else if (sort === 'progress_desc') {
      cmp = b.percentDone - a.percentDone;
    } else if (sort === 'progress_asc') {
      cmp = a.percentDone - b.percentDone;
    } else if (sort === 'size_desc') {
      cmp = this.torrentDisplayTotalSize(b) - this.torrentDisplayTotalSize(a);
    } else if (sort === 'size_asc') {
      cmp = this.torrentDisplayTotalSize(a) - this.torrentDisplayTotalSize(b);
    } else if (sort === 'download_speed_desc') {
      cmp = b.rateDownload - a.rateDownload;
    } else if (sort === 'upload_speed_desc') {
      cmp = b.rateUpload - a.rateUpload;
    } else if (sort === 'ratio_desc') {
      cmp = b.uploadRatio - a.uploadRatio;
    } else if (sort === 'ratio_asc') {
      cmp = a.uploadRatio - b.uploadRatio;
    } else {
      // added_desc（默认）
      cmp = b.addedDate - a.addedDate;
    }
    if (cmp !== 0) {
      return cmp;
    }
    const ascSort = sort.endsWith('_asc');
    return ascSort ? a.id - b.id : b.id - a.id;
  }

  private static cmpText(x: string, y: string): number {
    if (x < y) {
      return -1;
    }
    if (x > y) {
      return 1;
    }
    return 0;
  }

  // ===== 任务状态展示（对齐 isTorrentFinished / canShowTorrentStart / canShowTorrentPause / statusLabelForTorrent） =====

  isTorrentFinished(t: TorrentRecord): boolean {
    if (t.isFinished) {
      return true;
    }
    if (t.status === 6) {
      return true;
    }
    return t.percentDone >= 1.0;
  }

  canShowTorrentStart(t: TorrentRecord): boolean {
    if (this.isTorrentFinished(t)) {
      return false;
    }
    return t.status === 0;
  }

  canShowTorrentPause(t: TorrentRecord): boolean {
    if (this.isTorrentFinished(t)) {
      return false;
    }
    return t.status !== 0;
  }

  statusLabelForTorrent(t: TorrentRecord): string {
    if (t.error !== 0) {
      return L10n.t('transmission_status_error', '错误');
    }
    switch (t.status) {
      case 4:
        return L10n.t('transmission_status_downloading', '下载中');
      case 6:
        return L10n.t('transmission_status_seeding', '做种');
      case 0:
        return L10n.t('transmission_status_stopped', '已停止');
      case 2:
        return L10n.t('transmission_status_checking', '校验中');
      default:
        return L10n.t('transmission_status_queued', '排队中');
    }
  }

  // ===== 大小折算（对齐 torrentDisplayTotalSize / torrentDisplayDownloadedBytes） =====

  torrentDisplayTotalSize(t: TorrentRecord): number {
    if (t.displayTotalSize > 0) {
      return t.displayTotalSize;
    }
    if (t.sizeWhenDone > 0) {
      return t.sizeWhenDone;
    }
    return t.totalSize;
  }

  torrentDisplayDownloadedBytes(t: TorrentRecord): number {
    if (t.displayDownloadedBytes >= 0) {
      const total = this.torrentDisplayTotalSize(t);
      if (total > 0) {
        return clampNum(t.displayDownloadedBytes, 0, total);
      }
      if (t.displayDownloadedBytes > 0) {
        return t.displayDownloadedBytes;
      }
    }
    const total = this.torrentDisplayTotalSize(t);
    if (t.sizeWhenDone > 0) {
      return clampNum(t.sizeWhenDone - t.leftUntilDone, 0, t.sizeWhenDone);
    }
    const percent = t.percentDone;
    if (total > 0 && percent > 0) {
      return clampNum(total * percent, 0, total);
    }
    const have = t.haveValid + t.haveUnchecked;
    if (have > 0) {
      return total > 0 ? clampNum(have, 0, total) : have;
    }
    return t.downloadedEver;
  }

  // ===== 服务控制（对齐 toggleService / restartService / saveConfig） =====

  async toggleService(enabled: boolean): Promise<void> {
    if (this.serviceOperating) {
      return;
    }
    if (enabled && this.isRunning()) {
      await this.refreshStatus(false);
      return;
    }
    if (!enabled && !this.isRunning()) {
      await this.refreshStatus(false);
      return;
    }
    this.serviceOperating = true;
    try {
      void DialogUtil.showLoading(enabled
        ? L10n.t('transmission_starting', '正在启动...')
        : L10n.t('transmission_stopping', '正在停止...'));
      const res = enabled
        ? await TransmissionApiService.startService()
        : await TransmissionApiService.stopService();
      if (res.success) {
        ToastUtil.show(enabled
          ? L10n.t('transmission_started', 'Transmission 已启动')
          : L10n.t('transmission_stopped', 'Transmission 已停止'));
        await this.refreshAll(false);
        this.resetPollInterval();
      } else {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      }
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      this.serviceOperating = false;
      void DialogUtil.dismissLoading(true);
    }
  }

  async restartService(): Promise<void> {
    if (this.serviceOperating) {
      return;
    }
    this.serviceOperating = true;
    try {
      void DialogUtil.showLoading(L10n.t('transmission_restarting', '正在重启...'));
      const res = await TransmissionApiService.restartService();
      if (res.success) {
        ToastUtil.show(L10n.t('transmission_restarted', 'Transmission 已重启'));
        await this.refreshAll(false);
        this.resetPollInterval();
      } else {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      }
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      this.serviceOperating = false;
      void DialogUtil.dismissLoading(true);
    }
  }

  async saveConfig(body: Record<string, Object | null>): Promise<void> {
    if (this.savingConfig) {
      return;
    }
    this.savingConfig = true;
    try {
      void DialogUtil.showLoading(L10n.loading);
      const res = await TransmissionApiService.saveConfig(body as Object);
      if (res.success) {
        ToastUtil.show(L10n.t('transmission_config_saved', '配置已保存'));
        if (res.data !== undefined && res.data['needs_restart'] === true) {
          ToastUtil.show(L10n.t('transmission_restart_required', '部分配置需重启服务后生效'));
        }
        await this.refreshConfig(false);
      } else {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      }
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      this.savingConfig = false;
      void DialogUtil.dismissLoading(true);
    }
  }

  // ===== 任务操作（对齐 addTorrent / setTorrentDownloadDir / start / stop / remove / files） =====

  /**
   * 添加任务：magnetOrUrl / 本地 torrent 文件 uri / 服务器种子文件路径 三选一。
   */
  async addTorrent(magnetOrUrl: string, torrentFileUri: string, serverTorrentPath: string,
    downloadDir: string, paused: boolean = false): Promise<void> {
    const url = magnetOrUrl.trim();
    const serverPath = serverTorrentPath.trim();
    if (url.length === 0 && torrentFileUri.trim().length === 0 && serverPath.length === 0) {
      return;
    }
    const dir = downloadDir.trim();
    if (dir.length === 0) {
      ToastUtil.show(L10n.t('transmission_task_download_dir_required', '请选择保存目录'));
      return;
    }
    try {
      void DialogUtil.showLoading(L10n.loading);
      let res: TransmissionApiResult<Record<string, Object>>;
      if (serverPath.length > 0) {
        res = await TransmissionApiService.addTorrent('', '', serverPath, dir, paused);
      } else if (torrentFileUri.trim().length > 0) {
        const metainfo = await readTorrentBase64(torrentFileUri.trim());
        res = await TransmissionApiService.addTorrent('', metainfo, '', dir, paused);
      } else {
        res = await TransmissionApiService.addTorrent(url, '', '', dir, paused);
      }
      if (res.success) {
        ToastUtil.show(L10n.t('transmission_torrent_added', '任务已添加'));
        await this.refreshTorrents(false);
      } else {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      }
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      void DialogUtil.dismissLoading(true);
    }
  }

  async setTorrentDownloadDir(id: number, location: string): Promise<void> {
    const path = location.trim();
    if (path.length === 0) {
      return;
    }
    this.setOpLoading(id, true);
    try {
      const res = await TransmissionApiService.setTorrentLocation([id], path);
      if (res.success) {
        await this.refreshTorrents(false);
      } else {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      }
    } finally {
      this.setOpLoading(id, false);
    }
  }

  /** 任务文件列表；失败抛出错误信息（调用方展示） */
  async loadTorrentFiles(id: number): Promise<TorrentFileEntry[]> {
    const res = await TransmissionApiService.getTorrentFiles(id);
    if (!res.success) {
      throw new Error(res.message.length > 0 ? res.message : L10n.operationFailed);
    }
    const list = (res.data as Record<string, Object>)['files'];
    if (!Array.isArray(list)) {
      return [];
    }
    const out: TorrentFileEntry[] = [];
    (list as Object[]).forEach((e: Object): void => {
      out.push(TorrentFileEntry.fromJson(e as Record<string, Object>));
    });
    return out;
  }

  /** 保存任务文件选中项；失败抛出错误信息（调用方展示） */
  async saveTorrentFilesSelection(torrentId: number, wantedByIndex: Map<number, boolean>): Promise<void> {
    if (wantedByIndex.size === 0) {
      return;
    }
    const filesWanted: number[] = [];
    const filesUnwanted: number[] = [];
    wantedByIndex.forEach((wanted: boolean, index: number): void => {
      if (wanted) {
        filesWanted.push(index);
      } else {
        filesUnwanted.push(index);
      }
    });
    const res = await TransmissionApiService.setTorrentFiles(torrentId, filesWanted, filesUnwanted);
    if (!res.success) {
      throw new Error(res.message.length > 0 ? res.message : L10n.operationFailed);
    }
    await this.refreshTorrents(false);
  }

  async startTorrent(id: number): Promise<void> {
    this.setOpLoading(id, true);
    try {
      const res = await TransmissionApiService.startTorrents([id]);
      if (res.success) {
        await this.refreshTorrents(false);
      }
    } finally {
      this.setOpLoading(id, false);
    }
  }

  async stopTorrent(id: number): Promise<void> {
    this.setOpLoading(id, true);
    try {
      const res = await TransmissionApiService.stopTorrents([id]);
      if (res.success) {
        await this.refreshTorrents(false);
      }
    } finally {
      this.setOpLoading(id, false);
    }
  }

  async removeTorrent(id: number, deleteLocalData: boolean = false): Promise<void> {
    this.setOpLoading(id, true);
    try {
      const res = await TransmissionApiService.removeTorrents([id], deleteLocalData);
      if (res.success) {
        await this.refreshTorrents(false);
      }
    } finally {
      this.setOpLoading(id, false);
    }
  }

  // ===== 总览统计（对齐 overviewTotalDownloaded / overviewTotalUploaded） =====

  get overviewTotalDownloaded(): number {
    const fromStats = firstNum(this.sessionStats,
      ['downloadedBytes', 'cumulativeDownloadedBytes']);
    if (fromStats > 0) {
      return fromStats;
    }
    let sum = 0;
    this.torrents.forEach((t: TorrentRecord): void => {
      sum += this.torrentDisplayDownloadedBytes(t);
    });
    return sum;
  }

  get overviewTotalUploaded(): number {
    const fromStats = firstNum(this.sessionStats, ['uploadedBytes', 'cumulativeUploadedBytes']);
    if (fromStats > 0) {
      return fromStats;
    }
    let sum = 0;
    this.torrents.forEach((t: TorrentRecord): void => {
      sum += t.uploadedEver;
    });
    return sum;
  }

  // ===== 格式化（对齐 formatBytes / formatSpeed / formatRatio） =====

  formatBytes(value: number = 0): string {
    const v = value;
    if (v < 1024) {
      return `${v.toFixed(0)} B`;
    }
    if (v < 1024 * 1024) {
      return `${(v / 1024).toFixed(1)} KB`;
    }
    if (v < 1024 * 1024 * 1024) {
      return `${(v / 1024 / 1024).toFixed(1)} MB`;
    }
    return `${(v / 1024 / 1024 / 1024).toFixed(2)} GB`;
  }

  formatSpeed(value: number = 0): string {
    return `${this.formatBytes(value)}/s`;
  }

  formatRatio(value: number = 0): string {
    const v = value;
    if (v < 0) {
      return '-';
    }
    return v.toFixed(2);
  }
}
