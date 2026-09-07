import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import {
  PhotoMapIndexItem,
  PhotoMapTileServer,
  PhotoMapZoomInfo,
  parsePhotoMapIndexItem,
  parsePhotoMapTileServer,
  parsePhotoMapZoomInfo
} from '../models/PhotoMapModels';

/** getZoom 组合结果（ArkTS 无元组） */
export class ZoomAndTileServer {
  zoomInfo: PhotoMapZoomInfo = new PhotoMapZoomInfo();
  tileServer: PhotoMapTileServer = new PhotoMapTileServer();
}

/**
 * 足迹地图 API 服务（对齐 Flutter map/service/photo_map_api_service.dart）
 */
export class PhotoMapApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** 获取缩放范围与当前瓦片服务器（对齐 Flutter getZoom） */
  async getZoom(): Promise<APIResponse<ZoomAndTileServer>> {
    const res = await this.api().apiGet<Record<string, Object>>('/api/mapApi/getZoom');
    if (!res.success || res.data === undefined) {
      return APIResponse.failure<ZoomAndTileServer>(res.message ?? '', res.code);
    }
    const o = res.data as Record<string, Object>;
    const result = new ZoomAndTileServer();
    const zi: Object | undefined = o['zoomInfo'];
    if (zi !== undefined && zi !== null && typeof zi === 'object') {
      result.zoomInfo = parsePhotoMapZoomInfo(zi);
    }
    const ts: Object | undefined = o['tileServer'];
    if (ts !== undefined && ts !== null && typeof ts === 'object') {
      result.tileServer = parsePhotoMapTileServer(ts);
    }
    return APIResponse.success<ZoomAndTileServer>(result, res.message, res.code);
  }

  /** 瓦片服务器列表（对齐 Flutter getTileServerList） */
  async getTileServerList(): Promise<APIResponse<PhotoMapTileServer[]>> {
    const body: Record<string, Object> = {};
    const res = await this.api().apiPost<Record<string, Object>>('/api/mapApi/getTileServerList', body);
    if (!res.success || res.data === undefined) {
      return APIResponse.failure<PhotoMapTileServer[]>(res.message ?? '', res.code);
    }
    // 对齐 Flutter：data.tileServerList 数组
    const o = res.data as Record<string, Object>;
    const raw: Object | undefined = o['tileServerList'];
    const list: PhotoMapTileServer[] = [];
    if (Array.isArray(raw)) {
      const arr = raw as Object[];
      for (const e of arr) {
        list.push(parsePhotoMapTileServer(e));
      }
    }
    return APIResponse.success<PhotoMapTileServer[]>(list, res.message, res.code);
  }

  /** 切换瓦片服务器（对齐 Flutter setTileServer） */
  async setTileServer(server: PhotoMapTileServer): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'tileServer': server.toJson() };
    const res = await this.api().apiPost<Object>('/api/mapApi/setTileServer', body);
    return APIResponse.success<boolean>(res.success, res.message, res.code);
  }

  /** 拉取可视范围内照片（对齐 Flutter getBoundsPhoto） */
  async getBoundsPhoto(minLat: number, minLng: number, maxLat: number, maxLng: number,
    zoom: number): Promise<APIResponse<PhotoMapIndexItem[]>> {
    const body: Record<string, Object> = {
      'minLat': minLat,
      'minLng': minLng,
      'maxLat': maxLat,
      'maxLng': maxLng,
      'zoom': zoom
    };
    const res = await this.api().apiPost<Record<string, Object>>('/api/mapApi/getBoundsPhoto', body);
    if (!res.success || res.data === undefined) {
      return APIResponse.failure<PhotoMapIndexItem[]>(res.message ?? '', res.code);
    }
    const o = res.data as Record<string, Object>;
    const raw: Object | undefined = o['mapPhoto'];
    const list: PhotoMapIndexItem[] = [];
    if (Array.isArray(raw)) {
      const arr = raw as Object[];
      for (const e of arr) {
        const item = parsePhotoMapIndexItem(e);
        // 对齐 Flutter：过滤 id <= 0
        if (item.id > 0) {
          list.push(item);
        }
      }
    }
    return APIResponse.success<PhotoMapIndexItem[]>(list, res.message, res.code);
  }

  /** geohash 反查地名（对齐 Flutter getLocationStr） */
  async getLocationStr(geohash: string): Promise<APIResponse<string>> {
    const body: Record<string, Object> = { 'geohash': geohash };
    const res = await this.api().apiPost<Record<string, Object>>('/api/mapApi/getLocationStr', body);
    if (!res.success || res.data === undefined) {
      return APIResponse.failure<string>(res.message ?? '', res.code);
    }
    const o = res.data as Record<string, Object>;
    const geo: Object | undefined = o['geo'];
    return APIResponse.success<string>(geo !== undefined && geo !== null ? `${geo}` : '', res.message, res.code);
  }
}
