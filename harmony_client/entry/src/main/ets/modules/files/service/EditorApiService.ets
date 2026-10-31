import { APIClient } from '../../../core/network/APIClient';
import { APIResponse } from '../../../core/network/APIResponse';

/**
 * 文本编辑器 API 服务（对齐 Flutter editor_api_service.dart）：
 * - open：POST /api/editor/open，返回文本内容 / 修订号 / 用户字号配置 / 是否可写
 * - save：POST /api/editor/save，服务端直接写回文件
 */

export class EditorUserConfig {
  fontSize: number = 14;
}

export class EditorOpenResult {
  docId: string = '';
  path: string = '';
  text: string = '';
  rev: number = 0;
  size: number = 0;
  mtimeMs: number = 0;
  config: EditorUserConfig = new EditorUserConfig();
  canWrite: boolean = false;
}

function asStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

function asNum(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Number.isFinite(v) ? v : 0;
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? n : 0;
}

export class EditorApiService {
  private api(): APIClient {
    return APIClient.getInstance();
  }

  /** 打开（读取）文件内容（对齐 Flutter EditorApiService.open） */
  async open(path: string): Promise<APIResponse<EditorOpenResult>> {
    const body: Record<string, Object> = { 'path': path };
    return this.api().apiPost<EditorOpenResult>('/api/editor/open', body, undefined, undefined, undefined,
      (d: Object, _c: number): EditorOpenResult => {
        const map = d as Record<string, Object>;
        const r = new EditorOpenResult();
        r.docId = asStr(map['docId']);
        r.path = asStr(map['path']);
        r.text = asStr(map['text']);
        r.rev = asNum(map['rev']);
        r.size = asNum(map['size']);
        r.mtimeMs = asNum(map['mtimeMs']);
        r.canWrite = map['canWrite'] === true;
        const cfg = map['config'];
        if (cfg !== undefined && cfg !== null) {
          const fontSize = asNum((cfg as Record<string, Object>)['fontSize']);
          r.config.fontSize = fontSize > 0 ? fontSize : 14;
        }
        return r;
      });
  }

  /** 保存文件内容（对齐 Flutter EditorApiService.save） */
  async save(path: string, text: string): Promise<APIResponse<boolean>> {
    const body: Record<string, Object> = { 'path': path, 'text': text };
    return this.api().apiPost<boolean>('/api/editor/save', body,
      undefined, undefined, undefined,
      (d: Object, _c: number): boolean => {
        if (d === undefined || d === null) {
          return false;
        }
        return (d as Record<string, Object>)['ok'] === true;
      });
  }
}
