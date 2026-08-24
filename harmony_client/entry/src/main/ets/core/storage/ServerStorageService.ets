import { PreferencesStore } from './PreferencesStore';
import { CacheKeys } from './CacheKeys';
import { ServerInfo } from '../../auth/models/ServerInfo';

export class ServerStorageService {
  private static instance: ServerStorageService | undefined = undefined;

  static getInstance(): ServerStorageService {
    if (!ServerStorageService.instance) {
      ServerStorageService.instance = new ServerStorageService();
    }
    return ServerStorageService.instance;
  }

  loadServers(): ServerInfo[] {
    const raw = PreferencesStore.getInstance().getJson<Object[]>(CacheKeys.SAVED_SERVERS);
    if (!raw || !Array.isArray(raw)) {
      return [];
    }
    const list = raw.map((item: Object) => {
      const s = ServerInfo.fromJson(item);
      s.isAutoScanned = false;
      return s;
    });
    return this.dedupeByUniqueKey(list);
  }

  async saveServers(servers: ServerInfo[]): Promise<boolean> {
    const normalized = this.dedupeByUniqueKey(servers);
    const json = normalized.map(s => s.toJson());
    await PreferencesStore.getInstance().setJson(CacheKeys.SAVED_SERVERS, json);
    return true;
  }

  async addServer(server: ServerInfo): Promise<boolean> {
    const current = this.loadServers();
    const key = server.uniqueKey;
    const idx = current.findIndex(s => s.uniqueKey === key);
    if (idx >= 0) {
      current[idx] = ServerInfo.merged(current[idx], server);
    } else {
      current.push(server);
    }
    return this.saveServers(current);
  }

  async removeServer(server: ServerInfo): Promise<boolean> {
    const key = server.uniqueKey;
    const current = this.loadServers().filter(s => s.uniqueKey !== key);
    return this.saveServers(current);
  }

  async updateServer(server: ServerInfo): Promise<boolean> {
    const current = this.loadServers();
    const key = server.uniqueKey;
    const idx = current.findIndex(s => s.uniqueKey === key);
    if (idx < 0) {
      return false;
    }
    current[idx] = ServerInfo.merged(current[idx], server);
    return this.saveServers(current);
  }

  async saveLastSelected(server: ServerInfo): Promise<boolean> {
    await PreferencesStore.getInstance().setJson(CacheKeys.LAST_SELECTED_SERVER, server.toJson());
    return true;
  }

  getLastSelected(): ServerInfo | undefined {
    const raw = PreferencesStore.getInstance().getJson<Object>(CacheKeys.LAST_SELECTED_SERVER);
    if (!raw) {
      return undefined;
    }
    return ServerInfo.fromJson(raw);
  }

  private dedupeByUniqueKey(list: ServerInfo[]): ServerInfo[] {
    const byKey = new Map<string, ServerInfo>();
    const order: string[] = [];
    for (const s of list) {
      const key = s.uniqueKey;
      const existing = byKey.get(key);
      if (existing) {
        byKey.set(key, ServerInfo.merged(existing, s));
      } else {
        byKey.set(key, s);
        order.push(key);
      }
    }
    return order.map(k => byKey.get(k)!).filter(s => s !== undefined);
  }
}
