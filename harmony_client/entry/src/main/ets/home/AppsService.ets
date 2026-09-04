import { APIClient } from '../core/network/APIClient';
import { APIResponse } from '../core/network/APIResponse';
import { CurrentUserStore } from '../core/user/CurrentUserStore';
import { AppsJson, DeleteWallpaperRespJson, HomeConfigJson, JsonCodec, WallpaperItemJson, WallpaperJson } from '../common/JsonTypes';
import { DeleteWallpaperBody, HideAppsBody, SetAppsOrderBody, SetWallpaperBody } from '../common/HttpTypes';

/** home 模块 API：对应 Flutter apps_api_service.dart */
export class AppsService {
  private static instance: AppsService | undefined = undefined;
  private api: APIClient = APIClient.getInstance();

  static getInstance(): AppsService {
    if (!AppsService.instance) {
      AppsService.instance = new AppsService();
    }
    return AppsService.instance;
  }

  async getHomeConfig(): Promise<APIResponse<HomeConfigJson>> {
    return this.api.apiGet<HomeConfigJson>(
      '/api/home/config',
      undefined,
      undefined,
      undefined,
      (d, _) => JsonCodec.parse<HomeConfigJson>(d)
    );
  }

  async getApps(): Promise<APIResponse<AppsJson>> {
    return this.api.apiGet<AppsJson>(
      '/api/apps/getApps',
      undefined,
      undefined,
      undefined,
      (d, _) => JsonCodec.parse<AppsJson>(d)
    );
  }

  async setHideApps(hideApps: string[]): Promise<APIResponse<AppsJson>> {
    const uid = CurrentUserStore.getInstance().current?.id ?? 0;
    const body = new HideAppsBody(uid, hideApps);
    return this.api.apiPost<AppsJson>(
      '/api/apps/setHideApps',
      body,
      undefined,
      undefined,
      undefined,
      (d, _) => JsonCodec.parse<AppsJson>(d)
    );
  }

  async setAppsOrder(orderApp: string[]): Promise<APIResponse<AppsJson>> {
    const uid = CurrentUserStore.getInstance().current?.id ?? 0;
    const body = new SetAppsOrderBody(uid, orderApp);
    return this.api.apiPost<AppsJson>(
      '/api/apps/setAppsOrder',
      body,
      undefined,
      undefined,
      undefined,
      (d, _) => JsonCodec.parse<AppsJson>(d)
    );
  }
}

/** 外观（壁纸）API：对应 Flutter appearance_api_service.dart */
export class AppearanceService {
  private static instance: AppearanceService | undefined = undefined;
  private api: APIClient = APIClient.getInstance();

  static getInstance(): AppearanceService {
    if (!AppearanceService.instance) {
      AppearanceService.instance = new AppearanceService();
    }
    return AppearanceService.instance;
  }

  async getWallpapers(): Promise<APIResponse<WallpaperItemJson[]>> {
    return this.api.apiGet<WallpaperItemJson[]>(
      '/api/appearance/wallpapers',
      undefined,
      undefined,
      undefined,
      (d, _) => d as WallpaperItemJson[]
    );
  }

  async setWallpaper(mode: string, name?: string): Promise<APIResponse<WallpaperJson>> {
    const body = new SetWallpaperBody(mode, name);
    return this.api.apiPost<WallpaperJson>(
      '/api/appearance/setWallpaper',
      body,
      undefined,
      undefined,
      undefined,
      (d, _) => JsonCodec.parse<WallpaperJson>(d)
    );
  }

  async deleteWallpaper(name: string): Promise<APIResponse<DeleteWallpaperRespJson>> {
    const body = new DeleteWallpaperBody(name);
    return this.api.apiPost<DeleteWallpaperRespJson>(
      '/api/appearance/deleteWallpaper',
      body,
      undefined,
      undefined,
      undefined,
      (d, _) => JsonCodec.parse<DeleteWallpaperRespJson>(d)
    );
  }
}
