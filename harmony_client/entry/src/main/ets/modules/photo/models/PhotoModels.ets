/**
 * 照片模块数据模型（对齐 Flutter photo_timeline_model.dart）
 */

export class TimelineDateItem {
  originalDate: string = '';
  count: number = 0;
}

@ObservedV2
export class TimelinePhotoItem {
  id: number = 0;
  path: string = '';
  filename: string = '';
  size: number = 0;
  isLvp: number = 0;
  isMergeLvp: number = 0;
  /** 1=图片 2=视频 */
  type: number = 0;
  width: number = 0;
  height: number = 0;
  originalDate: string = '';
  originalTime: string = '';
  fullpath: string = '';
  duration: number = 0;
  fileHash: string = '';
  @Trace isFavorite: boolean = false;
  liveFilename: string = '';
  rawFilename: string = '';
  rawShowExt: string = '';
}

export class TimelinePathItem {
  path: string = '';
  valid: boolean = false;
}

export class TimelineDateInfo {
  originalDate: string = '';
  geo: string = '';
  camera: string = '';
}

export class TimelineYearItem {
  year: number = 0;
  count: number = 0;
  cover: TimelinePhotoItem = new TimelinePhotoItem();
}

export class TimelineDetectedFaceItem {
  faceId: number = 0;
  faceCount: number = 0;
  name: string = '';
  isHide: boolean = false;
}

export class TimelineDateListResult {
  items: TimelineDateItem[] = [];
  validPaths: TimelinePathItem[] = [];
}

export class TimelinePhotoListResult {
  photoList: TimelinePhotoItem[] = [];
  dateInfoList: TimelineDateInfo[] = [];
}

export class TimelineYearListResult {
  items: TimelineYearItem[] = [];
}

/** 回收站照片条目（对齐 Flutter photo_trash_model.dart 字段） */
export class TrashPhotoItem {
  id: number = 0;
  path: string = '';
  filename: string = '';
  fullpath: string = '';
  /** 1=图片 2=视频 */
  type: number = 0;
  size: number = 0;
  originalDate: string = '';
  originalTime: string = '';
  inTrashTime: string = '';
  fileHash: string = '';
  width: number = 0;
  height: number = 0;
  duration: number = 0;
  /** 是否实况照片（对齐 Flutter TimelinePhotoItem.isLvp，用于实况标识） */
  isLvp: number = 0;
  /** 关联 livephoto 文件名（删除确认弹窗显示用，对齐 Flutter live_filename） */
  liveFilename: string = '';
  /** 关联 raw 文件名（删除确认弹窗显示用，对齐 Flutter raw_filename） */
  rawFilename: string = '';
}

export class TrashPhotoListResult {
  total: number = 0;
  items: TrashPhotoItem[] = [];
}

// ===== 解析辅助（服务端字段可能为数字/字符串） =====

export function jsonAsInt(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Math.floor(v);
  }
  if (typeof v === 'boolean') {
    return v ? 1 : 0;
  }
  const n = parseInt(`${v}`, 10);
  return isNaN(n) ? 0 : n;
}

export function jsonAsDouble(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return v;
  }
  const n = parseFloat(`${v}`);
  return isNaN(n) ? 0 : n;
}

export function jsonAsStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'string') {
    return v;
  }
  return `${v}`;
}

export function jsonAsBool(v: Object | undefined | null): boolean {
  if (v === undefined || v === null) {
    return false;
  }
  if (typeof v === 'boolean') {
    return v;
  }
  if (typeof v === 'number') {
    return v !== 0;
  }
  return `${v}` === 'true' || `${v}` === '1';
}

export function jsonAsArray(v: Object | undefined | null): Record<string, Object>[] {
  if (v === undefined || v === null || !Array.isArray(v)) {
    return [];
  }
  return v as Record<string, Object>[];
}

type Obj = Record<string, Object>;

export function parseTimelinePhotoItem(e: Obj): TimelinePhotoItem {
  const it = new TimelinePhotoItem();
  it.id = jsonAsInt(e['id']);
  it.path = jsonAsStr(e['path']);
  it.filename = jsonAsStr(e['filename']);
  it.size = jsonAsInt(e['size'] ?? e['file_size']);
  it.isLvp = jsonAsInt(e['is_lvp']);
  it.isMergeLvp = jsonAsInt(e['is_merge_lvp']);
  it.type = jsonAsInt(e['type']);
  it.width = jsonAsInt(e['width']);
  it.height = jsonAsInt(e['height']);
  it.originalDate = jsonAsStr(e['original_date']);
  it.originalTime = jsonAsStr(e['original_time']);
  it.fullpath = jsonAsStr(e['fullpath']);
  it.duration = e['duration'] !== undefined ? jsonAsInt(e['duration']) : 0;
  it.fileHash = jsonAsStr(e['file_hash']);
  it.isFavorite = jsonAsInt(e['is_favorite']) === 1;
  it.liveFilename = jsonAsStr(e['live_filename']);
  it.rawFilename = jsonAsStr(e['raw_filename']);
  it.rawShowExt = jsonAsStr(e['raw_show_ext']);
  return it;
}

export function parseTimelineDateListResult(d: Object): TimelineDateListResult {
  const r = new TimelineDateListResult();
  const map = d as Obj;
  for (const e of jsonAsArray(map['items'])) {
    const it = new TimelineDateItem();
    it.originalDate = jsonAsStr(e['original_date']);
    it.count = jsonAsInt(e['date_photo_count']);
    r.items.push(it);
  }
  for (const e of jsonAsArray(map['validPaths'])) {
    const it = new TimelinePathItem();
    if (typeof e['path'] === 'string' && e['valid'] === undefined) {
      // 兼容旧数据：纯字符串数组
      it.path = jsonAsStr(e['path']);
      it.valid = true;
    } else {
      it.path = jsonAsStr(e['path']);
      it.valid = jsonAsBool(e['valid']);
    }
    r.validPaths.push(it);
  }
  return r;
}

export function parseTimelinePhotoListResult(d: Object): TimelinePhotoListResult {
  const r = new TimelinePhotoListResult();
  const map = d as Obj;
  for (const e of jsonAsArray(map['photoList'])) {
    r.photoList.push(parseTimelinePhotoItem(e));
  }
  for (const e of jsonAsArray(map['dateInfoList'])) {
    const it = new TimelineDateInfo();
    it.originalDate = jsonAsStr(e['original_date']);
    it.geo = jsonAsStr(e['geo']);
    it.camera = jsonAsStr(e['camera']);
    r.dateInfoList.push(it);
  }
  return r;
}

export function parseTimelineYearListResult(d: Object): TimelineYearListResult {
  const r = new TimelineYearListResult();
  for (const e of jsonAsArray((d as Obj)['items'])) {
    const it = new TimelineYearItem();
    it.year = jsonAsInt(e['year']);
    it.count = jsonAsInt(e['count']);
    const cover = e['cover'];
    if (cover !== undefined && cover !== null && typeof cover === 'object') {
      it.cover = parseTimelinePhotoItem(cover as Obj);
    }
    r.items.push(it);
  }
  return r;
}

export function parseTrashPhotoListResult(d: Object): TrashPhotoListResult {
  const r = new TrashPhotoListResult();
  const map = d as Obj;
  r.total = jsonAsInt(map['total'] ?? map['totalCount']);
  const list = map['list'] ?? map['items'] ?? map['photoList'];
  for (const e of jsonAsArray(list)) {
    const it = new TrashPhotoItem();
    it.id = jsonAsInt(e['id']);
    it.path = jsonAsStr(e['path']);
    it.filename = jsonAsStr(e['filename']);
    it.fullpath = jsonAsStr(e['fullpath']);
    it.type = jsonAsInt(e['type']);
    it.size = jsonAsInt(e['size'] ?? e['file_size']);
    it.originalDate = jsonAsStr(e['original_date']);
    it.originalTime = jsonAsStr(e['original_time']);
    it.inTrashTime = jsonAsStr(e['in_trash_time']);
    it.fileHash = jsonAsStr(e['file_hash']);
    it.width = jsonAsInt(e['width']);
    it.height = jsonAsInt(e['height']);
    it.duration = jsonAsInt(e['duration']);
    it.isLvp = jsonAsInt(e['is_lvp']);
    it.liveFilename = jsonAsStr(e['live_filename']);
    it.rawFilename = jsonAsStr(e['raw_filename']);
    r.items.push(it);
  }
  return r;
}
