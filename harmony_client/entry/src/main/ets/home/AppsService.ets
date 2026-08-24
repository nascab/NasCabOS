import { APIClient } from '../core/network/APIClient';
import { APIResponse } from '../core/network/APIResponse';
import { CurrentUserStore } from '../core/user/CurrentUserStore';
import { AppsJson, HomeConfigJson, JsonCodec } from '../common/JsonTypes';
import { HideAppsBody } from '../common/HttpTypes';

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
}
