import { PreferencesStore } from '../storage/PreferencesStore';
import { CacheKeys } from '../storage/CacheKeys';
import { AppsJson, JsonCodec, UserJson, WallpaperJson } from '../../common/JsonTypes';

export class CurrentUser {
  id: number = 0;
  username: string = '';
  role: string = '';
  /** 用户类型，对齐 Flutter CurrentUser.type（'super_admin' / 'admin' / 其它） */
  type: string = '';
  isAdmin: boolean = false;
}

@ObservedV2
export class CurrentUserStore {
  private static instance: CurrentUserStore | undefined = undefined;

  @Trace current: CurrentUser | undefined = undefined;
  @Trace allApps: string[] = [];
  @Trace hideApps: string[] = [];
  @Trace wallpaperUrl: string | undefined = undefined;

  static getInstance(): CurrentUserStore {
    if (!CurrentUserStore.instance) {
      CurrentUserStore.instance = new CurrentUserStore();
    }
    return CurrentUserStore.instance;
  }

  get isLoggedIn(): boolean {
    return this.current !== undefined;
  }

  get isAdmin(): boolean {
    // 对齐 Flutter CurrentUserController.isAdmin：按用户 type 字段判定
    return this.current?.type === 'super_admin' || this.current?.type === 'admin';
  }

  loadFromCache(): void {
    const userRaw = PreferencesStore.getInstance().getString(CacheKeys.USER_INFO, '');
    if (userRaw && userRaw.length > 0) {
      this.setUserFromJson(JsonCodec.parseStr<UserJson>(userRaw));
    }
    const appsRaw = PreferencesStore.getInstance().getString(CacheKeys.USER_APPS, '');
    if (appsRaw && appsRaw.length > 0) {
      this.setAppsFromJson(JsonCodec.parseStr<AppsJson>(appsRaw));
    }
    const wallpaperRaw = PreferencesStore.getInstance().getString(CacheKeys.USER_WALLPAPER, '');
    if (wallpaperRaw && wallpaperRaw.length > 0) {
      this.setWallpaperFromJson(JsonCodec.parseStr<WallpaperJson>(wallpaperRaw));
    }
  }

  setUserFromJson(map: UserJson): void {
    const user = new CurrentUser();
    user.id = map.id ?? 0;
    user.username = map.username ?? '';
    user.role = map.role ?? '';
    user.type = map.type ?? '';
    // 兼容旧缓存：无 type 时回退 role/isAdmin
    user.isAdmin = user.type === 'super_admin' || user.type === 'admin'
      || (user.type.length === 0 && (map.isAdmin === true || user.role === 'admin'));
    this.current = user;
    void PreferencesStore.getInstance().setString(CacheKeys.USER_INFO, JSON.stringify(map));
  }

  setAppsFromJson(map: AppsJson): void {
    this.allApps = map.all_app ?? [];
    this.hideApps = map.hide_app ?? [];
    void PreferencesStore.getInstance().setString(CacheKeys.USER_APPS, JSON.stringify(map));
  }

  setWallpaperFromJson(map: WallpaperJson): void {
    this.wallpaperUrl = map.url;
    void PreferencesStore.getInstance().setString(CacheKeys.USER_WALLPAPER, JSON.stringify(map));
  }

  clear(): void {
    this.current = undefined;
    this.allApps = [];
    this.hideApps = [];
    this.wallpaperUrl = undefined;
    const store = PreferencesStore.getInstance();
    void store.remove(CacheKeys.USER_INFO);
    void store.remove(CacheKeys.USER_APPS);
    void store.remove(CacheKeys.USER_WALLPAPER);
  }
}
