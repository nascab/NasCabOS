import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { APIClient } from '../../../core/network/APIClient';
import { AppEventBus } from '../../../common/AppEventBus';
import { L10n } from '../../../core/localization/L10n';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NotesNotebookInfo, NotesGroup, NotesNote, bStr } from '../models/NotesModels';

const TAG = 'NotesApi';

/**
 * 笔记模块通用结果（对齐 Flutter ApiResponse 用法）。
 */
export class NotesApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;
  /** 业务码（409 保存冲突等） */
  code: number = 0;

  static ok<D>(data: D | undefined, message: string = '', code: number = 0): NotesApiResult<D> {
    const r = new NotesApiResult<D>();
    r.success = true;
    r.data = data;
    r.message = message;
    r.code = code;
    return r;
  }

  static fail<D>(message: string, code: number = 0): NotesApiResult<D> {
    const r = new NotesApiResult<D>();
    r.success = false;
    r.message = message;
    r.code = code;
    return r;
  }
}

export interface NotesStatePayload {
  notebook: NotesNotebookInfo | undefined;
  groups: NotesGroup[];
  notes: NotesNote[];
}

export interface NotesNoteDetailPayload {
  note: NotesNote;
  /** Quill Delta ops 数组（JSON 值） */
  delta: Object[] | undefined;
  revision: number;
}

class NotesApiBase {
  /** POST JSON 并解析响应 data 字段；失败/未登录返回 fail（对齐 BookApiBase.post） */
  public static async post(endpoint: string, body: Record<string, Object> | undefined,
    showLoading: boolean = false): Promise<NotesApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return NotesApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiPost<Object>(endpoint, body as Object);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        return NotesApiResult.fail<Object>(msg.length > 0 ? msg : L10n.operationFailed, res.code);
      }
      return NotesApiResult.ok<Object>(res.data, '', res.code);
    } catch (e) {
      return NotesApiResult.fail<Object>(L10n.networkFailure);
    }
  }

  static accessToken(): string {
    return (APIClient.getInstance().accessToken ?? '').trim();
  }

  static baseUrl(): string {
    return APIClient.getInstance().baseUrl;
  }

  static asRecord(v: Object | undefined | null): Record<string, Object> {
    if (v === undefined || v === null) {
      return {} as Record<string, Object>;
    }
    return v as Record<string, Object>;
  }

  static asArray(v: Object | undefined | null): Object[] {
    if (v === undefined || v === null || !Array.isArray(v)) {
      return [];
    }
    return v as Object[];
  }
}

/**
 * 笔记 API 服务（对齐 Flutter NotesApiService；直连服务器，P2P 通道未迁移）。
 */
export class NotesApiService {
  private static readonly modulePath = '/api/notes';

  static async getNotebookStatus(): Promise<NotesApiResult<NotesNotebookInfo>> {
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/notebook/status`, undefined);
    if (!res.success) {
      return NotesApiResult.fail<NotesNotebookInfo>(res.message);
    }
    return NotesApiResult.ok<NotesNotebookInfo>(
      NotesNotebookInfo.fromJson(NotesApiBase.asRecord(res.data)));
  }

  static async selectNotebook(folderPath: string): Promise<NotesApiResult<NotesNotebookInfo>> {
    const body: Record<string, Object> = { 'folderPath': folderPath };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/notebook/select`, body);
    if (!res.success) {
      return NotesApiResult.fail<NotesNotebookInfo>(res.message);
    }
    const rec = NotesApiBase.asRecord(res.data);
    return NotesApiResult.ok<NotesNotebookInfo>(
      NotesNotebookInfo.fromJson(NotesApiBase.asRecord(rec['notebook'])));
  }

  static async getState(groupId: string, keyword: string,
    includeDeleted: boolean): Promise<NotesApiResult<NotesStatePayload>> {
    const body: Record<string, Object> = {
      'groupId': groupId,
      'keyword': keyword,
      'includeDeleted': includeDeleted
    };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/state`, body);
    if (!res.success) {
      return NotesApiResult.fail<NotesStatePayload>(res.message);
    }
    const rec = NotesApiBase.asRecord(res.data);
    const groups: NotesGroup[] = [];
    NotesApiBase.asArray(rec['groups']).forEach((item: Object): void => {
      groups.push(NotesGroup.fromJson(NotesApiBase.asRecord(item)));
    });
    const notes: NotesNote[] = [];
    NotesApiBase.asArray(rec['notes']).forEach((item: Object): void => {
      notes.push(NotesNote.fromJson(NotesApiBase.asRecord(item)));
    });
    const payload: NotesStatePayload = {
      notebook: NotesNotebookInfo.fromJson(NotesApiBase.asRecord(rec['notebook'])),
      groups: groups,
      notes: notes
    };
    return NotesApiResult.ok<NotesStatePayload>(payload);
  }

  static async createGroup(name: string): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = { 'name': name };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/group/create`, body);
    return res;
  }

  static async updateGroup(groupId: string, name: string): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = { 'groupId': groupId, 'name': name };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/group/update`, body);
    return res;
  }

  static async deleteGroup(groupId: string): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = { 'groupId': groupId };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/group/delete`, body);
    return res;
  }

  static async reorderGroups(orderedGroupIds: string[]): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = { 'orderedGroupIds': orderedGroupIds as Object };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/group/reorder`, body);
    return res;
  }

  static async createNote(groupId: string): Promise<NotesApiResult<NotesNote>> {
    const body: Record<string, Object> = { 'groupId': groupId, 'title': '' };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/create`, body);
    if (!res.success) {
      return NotesApiResult.fail<NotesNote>(res.message);
    }
    const rec = NotesApiBase.asRecord(res.data);
    return NotesApiResult.ok<NotesNote>(NotesNote.fromJson(NotesApiBase.asRecord(rec['note'])));
  }

  static async getNoteDetail(noteId: string): Promise<NotesApiResult<NotesNoteDetailPayload>> {
    const body: Record<string, Object> = { 'noteId': noteId };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/detail`, body);
    if (!res.success) {
      return NotesApiResult.fail<NotesNoteDetailPayload>(res.message);
    }
    const rec = NotesApiBase.asRecord(res.data);
    const payload: NotesNoteDetailPayload = {
      note: NotesNote.fromJson(NotesApiBase.asRecord(rec['note'])),
      delta: NotesApiBase.asArray(rec['delta']),
      revision: Number(rec['revision'] ?? 0)
    };
    return NotesApiResult.ok<NotesNoteDetailPayload>(payload);
  }

  static async saveNote(noteId: string, title: string, baseRevision: number,
    deltaPatch: Object[] | undefined): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = {
      'noteId': noteId,
      'title': title,
      'baseRevision': baseRevision
    };
    if (deltaPatch !== undefined) {
      body['deltaPatch'] = deltaPatch as Object;
    }
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/save`, body);
    return res;
  }

  static async updateNoteMeta(noteIds: string[], title: string | undefined,
    tagColor: string | undefined, isPinned: boolean | undefined): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = { 'noteIds': noteIds as Object };
    if (title !== undefined) {
      body['title'] = title;
    }
    if (tagColor !== undefined) {
      body['tagColor'] = tagColor;
    }
    if (isPinned !== undefined) {
      body['isPinned'] = isPinned;
    }
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/meta`, body);
    return res;
  }

  static async moveNote(noteId: string, targetGroupId: string): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = { 'noteId': noteId, 'targetGroupId': targetGroupId };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/move`, body);
    return res;
  }

  static async batchMoveNotes(noteIds: string[],
    targetGroupId: string): Promise<NotesApiResult<number>> {
    const body: Record<string, Object> = {
      'noteIds': noteIds as Object,
      'targetGroupId': targetGroupId
    };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/batchMove`, body);
    if (!res.success) {
      return NotesApiResult.fail<number>(res.message, res.code);
    }
    const rec = NotesApiBase.asRecord(res.data);
    return NotesApiResult.ok<number>(Number(rec['movedCount'] ?? 0));
  }

  static async deleteNote(noteId: string): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = { 'noteId': noteId };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/delete`, body);
    return res;
  }

  static async batchDeleteNotes(noteIds: string[]): Promise<NotesApiResult<number>> {
    const body: Record<string, Object> = { 'noteIds': noteIds as Object };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/batchDelete`, body);
    if (!res.success) {
      return NotesApiResult.fail<number>(res.message, res.code);
    }
    const rec = NotesApiBase.asRecord(res.data);
    return NotesApiResult.ok<number>(Number(rec['deletedCount'] ?? 0));
  }

  static async restoreNote(noteId: string): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = { 'noteId': noteId };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/restore`, body);
    return res;
  }

  static async batchRestoreNotes(noteIds: string[]): Promise<NotesApiResult<number>> {
    const body: Record<string, Object> = { 'noteIds': noteIds as Object };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/batchRestore`, body);
    if (!res.success) {
      return NotesApiResult.fail<number>(res.message, res.code);
    }
    const rec = NotesApiBase.asRecord(res.data);
    return NotesApiResult.ok<number>(Number(rec['restoredCount'] ?? 0));
  }

  static async permanentlyDeleteNote(noteId: string): Promise<NotesApiResult<Object>> {
    const body: Record<string, Object> = { 'noteId': noteId };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/permanentDelete`, body);
    return res;
  }

  static async batchPermanentlyDeleteNotes(noteIds: string[]): Promise<NotesApiResult<number>> {
    const body: Record<string, Object> = { 'noteIds': noteIds as Object };
    const res = await NotesApiBase.post(`${NotesApiService.modulePath}/note/batchPermanentDelete`, body);
    if (!res.success) {
      return NotesApiResult.fail<number>(res.message, res.code);
    }
    const rec = NotesApiBase.asRecord(res.data);
    return NotesApiResult.ok<number>(Number(rec['deletedCount'] ?? 0));
  }

  /** 笔记资源 URL（对齐 Flutter buildAssetUrl：baseUrl + path + accessToken） */
  static buildAssetUrl(noteId: string, assetName: string): string {
    const token = NotesApiBase.accessToken();
    let url = `${NotesApiBase.baseUrl()}${NotesApiService.modulePath}/note/asset`
      + `?noteId=${encodeURIComponent(noteId)}&name=${encodeURIComponent(assetName)}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }

  /** 笔记导出 URL（对齐 Flutter buildExportUrl；服务器端渲染 pdf/markdown/txt） */
  static buildExportUrl(noteId: string, format: string): string {
    const lower = format.trim().toLowerCase();
    const ext = lower === 'markdown' ? 'md' : lower;
    const token = NotesApiBase.accessToken();
    let url = `${NotesApiBase.baseUrl()}${NotesApiService.modulePath}/note/export`
      + `?noteId=${encodeURIComponent(noteId)}&format=${encodeURIComponent(lower)}`
      + `&fileName=${encodeURIComponent(`note.${ext}`)}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }

  /** 编辑器内嵌资源展开：assets/<name> → 完整服务器 URL（对齐 Flutter expandEmbedForEditor） */
  static expandEmbedForEditor(noteId: string, value: string): string {
    const trimmed = value.trim();
    if (!trimmed.startsWith('assets/')) {
      return trimmed;
    }
    return NotesApiService.buildAssetUrl(noteId, trimmed.replace('assets/', ''));
  }

  /** 保存前资源收敛：带本笔记 noteId+name 的 URL → assets/<name>（对齐 Flutter normalizeEmbedForSave） */
  static normalizeEmbedForSave(noteId: string, value: string): string {
    const trimmed = value.trim();
    if (trimmed.startsWith('assets/')) {
      return trimmed;
    }
    const q = trimmed.indexOf('?');
    if (q < 0) {
      return trimmed;
    }
    const query = trimmed.substring(q + 1);
    const parts = query.split('&');
    let assetName = '';
    let requestNoteId = '';
    parts.forEach((p: string): void => {
      const eq = p.indexOf('=');
      if (eq < 0) {
        return;
      }
      const key = p.substring(0, eq).trim();
      const val = decodeURIComponent(p.substring(eq + 1).trim());
      if (key === 'name') {
        assetName = val;
      } else if (key === 'noteId') {
        requestNoteId = val;
      }
    });
    if (assetName.length > 0 && requestNoteId === noteId) {
      return `assets/${assetName}`;
    }
    return trimmed;
  }

  /**
   * 上传笔记图片资源（multipart/form-data，对齐 Flutter uploadAsset）。
   * 返回资源完整 URL；失败抛出错误信息（调用方 Toast）。
   */
  static async uploadAsset(noteId: string, localUri: string): Promise<string> {
    const filename = localUri.substring(localUri.lastIndexOf('/') + 1) || 'asset.bin';
    const boundary = `nascab-notes-${Date.now()}`;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(localUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      const fileBytes = new Uint8Array(buf);

      const notePart = `--${boundary}\r\n`
        + `Content-Disposition: form-data; name="noteId"\r\n\r\n${noteId}\r\n`;
      const filePart = `--${boundary}\r\n`
        + `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n`
        + `Content-Type: application/octet-stream\r\n\r\n`;
      const end = `\r\n--${boundary}--\r\n`;

      const encoder = new util.TextEncoder();
      const headBytes: Uint8Array = encoder.encode(notePart + filePart);
      const tailBytes: Uint8Array = encoder.encode(end);

      const total: number = headBytes.length + fileBytes.length + tailBytes.length;
      const bodyBuf = new ArrayBuffer(total);
      const bodyView = new Uint8Array(bodyBuf);
      bodyView.set(headBytes, 0);
      bodyView.set(fileBytes, headBytes.length);
      bodyView.set(tailBytes, headBytes.length + fileBytes.length);

      const header: Record<string, string> = {
        'Content-Type': `multipart/form-data; boundary=${boundary}`
      };
      const token = NotesApiBase.accessToken();
      if (token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      const client = http.createHttp();
      try {
        const resp = await client.request(
          `${NotesApiBase.baseUrl()}${NotesApiService.modulePath}/note/uploadAsset`, {
          method: http.RequestMethod.POST,
          header: header,
          extraData: bodyBuf,
          connectTimeout: 15000,
          readTimeout: 120000,
          maxLimit: 100 * 1024 * 1024
        });
        const ok = resp.responseCode >= 200 && resp.responseCode < 300;
        if (!ok) {
          throw new Error(L10n.operationFailed);
        }
        const json = JSON.parse(resp.result as string) as Record<string, Object>;
        const success = json['success'] === true || json['success'] === 'true';
        if (!success) {
          const msg = bStr(json['message']);
          throw new Error(msg.length > 0 ? msg : L10n.operationFailed);
        }
        const data = NotesApiBase.asRecord(json['data']);
        const assetName = bStr(data['assetName']);
        if (assetName.length === 0) {
          throw new Error(L10n.operationFailed);
        }
        return NotesApiService.buildAssetUrl(noteId, assetName);
      } finally {
        client.destroy();
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${JSON.stringify(e)}`;
      hilog.error(0x0000, TAG, 'uploadAsset failed: %{public}s', msg);
      throw new Error(msg.length > 0 ? msg : L10n.operationFailed);
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }
}
