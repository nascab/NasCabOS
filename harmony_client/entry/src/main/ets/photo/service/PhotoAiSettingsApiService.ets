import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';

/**
 * AI 设置 API 服务（对齐 Flutter photo_ai_settings_api_service.dart，仅移植本模块用到的方法）
 */
export class PhotoAiSettingsApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** 获取 AI 配置（对齐 Flutter getAiConfig） */
  async getAiConfig(): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {};
    return this.api().apiPost<Record<string, Object>>('/api/photo/getAiConfig', body,
      undefined, undefined, undefined, (d: Object, _c: number) => d as Record<string, Object>);
  }

  /** 设置人脸识别开关（对齐 Flutter setAiFaceEnable） */
  async setAiFaceEnable(enable: boolean): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'enable': enable ? 1 : 0 };
    return this.api().apiPost<Record<string, Object>>('/api/photo/setAiFaceEnable', body);
  }

  /** 设置场景识别开关（对齐 Flutter setAiPlaceEnable） */
  async setAiPlaceEnable(enable: boolean): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'enable': enable ? 1 : 0 };
    return this.api().apiPost<Record<string, Object>>('/api/photo/setAiPlaceEnable', body);
  }

  /** 设置照片去重开关（对齐 Flutter setAiSimilarEnable） */
  async setAiSimilarEnable(enable: boolean): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'enable': enable ? 1 : 0 };
    return this.api().apiPost<Record<string, Object>>('/api/photo/setAiSimilarEnable', body);
  }

  /** 重置照片去重扫描（对齐 Flutter resetSimilar） */
  async resetSimilar(): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {};
    return this.api().apiPost<Record<string, Object>>('/api/photo/similar/reset', body);
  }

  /** 设置人脸相册自动隐藏阈值（对齐 Flutter setAiFaceMinShowCount） */
  async setAiFaceMinShowCount(minShowCount: number): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'min_show_count': minShowCount < 0 ? 0 : minShowCount };
    return this.api().apiPost<Record<string, Object>>('/api/photo/setAiFaceMinShowCount', body);
  }

  /** 设置 OCR 文字识别开关（对齐 Flutter setAiOcrEnable） */
  async setAiOcrEnable(enable: boolean): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'enable': enable ? 1 : 0 };
    return this.api().apiPost<Record<string, Object>>('/api/photo/setAiOcrEnable', body);
  }

  /** 设置 GPU 优先开关（对齐 Flutter setAiGpuPrefer） */
  async setAiGpuPrefer(enable: boolean): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'enable': enable ? 1 : 0 };
    return this.api().apiPost<Record<string, Object>>('/api/photo/setAiGpuPrefer', body);
  }

  /** 获取预览尺寸配置（对齐 Flutter getPreviewConfig） */
  async getPreviewConfig(): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = {};
    return this.api().apiPost<Record<string, Object>>('/api/photo/getPreviewConfig', body);
  }

  /** 设置预览尺寸（对齐 Flutter setPreviewSize） */
  async setPreviewSize(size: string): Promise<APIResponse<Record<string, Object>>> {
    const body: Record<string, Object> = { 'size': size };
    return this.api().apiPost<Record<string, Object>>('/api/photo/setPreviewSize', body);
  }
}
