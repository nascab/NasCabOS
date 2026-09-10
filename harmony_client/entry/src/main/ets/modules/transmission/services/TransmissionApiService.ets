import { APIClient } from '../../../core/network/APIClient';

/**
 * Transmission 模块 API 服务（对齐 Flutter modules/transmission/service/transmission_api_service.dart）。
 * 请求路径、方法、参数与超时完全一致；均走 Nascab 服务端代理 RPC（/api/transmission/*）。
 */
export class TransmissionApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;
  code: number = 0;

  static ok<D>(data: D | undefined, message: string = '', code: number = 0): TransmissionApiResult<D> {
    const r = new TransmissionApiResult<D>();
    r.success = true;
    r.data = data;
    r.message = message;
    r.code = code;
    return r;
  }

  static fail<D>(message: string, code: number = 0): TransmissionApiResult<D> {
    const r = new TransmissionApiResult<D>();
    r.success = false;
    r.message = message;
    r.code = code;
    return r;
  }
}

function asRecord(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null || typeof v !== 'object' || Array.isArray(v)) {
    return {} as Record<string, Object>;
  }
  return v as Record<string, Object>;
}

export class TransmissionApiService {
  /** GET 并解析 data 为 Record */
  static async getRecord(endpoint: string, query?: Map<string, string>,
    timeoutMs?: number): Promise<TransmissionApiResult<Record<string, Object>>> {
    const res = await APIClient.getInstance().apiGet<Object>(endpoint, query, timeoutMs);
    if (!res.success) {
      return TransmissionApiResult.fail<Record<string, Object>>(res.message ?? '', res.code ?? 0);
    }
    return TransmissionApiResult.ok<Record<string, Object>>(asRecord(res.data));
  }

  /** POST 并解析 data 为 Record */
  static async postRecord(endpoint: string, body?: Object,
    timeoutMs?: number): Promise<TransmissionApiResult<Record<string, Object>>> {
    const res = await APIClient.getInstance().apiPost<Object>(endpoint, body, undefined, timeoutMs);
    if (!res.success) {
      return TransmissionApiResult.fail<Record<string, Object>>(res.message ?? '', res.code ?? 0);
    }
    return TransmissionApiResult.ok<Record<string, Object>>(asRecord(res.data));
  }

  /** 服务状态（GET /api/transmission/status） */
  static getStatus(): Promise<TransmissionApiResult<Record<string, Object>>> {
    return TransmissionApiService.getRecord('/api/transmission/status');
  }

  /** 服务配置（GET /api/transmission/config） */
  static getConfig(): Promise<TransmissionApiResult<Record<string, Object>>> {
    return TransmissionApiService.getRecord('/api/transmission/config');
  }

  /** 保存配置（POST /api/transmission/config/save，超时 20s） */
  static saveConfig(body: Object): Promise<TransmissionApiResult<Record<string, Object>>> {
    return TransmissionApiService.postRecord('/api/transmission/config/save', body, 20000);
  }

  /** 设置 RPC 端口（POST /api/transmission/config/ports） */
  static setRpcPort(port: number): Promise<TransmissionApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'rpc_port': port };
    return TransmissionApiService.postRecord('/api/transmission/config/ports', body);
  }

  /** 启动服务（POST /api/transmission/start，超时 30s） */
  static startService(): Promise<TransmissionApiResult<Record<string, Object>>> {
    return TransmissionApiService.postRecord('/api/transmission/start', {} as Record<string, Object>, 30000);
  }

  /** 停止服务（POST /api/transmission/stop，超时 20s） */
  static stopService(): Promise<TransmissionApiResult<Record<string, Object>>> {
    return TransmissionApiService.postRecord('/api/transmission/stop', {} as Record<string, Object>, 20000);
  }

  /** 重启服务（POST /api/transmission/restart，超时 30s） */
  static restartService(): Promise<TransmissionApiResult<Record<string, Object>>> {
    return TransmissionApiService.postRecord('/api/transmission/restart', {} as Record<string, Object>, 30000);
  }

  /** RPC 会话与统计（GET /api/transmission/session，data: {session, stats}） */
  static getSession(): Promise<TransmissionApiResult<Record<string, Object>>> {
    return TransmissionApiService.getRecord('/api/transmission/session');
  }

  /** 任务列表（GET /api/transmission/torrents/list?ids=&fields=） */
  static listTorrents(ids: number[],
    fields: string[]): Promise<TransmissionApiResult<Record<string, Object>>> {
    const query = new Map<string, string>();
    if (ids.length > 0) {
      query.set('ids', ids.join(','));
    }
    if (fields.length > 0) {
      query.set('fields', fields.join(','));
    }
    return TransmissionApiService.getRecord('/api/transmission/torrents/list', query);
  }

  /**
   * 添加任务（POST /api/transmission/torrents/add）：
   * url / metainfo（.torrent base64）/ filename（服务器种子文件路径）三选一，
   * 非空才会加入请求体（与 Flutter 条件字段一致）。
   */
  static addTorrent(url: string, metainfo: string, filename: string,
    downloadDir: string, paused: boolean): Promise<TransmissionApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'paused': paused };
    if (url.trim().length > 0) {
      body['url'] = url.trim();
    }
    if (metainfo.length > 0) {
      body['metainfo'] = metainfo;
    }
    if (filename.trim().length > 0) {
      body['filename'] = filename.trim();
    }
    if (downloadDir.trim().length > 0) {
      body['download_dir'] = downloadDir.trim();
    }
    return TransmissionApiService.postRecord('/api/transmission/torrents/add', body);
  }

  /** 更改任务保存目录（POST /api/transmission/torrents/set-location） */
  static setTorrentLocation(ids: number[], location: string,
    move: boolean = true): Promise<TransmissionApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'ids': ids as Object,
      'location': location,
      'move': move
    };
    return TransmissionApiService.postRecord('/api/transmission/torrents/set-location', body);
  }

  /** 开始任务（POST /api/transmission/torrents/start） */
  static startTorrents(ids: number[]): Promise<TransmissionApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'ids': ids as Object };
    return TransmissionApiService.postRecord('/api/transmission/torrents/start', body);
  }

  /** 暂停任务（POST /api/transmission/torrents/stop） */
  static stopTorrents(ids: number[]): Promise<TransmissionApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'ids': ids as Object };
    return TransmissionApiService.postRecord('/api/transmission/torrents/stop', body);
  }

  /** 删除任务（POST /api/transmission/torrents/remove） */
  static removeTorrents(ids: number[],
    deleteLocalData: boolean = false): Promise<TransmissionApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'ids': ids as Object,
      'deleteLocalData': deleteLocalData
    };
    return TransmissionApiService.postRecord('/api/transmission/torrents/remove', body);
  }

  /** 任务文件列表（GET /api/transmission/torrents/files?id=） */
  static getTorrentFiles(id: number): Promise<TransmissionApiResult<Record<string, Object>>> {
    const query = new Map<string, string>();
    query.set('id', `${id}`);
    return TransmissionApiService.getRecord('/api/transmission/torrents/files', query);
  }

  /** 设置任务文件选中项（POST /api/transmission/torrents/files/set） */
  static setTorrentFiles(id: number, filesWanted: number[],
    filesUnwanted: number[]): Promise<TransmissionApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'id': id };
    if (filesWanted.length > 0) {
      body['files_wanted'] = filesWanted as Object;
    }
    if (filesUnwanted.length > 0) {
      body['files_unwanted'] = filesUnwanted as Object;
    }
    return TransmissionApiService.postRecord('/api/transmission/torrents/files/set', body);
  }

  /** 服务器目录是否可写（GET /api/file/fs-access，对齐 Flutter FileApiService.isServerDirWritable） */
  static async isServerDirWritable(dir: string): Promise<boolean> {
    const path = dir.trim();
    if (path.length === 0) {
      return false;
    }
    const query = new Map<string, string>();
    query.set('path', path);
    const res = await TransmissionApiService.getRecord('/api/file/fs-access', query, 15000);
    if (!res.success) {
      return false;
    }
    const d = res.data as Record<string, Object>;
    return d['exists'] === true && d['isDirectory'] === true && d['canWrite'] === true;
  }
}
