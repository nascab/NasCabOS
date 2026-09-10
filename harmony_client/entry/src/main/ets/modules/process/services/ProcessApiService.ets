import { APIClient } from '../../../core/network/APIClient';
import { APIResponse } from '../../../core/network/APIResponse';
import { AppEventBus } from '../../../common/AppEventBus';
import { L10n } from '../../../core/localization/L10n';
import { WorkerProcessItem } from '../models/ProcessModels';

/**
 * 进程 API 服务（对齐 Flutter modules/process/service/process_api_service.dart）。
 */
export class ProcessApiService {
  /**
   * 拉取 worker 进程列表（对齐 fetchWorkerProcessList）：
   * GET /api/service/process，超时 15s，不展示全局 loading。
   * 响应 data 非数组时按空列表成功处理（对齐 Flutter raw is! List 分支）。
   */
  static async fetchWorkerProcessList(): Promise<APIResponse<WorkerProcessItem[]>> {
    const res = await APIClient.getInstance().apiGet<Object>('/api/service/process', undefined, 15000);
    if (!res.success) {
      if (res.code === 401) {
        AppEventBus.emitAuthSessionExpired();
      }
      const msg = res.message !== undefined && res.message.length > 0 ? res.message : L10n.networkFailure;
      return APIResponse.failure<WorkerProcessItem[]>(msg, res.code, res.rawResponse);
    }
    const raw = res.data;
    if (raw === undefined || raw === null || !Array.isArray(raw)) {
      return APIResponse.success<WorkerProcessItem[]>([], res.message, res.code, res.rawResponse);
    }
    const list: WorkerProcessItem[] = [];
    (raw as Object[]).forEach((e: Object): void => {
      if (e !== null && e !== undefined && typeof e === 'object' && !Array.isArray(e)) {
        list.push(WorkerProcessItem.fromJson(e as Record<string, Object>));
      }
    });
    return APIResponse.success<WorkerProcessItem[]>(list, res.message, res.code, res.rawResponse);
  }
}
