import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import { AiSimilarListResult, parseAiSimilarListResult } from '../models/PhotoAiModels';

/**
 * 相似照片（照片去重）API 服务（对齐 Flutter photo_ai_similar_api_service.dart）
 */
export class PhotoAiSimilarApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** 相似照片分组列表（分页，对齐 Flutter listSimilarGroups） */
  async listSimilarGroups(page: number = 1, pageSize: number = 20):
    Promise<APIResponse<AiSimilarListResult>> {
    const body: Record<string, Object> = { 'page': page, 'pageSize': pageSize };
    return this.api().apiPost<AiSimilarListResult>('/api/photo/similar/list', body,
      undefined, undefined, undefined, (d: Object, _c: number) => parseAiSimilarListResult(d));
  }

  /** 批量删除相似分组记录（对齐 Flutter batchDeleteGroups，返回删除条数） */
  async batchDeleteGroups(ids: number[]): Promise<APIResponse<number>> {
    const body: Record<string, Object> = { 'ids': ids };
    return this.api().apiPost<number>('/api/photo/similar/delete', body,
      undefined, undefined, undefined, (d: Object, _c: number) => {
        const map = d as Record<string, Object>;
        const n = parseInt(`${map['deleted']}`, 10);
        return isNaN(n) ? 0 : n;
      });
  }

  /** 照片属性查询（对齐 Flutter getPhotoProperties，用于相似分组默认勾选时取文件大小） */
  async getPhotoProperties(path: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'path': path };
    return this.api().apiPost<Record<string, Object>>('/api/photo/properties/get', body,
      undefined, undefined, undefined, (d: Object, _c: number) => d as Record<string, Object>);
  }
}
