import { L10n } from '../../../core/localization/L10n';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { MountItem } from '../models/FileMountModels';
import {
  FileMountApiService, OpenlistMountApiService, OpenlistDriverInfo, MountApiResult, MountApiBase
} from '../services/FileMountApiServices';
import { MountPluginStatus } from '../services/MountPluginStatus';
import { MountPageKeys } from '../router/FileMountRoutes';

/** WinFsp 检测结果缓存有效期 ms（对齐 Flutter 30s） */
const WINFSP_CACHE_MS: number = 30 * 1000;

function opFailed(): string {
  return L10n.t('operation_failed', '操作失败');
}

/**
 * 文件协议挂载控制器（对齐 Flutter FileMountController）。
 * Flutter 端为 Get.put 单例，鸿蒙端保持模块级单例语义（getInstance）。
 */
@ObservedV2
export class FileMountController {
  private static instance: FileMountController | undefined = undefined;

  static getInstance(): FileMountController {
    if (!FileMountController.instance) {
      FileMountController.instance = new FileMountController();
    }
    return FileMountController.instance;
  }

  @Trace currentPageKey: string = MountPageKeys.LIST;
  @Trace mounts: MountItem[] = [];
  @Trace isLoading: boolean = false;
  @Trace errorText: string = '';
  /** 正在执行启停操作的挂载 id 集合（对齐 Flutter opLoadingById） */
  @Trace opLoadingIds: number[] = [];

  private winfspStatusCache: Record<string, Object> | undefined = undefined;
  private winfspStatusCacheAt: number = 0;

  onInit(): void {
    void this.refreshList(false);
  }

  selectPage(key: string): void {
    this.currentPageKey = key;
  }

  private setOpLoading(id: number, loading: boolean): void {
    const next = this.opLoadingIds.slice();
    const idx = next.indexOf(id);
    if (loading && idx < 0) {
      next.push(id);
    } else if (!loading && idx >= 0) {
      next.splice(idx, 1);
    }
    this.opLoadingIds = next;
  }

  isOpLoading(id: number): boolean {
    return this.opLoadingIds.indexOf(id) >= 0;
  }

  async refreshList(showLoading: boolean = true): Promise<void> {
    this.isLoading = true;
    this.errorText = '';
    try {
      if (showLoading) {
        void DialogUtil.showLoading(L10n.t('loading', '加载中...'));
      }
      const res = await FileMountApiService.list();
      if (!res.success) {
        this.errorText = res.message.length > 0 ? res.message : opFailed();
        this.mounts = [];
        return;
      }
      const list: MountItem[] = [];
      MountApiBase.asArray(res.data).forEach((o: Object): void => {
        list.push(MountItem.from(o));
      });
      this.mounts = list;
    } catch (_e) {
      this.errorText = opFailed();
      this.mounts = [];
    } finally {
      if (showLoading) {
        void DialogUtil.dismissLoading(true);
      }
      this.isLoading = false;
    }
  }

  async upsert(id: number | undefined, name: string, mountPath: string, remote: string,
    config: Record<string, Object> | undefined): Promise<boolean> {
    const n = name.trim();
    const mp = mountPath.trim();
    const r = remote.trim();
    if (n.length === 0 || mp.length === 0 || r.length === 0) {
      ToastUtil.show(opFailed());
      return false;
    }
    const res = await FileMountApiService.upsert(id, n, mp, r, config);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : opFailed());
      return false;
    }
    await this.refreshList(false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    return true;
  }

  async remove(id: number): Promise<boolean> {
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('file_mount_delete_confirm', '确定删除该挂载吗？'));
    if (confirmed !== true) {
      return false;
    }
    const res = await FileMountApiService.delete(id);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed', '删除失败'));
      return false;
    }
    await this.refreshList(false);
    ToastUtil.show(L10n.t('delete_success', '删除成功'));
    return true;
  }

  async start(id: number): Promise<void> {
    const plugin = MountPluginStatus.ensure();
    if (!plugin.canUseFileMount) {
      plugin.showNotReadyToast();
      return;
    }
    const allowed = await this.ensureWinfspReady();
    if (!allowed) {
      return;
    }
    this.setOpLoading(id, true);
    const res = await FileMountApiService.start(id);
    this.setOpLoading(id, false);
    if (!res.success) {
      const msg = res.apiErrorKey === 'mountShare.PLUGIN_NOT_READY'
        ? L10n.t('mount_share_plugin_not_ready', '此功能所需插件还未下载完成，请稍后再试。')
        : (res.message.length > 0 ? res.message : opFailed());
      ToastUtil.show(msg);
      await this.refreshList(false);
      return;
    }
    await this.refreshList(false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  async stop(id: number): Promise<void> {
    this.setOpLoading(id, true);
    const res = await FileMountApiService.stop(id);
    this.setOpLoading(id, false);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : opFailed());
      await this.refreshList(false);
      return;
    }
    await this.refreshList(false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  /** WinFsp 环境检测（30s 缓存；Windows 服务端未装 WinFsp 时弹窗阻断，对齐 Flutter） */
  async ensureWinfspReady(force: boolean = false): Promise<boolean> {
    try {
      const now = Date.now();
      if (!force && this.winfspStatusCache !== undefined
        && now - this.winfspStatusCacheAt < WINFSP_CACHE_MS) {
        return FileMountController.handleWinfspStatus(this.winfspStatusCache);
      }
      void DialogUtil.showLoading(L10n.t('file_mount_checking_winfsp', '正在检测 WinFsp 环境...'));
      const res = await FileMountApiService.checkWinfsp();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : opFailed());
        return false;
      }
      const status = MountApiBase.asRecord(res.data);
      this.winfspStatusCache = status;
      this.winfspStatusCacheAt = now;
      return FileMountController.handleWinfspStatus(status);
    } catch (_e) {
      ToastUtil.show(opFailed());
      return false;
    } finally {
      void DialogUtil.dismissLoading(true);
    }
  }

  static handleWinfspStatus(status: Record<string, Object>): boolean {
    const isWindows = status['isWindows'] === true;
    const available = status['available'] === true;
    if (!isWindows || available) {
      return true;
    }
    void DialogUtil.showInfoDialog(
      L10n.t('file_mount_winfsp_required_title', '需要安装 WinFsp'),
      L10n.t('file_mount_winfsp_required_content',
        '当前服务端是 Windows，此功能需要额外的WinFsp驱动。请先在服务端正确安装 WinFsp，'
        + '然后再进行远程挂载。下载地址：https://winfsp.dev/rel'));
    return false;
  }
}

/**
 * 网盘挂载控制器（对齐 Flutter OpenlistMountController）。
 */
@ObservedV2
export class OpenlistMountController {
  private static instance: OpenlistMountController | undefined = undefined;

  static getInstance(): OpenlistMountController {
    if (!OpenlistMountController.instance) {
      OpenlistMountController.instance = new OpenlistMountController();
    }
    return OpenlistMountController.instance;
  }

  @Trace mounts: MountItem[] = [];
  @Trace drivers: OpenlistDriverInfo[] = [];
  @Trace isLoading: boolean = false;
  @Trace isDriversLoading: boolean = false;
  @Trace errorText: string = '';
  @Trace opLoadingIds: number[] = [];

  oauthHelpUrl: string = 'https://api.oplist.org/';

  private winfspStatusCache: Record<string, Object> | undefined = undefined;
  private winfspStatusCacheAt: number = 0;

  onInit(): void {
    void this.refreshList(false);
    void this.loadOauthUrl();
  }

  private async loadOauthUrl(): Promise<void> {
    const res = await OpenlistMountApiService.oauthHelpUrl();
    if (!res.success || res.data === undefined) {
      return;
    }
    const rec = res.data as Record<string, Object>;
    const url = rec['url'] !== undefined ? `${rec['url']}`.trim() : '';
    if (url.length > 0) {
      this.oauthHelpUrl = url;
    }
  }

  async loadDrivers(force: boolean = false): Promise<void> {
    if (!force && this.drivers.length > 0) {
      return;
    }
    this.isDriversLoading = true;
    try {
      const res = await OpenlistMountApiService.drivers();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : opFailed());
        return;
      }
      this.drivers = res.data ?? [];
    } finally {
      this.isDriversLoading = false;
    }
  }

  /** 取驱动 additional 原始值（编辑页解析字段用） */
  driverAdditional(driverName: string): Object | undefined {
    const found = this.drivers.find((d: OpenlistDriverInfo): boolean => d.name === driverName);
    return found !== undefined ? found.additional : undefined;
  }

  /** 驱动自带 docUrl（对齐 Flutter _driverDocUrlFor 的 API 覆盖） */
  driverDocUrlFromApi(driverName: string): string {
    const found = this.drivers.find((d: OpenlistDriverInfo): boolean => d.name === driverName);
    return found !== undefined ? found.docUrl : '';
  }

  private setOpLoading(id: number, loading: boolean): void {
    const next = this.opLoadingIds.slice();
    const idx = next.indexOf(id);
    if (loading && idx < 0) {
      next.push(id);
    } else if (!loading && idx >= 0) {
      next.splice(idx, 1);
    }
    this.opLoadingIds = next;
  }

  isOpLoading(id: number): boolean {
    return this.opLoadingIds.indexOf(id) >= 0;
  }

  async refreshList(showLoading: boolean = true): Promise<void> {
    this.isLoading = true;
    this.errorText = '';
    try {
      if (showLoading) {
        void DialogUtil.showLoading(L10n.t('loading', '加载中...'));
      }
      const res: MountApiResult<Object[]> = await OpenlistMountApiService.list();
      if (!res.success) {
        this.errorText = res.message.length > 0 ? res.message : opFailed();
        this.mounts = [];
        return;
      }
      const list: MountItem[] = [];
      MountApiBase.asArray(res.data).forEach((o: Object): void => {
        list.push(MountItem.from(o));
      });
      this.mounts = list;
    } catch (_e) {
      this.errorText = opFailed();
      this.mounts = [];
    } finally {
      if (showLoading) {
        void DialogUtil.dismissLoading(true);
      }
      this.isLoading = false;
    }
  }

  async upsert(id: number | undefined, name: string, mountPath: string, driver: string,
    addition: Record<string, Object>): Promise<boolean> {
    const config: Record<string, Object> = { 'addition': addition };
    const res = await OpenlistMountApiService.upsert(id, name.trim(), mountPath.trim(),
      driver.trim(), config);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : opFailed());
      return false;
    }
    await this.refreshList(false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    return true;
  }

  async remove(id: number): Promise<boolean> {
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('openlist_mount_delete_confirm', '确定删除该网盘挂载吗？'));
    if (confirmed !== true) {
      return false;
    }
    const res = await OpenlistMountApiService.delete(id);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed', '删除失败'));
      return false;
    }
    await this.refreshList(false);
    ToastUtil.show(L10n.t('delete_success', '删除成功'));
    return true;
  }

  async start(id: number): Promise<void> {
    if (this.isOpLoading(id)) {
      return;
    }
    const plugin = MountPluginStatus.ensure();
    if (!plugin.canUseOpenlistMount) {
      plugin.showNotReadyToast();
      return;
    }
    const allowed = await this.ensureWinfspReady();
    if (!allowed) {
      return;
    }
    this.setOpLoading(id, true);
    ToastUtil.show(L10n.t('openlist_mount_start_sent', '挂载命令已经发送，稍后将刷新状态'));
    const res = await OpenlistMountApiService.start(id);
    this.setOpLoading(id, false);
    if (!res.success) {
      const msg = res.apiErrorKey === 'mountShare.PLUGIN_NOT_READY'
        ? L10n.t('mount_share_plugin_not_ready', '此功能所需插件还未下载完成，请稍后再试。')
        : (res.message.length > 0 ? res.message : opFailed());
      ToastUtil.show(msg);
    }
    await this.refreshList(false);
  }

  async stop(id: number): Promise<void> {
    this.setOpLoading(id, true);
    const res = await OpenlistMountApiService.stop(id);
    this.setOpLoading(id, false);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : opFailed());
      await this.refreshList(false);
      return;
    }
    await this.refreshList(false);
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  async ensureWinfspReady(force: boolean = false): Promise<boolean> {
    try {
      const now = Date.now();
      if (!force && this.winfspStatusCache !== undefined
        && now - this.winfspStatusCacheAt < WINFSP_CACHE_MS) {
        return FileMountController.handleWinfspStatus(this.winfspStatusCache);
      }
      void DialogUtil.showLoading(L10n.t('file_mount_checking_winfsp', '正在检测 WinFsp 环境...'));
      const res = await FileMountApiService.checkWinfsp();
      if (!res.success) {
        ToastUtil.show(res.message.length > 0 ? res.message : opFailed());
        return false;
      }
      const status = MountApiBase.asRecord(res.data);
      this.winfspStatusCache = status;
      this.winfspStatusCacheAt = now;
      return FileMountController.handleWinfspStatus(status);
    } catch (_e) {
      ToastUtil.show(opFailed());
      return false;
    } finally {
      void DialogUtil.dismissLoading(true);
    }
  }
}
