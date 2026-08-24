import { ServerInfo } from '../auth/models/ServerInfo';
import { ServerStorageService } from '../core/storage/ServerStorageService';
import { CurrentUserStore } from '../core/user/CurrentUserStore';
import { AppsService } from './AppsService';
import { L10n } from '../core/localization/L10n';

@ObservedV2
export class HomeViewModel {
  @Trace currentServer: ServerInfo | undefined = undefined;
  @Trace searchQuery: string = '';
  @Trace serverMessage: string = '';
  @Trace allApps: string[] = [];
  @Trace hideApps: string[] = [];

  private userStore: CurrentUserStore = CurrentUserStore.getInstance();
  private appsService: AppsService = AppsService.getInstance();

  async init(): Promise<void> {
    this.loadAppsFromUser();
    await this.loadServerInfo();
    await this.loadHomeConfig();
  }

  get isAdmin(): boolean {
    return this.userStore.isAdmin;
  }

  get showApps(): string[] {
    return this.allApps
      .filter(a => !this.hideApps.includes(a))
      .filter(a => this.isAdmin || a !== 'backup')
      .filter(a => this.isAdmin || a !== 'process')
      .filter(a => this.matchesSearch(a));
  }

  filteredApps(): string[] {
    return this.showApps;
  }

  private matchesSearch(appId: string): boolean {
    const q = this.searchQuery.trim().toLowerCase();
    if (q.length === 0) {
      return true;
    }
    return appId.toLowerCase().includes(q);
  }

  private loadAppsFromUser(): void {
    this.allApps = this.userStore.allApps.slice();
    this.hideApps = this.userStore.hideApps.slice();
  }

  private async loadServerInfo(): Promise<void> {
    const last = ServerStorageService.getInstance().getLastSelected();
    if (last) {
      this.currentServer = last;
    } else {
      const servers = ServerStorageService.getInstance().loadServers();
      if (servers.length > 0) {
        this.currentServer = servers[0];
      }
    }
  }

  private async loadHomeConfig(): Promise<void> {
    const response = await this.appsService.getHomeConfig();
    if (response.success && response.data) {
      const msg = response.data.message;
      if (msg && msg.length > 0) {
        this.serverMessage = msg;
      }
    }
  }

  getAppDisplayName(appId: string): string {
    switch (appId) {
      case 'files':
        return '文件';
      case 'photo':
        return '相册';
      case 'video':
        return '影视';
      case 'music':
        return '音乐';
      case 'book':
        return '图书';
      case 'notes':
        return '笔记';
      case 'backup':
        return '备份';
      case 'monitor':
        return '监控';
      case 'docker':
        return 'Docker';
      case 'process':
        return '进程';
      case 'service':
        return '服务';
      case 'security':
        return '安全';
      case 'user':
        return '用户';
      case 'task_center':
        return '任务中心';
      default:
        return appId;
    }
  }
}
