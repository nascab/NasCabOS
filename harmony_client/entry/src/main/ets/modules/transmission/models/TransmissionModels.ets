/**
 * Transmission 模块模型（对齐 Flutter 端 Map<String, dynamic> 字段访问面）：
 * 服务端字段为 Transmission RPC 命名（camelCase），部分响应附带 snake_case 别名与
 * display* 预计算字段（下载量按文件选择折算），fromJson 统一兼容两种命名。
 */

/** 取第一个存在的数字字段（number 或数字字符串），否则 0 */
function trNum(d: Record<string, Object>, keys: string[]): number {
  for (const k of keys) {
    const v = d[k];
    if (typeof v === 'number' && Number.isFinite(v)) {
      return v;
    }
    if (typeof v === 'string' && v.trim().length > 0) {
      const n = Number(v);
      if (Number.isFinite(n)) {
        return n;
      }
    }
  }
  return 0;
}

/** 取第一个存在的整数字段，否则 0 */
function trInt(d: Record<string, Object>, keys: string[]): number {
  return Math.trunc(trNum(d, keys));
}

/** 取第一个存在的字符串字段，否则 '' */
function trStr(d: Record<string, Object>, keys: string[]): string {
  for (const k of keys) {
    const v = d[k];
    if (v === undefined || v === null) {
      continue;
    }
    if (typeof v === 'string') {
      return v;
    }
    return `${v}`;
  }
  return '';
}

/** torrent 任务记录 */
export class TorrentRecord {
  id: number = 0;
  name: string = '';
  /** Transmission 状态码：0 已停止 2 校验中 4 下载中 6 做种（其余为排队等） */
  status: number = 0;
  addedDate: number = 0;
  percentDone: number = 0;
  rateDownload: number = 0;
  rateUpload: number = 0;
  eta: number = 0;
  totalSize: number = 0;
  sizeWhenDone: number = 0;
  leftUntilDone: number = 0;
  haveValid: number = 0;
  haveUnchecked: number = 0;
  downloadedEver: number = 0;
  uploadedEver: number = 0;
  uploadRatio: number = 0;
  error: number = 0;
  errorString: string = '';
  isFinished: boolean = false;
  downloadDir: string = '';
  /** 服务器预计算总大小（<=0 视为未提供） */
  displayTotalSize: number = -1;
  /** 服务器预计算已下载字节（<0 视为未提供） */
  displayDownloadedBytes: number = -1;

  static fromJson(data: Record<string, Object> | undefined | null): TorrentRecord {
    const t = new TorrentRecord();
    const d = data ?? {};
    t.id = trInt(d, ['id']);
    t.name = trStr(d, ['name']);
    t.status = trInt(d, ['status']);
    t.addedDate = trInt(d, ['addedDate', 'added_date', 'dateAdded', 'date_added']);
    t.percentDone = trNum(d, ['percentDone', 'percent_done']);
    t.rateDownload = trNum(d, ['rateDownload', 'rate_download']);
    t.rateUpload = trNum(d, ['rateUpload', 'rate_upload']);
    t.eta = trInt(d, ['eta']);
    t.totalSize = trNum(d, ['totalSize', 'total_size']);
    t.sizeWhenDone = trNum(d, ['sizeWhenDone', 'size_when_done']);
    t.leftUntilDone = trNum(d, ['leftUntilDone', 'left_until_done']);
    t.haveValid = trNum(d, ['haveValid', 'have_valid']);
    t.haveUnchecked = trNum(d, ['haveUnchecked', 'have_unchecked']);
    t.downloadedEver = trNum(d, ['downloadedEver', 'downloaded_ever']);
    t.uploadedEver = trNum(d, ['uploadedEver', 'uploaded_ever']);
    t.uploadRatio = trNum(d, ['uploadRatio', 'upload_ratio']);
    t.error = trInt(d, ['error']);
    t.errorString = trStr(d, ['errorString', 'error_string']);
    t.isFinished = d['isFinished'] === true;
    t.downloadDir = trStr(d, ['downloadDir', 'download_dir']);
    const dt = d['displayTotalSize'];
    t.displayTotalSize = typeof dt === 'number' && Number.isFinite(dt) ? dt : -1;
    const dd = d['displayDownloadedBytes'];
    t.displayDownloadedBytes = typeof dd === 'number' && Number.isFinite(dd) ? dd : -1;
    return t;
  }
}

/** torrent 内文件条目（/api/transmission/torrents/files） */
export class TorrentFileEntry {
  index: number = 0;
  name: string = '';
  length: number = 0;
  wanted: boolean = true;

  static fromJson(data: Record<string, Object> | undefined | null): TorrentFileEntry {
    const f = new TorrentFileEntry();
    const d = data ?? {};
    f.index = trInt(d, ['index']);
    f.name = trStr(d, ['name']);
    f.length = trNum(d, ['length', 'size']);
    const w = d['wanted'];
    // 对齐 Flutter _isWanted：仅 false / 0 视为未选中
    f.wanted = !(w === false || w === 0);
    return f;
  }
}

/** 任务列表请求字段（与 Flutter _torrentFields 完全一致） */
export const TORRENT_FIELDS: string[] = [
  'id', 'name', 'status', 'addedDate', 'added_date', 'percentDone',
  'rateDownload', 'rateUpload', 'eta', 'totalSize', 'sizeWhenDone',
  'leftUntilDone', 'haveValid', 'haveUnchecked', 'downloadedEver',
  'uploadedEver', 'uploadRatio', 'error', 'errorString', 'isFinished',
  'labels', 'downloadDir'
];

/** 任务排序 key（与 Flutter torrentSortKeys 完全一致） */
export const TORRENT_SORT_KEYS: string[] = [
  'added_desc', 'added_asc', 'name_asc', 'name_desc',
  'progress_desc', 'progress_asc', 'size_desc', 'size_asc',
  'download_speed_desc', 'upload_speed_desc', 'ratio_desc', 'ratio_asc'
];

/** 排序 key → 语言包 key */
export const TORRENT_SORT_LABEL_KEYS: Record<string, string> = {
  'added_desc': 'transmission_sort_added_desc',
  'added_asc': 'transmission_sort_added_asc',
  'name_asc': 'transmission_sort_name_asc',
  'name_desc': 'transmission_sort_name_desc',
  'progress_desc': 'transmission_sort_progress_desc',
  'progress_asc': 'transmission_sort_progress_asc',
  'size_desc': 'transmission_sort_size_desc',
  'size_asc': 'transmission_sort_size_asc',
  'download_speed_desc': 'transmission_sort_download_desc',
  'upload_speed_desc': 'transmission_sort_upload_desc',
  'ratio_desc': 'transmission_sort_ratio_desc',
  'ratio_asc': 'transmission_sort_ratio_asc'
};

/** 配置数字字段：存在（number/数字字符串）→ 值，缺失 → 默认值 */
export function cfgNum(cfg: Record<string, Object>, key: string, def: number): number {
  const v = cfg[key];
  if (typeof v === 'number' && Number.isFinite(v)) {
    return v;
  }
  if (typeof v === 'string' && v.trim().length > 0) {
    const n = Number(v);
    if (Number.isFinite(n)) {
      return n;
    }
  }
  return def;
}

/** 配置展示文本：缺失 → ''（对齐 Flutter '${cfg[key] ?? ''}'） */
export function cfgNumText(cfg: Record<string, Object>, key: string): string {
  const v = cfg[key];
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'number' && Number.isFinite(v)) {
    return `${v}`;
  }
  return `${v}`;
}

/** 配置字符串字段 */
export function cfgStr(cfg: Record<string, Object>, key: string): string {
  const v = cfg[key];
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'string') {
    return v;
  }
  return `${v}`;
}

/** 配置布尔字段：explicit false → false，explicit true → true，缺失 → 默认值（对齐 Dart ==true / !=false） */
export function cfgBool(cfg: Record<string, Object>, key: string, def: boolean): boolean {
  const v = cfg[key];
  if (v === true) {
    return true;
  }
  if (v === false) {
    return false;
  }
  return def;
}
