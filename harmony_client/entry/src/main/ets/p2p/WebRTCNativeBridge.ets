import webrtc from '@ohos/webrtc';
import { SdpJson } from '../common/JsonTypes';

export type BinaryMessageHandler = (channelHandle: number, data: ArrayBuffer) => void;
export type ChannelReadyHandler = (channelName: string) => void;
export type IceCandidateHandler = (candidate: string, sdpMid: string, sdpMLineIndex: number) => void;

interface BridgeChannel {
  label: string;
  dc: webrtc.RTCDataChannel;
}

/**
 * 基于 @ohos/webrtc（OpenHarmony WebRTC 移植）的真实桥接实现，
 * 替换原 stub native 库：对齐 Flutter 端 flutter_webrtc 的能力。
 */
export class WebRTCNativeBridge {
  private static factory: webrtc.PeerConnectionFactory | undefined = undefined;
  private static pcs: Map<number, webrtc.RTCPeerConnection> = new Map();
  private static channels: Map<number, BridgeChannel> = new Map();
  private static nextHandle: number = 1;
  private static lastPcHandle: number = -1;
  private static binaryHandler: BinaryMessageHandler | undefined = undefined;
  private static readyHandler: ChannelReadyHandler | undefined = undefined;
  private static iceHandler: IceCandidateHandler | undefined = undefined;

  static init(onBinary: BinaryMessageHandler, onReady: ChannelReadyHandler): void {
    // 每次初始化都覆盖注册：重连时会创建新的 WebRTCClient，
    // 回调必须始终指向当前客户端实例。
    WebRTCNativeBridge.binaryHandler = onBinary;
    WebRTCNativeBridge.readyHandler = onReady;
    if (!WebRTCNativeBridge.factory) {
      WebRTCNativeBridge.factory = new webrtc.PeerConnectionFactory();
    }
  }

  static setOnIceCandidate(handler: IceCandidateHandler): void {
    WebRTCNativeBridge.iceHandler = handler;
  }

  static createPeerConnection(iceServers: Object[]): number {
    const factory = WebRTCNativeBridge.factory;
    if (!factory) {
      return -1;
    }
    // ICE 服务器传入 WebRTC 栈（对齐 Flutter：RTCPeerConfiguration.iceServers）
    const config: webrtc.RTCConfiguration = {
      iceServers: iceServers as webrtc.RTCIceServer[]
    } as webrtc.RTCConfiguration;
    const pc: webrtc.RTCPeerConnection = factory.createPeerConnection(config);
    const handle = WebRTCNativeBridge.nextHandle++;
    WebRTCNativeBridge.lastPcHandle = handle;
    WebRTCNativeBridge.pcs.set(handle, pc);
    // ICE 候选上行：对齐 Flutter 端 onCandidate -> webrtc:candidate 信令
    pc.onicecandidate = (event: webrtc.RTCPeerConnectionIceEvent) => {
      const c = event.candidate;
      if (c && c.candidate && c.candidate.length > 0) {
        console.error(`[P2P] local candidate: ${(c.candidate ?? '').substring(0, 60)}`);
        WebRTCNativeBridge.iceHandler?.(
          c.candidate,
          c.sdpMid ?? '',
          c.sdpMLineIndex ?? 0
        );
      }
    };
    return handle;
  }

  static createDataChannel(pcHandle: number, label: string): number {
    const pc = WebRTCNativeBridge.pcs.get(pcHandle);
    if (!pc) {
      return -1;
    }
    const dc: webrtc.RTCDataChannel = pc.createDataChannel(label, { negotiated: false });
    const handle = WebRTCNativeBridge.nextHandle++;
    WebRTCNativeBridge.channels.set(handle, { label: label, dc: dc });
    dc.binaryType = 'arraybuffer';
    dc.onopen = () => {
      console.error(`[P2P] channel open: ${label}`);
      WebRTCNativeBridge.readyHandler?.(label);
    };
    dc.onmessage = (ev: webrtc.MessageEvent<Object>) => {
      const data = ev.data as Object;
      if (data instanceof ArrayBuffer) {
        WebRTCNativeBridge.binaryHandler?.(handle, data);
      }
    };
    return handle;
  }

  static sendBinary(channelHandle: number, data: ArrayBuffer): boolean {
    const ch = WebRTCNativeBridge.channels.get(channelHandle);
    if (!ch) {
      return false;
    }
    try {
      ch.dc.send(data);
      return true;
    } catch (_e) {
      return false;
    }
  }

  static createOffer(): SdpJson {
    const pc = WebRTCNativeBridge.pcs.get(WebRTCNativeBridge.lastPcHandle);
    if (!pc) {
      const empty = new SdpJson();
      empty.type = 'offer';
      empty.sdp = '';
      return empty;
    }
    // 同步接口的桥接：createOffer 是异步的，这里用 pending promise 缓存结果，
    // 由 ensureLocalOffer 在发送 offer 前等待完成。
    WebRTCNativeBridge.offerPending = (async (): Promise<SdpJson> => {
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      const out = new SdpJson();
      out.type = offer.type ?? 'offer';
      out.sdp = offer.sdp ?? '';
      return out;
    })();
    const placeholder = new SdpJson();
    placeholder.type = 'offer';
    placeholder.sdp = '';
    return placeholder;
  }

  static offerPending: Promise<SdpJson> | undefined = undefined;

  static async ensureLocalOffer(): Promise<SdpJson> {
    const pending = WebRTCNativeBridge.offerPending;
    WebRTCNativeBridge.offerPending = undefined;
    if (pending) {
      return pending;
    }
    const empty = new SdpJson();
    empty.type = 'offer';
    empty.sdp = '';
    return empty;
  }

  static setRemoteDescription(pcHandle: number, type: string, sdp: string): boolean {
    const pc = WebRTCNativeBridge.pcs.get(pcHandle);
    if (!pc) {
      return false;
    }
    pc.setRemoteDescription({ type: type as webrtc.RTCSdpType, sdp: sdp }).catch(() => {
    });
    return true;
  }

  static addIceCandidate(pcHandle: number, candidate: string, _sdpMid: string, _sdpMLineIndex: number): boolean {
    const pc = WebRTCNativeBridge.pcs.get(pcHandle);
    if (!pc) {
      return false;
    }
    pc.addIceCandidate({ candidate: candidate, sdpMid: _sdpMid, sdpMLineIndex: _sdpMLineIndex }).catch(() => {
    });
    return true;
  }

  static closePeerConnection(pcHandle: number): void {
    const pc = WebRTCNativeBridge.pcs.get(pcHandle);
    if (pc) {
      try {
        pc.close();
      } catch (_e) {
      }
      WebRTCNativeBridge.pcs.delete(pcHandle);
      WebRTCNativeBridge.channels.forEach((ch: BridgeChannel, handle: number) => {
        if (!WebRTCNativeBridge.channels.has(handle)) {
          return;
        }
      });
      WebRTCNativeBridge.channels.clear();
    }
  }
}
