import { APIClient } from '../../../core/network/APIClient';
import { SecurityBlacklistItem, SecurityDevice, secNum } from '../models/SecurityModels';

/**
 * 安全中心 API 服务（对齐 Flutter modules/security/security_api_service.dart）。
 * 请求路径、方法与参数完全一致；GET 走 apiGet，POST 走 apiPost。
 */
export class SecurityApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;
  code: number = 0;

  static ok<D>(data: D | undefined): SecurityApiResult<D> {
    const r = new SecurityApiResult<D>();
    r.success = true;
    r.data = data;
    return r;
  }

  static fail<D>(message: string, code: number = 0): SecurityApiResult<D> {
    const r = new SecurityApiResult<D>();
    r.success = false;
    r.message = message;
    r.code = code;
    return r;
  }
}

export class SecurityConfig {
  banEnabled: boolean = true;
  maxFailedAttempts: number = 5;
  banMinutes: number = 1;
  bypassLanAuth: boolean = true;

  static fromJson(data: Record<string, Object> | undefined | null): SecurityConfig {
    const c = new SecurityConfig();
    const d = data ?? {};
    const enabled = d['banEnabled'];
    if (enabled !== undefined && enabled !== null) {
      c.banEnabled = enabled === true;
    }
    const attempts = d['maxFailedAttempts'];
    if (attempts !== undefined && attempts !== null) {
      c.maxFailedAttempts = secNum(attempts);
    }
    const minutes = d['banMinutes'];
    if (minutes !== undefined && minutes !== null) {
      c.banMinutes = secNum(minutes);
    }
    const bypass = d['bypassLanAuth'];
    if (bypass !== undefined && bypass !== null) {
      c.bypassLanAuth = bypass === true;
    }
    return c;
  }
}

function asRecord(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null) {
    return {} as Record<string, Object>;
  }
  return v as Record<string, Object>;
}

function asArray(v: Object | undefined | null): Object[] {
  if (v === undefined || v === null || !Array.isArray(v)) {
    return [];
  }
  return v as Object[];
}

export class SecurityApiService {
  /** 读取安全配置（GET /api/security/config） */
  static async getConfig(): Promise<SecurityApiResult<SecurityConfig>> {
    const res = await APIClient.getInstance().apiGet<Object>('/api/security/config');
    if (!res.success) {
      return SecurityApiResult.fail<SecurityConfig>(res.message ?? '', res.code ?? 0);
    }
    return SecurityApiResult.ok<SecurityConfig>(SecurityConfig.fromJson(asRecord(res.data)));
  }

  /** 保存安全配置（POST /api/security/config，参数与 Flutter 完全一致） */
  static async setConfig(banEnabled: boolean, maxFailedAttempts: number,
    banMinutes: number, bypassLanAuth: boolean): Promise<SecurityApiResult<Object>> {
    const body: Record<string, Object> = {
      'banEnabled': banEnabled,
      'maxFailedAttempts': maxFailedAttempts,
      'banMinutes': banMinutes,
      'bypassLanAuth': bypassLanAuth
    };
    const res = await APIClient.getInstance().apiPost<Object>('/api/security/config', body);
    if (!res.success) {
      return SecurityApiResult.fail<Object>(res.message ?? '', res.code ?? 0);
    }
    return SecurityApiResult.ok<Object>(res.data);
  }

  /** IP 黑名单列表（GET /api/security/ipBlacklist，取 data.items） */
  static async listIpBlacklist(): Promise<SecurityApiResult<SecurityBlacklistItem[]>> {
    const res = await APIClient.getInstance().apiGet<Object>('/api/security/ipBlacklist');
    if (!res.success) {
      return SecurityApiResult.fail<SecurityBlacklistItem[]>(res.message ?? '', res.code ?? 0);
    }
    const items = asArray(asRecord(res.data)['items']);
    const list: SecurityBlacklistItem[] = [];
    items.forEach((item: Object): void => {
      list.push(SecurityBlacklistItem.fromJson(asRecord(item)));
    });
    return SecurityApiResult.ok<SecurityBlacklistItem[]>(list);
  }

  /** 删除黑名单 IP（POST /api/security/ipBlacklist/delete，body {ip}） */
  static async deleteIpBlacklist(ip: string): Promise<SecurityApiResult<Object>> {
    const body: Record<string, Object> = { 'ip': ip };
    const res = await APIClient.getInstance().apiPost<Object>('/api/security/ipBlacklist/delete', body);
    if (!res.success) {
      return SecurityApiResult.fail<Object>(res.message ?? '', res.code ?? 0);
    }
    return SecurityApiResult.ok<Object>(res.data);
  }

  /** 清空黑名单（POST /api/security/ipBlacklist/clear，body {}） */
  static async clearIpBlacklist(): Promise<SecurityApiResult<Object>> {
    const body: Record<string, Object> = {};
    const res = await APIClient.getInstance().apiPost<Object>('/api/security/ipBlacklist/clear', body);
    if (!res.success) {
      return SecurityApiResult.fail<Object>(res.message ?? '', res.code ?? 0);
    }
    return SecurityApiResult.ok<Object>(res.data);
  }

  /** 已登录设备列表（GET /api/auth/devices，取 data.items） */
  static async listDevices(): Promise<SecurityApiResult<SecurityDevice[]>> {
    const res = await APIClient.getInstance().apiGet<Object>('/api/auth/devices');
    if (!res.success) {
      return SecurityApiResult.fail<SecurityDevice[]>(res.message ?? '', res.code ?? 0);
    }
    const items = asArray(asRecord(res.data)['items']);
    const list: SecurityDevice[] = [];
    items.forEach((item: Object): void => {
      list.push(SecurityDevice.fromJson(asRecord(item)));
    });
    return SecurityApiResult.ok<SecurityDevice[]>(list);
  }

  /** 踢出设备（POST /api/auth/devices/kick，body {deviceId}） */
  static async kickDevice(deviceId: string): Promise<SecurityApiResult<Object>> {
    const body: Record<string, Object> = { 'deviceId': deviceId };
    const res = await APIClient.getInstance().apiPost<Object>('/api/auth/devices/kick', body);
    if (!res.success) {
      return SecurityApiResult.fail<Object>(res.message ?? '', res.code ?? 0);
    }
    return SecurityApiResult.ok<Object>(res.data);
  }
}
