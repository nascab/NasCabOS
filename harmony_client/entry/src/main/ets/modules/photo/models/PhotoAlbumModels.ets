import {
  jsonAsInt, jsonAsStr, jsonAsBool, jsonAsArray
} from './PhotoModels';

/**
 * 相册/合集/智能相册数据模型（对齐 Flutter photo_album_model.dart /
 * photo_collection_model.dart / photo_smart_album_model.dart）
 */

// ================= 相册 =================

export class PhotoAlbumPreviewItem {
  fullpath: string = '';
}

export class PhotoAlbumItem {
  id: number = 0;
  ownerId: number = 0;
  name: string = '';
  isPublic: boolean = false;
  isOwner: boolean = false;
  previews: PhotoAlbumPreviewItem[] = [];
  /** 非自己创建的相册时接口返回的创建人用户名 */
  ownerUsername: string = '';
}

export class PhotoAlbumShareItem {
  uid: number = 0;
  username: string = '';
  canAdd: boolean = false;
  canDelete: boolean = false;
}

export class PhotoAlbumDetail {
  id: number = 0;
  ownerId: number = 0;
  name: string = '';
  isPublic: boolean = false;
  shares: PhotoAlbumShareItem[] = [];
}

export class PhotoAlbumListResult {
  items: PhotoAlbumItem[] = [];
  total: number = 0;
  page: number = 1;
  pageSize: number = 20;
}

/** 相册主页概览（对齐 PhotoAlbumOverviewResult） */
export class PhotoAlbumOverviewSection {
  items: PhotoAlbumItem[] = [];
  total: number = 0;
}

export class PhotoCollectionOverviewSection {
  items: PhotoCollectionItem[] = [];
  total: number = 0;
}

export class PhotoSmartAlbumOverviewSection {
  items: PhotoSmartAlbumItem[] = [];
  total: number = 0;
}

export class PhotoAlbumOverviewResult {
  albums: PhotoAlbumOverviewSection = new PhotoAlbumOverviewSection();
  smartAlbums: PhotoSmartAlbumOverviewSection = new PhotoSmartAlbumOverviewSection();
  collections: PhotoCollectionOverviewSection = new PhotoCollectionOverviewSection();
}

// ================= 合集 =================

export class PhotoCollectionItem {
  id: number = 0;
  ownerId: number = 0;
  name: string = '';
  pathList: string[] = [];
  createTime: string = '';
  previews: PhotoAlbumPreviewItem[] = [];
}

export class PhotoCollectionListResult {
  items: PhotoCollectionItem[] = [];
  total: number = 0;
  page: number = 1;
  pageSize: number = 20;
}

// ================= 智能相册 =================

export class PhotoSmartAlbumItem {
  id: number = 0;
  ownerId: number = 0;
  name: string = '';
  /** smart_date | condition */
  type: string = '';
  /** 服务端 filter_content 原始对象 */
  filterContent: Record<string, Object> = {};
  previews: PhotoAlbumPreviewItem[] = [];
}

export class PhotoSmartAlbumListResult {
  items: PhotoSmartAlbumItem[] = [];
  total: number = 0;
  page: number = 1;
  pageSize: number = 20;
}

// ================= 解析 =================

function parsePreviews(raw: Object | undefined | null): PhotoAlbumPreviewItem[] {
  const out: PhotoAlbumPreviewItem[] = [];
  for (const e of jsonAsArray(raw)) {
    const fullpath = jsonAsStr(e['fullpath']);
    if (fullpath.length === 0) {
      continue;
    }
    const p = new PhotoAlbumPreviewItem();
    p.fullpath = fullpath;
    out.push(p);
  }
  return out;
}

/** 分页信息（ArkTS 不支持解构，用类承载） */
class PaginationInfo {
  total: number = 0;
  page: number = 1;
  pageSize: number = 20;
}

function parsePagination(raw: Object | undefined | null): PaginationInfo {
  const info = new PaginationInfo();
  if (raw === undefined || raw === null) {
    return info;
  }
  const e = raw as Record<string, Object>;
  info.total = jsonAsInt(e['total']);
  info.page = jsonAsInt(e['page']);
  info.pageSize = jsonAsInt(e['pageSize']);
  return info;
}

export function parseAlbumItem(e: Record<string, Object>): PhotoAlbumItem {
  const item = new PhotoAlbumItem();
  item.id = jsonAsInt(e['id']);
  item.ownerId = jsonAsInt(e['owner_id']);
  item.name = jsonAsStr(e['name']);
  item.isPublic = jsonAsInt(e['is_public']) === 1 || jsonAsBool(e['is_public']);
  item.isOwner = jsonAsBool(e['is_owner']);
  item.previews = parsePreviews(e['previews']);
  item.ownerUsername = jsonAsStr(e['owner_username']);
  return item;
}

export function parseAlbumListResult(d: Object): PhotoAlbumListResult {
  const r = new PhotoAlbumListResult();
  const arr = jsonAsArray((d as Record<string, Object>)['items']);
  for (const e of arr) {
    const item = parseAlbumItem(e);
    if (item.id > 0) {
      r.items.push(item);
    }
  }
  const rec = d as Record<string, Object>;
  const pg = parsePagination(rec['pagination']);
  r.total = pg.total;
  r.page = pg.page;
  r.pageSize = pg.pageSize;
  return r;
}

export function parseAlbumDetail(d: Object): PhotoAlbumDetail {
  const rec = d as Record<string, Object>;
  const detail = new PhotoAlbumDetail();
  detail.id = jsonAsInt(rec['id']);
  detail.ownerId = jsonAsInt(rec['owner_id']);
  detail.name = jsonAsStr(rec['name']);
  detail.isPublic = jsonAsInt(rec['is_public']) === 1 || jsonAsBool(rec['is_public']);
  const arr = jsonAsArray(rec['shares']);
  for (const e of arr) {
    const s = new PhotoAlbumShareItem();
    s.uid = jsonAsInt(e['uid']);
    s.username = jsonAsStr(e['username']);
    s.canAdd = jsonAsInt(e['can_add']) !== 0 || jsonAsBool(e['can_add']);
    s.canDelete = jsonAsInt(e['can_delete']) !== 0 || jsonAsBool(e['can_delete']);
    if (s.uid > 0) {
      detail.shares.push(s);
    }
  }
  return detail;
}

/** 解析概览分区条目并返回 total（ArkTS 不支持对象字面量类型参数，改返回 total） */
function parseSectionItems<T>(raw: Object | undefined, fill: (e: Record<string, Object>) => T,
  items: T[]): number {
  if (raw === undefined || raw === null) {
    return 0;
  }
  const rec = raw as Record<string, Object>;
  const arr = jsonAsArray(rec['items']);
  for (const e of arr) {
    items.push(fill(e));
  }
  return jsonAsInt(rec['total']);
}

export function parseAlbumOverviewResult(d: Object): PhotoAlbumOverviewResult {
  const rec = d as Record<string, Object>;
  const r = new PhotoAlbumOverviewResult();
  r.albums.total = parseSectionItems<PhotoAlbumItem>(rec['albums'],
    (e: Record<string, Object>): PhotoAlbumItem => parseAlbumItem(e), r.albums.items);
  r.smartAlbums.total = parseSectionItems<PhotoSmartAlbumItem>(rec['smart_albums'],
    (e: Record<string, Object>): PhotoSmartAlbumItem => parseSmartAlbumItem(e), r.smartAlbums.items);
  r.collections.total = parseSectionItems<PhotoCollectionItem>(rec['collections'],
    (e: Record<string, Object>): PhotoCollectionItem => parseCollectionItem(e), r.collections.items);
  return r;
}

export function parseCollectionItem(e: Record<string, Object>): PhotoCollectionItem {
  const item = new PhotoCollectionItem();
  item.id = jsonAsInt(e['id']);
  item.ownerId = jsonAsInt(e['uid']);
  item.name = jsonAsStr(e['name']);
  const pathArr = jsonAsArray(e['path_list']);
  for (const p of pathArr) {
    const s = jsonAsStr(p);
    if (s.length > 0) {
      item.pathList.push(s);
    }
  }
  item.createTime = jsonAsStr(e['create_time']);
  item.previews = parsePreviews(e['previews']);
  return item;
}

export function parseCollectionListResult(d: Object): PhotoCollectionListResult {
  const r = new PhotoCollectionListResult();
  const arr = jsonAsArray((d as Record<string, Object>)['items']);
  for (const e of arr) {
    const item = parseCollectionItem(e);
    if (item.id > 0) {
      r.items.push(item);
    }
  }
  const rec = d as Record<string, Object>;
  const pg = parsePagination(rec['pagination']);
  r.total = pg.total;
  r.page = pg.page;
  r.pageSize = pg.pageSize;
  return r;
}

export function parseSmartAlbumItem(e: Record<string, Object>): PhotoSmartAlbumItem {
  const item = new PhotoSmartAlbumItem();
  item.id = jsonAsInt(e['id']);
  item.ownerId = jsonAsInt(e['uid']);
  item.name = jsonAsStr(e['name']);
  item.type = jsonAsStr(e['type']);
  const fc = e['filter_content'];
  if (fc !== undefined && fc !== null && typeof fc === 'object') {
    item.filterContent = fc as Record<string, Object>;
  }
  item.previews = parsePreviews(e['previews']);
  return item;
}

export function parseSmartAlbumListResult(d: Object): PhotoSmartAlbumListResult {
  const r = new PhotoSmartAlbumListResult();
  const arr = jsonAsArray((d as Record<string, Object>)['items']);
  for (const e of arr) {
    const item = parseSmartAlbumItem(e);
    if (item.id > 0) {
      r.items.push(item);
    }
  }
  const rec = d as Record<string, Object>;
  const pg = parsePagination(rec['pagination']);
  r.total = pg.total;
  r.page = pg.page;
  r.pageSize = pg.pageSize;
  return r;
}
