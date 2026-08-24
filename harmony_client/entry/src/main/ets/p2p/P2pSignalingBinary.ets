import { util } from '@kit.ArkTS';
import { IceCandidateJson, SignalingDecoded, SdpJson } from '../common/JsonTypes';

const MAGIC: number[] = [0x4e, 0x50, 0x53, 0x01];
const TYPE_PING = 0x01;
const TYPE_PONG = 0x02;
const TYPE_SESSION_READY = 0x10;
const TYPE_SESSION_CLOSED = 0x11;
const TYPE_WEBRTC_OFFER = 0x20;
const TYPE_WEBRTC_ANSWER = 0x21;
const TYPE_WEBRTC_CANDIDATE = 0x22;
const TYPE_ERROR = 0x23;
const TYPE_WEBRTC_DEVICE_READY = 0x33;

export class SignalingPingMsg {
  type: string = 'ping';
  ts: number = 0;

  constructor(ts: number) {
    this.ts = ts;
  }
}

export class SignalingOfferMsg {
  type: string = 'webrtc:offer';
  sessionId: string = '';
  offer: SdpJson = new SdpJson();

  constructor(sessionId: string, offerType: string, offerSdp: string) {
    this.sessionId = sessionId;
    this.offer.type = offerType;
    this.offer.sdp = offerSdp;
  }
}

function encodeVarint(n: number): Uint8Array {
  let v = n < 0 ? 0 : n;
  const out: number[] = [];
  while (v >= 0x80) {
    out.push((v & 0x7f) | 0x80);
    v >>>= 7;
  }
  out.push(v & 0xff);
  return new Uint8Array(out);
}

function decodeVarint(buf: Uint8Array, offset0: number): VarintResult | undefined {
  let offset = offset0;
  let shift = 0;
  let result = 0;
  while (offset < buf.length) {
    const b = buf[offset] & 0xff;
    offset += 1;
    result |= (b & 0x7f) << shift;
    if ((b & 0x80) === 0) {
      const r = new VarintResult();
      r.value = result;
      r.nextOffset = offset;
      return r;
    }
    shift += 7;
    if (shift > 35) {
      return undefined;
    }
  }
  return undefined;
}

class VarintResult {
  value: number = 0;
  nextOffset: number = 0;
}

function encodeString(s: string): Uint8Array {
  const encoder = new util.TextEncoder();
  const b = encoder.encodeInto(s);
  const len = encodeVarint(b.length);
  const out = new Uint8Array(len.length + b.length);
  out.set(len, 0);
  out.set(b, len.length);
  return out;
}

function decodeString(buf: Uint8Array, offset0: number): StringResult | undefined {
  const v = decodeVarint(buf, offset0);
  if (!v) {
    return undefined;
  }
  const len = v.value;
  let offset = v.nextOffset;
  const end = offset + len;
  if (end > buf.length) {
    return undefined;
  }
  const decoder = new util.TextDecoder();
  const str = len === 0 ? '' : decoder.decodeToString(buf.subarray(offset, end));
  const r = new StringResult();
  r.value = str;
  r.nextOffset = end;
  return r;
}

class StringResult {
  value: string = '';
  nextOffset: number = 0;
}

function appendMagic(parts: number[], mt: number): void {
  for (let i = 0; i < MAGIC.length; i++) {
    parts.push(MAGIC[i]);
  }
  parts.push(mt);
}

function appendBytes(parts: number[], arr: Uint8Array): void {
  for (let i = 0; i < arr.length; i++) {
    parts.push(arr[i]);
  }
}

export class P2pSignalingBinary {
  static isSignalingBinary(buf: Uint8Array): boolean {
    if (buf.length < 5) {
      return false;
    }
    return buf[0] === MAGIC[0] && buf[1] === MAGIC[1] && buf[2] === MAGIC[2] && buf[3] === MAGIC[3];
  }

  static encodePing(ts: number): Uint8Array {
    const parts: number[] = [];
    appendMagic(parts, TYPE_PING);
    appendBytes(parts, encodeVarint(ts));
    return new Uint8Array(parts);
  }

  static encodeOffer(msg: SignalingOfferMsg): Uint8Array {
    const parts: number[] = [];
    appendMagic(parts, TYPE_WEBRTC_OFFER);
    appendBytes(parts, encodeString(msg.sessionId));
    appendBytes(parts, encodeString(msg.offer.type ?? ''));
    appendBytes(parts, encodeString(msg.offer.sdp ?? ''));
    return new Uint8Array(parts);
  }

  static decodeSignaling(buf: Uint8Array): SignalingDecoded | undefined {
    if (buf.length < 5 || !P2pSignalingBinary.isSignalingBinary(buf)) {
      return undefined;
    }
    const mt = buf[4] & 0xff;
    let offset = 5;
    const decoded = new SignalingDecoded();

    if (mt === TYPE_PING) {
      const ts = decodeVarint(buf, offset);
      if (!ts) return undefined;
      decoded.type = 'ping';
      decoded.ts = ts.value;
      return decoded;
    }
    if (mt === TYPE_PONG) {
      const ts = decodeVarint(buf, offset);
      if (!ts) return undefined;
      decoded.type = 'pong';
      decoded.ts = ts.value;
      return decoded;
    }
    if (mt === TYPE_SESSION_READY) {
      const sessionId = decodeString(buf, offset);
      if (!sessionId) return undefined;
      offset = sessionId.nextOffset;
      const iceJson = decodeString(buf, offset);
      if (!iceJson) return undefined;
      decoded.type = 'session:ready';
      decoded.sessionId = sessionId.value;
      try {
        decoded.iceServers = JSON.parse(iceJson.value) as Object[];
      } catch (_e) {
        decoded.iceServers = [];
      }
      return decoded;
    }
    if (mt === TYPE_SESSION_CLOSED) {
      const sessionId = decodeString(buf, offset);
      if (!sessionId) return undefined;
      decoded.type = 'session:closed';
      decoded.sessionId = sessionId.value;
      return decoded;
    }
    if (mt === TYPE_WEBRTC_ANSWER) {
      const sessionId = decodeString(buf, offset);
      if (!sessionId) return undefined;
      offset = sessionId.nextOffset;
      const sdpType = decodeString(buf, offset);
      if (!sdpType) return undefined;
      offset = sdpType.nextOffset;
      const sdp = decodeString(buf, offset);
      if (!sdp) return undefined;
      decoded.type = 'webrtc:answer';
      decoded.sessionId = sessionId.value;
      decoded.answer = new SdpJson();
      decoded.answer.type = sdpType.value;
      decoded.answer.sdp = sdp.value;
      return decoded;
    }
    if (mt === TYPE_WEBRTC_CANDIDATE) {
      const sessionId = decodeString(buf, offset);
      if (!sessionId) return undefined;
      offset = sessionId.nextOffset;
      const candidate = decodeString(buf, offset);
      if (!candidate) return undefined;
      offset = candidate.nextOffset;
      const sdpMid = decodeString(buf, offset);
      if (!sdpMid) return undefined;
      offset = sdpMid.nextOffset;
      const idx = decodeVarint(buf, offset);
      if (!idx) return undefined;
      decoded.type = 'webrtc:candidate';
      decoded.sessionId = sessionId.value;
      const cand = new IceCandidateJson();
      cand.candidate = candidate.value;
      cand.sdpMid = sdpMid.value;
      cand.sdpMLineIndex = idx.value;
      decoded.candidate = cand;
      return decoded;
    }
    if (mt === TYPE_ERROR) {
      const code = decodeString(buf, offset);
      if (!code) return undefined;
      decoded.type = 'error';
      decoded.code = code.value;
      return decoded;
    }
    if (mt === TYPE_WEBRTC_DEVICE_READY) {
      const sessionId = decodeString(buf, offset);
      if (!sessionId) return undefined;
      decoded.type = 'webrtc:device_ready';
      decoded.sessionId = sessionId.value;
      return decoded;
    }
    return undefined;
  }
}
