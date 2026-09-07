import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import { AiSceneListResult, parseAiSceneListResult } from '../models/PhotoAiModels';

/**
 * 场景相册 API 服务（对齐 Flutter photo_ai_scenes_api_service.dart）
 */
export class PhotoAiScenesApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** 场景列表（对齐 Flutter listScenes：一次取全部，客户端过滤） */
  async listScenes(status: string = 'visible'): Promise<APIResponse<AiSceneListResult>> {
    const body: Record<string, Object> = { 'status': status };
    return this.api().apiPost<AiSceneListResult>('/api/photo/place/list', body,
      undefined, undefined, undefined, (d: Object, _c: number) => parseAiSceneListResult(d));
  }

  /** 设置场景显示/隐藏（对齐 Flutter setSceneStatus） */
  async setSceneStatus(placeName: string, isHide: boolean): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'place_name': placeName, 'is_hide': isHide };
    return this.api().apiPost<boolean>('/api/photo/place/status/set', body);
  }

  /** 重置场景识别（对齐 Flutter resetScenes） */
  async resetScenes(): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = {};
    return this.api().apiPost<boolean>('/api/photo/place/reset', body);
  }
}
