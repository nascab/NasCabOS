import { APIClient } from '../../../core/network/APIClient';
import { AppEventBus } from '../../../common/AppEventBus';
import { L10n } from '../../../core/localization/L10n';
import { BackupRecord, BackupRecordsPayload, BackupTask, parseIntOr } from '../models/FileBackupModels';

/**
 * 磁盘间备份 API 服务（对齐 Flutter FileBackupApiService）：
 * /api/fileBackup/list、/upsert、/delete、/start、/stop、/records/list。
 * 请求路径与参数和 Flutter 端完全一致。
 */
export class FileBackupApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;
  /** 业务码（401 会话过期等） */
  code: number = 0;

  static ok<D>(data: D | undefined, message: string = '', code: number = 0): FileBackupApiResult<D> {
    const r = new FileBackupApiResult<D>();
    r.success = true;
    r.data = data;
    r.message = message;
    r.code = code;
    return r;
  }

  static fail<D>(message: string, code: number = 0): FileBackupApiResult<D> {
    const r = new FileBackupApiResult<D>();
    r.success = false;
    r.message = message;
    r.code = code;
    return r;
  }
}

class FileBackupApiBase {
  /** POST JSON 并解析响应 data 字段；失败/未登录返回 fail（对齐 NotesApiBase.post） */
  public static async post(endpoint: string,
    body: Record<string, Object> | undefined): Promise<FileBackupApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return FileBackupApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiPost<Object>(endpoint, body as Object);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        return FileBackupApiResult.fail<Object>(msg.length > 0 ? msg : L10n.operationFailed, res.code);
      }
      return FileBackupApiResult.ok<Object>(res.data, '', res.code);
    } catch (_e) {
      return FileBackupApiResult.fail<Object>(L10n.networkFailure);
    }
  }

  static asRecord(v: Object | undefined | null): Record<string, Object> {
    if (v === undefined || v === null || Array.isArray(v)) {
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

export class FileBackupApiService {
  private static readonly listPath = '/api/fileBackup/list';
  private static readonly upsertPath = '/api/fileBackup/upsert';
  private static readonly deletePath = '/api/fileBackup/delete';
  private static readonly startPath = '/api/fileBackup/start';
  private static readonly stopPath = '/api/fileBackup/stop';
  private static readonly recordsPath = '/api/fileBackup/records/list';

  /** 任务列表（对齐 Flutter list(page: 1)，controller 仅使用 page=1） */
  static async listTasks(): Promise<FileBackupApiResult<BackupTask[]>> {
    const body: Record<string, Object> = { 'page': 1 };
    const res = await FileBackupApiBase.post(FileBackupApiService.listPath, body);
    if (!res.success) {
      return FileBackupApiResult.fail<BackupTask[]>(res.message, res.code);
    }
    const rec = FileBackupApiBase.asRecord(res.data);
    const items: BackupTask[] = [];
    FileBackupApiBase.asArray(rec['items']).forEach((item: Object): void => {
      items.push(BackupTask.fromJson(FileBackupApiBase.asRecord(item)));
    });
    return FileBackupApiResult.ok<BackupTask[]>(items);
  }

  /** 新增/编辑任务（对齐 Flutter upsert：id 可选，frenquence 为小时数） */
  static async upsertTask(id: number | undefined, sourcePathList: string[], type: string,
    targetPath: string, frenquence: number, excludeList: string[]): Promise<FileBackupApiResult<Object>> {
    const body: Record<string, Object> = {
      'source_path': sourcePathList,
      'type': type,
      'target_path': targetPath,
      'frenquence': frenquence,
      'exclude_list': excludeList
    };
    if (id !== undefined) {
      body['id'] = id;
    }
    const res = await FileBackupApiBase.post(FileBackupApiService.upsertPath, body);
    if (!res.success) {
      return FileBackupApiResult.fail<Object>(res.message, res.code);
    }
    return FileBackupApiResult.ok<Object>(res.data, '', res.code);
  }

  static async deleteTask(id: number): Promise<FileBackupApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    const res = await FileBackupApiBase.post(FileBackupApiService.deletePath, body);
    if (!res.success) {
      return FileBackupApiResult.fail<Object>(res.message, res.code);
    }
    return FileBackupApiResult.ok<Object>(res.data, '', res.code);
  }

  static async startTask(id: number): Promise<FileBackupApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    const res = await FileBackupApiBase.post(FileBackupApiService.startPath, body);
    if (!res.success) {
      return FileBackupApiResult.fail<Object>(res.message, res.code);
    }
    return FileBackupApiResult.ok<Object>(res.data, '', res.code);
  }

  static async stopTask(id: number): Promise<FileBackupApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    const res = await FileBackupApiBase.post(FileBackupApiService.stopPath, body);
    if (!res.success) {
      return FileBackupApiResult.fail<Object>(res.message, res.code);
    }
    return FileBackupApiResult.ok<Object>(res.data, '', res.code);
  }

  /** 备份记录（对齐 Flutter listRecords：body 为 {id, page, pageSize}） */
  static async listRecords(taskId: number, page: number,
    pageSize: number): Promise<FileBackupApiResult<BackupRecordsPayload>> {
    const body: Record<string, Object> = { 'id': taskId, 'page': page, 'pageSize': pageSize };
    const res = await FileBackupApiBase.post(FileBackupApiService.recordsPath, body);
    if (!res.success) {
      return FileBackupApiResult.fail<BackupRecordsPayload>(res.message, res.code);
    }
    const rec = FileBackupApiBase.asRecord(res.data);
    const payload = new BackupRecordsPayload();
    // 对齐 Flutter int.tryParse(...) ?? 300：字段缺失或非法时取 300
    const maxRaw = rec['max_kept_per_task'];
    payload.maxKept = maxRaw === undefined || maxRaw === null
      ? 300
      : parseIntOr(`${maxRaw}`, 300);
    payload.items = [];
    FileBackupApiBase.asArray(rec['items']).forEach((item: Object): void => {
      payload.items.push(BackupRecord.fromJson(FileBackupApiBase.asRecord(item)));
    });
    return FileBackupApiResult.ok<BackupRecordsPayload>(payload, '', res.code);
  }
}
