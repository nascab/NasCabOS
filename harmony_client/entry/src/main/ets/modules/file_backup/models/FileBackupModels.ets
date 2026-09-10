import { L10n } from '../../../core/localization/L10n';

/**
 * 磁盘间备份模块模型（对齐 Flutter fileBackup 模块直接使用的 Map 字段：
 * /api/fileBackup/list 与 /api/fileBackup/records/list 返回的 item 结构）。
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

/** 解析整数字符串（对齐 Flutter int.tryParse：整串匹配才成功），失败返回 fallback */
export function parseIntOr(text: string, fallback: number): number {
  const t = text.trim();
  if (!/^[+-]?\d+$/.test(t)) {
    return fallback;
  }
  const n = Number.parseInt(t, 10);
  return Number.isFinite(n) ? n : fallback;
}

/** 两位补零 */
function two(n: number): string {
  return `${n < 10 ? '0' : ''}${n}`;
}

/** 备份任务（对齐 _ServerBackupListPanel.build 中解析的 item 字段） */
export class BackupTask {
  id: number = 0;
  /** 缺省按 'stopped' 处理（对齐 Flutter ?? 'stopped'） */
  status: string = 'stopped';
  /** 缺省按 'copy' 处理（对齐 Flutter ?? 'copy'） */
  type: string = 'copy';
  sourcePath: string[] = [];
  targetPath: string = '';
  frenquence: number = 0;
  excludeList: string[] = [];
  progress: string = '';
  /** 原始值：秒/毫秒时间戳（number）或 ISO 字符串 */
  lastSuccessTime: Object | undefined = undefined;
  lastError: string = '';

  static fromJson(data: Record<string, Object> | undefined | null): BackupTask {
    const t = new BackupTask();
    const d = data ?? {};
    t.id = bNum(d['id']);
    const statusRaw = d['status'];
    t.status = statusRaw === undefined || statusRaw === null
      ? 'stopped'
      : bStr(statusRaw).trim().toLowerCase();
    const typeRaw = d['type'];
    t.type = typeRaw === undefined || typeRaw === null
      ? 'copy'
      : bStr(typeRaw).trim().toLowerCase();
    t.sourcePath = strListOf(d['source_path']);
    t.targetPath = bStr(d['target_path']);
    t.frenquence = bNum(d['frenquence']);
    t.excludeList = strListOf(d['exclude_list']);
    t.progress = bStr(d['progress']);
    t.lastSuccessTime = d['last_success_time'];
    t.lastError = bStr(d['last_error']);
    return t;
  }
}

/** 把服务端数组字段解析为非空字符串数组（对齐 Flutter _toStringList） */
function strListOf(v: Object | undefined | null): string[] {
  const out: string[] = [];
  if (v === undefined || v === null || !Array.isArray(v)) {
    return out;
  }
  const arr = v as Object[];
  arr.forEach((e: Object): void => {
    const s = bStr(e).trim();
    if (s.length > 0) {
      out.push(s);
    }
  });
  return out;
}

/** 备份记录中的失败文件条目（对齐 error_file_list 元素 {path, error}） */
export class BackupRecordError {
  path: string = '';
  error: string = '';

  static fromJson(data: Record<string, Object> | undefined | null): BackupRecordError {
    const e = new BackupRecordError();
    const d = data ?? {};
    e.path = bStr(d['path']);
    e.error = bStr(d['error']);
    return e;
  }
}

/** 单次备份运行记录（对齐 _BackupRecordsDialog 中解析的 row 字段） */
export class BackupRecord {
  id: number = -1;
  /** id 字段是否存在（缺失时展示回退序号，对齐 Flutter row['id']?.toString() ?? ...） */
  idPresent: boolean = false;
  startTime: Object | undefined = undefined;
  endTime: Object | undefined = undefined;
  status: string = '';
  /** 原始耗时毫秒（number/字符串），格式化时解析 */
  durationMs: Object | undefined = undefined;
  filesCopied: number = 0;
  filesSkipped: number = 0;
  filesRemoved: number = 0;
  bytesCopied: number = 0;
  errors: BackupRecordError[] = [];

  static fromJson(data: Record<string, Object> | undefined | null): BackupRecord {
    const r = new BackupRecord();
    const d = data ?? {};
    const idRaw = d['id'];
    r.idPresent = idRaw !== undefined && idRaw !== null;
    r.id = r.idPresent ? bNum(idRaw) : -1;
    r.startTime = d['start_time'];
    r.endTime = d['end_time'];
    r.status = bStr(d['status']);
    r.durationMs = d['duration_ms'];
    r.filesCopied = bNum(d['files_copied_count']);
    r.filesSkipped = bNum(d['files_skipped_count']);
    r.filesRemoved = bNum(d['files_removed_count']);
    r.bytesCopied = bNum(d['bytes_copied_count']);
    const errList = d['error_file_list'];
    if (errList !== undefined && errList !== null && Array.isArray(errList)) {
      const arr = errList as Object[];
      arr.forEach((m: Object): void => {
        r.errors.push(BackupRecordError.fromJson(m as Record<string, Object>));
      });
    }
    return r;
  }
}

/** 备份记录接口返回（对齐 data: {max_kept_per_task, items}） */
export class BackupRecordsPayload {
  maxKept: number = 300;
  items: BackupRecord[] = [];
}

/**
 * 时间显示（对齐 Flutter _formatLocalTime）：
 * 秒/毫秒时间戳自动判断，字符串先按整数解析再按 ISO 解析，输出本地 yyyy-MM-dd HH:mm:ss。
 */
export function formatBackupLocalTime(v: Object | undefined | null, naText: string): string {
  let ms = Number.NaN;
  if (typeof v === 'number') {
    ms = v > 10000000000 ? v : v * 1000;
  } else if (typeof v === 'string') {
    const s = v.trim();
    if (s.length > 0) {
      if (/^[+-]?\d+$/.test(s)) {
        const n = Number.parseInt(s, 10);
        ms = n > 10000000000 ? n : n * 1000;
      } else {
        const t = Date.parse(s);
        if (Number.isFinite(t)) {
          ms = t;
        }
      }
    }
  }
  if (!Number.isFinite(ms)) {
    return naText;
  }
  const dt = new Date(ms);
  return `${dt.getFullYear()}-${two(dt.getMonth() + 1)}-${two(dt.getDate())} `
    + `${two(dt.getHours())}:${two(dt.getMinutes())}:${two(dt.getSeconds())}`;
}

/** 字节数可读化（对齐 Flutter _formatBytes：<1024 显示 B，否则 KB/MB/GB/TB） */
export function formatBackupBytes(v: Object | undefined | null): string {
  const na = L10n.t('file_backup_run_records_na', '—');
  const n = bNum(v);
  if (n < 0) {
    return na;
  }
  if (n < 1024) {
    return L10n.t('file_backup_run_record_bytes_value', '@n B', L10n.paramsOf('n', `${n}`));
  }
  const units: string[] = ['KB', 'MB', 'GB', 'TB'];
  let x = n / 1024;
  let i = 0;
  while (x >= 1024 && i < units.length - 1) {
    x /= 1024;
    i++;
  }
  const s = x >= 100 ? x.toFixed(0) : (x >= 10 ? x.toFixed(1) : x.toFixed(2));
  const params = new Map<string, string>();
  params.set('v', s);
  params.set('u', units[i]);
  return L10n.t('file_backup_run_record_bytes_shorthand', '@v @u', params);
}

/** 耗时格式化（对齐 Flutter _formatDurationMs：HH:mm:ss，不足 1s 按 1s 计） */
export function formatBackupDurationMs(v: Object | undefined | null, naText: string): string {
  if (v === undefined || v === null) {
    return naText;
  }
  const s = `${v}`.trim();
  if (!/^[+-]?\d+$/.test(s)) {
    return naText;
  }
  const ms = Number.parseInt(s, 10);
  if (ms < 0) {
    return naText;
  }
  const totalSeconds = ms === 0 ? 0 : (ms < 1000 ? 1 : Math.floor(ms / 1000));
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const sec = totalSeconds % 60;
  return `${two(h)}:${two(m)}:${two(sec)}`;
}

/** 错误码友好化（对齐 Flutter _friendlyLastError：target/source_not_found 走翻译） */
export function friendlyBackupError(lastError: string): string {
  const code = lastError.trim().toLowerCase();
  if (code === 'target_not_found') {
    return L10n.t('target_not_found', '目标目录不存在');
  }
  if (code === 'source_not_found') {
    return L10n.t('source_not_found', '源目录不存在');
  }
  return lastError.trim();
}

/** 上次备份状态文案（对齐 Flutter _lastBackupStatusText） */
export function backupLastStatusText(lastError: string, lastSuccessTime: Object | undefined | null): string {
  if (lastError.trim().length > 0) {
    return L10n.t('file_backup_last_backup_status_failed', '失败');
  }
  if (lastSuccessTime === undefined || lastSuccessTime === null) {
    return L10n.t('file_backup_last_backup_status_unknown', '未知');
  }
  const s = `${lastSuccessTime}`.trim();
  if (s.length === 0) {
    return L10n.t('file_backup_last_backup_status_unknown', '未知');
  }
  return L10n.t('file_backup_last_backup_status_success', '成功');
}
