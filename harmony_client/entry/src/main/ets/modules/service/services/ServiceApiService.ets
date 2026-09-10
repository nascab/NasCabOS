import { APIClient } from '../../../core/network/APIClient';
import { APIResponse } from '../../../core/network/APIResponse';
import { svcRecord } from '../models/ServiceModels';

/** nas.cab 官网地址（对齐 Flutter NasCabEndpoints.websiteBaseUrl） */
export const NASCAB_WEBSITE_BASE_URL: string = 'https://nas.cab';

/**
 * 提取响应的业务错误码字符串（对齐 Flutter `res.rawResponse['code']` 读取，
 * 如 P2P.ERR_DEVICE_COUNT_LIMIT / P2P_CUSTOM_PAIR_CODE_TAKEN）。
 */
export function svcBusinessCode(res: APIResponse<Object>): string {
  const code = res.rawResponse?.code;
  if (code === undefined || code === null) {
    return '';
  }
  return `${code}`.trim();
}

/**
 * NasCab 账号 / P2P 远程访问 / DDNS API（对齐 Flutter NasCabAccountApiService，
 * 路径与请求参数完全一致；data 均取信封 data 字段原始 JSON 对象）。
 */
export class ServiceApiService {
  /** 查询 NasCab 账号信息（未绑定时 data 为空对象） */
  static query(): Promise<APIResponse<Object>> {
    return APIClient.getInstance().apiGet<Object>('/api/service/nascab/query');
  }

  /** 使用 jwt 登录 */
  static login(jwt: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'jwt': jwt };
    return APIClient.getInstance().apiPost<Object>('/api/service/nascab/login', body);
  }

  /** 使用登录回调的临时 code 登录（避免 JWT 暴露在 URL 中） */
  static loginWithCode(code: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'code': code };
    return APIClient.getInstance().apiPost<Object>('/api/service/nascab/login', body);
  }

  static logout(): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {};
    return APIClient.getInstance().apiPost<Object>('/api/service/nascab/logout', body);
  }

  static refresh(): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {};
    return APIClient.getInstance().apiPost<Object>('/api/service/nascab/refresh', body);
  }

  static getP2pPairCode(): Promise<APIResponse<Object>> {
    return APIClient.getInstance().apiGet<Object>('/api/service/nascab/p2p/pairCode');
  }

  static resetP2pPairCode(): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {};
    return APIClient.getInstance().apiPost<Object>('/api/service/nascab/p2p/pairCode/reset', body);
  }

  static customP2pPairCode(pairCode: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'pairCode': pairCode };
    return APIClient.getInstance().apiPost<Object>('/api/service/nascab/p2p/pairCode/custom', body);
  }

  static getP2pRemoteAccess(): Promise<APIResponse<Object>> {
    return APIClient.getInstance().apiGet<Object>('/api/service/nascab/p2p/remoteAccess');
  }

  static setP2pRemoteAccess(enabled: boolean): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'enabled': enabled };
    return APIClient.getInstance().apiPost<Object>('/api/service/nascab/p2p/remoteAccess', body);
  }

  static setP2pNodePreference(domain: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'domain': domain };
    return APIClient.getInstance().apiPost<Object>('/api/service/nascab/p2p/nodePreference', body);
  }

  /** 绑定当前设备到 NasCab 账号（用于 P2P 远程连接） */
  static bindP2pDevice(): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {};
    return APIClient.getInstance().apiPost<Object>('/api/service/nascab/p2p/bindDevice', body);
  }

  /** 获取官网临时 code，用于打开 https://nas.cab/user/[path]?code=xxx */
  static getTempCode(): Promise<APIResponse<Object>> {
    return APIClient.getInstance().apiGet<Object>('/api/service/nascab/tempCode');
  }

  static getDdnsStatus(): Promise<APIResponse<Object>> {
    return APIClient.getInstance().apiGet<Object>('/api/service/ddns/status');
  }

  static setDdnsDomain(ddnsDomain: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'ddnsDomain': ddnsDomain };
    return APIClient.getInstance().apiPost<Object>('/api/service/ddns/domain', body);
  }

  static setDdnsType(ddnsType: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'ddnsType': ddnsType };
    return APIClient.getInstance().apiPost<Object>('/api/service/ddns/type', body);
  }

  static setDdnsEnabled(enabled: boolean): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'enabled': enabled };
    return APIClient.getInstance().apiPost<Object>('/api/service/ddns/enabled', body);
  }

  /** 从响应 data 中提取 PairCode（reset/custom 接口返回 {'pairCode': ...}） */
  static pairCodeOf(res: APIResponse<Object>): string {
    const data = svcRecord(res.data);
    return `${data['pairCode'] ?? ''}`.trim();
  }
}
