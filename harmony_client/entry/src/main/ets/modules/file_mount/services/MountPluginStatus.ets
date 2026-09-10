import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { MountPluginApiService, MountApiResult } from './FileMountApiServices';
import { recBool } from '../models/FileMountModels';

/**
 * 挂载插件状态服务（对齐 Flutter MountPluginStatusService）：
 * 轮询 /api/plugin/mountLibsStatus（3s 间隔，全部就绪或超 600 次后停止）；
 * 旧版服务端（< v10 或版本未知）使用内置插件，直接视为就绪，无需检查。
 * 模块内单例：Flutter 端为 core 通用服务，鸿蒙端随本模块先落地于此，
 * 后续 mount_share 等模块迁移时可上移为公共设施。
 */
@ObservedV2
export class MountPluginStatus {
  private static instance: MountPluginStatus | undefined = undefined;

  static ensure(): MountPluginStatus {
    if (!MountPluginStatus.instance) {
      MountPluginStatus.instance = new MountPluginStatus();
    }
    return MountPluginStatus.instance;
  }

  /** 引入 /api/plugin/mountLibsStatus 的最低服务端版本 */
  private static readonly MIN_SERVER_VERSION_FOR_PLUGIN_CHECK: number = 10;
  /** 轮询间隔 ms（对齐 Flutter Timer.periodic 3s） */
  private static readonly POLL_INTERVAL_MS: number = 3000;
  private static readonly POLL_MAX_COUNT: number = 600;

  @Trace statusKnown: boolean = false;
  @Trace remoteAssetsEnabled: boolean = false;
  @Trace fileMountReady: boolean = false;
  @Trace openlistMountReady: boolean = false;
  @Trace fileServerReady: boolean = false;
  @Trace syncing: boolean = false;

  private pollTimer: number = -1;
  private pollCount: number = 0;

  /** 解析主版本号（对齐 Flutter ServerVersionUtil.parseMajorVersion） */
  static parseMajorVersion(version: string): number | undefined {
    const trimmed = version.trim();
    if (trimmed.length === 0) {
      return undefined;
    }
    const normalized = trimmed.startsWith('v') || trimmed.startsWith('V')
      ? trimmed.substring(1) : trimmed;
    const parts = normalized.split('.');
    if (parts.length === 0) {
      return undefined;
    }
    const m = /(\d+)/.exec(parts[0]);
    if (m === null) {
      return undefined;
    }
    const v = Number.parseInt(m[1], 10);
    return Number.isFinite(v) ? v : undefined;
  }

  /** 是否需要轮询插件状态；旧版服务端使用内置插件，无需检查（未知版本视为不支持检查） */
  private shouldCheckPlugin(): boolean {
    const version = APIClient.getInstance().state.serverVersion ?? '';
    const major = MountPluginStatus.parseMajorVersion(version);
    return major !== undefined && major >= MountPluginStatus.MIN_SERVER_VERSION_FOR_PLUGIN_CHECK;
  }

  get canUseFileMount(): boolean {
    if (!this.shouldCheckPlugin()) {
      return true;
    }
    return this.statusKnown && (!this.remoteAssetsEnabled || this.fileMountReady);
  }

  get canUseOpenlistMount(): boolean {
    if (!this.shouldCheckPlugin()) {
      return true;
    }
    return this.statusKnown && (!this.remoteAssetsEnabled || this.openlistMountReady);
  }

  private applyStatus(data: Record<string, Object>): void {
    this.statusKnown = true;
    this.remoteAssetsEnabled = recBool(data, 'enabled');
    if (!this.remoteAssetsEnabled) {
      this.fileMountReady = true;
      this.openlistMountReady = true;
      this.fileServerReady = true;
      this.syncing = false;
      return;
    }
    this.fileMountReady = recBool(data, 'fileMountReady');
    this.openlistMountReady = recBool(data, 'openlistMountReady');
    this.fileServerReady = recBool(data, 'fileServerReady');
    this.syncing = recBool(data, 'syncing');
  }

  async refreshStatus(): Promise<void> {
    if (!this.shouldCheckPlugin()) {
      return;
    }
    const res: MountApiResult<Object> = await MountPluginApiService.getStatus();
    if (!res.success || res.data === undefined) {
      return;
    }
    this.applyStatus(res.data as Record<string, Object>);
  }

  showNotReadyToast(): void {
    ToastUtil.show(L10n.t('mount_share_plugin_not_ready', '此功能所需插件还未下载完成，请稍后再试。'));
  }

  startPolling(forceRestart: boolean = false): void {
    if (!this.shouldCheckPlugin()) {
      // 旧版服务端使用内置插件，无需轮询，直接标记就绪
      this.stopPolling();
      this.statusKnown = true;
      this.remoteAssetsEnabled = false;
      this.fileMountReady = true;
      this.openlistMountReady = true;
      this.fileServerReady = true;
      this.syncing = false;
      return;
    }
    if (forceRestart) {
      this.stopPolling();
      this.pollCount = 0;
    }
    if (this.pollTimer >= 0) {
      return;
    }
    void this.refreshStatus();
    this.pollTimer = setInterval((): void => {
      this.pollCount++;
      void this.refreshStatus().then((): void => {
        const allReady = this.fileMountReady && this.openlistMountReady && this.fileServerReady;
        if (allReady && !this.syncing) {
          this.stopPolling();
        } else if (this.pollCount > MountPluginStatus.POLL_MAX_COUNT) {
          this.stopPolling();
        }
      });
    }, MountPluginStatus.POLL_INTERVAL_MS);
  }

  stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  /** 进入页面时调用（对齐 Flutter ensurePolling：立即刷新一次并保证轮询进行中） */
  ensurePolling(): void {
    this.startPolling(this.pollTimer < 0);
    void this.refreshStatus();
  }
}
