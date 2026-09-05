import { webSocket } from '@kit.NetworkKit';
import { APIClient } from '../../core/network/APIClient';
import { JsonCodec } from '../../common/JsonTypes';
import { resolveFileWsBaseUri } from './FileWatcherService';
import { FileStats } from '../models/FileModels';

/** WS /api/file/stats 消息（progress/complete/error 共用结构） */
class FileStatsMessage {
  type?: string;
  message?: string;
  size?: number;
  count?: number;
  folderCount?: number;
  ctime?: string;
  mtime?: string;
}

type StatsCallback = (stats: FileStats) => void;

/**
 * 目录大小统计服务（对齐 Flutter file_stats_service.dart）：
 * 连接 /api/file/stats 后下发 {paths, action:'start'}，接收 progress/complete/error 事件。
 */
export class FileStatsService {
  private ws: webSocket.WebSocket | undefined = undefined;

  connect(paths: string[], onProgress: StatsCallback, onComplete: StatsCallback,
    onError: (message: string) => void): void {
    this.close();
    const api = APIClient.getInstance();
    const baseUrl = api.baseUrl;
    if (baseUrl.trim().length === 0) {
      onError('Base URL is empty');
      return;
    }
    const wsBase = resolveFileWsBaseUri(baseUrl);
    if (wsBase.length === 0) {
      onError('Invalid Base URL');
      return;
    }
    const token = api.accessToken;
    const qp: string[] = [];
    if (token !== undefined && token.length > 0) {
      qp.push(`accessToken=${encodeURIComponent(token)}`);
    }
    const wsUri = qp.length > 0 ? `${wsBase}/api/file/stats?${qp.join('&')}` : `${wsBase}/api/file/stats`;
    try {
      this.ws = webSocket.createWebSocket();
      this.ws.on('message', (_err: Object, value: string | ArrayBuffer): void => {
        if (typeof value !== 'string') {
          return;
        }
        try {
          const data = JsonCodec.parseStr<FileStatsMessage>(value);
          const stats = new FileStats();
          stats.size = data.size ?? 0;
          stats.count = data.count ?? 0;
          stats.folderCount = data.folderCount ?? 0;
          stats.ctime = data.ctime;
          stats.mtime = data.mtime;
          if (data.type === 'progress') {
            onProgress(stats);
          } else if (data.type === 'complete') {
            onComplete(stats);
            this.close();
          } else if (data.type === 'error') {
            onError(data.message ?? 'stats error');
            this.close();
          }
        } catch (_e) {
          // 消息解析失败忽略
        }
      });
      this.ws.on('error', (err: Object): void => {
        onError(`${JSON.stringify(err ?? {})}`);
      });
      this.ws.connect(wsUri, (err: Object, _value: boolean): void => {
        if (err) {
          onError(`${JSON.stringify(err)}`);
          return;
        }
        const msg = JSON.stringify({ 'paths': paths, 'action': 'start' });
        this.ws?.send(msg, (): void => {
        });
      });
    } catch (e) {
      onError(`${e}`);
    }
  }

  close(): void {
    if (this.ws) {
      try {
        this.ws.close();
      } catch (_e) {
        // 已断开
      }
      this.ws = undefined;
    }
  }
}
