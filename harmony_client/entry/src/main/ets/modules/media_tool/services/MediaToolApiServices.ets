import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { APIClient } from '../../../core/network/APIClient';
import { AppEventBus } from '../../../common/AppEventBus';
import { L10n } from '../../../core/localization/L10n';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'MediaToolApi';

/**
 * 媒体工具模块通用结果（对齐 Flutter ApiResponse 用法）。
 */
export class MediaToolApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;
  code: number = 0;

  static ok<D>(data: D | undefined, message: string = '', code: number = 0): MediaToolApiResult<D> {
    const r = new MediaToolApiResult<D>();
    r.success = true;
    r.data = data;
    r.message = message;
    r.code = code;
    return r;
  }

  static fail<D>(message: string, code: number = 0): MediaToolApiResult<D> {
    const r = new MediaToolApiResult<D>();
    r.success = false;
    r.message = message;
    r.code = code;
    return r;
  }
}

/**
 * 批量任务 API 服务（对齐 Flutter ImgBatchCompressApiService / VideoTransApiService /
 * AudioTransApiService / MediaArrangeApiService：四套接口仅路径前缀不同，统一参数化）。
 */
export class MediaToolTaskApiService {
  private readonly basePath: string;

  constructor(basePath: string) {
    this.basePath = basePath;
  }

  private static async post(endpoint: string, body: Record<string, Object> | undefined,
    showLoading: boolean = false): Promise<MediaToolApiResult<Record<string, Object>>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return MediaToolApiResult.fail<Record<string, Object>>(L10n.networkFailure);
    }
    try {
      const res = await api.apiPost<Object>(endpoint, body as Object);
      if (!res.success) {
        if (res.code === 401) {
          AppEventBus.emitAuthSessionExpired();
        }
        const msg = res.message !== undefined ? res.message : '';
        return MediaToolApiResult.fail<Record<string, Object>>(
          msg.length > 0 ? msg : L10n.operationFailed, res.code ?? 0);
      }
      const data = res.data !== undefined ? res.data as Record<string, Object> : undefined;
      return MediaToolApiResult.ok<Record<string, Object>>(data, '', res.code ?? 0);
    } catch (_e) {
      return MediaToolApiResult.fail<Record<string, Object>>(L10n.networkFailure);
    }
  }

  async list(page: number = 1): Promise<MediaToolApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'page': page };
    return MediaToolTaskApiService.post(`${this.basePath}/list`, body);
  }

  async upsert(body: Record<string, Object>): Promise<MediaToolApiResult<Record<string, Object>>> {
    return MediaToolTaskApiService.post(`${this.basePath}/upsert`, body);
  }

  async remove(id: number): Promise<MediaToolApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'id': id };
    return MediaToolTaskApiService.post(`${this.basePath}/delete`, body);
  }

  async start(id: number): Promise<MediaToolApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'id': id };
    return MediaToolTaskApiService.post(`${this.basePath}/start`, body);
  }

  async stop(id: number): Promise<MediaToolApiResult<Record<string, Object>>> {
    const body: Record<string, Object> = { 'id': id };
    return MediaToolTaskApiService.post(`${this.basePath}/stop`, body);
  }
}

/** 图片压缩结果条目（对齐 Flutter ImageCompressItem） */
export class MediaToolImageCompressResult {
  fileName: string = '';
  inputSize: number = 0;
  outputSize: number = 0;
  outputFormat: string = '';
  outputFullPath: string = '';
  uploadStartTime: number = 0;
}

/**
 * 图片压缩转换 API 服务（对齐 Flutter ImageCompressApiService；
 * multipart/form-data 直传，P2P 通道未迁移与 notes 模块策略一致）。
 */
export class MediaToolImageCompressApiService {
  private static readonly uploadPath = '/api/mediaTool/imageCompress/upload';

  /** 按扩展名推断文件 Content-Type（对齐 Flutter contentType 推断） */
  private static contentTypeForName(fileName: string): string {
    const lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }

  /**
   * 上传并压缩单张图片（multipart/form-data，query 参数与 Flutter 完全一致）。
   * 失败返回 fail（message 为服务端信息或网络错误）。
   */
  static async uploadAndCompress(localUri: string, fileName: string,
    query: Map<string, string>): Promise<MediaToolApiResult<Record<string, Object>>> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return MediaToolApiResult.fail<Record<string, Object>>(L10n.networkFailure);
    }
    const boundary = `----nascab-${Date.now()}`;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(localUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      const fileBytes = new Uint8Array(buf);

      const head = `--${boundary}\r\n`
        + `Content-Disposition: form-data; name="file"; filename="${fileName}"\r\n`
        + `Content-Type: ${MediaToolImageCompressApiService.contentTypeForName(fileName)}\r\n\r\n`;
      const tail = `\r\n--${boundary}--\r\n`;
      const encoder = new util.TextEncoder();
      const headBytes: Uint8Array = encoder.encode(head);
      const tailBytes: Uint8Array = encoder.encode(tail);

      const total: number = headBytes.length + fileBytes.length + tailBytes.length;
      const bodyBuf = new ArrayBuffer(total);
      const bodyView = new Uint8Array(bodyBuf);
      bodyView.set(headBytes, 0);
      bodyView.set(fileBytes, headBytes.length);
      bodyView.set(tailBytes, headBytes.length + fileBytes.length);

      // query 参数拼接（fileName/uploadStartTime/withMeta/zipQuality/outSize/zipFormat）
      const parts: string[] = [];
      query.forEach((value: string, key: string): void => {
        parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
      });
      const url = `${api.baseUrl}${MediaToolImageCompressApiService.uploadPath}?${parts.join('&')}`;

      const header: Record<string, string> = {
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
        'accept': 'application/json'
      };
      const token = (api.accessToken ?? '').trim();
      if (token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      const client = http.createHttp();
      try {
        const resp = await client.request(url, {
          method: http.RequestMethod.POST,
          header: header,
          extraData: bodyBuf,
          connectTimeout: 30000,
          readTimeout: 300000,
          maxLimit: 100 * 1024 * 1024
        });
        if (resp.responseCode < 200 || resp.responseCode >= 300) {
          return MediaToolApiResult.fail<Record<string, Object>>(`HTTP ${resp.responseCode}`);
        }
        const json = JSON.parse(resp.result as string) as Record<string, Object>;
        const success = json['success'] === true || json['success'] === 'true';
        if (!success) {
          const msg = json['message'] !== undefined && json['message'] !== null
            ? `${json['message']}` : '';
          return MediaToolApiResult.fail<Record<string, Object>>(
            msg.length > 0 ? msg : L10n.t('server_error', '服务器错误'));
        }
        const data = json['data'] !== undefined && json['data'] !== null
          ? json['data'] as Record<string, Object>
          : {} as Record<string, Object>;
        return MediaToolApiResult.ok<Record<string, Object>>(data);
      } finally {
        client.destroy();
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${JSON.stringify(e)}`;
      hilog.error(0x0000, TAG, 'uploadAndCompress failed: %{public}s', msg);
      return MediaToolApiResult.fail<Record<string, Object>>(msg);
    } finally {
      if (file !== null) {
        fs.closeSync(file);
      }
    }
  }

  /** 单文件下载 URL（对齐 Flutter _buildDownloadUrl：query 含 accessToken） */
  static buildFileDownloadUrl(serverPath: string, fileName: string): string {
    const api = APIClient.getInstance();
    const token = (api.accessToken ?? '').trim();
    let url = `${api.baseUrl}/api/mediaTool/imageCompress/file`
      + `?path=${encodeURIComponent(serverPath)}&fileName=${encodeURIComponent(fileName)}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }

  /** 打包下载 URL（对齐 Flutter downloadZip 的 URL 组装） */
  static buildZipDownloadUrl(minTimeStamp: number, fileName: string): string {
    const api = APIClient.getInstance();
    const token = (api.accessToken ?? '').trim();
    let url = `${api.baseUrl}/api/mediaTool/imageCompress/zip`
      + `?minTimeStamp=${minTimeStamp}&fileName=${encodeURIComponent(fileName)}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }
}
