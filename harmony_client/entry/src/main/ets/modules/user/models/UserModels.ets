/**
 * 用户管理模块模型（对齐 Flutter modules/user 各组件直接读取的 Map<String, dynamic> 字段，
 * 以及 modules/transfer/models/file_operation_log.dart 的 FileOperationLog/FileLogListResponse）。
 * 字段沿用服务器 snake_case 原始 key（与 Flutter 端读取方式一致）。
 */

export function uStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

export function uNum(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Math.trunc(v);
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

export function uBool(v: Object | undefined | null): boolean {
  return v === true || v === 1;
}

function pad2(n: number): string {
  return `${n < 10 ? '0' : ''}${n}`;
}

function formatEpochMs(ms: number): string {
  const dt = new Date(ms);
  return `${dt.getFullYear()}-${pad2(dt.getMonth() + 1)}-${pad2(dt.getDate())} `
    + `${pad2(dt.getHours())}:${pad2(dt.getMinutes())}:${pad2(dt.getSeconds())}`;
}

/**
 * 登录记录时间格式化（对齐 CustomLoginRecordCard.formatLocalTime）：
 * 数字 > ~2001-09-09 的秒级阈值视为毫秒，其余为秒；字符串先尝试整数再尝试 ISO 解析；
 * 无法解析时原样返回。
 */
export function formatUserTime(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'number') {
    const isMs = v > 10000000000;
    return formatEpochMs(isMs ? v : v * 1000);
  }
  const s = `${v}`;
  const n = Number(s);
  if (Number.isFinite(n) && s.trim().length > 0 && /^-?\d+$/.test(s.trim())) {
    const isMs = n > 10000000000;
    return formatEpochMs(isMs ? n : n * 1000);
  }
  const t = Date.parse(s);
  if (Number.isFinite(t)) {
    return formatEpochMs(t);
  }
  return s;
}

/** 文件操作日志时间格式化（对齐 FileLogItem._formatTime：毫秒 → yyyy-MM-dd HH:mm:ss） */
export function formatLogTime(timestamp: number): string {
  if (timestamp === undefined || timestamp === null || timestamp <= 0) {
    return '-';
  }
  return formatEpochMs(timestamp);
}

/** 用户记录（服务器 /api/user/list items） */
export class UserProfile {
  id: number = 0;
  username: string = '';
  /** 用户类型：user / admin / super_admin */
  type: string = '';
  phone: string = '';
  userRemark: string = '';
  isActive: boolean = true;

  static fromJson(data: Record<string, Object> | undefined | null): UserProfile {
    const u = new UserProfile();
    const d = data ?? {};
    u.id = uNum(d['id']);
    u.username = uStr(d['username']);
    u.type = uStr(d['type']);
    if (u.type.length === 0) {
      u.type = 'user';
    }
    u.phone = uStr(d['phone']);
    u.userRemark = uStr(d['user_remark']);
    const active = d['is_active'];
    u.isActive = active === undefined || active === null ? true : uBool(active);
    return u;
  }
}

/** 登录记录（服务器 /api/user/login-records items） */
export class LoginRecord {
  browser: string = '';
  deviceInfo: string = '';
  os: string = '';
  /** 原始时间值（数字秒/毫秒或字符串），展示时用 formatUserTime */
  createTimeRaw: Object | undefined = undefined;

  static fromJson(data: Record<string, Object> | undefined | null): LoginRecord {
    const r = new LoginRecord();
    const d = data ?? {};
    r.browser = uStr(d['browser']);
    r.deviceInfo = uStr(d['device_info']);
    r.os = uStr(d['os']);
    r.createTimeRaw = d['create_time'];
    return r;
  }

  /** 设备图标语义（对齐 CustomLoginRecordCard._iconForRecord：移动端 → phone，其余 → display） */
  isMobile(): boolean {
    const os = this.os.toLowerCase();
    const device = this.deviceInfo.toLowerCase();
    return os.includes('android') || os.includes('ios') || device.includes('mobile');
  }
}

/** 单条权限记录（服务器权限接口的扁平条目） */
export class UserPermissionItem {
  resType: string = 'file';
  resPath: string = '';
  action: string = '';

  static fromJson(data: Record<string, Object> | undefined | null): UserPermissionItem {
    const p = new UserPermissionItem();
    const d = data ?? {};
    const t = d['res_type'];
    p.resType = t === undefined || t === null ? 'file' : uStr(t);
    p.resPath = uStr(d['res_path']);
    p.action = uStr(d['action']);
    return p;
  }

  toBody(): Record<string, Object> {
    const m: Record<string, Object> = {
      'res_type': this.resType,
      'res_path': this.resPath,
      'action': this.action
    };
    return m;
  }
}

/** 按目录聚合后的权限条目（对齐 CustomPermissionEditorController 的 items） */
export class PermissionGroup {
  resType: string = 'file';
  resPath: string = '';
  actions: string[] = [];
}

/** 将扁平权限列表按 res_type|res_path 聚合（对齐 _initializeItems） */
export function groupPermissions(items: UserPermissionItem[]): PermissionGroup[] {
  const order: string[] = [];
  const grouped: Map<string, PermissionGroup> = new Map();
  items.forEach((p: UserPermissionItem): void => {
    if (p.resPath.length === 0 || p.action.length === 0) {
      return;
    }
    const key = `${p.resType}|${p.resPath}`;
    const exist = grouped.get(key);
    if (exist === undefined) {
      const g = new PermissionGroup();
      g.resType = p.resType;
      g.resPath = p.resPath;
      g.actions.push(p.action);
      grouped.set(key, g);
      order.push(key);
    } else if (!exist.actions.includes(p.action)) {
      exist.actions.push(p.action);
    }
  });
  const result: PermissionGroup[] = [];
  order.forEach((k: string): void => {
    const g = grouped.get(k);
    if (g !== undefined) {
      result.push(g);
    }
  });
  return result;
}

/** 将聚合条目拍平为服务器条目（对齐 autoSave 的 flattened 结构） */
export function flattenPermissions(groups: PermissionGroup[]): UserPermissionItem[] {
  const result: UserPermissionItem[] = [];
  groups.forEach((g: PermissionGroup): void => {
    g.actions.forEach((a: string): void => {
      const it = new UserPermissionItem();
      it.resType = g.resType;
      it.resPath = g.resPath;
      it.action = a;
      result.push(it);
    });
  });
  return result;
}

/** 文件操作日志（对齐 FileOperationLog） */
export class FileOperationLog {
  id: number = 0;
  type: string = '';
  sourcePath: string[] = [];
  targetPath: string = '';
  uid: number = 0;
  state: string = '';
  message: string = '';
  totalSize: number = 0;
  copiedSize: number = 0;
  /** 毫秒时间戳（<=0 视为无） */
  createTime: number = 0;

  static fromJson(data: Record<string, Object> | undefined | null): FileOperationLog {
    const log = new FileOperationLog();
    const d = data ?? {};
    log.id = uNum(d['id']);
    log.type = uStr(d['type']);
    log.sourcePath = parseSourcePath(d['source_path']);
    log.targetPath = uStr(d['target_path']);
    log.uid = uNum(d['uid']);
    log.state = uStr(d['state']);
    log.message = uStr(d['message']);
    log.totalSize = uNum(d['total_size']);
    log.copiedSize = uNum(d['copied_size']);
    log.createTime = uNum(d['create_time']);
    return log;
  }

  /** 进度（对齐 FileOperationLog.progress） */
  progress(): number {
    if (this.totalSize === 0) {
      return 0;
    }
    if (this.copiedSize === 0) {
      return 0;
    }
    return this.copiedSize / this.totalSize;
  }

  /** 状态色语义：SUCCESS/PROCESSING/WAIT → 主色，ERROR/CANCELLED/INTERRUPTED → 错误色 */
  isErrorState(): boolean {
    return this.state === 'ERROR' || this.state === 'CANCELLED' || this.state === 'INTERRUPTED';
  }
}

function parseSourcePath(v: Object | undefined | null): string[] {
  if (v === undefined || v === null) {
    return [];
  }
  if (typeof v === 'string') {
    try {
      const decoded: Object = JSON.parse(v);
      if (Array.isArray(decoded)) {
        const arr: string[] = [];
        (decoded as Object[]).forEach((e: Object): void => {
          arr.push(`${e}`);
        });
        return arr;
      }
    } catch (_e) {
      // 非 JSON 串时按单路径处理
    }
    return [`${v}`];
  }
  if (Array.isArray(v)) {
    const arr: string[] = [];
    (v as Object[]).forEach((e: Object): void => {
      arr.push(`${e}`);
    });
    return arr;
  }
  return [`${v}`];
}

/** 文件日志分页响应（对齐 FileLogListResponse） */
export class FileLogListResponse {
  list: FileOperationLog[] = [];
  total: number = 0;
  page: number = 1;
  pageSize: number = 20;

  static fromJson(data: Record<string, Object> | undefined | null): FileLogListResponse {
    const r = new FileLogListResponse();
    const d = data ?? {};
    const rawList = d['list'];
    if (Array.isArray(rawList)) {
      (rawList as Object[]).forEach((e: Object): void => {
        r.list.push(FileOperationLog.fromJson(e as Record<string, Object>));
      });
    }
    r.total = uNum(d['total']);
    r.page = uNum(d['page']);
    r.pageSize = uNum(d['pageSize']);
    return r;
  }
}
