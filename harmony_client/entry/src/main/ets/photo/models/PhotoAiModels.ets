/**
 * AI 相册模块数据模型（对齐 Flutter ai_faces_models.dart / ai_scenes_models.dart / ai_similar_models.dart）
 */
import { TimelinePhotoItem, parseTimelinePhotoItem, jsonAsInt, jsonAsStr } from './PhotoModels';

type Obj = Record<string, Object>;

// ===== 人脸（对齐 Flutter AiFaceItem / AiFaceListResult） =====

export class AiFaceItem {
  faceId: number = 0;
  faceCount: number = 0;
  coverFileHash: string = '';
  name: string = '';
  isHide: boolean = false;
}

export class AiFaceListResult {
  items: AiFaceItem[] = [];
  total: number = 0;
  page: number = 1;
  pageSize: number = 50;
  faceEnable: boolean = true;
}

/** 解析开关字段：bool / 数字 1 / 字符串 '1'/'true'，缺省 true（对齐 Flutter parseEnable） */
function parseEnable(v: Object | undefined | null): boolean {
  if (v === undefined || v === null) {
    return true;
  }
  if (typeof v === 'boolean') {
    return v;
  }
  if (typeof v === 'number') {
    return Math.floor(v) === 1;
  }
  const s = `${v}`.toLowerCase();
  return s === '1' || s === 'true';
}

export function parseAiFaceItem(e: Obj): AiFaceItem {
  const it = new AiFaceItem();
  it.faceId = jsonAsInt(e['face_id'] ?? e['faceId']);
  it.faceCount = jsonAsInt(e['face_count'] ?? e['faceCount']);
  it.coverFileHash = jsonAsStr(e['cover_file_hash'] ?? e['coverFileHash']);
  it.name = jsonAsStr(e['name']);
  it.isHide = jsonAsInt(e['is_hide']) === 1;
  return it;
}

export function parseAiFaceListResult(d: Object): AiFaceListResult {
  const r = new AiFaceListResult();
  const map = d as Obj;
  const list = map['items'];
  if (Array.isArray(list)) {
    for (const e of list as Obj[]) {
      const it = parseAiFaceItem(e);
      // 对齐 Flutter：过滤无效 faceId
      if (it.faceId > 0) {
        r.items.push(it);
      }
    }
  }
  const pagination = (map['pagination'] ?? new Object()) as Obj;
  r.total = jsonAsInt(pagination['total']);
  r.page = jsonAsInt(pagination['page']) > 0 ? jsonAsInt(pagination['page']) : 1;
  r.pageSize = jsonAsInt(pagination['pageSize']) > 0 ? jsonAsInt(pagination['pageSize']) : 50;
  r.faceEnable = parseEnable(map['faceEnable'] ?? map['face_enable']);
  return r;
}

// ===== 场景（对齐 Flutter AiSceneCover / AiSceneItem / AiSceneListResult） =====

export class AiSceneItem {
  placeName: string = '';
  placeNameRaw: string = '';
  photoCount: number = 0;
  isHide: boolean = false;
  /** 封面 fullpath（对齐 Flutter AiSceneCover.fullpath，用缩略图 URL 加载） */
  coverFullpath: string = '';
}

export class AiSceneListResult {
  items: AiSceneItem[] = [];
  total: number = 0;
  page: number = 1;
  pageSize: number = 50;
  placeEnable: boolean = true;
}

export function parseAiSceneItem(e: Obj): AiSceneItem {
  const it = new AiSceneItem();
  const rawName = e['place_name_raw'] ?? e['placeNameRaw'] ?? e['place_name'];
  it.placeName = jsonAsStr(e['place_name']);
  it.placeNameRaw = jsonAsStr(rawName);
  it.photoCount = jsonAsInt(e['photo_count'] ?? e['photoCount']);
  it.isHide = jsonAsInt(e['is_hide']) === 1;
  const cover = e['cover'];
  if (cover !== undefined && cover !== null && typeof cover === 'object') {
    it.coverFullpath = jsonAsStr((cover as Obj)['fullpath']);
  }
  return it;
}

export function parseAiSceneListResult(d: Object): AiSceneListResult {
  const r = new AiSceneListResult();
  const map = d as Obj;
  const list = map['items'];
  if (Array.isArray(list)) {
    for (const e of list as Obj[]) {
      const it = parseAiSceneItem(e);
      // 对齐 Flutter：过滤空 placeNameRaw
      if (it.placeNameRaw.trim().length > 0) {
        r.items.push(it);
      }
    }
  }
  const pagination = (map['pagination'] ?? new Object()) as Obj;
  r.total = jsonAsInt(pagination['total']);
  r.page = jsonAsInt(pagination['page']) > 0 ? jsonAsInt(pagination['page']) : 1;
  r.pageSize = jsonAsInt(pagination['pageSize']) > 0 ? jsonAsInt(pagination['pageSize']) : 50;
  r.placeEnable = parseEnable(map['placeEnable'] ?? map['place_enable']);
  return r;
}

// ===== 相似照片（对齐 Flutter AiSimilarPagination / AiSimilarGroupItem / AiSimilarListResult） =====

export class AiSimilarPagination {
  total: number = 0;
  page: number = 0;
  pageSize: number = 0;
}

export class AiSimilarGroupItem {
  id: number = 0;
  indexId: number = 0;
  photos: TimelinePhotoItem[] = [];
  createTime: string = '';
}

export class AiSimilarListResult {
  similarEnable: boolean = false;
  items: AiSimilarGroupItem[] = [];
  pagination: AiSimilarPagination = new AiSimilarPagination();
}

export function parseAiSimilarGroupItem(e: Obj): AiSimilarGroupItem {
  const it = new AiSimilarGroupItem();
  it.id = jsonAsInt(e['id']);
  it.indexId = jsonAsInt(e['index_id'] ?? e['indexId']);
  const photos = e['photos'];
  if (Array.isArray(photos)) {
    for (const p of photos as Obj[]) {
      it.photos.push(parseTimelinePhotoItem(p));
    }
  }
  it.createTime = jsonAsStr(e['create_time'] ?? e['createTime']);
  return it;
}

export function parseAiSimilarListResult(d: Object): AiSimilarListResult {
  const r = new AiSimilarListResult();
  const map = d as Obj;
  // 对齐 Flutter：similarEnable == 1/'1'/true
  r.similarEnable = parseEnable2(map['similarEnable']);
  const list = map['items'];
  if (Array.isArray(list)) {
    for (const e of list as Obj[]) {
      r.items.push(parseAiSimilarGroupItem(e));
    }
  }
  const pagination = map['pagination'];
  if (pagination !== undefined && pagination !== null && typeof pagination === 'object') {
    const p = pagination as Obj;
    r.pagination.total = jsonAsInt(p['total']);
    r.pagination.page = jsonAsInt(p['page']);
    r.pagination.pageSize = jsonAsInt(p['pageSize'] ?? p['page_size']);
  }
  return r;
}

/** 对齐 Flutter AiSimilarListResult.fromJson 的 similarEnable 判定（缺省 false） */
function parseEnable2(v: Object | undefined | null): boolean {
  if (v === undefined || v === null) {
    return false;
  }
  if (typeof v === 'boolean') {
    return v;
  }
  if (typeof v === 'number') {
    return v === 1;
  }
  return `${v}` === '1' || `${v}`.toLowerCase() === 'true';
}
