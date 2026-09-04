import { util } from '@kit.ArkTS';
import { WebRTCNativeBridge } from './WebRTCNativeBridge';
import {
  P2pApiResponse,
  P2pBinaryFrame,
  P2pBinaryReader,
  P2pControlBinary,
  P2pControlType,
  P2pRequestId,
  P2pRtcChannel,
  P2PError,
} from './P2pProtocol';
import { HeaderMap } from '../common/HeaderMap';
import { IceCandidateJson, P2pControlPayload, SignalingDecoded } from '../common/JsonTypes';
import { SignalingOfferMsg } from './P2pSignalingBinary';

const BODY_CHUNK_SIZE = 64 * 1024; // 对齐 Flutter _bodyChunkSize(api)
const ACK_IMMEDIATE_THRESHOLD = 32 * 1024; // 累积超过阈值立即回 ack
const ACK_FLUSH_DELAY_MS = 15; // 对齐 Flutter api 通道 ack 定时刷新
const HEARTBEAT_INTERVAL_MS = 15000; // 对齐 Flutter _apiHeartbeatTimer

class PendingRequest {
  resolve: (value: P2pApiResponse) => void = () => {};
  reject: (reason: Error) => void = () => {};
  method: string = '';
  path: string = '';
}

class PendingChunk {
  status: number = 200;
  headers: HeaderMap = new HeaderMap();
  chunks: Uint8Array[] = [];
  length: number = 0;
  ackPendingBytes: number = 0;
  ackTimerId: number = -1;
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
  private heartbeatTimerId: number = -1;

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
    console.error(`[P2P] start: channels=${requestedChannels.join(',')}, iceServers=${JSON.stringify(this.iceServers)}`);
    this.pcHandle = WebRTCNativeBridge.createPeerConnection(this.iceServers);
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

    // 先触发真实的 createOffer + setLocalDescription（异步），
    // 再等待其完成拿到真实 SDP。此前直接调用 ensureLocalOffer 会因
    // offerPending 未设置而返回空 SDP，导致服务端无法处理而断开。
    WebRTCNativeBridge.createOffer();
    const offer = await WebRTCNativeBridge.ensureLocalOffer();
    console.error(`[P2P] offer ready: type=${offer.type}, sdpLen=${(offer.sdp ?? '').length}`);
    const offerMsg = new SignalingOfferMsg(this.sessionId, offer.type ?? 'offer', offer.sdp ?? '');
    this.sendOffer(offerMsg);

    // 不再模拟通道就绪：等待 native 上报 data channel 真正打开（onChannelReady），
    // 否则请求会发向未建立的通道而被丢弃，导致 checkServerStatus 失败。
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
    this.startHeartbeat();
  }

  handleSignalingMessage(msg: SignalingDecoded): void {
    const msgType = msg.type ?? '';
    console.error(`[P2P] signaling msg: ${msgType}`);
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

  private startHeartbeat(): void {
    if (this.heartbeatTimerId !== -1) {
      return;
    }
    this.heartbeatTimerId = setInterval(() => {
      // 对齐 Flutter：每 15s 在所有通道上发 ping 保活
      const ts = Date.now();
      this.channels.forEach((state: ChannelState) => {
        const payload = new P2pControlPayload();
        payload.ts = ts;
        const ping = P2pControlBinary.encodeControl(state.prefix, P2pControlType.PING, payload);
        if (ping) {
          WebRTCNativeBridge.sendBinary(state.handle, ping.buffer as ArrayBuffer);
        }
      });
    }, HEARTBEAT_INTERVAL_MS);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimerId !== -1) {
      clearInterval(this.heartbeatTimerId);
      this.heartbeatTimerId = -1;
    }
  }

  private sendControl(state: ChannelState, type: P2pControlType, payload: P2pControlPayload): boolean {
    const ctrl = P2pControlBinary.encodeControl(state.prefix, type, payload);
    if (!ctrl) {
      return false;
    }
    return WebRTCNativeBridge.sendBinary(state.handle, ctrl.buffer as ArrayBuffer);
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
      this.handleControlMessage(state!, bytes);
    } else {
      this.handleBinaryFrame(state!, bytes);
    }
  }

  /**
   * 控制帧解析，对齐 Flutter _tryDecodeControlBinary / _onChannelMessage。
   * 帧结构：magic(4) + type(1) + payload。
   */
  private handleControlMessage(state: ChannelState, data: Uint8Array): void {
    const mt = data[4];
    const reader = new P2pBinaryReader(data, 5);

    if (mt === P2pControlType.READY) {
      const cbv2 = reader.readVarint() ?? 0;
      state.isReady = true;
      console.error(`[P2P] ${state.prefix} ready: chunkBinaryV2=${cbv2 !== 0}`);
      return;
    }
    if (mt === P2pControlType.PING) {
      // 收到服务端 ping 必须回 pong，否则服务端可能判定通道失活
      const ts = reader.readVarint() ?? 0;
      const payload = new P2pControlPayload();
      payload.ts = ts;
      this.sendControl(state, P2pControlType.PONG, payload);
      return;
    }
    if (mt === P2pControlType.PONG) {
      return;
    }
    if (mt === P2pControlType.RES_BEGIN) {
      // payload: id, status(varint), headers(map), length(varint)
      const id = reader.readString() ?? '';
      if (id.length === 0) {
        console.error(`[P2P] ${state.prefix} res:begin invalid id`);
        return;
      }
      const chunk = new PendingChunk();
      chunk.status = reader.readVarint() ?? 500;
      chunk.headers = reader.readHeaderMap() ?? new HeaderMap();
      chunk.length = reader.readVarint() ?? 0;
      state.pendingChunks.set(id, chunk);
      console.error(`[P2P] ${state.prefix} res:begin id=${id} status=${chunk.status} len=${chunk.length}`);
      return;
    }
    if (mt === P2pControlType.RES_END) {
      const id = reader.readString() ?? '';
      const chunk = state.pendingChunks.get(id);
      if (!chunk) {
        return;
      }
      state.pendingChunks.delete(id);
      this.clearChunkAckTimer(chunk);
      this.flushChunkAck(state, id, chunk);
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
        state.pending.delete(id);
        console.error(`[P2P] ${state.prefix} res done: id=${id} status=${chunk.status} bodyLen=${body.length}`);
        pending.resolve(new P2pApiResponse(chunk.status, chunk.headers, body));
      }
      return;
    }
    if (mt === P2pControlType.ACK) {
      // 服务端对我们发出的请求体回 ack：当前请求体较小，无需流控处理
      return;
    }
    if (mt === P2pControlType.FLOW) {
      return;
    }
    if (mt === P2pControlType.CANCEL) {
      const id = reader.readString() ?? '';
      const chunk = state.pendingChunks.get(id);
      if (chunk) {
        this.clearChunkAckTimer(chunk);
        state.pendingChunks.delete(id);
      }
      const pending = state.pending.get(id);
      if (pending) {
        state.pending.delete(id);
        pending.reject(P2PError.wsError('p2p_req_canceled') as Error);
      }
      return;
    }
  }

  /**
   * 响应体二进制分块帧：[version][idLen][id][payload]，对齐 Flutter _handleBinaryChunk。
   */
  private handleBinaryFrame(state: ChannelState, data: Uint8Array): void {
    if (data.length < 2) {
      return;
    }
    const version = data[0];
    if (version !== P2pBinaryFrame.VERSION_V1 && version !== 0x02) {
      return;
    }
    const idLen = data[1];
    if (idLen <= 0 || data.length < 2 + idLen) {
      return;
    }
    const decoder = new util.TextDecoder();
    const requestId = decoder.decodeToString(data.subarray(2, 2 + idLen));
    const payload = data.subarray(2 + idLen);
    const chunk = state.pendingChunks.get(requestId);
    if (!chunk) {
      return;
    }
    if (payload.length > 0) {
      chunk.chunks.push(payload);
      this.scheduleChunkAck(state, requestId, chunk, payload.length);
    }
  }

  private scheduleChunkAck(state: ChannelState, id: string, chunk: PendingChunk, delta: number): void {
    chunk.ackPendingBytes += delta;
    if (chunk.ackPendingBytes >= ACK_IMMEDIATE_THRESHOLD) {
      this.flushChunkAck(state, id, chunk);
      return;
    }
    if (chunk.ackTimerId === -1) {
      chunk.ackTimerId = setTimeout(() => {
        chunk.ackTimerId = -1;
        if (state.pendingChunks.get(id) === chunk) {
          this.flushChunkAck(state, id, chunk);
        }
      }, ACK_FLUSH_DELAY_MS);
    }
  }

  private flushChunkAck(state: ChannelState, id: string, chunk: PendingChunk): void {
    const delta = chunk.ackPendingBytes;
    if (delta <= 0) {
      return;
    }
    chunk.ackPendingBytes = 0;
    const payload = new P2pControlPayload();
    payload.id = id;
    payload.delta = delta;
    this.sendControl(state, P2pControlType.ACK, payload);
  }

  private clearChunkAckTimer(chunk: PendingChunk): void {
    if (chunk.ackTimerId !== -1) {
      clearTimeout(chunk.ackTimerId);
      chunk.ackTimerId = -1;
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
      pending.method = method;
      pending.path = path;
      state.pending.set(id, pending);

      const sendCtrl = (payload: P2pControlPayload, type: P2pControlType): boolean => {
        const ctrl = P2pControlBinary.encodeControl(state.prefix, type, payload);
        if (!ctrl) {
          return false;
        }
        return WebRTCNativeBridge.sendBinary(state.handle, ctrl.buffer as ArrayBuffer);
      };

      if (bodyBytes.length === 0) {
        // 空请求体：单帧 req（对齐 Flutter sendRequest 空体分支）
        const payload = new P2pControlPayload();
        payload.id = id;
        payload.method = method;
        payload.path = path;
        payload.headers = safeHeaders;
        sendCtrl(payload, P2pControlType.REQ);
        console.error(`[P2P] req: ${method} ${path} id=${id}`);
      } else {
        // 有请求体：req:begin + 二进制分块 + req:end（对齐 Flutter）
        const beginPayload = new P2pControlPayload();
        beginPayload.id = id;
        beginPayload.method = method;
        beginPayload.path = path;
        beginPayload.headers = safeHeaders;
        beginPayload.length = bodyBytes.length;
        sendCtrl(beginPayload, P2pControlType.REQ_BEGIN);

        const header = P2pBinaryFrame.buildHeader(P2pBinaryFrame.VERSION_V1, id);
        for (let offset = 0; offset < bodyBytes.length; offset += BODY_CHUNK_SIZE) {
          const end = Math.min(offset + BODY_CHUNK_SIZE, bodyBytes.length);
          const piece = bodyBytes.subarray(offset, end);
          const packet = new Uint8Array(header.length + piece.length);
          packet.set(header, 0);
          packet.set(piece, header.length);
          WebRTCNativeBridge.sendBinary(state.handle, packet.buffer as ArrayBuffer);
        }

        const endPayload = new P2pControlPayload();
        endPayload.id = id;
        sendCtrl(endPayload, P2pControlType.REQ_END);
        console.error(`[P2P] req(body=${bodyBytes.length}): ${method} ${path} id=${id}`);
      }

      setTimeout(() => {
        const p = state.pending.get(id);
        if (p) {
          state.pending.delete(id);
          const chunk = state.pendingChunks.get(id);
          if (chunk) {
            this.clearChunkAckTimer(chunk);
            state.pendingChunks.delete(id);
          }
          // 超时后通知服务端取消（对齐 Flutter abortLocal）
          const cancelPayload = new P2pControlPayload();
          cancelPayload.id = id;
          sendCtrl(cancelPayload, P2pControlType.REQ_CANCEL);
          console.error(`[P2P] req timeout: ${p.method} ${p.path} id=${id}`);
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
    this.stopHeartbeat();
    if (this.pcHandle >= 0) {
      WebRTCNativeBridge.closePeerConnection(this.pcHandle);
      this.pcHandle = -1;
    }
    this.channels.forEach((state: ChannelState) => {
      state.pending.forEach((p: PendingRequest) => {
        p.reject(P2PError.wsError('p2p_closed') as Error);
      });
      state.pending.clear();
      state.pendingChunks.forEach((chunk: PendingChunk) => {
        this.clearChunkAckTimer(chunk);
      });
      state.pendingChunks.clear();
    });
    this.channels.clear();
  }
}

export class TransportStatsResult {
  type: string = 'relay';
}
