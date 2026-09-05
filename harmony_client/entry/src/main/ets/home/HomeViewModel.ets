import { ServerInfo } from '../auth/models/ServerInfo';
import { ServerStorageService } from '../core/storage/ServerStorageService';
import { APIClient } from '../core/network/APIClient';
import { CurrentUserStore } from '../core/user/CurrentUserStore';
import { AppsService } from './AppsService';
import { AppsJson, JsonCodec } from '../common/JsonTypes';
import { L10n } from '../core/localization/L10n';

/** 首页控制器：对应 Flutter AppHomeController */
@ObservedV2
export class HomeViewModel {
  @Trace currentServer: ServerInfo | undefined = undefined;
  @Trace searchQuery: string = '';
  @Trace serverMessage: string = '';
  @Trace allApps: string[] = [];
  @Trace hideApps: string[] = [];
  /** 语言版本号：切换语言后自增，驱动各卡片刷新 L10n 文案 */
  @Trace localeVersion: number = 0;

  private userStore: CurrentUserStore = CurrentUserStore.getInstance();
  private appsService: AppsService = AppsService.getInstance();

  async init(): Promise<void> {
    this.loadAppsFromUser();
    this.loadServerInfo();
    await this.loadHomeConfig();
  }

  get isAdmin(): boolean {
    return this.userStore.isAdmin;
  }

  /** 可显示的应用列表（对齐 Flutter AppHomeController.showApps） */
  get showApps(): string[] {
    return this.allApps
      .filter((a: string) => !this.hideApps.includes(a))
      .filter((a: string) => this.isAdmin || a !== 'backup')
      .filter((a: string) => this.isAdmin || a !== 'process')
      .filter((a: string) => a !== 'task_center'); // 移动端隐藏任务中心（DeviceUtils.isMobile）
  }

  filteredApps(): string[] {
    const q = this.searchQuery.trim().toLowerCase();
    const visible = this.showApps;
    if (q.length === 0) {
      return visible;
    }
    return visible.filter((e: string) => {
      const k = e.toLowerCase();
      const name = L10n.appDisplayName(e).toLowerCase();
      return k.includes(q) || name.includes(q);
    });
  }

  private loadAppsFromUser(): void {
    this.allApps = this.userStore.allApps.slice();
    this.hideApps = this.userStore.hideApps.slice();
  }

  /** 对齐 Flutter _loadServerInfo：serverId+用户名 优先，其次按 baseUrl 匹配 */
  private loadServerInfo(): void {
    const api = APIClient.getInstance();
    const currentServerId = api.state.serverId.trim();
    const currentBaseUrl = api.state.baseUrl.trim();
    const servers = ServerStorageService.getInstance().loadServers();
    const currentUsername = (this.userStore.current?.username ?? '').trim();

    let server: ServerInfo | undefined = undefined;
    if (currentServerId.length > 0) {
      if (currentUsername.length > 0) {
        server = servers.find((s: ServerInfo) =>
          s.serverId === currentServerId && (s.username ?? '').trim() === currentUsername);
      } else {
        server = servers.find((s: ServerInfo) => s.serverId === currentServerId);
      }
    }
    if (server === undefined) {
      if (currentUsername.length > 0) {
        server = servers.find((s: ServerInfo) =>
          s.serverUrl.trim() === currentBaseUrl && (s.username ?? '').trim() === currentUsername);
      } else {
        server = servers.find((s: ServerInfo) => s.serverUrl.trim() === currentBaseUrl);
      }
    }
    this.currentServer = server;
  }

  private async loadHomeConfig(): Promise<void> {
    try {
      const response = await this.appsService.getHomeConfig();
      if (!response.success) {
        this.serverMessage = '';
        return;
      }
      const msg = (response.data?.newMessage ?? response.data?.message ?? '').trim();
      this.serverMessage = msg;
    } catch (_e) {
      this.serverMessage = '';
    }
  }

  /** 拖拽排序：对齐 Flutter AppHomeController.reorderApp */
  reorderApp(oldIndex: number, newIndex: number): void {
    const visible = this.showApps;
    if (oldIndex < 0 || oldIndex >= visible.length) {
      return;
    }
    if (newIndex < 0 || newIndex >= visible.length) {
      return;
    }
    const item = visible[oldIndex];
    const next = this.allApps.slice();
    const removeIdx = next.indexOf(item);
    if (removeIdx < 0) {
      return;
    }
    next.splice(removeIdx, 1);
    if (newIndex < visible.length) {
      const anchor = visible[newIndex];
      const anchorIdx = next.indexOf(anchor);
      const insertIdx = anchorIdx >= 0 ? anchorIdx : next.length;
      next.splice(insertIdx, 0, item);
    } else {
      next.push(item);
    }
    this.allApps = next;
    void this.saveOrder();
  }

  /** 保存排序：写本地缓存并上报服务端 */
  async saveOrder(): Promise<void> {
    const apps = new AppsJson();
    apps.all_app = this.allApps.slice();
    apps.hide_app = this.hideApps.slice();
    this.userStore.setAppsFromJson(JsonCodec.parse<AppsJson>(apps));
    await this.appsService.setAppsOrder(this.allApps);
  }

  /**
   * 打开应用（对应 Flutter AppHomeController.openApp）。
   * 各子模块迁移完成后在此接入路由；未迁移的模块返回 false 由页面提示。
   */
  openApp(app: string): boolean {
    if (app === 'task_center') {
      return false; // 移动端不开放任务中心
    }
    if (app === 'setting') {
      return true; // 配置中心已迁移，由页面接线路由
    }
    return false;
  }

  /** 切换语言后调用：刷新文案并重载服务器消息 */
  notifyLocaleChanged(): void {
    this.localeVersion++;
    this.init();
  }

  getAppDisplayName(appId: string): string {
    return L10n.appDisplayName(appId);
  }
}
