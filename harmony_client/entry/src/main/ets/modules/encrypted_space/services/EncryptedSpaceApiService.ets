import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { APIClient } from '../../../core/network/APIClient';
import { NetworkConfig } from '../../../core/network/NetworkConfig';
import { AppEventBus } from '../../../common/AppEventBus';
import { L10n } from '../../../core/localization/L10n';
import { HeaderMap } from '../../../common/HeaderMap';
import { P2pRtcChannel } from '../../../p2p/P2pProtocol';
import { P2PService } from '../../../p2p/P2PService';
import { UploadCancellationToken } from '../../../transfer/controllers/UploadCore';
import { UploadTransferHelper } from '../../../transfer/utils/UploadTransferHelper';
import { UriReader } from '../../../transfer/utils/UriReader';

const TAG = 'EncryptedSpaceApi';

/**
 * 加密空间模块通用结果（对齐 Flutter ApiResponse 用法）。
 */
export class EncryptedApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;

  static ok<D>(data: D | undefined): EncryptedApiResult<D> {
    const r = new EncryptedApiResult<D>();
    r.success = true;
    r.data = data;
    return r;
  }

  static fail<D>(message: string): EncryptedApiResult<D> {
    const r = new EncryptedApiResult<D>();
    r.success = false;
    r.message = message;
    return r;
  }
}

class EncryptedApiBase {
  /** POST JSON 并解析响应 data 字段；失败/未登录返回 fail（对齐 NotesApiBase.post；loading 由控制器层负责） */
  public static async post(endpoint: string, body: Record<string, Object>): Promise<EncryptedApiResult<Object>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return EncryptedApiResult.fail<Object>(L10n.networkFailure);
    }
    try {
      const res = await api.apiPost<Object>(endpoint, body as Object);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        return EncryptedApiResult.fail<Object>(msg.length > 0 ? msg : L10n.operationFailed);
      }
      return EncryptedApiResult.ok<Object>(res.data);
    } catch (e) {
      return EncryptedApiResult.fail<Object>(L10n.networkFailure);
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

/** 导出任务状态文案（对齐 exportTaskStatusLabel） */
export function encryptedExportTaskStatusLabel(raw: string): string {
  const s = raw.trim().toLowerCase();
  if (s === 'pending') {
    return L10n.t('waiting', '等待中');
  }
  if (s === 'running') {
    return L10n.t('processing', '处理中');
  }
  if (s === 'success') {
    return L10n.t('completed', '已完成');
  }
  if (s === 'error') {
    return L10n.t('failed', '失败');
  }
  return raw.trim().length > 0 ? raw.trim() : '-';
}

/**
 * 加密空间 API 服务（对齐 Flutter EncryptedSpaceApiService；路径与参数完全一致）。
 */
export class EncryptedSpaceApiService {
  static async list(): Promise<EncryptedApiResult<Object[]>> {
    const res = await EncryptedApiBase.post('/api/encryptedSpace/list', {} as Record<string, Object>);
    if (!res.success) {
      return EncryptedApiResult.fail<Object[]>(res.message);
    }
    return EncryptedApiResult.ok<Object[]>(EncryptedApiBase.asArray(res.data));
  }

  static async exportTaskList(): Promise<EncryptedApiResult<Object[]>> {
    const res = await EncryptedApiBase.post('/api/encryptedSpace/export/list',
      {} as Record<string, Object>);
    if (!res.success) {
      return EncryptedApiResult.fail<Object[]>(res.message);
    }
    return EncryptedApiResult.ok<Object[]>(EncryptedApiBase.asArray(res.data));
  }

  static async addSpace(folderPath: string, spaceName: string,
    spacePwd: string): Promise<EncryptedApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'folderPath': folderPath,
      'spaceName': spaceName,
      'spacePwd': spacePwd
    };
    const res = await EncryptedApiBase.post('/api/encryptedSpace/addSpace', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  static async importSpace(folderPath: string, spaceName: string,
    spacePwd: string): Promise<EncryptedApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'folderPath': folderPath,
      'spaceName': spaceName,
      'spacePwd': spacePwd
    };
    const res = await EncryptedApiBase.post('/api/encryptedSpace/importSpace', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  static async checkPwd(spaceId: number,
    spacePwd: string): Promise<EncryptedApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'spaceId': spaceId, 'spacePwd': spacePwd };
    const res = await EncryptedApiBase.post('/api/encryptedSpace/checkPwd', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  static async deleteToken(spaceId: number): Promise<EncryptedApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'spaceId': spaceId };
    const res = await EncryptedApiBase.post('/api/encryptedSpace/deleteToken', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  static async deleteSpace(spaceId: number): Promise<EncryptedApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'spaceId': spaceId };
    const res = await EncryptedApiBase.post('/api/encryptedSpace/deleteSpace', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  static async updateSpaceName(spaceId: number,
    spaceName: string): Promise<EncryptedApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'spaceId': spaceId, 'spaceName': spaceName };
    const res = await EncryptedApiBase.post('/api/encryptedSpace/updateSpaceName', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  static async getFileList(spaceId: number, token: string, count: number, offsetCount: number,
    orderField: string, orderType: string, fileType: string,
    keyword: string): Promise<EncryptedApiResult<Object[]>> {
    const body: Record<string, Object> = {
      'spaceId': spaceId,
      'token': token,
      'count': count,
      'offsetCount': offsetCount,
      'orderField': orderField,
      'orderType': orderType,
      'fileType': fileType
    };
    const kw = keyword.trim();
    if (kw.length > 0) {
      body['keyword'] = kw;
    }
    const res = await EncryptedApiBase.post('/api/encryptedSpace/getFileList', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Object[]>(res.message);
    }
    return EncryptedApiResult.ok<Object[]>(EncryptedApiBase.asArray(res.data));
  }

  static async deleteSpaceFiles(spaceId: number,
    ids: number[]): Promise<EncryptedApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'spaceId': spaceId, 'ids': ids as Object };
    const res = await EncryptedApiBase.post('/api/encryptedSpace/deleteSpaceFiles', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  static async addExportTask(spaceId: number, spacePwd: string,
    targetPath: string): Promise<EncryptedApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = {
      'spaceId': spaceId,
      'spacePwd': spacePwd,
      'targetPath': targetPath
    };
    const res = await EncryptedApiBase.post('/api/encryptedSpace/export/add', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  static async deleteExportTask(id: number): Promise<EncryptedApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'id': id };
    const res = await EncryptedApiBase.post('/api/encryptedSpace/export/delete', body);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  static async clearFinishedExportTasks(): Promise<EncryptedApiResult<Record<string, Object>>> {
    const res = await EncryptedApiBase.post('/api/encryptedSpace/export/clearFinished',
      {} as Record<string, Object>);
    if (!res.success) {
      return EncryptedApiResult.fail<Record<string, Object>>(res.message);
    }
    return EncryptedApiResult.ok<Record<string, Object>>(EncryptedApiBase.asRecord(res.data));
  }

  /**
   * 解密文件 URL（对齐 buildDecodeUrl）：
   * $baseUrl/api/encryptedSpace/getDecodeFile?spaceId=&indexId=&spaceToken=[&type=][&download=1][&fileName=][&accessToken=]
   */
  static buildDecodeUrl(spaceId: number, token: string, indexId: number, type: string = '',
    download: boolean = false, fileName: string = ''): string {
    const parts: string[] = [
      `spaceId=${spaceId}`,
      `indexId=${indexId}`,
      `spaceToken=${encodeURIComponent(token)}`
    ];
    const t = type.trim();
    if (t.length > 0) {
      parts.push(`type=${encodeURIComponent(t)}`);
    }
    if (download) {
      parts.push('download=1');
      const name = fileName.trim();
      if (name.length > 0) {
        parts.push(`fileName=${encodeURIComponent(name)}`);
      }
    }
    const accessToken = EncryptedApiBase.accessToken();
    if (accessToken.length > 0) {
      parts.push(`accessToken=${encodeURIComponent(accessToken)}`);
    }
    return `${EncryptedApiBase.baseUrl()}/api/encryptedSpace/getDecodeFile?${parts.join('&')}`;
  }

  /** 分块上传 URL（对齐 _buildChunkUploadUrl） */
  private static buildChunkUploadUrl(spaceId: number, token: string): string {
    const parts: string[] = [
      `spaceId=${spaceId}`,
      `spaceToken=${encodeURIComponent(token)}`
    ];
    const accessToken = EncryptedApiBase.accessToken();
    if (accessToken.length > 0) {
      parts.push(`accessToken=${encodeURIComponent(accessToken)}`);
    }
    return `${EncryptedApiBase.baseUrl()}/api/encryptedSpace/upload/chunk?${parts.join('&')}`;
  }

  /**
   * 分块上传单个本地文件（对齐 _uploadPath：5MB 分片，hash=uuid_chunkSize）。
   * 失败抛出携带服务端 message 的 Error；取消抛 'upload_cancelled'。
   */
  static async uploadFile(spaceId: number, token: string, localUri: string, fileName: string,
    onProgress: (sent: number, total: number) => void,
    cancelToken: UploadCancellationToken): Promise<void> {
    const api = APIClient.getInstance();
    const url = EncryptedSpaceApiService.buildChunkUploadUrl(spaceId, token);
    const size = UriReader.statSize(localUri);
    if (size <= 0) {
      throw new Error(L10n.operationFailed);
    }
    const maxChunkSize = 5 * 1024 * 1024;
    const chunkSize = size < maxChunkSize ? size : maxChunkSize;
    const totalChunks = Math.ceil(size / chunkSize);
    const sessionHash = `${util.generateRandomUUID(false)}_${chunkSize}`;

    for (let part = 0; part < totalChunks; part++) {
      if (cancelToken.isCancelled()) {
        throw new Error('upload_cancelled');
      }
      const start = part * chunkSize;
      const end = Math.min(start + chunkSize, size);
      const length = end - start;
      const chunkBytes = UriReader.readRange(localUri, start, length);
      if (cancelToken.isCancelled()) {
        throw new Error('upload_cancelled');
      }

      const fields: Array<[string, string]> = [
        ['hash', sessionHash],
        ['chunkSize', `${chunkSize}`],
        ['fileName', fileName],
        ['totalChunks', `${totalChunks}`],
        ['index', `${part}`]
      ];
      const boundary = `----nascabformdata${Date.now()}`;
      const body = UploadTransferHelper.buildMultipartBody(boundary, fields, 'file', 'chunk',
        chunkBytes);
      const header: Record<string, string> = {
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
        'Accept': 'application/json'
      };
      const accessToken = EncryptedApiBase.accessToken();
      if (accessToken.length > 0) {
        header['Authorization'] = `Bearer ${accessToken}`;
      }

      let statusCode = 0;
      let respText = '';
      if (api.isP2pMode) {
        const headers = new HeaderMap();
        if (accessToken.length > 0) {
          headers.set('Authorization', `Bearer ${accessToken}`);
        }
        headers.set('Content-Type', `multipart/form-data; boundary=${boundary}`);
        headers.set('Accept', 'application/json');
        const resp = await P2PService.getInstance().sendOnChannel(
          P2pRtcChannel.UPLOAD, 'POST', url, headers, body, 300000);
        statusCode = resp.status;
        const decoder = new util.TextDecoder();
        respText = decoder.decodeToString(resp.bodyBytes);
      } else {
        const req = http.createHttp();
        try {
          const resp = await req.request(url, {
            method: http.RequestMethod.POST,
            header: header,
            extraData: body.buffer as ArrayBuffer,
            connectTimeout: NetworkConfig.DEFAULT_TIMEOUT_MS,
            readTimeout: 600000,
            expectDataType: http.HttpDataType.STRING,
            usingProtocol: http.HttpProtocol.HTTP1_1,
            remoteValidation: 'skip'
          });
          statusCode = resp.responseCode;
          respText = `${resp.result}`;
        } finally {
          req.destroy();
        }
      }

      EncryptedSpaceApiService.ensureChunkSuccess(statusCode, respText);
      onProgress(end, size);
    }
  }

  /** 校验分块响应（对齐 _ensureSuccess：success===true 或 code===0） */
  private static ensureChunkSuccess(statusCode: number, respText: string): void {
    if (statusCode < 200 || statusCode >= 300) {
      throw new Error(EncryptedSpaceApiService.describeChunkError(statusCode, respText));
    }
    const text = respText.trim();
    if (text.length === 0) {
      return;
    }
    try {
      const decoded = JSON.parse(text) as Record<string, Object>;
      const ok = decoded['success'] === true || decoded['code'] === 0;
      if (ok) {
        return;
      }
      throw new Error(EncryptedSpaceApiService.describeChunkError(statusCode, respText));
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      if (msg.length > 0 && !msg.startsWith('Unexpected') && !msg.includes('JSON')) {
        throw e instanceof Error ? e : new Error(msg);
      }
      // 非 JSON 响应且 HTTP 2xx：视为成功（对齐 Flutter 校验宽松度）
    }
  }

  /** 从服务端错误提取可展示文案（优先接口 message，对齐 _serverMessage） */
  private static describeChunkError(statusCode: number, respText: string): string {
    const text = respText.trim();
    if (text.length > 0) {
      try {
        const decoded = JSON.parse(text) as Record<string, Object>;
        const msg = decoded['message'];
        if (msg !== undefined && msg !== null && `${msg}`.trim().length > 0) {
          return `${msg}`;
        }
      } catch (_e) {
        // 非 JSON：截断展示
      }
      const clipped = text.length > 240 ? text.substring(0, 240) : text;
      hilog.error(0x0000, TAG, 'chunk upload http %{public}d: %{public}s', statusCode, clipped);
      return statusCode >= 200 && statusCode < 300 ? clipped : `upload_chunk_http_${statusCode}`;
    }
    return `upload_chunk_http_${statusCode}`;
  }
}
