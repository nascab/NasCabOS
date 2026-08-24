import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { APIClient } from '../core/network/APIClient';
import { NetworkConfig } from '../core/network/NetworkConfig';
import { P2PService } from './P2PService';
import { P2pChannelUtil } from './P2pProtocol';
import { HeaderMap } from '../common/HeaderMap';

export class LocalPlaybackProxy {
  private static instance: LocalPlaybackProxy | undefined = undefined;
  isRunning: boolean = false;
  port: number | undefined = undefined;
  private tcpServer: socket.TCPSocketServer | undefined = undefined;

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
    client.on('message', (value: socket.SocketMessageInfo) => {
      const decoder = new util.TextDecoder();
      buffer += decoder.decodeToString(new Uint8Array(value.message));
      const headerEnd = buffer.indexOf('\r\n\r\n');
      if (headerEnd < 0) {
        return;
      }
      const headerPart = buffer.substring(0, headerEnd);
      const lines = headerPart.split('\r\n');
      const requestLine = lines.length > 0 ? lines[0] : '';
      const parts = requestLine.split(' ');
      const method = parts.length > 0 ? parts[0] : 'GET';
      const pathWithQuery = parts.length > 1 ? parts[1] : '/';

      const headers = new HeaderMap();
      for (let i = 1; i < lines.length; i++) {
        const idx = lines[i].indexOf(':');
        if (idx > 0) {
          const k = lines[i].substring(0, idx).trim();
          const v = lines[i].substring(idx + 1).trim();
          headers.set(k, v);
        }
      }

      const p2p = P2PService.getInstance();
      const channel = P2pChannelUtil.resolvePath(pathWithQuery);
      p2p.sendOnChannel(
        channel,
        method,
        pathWithQuery,
        headers,
        new Uint8Array(0),
        600000
      ).then((response) => {
        const responseHeaders = [
          `HTTP/1.1 ${response.status} OK`,
          'Content-Type: application/json',
          `Content-Length: ${response.bodyBytes.length}`,
          'Connection: close',
          '',
          '',
        ].join('\r\n');
        const encoder = new util.TextEncoder();
        const headerBytes = encoder.encodeInto(responseHeaders);
        const out = new Uint8Array(headerBytes.length + response.bodyBytes.length);
        out.set(headerBytes, 0);
        out.set(response.bodyBytes, headerBytes.length);
        client.send({ data: out.buffer });
        client.close();
      }).catch(() => {
        const err = 'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n';
        const encoder = new util.TextEncoder();
        client.send({ data: encoder.encodeInto(err).buffer });
        client.close();
      });
    });
  }
}
