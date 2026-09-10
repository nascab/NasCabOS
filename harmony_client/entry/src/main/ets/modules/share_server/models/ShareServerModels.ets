/**
 * 分享管理模块模型（对齐 Flutter modules/fileShareServer 各 service/controller 使用的原始 Map 结构）。
 * - 用户权限配置（fileServer/list）：{ uid, status, http_port, https_port, root_path: [...] }
 * - 用户共享目录（file/userShareFolder/list）：{ name, path, exists, isDirectory, allowDownload }
 * - 快速分享（quickShare/list）：{ id, path, token, pwd, hasPwd, end_time }
 */

export function bStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

export function bNum(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Math.trunc(v);
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

export function bBool(v: Object | undefined | null): boolean {
  return v === true;
}

/** 对齐 Flutter _toBool：bool/num/字符串宽容解析，非法回退默认值 */
export function permToBool(v: Object | undefined | null, defaultValue: boolean = true): boolean {
  if (v === undefined || v === null) {
    return defaultValue;
  }
  if (typeof v === 'boolean') {
    return v;
  }
  if (typeof v === 'number') {
    return v !== 0;
  }
  const t = `${v}`.trim().toLowerCase();
  if (t === '1' || t === 'true') {
    return true;
  }
  if (t === '0' || t === 'false') {
    return false;
  }
  return defaultValue;
}

/** 单条根路径权限（对齐 Flutter _RootPathRowState + root_path 行结构） */
export class ShareRootPath {
  path: string = '';
  write: boolean = true;
  update: boolean = true;
  delete: boolean = true;

  /** upsert 请求体行结构（write/update/delete 为 0/1 数字，对齐 Flutter） */
  toRecord(): Record<string, Object> {
    const r: Record<string, Object> = {
      'path': this.path,
      'write': this.write ? 1 : 0,
      'update': this.update ? 1 : 0,
      'delete': this.delete ? 1 : 0
    };
    return r;
  }

  /** 宽容解析一行：字符串 → 全权限；Map → 逐字段（对齐 Flutter _normalizeRootPath/_buildInitialRows） */
  static fromRaw(item: Object | undefined | null): ShareRootPath | undefined {
    if (item === undefined || item === null) {
      return undefined;
    }
    const row = new ShareRootPath();
    if (typeof item === 'string') {
      const p = item.trim();
      if (p.length === 0) {
        return undefined;
      }
      row.path = p;
      return row;
    }
    if (typeof item === 'object' && !Array.isArray(item)) {
      const rec = item as Record<string, Object>;
      const p = bStr(rec['path']).trim();
      if (p.length === 0) {
        return undefined;
      }
      row.path = p;
      row.write = permToBool(rec['write']);
      row.update = permToBool(rec['update']);
      row.delete = permToBool(rec['delete']);
      return row;
    }
    return undefined;
  }

  static listFromRaw(v: Object | undefined | null): ShareRootPath[] {
    const out: ShareRootPath[] = [];
    if (v === undefined || v === null) {
      return out;
    }
    if (Array.isArray(v)) {
      (v as Object[]).forEach((item: Object): void => {
        const row = ShareRootPath.fromRaw(item);
        if (row !== undefined) {
          out.push(row);
        }
      });
      return out;
    }
    if (typeof v === 'string') {
      const p = (v as string).trim();
      if (p.length > 0) {
        const row = new ShareRootPath();
        row.path = p;
        out.push(row);
      }
    }
    return out;
  }
}

/** 用户权限配置记录（对齐 Flutter configsByType 里的行 Map） */
export class ShareServerConfigRecord {
  uid: number = 0;
  status: string = '';
  httpPort: string = '';
  httpsPort: string = '';
  rootPath: ShareRootPath[] = [];

  static fromJson(data: Record<string, Object> | undefined | null): ShareServerConfigRecord {
    const c = new ShareServerConfigRecord();
    const d = data ?? {};
    c.uid = bNum(d['uid']);
    c.status = bStr(d['status']);
    c.httpPort = bStr(d['http_port']);
    c.httpsPort = bStr(d['https_port']);
    c.rootPath = ShareRootPath.listFromRaw(d['root_path']);
    return c;
  }
}

/** 用户信息（对齐 Flutter usersById 里的行 Map，仅取展示所需字段） */
export class ShareUserOption {
  id: number = 0;
  username: string = '';

  static fromJson(data: Record<string, Object> | undefined | null): ShareUserOption {
    const u = new ShareUserOption();
    const d = data ?? {};
    u.id = bNum(d['id']);
    u.username = bStr(d['username']);
    return u;
  }
}

/** 用户共享目录条目（对齐 Flutter userShareFolders 行 Map） */
export class UserShareFolderItem {
  name: string = '';
  path: string = '';
  exists: boolean = false;
  isDirectory: boolean = false;
  allowDownload: boolean = false;

  static fromJson(data: Record<string, Object> | undefined | null): UserShareFolderItem {
    const it = new UserShareFolderItem();
    const d = data ?? {};
    it.name = bStr(d['name']);
    it.path = bStr(d['path']);
    it.exists = bBool(d['exists']);
    it.isDirectory = bBool(d['isDirectory']);
    it.allowDownload = bBool(d['allowDownload']);
    return it;
  }
}

/** 快速分享条目（对齐 Flutter _ShareItemCard 使用的行 Map） */
export class QuickShareItem {
  id: number = 0;
  path: string = '';
  token: string = '';
  pwd: string = '';
  hasPwd: boolean = false;
  /** 截止时间毫秒；-1 表示无期限（对齐 Flutter _parseDate 失败/缺失） */
  endTimeMs: number = -1;

  static fromJson(data: Record<string, Object> | undefined | null): QuickShareItem {
    const it = new QuickShareItem();
    const d = data ?? {};
    it.id = bNum(d['id']);
    it.path = bStr(d['path']);
    it.token = bStr(d['token']);
    it.pwd = bStr(d['pwd']);
    it.hasPwd = bBool(d['hasPwd']) || it.pwd.trim().length > 0;
    it.endTimeMs = QuickShareItem.parseEndTime(d['end_time']);
    return it;
  }

  /** 对齐 Flutter _parseDate：秒/毫秒时间戳或 ISO 字符串 */
  private static parseEndTime(v: Object | undefined | null): number {
    if (v === undefined || v === null) {
      return -1;
    }
    if (typeof v === 'number') {
      return v > 9999999999 ? Math.trunc(v) : Math.trunc(v) * 1000;
    }
    const t = Date.parse(`${v}`);
    return Number.isFinite(t) ? t : -1;
  }
}

/** 服务端口展示（http_port/https_port 宽容字符串化） */
export class ServerPorts {
  httpPort: string = '';
  httpsPort: string = '';

  static fromRecord(v: Object | undefined | null): ServerPorts {
    const p = new ServerPorts();
    if (v !== undefined && v !== null && typeof v === 'object' && !Array.isArray(v)) {
      const rec = v as Record<string, Object>;
      p.httpPort = bStr(rec['http_port']);
      p.httpsPort = bStr(rec['https_port']);
    }
    return p;
  }
}

/** 端口设置失败的结构化错误（对齐 Flutter res.rawResponse['details'] 解析） */
export class PortsSaveErrorInfo {
  message: string = '';
  /** true 表示错误关联 http_port 字段 */
  hitHttp: boolean = false;
  /** true 表示错误关联 https_port 字段 */
  hitHttps: boolean = false;
  minPort: string = '';
  maxPort: string = '';

  static fromRaw(rawMessage: string, details: Object | undefined | null): PortsSaveErrorInfo {
    const info = new PortsSaveErrorInfo();
    info.message = rawMessage;
    if (details === undefined || details === null || typeof details !== 'object'
      || Array.isArray(details)) {
      info.hitHttp = true;
      info.hitHttps = true;
      return info;
    }
    const rec = details as Record<string, Object>;
    const fields = rec['fields'];
    const fieldNames: string[] = [];
    if (Array.isArray(fields)) {
      (fields as Object[]).forEach((f: Object): void => {
        fieldNames.push(`${f}`);
      });
    }
    info.hitHttp = fieldNames.length === 0 || fieldNames.indexOf('http_port') >= 0;
    info.hitHttps = fieldNames.length === 0 || fieldNames.indexOf('https_port') >= 0;
    const suggested = rec['suggestedRange'];
    if (suggested !== undefined && suggested !== null && typeof suggested === 'object'
      && !Array.isArray(suggested)) {
      const sRec = suggested as Record<string, Object>;
      const min = sRec['min'];
      const max = sRec['max'];
      info.minPort = min === undefined || min === null ? '' : `${min}`;
      info.maxPort = max === undefined || max === null ? '' : `${max}`;
    }
    return info;
  }
}
