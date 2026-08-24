import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { JsonCodec, UdpDiscoveryJson } from '../../common/JsonTypes';

const BROADCAST_PORT = 8888;

export type ServerDiscoveredCallback = (info: UdpDiscoveryJson) => void;

export class UdpBroadcastListener {
  private udp: socket.UDPSocket | undefined = undefined;
  private listening: boolean = false;
  private callback: ServerDiscoveredCallback | undefined = undefined;

  setOnServerDiscovered(cb: ServerDiscoveredCallback): void {
    this.callback = cb;
  }

  async startListening(): Promise<void> {
    if (this.listening) {
      return;
    }
    try {
      this.udp = socket.constructUDPSocketInstance();
      this.udp.on('message', (value: socket.SocketMessageInfo) => {
        this.handleMessage(value);
      });
      await this.udp.bind({ address: '0.0.0.0', port: BROADCAST_PORT, family: 1 });
      this.listening = true;
    } catch (e) {
      console.error(`UDP listen failed: ${e}`);
    }
  }

  stopListening(): void {
    if (this.udp) {
      this.udp.off('message');
      this.udp.close();
      this.udp = undefined;
    }
    this.listening = false;
  }

  private handleMessage(value: socket.SocketMessageInfo): void {
    try {
      const decoder = new util.TextDecoder();
      const text = decoder.decodeToString(new Uint8Array(value.message));
      const info = JsonCodec.parseStr<UdpDiscoveryJson>(text);
      if (info.service === 'nascab-pro-service' &&
        info.host !== undefined &&
        info.port !== undefined) {
        this.callback?.(info);
      }
    } catch (_e) {
      // ignore malformed broadcasts
    }
  }
}
