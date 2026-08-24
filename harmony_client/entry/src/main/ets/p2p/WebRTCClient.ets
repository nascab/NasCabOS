import { util } from '@kit.ArkTS';
import { WebRTCNativeBridge } from './WebRTCNativeBridge';
import {
  P2pApiResponse,
  P2pBinaryFrame,
  P2pControlBinary,
  P2pControlType,
  P2pRequestId,
  P2pRtcChannel,
  P2PError,
} from './P2pProtocol';
import { HeaderMap } from '../common/HeaderMap';
import { IceCandidateJson, P2pControlPayload, SignalingDecoded } from '../common/JsonTypes';
import { SignalingOfferMsg } from './P2pSignalingBinary';

class PendingRequest {
  resolve: (value: P2pApiResponse) => void = () => {};
  reject: (reason: Error) => void = () => {};
}

class PendingChunk {
  status: number = 200;
  headers: HeaderMap = new HeaderMap();
  chunks: Uint8Array[] = [];
}

class ChannelState {
  channel: P2pRtcChannel;
  prefix: string;
  handle: number = -1;
  isReady: boolean = false;
  pending: Map<string, PendingRequest> = new Map();
  pendingChunks: Map<string, PendingChunk> = new Map();

  constructor(channel: P2pRtcChannel, handle: number) {
    this.channel = channel;
    this.prefix = channel;
    this.handle = handle;
  }
}

export type SignalingSendCallback = (msg: SignalingOfferMsg) => void;

export class WebRTCClient {
  sessionId: string;
  iceServers: Object[];
  sendOffer: SignalingSendCallback;
  private pcHandle: number = -1;
  private channels: Map<P2pRtcChannel, ChannelState> = new Map();
  private readyPromise: Promise<void> | undefined = undefined;
  private readyResolve: (() => void) | undefined = undefined;
  private readyReject: ((e: Error) => void) | undefined = undefined;
  private pendingReadyCount: number = 0;
  private remoteDescriptionApplied: boolean = false;
  private pendingRemoteIce: IceCandidateJson[] = [];

  constructor(sessionId: string, iceServers: Object[], sendOffer: SignalingSendCallback) {
    this.sessionId = sessionId;
    this.iceServers = iceServers;
    this.sendOffer = sendOffer;
    WebRTCNativeBridge.init(
      (channelHandle, data) => this.onBinaryMessage(channelHandle, data),
      (channelName) => this.onChannelReady(channelName)
    );
  }

  async start(requestedChannels: P2pRtcChannel[]): Promise<void> {
    this.pcHandle = WebRTCNativeBridge.createPeerConnection();
    this.pendingReadyCount = requestedChannels.length;
    this.readyPromise = new Promise<void>((resolve, reject) => {
      this.readyResolve = resolve;
      this.readyReject = reject;
    });

    for (let i = 0; i < requestedChannels.length; i++) {
      const ch = requestedChannels[i];
      const handle = WebRTCNativeBridge.createDataChannel(this.pcHandle, ch);
      this.channels.set(ch, new ChannelState(ch, handle));
    }

    const offer = WebRTCNativeBridge.createOffer();
    const offerMsg = new SignalingOfferMsg(this.sessionId, offer.type ?? 'offer', offer.sdp ?? '');
    this.sendOffer(offerMsg);

    for (let i = 0; i < requestedChannels.length; i++) {
      WebRTCNativeBridge.simulateChannelReady(requestedChannels[i]);
    }

    const timeout = setTimeout(() => {
      if (this.readyReject) {
        this.readyReject(P2PError.wsError('p2p_ready_timeout') as Error);
      }
    }, 60000);

    try {
      if (this.readyPromise) {
        await this.readyPromise;
      }
    } finally {
      clearTimeout(timeout);
    }
  }

  handleSignalingMessage(msg: SignalingDecoded): void {
    const msgType = msg.type ?? '';
    if (msgType === 'webrtc:answer') {
      const answer = msg.answer;
      if (answer) {
        WebRTCNativeBridge.setRemoteDescription(
          this.pcHandle,
          answer.type ?? '',
          answer.sdp ?? ''
        );
      }
      this.remoteDescriptionApplied = true;
      for (let i = 0; i < this.pendingRemoteIce.length; i++) {
        this.addRemoteCandidate(this.pendingRemoteIce[i]);
      }
      this.pendingRemoteIce = [];
    } else if (msgType === 'webrtc:candidate') {
      const c = msg.candidate;
      if (!c) {
        return;
      }
      if (!this.remoteDescriptionApplied) {
        this.pendingRemoteIce.push(c);
      } else {
        this.addRemoteCandidate(c);
      }
    }
  }

  private addRemoteCandidate(c: IceCandidateJson): void {
    WebRTCNativeBridge.addIceCandidate(
      this.pcHandle,
      c.candidate,
      c.sdpMid,
      c.sdpMLineIndex
    );
  }

  private onChannelReady(channelName: string): void {
    this.channels.forEach((state: ChannelState) => {
      if (state.prefix === channelName) {
        state.isReady = true;
        this.pendingReadyCount -= 1;
        if (this.pendingReadyCount <= 0 && this.readyResolve) {
          this.readyResolve();
        }
      }
    });
  }

  private onBinaryMessage(channelHandle: number, data: ArrayBuffer): void {
    const bytes = new Uint8Array(data);
    let state: ChannelState | undefined = undefined;
    this.channels.forEach((ch: ChannelState) => {
      if (ch.handle === channelHandle) {
        state = ch;
      }
    });
    if (!state) {
      return;
    }
    if (P2pControlBinary.isControl(bytes)) {
      this.handleControlMessage(state, bytes);
    } else {
      this.handleBinaryFrame(state, bytes);
    }
  }

  private handleControlMessage(state: ChannelState, data: Uint8Array): void {
    const mt = data[4];
    if (mt === P2pControlType.READY) {
      state.isReady = true;
      return;
    }
    if (mt === P2pControlType.RES_BEGIN) {
      const decoder = new util.TextDecoder();
      const text = decoder.decodeToString(data);
      const idMatch = text.match(/req_\d+/);
      const id = idMatch ? idMatch[0] : P2pRequestId.generate();
      const chunk = new PendingChunk();
      state.pendingChunks.set(id, chunk);
    }
    if (mt === P2pControlType.RES_END) {
      state.pendingChunks.forEach((chunk: PendingChunk, id: string) => {
        let totalLen = 0;
        for (let i = 0; i < chunk.chunks.length; i++) {
          totalLen += chunk.chunks[i].length;
        }
        const body = new Uint8Array(totalLen);
        let offset = 0;
        for (let i = 0; i < chunk.chunks.length; i++) {
          body.set(chunk.chunks[i], offset);
          offset += chunk.chunks[i].length;
        }
        const pending = state.pending.get(id);
        if (pending) {
          pending.resolve(new P2pApiResponse(chunk.status, chunk.headers, body));
          state.pending.delete(id);
        }
        state.pendingChunks.delete(id);
      });
    }
  }

  private handleBinaryFrame(state: ChannelState, data: Uint8Array): void {
    if (data.length < 2) return;
    const idLen = data[1];
    if (data.length < 2 + idLen) return;
    const decoder = new util.TextDecoder();
    const requestId = decoder.decodeToString(data.subarray(2, 2 + idLen));
    const payload = data.subarray(2 + idLen);
    const chunk = state.pendingChunks.get(requestId);
    if (chunk) {
      chunk.chunks.push(payload);
    }
  }

  async sendRequest(
    channel: P2pRtcChannel,
    method: string,
    path: string,
    headers: HeaderMap,
    bodyBytes: Uint8Array = new Uint8Array(0),
    timeoutMs: number = 300000
  ): Promise<P2pApiResponse> {
    const state = this.channels.get(channel);
    if (!state || !state.isReady) {
      throw P2PError.notConnected();
    }

    const id = P2pRequestId.generate();
    const safeHeaders = headers.removeProxyHeaders();

    return new Promise<P2pApiResponse>((resolve, reject) => {
      const pending = new PendingRequest();
      pending.resolve = resolve;
      pending.reject = reject;
      state.pending.set(id, pending);

      if (bodyBytes.length === 0) {
        const payload = new P2pControlPayload();
        payload.id = id;
        payload.method = method;
        payload.path = path;
        payload.headers = safeHeaders;
        const ctrl = P2pControlBinary.encodeControl(state.prefix, P2pControlType.REQ, payload);
        if (ctrl) {
          WebRTCNativeBridge.sendBinary(state.handle, ctrl.buffer as ArrayBuffer);
        }
      } else {
        const beginPayload = new P2pControlPayload();
        beginPayload.id = id;
        beginPayload.method = method;
        beginPayload.path = path;
        beginPayload.headers = safeHeaders;
        beginPayload.length = bodyBytes.length;
        const begin = P2pControlBinary.encodeControl(state.prefix, P2pControlType.REQ_BEGIN, beginPayload);
        if (begin) {
          WebRTCNativeBridge.sendBinary(state.handle, begin.buffer as ArrayBuffer);
        }
        const header = P2pBinaryFrame.buildHeader(P2pBinaryFrame.VERSION_V1, id);
        const packet = new Uint8Array(header.length + bodyBytes.length);
        packet.set(header, 0);
        packet.set(bodyBytes, header.length);
        WebRTCNativeBridge.sendBinary(state.handle, packet.buffer as ArrayBuffer);

        const endPayload = new P2pControlPayload();
        endPayload.id = id;
        const end = P2pControlBinary.encodeControl(state.prefix, P2pControlType.REQ_END, endPayload);
        if (end) {
          WebRTCNativeBridge.sendBinary(state.handle, end.buffer as ArrayBuffer);
        }
      }

      setTimeout(() => {
        const p = state.pending.get(id);
        if (p) {
          state.pending.delete(id);
          state.pendingChunks.delete(id);
          p.reject(P2PError.wsError('p2p_timeout') as Error);
        }
      }, timeoutMs);
    });
  }

  get hasPendingRequests(): boolean {
    let found = false;
    this.channels.forEach((state: ChannelState) => {
      if (state.pending.size > 0 || state.pendingChunks.size > 0) {
        found = true;
      }
    });
    return found;
  }

  async getTransportStats(): Promise<TransportStatsResult> {
    const stats = new TransportStatsResult();
    stats.type = 'relay';
    return stats;
  }

  close(): void {
    if (this.pcHandle >= 0) {
      WebRTCNativeBridge.closePeerConnection(this.pcHandle);
      this.pcHandle = -1;
    }
    this.channels.forEach((state: ChannelState) => {
      state.pending.forEach((p: PendingRequest) => {
        p.reject(P2PError.wsError('p2p_closed') as Error);
      });
      state.pending.clear();
      state.pendingChunks.clear();
    });
    this.channels.clear();
  }
}

export class TransportStatsResult {
  type: string = 'relay';
}
