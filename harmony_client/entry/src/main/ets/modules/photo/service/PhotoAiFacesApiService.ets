import { APIClient } from '../../../core/network/APIClient';
import { APIResponse } from '../../../core/network/APIResponse';
import { AiFaceListResult, parseAiFaceListResult } from '../models/PhotoAiModels';

/**
 * 人脸相册 API 服务（对齐 Flutter photo_ai_faces_api_service.dart）
 */
export class PhotoAiFacesApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** 人脸列表（分页 + 状态过滤 + 关键字，对齐 Flutter listFaces） */
  async listFaces(page: number = 1, pageSize: number = 50, status: string = 'visiable',
    keyword: string = ''): Promise<APIResponse<AiFaceListResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'pageSize': pageSize,
      'status': status
    };
    if (keyword.trim().length > 0) {
      body['keyword'] = keyword.trim();
    }
    return this.api().apiPost<AiFaceListResult>('/api/photo/face/list', body,
      undefined, undefined, undefined, (d: Object, _c: number) => parseAiFaceListResult(d));
  }

  /** 修改人脸名字（对齐 Flutter updateFaceName） */
  async updateFaceName(faceId: number, name: string): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'face_id': faceId, 'name': name };
    return this.api().apiPost<boolean>('/api/photo/face/name/update', body);
  }

  /** 设置人脸显示/隐藏（对齐 Flutter setFaceStatus） */
  async setFaceStatus(faceId: number, isHide: boolean): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'face_id': faceId, 'is_hide': isHide ? 1 : 0 };
    return this.api().apiPost<boolean>('/api/photo/face/status/set', body);
  }

  /** 合并多个人脸（对齐 Flutter mergeFaces） */
  async mergeFaces(faceIds: number[]): Promise<APIResponse<boolean>> {
    const ids: number[] = [];
    for (const id of faceIds) {
      if (id > 0) {
        ids.push(id);
      }
    }
    const body: Record<string, Object> = { 'face_ids': ids };
    return this.api().apiPost<boolean>('/api/photo/face/merge', body);
  }

  /** 重置人脸识别（对齐 Flutter resetFaces） */
  async resetFaces(): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = {};
    return this.api().apiPost<boolean>('/api/photo/face/reset', body);
  }

  /** 把整个人脸合并（移动）到另一人脸（对齐 Flutter moveFaceToOther） */
  async moveFaceToOther(fromFaceId: number, toFaceId: number): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'from_face_id': fromFaceId, 'to_face_id': toFaceId };
    return this.api().apiPost<boolean>('/api/photo/face/merge', body);
  }

  /** 把单张照片移出指定人脸（对齐 Flutter removePhotoFromFace） */
  async removePhotoFromFace(faceId: number, fileHash: string): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'face_id': faceId, 'file_hash': fileHash };
    return this.api().apiPost<boolean>('/api/photo/face/photo/remove', body);
  }

  /** 把照片移动到另一人脸（对齐 Flutter movePhotoToFace） */
  async movePhotoToFace(fromFaceId: number, toFaceId: number,
    fileHashes: string[]): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = {
      'from_face_id': fromFaceId,
      'to_face_id': toFaceId,
      'file_hashes': fileHashes
    };
    return this.api().apiPost<boolean>('/api/photo/face/photo/move', body);
  }

  /** 人脸相册下载文件路径（对齐 Flutter /api/photo/download/info，albumType:face） */
  async faceDownloadPaths(faceId: number): Promise<string[]> {
    const body: Record<string, Object> = { 'albumType': 'face', 'albumId': faceId };
    try {
      const res = await this.api().apiPost<Record<string, Object>>('/api/photo/download/info', body,
        undefined, undefined, undefined, (d: Object, _c: number) => d as Record<string, Object>);
      if (!res.success || res.data === undefined) {
        return [];
      }
      const items = res.data['items'];
      if (!Array.isArray(items)) {
        return [];
      }
      const paths: string[] = [];
      for (const e of items as Record<string, Object>[]) {
        const p = e['path'];
        const v = p === undefined || p === null ? '' : `${p}`.trim();
        if (v.length > 0) {
          paths.push(v);
        }
      }
      return paths;
    } catch (_e) {
      return [];
    }
  }
}
