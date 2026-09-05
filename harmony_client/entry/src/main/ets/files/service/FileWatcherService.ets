import { webSocket } from '@kit.NetworkKit';
import { APIClient } from '../../core/network/APIClient';
import { JsonCodec } from '../../common/JsonTypes';
import { FileItem } from '../models/FileModels';

/** 文件变更消息（WS /api/file/watch type=change） */
export class FileChangeData {
  type?: string;
  changeDir?: string;
  added?: FileItem[];
  removed?: string[];
}

/**
 * 由 baseUrl 推导 WS 地址（对齐 Flutter resolveFileWsBaseUri 非 Web 分支）：
 * https → wss，http → ws；端口缺省时按协议默认端口。
 */
export function resolveFileWsBaseUri(baseUrl: string): string {
  const base = baseUrl.trim();
  if (base.length === 0) {
    return '';
  }
  const uri = base.replace(/\/+$/, '');
  if (uri.startsWith('https://')) {
    return `wss://${uri.substring('https://'.length)}`;
  }
  if (uri.startsWith('http://')) {
    return `ws://${uri.substring('http://'.length)}`;
  }
  return `ws://${uri}`;
}

/**
 * 文件监听服务（对齐 Flutter file_watcher_service.dart）：
 * 连接 /api/file/watch，进入目录后下发 watch 命令，接收 change 事件增量更新列表。
 */
export class FileWatcherService {
  private ws: webSocket.WebSocket | undefined = undefined;
  private readonly onFileChange: (data: FileChangeData) => void;
  private readonly onError: (e: Object) => void;

  constructor(onFileChange: (data: FileChangeData) => void, onError: (e: Object) => void) {
    this.onFileChange = onFileChange;
    this.onError = onError;
  }

  connect(path: string): void {
    this.disconnect();
    const api = APIClient.getInstance();
    const baseUrl = api.baseUrl;
    if (baseUrl.trim().length === 0) {
      return;
    }
    const wsBase = resolveFileWsBaseUri(baseUrl);
    if (wsBase.length === 0) {
      return;
    }
    const token = api.accessToken;
    const qp: string[] = [];
    if (token !== undefined && token.length > 0) {
      qp.push(`accessToken=${encodeURIComponent(token)}`);
    }
    qp.push(`path=${encodeURIComponent(path)}`);
    const wsUri = `${wsBase}/api/file/watch?${qp.join('&')}`;
    try {
      this.ws = webSocket.createWebSocket();
      this.ws.on('message', (_err: Object, value: string | ArrayBuffer): void => {
        if (typeof value !== 'string') {
          return;
        }
        try {
          const data = JsonCodec.parseStr<FileChangeData>(value);
          if (data.type === 'change') {
            this.onFileChange(data);
          }
        } catch (e) {
          console.error(`[FileWatcher] parse error: ${e}`);
        }
      });
      this.ws.on('error', (err: Object): void => {
        console.error(`[FileWatcher] ws error: ${JSON.stringify(err ?? {})}`);
        this.onError(err);
      });
      this.ws.connect(wsUri, (err: Object, _value: boolean): void => {
        if (err) {
          console.error(`[FileWatcher] connect error: ${JSON.stringify(err)}`);
          return;
        }
        // 连接成功后下发 watch 命令
        const msg = JSON.stringify({ 'type': 'watch', 'path': path });
        this.ws?.send(msg, (sendErr: Object): void => {
          if (sendErr) {
            console.error(`[FileWatcher] send error: ${JSON.stringify(sendErr)}`);
          }
        });
      });
    } catch (e) {
      console.error(`[FileWatcher] connect failed: ${e}`);
      this.onError(e as Object);
    }
  }

  disconnect(): void {
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
