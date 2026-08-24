export interface WebRTCNapi {
  createPeerConnection(): number;
  createDataChannel(pcHandle: number, label: string): number;
  sendBinary(channelHandle: number, data: ArrayBuffer): boolean;
  setOnBinaryMessage(callback: (channelHandle: number, data: ArrayBuffer) => void): void;
  setOnChannelReady(callback: (channelName: string) => void): void;
  createOffer(): Record<string, Object>;
  setRemoteDescription(pcHandle: number, type: string, sdp: string): boolean;
  addIceCandidate(pcHandle: number, candidate: string, sdpMid: string, sdpMLineIndex: number): boolean;
  closePeerConnection(pcHandle: number): void;
  simulateChannelReady(channelName: string): void;
}

declare const nascabWebrtc: WebRTCNapi;
export default nascabWebrtc;
