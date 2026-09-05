import { APIClient } from '../core/network/APIClient';
import { APIResponse } from '../core/network/APIResponse';
import { JsonCodec } from '../common/JsonTypes';

/** 服务端配置数据（对应 Flutter _ApiSettingApiService） */
export class ApiSettingConfig {
  httpPort: number = 6789;
  httpsPort: number = 6799;
  expressApiCount: number = 2;
  welcomeText: string = '';
  customHostname: string = '';
  cpuCores: number | undefined = undefined;
}

/** /api/apiSetting/get 原始响应结构 */
export class ApiSettingJson {
  httpPort: Object | undefined = undefined;
  httpsPort: Object | undefined = undefined;
  expressApiCount: Object | undefined = undefined;
  welcomeText: Object | undefined = undefined;
  customHostname: Object | undefined = undefined;
  cpuCores: Object | undefined = undefined;
}

export class SettingsApiService {
  private static instance: SettingsApiService | undefined = undefined;
  private api: APIClient = APIClient.getInstance();

  static getInstance(): SettingsApiService {
    if (!SettingsApiService.instance) {
      SettingsApiService.instance = new SettingsApiService();
    }
    return SettingsApiService.instance;
  }

  async getConfig(): Promise<APIResponse<ApiSettingConfig>> {
    return this.api.apiGet<ApiSettingConfig>(
      '/api/apiSetting/get',
      undefined,
      undefined,
      undefined,
      (d, _) => SettingsApiService.parseConfig(d)
    );
  }

  private static parseConfig(data: Object): ApiSettingConfig {
    const json = JsonCodec.parse<ApiSettingJson>(data);
    const config = new ApiSettingConfig();
    config.httpPort = SettingsApiService.toInt(json.httpPort, 6789);
    config.httpsPort = SettingsApiService.toInt(json.httpsPort, 6799);
    config.expressApiCount = SettingsApiService.toInt(json.expressApiCount, 2);
    const welcome = json.welcomeText;
    config.welcomeText = typeof welcome === 'string' ? welcome.trim() : '';
    const host = json.customHostname;
    config.customHostname = typeof host === 'string' ? host.trim() : '';
    config.cpuCores = SettingsApiService.toIntOrNull(json.cpuCores);
    return config;
  }

  private static toInt(value: Object | undefined, fallback: number): number {
    const v = SettingsApiService.toIntOrNull(value);
    return v === undefined ? fallback : v;
  }

  private static toIntOrNull(value: Object | undefined): number | undefined {
    if (typeof value === 'number') {
      return Math.trunc(value);
    }
    if (typeof value === 'string') {
      const s = value.trim();
      if (s.length === 0) {
        return undefined;
      }
      const n = parseInt(s, 10);
      return isNaN(n) ? undefined : n;
    }
    return undefined;
  }

  async saveConfig(httpPort: number, httpsPort: number, expressApiCount: number): Promise<APIResponse<Object>> {
    const body: Record<string, number> = {
      'httpPort': httpPort,
      'httpsPort': httpsPort,
      'expressApiCount': expressApiCount,
    };
    return this.api.apiPost<Object>('/api/apiSetting/save', body);
  }

  async saveWelcome(welcomeText: string): Promise<APIResponse<Object>> {
    const body: Record<string, string> = { 'welcomeText': welcomeText };
    return this.api.apiPost<Object>('/api/apiSetting/saveWelcome', body);
  }

  async restartService(): Promise<APIResponse<Object>> {
    return this.api.apiPost<Object>('/api/apiSetting/restart');
  }

  async setCustomHostname(customHostname: string): Promise<APIResponse<Object>> {
    const body: Record<string, string> = { 'customHostname': customHostname };
    return this.api.apiPost<Object>('/api/appearance/setCustomHostname', body);
  }
}
