/**
 * 安全中心模型（对齐 Flutter security 模块 controller 中 Map<String, dynamic> 的服务端记录）。
 * 字段沿用服务器 snake_case 原始 key（与 Flutter 端读取方式一致）。
 */

export function secStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

export function secNum(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Math.trunc(v);
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

export function secBool(v: Object | undefined | null): boolean {
  return v === true || v === 1;
}

/** 时间戳/时间串 → 本地 "yyyy-MM-dd HH:mm:ss"（对齐 Flutter 两个面板的 _formatTime 合并语义） */
export function formatSecurityTime(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'number') {
    if (v <= 0) {
      return '';
    }
    return formatEpochMs(v);
  }
  const s = `${v}`.trim();
  if (s.length === 0) {
    return '';
  }
  if (/^-?\d+$/.test(s)) {
    const ms = Number(s);
    if (ms <= 0) {
      return '';
    }
    return formatEpochMs(ms);
  }
  const t = Date.parse(s);
  if (!Number.isFinite(t)) {
    return s;
  }
  return formatEpochMs(t);
}

function formatEpochMs(ms: number): string {
  const dt = new Date(ms);
  const pad = (n: number): string => `${n < 10 ? '0' : ''}${n}`;
  return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())} `
    + `${pad(dt.getHours())}:${pad(dt.getMinutes())}:${pad(dt.getSeconds())}`;
}

/** IP 黑名单条目（服务器 /api/security/ipBlacklist items，Flutter 读 ip/description/createTime） */
export class SecurityBlacklistItem {
  ip: string = '';
  description: string = '';
  /** 创建时间（毫秒时间戳，<=0 视为无） */
  createTime: number = 0;

  static fromJson(data: Record<string, Object> | undefined | null): SecurityBlacklistItem {
    const it = new SecurityBlacklistItem();
    const d = data ?? {};
    it.ip = secStr(d['ip']);
    it.description = secStr(d['description']);
    it.createTime = secNum(d['createTime']);
    return it;
  }
}

/**
 * 已登录设备（服务器 /api/auth/devices items）。
 * deviceTypeRaw 为设备类型原始串（Flutter _deviceIcon 的多字段回退拼接结果），
 * 仅用于本地图标匹配，不上屏。
 */
export class SecurityDevice {
  deviceName: string = '';
  deviceId: string = '';
  firstSeenAt: string = '';
  lastSeenAt: string = '';
  osVersion: string = '';
  trusted: boolean = false;
  deviceTypeRaw: string = '';

  static fromJson(data: Record<string, Object> | undefined | null): SecurityDevice {
    const it = new SecurityDevice();
    const d = data ?? {};
    it.deviceName = secStr(d['device_name'] ?? d['device_id']);
    it.deviceId = secStr(d['device_id']);
    it.firstSeenAt = secStr(d['first_seen_at']);
    it.lastSeenAt = secStr(d['last_seen_at']);
    it.osVersion = secStr(d['os_version']);
    it.trusted = secBool(d['trusted_flag']);
    // 对齐 Flutter _deviceIcon：device_type→platform→os→client_type→client_name→device_name 依次回退
    const raw = d['device_type'] ?? d['platform'] ?? d['os'] ?? d['client_type']
      ?? d['client_name'] ?? d['device_name'] ?? '';
    it.deviceTypeRaw = secStr(raw).toLowerCase();
    return it;
  }
}
