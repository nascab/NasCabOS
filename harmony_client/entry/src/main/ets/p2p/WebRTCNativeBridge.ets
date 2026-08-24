import nascabWebrtc from 'libnascab_webrtc.so';
import { SdpJson } from '../common/JsonTypes';

export type BinaryMessageHandler = (channelHandle: number, data: ArrayBuffer) => void;
export type ChannelReadyHandler = (channelName: string) => void;

export class WebRTCNativeBridge {
  private static binaryHandler: BinaryMessageHandler | undefined = undefined;
  private static readyHandler: ChannelReadyHandler | undefined = undefined;
  private static initialized: boolean = false;

  static init(onBinary: BinaryMessageHandler, onReady: ChannelReadyHandler): void {
    if (WebRTCNativeBridge.initialized) {
      return;
    }
    WebRTCNativeBridge.binaryHandler = onBinary;
    WebRTCNativeBridge.readyHandler = onReady;
    nascabWebrtc.setOnBinaryMessage((channelHandle: number, data: ArrayBuffer) => {
      if (WebRTCNativeBridge.binaryHandler) {
        WebRTCNativeBridge.binaryHandler(channelHandle, data);
      }
    });
    nascabWebrtc.setOnChannelReady((channelName: string) => {
      if (WebRTCNativeBridge.readyHandler) {
        WebRTCNativeBridge.readyHandler(channelName);
      }
    });
    WebRTCNativeBridge.initialized = true;
  }

  static createPeerConnection(): number {
    return nascabWebrtc.createPeerConnection() as number;
  }

  static createDataChannel(pcHandle: number, label: string): number {
    return nascabWebrtc.createDataChannel(pcHandle, label) as number;
  }

  static sendBinary(channelHandle: number, data: ArrayBuffer): boolean {
    return nascabWebrtc.sendBinary(channelHandle, data) as boolean;
  }

  static createOffer(): SdpJson {
    const raw = nascabWebrtc.createOffer() as SdpJson;
    const offer = new SdpJson();
    offer.type = raw.type ?? 'offer';
    offer.sdp = raw.sdp ?? '';
    return offer;
  }

  static setRemoteDescription(pcHandle: number, type: string, sdp: string): boolean {
    return nascabWebrtc.setRemoteDescription(pcHandle, type, sdp) as boolean;
  }

  static addIceCandidate(pcHandle: number, candidate: string, sdpMid: string, sdpMLineIndex: number): boolean {
    return nascabWebrtc.addIceCandidate(pcHandle, candidate, sdpMid, sdpMLineIndex) as boolean;
  }

  static closePeerConnection(pcHandle: number): void {
    nascabWebrtc.closePeerConnection(pcHandle);
  }

  static simulateChannelReady(channelName: string): void {
    nascabWebrtc.simulateChannelReady(channelName);
  }
}
