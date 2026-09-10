import { APIClient } from '../../../core/network/APIClient';
import { APIResponse } from '../../../core/network/APIResponse';
import { AppEventBus } from '../../../common/AppEventBus';
import { L10n } from '../../../core/localization/L10n';

/**
 * 远程挂载模块通用结果（对齐 Flutter ApiResponse 用法）。
 * apiErrorKey 对齐 Flutter ApiResponse.apiErrorKey（服务端业务错误码，
 * 如 mountShare.PLUGIN_NOT_READY，供控制器做专属文案映射）。
 */
export class MountApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;
  apiErrorKey: string = '';

  static ok<D>(data: D | undefined, message: string = ''): MountApiResult<D> {
    const r = new MountApiResult<D>();
    r.success = true;
    r.data = data;
    r.message = message;
    return r;
  }

  static fail<D>(message: string, apiErrorKey: string = ''): MountApiResult<D> {
    const r = new MountApiResult<D>();
    r.success = false;
    r.message = message;
    r.apiErrorKey = apiErrorKey;
    return r;
  }
}

/** 服务端 JSON 结构对齐 Flutter BaseApiService（success/code/message/data 信封） */
export class MountApiBase {
  /** 业务错误码提取（对齐 Flutter rawBizCode → apiErrorKey） */
  private static errorKey(res: APIResponse<Object>): string {
    const raw = res.rawResponse;
    if (raw === undefined || raw.code === undefined || raw.code === null) {
      return '';
    }
    return `${raw.code}`;
  }

  private static toResult(res: APIResponse<Object>): MountApiResult<Object> {
    if (!res.success) {
      if (res.code === 401) {
        AppEventBus.emitAuthSessionExpired();
      }
      const msg = res.message !== undefined ? res.message : '';
      return MountApiResult.fail<Object>(msg.length > 0 ? msg : L10n.operationFailed,
        MountApiBase.errorKey(res));
    }
    return MountApiResult.ok<Object>(res.data);
  }

  static async post(endpoint: string, body: Record<string, Object>): Promise<MountApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return MountApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiPost<Object>(endpoint, body as Object);
      return MountApiBase.toResult(res);
    } catch (_e) {
      return MountApiResult.fail<Object>(L10n.networkFailure);
    }
  }

  static async get(endpoint: string): Promise<MountApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return MountApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiGet<Object>(endpoint);
      return MountApiBase.toResult(res);
    } catch (_e) {
      return MountApiResult.fail<Object>(L10n.networkFailure);
    }
  }

  static asArray(v: Object | undefined | null): Object[] {
    if (v === undefined || v === null || !Array.isArray(v)) {
      return [];
    }
    return v as Object[];
  }

  static asRecord(v: Object | undefined | null): Record<string, Object> {
    if (v === undefined || v === null || typeof v !== 'object' || Array.isArray(v)) {
      return {} as Record<string, Object>;
    }
    return v as Record<string, Object>;
  }
}

/** 网盘驱动条目（drivers 接口返回；driver/name 与 additional 为关键封面字段） */
export class OpenlistDriverInfo {
  /** 驱动标识（优先 driver 字段，其次 name，对齐 Flutter _pickDriverName） */
  name: string = '';
  docUrl: string = '';
  additional: Object | undefined = undefined;

  static from(v: Object): OpenlistDriverInfo {
    const info = new OpenlistDriverInfo();
    const rec = v as Record<string, Object>;
    const driver = rec['driver'] !== undefined ? `${rec['driver']}` : '';
    const name = rec['name'] !== undefined ? `${rec['name']}` : '';
    info.name = driver.length > 0 ? driver : name;
    const doc = rec['docUrl'] !== undefined ? `${rec['docUrl']}` : '';
    info.docUrl = doc.trim();
    info.additional = rec['additional'];
    return info;
  }
}

/**
 * 文件协议挂载 API（对齐 Flutter FileMountApiService，路径与参数完全一致）。
 */
export class FileMountApiService {
  static async list(uid: string = '', status: string = ''): Promise<MountApiResult<Object[]>> {
    const body: Record<string, Object> = {};
    if (uid.length > 0) {
      body['uid'] = uid;
    }
    if (status.length > 0) {
      body['status'] = status;
    }
    const res = await MountApiBase.post('/api/fileMount/list', body);
    if (!res.success) {
      return MountApiResult.fail<Object[]>(res.message, res.apiErrorKey);
    }
    return MountApiResult.ok<Object[]>(MountApiBase.asArray(res.data));
  }

  static upsert(id: number | undefined, name: string, mountPath: string, remote: string,
    config: Record<string, Object> | undefined): Promise<MountApiResult<Object>> {
    const body: Record<string, Object> = {};
    if (id !== undefined) {
      body['id'] = id;
    }
    body['name'] = name;
    body['mount_path'] = mountPath;
    body['remote'] = remote;
    if (config !== undefined) {
      body['config'] = config;
    }
    return MountApiBase.post('/api/fileMount/upsert', body);
  }

  static delete(id: number): Promise<MountApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return MountApiBase.post('/api/fileMount/delete', body);
  }

  static start(id: number): Promise<MountApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return MountApiBase.post('/api/fileMount/start', body);
  }

  static stop(id: number): Promise<MountApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return MountApiBase.post('/api/fileMount/stop', body);
  }

  static checkWinfsp(): Promise<MountApiResult<Object>> {
    return MountApiBase.post('/api/fileMount/checkWinfsp', {} as Record<string, Object>);
  }
}

/**
 * 网盘挂载 API（对齐 Flutter OpenlistMountApiService，路径与参数完全一致）。
 */
export class OpenlistMountApiService {
  static async list(uid: string = '', status: string = ''): Promise<MountApiResult<Object[]>> {
    const body: Record<string, Object> = {};
    if (uid.length > 0) {
      body['uid'] = uid;
    }
    if (status.length > 0) {
      body['status'] = status;
    }
    const res = await MountApiBase.post('/api/openlistMount/list', body);
    if (!res.success) {
      return MountApiResult.fail<Object[]>(res.message, res.apiErrorKey);
    }
    return MountApiResult.ok<Object[]>(MountApiBase.asArray(res.data));
  }

  static upsert(id: number | undefined, name: string, mountPath: string, driver: string,
    config: Record<string, Object> | undefined): Promise<MountApiResult<Object>> {
    const body: Record<string, Object> = {};
    if (id !== undefined) {
      body['id'] = id;
    }
    body['name'] = name;
    body['mount_path'] = mountPath;
    body['driver'] = driver;
    if (config !== undefined) {
      body['config'] = config;
    }
    return MountApiBase.post('/api/openlistMount/upsert', body);
  }

  static delete(id: number): Promise<MountApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return MountApiBase.post('/api/openlistMount/delete', body);
  }

  static start(id: number): Promise<MountApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return MountApiBase.post('/api/openlistMount/start', body);
  }

  static stop(id: number): Promise<MountApiResult<Object>> {
    const body: Record<string, Object> = { 'id': id };
    return MountApiBase.post('/api/openlistMount/stop', body);
  }

  static async drivers(): Promise<MountApiResult<OpenlistDriverInfo[]>> {
    const res = await MountApiBase.get('/api/openlistMount/drivers');
    if (!res.success) {
      return MountApiResult.fail<OpenlistDriverInfo[]>(res.message, res.apiErrorKey);
    }
    const list: OpenlistDriverInfo[] = [];
    MountApiBase.asArray(res.data).forEach((o: Object): void => {
      list.push(OpenlistDriverInfo.from(o));
    });
    return MountApiResult.ok<OpenlistDriverInfo[]>(list);
  }

  static oauthHelpUrl(): Promise<MountApiResult<Object>> {
    return MountApiBase.get('/api/openlistMount/oauthHelpUrl');
  }
}

/**
 * 挂载插件状态 API（对齐 Flutter MountPluginApiService）。
 */
export class MountPluginApiService {
  static getStatus(): Promise<MountApiResult<Object>> {
    return MountApiBase.post('/api/plugin/mountLibsStatus', {} as Record<string, Object>);
  }
}
