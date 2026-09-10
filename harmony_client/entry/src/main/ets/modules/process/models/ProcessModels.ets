/**
 * 进程模块模型（对齐 Flutter modules/process/models/worker_process_item.dart）。
 */

/** 未知进程名称 key（对齐 Flutter _kProcessUnknownNameKey） */
export const PROCESS_UNKNOWN_NAME_KEY: string = 'process.worker.unknown.name';
/** 未知进程用途 key（对齐 Flutter worker_process_item.dart 默认 purposeKey） */
export const PROCESS_UNKNOWN_PURPOSE_KEY: string = 'process.worker.unknown.purpose';

function bStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

function bNum(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Math.trunc(v);
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

export class WorkerProcessItem {
  pid: number = 0;
  workerPath: string = '';
  role: string = '';
  nameKey: string = PROCESS_UNKNOWN_NAME_KEY;
  purposeKey: string = PROCESS_UNKNOWN_PURPOSE_KEY;
  startedAt: number = 0;

  static fromJson(data: Record<string, Object> | undefined | null): WorkerProcessItem {
    const item = new WorkerProcessItem();
    const d = data ?? {};
    item.pid = bNum(d['pid']);
    item.workerPath = bStr(d['workerPath']);
    item.role = bStr(d['role']);
    // 对齐 Flutter：nameKey/purposeKey 缺省时才取未知进程 key（空字符串按原样保留）
    const rawNameKey = d['nameKey'];
    item.nameKey = (rawNameKey === undefined || rawNameKey === null)
      ? PROCESS_UNKNOWN_NAME_KEY : bStr(rawNameKey);
    const rawPurposeKey = d['purposeKey'];
    item.purposeKey = (rawPurposeKey === undefined || rawPurposeKey === null)
      ? PROCESS_UNKNOWN_PURPOSE_KEY : bStr(rawPurposeKey);
    item.startedAt = bNum(d['startedAt']);
    return item;
  }
}
