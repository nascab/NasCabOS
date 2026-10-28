import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { APIClient } from '../core/network/APIClient';
import { NetworkConfig } from '../core/network/NetworkConfig';
import { P2PService } from './P2PService';
import { P2pChannelUtil } from './P2pProtocol';
import { P2pStreamHandler } from './WebRTCClient';
import { HeaderMap } from '../common/HeaderMap';

/** 单次 socket send 的最大字节数（P2P 分块最大 128KB，这里再切一次保证稳定） */
const SOCKET_SEND_CHUNK = 64 * 1024;
/** 流式请求空闲超时：转码产片/原画大文件可能出现较长时间无数据，给足余量 */
const STREAM_IDLE_TIMEOUT_MS = 300000;

/**
 * P2P 本地 HTTP 代理：
 * `p2p.local` 是虚拟域名，底层播放器（mpv/ffmpeg）无法解析，
 * 因此把播放地址改写到本机 `127.0.0.1:<port>`，由这里转成 P2P 通道请求。
 * 视频/大文件走流式转发（边收边写），不整体缓存。
 */
export class LocalPlaybackProxy {
  private static instance: LocalPlaybackProxy | undefined = undefined;
  isRunning: boolean = false;
  port: number | undefined = undefined;
  private tcpServer: socket.TCPSocketServer | undefined = undefined;
  private startPromise: Promise<void> | undefined = undefined;

  static getInstance(): LocalPlaybackProxy {
    if (!LocalPlaybackProxy.instance) {
      LocalPlaybackProxy.instance = new LocalPlaybackProxy();
    }
    return LocalPlaybackProxy.instance;
  }

  async start(): Promise<void> {
    if (this.isRunning) {
      return;
    }
    if (!APIClient.getInstance().isP2pMode) {
      return;
    }
    // 并发调用（建连流程 + 播放器起播）合并为同一次启动
    if (this.startPromise !== undefined) {
      await this.startPromise;
      return;
    }
    this.startPromise = this.openServer();
    try {
      await this.startPromise;
    } finally {
      this.startPromise = undefined;
    }
  }

  private async openServer(): Promise<void> {
    try {
      this.tcpServer = socket.constructTCPSocketServerInstance();
      this.tcpServer.on('connect', (client: socket.TCPSocketConnection) => {
        this.handleConnection(client);
      });
      await this.tcpServer.listen({ address: '127.0.0.1', port: 0, family: 1 });
      const local = await this.tcpServer.getLocalAddress();
      this.port = local.port;
      this.isRunning = true;
    } catch (e) {
      console.error(`LocalPlaybackProxy start failed: ${e}`);
      this.stop();
    }
  }

  stop(): void {
    if (this.tcpServer) {
      this.tcpServer.off('connect');
      this.tcpServer.close();
      this.tcpServer = undefined;
    }
    this.isRunning = false;
    this.port = undefined;
  }

  getBaseUrl(): string | undefined {
    if (!APIClient.getInstance().isP2pMode || !this.isRunning || !this.port) {
      return undefined;
    }
    return `http://127.0.0.1:${this.port}`;
  }

  /** 把 p2p.local 播放地址改写到本地代理；非 P2P 地址原样返回 */
  resolveP2pProxyUrl(url: string): string {
    if (!url.startsWith(NetworkConfig.P2P_BASE_URL)) {
      return url;
    }
    const base = this.getBaseUrl();
    if (!base) {
      return url;
    }
    return url.replace(NetworkConfig.P2P_BASE_URL, base);
  }

  private handleConnection(client: socket.TCPSocketConnection): void {
    let buffer = '';
    let requestStarted = false;
    let finished = false;
    let closed = false;
    let cancelFn: (() => void) | undefined = undefined;
    let headersSent = false;
    let useChunked = false;
    let writeChain: Promise<void> = Promise.resolve();

    const closeClient = (): void => {
      if (closed) {
        return;
      }
      closed = true;
      writeChain.then((): void => {
        client.close();
      }).catch((): void => {
        client.close();
      });
    };

    // 串行发送，保证响应数据按序写回；写入失败视为播放器已断开
    const enqueuePiece = (bytes: Uint8Array): void => {
      writeChain = writeChain
        .then((): Promise<void> => client.send({ data: bytes.buffer as ArrayBuffer }))
        .catch((): void => {
          // 播放器主动断开（seek/切换）：停止上游推送
          if (!finished) {
            finished = true;
            const fn = cancelFn;
            cancelFn = undefined;
            if (fn !== undefined) {
              fn();
            }
          }
        });
    };

    const enqueue = (bytes: Uint8Array): void => {
      for (let offset = 0; offset < bytes.length; offset += SOCKET_SEND_CHUNK) {
        const end = Math.min(offset + SOCKET_SEND_CHUNK, bytes.length);
        enqueuePiece(bytes.subarray(offset, end).slice());
      }
    };

    const enqueueText = (text: string): void => {
      const encoder = new util.TextEncoder();
      enqueue(encoder.encodeInto(text));
    };

    const writeSimpleError = (status: number, reason: string, detail: string): void => {
      headersSent = true;
      const encoder = new util.TextEncoder();
      const bodyBytes = encoder.encodeInto(detail);
      const head = `HTTP/1.1 ${status} ${reason}\r\n` +
        `Content-Type: text/plain; charset=utf-8\r\n` +
        `Content-Length: ${bodyBytes.length}\r\n` +
        `Connection: close\r\n\r\n`;
      enqueueText(head);
      enqueue(bodyBytes);
      closeClient();
    };

    client.on('close', (): void => {
      if (finished) {
        return;
      }
      finished = true;
      const fn = cancelFn;
      cancelFn = undefined;
      if (fn !== undefined) {
        fn();
      }
    });

    client.on('message', (value: socket.SocketMessageInfo) => {
      if (requestStarted) {
        // 播放请求均为 GET/HEAD，请求体直接忽略
        return;
      }
      const decoder = new util.TextDecoder();
      buffer += decoder.decodeToString(new Uint8Array(value.message));
      const headerEnd = buffer.indexOf('\r\n\r\n');
      if (headerEnd < 0) {
        return;
      }
      requestStarted = true;

      const headerPart = buffer.substring(0, headerEnd);
      const lines = headerPart.split('\r\n');
      const requestLine = lines.length > 0 ? lines[0] : '';
      const parts = requestLine.split(' ');
      const method = parts.length > 0 ? parts[0].trim().toUpperCase() : 'GET';
      let target = parts.length > 1 ? parts[1].trim() : '';

      // 兼容代理式绝对地址：GET http://127.0.0.1:port/path HTTP/1.1
      if (target.startsWith('http://') || target.startsWith('https://')) {
        const schemeEnd = target.indexOf('://');
        const pathIdx = target.indexOf('/', schemeEnd + 3);
        target = pathIdx >= 0 ? target.substring(pathIdx) : '/';
      }
      if (target.length === 0 || !target.startsWith('/')) {
        writeSimpleError(400, 'Bad Request', 'bad request target');
        return;
      }

      const headers = new HeaderMap();
      for (let i = 1; i < lines.length; i++) {
        const idx = lines[i].indexOf(':');
        if (idx > 0) {
          const k = lines[i].substring(0, idx).trim();
          const v = lines[i].substring(idx + 1).trim();
          headers.set(k, v);
        }
      }
      // 播放器不会带鉴权头：URL 未带 accessToken 时补 Authorization（对齐 Flutter/Android 代理）
      if (headers.get('Authorization') === undefined && target.indexOf('accessToken=') < 0) {
        const token = (APIClient.getInstance().accessToken ?? '').trim();
        if (token.length > 0) {
          headers.set('Authorization', `Bearer ${token}`);
        }
      }

      const isHead = method === 'HEAD';
      const channel = P2pChannelUtil.resolvePath(target);

      const streamHandler: P2pStreamHandler = {
        onBegin: (status: number, respHeaders: HeaderMap): void => {
          headersSent = true;
          const headLines: string[] = [];
          headLines.push(`HTTP/1.1 ${status} ${reasonPhrase(status)}`);
          let hasLength = false;
          respHeaders.forEach((v: string, k: string): void => {
            const lk = k.toLowerCase();
            if (lk === 'connection' || lk === 'transfer-encoding') {
              return;
            }
            if (lk === 'content-length') {
              hasLength = true;
            }
            headLines.push(`${k}: ${v}`);
          });
          // 无 Content-Length 时用 chunked，让播放器可以边下边播
          if (!isHead && !hasLength) {
            useChunked = true;
            headLines.push('Transfer-Encoding: chunked');
          }
          headLines.push('Connection: close');
          enqueueText(headLines.join('\r\n') + '\r\n\r\n');
        },
        onChunk: (data: Uint8Array): void => {
          if (isHead) {
            return;
          }
          if (!useChunked) {
            enqueue(data);
            return;
          }
          const encoder = new util.TextEncoder();
          const sizeBytes = encoder.encodeInto(`${data.length.toString(16)}\r\n`);
          const tail = encoder.encodeInto('\r\n');
          const out = new Uint8Array(sizeBytes.length + data.length + tail.length);
          out.set(sizeBytes, 0);
          out.set(data, sizeBytes.length);
          out.set(tail, sizeBytes.length + data.length);
          enqueue(out);
        },
        onEnd: (): void => {
          if (finished) {
            return;
          }
          finished = true;
          cancelFn = undefined;
          if (useChunked) {
            enqueueText('0\r\n\r\n');
          }
          closeClient();
        },
        onError: (e: Error): void => {
          console.error(`LocalPlaybackProxy stream error: ${e.message} url=${target}`);
          if (finished) {
            return;
          }
          finished = true;
          cancelFn = undefined;
          if (!headersSent) {
            writeSimpleError(502, 'Bad Gateway', `p2p stream error: ${e.message}`);
          } else {
            closeClient();
          }
        }
      };

      P2PService.getInstance()
        .sendOnChannelStream(channel, method, target, headers, new Uint8Array(0),
          STREAM_IDLE_TIMEOUT_MS, streamHandler)
        .then((cancel: () => void): void => {
          cancelFn = cancel;
          if (finished) {
            // 请求建立前连接已结束：立刻通知对端停止推送
            cancel();
          }
        })
        .catch((e: Error): void => {
          console.error(`LocalPlaybackProxy request failed: ${e.message} url=${target}`);
          if (finished) {
            return;
          }
          finished = true;
          cancelFn = undefined;
          if (!headersSent) {
            writeSimpleError(502, 'Bad Gateway', `p2p not ready: ${e.message}`);
          } else {
            closeClient();
          }
        });
    });
  }
}

function reasonPhrase(status: number): string {
  switch (status) {
    case 200:
      return 'OK';
    case 206:
      return 'Partial Content';
    case 301:
      return 'Moved Permanently';
    case 302:
      return 'Found';
    case 304:
      return 'Not Modified';
    case 400:
      return 'Bad Request';
    case 401:
      return 'Unauthorized';
    case 403:
      return 'Forbidden';
    case 404:
      return 'Not Found';
    case 416:
      return 'Range Not Satisfiable';
    case 500:
      return 'Internal Server Error';
    case 503:
      return 'Service Unavailable';
    default:
      return 'OK';
  }
}
