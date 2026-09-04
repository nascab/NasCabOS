import { util } from '@kit.ArkTS';
import { webSocket } from '@kit.NetworkKit';
import { P2pSignalingBinary, SignalingOfferMsg } from './P2pSignalingBinary';
import { SignalingDecoded } from '../common/JsonTypes';

export interface WebSocketSignalingDelegate {
  onSessionReady(sessionId: string, iceServers: Object[]): void;
  onWebRTCMessage(message: SignalingDecoded): void;
  onError(code: string): void;
  onClose(): void;
}

export class WebSocketSignaling {
  private ws: webSocket.WebSocket | undefined = undefined;
  private connected: boolean = false;
  private heartbeatTimerId: number = -1;
  delegate: WebSocketSignalingDelegate | undefined = undefined;

  connect(urlString: string): void {
    if (this.ws) {
      this.disconnect();
    }
    this.ws = webSocket.createWebSocket();
    this.ws.on('open', (err, value) => {
      console.error(`[P2P] ws open: ${JSON.stringify(value ?? {})}`);
      this.connected = true;
      this.startHeartbeat();
    });
    this.ws.on('message', (err, value) => {
      if (err) {
        console.error(`[P2P] ws message error: ${JSON.stringify(err)}`);
        return;
      }
      this.handleMessage(value);
    });
    this.ws.on('close', (err, value) => {
      console.error(`[P2P] ws close: code=${JSON.stringify(value ?? {})}, err=${JSON.stringify(err ?? {})}`);
      this.handleDisconnect();
    });
    this.ws.on('error', (err) => {
      console.error(`[P2P] ws error: ${JSON.stringify(err ?? {})}`);
      this.delegate?.onError('p2p_ws_error');
      this.handleDisconnect();
    });
    console.error(`[P2P] ws connecting: ${urlString}`);
    this.ws.connect(urlString);
  }

  sendPing(ts: number): void {
    if (!this.ws || !this.connected) {
      return;
    }
    const data = P2pSignalingBinary.encodePing(ts);
    this.ws.send(data.buffer);
  }

  sendOffer(msg: SignalingOfferMsg): void {
    if (!this.ws || !this.connected) {
      return;
    }
    const data = P2pSignalingBinary.encodeOffer(msg);
    this.ws.send(data.buffer);
  }

  sendCandidate(data: Uint8Array): void {
    if (!this.ws || !this.connected) {
      return;
    }
    this.ws.send(data.buffer);
  }

  disconnect(): void {
    this.connected = false;
    this.stopHeartbeat();
    if (this.ws) {
      this.ws.close();
      this.ws = undefined;
    }
  }

  private handleMessage(value: Object): void {
    let bytes: Uint8Array;
    if (value instanceof ArrayBuffer) {
      bytes = new Uint8Array(value);
    } else if (typeof value === 'string') {
      const encoder = new util.TextEncoder();
      bytes = encoder.encodeInto(value);
    } else {
      return;
    }
    const json = P2pSignalingBinary.decodeSignaling(bytes);
    if (!json || !json.type) {
      return;
    }
    const type = json.type;
    switch (type) {
      case 'pong':
        break;
      case 'session:ready':
        this.delegate?.onSessionReady(
          json.sessionId ?? '',
          json.iceServers ?? []
        );
        break;
      case 'session:closed':
        this.handleDisconnect();
        break;
      case 'error':
        this.delegate?.onError(json.code ?? 'P2P_ERROR');
        this.handleDisconnect();
        break;
      default:
        if (type.startsWith('webrtc:')) {
          this.delegate?.onWebRTCMessage(json);
        }
        break;
    }
  }

  private handleDisconnect(): void {
    if (!this.connected) {
      return;
    }
    this.connected = false;
    this.stopHeartbeat();
    this.delegate?.onClose();
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimerId = setInterval(() => {
      this.sendPing(Date.now());
    }, 25000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimerId >= 0) {
      clearInterval(this.heartbeatTimerId);
      this.heartbeatTimerId = -1;
    }
  }
}
