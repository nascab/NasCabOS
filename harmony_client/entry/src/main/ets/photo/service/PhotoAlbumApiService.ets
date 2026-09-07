import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import {
  PhotoAlbumListResult, PhotoAlbumDetail, PhotoAlbumOverviewResult,
  PhotoCollectionListResult, PhotoSmartAlbumListResult,
  parseAlbumListResult, parseAlbumDetail, parseAlbumOverviewResult,
  parseCollectionListResult, parseSmartAlbumListResult
} from '../models/PhotoAlbumModels';

/**
 * 相册 API 服务（对齐 Flutter photo_album_api_service.dart）
 */
export class PhotoAlbumApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async listAlbums(page: number = 1, pageSize: number = 20, keyword: string = '',
    type: string = 'all', sortField: string = 'create_time', sortOrder: string = 'desc'):
    Promise<APIResponse<PhotoAlbumListResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'pageSize': pageSize,
      'sortField': sortField,
      'sortOrder': sortOrder
    };
    if (keyword.trim().length > 0) {
      body['keyword'] = keyword.trim();
    }
    if (type.length > 0) {
      body['type'] = type;
    }
    return this.api().apiPost<PhotoAlbumListResult>('/api/photo/album/list', body,
      undefined, undefined, undefined, parseAlbumListResult);
  }

  async getAlbumOverview(limit: number = 6): Promise<APIResponse<PhotoAlbumOverviewResult>> {
    const safeLimit = Math.min(Math.max(limit, 1), 12);
    const body: Record<string, Object> = { 'limit': safeLimit };
    return this.api().apiPost<PhotoAlbumOverviewResult>('/api/photo/album/overview', body,
      undefined, undefined, undefined, parseAlbumOverviewResult);
  }

  async getAlbum(id: number): Promise<APIResponse<PhotoAlbumDetail>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<PhotoAlbumDetail>('/api/photo/album/get', body,
      undefined, undefined, undefined, parseAlbumDetail);
  }

  async createAlbum(name: string, isPublic: boolean): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {
      'name': name,
      'is_public': isPublic ? 1 : 0,
      'shares': []
    };
    return this.api().apiPost<Object>('/api/photo/album/create', body, undefined, undefined,
      undefined);
  }

  async updateAlbum(id: number, name: string, isPublic: boolean): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = {
      'id': id,
      'name': name,
      'is_public': isPublic ? 1 : 0
    };
    return this.api().apiPost<boolean>('/api/photo/album/update', body, undefined, undefined,
      undefined);
  }

  async deleteAlbum(id: number): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<Object>('/api/photo/album/delete', body, undefined, undefined,
      undefined);
  }

  async addAlbumIndexes(albumId: number, fileHashes: string[]): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'album_id': albumId, 'file_hashes': fileHashes };
    return this.api().apiPost<Object>('/api/photo/album/index/add', body, undefined, undefined,
      undefined);
  }

  async removeAlbumIndexes(albumId: number, fileHashes: string[]): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'album_id': albumId, 'file_hashes': fileHashes };
    return this.api().apiPost<Object>('/api/photo/album/index/remove', body, undefined,
      undefined, undefined, undefined);
  }

  async setAlbumCover(albumId: number, fileHash: string): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'album_id': albumId, 'file_hash': fileHash };
    return this.api().apiPost<boolean>('/api/photo/album/cover/set', body, undefined,
      undefined, undefined, undefined);
  }
}

/**
 * 合集 API 服务（对齐 Flutter photo_collection_api_service.dart）
 */
export class PhotoCollectionApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async listCollections(page: number = 1, pageSize: number = 20, keyword: string = '',
    sortField: string = 'create_time', sortOrder: string = 'desc'):
    Promise<APIResponse<PhotoCollectionListResult>> {
    const body: Record<string, Object> = {
      'page': page,
      'pageSize': pageSize,
      'sortField': sortField,
      'sortOrder': sortOrder
    };
    if (keyword.trim().length > 0) {
      body['keyword'] = keyword.trim();
    }
    return this.api().apiPost<PhotoCollectionListResult>('/api/photo/collection/list', body,
      undefined, undefined, undefined, parseCollectionListResult);
  }

  async createCollection(name: string, pathList: string[]): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'name': name, 'path_list': pathList };
    return this.api().apiPost<Object>('/api/photo/collection/create', body, undefined,
      undefined, undefined, undefined);
  }

  async updateCollection(id: number, name: string, pathList: string[]):
    Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {
      'id': id,
      'name': name,
      'path_list': pathList
    };
    return this.api().apiPost<Object>('/api/photo/collection/update', body, undefined,
      undefined, undefined, undefined);
  }

  async deleteCollection(id: number): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<Object>('/api/photo/collection/delete', body, undefined,
      undefined, undefined, undefined);
  }
}

/**
 * 智能相册 API 服务（对齐 Flutter photo_smart_album_api_service.dart）
 */
export class PhotoSmartAlbumApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  async listSmartAlbums(page: number = 1, pageSize: number = 20, keyword: string = ''):
    Promise<APIResponse<PhotoSmartAlbumListResult>> {
    const body: Record<string, Object> = { 'page': page, 'pageSize': pageSize };
    if (keyword.trim().length > 0) {
      body['keyword'] = keyword.trim();
    }
    return this.api().apiPost<PhotoSmartAlbumListResult>('/api/photo/smart_album/list', body,
      undefined, undefined, undefined, parseSmartAlbumListResult);
  }

  async createSmartAlbum(name: string, type: string, filterContent: Record<string, Object>):
    Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {
      'name': name,
      'type': type,
      'filter_content': filterContent
    };
    return this.api().apiPost<Object>('/api/photo/smart_album/create', body, undefined,
      undefined, undefined, undefined);
  }

  async updateSmartAlbum(id: number, name: string, type: string,
    filterContent: Record<string, Object>): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {
      'id': id,
      'name': name,
      'type': type,
      'filter_content': filterContent
    };
    return this.api().apiPost<Object>('/api/photo/smart_album/update', body, undefined,
      undefined, undefined, undefined);
  }

  async deleteSmartAlbum(id: number): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return this.api().apiPost<Object>('/api/photo/smart_album/delete', body, undefined,
      undefined, undefined, undefined);
  }
}
