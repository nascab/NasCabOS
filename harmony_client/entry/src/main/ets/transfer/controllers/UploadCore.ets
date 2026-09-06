import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { APIClient } from '../../core/network/APIClient';
import { NetworkConfig } from '../../core/network/NetworkConfig';
import { APIResponse } from '../../core/network/APIResponse';
import { P2pRtcChannel, P2pTransportKind } from '../../p2p/P2pProtocol';
import { P2PService } from '../../p2p/P2PService';
import { HeaderMap } from '../../common/HeaderMap';
import { TransferTask } from '../models/TransferModels';
import { UploadTransferHelper } from '../utils/UploadTransferHelper';
import { UriReader } from '../utils/UriReader';

/** 取消令牌（对齐 Flutter CancelToken 的本地化最小实现） */
export class UploadCancellationToken {
  private cancelled: boolean = false;

  cancel(): void {
    this.cancelled = true;
  }

  isCancelled(): boolean {
    return this.cancelled;
  }
}

export class ProcessFileParams {
  task: TransferTask = new TransferTask('', '', '', '', 0, 0, 0);
  nameStrategy: string = 'skip';
  saveType: string = '';
  mtimeMs: number = 0;
  chunkSizeOverride: number = 0;
  onProgress: (increment: number) => void = (_n: number): void => {
  };
  onSkipped: () => void = (): void => {
  };
  cancelToken: UploadCancellationToken = new UploadCancellationToken();
}

const P2P_RELAY_CHUNK_CEILING = 256 * 1024;
const P2P_DIRECT_CHUNK_CEILING = 8 * 1024 * 1024;
const P2P_RELAY_MIN_CHUNK = 64 * 1024;
const MAX_RETRIES = 3;

/**
 * 分块上传核心（对齐 Flutter upload_core.dart）：
 * - check 接口走统一 APIClient（普通 HTTP 与 P2P 链路均可用）
 * - chunk 为 multipart 二进制：普通链路走 NetworkKit，P2P 链路走 RTC upload 通道
 * - P2P 中转链路对分块大小做上限收敛并在可重试错误时自动减半重试
 */
export class UploadCore {
  /** P2P 模式下归一化分块大小（对齐 _normalizeP2pChunkSize） */
  private static normalizeP2pChunkSize(chunkSize: number, isRelay: boolean): number {
    const max = isRelay ? P2P_RELAY_CHUNK_CEILING : P2P_DIRECT_CHUNK_CEILING;
    let normalized = chunkSize;
    if (normalized > max) {
      normalized = max;
    }
    if (isRelay && normalized < P2P_RELAY_MIN_CHUNK) {
      normalized = P2P_RELAY_MIN_CHUNK;
    }
    return normalized;
  }

  private static nextRelayChunkSize(chunkSize: number): number {
    const next = Math.floor(chunkSize / 2);
    return next < P2P_RELAY_MIN_CHUNK ? P2P_RELAY_MIN_CHUNK : next;
  }

  private static isRetryableRelayError(message: string): boolean {
    const lower = message.toLowerCase();
    return lower.includes('bad_gateway') ||
      lower.includes('request_body_too_large') ||
      lower.includes('request_timeout') ||
      lower.includes('upload_chunk_http_502') ||
      lower.includes('upload_chunk_http_413') ||
      lower.includes('upload_chunk_http_408');
  }

  private static throwIfCancelled(token: UploadCancellationToken): void {
    if (token.isCancelled()) {
      throw new Error('upload_cancelled');
    }
  }

  /** 上传单个文件核心逻辑，返回已处理字节数 */
  static async processFile(p: ProcessFileParams): Promise<number> {
    const task = p.task;
    const api = APIClient.getInstance();
    const isP2p = api.isP2pMode;
    const isRelayP2p = isP2p && P2PService.getInstance().transportKind === P2pTransportKind.RELAY;
    const saveType = (p.saveType === 'year' || p.saveType === 'month' || p.saveType === 'day') ? p.saveType : '';
    let chunkSize = p.chunkSizeOverride > 0 ? p.chunkSizeOverride : UploadTransferHelper.calculateChunkSize(task.totalSize);
    if (isP2p) {
      chunkSize = UploadCore.normalizeP2pChunkSize(chunkSize, isRelayP2p);
    }
    const sessionHash = `${task.fileHash}_${chunkSize}`;
    const totalChunks = Math.ceil(task.totalSize / chunkSize);
    let reportedNewProgress = false;

    // 1. 检查已上传分块（断点续传）；FILE_EXISTS 视为跳过
    let uploadedChunks: number[] = [];
    try {
      const body = UploadTransferHelper.checkBody(sessionHash, task.remotePath, chunkSize,
        task.name, totalChunks, p.nameStrategy, p.mtimeMs, saveType);
      const res = await api.apiPost<Object>('/api/file/upload/check', body, undefined,
        isP2p ? 120000 : undefined, isP2p ? 0 : undefined, (d: Object, _c: number) => d);
      if (!res.success) {
        const rawCode = UploadCore.rawCode(res);
        if (rawCode === 'file.FILE_EXISTS') {
          p.onSkipped();
          return task.totalSize;
        }
        throw new Error(res.message ?? 'upload_check_failed');
      }
      const data = res.data as Record<string, Object> | undefined;
      const list = data?.['uploadedChunks'];
      if (Array.isArray(list)) {
        uploadedChunks = (list as Array<Object>).map((v: Object): number => Number(v));
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      if (UploadTransferHelper.isFileExistsError(0, msg)) {
        p.onSkipped();
        return task.totalSize;
      }
      throw e instanceof Error ? e : new Error(`${e}`);
    }

    // 2. 逐块上传
    let processedSize = Math.min(uploadedChunks.length * chunkSize, task.totalSize);
    for (let i = 0; i < totalChunks; i++) {
      UploadCore.throwIfCancelled(p.cancelToken);
      if (uploadedChunks.includes(i)) {
        continue;
      }
      const start = i * chunkSize;
      const end = Math.min(start + chunkSize, task.totalSize);
      const length = end - start;

      let chunkToken = api.accessToken ?? '';
      if (api.state.isTokenExpiringSoon()) {
        const refreshed = await api.refreshAuthToken();
        if (refreshed) {
          chunkToken = api.accessToken ?? chunkToken;
        }
      }

      let retryCount = 0;
      while (true) {
        try {
          UploadCore.throwIfCancelled(p.cancelToken);
          const fields = UploadTransferHelper.chunkFields(sessionHash, task.remotePath, chunkSize,
            task.name, totalChunks, p.nameStrategy, i, p.mtimeMs, saveType);
          const chunkBytes = UriReader.readRange(task.localUri, start, length);
          UploadCore.throwIfCancelled(p.cancelToken);
          const boundary = `----nascabformdata${Date.now()}`;
          const body = UploadTransferHelper.buildMultipartBody(boundary, fields, 'file', 'chunk', chunkBytes);

          let statusCode = 0;
          let respText = '';
          if (isP2p) {
            const headers = new HeaderMap();
            headers.set('Authorization', `Bearer ${chunkToken}`);
            headers.set('Content-Type', `multipart/form-data; boundary=${boundary}`);
            headers.set('Accept', 'application/json');
            const resp = await P2PService.getInstance().sendOnChannel(
              P2pRtcChannel.UPLOAD, 'POST', '/api/file/upload/chunk', headers, body, 300000);
            statusCode = resp.status;
            const decoder = new util.TextDecoder();
            respText = decoder.decodeToString(resp.bodyBytes);
          } else {
            const req = http.createHttp();
            const resp = await req.request(`${api.baseUrl}/api/file/upload/chunk`, {
              method: http.RequestMethod.POST,
              header: UploadCore.directHeaders(chunkToken, boundary),
              extraData: body.buffer as ArrayBuffer,
              connectTimeout: NetworkConfig.DEFAULT_TIMEOUT_MS,
              readTimeout: 600000,
              expectDataType: http.HttpDataType.STRING,
              usingProtocol: http.HttpProtocol.HTTP1_1,
              remoteValidation: 'skip'
            });
            req.destroy();
            statusCode = resp.responseCode;
            respText = `${resp.result}`;
          }

          if (statusCode < 200 || statusCode >= 300) {
            if (UploadTransferHelper.isFileExistsError(statusCode, respText)) {
              p.onSkipped();
              p.onProgress(length);
              return task.totalSize;
            }
            throw new Error(UploadCore.describeHttpError(statusCode, respText));
          }
          break; // 本块成功
        } catch (e) {
          const msg = e instanceof Error ? e.message : `${e}`;
          if (msg === 'upload_cancelled') {
            throw e instanceof Error ? e : new Error(msg);
          }
          if (UploadTransferHelper.isFileExistsError(0, msg)) {
            p.onSkipped();
            p.onProgress(length);
            return task.totalSize;
          }
          // P2P 中转链路：未上报过新进度且可重试 → 减半分块重试整个文件
          if (isRelayP2p && !reportedNewProgress && p.chunkSizeOverride === 0 &&
            UploadCore.isRetryableRelayError(msg) && chunkSize > P2P_RELAY_MIN_CHUNK) {
            const next = UploadCore.nextRelayChunkSize(chunkSize);
            if (next < chunkSize) {
              p.chunkSizeOverride = next;
              return UploadCore.processFile(p);
            }
          }
          retryCount++;
          if (retryCount >= MAX_RETRIES) {
            throw e instanceof Error ? e : new Error(`${e}`);
          }
          await UploadCore.sleep(2000 * retryCount);
        }
      }

      p.onProgress(length);
      processedSize += length;
      reportedNewProgress = true;
    }
    return processedSize;
  }

  private static directHeaders(token: string, boundary: string): Record<string, string> {
    const record: Record<string, string> = {
      'Authorization': `Bearer ${token}`,
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'Accept': 'application/json'
    };
    return record;
  }

  private static describeHttpError(statusCode: number, respText: string): string {
    const text = respText.trim();
    if (text.length === 0) {
      return `upload_chunk_http_${statusCode}`;
    }
    try {
      const decoded = JSON.parse(text) as Record<string, Object>;
      const msg = decoded['message'];
      if (msg !== undefined && msg !== null) {
        return `${msg}`;
      }
    } catch (_e) {
      // 非 JSON
    }
    const clipped = text.length > 240 ? text.substring(0, 240) : text;
    return `upload_chunk_http_${statusCode}_${clipped}`;
  }

  private static rawCode(res: APIResponse<Object>): string {
    const raw = res.rawResponse;
    if (raw === undefined || raw === null) {
      return '';
    }
    const code = raw.code;
    return code === undefined || code === null ? '' : `${code}`;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
  }
}
