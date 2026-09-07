/**
 * 照片来源数据模型（对齐 Flutter source_setting/models/photo_source.dart）
 */

type Obj = Record<string, Object>;

export class PhotoSource {
  id: number = 0;
  path: string = '';
  exists: boolean = true;
  scanWhenStart: number = 0;
  scanWhenChange: number = 1;
  isShow: number = 1;
  ctime: string = '';
  scanInterval: number = 0;
  scanIntervalMs: number = 0;
  scanIntervalConfig: string = '';
  lastScanTime: number = 0;
}

export function parsePhotoSource(d: Object): PhotoSource {
  const map = d as Obj;
  const s = new PhotoSource();
  s.id = toInt(map['id']);
  s.path = toStr(map['path']);
  s.exists = typeof map['exists'] === 'boolean' ? map['exists'] as boolean : true;
  s.scanWhenStart = toInt(map['scan_when_start']);
  s.scanWhenChange = toInt(map['scan_when_change'], 1);
  s.isShow = toInt(map['is_show'], 1);
  s.ctime = map['ctime'] === undefined || map['ctime'] === null ? '' : `${map['ctime']}`;
  s.scanInterval = toInt(map['scan_interval']);
  s.scanIntervalMs = toInt(map['scan_interval_ms']);
  s.scanIntervalConfig = map['scan_interval_config'] === undefined || map['scan_interval_config'] === null
    ? '' : `${map['scan_interval_config']}`;
  s.lastScanTime = toInt(map['last_scan_time']);
  return s;
}

function toInt(v: Object | undefined | null, def: number = 0): number {
  if (v === undefined || v === null) {
    return def;
  }
  if (typeof v === 'number') {
    return Math.floor(v);
  }
  const parsed = parseInt(`${v}`, 10);
  return isNaN(parsed) ? def : parsed;
}

function toStr(v: Object | undefined | null): string {
  return v === undefined || v === null ? '' : `${v}`;
}
