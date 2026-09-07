import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import {
  AiFaceListResult, AiSceneListResult, parseAiFaceListResult, parseAiSceneListResult
} from '../models/PhotoAiModels';

type Obj = Record<string, Object>;

/** AI 概览结果（对齐 Flutter AppPhotoAiOverviewResult） */
export class AiOverviewResult {
  faces: AiFaceListResult = new AiFaceListResult();
  scenes: AiSceneListResult = new AiSceneListResult();
  similarEnable: boolean = true;
}

/** 解析开关字段：bool/数字1/字符串'1'/'true'，缺省 true（对齐 Flutter parseEnable） */
function parseEnable(v: Object | undefined | null): boolean {
  if (v === undefined || v === null) {
    return true;
  }
  if (typeof v === 'boolean') {
    return v;
  }
  if (typeof v === 'number') {
    return Math.floor(v) === 1;
  }
  const s = `${v}`.toLowerCase();
  return s === '1' || s === 'true';
}

export function parseAiOverviewResult(d: Object): AiOverviewResult {
  const r = new AiOverviewResult();
  const map = d as Obj;
  const facesRaw = map['faces'];
  if (facesRaw !== undefined && facesRaw !== null && typeof facesRaw === 'object') {
    r.faces = parseAiFaceListResult(facesRaw);
  }
  const scenesRaw = map['scenes'];
  if (scenesRaw !== undefined && scenesRaw !== null && typeof scenesRaw === 'object') {
    r.scenes = parseAiSceneListResult(scenesRaw);
  }
  r.similarEnable = parseEnable(map['similarEnable'] ?? map['similar_enable'] ?? map['similar']);
  return r;
}

/**
 * AI 概览 API 服务（对齐 Flutter AppPhotoAiApiService）
 */
export class PhotoAiOverviewApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** 获取 AI 概览（人脸/场景预览 + 去重开关，对齐 Flutter fetchOverview） */
  async fetchOverview(limit: number = 20): Promise<APIResponse<AiOverviewResult>> {
    const body: Record<string, Object> = { 'limit': limit <= 0 ? 20 : limit };
    return this.api().apiPost<AiOverviewResult>('/api/photo/app_ai/overview', body,
      undefined, undefined, undefined, parseAiOverviewResult);
  }
}
