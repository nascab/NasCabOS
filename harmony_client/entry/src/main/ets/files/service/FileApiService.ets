import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import { JsonCodec } from '../../common/JsonTypes';
import { FileItem, FileListData, FileSearchData } from '../models/FileModels';

/**
 * 文件模块 API 服务（对齐 Flutter file_api_service.dart，仅保留移动端文件浏览器使用到的端点）
 */
export class FileApiService {
  private static instance: FileApiService | undefined = undefined;

  static getInstance(): FileApiService {
    if (!FileApiService.instance) {
      FileApiService.instance = new FileApiService();
    }
    return FileApiService.instance;
  }

  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** 列出目录 */
  async listDirectory(path: string, onlyDir: boolean, includeHidden: boolean,
    source: string, sourceType: string, apiPath: string = '/api/file/list'): Promise<FileListData> {
    const body: Record<string, Object> = {
      'path': path,
      'onlyDir': onlyDir ? 'true' : 'false',
      'includeHidden': includeHidden ? 'true' : 'false',
      'source': source
    };
    if (sourceType.length > 0) {
      body['sourceType'] = sourceType;
    }
    const res = await this.api().apiPost<Object>(apiPath, body, undefined, undefined, undefined,
      (d: Object, _c: number) => d);
    const data = res.data;
    if (!res.success || data === undefined) {
      return new FileListData();
    }
    return JsonCodec.parse<FileListData>(data);
  }

  /** 全局/子树搜索 */
  async searchGlobal(keyword: string, directory: string, suffixes: string[], mode: string,
    limit: number, apiPath: string = '/api/file/search', sourceType: string = ''): Promise<APIResponse<FileSearchData>> {
    const body: Record<string, Object> = {
      'keyword': keyword,
      'limit': limit
    };
    if (directory.length > 0) {
      body['directory'] = directory;
    }
    if (suffixes.length > 0) {
      body['suffixes'] = suffixes;
    }
    if (mode.length > 0) {
      body['mode'] = mode;
    }
    if (sourceType.length > 0) {
      body['sourceType'] = sourceType;
    }
    return this.api().apiPost<FileSearchData>(apiPath, body, undefined, undefined, undefined,
      (d: Object, _c: number) => JsonCodec.parse<FileSearchData>(d));
  }

  /** 创建文件夹 */
  async mkdir(base: string, name: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'base': base, 'name': name };
    return this.api().apiPost<Object>('/api/file/mkdir', body, undefined, undefined, undefined,
      (d: Object, _c: number) => d);
  }

  /** 新建文件（仅 txt / md） */
  async createFile(base: string, name: string, type: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'base': base, 'name': name, 'type': type };
    return this.api().apiPost<Object>('/api/file/create', body, undefined, undefined, undefined,
      (d: Object, _c: number) => JsonCodec.parse<FileItem>(d) as Object);
  }

  /** 检查目录是否支持写入（新建文件夹/文件） */
  async checkMkdirSupport(base: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'base': base };
    return this.api().apiPost<Object>('/api/file/mkdir/check', body, undefined, undefined, undefined,
      (d: Object, _c: number) => JsonCodec.parse<Record<string, Object>>(d) as Object);
  }

  /** 删除多个文件或文件夹 */
  async deleteEntries(paths: string[], recycle: boolean): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'paths': paths, 'recycle': recycle };
    return this.api().apiPost<Object>('/api/file/delete', body, undefined, undefined, undefined,
      (d: Object, _c: number) => d);
  }

  /** 列出收藏 */
  async listFavorites(): Promise<FileItem[]> {
    const res = await this.api().apiPost<FileItem[]>('/api/file/quick/favorites/list', undefined,
      undefined, undefined, undefined, (d: Object, _c: number) => JsonCodec.parse<FileItem[]>(d));
    return res.data ?? [];
  }

  /** 添加收藏 */
  async addFavorites(paths: string[]): Promise<boolean> {
    const body: Record<string, Object> = { 'paths': paths };
    const res = await this.api().apiPost<Object>('/api/file/quick/favorites/add', body);
    return res.success;
  }

  /** 移除收藏 */
  async removeFavorites(paths: string[]): Promise<boolean> {
    const body: Record<string, Object> = { 'paths': paths };
    const res = await this.api().apiPost<Object>('/api/file/quick/favorites/remove', body);
    return res.success;
  }

  /** 清除最近访问记录 */
  async clearRecent(): Promise<boolean> {
    const body: Record<string, Object> = {};
    const res = await this.api().apiPost<Object>('/api/file/quick/recent/clear', body);
    return res.success;
  }

  /** 复制文件 */
  async copyFiles(paths: string[], targetPath: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'paths': paths, 'targetPath': targetPath };
    return this.api().apiPost<Object>('/api/file/copy', body, undefined, undefined, undefined,
      (d: Object, _c: number) => d);
  }

  /** 移动文件 */
  async moveFiles(paths: string[], targetPath: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'paths': paths, 'targetPath': targetPath };
    return this.api().apiPost<Object>('/api/file/move', body, undefined, undefined, undefined,
      (d: Object, _c: number) => d);
  }

  /** 重命名文件或文件夹 */
  async rename(path: string, newName: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'path': path, 'newName': newName };
    return this.api().apiPost<Object>('/api/file/rename', body, undefined, undefined, undefined,
      (d: Object, _c: number) => JsonCodec.parse<FileItem>(d) as Object);
  }

  /** 获取索引设置 */
  async getIndexSettings(): Promise<APIResponse<Object>> {
    return this.api().apiGet<Object>('/api/file/config/index', undefined, undefined, undefined,
      (d: Object, _c: number) => JsonCodec.parse<Record<string, Object>>(d) as Object);
  }

  /** 保存索引设置 */
  async saveIndexSettings(enabled: boolean, intervalHours: number): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'enabled': enabled, 'intervalHours': intervalHours };
    return this.api().apiPost<Object>('/api/file/config/index', body, undefined, undefined, undefined,
      (d: Object, _c: number) => JsonCodec.parse<Record<string, Object>>(d) as Object);
  }

  /** 重置索引 */
  async resetIndex(): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = {};
    return this.api().apiPost<Object>('/api/file/config/index/reset', body, undefined, undefined,
      undefined, (d: Object, _c: number) => d);
  }

  /** 添加自定义根路径 */
  async addCustomPath(name: string, path: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'name': name, 'path': path };
    return this.api().apiPost<Object>('/api/file/customPath/add', body, undefined, 10000, undefined,
      (d: Object, _c: number) => d);
  }

  /** 移除自定义根路径 */
  async removeCustomPath(path: string): Promise<APIResponse<Object>> {
    const body: Record<string, Object> = { 'path': path };
    return this.api().apiPost<Object>('/api/file/customPath/remove', body, undefined, undefined,
      undefined, (d: Object, _c: number) => d);
  }
}
