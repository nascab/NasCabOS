/**
 * 足迹地图数据模型（对齐 Flutter photo_map_models.dart）
 */

/** 瓦片服务器（对齐 Flutter PhotoMapTileServer） */
export class PhotoMapTileServer {
  name: string = '';
  server: string = '';
  coordinate: string = 'WGS-84';
  maxLevel: number = 18;
  isDefault: boolean = false;
  isCustom: boolean = false;
  isCurrent: boolean = false;

  toJson(): Record<string, Object> {
    const obj: Record<string, Object> = {
      'name': this.name,
      'server': this.server,
      'coordinate': this.coordinate,
      'maxLevel': this.maxLevel,
      'isDefault': this.isDefault ? 1 : 0
    };
    return obj;
  }
}

function toBool(v: ESObject): boolean {
  return v === true || v === 1;
}

function toInt(v: ESObject, fallback: number): number {
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(n) : fallback;
}

export function parsePhotoMapTileServer(raw: Object): PhotoMapTileServer {
  const s = new PhotoMapTileServer();
  const o = raw as Record<string, ESObject>;
  s.name = o['name'] !== undefined && o['name'] !== null ? `${o['name']}` : '';
  s.server = o['server'] !== undefined && o['server'] !== null ? `${o['server']}` : '';
  s.coordinate = o['coordinate'] !== undefined && o['coordinate'] !== null ? `${o['coordinate']}` : 'WGS-84';
  s.maxLevel = toInt(o['maxLevel'] ?? 18, 18);
  s.isDefault = toBool(o['isDefault']);
  s.isCustom = toBool(o['isCustom']);
  // 对齐 Flutter：current 字段映射 isCurrent
  s.isCurrent = toBool(o['current']);
  return s;
}

/** 缩放范围（对齐 Flutter PhotoMapZoomInfo） */
export class PhotoMapZoomInfo {
  minZoom: number = 2;
  maxZoom: number = 18;
}

export function parsePhotoMapZoomInfo(raw: Object): PhotoMapZoomInfo {
  const z = new PhotoMapZoomInfo();
  const o = raw as Record<string, ESObject>;
  z.minZoom = toInt(o['minZoom'] ?? 2, 2);
  z.maxZoom = toInt(o['maxZoom'] ?? 18, 18);
  return z;
}

/** 地图照片索引项（对齐 Flutter PhotoMapIndexItem） */
export class PhotoMapIndexItem {
  id: number = 0;
  latitude: number = 0;
  longitude: number = 0;
  geohash: string = '';
  originalTime: number = 0;
  fullpath: string = '';
  type: string = '';
  duration: number = 0;
}

export function parsePhotoMapIndexItem(raw: Object): PhotoMapIndexItem {
  const it = new PhotoMapIndexItem();
  const o = raw as Record<string, ESObject>;
  it.id = toInt(o['id'] ?? 0, 0);
  it.latitude = Number(o['latitude'] ?? 0) || 0;
  it.longitude = Number(o['longitude'] ?? 0) || 0;
  it.geohash = o['geohash'] !== undefined && o['geohash'] !== null ? `${o['geohash']}` : '';
  it.originalTime = toInt(o['original_time'] ?? 0, 0);
  it.fullpath = o['fullpath'] !== undefined && o['fullpath'] !== null ? `${o['fullpath']}` : '';
  it.type = o['type'] !== undefined && o['type'] !== null ? `${o['type']}` : '';
  it.duration = Number(o['duration'] ?? 0) || 0;
  return it;
}
