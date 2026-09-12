import { APIClient } from '../../core/network/APIClient';
import { FileLogListResponse } from '../../modules/user/models/UserModels';

function asRecord(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null || Array.isArray(v) || typeof v !== 'object') {
    return {} as Record<string, Object>;
  }
  return v as Record<string, Object>;
}

/**
 * 文件操作日志服务（对齐 Flutter FileLogRepository）：
 * 全局文件操作日志的查询/清除/取消操作。
 */
export class FileLogService {
  /** 文件操作日志分页（POST /api/file/log/list，body {types,page,pageSize,stateList,keyword}） */
  static async getFileLogs(types: string[] | undefined, page: number, pageSize: number,
    stateList: string[] | undefined, keyword: string | undefined): Promise<FileLogListResponse | undefined> {
    const body: Record<string, Object> = {
      'page': page,
      'pageSize': pageSize
    };
    if (types !== undefined) {
      body['types'] = types;
    }
    if (stateList !== undefined) {
      body['stateList'] = stateList;
    }
    if (keyword !== undefined && keyword.length > 0) {
      body['keyword'] = keyword;
    }
    const res = await APIClient.getInstance().apiPost<FileLogListResponse>(
      '/api/file/log/list', body, undefined, undefined, undefined,
      (data: Object, _code: number): FileLogListResponse =>
        FileLogListResponse.fromJson(asRecord(data)));
    if (!res.success) {
      return undefined;
    }
    return res.data;
  }

  /** 清除操作日志（POST /api/file/log/clear，stateList 缺省表示清除全部） */
  static async clearLogs(stateList: string[] | undefined): Promise<boolean> {
    const body: Record<string, Object> = {};
    if (stateList !== undefined) {
      body['stateList'] = stateList;
    }
    const res = await APIClient.getInstance().apiPost<Object>('/api/file/log/clear', body);
    return res.success;
  }

  /** 取消进行中的文件操作（POST /api/file/cancel_file_operation，body {id}） */
  static async cancelFileOperation(id: number): Promise<boolean> {
    const body: Record<string, Object> = { 'id': id };
    const res = await APIClient.getInstance().apiPost<Object>('/api/file/cancel_file_operation', body);
    return res.success;
  }
}
