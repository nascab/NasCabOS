import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import { PhotoSource, parsePhotoSource } from '../models/PhotoSourceModels';

/**
 * 照片来源 API 服务（对齐 Flutter source_setting/service/photo_source_api_service.dart）
 */
export class PhotoSourceApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** 列出所有照片来源（对齐 Flutter listSources，返回数组） */
  async listSources(): Promise<PhotoSource[]> {
    const body: Record<string, Object> = {};
    const res = await this.api().apiPost<Object[]>('/api/photo/source/list', body,
      undefined, undefined, undefined, (d: Object, _c: number) => (Array.isArray(d) ? d : []));
    if (!res.success || res.data === undefined) {
      return [];
    }
    const list: PhotoSource[] = [];
    for (const e of res.data) {
      if (e !== null && typeof e === 'object') {
        list.push(parsePhotoSource(e));
      }
    }
    return list;
  }

  /** 添加来源（对齐 Flutter addSource） */
  async addSource(path: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'path': path };
    return this.api().apiPost<Record<string, Object>>('/api/photo/source/add', body);
  }

  /** 更新来源（对齐 Flutter updateSource，payload 为 snake_case 字段） */
  async updateSource(id: number, payload: Record<string, Object>): Promise<APIResponse<Record<string, Object>>> {
    return this.api().apiPost<Record<string, Object>>(`/api/photo/source/update/${id}`, payload);
  }

  /** 删除来源（对齐 Flutter deleteSource） */
  async deleteSource(id: number): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<Record<string, Object>>('/api/photo/source/delete', body);
  }

  /** 重新定位来源（对齐 Flutter relocateSource） */
  async relocateSource(id: number, newPath: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'new_path': newPath };
    return this.api().apiPost<Record<string, Object>>(`/api/photo/source/relocate/${id}`, body);
  }

  /** 立即扫描（对齐 Flutter scanSource） */
  async scanSource(path: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'path': path };
    return this.api().apiPost<Record<string, Object>>('/api/photo/source/scan', body);
  }

  /** 重置缩略图（对齐 Flutter preGenerateThumbnails） */
  async preGenerateThumbnails(): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {};
    return this.api().apiPost<Record<string, Object>>('/api/photo/source/regenerate_thumbnails', body);
  }
}
