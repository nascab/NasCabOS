import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import {
  TimelineDateListResult, TimelinePhotoListResult, TimelineYearListResult,
  TimelineDetectedFaceItem, TrashPhotoListResult,
  parseTimelineDateListResult, parseTimelinePhotoListResult,
  parseTimelineYearListResult, parseTrashPhotoListResult, jsonAsBool
} from '../models/PhotoModels';

/** 时间轴查询过滤参数（对齐 Flutter getTimelineDateList/getTimelinePhotoList 入参） */
export class TimelineFilter {
  sort: string = 'desc';
  fileType: string = '';
  search: string = '';
  geohash: string = '';
  sourceList: string[] = [];
  listType: string = 'timeline';
  albumId: number = 0;
  collectionId: number = 0;
  smartAlbumId: number = 0;
  faceId: number = 0;
  placeName: string = '';
  loadTheDay: boolean = false;
  year: number = 0;
}

/**
 * 照片时间轴 API 服务（对齐 Flutter photo_timeline_api_service.dart）
 */
export class PhotoTimelineApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  private buildFilterBody(f: TimelineFilter, withRange: boolean, startTime: number = 0,
    endTime: number = 0): Record<string, Object> {
    const body: Record<string, Object> = { 'sort': f.sort };
    if (f.fileType.length > 0 && f.fileType !== 'all') {
      body['fileType'] = f.fileType;
    }
    if (withRange) {
      body['startTime'] = startTime;
      body['endTime'] = endTime;
    }
    if (f.search.length > 0) {
      body['search'] = f.search;
    }
    if (f.geohash.trim().length > 0) {
      body['geohash'] = f.geohash.trim();
    }
    if (f.sourceList.length > 0) {
      body['sourceList'] = f.sourceList;
    }
    if (f.listType === 'favorite') {
      body['list_type'] = 'favorite';
    }
    if (f.albumId > 0) {
      body['album_id'] = f.albumId;
    }
    if (f.collectionId > 0) {
      body['collection_id'] = f.collectionId;
    }
    if (f.smartAlbumId > 0) {
      body['smart_album_id'] = f.smartAlbumId;
    }
    if (f.faceId > 0) {
      body['face_id'] = f.faceId;
    }
    if (f.placeName.trim().length > 0) {
      body['place_name'] = f.placeName.trim();
    }
    if (f.loadTheDay) {
      body['loadTheDay'] = 1;
    }
    if (f.year > 0) {
      body['year'] = f.year;
    }
    return body;
  }

  /** 获取时间轴日期列表 */
  async getTimelineDateList(f: TimelineFilter): Promise<APIResponse<TimelineDateListResult>> {
    return this.api().apiPost<TimelineDateListResult>('/api/photo/timeline/dates',
      this.buildFilterBody(f, false), undefined, undefined, undefined,
      (d: Object, _c: number) => parseTimelineDateListResult(d));
  }

  /** 获取时间轴照片列表（按时间范围分页） */
  async getTimelinePhotoList(f: TimelineFilter, startTime: number, endTime: number,
  ): Promise<APIResponse<TimelinePhotoListResult>> {
    return this.api().apiPost<TimelinePhotoListResult>('/api/photo/timeline/photos',
      this.buildFilterBody(f, true, startTime, endTime), undefined, undefined, undefined,
      (d: Object, _c: number) => parseTimelinePhotoListResult(d));
  }

  /** 获取年份列表（按年视图封面） */
  async getTimelineYearList(): Promise<APIResponse<TimelineYearListResult>> {
    const body: Record<string, Object> = {};
    return this.api().apiPost<TimelineYearListResult>('/api/photo/timeline/years', body,
      undefined, undefined, undefined, (d: Object, _c: number) => parseTimelineYearListResult(d));
  }

  /** 获取回收站照片列表（对齐 Flutter getTrashPhotoList：fileType='all'/search 为空时不传该字段） */
  async getTrashPhotoList(page: number, pageSize: number, fileType: string, search: string,
    sortField: string = 'in_trash_time', sortOrder: string = 'desc'): Promise<APIResponse<TrashPhotoListResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'pageSize': pageSize,
      'sortField': sortField,
      'sortOrder': sortOrder
    };
    if (fileType.length > 0 && fileType !== 'all') {
      body['fileType'] = fileType;
    }
    if (search.trim().length > 0) {
      body['search'] = search;
    }
    return this.api().apiPost<TrashPhotoListResult>('/api/photo/trash/list', body,
      undefined, undefined, undefined, (d: Object, _c: number) => parseTrashPhotoListResult(d));
  }

  /** 切换单个收藏状态，返回最终 is_favorite */
  async toggleFavorite(fileHash: string): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'file_hash': fileHash };
    return this.api().apiPost<boolean>('/api/photo/favorite/toggle', body,
      undefined, undefined, undefined, (d: Object, _c: number) => {
        const map = d as Record<string, Object>;
        return jsonAsBool(map['is_favorite']);
      });
  }

  /** 批量收藏/取消收藏 */
  async batchFavorite(fileHashes: string[], isFavorite: boolean): Promise<boolean> {
    const body: Record<string, Object> = {
      'file_hashes': fileHashes,
      'is_favorite': isFavorite
    };
    const res = await this.api().apiPost<Object>('/api/photo/favorite/batch', body);
    return res.success;
  }

  /** 批量放入回收站 */
  async batchTrash(ids: number[]): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'ids': ids };
    return this.api().apiPost<Object>('/api/photo/trash/add', body, undefined, undefined,
      undefined, (d: Object, _c: number) => d);
  }

  /** 从回收站恢复 */
  async restoreFromTrash(ids: number[]): Promise<boolean> {
    const body: Record<string, Object> = { 'ids': ids };
    const res = await this.api().apiPost<Object>('/api/photo/trash/restore', body);
    return res.success;
  }

  /** 恢复回收站全部照片 */
  async restoreAllFromTrash(): Promise<boolean> {
    const body: Record<string, Object> = { 'restore_all': 1 };
    const res = await this.api().apiPost<Object>('/api/photo/trash/restore', body);
    return res.success;
  }

  /** 从回收站删除（物理删除） */
  async deleteFromTrash(ids: number[], recycle: boolean = false, deleteLivePhotoFile: boolean = true,
    deleteRawFile: boolean = true): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {
      'ids': ids,
      'recycle': recycle,
      'delete_livephoto_file': deleteLivePhotoFile ? 1 : 0,
      'delete_raw_file': deleteRawFile ? 1 : 0
    };
    return this.api().apiPost<Object>('/api/photo/trash/delete', body, undefined, undefined,
      undefined, (d: Object, _c: number) => d);
  }

  /** 清空回收站 */
  async emptyTrash(recycle: boolean = false, deleteLivePhotoFile: boolean = true,
    deleteRawFile: boolean = true): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {
      'recycle': recycle,
      'delete_livephoto_file': deleteLivePhotoFile ? 1 : 0,
      'delete_raw_file': deleteRawFile ? 1 : 0
    };
    return this.api().apiPost<Object>('/api/photo/trash/empty', body, undefined, undefined,
      undefined, (d: Object, _c: number) => d);
  }

  /** 列出照片中检测到的人脸 */
  async listPhotoFaces(fileHash: string): Promise<APIResponse<TimelineDetectedFaceItem[]>> {
    const body: Record<string, Object> = { 'file_hash': fileHash };
    return this.api().apiPost<TimelineDetectedFaceItem[]>('/api/photo/face/photo/list', body,
      undefined, undefined, undefined, (d: Object, _c: number) => {
        const items: TimelineDetectedFaceItem[] = [];
        const arr = (d as Record<string, Object>)['items'];
        if (Array.isArray(arr)) {
          for (const e of arr as Record<string, Object>[]) {
            const it = new TimelineDetectedFaceItem();
            it.faceId = parseInt(`${e['face_id'] ?? e['faceId']}`, 10) || 0;
            it.faceCount = parseInt(`${e['face_count'] ?? e['faceCount']}`, 10) || 0;
            const n = e['name'];
            it.name = n === undefined || n === null ? '' : `${n}`;
            const h = e['is_hide'] ?? e['isHide'];
            it.isHide = `${h}` === '1' || `${h}` === 'true';
            if (it.faceId > 0) {
              items.push(it);
            }
          }
        }
        return items;
      });
  }
}
