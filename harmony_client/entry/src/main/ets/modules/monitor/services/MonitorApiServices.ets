import { APIClient } from '../../../core/network/APIClient';
import { L10n } from '../../../core/localization/L10n';
import { AppEventBus } from '../../../common/AppEventBus';
import { MonitorMetrics } from '../models/MonitorModels';

/**
 * 监控模块通用结果（对齐 Flutter ApiResponse 用法）。
 */
export class MonitorApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;

  static ok<D>(data: D | undefined, message: string = ''): MonitorApiResult<D> {
    const r = new MonitorApiResult<D>();
    r.success = true;
    r.data = data;
    r.message = message;
    return r;
  }

  static fail<D>(message: string): MonitorApiResult<D> {
    const r = new MonitorApiResult<D>();
    r.success = false;
    r.message = message;
    return r;
  }
}

/**
 * 监控 API 服务（对齐 Flutter _HwApiService：GET /api/hw/metrics，静默请求）。
 */
export class MonitorApiService {
  private static readonly metricsPath = '/api/hw/metrics';

  static async getMetrics(): Promise<MonitorApiResult<MonitorMetrics>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return MonitorApiResult.fail<MonitorMetrics>(L10n.networkFailure);
    }
    try {
      const res = await api.apiGet<Object>(MonitorApiService.metricsPath);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        return MonitorApiResult.fail<MonitorMetrics>(
          msg.length > 0 ? msg : L10n.operationFailed);
      }
      const raw = res.data;
      if (raw === undefined || raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
        return MonitorApiResult.fail<MonitorMetrics>(L10n.networkFailure);
      }
      return MonitorApiResult.ok<MonitorMetrics>(
        MonitorMetrics.fromJson(raw as Record<string, Object>));
    } catch (_e) {
      return MonitorApiResult.fail<MonitorMetrics>(L10n.networkFailure);
    }
  }
}
