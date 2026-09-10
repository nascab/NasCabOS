import { APIClient } from '../../../core/network/APIClient';
import { AppEventBus } from '../../../common/AppEventBus';
import { L10n } from '../../../core/localization/L10n';
import {
  bStr, PortsSaveErrorInfo, QuickShareItem, ServerPorts, ShareServerConfigRecord,
  ShareRootPath, ShareUserOption, UserShareFolderItem
} from '../models/ShareServerModels';

const TAG = 'ShareServerApi';

/**
 * 分享管理模块通用结果（对齐 Flutter ApiResponse 用法）。
 * raw 保留失败响应的 data 字段（端口设置失败时读取 details 结构化错误）。
 */
export class ShareApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;
  code: number = 0;
  /** 失败响应的原始 data（结构化错误 details），成功时为 undefined */
  raw: Record<string, Object> | undefined = undefined;

  static ok<D>(data: D | undefined, message: string = '', code: number = 0): ShareApiResult<D> {
    const r = new ShareApiResult<D>();
    r.success = true;
    r.data = data;
    r.message = message;
    r.code = code;
    return r;
  }

  static fail<D>(message: string, code: number = 0,
    raw: Record<string, Object> | undefined = undefined): ShareApiResult<D> {
    const r = new ShareApiResult<D>();
    r.success = false;
    r.message = message;
    r.code = code;
    r.raw = raw;
    return r;
  }
}

class ShareApiBase {
  /** POST JSON 并解析响应 data 字段；失败/未登录返回 fail（对齐 NotesApiBase.post） */
  public static async post(endpoint: string, body: Record<string, Object> | undefined,
    showLoading: boolean = false): Promise<ShareApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return ShareApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiPost<Object>(endpoint, body as Object);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        const raw = res.rawResponse?.data === undefined
          ? undefined : (res.rawResponse.data as Record<string, Object>);
        return ShareApiResult.fail<Object>(msg.length > 0 ? msg : L10n.operationFailed, res.code, raw);
      }
      return ShareApiResult.ok<Object>(res.data, '', res.code);
    } catch (e) {
      return ShareApiResult.fail<Object>(L10n.networkFailure);
    }
  }

  public static async get(endpoint: string): Promise<ShareApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return ShareApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiGet<Object>(endpoint);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        const raw = res.rawResponse?.data === undefined
          ? undefined : (res.rawResponse.data as Record<string, Object>);
        return ShareApiResult.fail<Object>(msg.length > 0 ? msg : L10n.operationFailed, res.code, raw);
      }
      return ShareApiResult.ok<Object>(res.data, '', res.code);
    } catch (e) {
      return ShareApiResult.fail<Object>(L10n.networkFailure);
    }
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
 * 文件服务（WebDav/FTP/SFTP）API（对齐 Flutter FileShareServerApiService；路径与参数完全一致）。
 */
export class FileShareServerApiService {
  /** 配置列表 */
  static async list(serverType: string): Promise<ShareApiResult<ShareServerConfigRecord[]>> {
    const body: Record<string, Object> = { 'server_type': serverType };
    const res = await ShareApiBase.post('/api/fileServer/list', body);
    if (!res.success) {
      return ShareApiResult.fail<ShareServerConfigRecord[]>(res.message, res.code);
    }
    const configs: ShareServerConfigRecord[] = [];
    ShareApiBase.asArray(res.data).forEach((item: Object): void => {
      configs.push(ShareServerConfigRecord.fromJson(ShareApiBase.asRecord(item)));
    });
    return ShareApiResult.ok<ShareServerConfigRecord[]>(configs);
  }

  /** 新建/更新配置（uid 按字符串传，对齐 Flutter uid.toString()） */
  static async upsert(uid: number, serverType: string,
    rootPath: ShareRootPath[]): Promise<ShareApiResult<Object>> {
    const rows: Record<string, Object>[] = [];
    rootPath.forEach((row: ShareRootPath): void => {
      rows.push(row.toRecord());
    });
    const body: Record<string, Object> = {
      'uid': `${uid}`,
      'server_type': serverType,
      'root_path': rows as Object,
      'config': {} as Record<string, Object>
    };
    return await ShareApiBase.post('/api/fileServer/upsert', body);
  }

  static async delete(uid: number, serverType: string): Promise<ShareApiResult<Object>> {
    const body: Record<string, Object> = { 'uid': `${uid}`, 'server_type': serverType };
    return await ShareApiBase.post('/api/fileServer/delete', body);
  }

  static async start(serverType: string): Promise<ShareApiResult<Object>> {
    const body: Record<string, Object> = { 'server_type': serverType };
    return await ShareApiBase.post('/api/fileServer/start', body);
  }

  static async stop(serverType: string): Promise<ShareApiResult<Object>> {
    const body: Record<string, Object> = { 'server_type': serverType };
    return await ShareApiBase.post('/api/fileServer/stop', body);
  }

  static async getPorts(serverType: string): Promise<ShareApiResult<ServerPorts>> {
    const body: Record<string, Object> = { 'server_type': serverType };
    const res = await ShareApiBase.post('/api/fileServer/ports/get', body);
    if (!res.success) {
      return ShareApiResult.fail<ServerPorts>(res.message, res.code);
    }
    return ShareApiResult.ok<ServerPorts>(ServerPorts.fromRecord(res.data));
  }

  /**
   * 保存端口（httpPort/httpsPort 传 undefined 表示不设置该字段）。
   * 失败时 raw 携带 details（fields/suggestedRange），供 PortsSaveErrorInfo 解析。
   */
  static async setPorts(serverType: string, httpPort: number | undefined,
    httpsPort: number | undefined): Promise<ShareApiResult<Object>> {
    const body: Record<string, Object> = { 'server_type': serverType };
    if (httpPort !== undefined) {
      body['http_port'] = httpPort;
    }
    if (httpsPort !== undefined) {
      body['https_port'] = httpsPort;
    }
    return await ShareApiBase.post('/api/fileServer/ports/set', body);
  }
}

/**
 * 用户共享目录 API（对齐 Flutter UserShareFolderApiService）。
 */
export class UserShareFolderApiService {
  static async list(): Promise<ShareApiResult<UserShareFolderItem[]>> {
    const res = await ShareApiBase.get('/api/file/userShareFolder/list');
    if (!res.success) {
      return ShareApiResult.fail<UserShareFolderItem[]>(res.message, res.code);
    }
    const rec = ShareApiBase.asRecord(res.data);
    const items: UserShareFolderItem[] = [];
    ShareApiBase.asArray(rec['items']).forEach((item: Object): void => {
      items.push(UserShareFolderItem.fromJson(ShareApiBase.asRecord(item)));
    });
    return ShareApiResult.ok<UserShareFolderItem[]>(items);
  }

  static async add(path: string, name: string | undefined,
    allowDownload: boolean | undefined): Promise<ShareApiResult<Object>> {
    const body: Record<string, Object> = { 'path': path };
    if (name !== undefined && name.trim().length > 0) {
      body['name'] = name.trim();
    }
    if (allowDownload !== undefined) {
      body['allowDownload'] = allowDownload;
    }
    return await ShareApiBase.post('/api/file/userShareFolder/add', body);
  }

  static async remove(path: string): Promise<ShareApiResult<Object>> {
    const body: Record<string, Object> = { 'path': path };
    return await ShareApiBase.post('/api/file/userShareFolder/remove', body);
  }

  static async setAllowDownload(path: string,
    allowDownload: boolean): Promise<ShareApiResult<Object>> {
    const body: Record<string, Object> = { 'path': path, 'allowDownload': allowDownload };
    return await ShareApiBase.post('/api/file/userShareFolder/allowDownload', body);
  }
}

/** 快速分享列表载荷（items + pairCode，对齐 Flutter data['items']/data['pairCode']） */
export interface QuickShareListPayload {
  items: QuickShareItem[];
  pairCode: string;
}

/**
 * 快速分享 API（对齐 Flutter QuickShareApiService）。
 */
export class QuickShareApiService {
  static async list(): Promise<ShareApiResult<QuickShareListPayload>> {
    const res = await ShareApiBase.get('/api/quickShare/list');
    if (!res.success) {
      return ShareApiResult.fail<QuickShareListPayload>(res.message, res.code);
    }
    const rec = ShareApiBase.asRecord(res.data);
    const items: QuickShareItem[] = [];
    ShareApiBase.asArray(rec['items']).forEach((item: Object): void => {
      items.push(QuickShareItem.fromJson(ShareApiBase.asRecord(item)));
    });
    const payload: QuickShareListPayload = { items: items, pairCode: bStr(rec['pairCode']).trim() };
    return ShareApiResult.ok<QuickShareListPayload>(payload);
  }

  static async create(path: string, pwd: string, remark: string | undefined,
    durationValue: number | undefined, durationUnit: string | undefined,
    noLimit: boolean | undefined): Promise<ShareApiResult<Object>> {
    const body: Record<string, Object> = { 'path': path, 'pwd': pwd };
    if (remark !== undefined) {
      body['remark'] = remark;
    }
    if (durationValue !== undefined) {
      body['durationValue'] = durationValue;
    }
    if (durationUnit !== undefined) {
      body['durationUnit'] = durationUnit;
    }
    if (noLimit !== undefined) {
      body['noLimit'] = noLimit;
    }
    return await ShareApiBase.post('/api/quickShare/create', body);
  }

  static async delete(id: number): Promise<ShareApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return await ShareApiBase.post('/api/quickShare/delete', body);
  }

  static async cleanExpired(): Promise<ShareApiResult<Object>> {
    return await ShareApiBase.post('/api/quickShare/cleanExpired', undefined);
  }
}

/**
 * 用户列表 API（对齐 Flutter UserApiService.fetchUsers；仅取 id/username 展示字段）。
 */
export class ShareUserApiService {
  static async fetchUsers(limit: number, keyword: string): Promise<ShareApiResult<ShareUserOption[]>> {
    const body: Record<string, Object> = { 'page': 1, 'limit': limit, 'keyword': keyword };
    const res = await ShareApiBase.post('/api/user/list', body);
    if (!res.success) {
      return ShareApiResult.fail<ShareUserOption[]>(res.message, res.code);
    }
    const rec = ShareApiBase.asRecord(res.data);
    const users: ShareUserOption[] = [];
    ShareApiBase.asArray(rec['items']).forEach((item: Object): void => {
      users.push(ShareUserOption.fromJson(ShareApiBase.asRecord(item)));
    });
    return ShareApiResult.ok<ShareUserOption[]>(users);
  }
}
