import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREFERENCES_NAME = 'nascab_harmony_prefs';

export class PreferencesStore {
  private static instance: PreferencesStore | undefined = undefined;
  private prefs: preferences.Preferences | undefined = undefined;

  static getInstance(): PreferencesStore {
    if (!PreferencesStore.instance) {
      PreferencesStore.instance = new PreferencesStore();
    }
    return PreferencesStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.prefs) {
      return;
    }
    // 同步初始化：返回时磁盘数据已加载完成，避免页面启动早于初始化完成导致读取/写入失败
    this.prefs = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
  }

  private ensurePrefs(): preferences.Preferences {
    if (!this.prefs) {
      throw new Error('PreferencesStore not initialized');
    }
    return this.prefs;
  }

  async setString(key: string, value: string): Promise<void> {
    const p = this.ensurePrefs();
    await p.put(key, value);
    await p.flush();
  }

  getString(key: string, defaultValue?: string): string | undefined {
    const p = this.ensurePrefs();
    const v = p.getSync(key, defaultValue ?? '') as string;
    if (v === '' && defaultValue === undefined) {
      return undefined;
    }
    return v;
  }

  async setInt(key: string, value: number): Promise<void> {
    const p = this.ensurePrefs();
    await p.put(key, value);
    await p.flush();
  }

  getInt(key: string, defaultValue: number = 0): number {
    return this.ensurePrefs().getSync(key, defaultValue) as number;
  }

  async setBool(key: string, value: boolean): Promise<void> {
    const p = this.ensurePrefs();
    await p.put(key, value);
    await p.flush();
  }

  getBool(key: string, defaultValue: boolean = false): boolean {
    return this.ensurePrefs().getSync(key, defaultValue) as boolean;
  }

  async setJson(key: string, obj: Object): Promise<void> {
    await this.setString(key, JSON.stringify(obj));
  }

  getJson<T>(key: string): T | undefined {
    const raw = this.getString(key);
    if (!raw || raw.trim() === '') {
      return undefined;
    }
    try {
      return JSON.parse(raw) as T;
    } catch (_e) {
      return undefined;
    }
  }

  async remove(key: string): Promise<void> {
    const p = this.ensurePrefs();
    await p.delete(key);
    await p.flush();
  }
}
