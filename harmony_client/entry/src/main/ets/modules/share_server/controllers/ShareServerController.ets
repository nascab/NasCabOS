import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { ShareServerPageKeys } from '../router/ShareServerRoutes';
import {
  PortsSaveErrorInfo, ServerPorts, ShareRootPath, ShareServerConfigRecord, ShareUserOption,
  UserShareFolderItem
} from '../models/ShareServerModels';
import {
  FileShareServerApiService, ShareApiResult, UserShareFolderApiService, ShareUserApiService
} from '../services/ShareServerApiServices';

/**
 * 文件服务/用户共享控制器（对齐 Flutter FileShareServerController；@ObservedV2 + @Trace 驱动 V2 刷新）。
 * 随页面创建/销毁（页面 aboutToAppear 调 onInit()，aboutToDisappear 调 onClose()）。
 *
 * 与 Flutter 的差异：
 * - MountPluginStatusService 未迁移到鸿蒙端，start 不做插件就绪校验（横幅同样省略）。
 */
@ObservedV2
export class ShareServerController {
  /** 支持的服务类型（对齐 Flutter supportedTypes） */
  static readonly SUPPORTED_TYPES: string[] = ['WebDav', 'FTP', 'SFTP'];

  private static instance: ShareServerController | undefined = undefined;

  /** 全局单例（主页与端口设置页共享同一份配置/端口状态） */
  static getInstance(): ShareServerController {
    if (!ShareServerController.instance) {
      ShareServerController.instance = new ShareServerController();
    }
    return ShareServerController.instance;
  }

  @Trace currentPageKey: string = ShareServerPageKeys.QUICK;

  /** 各类型配置/端口/状态/操作中标记（key = WebDav/FTP/SFTP） */
  @Trace configsByType: Map<string, ShareServerConfigRecord[]> = new Map();
  @Trace portsByType: Map<string, ServerPorts> = new Map();
  @Trace statusByType: Map<string, string> = new Map();
  @Trace actualPortsByType: Map<string, ServerPorts> = new Map();
  @Trace opLoadingByType: Map<string, boolean> = new Map();

  /** 用户表（key = uid 字符串，对齐 Flutter usersById） */
  @Trace usersById: Map<string, ShareUserOption> = new Map();

  @Trace userShareFolders: UserShareFolderItem[] = [];
  @Trace userShareFoldersLoading: boolean = false;

  private pendingUserShareFoldersRefresh: boolean = false;
  private disposed: boolean = false;

  get isAdmin(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  // ===== 生命周期（对齐 onInit） =====

  onInit(pageKey: string): void {
    // 单例跨页面复用：重开页面时恢复刷新链路
    this.disposed = false;
    const initialKey = pageKey.trim();
    if (initialKey.length > 0) {
      if (initialKey === ShareServerPageKeys.PORTS) {
        // 端口设置在移动端转独立页打开（由页面层处理），主页底层停在快速分享
        this.selectPage(ShareServerPageKeys.QUICK);
      } else {
        this.selectPage(initialKey);
      }
    }
    void this.refreshAll(false);
  }

  onClose(): void {
    this.disposed = true;
  }

  selectPage(key: string): void {
    this.currentPageKey = key;
    if (key === ShareServerPageKeys.QUICK) {
      // 快速分享列表由 QuickShareController 管理
      return;
    }
    if (key === ShareServerPageKeys.WEBDAV) {
      void this.refreshType('WebDav', false);
    } else if (key === ShareServerPageKeys.FTP) {
      void this.refreshType('FTP', false);
    } else if (key === ShareServerPageKeys.SFTP) {
      void this.refreshType('SFTP', false);
    } else if (key === ShareServerPageKeys.USER_FOLDERS) {
      void this.refreshUserShareFolders(false, false);
    }
  }

  /** 刷新用户列表 + 全部类型 + 用户共享目录（对齐 refreshAll） */
  async refreshAll(showLoading: boolean): Promise<void> {
    try {
      if (showLoading) {
        await DialogUtil.showLoading(L10n.loading);
      }
      await this.refreshUsers();
      for (const t of ShareServerController.SUPPORTED_TYPES) {
        await this.refreshType(t, false);
      }
      await this.refreshUserShareFolders(false, false);
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading(true);
      }
    }
  }

  // ===== 用户共享目录（对齐 refreshUserShareFolders/add/remove/setAllowDownload） =====

  async refreshUserShareFolders(showLoading: boolean, force: boolean): Promise<void> {
    if (this.userShareFoldersLoading && !force) {
      this.pendingUserShareFoldersRefresh = true;
      return;
    }
    this.userShareFoldersLoading = true;
    try {
      if (showLoading) {
        await DialogUtil.showLoading(L10n.loading);
      }
      const res = await UserShareFolderApiService.list();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      this.userShareFolders = res.data ?? [];
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading(true);
      }
      this.userShareFoldersLoading = false;
      if (this.pendingUserShareFoldersRefresh && !this.disposed) {
        this.pendingUserShareFoldersRefresh = false;
        await this.refreshUserShareFolders(false, true);
      }
    }
  }

  async addUserShareFolder(path: string, name: string | undefined,
    allowDownload: boolean | undefined): Promise<void> {
    const p = path.trim();
    if (p.length === 0) {
      return;
    }
    const res = await UserShareFolderApiService.add(p, name, allowDownload);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    await this.refreshUserShareFolders(false, true);
    await ShareServerController.delay(200);
    await this.refreshUserShareFolders(false, true);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  async removeUserShareFolder(path: string): Promise<void> {
    const p = path.trim();
    if (p.length === 0) {
      return;
    }
    const res = await UserShareFolderApiService.remove(p);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    await this.refreshUserShareFolders(false, true);
    await ShareServerController.delay(200);
    await this.refreshUserShareFolders(false, true);
    ToastUtil.show(L10n.t('delete_success', '删除成功'));
  }

  async setUserShareAllowDownload(path: string, allowDownload: boolean): Promise<void> {
    const p = path.trim();
    const res = await UserShareFolderApiService.setAllowDownload(p, allowDownload);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    await this.refreshUserShareFolders(false, false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  // ===== 文件服务类型（对齐 refreshType/start/stop/upsert/delete/setPorts） =====

  async refreshType(serverType: string, showLoading: boolean): Promise<void> {
    const type = serverType.trim();
    if (type.length === 0) {
      return;
    }
    try {
      if (showLoading) {
        await DialogUtil.showLoading(L10n.loading);
      }
      const portsRes = await FileShareServerApiService.getPorts(type);
      if (portsRes.success && portsRes.data !== undefined) {
        this.portsByType.set(type, portsRes.data);
      }

      const listRes = await FileShareServerApiService.list(type);
      this.configsByType.set(type, listRes.success ? (listRes.data ?? []) : []);

      const configs = this.configsByType.get(type) ?? [];
      this.statusByType.set(type, ShareServerController.deriveStatusFromRows(configs));

      const actual = ShareServerController.derivePortsFromRows(configs);
      if (actual.httpPort.length > 0 || actual.httpsPort.length > 0) {
        this.actualPortsByType.set(type, actual);
      }
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    } finally {
      if (showLoading) {
        await DialogUtil.dismissLoading(true);
      }
    }
  }

  getStatus(serverType: string): string {
    const s = this.statusByType.get(serverType);
    return s === undefined ? 'stopped' : s;
  }

  /** 展示端口：运行中优先取配置行实际端口（对齐 getDisplayPorts） */
  getDisplayPorts(serverType: string): ServerPorts {
    const status = this.getStatus(serverType);
    if (status === 'running') {
      const actual = this.actualPortsByType.get(serverType);
      if (actual !== undefined && (actual.httpPort.length > 0 || actual.httpsPort.length > 0)) {
        return actual;
      }
    }
    const ports = this.portsByType.get(serverType);
    return ports === undefined ? new ServerPorts() : ports;
  }

  isOpLoading(serverType: string): boolean {
    return this.opLoadingByType.get(serverType) === true;
  }

  async start(serverType: string): Promise<void> {
    const type = serverType.trim();
    if (type.length === 0) {
      return;
    }
    const list = this.configsByType.get(type) ?? [];
    if (list.length === 0) {
      DialogUtil.showErrorDialog(L10n.t('file_share_server_cannot_start_no_config',
        '没有任何用户权限配置，无法启动服务'));
      return;
    }
    this.opLoadingByType.set(type, true);
    const res = await FileShareServerApiService.start(type);
    this.opLoadingByType.set(type, false);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    await this.refreshType(type, false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  async stop(serverType: string): Promise<void> {
    const type = serverType.trim();
    if (type.length === 0) {
      return;
    }
    this.opLoadingByType.set(type, true);
    const res = await FileShareServerApiService.stop(type);
    this.opLoadingByType.set(type, false);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    await this.refreshType(type, false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  async upsertConfig(uid: number, serverType: string, rootPath: ShareRootPath[]): Promise<boolean> {
    const type = serverType.trim();
    if (type.length === 0) {
      return false;
    }
    const res = await FileShareServerApiService.upsert(uid, type, rootPath);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return false;
    }
    await this.refreshType(type, false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    return true;
  }

  async deleteConfig(uid: number, serverType: string): Promise<boolean> {
    const type = serverType.trim();
    if (type.length === 0) {
      return false;
    }
    const res = await FileShareServerApiService.delete(uid, type);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return false;
    }
    await this.refreshType(type, false);
    ToastUtil.show(L10n.t('delete_success', '删除成功'));
    return true;
  }

  /** 保存端口；失败时返回结构化错误信息（fields/suggestedRange），成功返回 undefined */
  async setPorts(serverType: string, httpPort: number | undefined,
    httpsPort: number | undefined): Promise<PortsSaveErrorInfo | undefined> {
    const type = serverType.trim();
    if (type.length === 0) {
      const info = new PortsSaveErrorInfo();
      info.message = L10n.operationFailed;
      info.hitHttp = true;
      info.hitHttps = true;
      return info;
    }
    const res = await FileShareServerApiService.setPorts(type, httpPort, httpsPort);
    if (!res.success) {
      const msg = res.message.length > 0 ? res.message : L10n.operationFailed;
      const details = res.raw !== undefined ? res.raw['details'] : undefined;
      return PortsSaveErrorInfo.fromRaw(msg, details);
    }
    await this.refreshType(type, false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    return undefined;
  }

  // ===== 用户（对齐 _refreshUsers/usernameForUid） =====

  async refreshUsers(): Promise<void> {
    const res = await ShareUserApiService.fetchUsers(100, '');
    if (!res.success) {
      return;
    }
    const map = new Map<string, ShareUserOption>();
    (res.data ?? []).forEach((u: ShareUserOption): void => {
      map.set(`${u.id}`, u);
    });
    this.usersById = map;
  }

  usernameForUid(uid: number): string {
    const u = this.usersById.get(`${uid}`);
    return u === undefined ? '' : u.username;
  }

  configsFor(serverType: string): ShareServerConfigRecord[] {
    const list = this.configsByType.get(serverType);
    return list === undefined ? [] : list;
  }

  // ===== 工具 =====

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  private static deriveStatusFromRows(rows: ShareServerConfigRecord[]): string {
    if (rows.length === 0) {
      return 'stopped';
    }
    const s = rows[0].status;
    if (s === 'running' || s === 'error' || s === 'stopped') {
      return s;
    }
    return 'stopped';
  }

  private static derivePortsFromRows(rows: ShareServerConfigRecord[]): ServerPorts {
    const out = new ServerPorts();
    if (rows.length === 0) {
      return out;
    }
    out.httpPort = rows[0].httpPort;
    out.httpsPort = rows[0].httpsPort;
    return out;
  }
}
