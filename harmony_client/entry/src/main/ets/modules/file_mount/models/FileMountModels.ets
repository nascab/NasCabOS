/**
 * 远程挂载模块数据模型（对齐 Flutter fileMount 模块 Map<String, dynamic> 的字段访问）。
 * 服务端返回的挂载条目/网盘驱动为动态 JSON，这里统一收口为强类型模型。
 */

/** 通用取值工具（对齐 Flutter `item['x']?.toString()` 容错语义） */
export function recStr(rec: Record<string, Object>, key: string): string {
  const v = rec[key];
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

export function recNum(rec: Record<string, Object>, key: string): number {
  const raw = recStr(rec, key).trim();
  const v = Number.parseInt(raw, 10);
  return Number.isFinite(v) ? v : 0;
}

export function recBool(rec: Record<string, Object>, key: string): boolean {
  const v = rec[key];
  if (v === true || v === 1) {
    return true;
  }
  const s = recStr(rec, key).trim().toLowerCase();
  return s === 'true' || s === '1';
}

export function recRecord(rec: Record<string, Object>, key: string): Record<string, Object> {
  const v = rec[key];
  if (v !== undefined && v !== null && typeof v === 'object' && !Array.isArray(v)) {
    return v as Record<string, Object>;
  }
  return {} as Record<string, Object>;
}

/**
 * 挂载条目（文件协议挂载与网盘挂载共用字段面，对齐 Flutter 列表项读取方式）。
 */
export class MountItem {
  id: number = 0;
  name: string = '';
  mountPath: string = '';
  remote: string = '';
  status: string = 'stopped';
  /** 网盘挂载：驱动名（如 aliyundriveopen） */
  driver: string = '';
  /** 网盘挂载：服务端实际挂载到的本机目录（可能为空） */
  localMountDir: string = '';
  lastError: string = '';
  lastErrorDisplay: string = '';
  /** 完整错误（显示值 + 原始值，对齐 Flutter lastErrorFull 拼装） */
  lastErrorFull: string = '';
  /** 原始 config（编辑回填用） */
  config: Record<string, Object> = {};

  static from(v: Object | undefined | null): MountItem {
    const item = new MountItem();
    if (v === undefined || v === null) {
      return item;
    }
    const rec = v as Record<string, Object>;
    const display = recStr(rec, 'last_error_display').trim();
    const rawErr = recStr(rec, 'last_error').trim();
    let full: string;
    if (rawErr.length === 0) {
      full = display;
    } else if (display.length > 0 && display !== rawErr) {
      full = `${display}\n\n[${rawErr}]`;
    } else {
      full = display.length > 0 ? display : rawErr;
    }
    item.id = recNum(rec, 'id');
    item.name = recStr(rec, 'name');
    item.mountPath = recStr(rec, 'mount_path');
    item.remote = recStr(rec, 'remote');
    item.status = recStr(rec, 'status').length > 0 ? recStr(rec, 'status') : 'stopped';
    item.driver = recStr(rec, 'driver');
    item.localMountDir = recStr(rec, 'local_mount_dir').trim();
    item.lastError = recStr(rec, 'last_error');
    item.lastErrorDisplay = recStr(rec, 'last_error_display');
    item.lastErrorFull = full;
    item.config = recRecord(rec, 'config');
    return item;
  }

  get isRunning(): boolean {
    return this.status === 'running';
  }

  get canStop(): boolean {
    return this.status === 'running';
  }

  get canStart(): boolean {
    return this.status !== 'running';
  }

  /** 网盘挂载展示路径：优先本机挂载目录（对齐 Flutter displayMountPath） */
  get displayMountPath(): string {
    return this.localMountDir.length > 0 ? this.localMountDir : this.mountPath;
  }

  get displayName(): string {
    return this.name.length > 0 ? this.name : '-';
  }
}

/**
 * 网盘驱动配置字段（对齐 Flutter drivers[i]['additional'] 中的字段项）。
 * 显示名通过 OpenlistDriverI18n.fieldLabel(field) 解析（openlist_field_* key → help → 原名）。
 */
export class DriverField {
  name: string = '';
  type: string = 'string';
  help: string = '';
  required: boolean = false;
  /** help 同时含 'one of' 与 'required' 时视为必填（对齐 Flutter oneOf） */
  oneOfRequired: boolean = false;
  defaultValue: string = '';
  defaultBool: boolean = false;
  options: string[] = [];

  static from(v: Object): DriverField {
    const f = new DriverField();
    if (v === undefined || v === null) {
      return f;
    }
    const rec = v as Record<string, Object>;
    const type = recStr(rec, 'type').trim().toLowerCase();
    const help = recStr(rec, 'help');
    const helpLower = help.toLowerCase();
    f.name = recStr(rec, 'name');
    f.type = type.length > 0 ? type : 'string';
    f.help = help.trim();
    f.required = recBool(rec, 'required');
    f.oneOfRequired = helpLower.includes('one of') && helpLower.includes('required');
    f.defaultValue = recStr(rec, 'default');
    f.defaultBool = recBool(rec, 'default');
    f.options = DriverField.parseOptions(rec['options']);
    return f;
  }

  /** options 兼容字符串 'a,b,c' 与 [{value:...}] / 纯值数组（对齐 Flutter 选项解析） */
  private static parseOptions(raw: Object | undefined): string[] {
    const options: string[] = [];
    if (raw === undefined || raw === null) {
      return options;
    }
    if (typeof raw === 'string') {
      const parts = raw.trim().length > 0 ? raw.split(',') : [];
      parts.forEach((s: string): void => {
        const t = s.trim();
        if (t.length > 0) {
          options.push(t);
        }
      });
      return options;
    }
    if (Array.isArray(raw)) {
      (raw as Object[]).forEach((o: Object): void => {
        if (o !== null && typeof o === 'object' && (o as Record<string, Object>)['value'] !== undefined) {
          options.push(`${(o as Record<string, Object>)['value']}`);
        } else {
          options.push(`${o}`);
        }
      });
    }
    return options;
  }

  get isBool(): boolean {
    return this.type === 'bool';
  }

  get isSelect(): boolean {
    return this.type === 'select';
  }

  get isText(): boolean {
    return this.type === 'text';
  }

  /** 密码/token/secret/cookie 类字段掩码输入（对齐 Flutter isSecret） */
  get isSecret(): boolean {
    const n = this.name.toLowerCase();
    return n.includes('token') || n.includes('password') || n.includes('secret')
      || n.includes('cookie');
  }
}

/** 解析驱动 additional（数组或 JSON 字符串，对齐 Flutter _parseAdditional） */
export function parseDriverFields(raw: Object | undefined): DriverField[] {
  const fields: DriverField[] = [];
  if (raw === undefined || raw === null) {
    return fields;
  }
  if (typeof raw === 'string') {
    const t = raw.trim();
    if (t.length === 0) {
      return fields;
    }
    try {
      const v: Object = JSON.parse(t);
      return parseDriverFields(v);
    } catch (_e) {
      return fields;
    }
  }
  if (Array.isArray(raw)) {
    (raw as Object[]).forEach((o: Object): void => {
      if (o !== null && typeof o === 'object') {
        fields.push(DriverField.from(o));
      }
    });
  }
  return fields;
}
