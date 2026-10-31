import { webSocket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { APIClient } from '../../../core/network/APIClient';
import { JsonCodec } from '../../../common/JsonTypes';
import { P2PService } from '../../../p2p/P2PService';
import { P2pRtcChannel, P2pWebSocket } from '../../../p2p/P2pProtocol';
import { extractWsRequestPath } from '../../terminal/services/TerminalUrlService';
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
type ErrorCallback = (message: string) => void;

/**
 * 目录大小统计服务（对齐 Flutter file_stats_service.dart）：
 * 连接 /api/file/stats 后下发 {paths, action:'start'}，接收 progress/complete/error 事件。
 * P2P 模式下 p2p.local 无法直连，必须走 DataChannel 内的 WebSocket 隧道
 * （对齐 Flutter connectFileWebSocketChannel → connectP2pWebSocketChannelLazy）。
 */
export class FileStatsService {
  private ws: webSocket.WebSocket | undefined = undefined;
  private p2pWs: P2pWebSocket | undefined = undefined;

  connect(paths: string[], onProgress: StatsCallback, onComplete: StatsCallback,
    onError: ErrorCallback): void {
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
    if (api.isP2pMode) {
      this.connectP2p(wsUri, paths, onProgress, onComplete, onError);
      return;
    }
    try {
      const ws = webSocket.createWebSocket();
      this.ws = ws;
      // 必须等 on('open')（握手完成、socket 真正可写）再下发 start 命令。
      // 鸿蒙 connect 回调会早于 open 事件触发，此时 send 的帧会丢失且回调无错误，
      // 导致服务端始终收不到 start → 收不到 progress/complete → 属性里没有统计数据。
      ws.on('open', (_err: Object, _value: Object): void => {
        if (this.ws !== ws) {
          return;
        }
        console.info(`[FileStats] open, send start paths=${paths.length}`);
        ws.send(JSON.stringify({ 'paths': paths, 'action': 'start' }), (sendErr: Object): void => {
          if (sendErr) {
            console.error(`[FileStats] send start error: ${JSON.stringify(sendErr)}`);
            onError(`${JSON.stringify(sendErr)}`);
          }
        });
      });
      ws.on('message', (_err: Object, value: string | ArrayBuffer): void => {
        if (this.ws !== ws) {
          return;
        }
        const text = typeof value === 'string' ? value : FileStatsService.decode(value);
        this.handleText(text, onProgress, onComplete, onError);
      });
      ws.on('error', (err: Object): void => {
        if (this.ws !== ws) {
          return;
        }
        console.error(`[FileStats] ws error: ${JSON.stringify(err ?? {})}`);
        onError(`${JSON.stringify(err ?? {})}`);
      });
      console.info(`[FileStats] connecting uri=${wsUri}`);
      ws.connect(wsUri, (err: Object, _value: boolean): void => {
        if (err) {
          console.error(`[FileStats] connect error: ${JSON.stringify(err)} uri=${wsUri}`);
          onError(`${JSON.stringify(err)}`);
        }
      });
    } catch (e) {
      console.error(`[FileStats] connect failed: ${e}`);
      onError(`${e}`);
    }
  }

  /** P2P 模式：在 API 通道上开 WebSocket 隧道（路径取自 p2p.local 形式的 ws 地址） */
  private connectP2p(wsUri: string, paths: string[], onProgress: StatsCallback,
    onComplete: StatsCallback, onError: ErrorCallback): void {
    const path = extractWsRequestPath(wsUri);
    if (path.length === 0) {
      onError('Invalid P2P WS path');
      return;
    }
    try {
      const ws = P2PService.getInstance().openWebSocket(P2pRtcChannel.API, path);
      this.p2pWs = ws;
      ws.listener = {
        onOpen: (): void => {
          if (this.p2pWs !== ws) {
            return;
          }
          console.info(`[FileStats] p2p ws open, send start paths=${paths.length}`);
          ws.send(JSON.stringify({ 'paths': paths, 'action': 'start' }));
        },
        onMessage: (data: string): void => {
          if (this.p2pWs !== ws) {
            return;
          }
          this.handleText(data, onProgress, onComplete, onError);
        },
        onError: (error: string): void => {
          if (this.p2pWs !== ws) {
            return;
          }
          console.error(`[FileStats] p2p ws error: ${error}`);
          onError(error);
        },
        onClose: (code: number, reason: string): void => {
          if (this.p2pWs !== ws) {
            return;
          }
          console.info(`[FileStats] p2p ws close: ${code} ${reason}`);
        }
      };
      console.info(`[FileStats] connecting p2p path=${path.substring(0, 80)}`);
      ws.open();
    } catch (e) {
      console.error(`[FileStats] p2p connect failed: ${e}`);
      onError(`${e}`);
    }
  }

  /** 解析并分发 progress/complete/error（普通 WS 与 P2P 隧道共用） */
  private handleText(text: string, onProgress: StatsCallback, onComplete: StatsCallback,
    onError: ErrorCallback): void {
    if (text.length === 0) {
      return;
    }
    try {
      const data = JsonCodec.parseStr<FileStatsMessage>(text);
      const stats = new FileStats();
      stats.size = data.size ?? 0;
      stats.count = data.count ?? 0;
      stats.folderCount = data.folderCount ?? 0;
      stats.ctime = data.ctime;
      stats.mtime = data.mtime;
      console.info(`[FileStats] type=${data.type ?? ''} size=${stats.size} count=${stats.count} ` +
        `folderCount=${stats.folderCount}`);
      if (data.type === 'progress') {
        onProgress(stats);
      } else if (data.type === 'complete') {
        onComplete(stats);
        this.close();
      } else if (data.type === 'error') {
        onError(data.message ?? 'stats error');
        this.close();
      }
    } catch (e) {
      console.error(`[FileStats] parse error: ${e}`);
    }
  }

  /** 服务端可能以二进制帧下发 JSON（对齐 FileWatcherService.decode） */
  private static decode(buf: ArrayBuffer): string {
    try {
      return new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
    } catch (_e) {
      return '';
    }
  }

  close(): void {
    const p2pWs = this.p2pWs;
    this.p2pWs = undefined;
    if (p2pWs) {
      try {
        p2pWs.close();
      } catch (_e) {
        // 已断开
      }
    }
    const ws = this.ws;
    this.ws = undefined;
    if (ws) {
      try {
        ws.close();
      } catch (_e) {
        // 已断开
      }
    }
  }
}
