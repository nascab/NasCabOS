import { http } from '@kit.NetworkKit';
import { PreferencesStore } from '../core/storage/PreferencesStore';

const KEY_LAST_CHECK_TIME = 'update_check_last_time_ms';
const KEY_CACHED_JSON = 'update_info_cached_json';
const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;
const BASE_URL = 'https://nas.cab/config/updateInfo';

/** 新版本检测：24 小时最多检测一次，缓存上次成功结果，所有异常内部吞掉不外溢（对应 Flutter UpdateCheckHelper）。 */
export class UpdateCheckHelper {
  /** 平台对应的 JSON 文件名（对应 Flutter _platformId） */
  private static get platformId(): string {
    return 'harmonyos';
  }

  /** 解析并返回缓存的更新信息；解析失败或未缓存返回 undefined。不抛异常。 */
  static getCachedUpdateInfo(): UpdateInfo | undefined {
    try {
      const jsonStr = PreferencesStore.getInstance().getString(KEY_CACHED_JSON);
      if (!jsonStr || jsonStr.trim().length === 0) {
        return undefined;
      }
      const map = JSON.parse(jsonStr) as CachedUpdateJson;
      if (!map) {
        return undefined;
      }
      const newVersion = UpdateCheckHelper.toStr(map.new_version);
      if (newVersion.length === 0) {
        return undefined;
      }
      return new UpdateInfo(newVersion, UpdateCheckHelper.toStr(map.open_url));
    } catch (_e) {
      return undefined;
    }
  }

  private static toStr(v: string | number | undefined): string {
    if (v === undefined || v === null) {
      return '';
    }
    return `${v}`;
  }

  /** 若 newVersion > currentVersion 返回 true，否则 false。异常或格式不符返回 false。 */
  static isNewVersionGreater(newVersion: string, currentVersion: string): boolean {
    try {
      if (newVersion.length === 0 || currentVersion.length === 0) {
        return false;
      }
      const newParts = UpdateCheckHelper.parseVersion(newVersion);
      const curParts = UpdateCheckHelper.parseVersion(currentVersion);
      if (!newParts || !curParts) {
        return false;
      }
      for (let i = 0; i < 3; i++) {
        if (newParts[i] > curParts[i]) {
          return true;
        }
        if (newParts[i] < curParts[i]) {
          return false;
        }
      }
      return false;
    } catch (_e) {
      return false;
    }
  }

  private static parseVersion(v: string): number[] | undefined {
    const parts = v.trim().split('.');
    if (parts.length === 0) {
      return undefined;
    }
    const out: number[] = [];
    for (let i = 0; i < 3; i++) {
      const n = parseInt(i < parts.length ? parts[i].trim() : '0', 10);
      out.push(isNaN(n) ? 0 : n);
    }
    return out;
  }

  /** 执行检测：先读缓存并立即返回；若距上次检测已超过 24 小时则请求并更新缓存。 */
  static async checkForUpdate(currentVersion: string): Promise<boolean> {
    try {
      const cached = UpdateCheckHelper.getCachedUpdateInfo();
      const hasUpdateFromCache = cached !== undefined &&
        UpdateCheckHelper.isNewVersionGreater(cached.newVersion, currentVersion);

      const lastMs = PreferencesStore.getInstance().getInt(KEY_LAST_CHECK_TIME, 0);
      const now = Date.now();
      if (lastMs > 0 && (now - lastMs) < CHECK_INTERVAL_MS) {
        return hasUpdateFromCache;
      }

      const url = `${BASE_URL}/${UpdateCheckHelper.platformId}.json`;
      const body = await UpdateCheckHelper.fetchJson(url);
      if (body.length === 0) {
        return hasUpdateFromCache;
      }
      const map = JSON.parse(body) as CachedUpdateJson;
      const newVersion = map ? UpdateCheckHelper.toStr(map.new_version) : '';
      if (newVersion.length === 0) {
        return hasUpdateFromCache;
      }
      const store = PreferencesStore.getInstance();
      await store.setString(KEY_CACHED_JSON, body);
      await store.setInt(KEY_LAST_CHECK_TIME, now);
      return UpdateCheckHelper.isNewVersionGreater(newVersion, currentVersion);
    } catch (_e) {
      try {
        const cached = UpdateCheckHelper.getCachedUpdateInfo();
        return cached !== undefined &&
          UpdateCheckHelper.isNewVersionGreater(cached.newVersion, currentVersion);
      } catch (_e2) {
        return false;
      }
    }
  }

  /** 请求更新信息 JSON，10 秒超时；非 200 或空 body 返回空串。 */
  private static fetchJson(url: string): Promise<string> {
    return new Promise<string>((resolve) => {
      try {
        const client = http.createHttp();
        client.request(url, {
          method: http.RequestMethod.GET,
          connectTimeout: 10000,
          readTimeout: 10000,
        }).then((resp) => {
          const code = resp.responseCode;
          const body = typeof resp.result === 'string' ? resp.result : '';
          client.destroy();
          if (code !== 200 || body.length === 0) {
            resolve('');
            return;
          }
          resolve(body);
        }).catch(() => {
          client.destroy();
          resolve('');
        });
      } catch (_e) {
        resolve('');
      }
    });
  }

  /** 获取用于展示的更新信息（来自缓存或 undefined）。不抛异常。 */
  static getUpdateInfoIfNewer(currentVersion: string): UpdateInfo | undefined {
    try {
      const cached = UpdateCheckHelper.getCachedUpdateInfo();
      if (!cached) {
        return undefined;
      }
      if (!UpdateCheckHelper.isNewVersionGreater(cached.newVersion, currentVersion)) {
        return undefined;
      }
      return cached;
    } catch (_e) {
      return undefined;
    }
  }
}

export class UpdateInfo {
  readonly newVersion: string;
  readonly openUrl: string;

  constructor(newVersion: string, openUrl: string) {
    this.newVersion = newVersion;
    this.openUrl = openUrl;
  }
}

interface CachedUpdateJson {
  new_version?: string | number;
  open_url?: string | number;
}
