import {
  SIGNAL_MAGIC,
  SIG_PING,
  SIG_PONG,
  SIG_SESSION_READY,
  SIG_SESSION_CLOSED,
  SIG_WEBRTC_OFFER,
  SIG_WEBRTC_ANSWER,
  SIG_WEBRTC_CANDIDATE,
  SIG_ERROR,
} from './constants.js';

// P2P 信令紧凑二进制协议（与 p2pConnectWorker/signalingBinary、remote wsServer 一致）











export function encodeSignalVarint(n) {
  let v = n >= 0 ? n : 0;
  const out = [];
  while (v >= 0x80) {
    out.push((v & 0x7f) | 0x80);
    v >>>= 7;
  }
  out.push(v & 0xff);
  return out;
}

export function decodeSignalVarint(bytes, offset) {
  let shift = 0;
  let result = 0;
  while (offset < bytes.length) {
    const b = bytes[offset] & 0xff;
    offset += 1;
    result |= (b & 0x7f) << shift;
    if ((b & 0x80) === 0) return { value: result, offset };
    shift += 7;
    if (shift > 28) return null;
  }
  return null;
}

export function encodeSignalString(parts, s) {
  const str = s != null ? String(s) : '';
  const enc = new TextEncoder().encode(str);
  parts.push(...encodeSignalVarint(enc.length));
  parts.push(...enc);
}

export function decodeSignalString(bytes, offset) {
  const v = decodeSignalVarint(bytes, offset);
  if (!v) return null;
  const end = v.offset + v.value;
  if (end > bytes.length) return null;
  const slice = bytes.subarray(v.offset, end);
  return { value: new TextDecoder().decode(slice), offset: end };
}

export function encodeSignalMessage(msg) {
  const type = msg && msg.type != null ? String(msg.type) : '';
  const parts = [...SIGNAL_MAGIC];
  let mt;
  if (type === 'ping') mt = SIG_PING;
  else if (type === 'webrtc:offer') mt = SIG_WEBRTC_OFFER;
  else if (type === 'webrtc:candidate') mt = SIG_WEBRTC_CANDIDATE;
  else return null;
  parts.push(mt);
  if (mt === SIG_PING) {
    parts.push(...encodeSignalVarint(Number(msg.ts) || 0));
    return new Uint8Array(parts).buffer;
  }
  if (mt === SIG_WEBRTC_OFFER) {
    encodeSignalString(parts, msg.sessionId || '');
    const o = msg.offer && typeof msg.offer === 'object' ? msg.offer : {};
    encodeSignalString(parts, o.type != null ? o.type : '');
    encodeSignalString(parts, o.sdp != null ? o.sdp : '');
    return new Uint8Array(parts).buffer;
  }
  if (mt === SIG_WEBRTC_CANDIDATE) {
    encodeSignalString(parts, msg.sessionId || '');
    const c = msg.candidate && typeof msg.candidate === 'object' ? msg.candidate : {};
    encodeSignalString(parts, c.candidate != null ? c.candidate : '');
    encodeSignalString(parts, c.sdpMid != null ? c.sdpMid : '');
    parts.push(...encodeSignalVarint(Number(c.sdpMLineIndex) || 0));
    return new Uint8Array(parts).buffer;
  }
  return null;
}

export function decodeSignalMessage(data) {
  if (!data || data.byteLength < 5) return null;
  const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : data;
  if (bytes[0] !== SIGNAL_MAGIC[0] || bytes[1] !== SIGNAL_MAGIC[1] || bytes[2] !== SIGNAL_MAGIC[2] || bytes[3] !== SIGNAL_MAGIC[3]) return null;
  const mt = bytes[4] & 0xff;
  let offset = 5;
  const readStr = () => {
    const r = decodeSignalString(bytes, offset);
    if (!r) return null;
    offset = r.offset;
    return r.value;
  };
  const readVar = () => {
    const r = decodeSignalVarint(bytes, offset);
    if (!r) return null;
    offset = r.offset;
    return r.value;
  };
  if (mt === SIG_PONG) {
    const ts = readVar();
    if (ts == null) return null;
    return { type: 'pong', ts };
  }
  if (mt === SIG_SESSION_READY) {
    const sessionId = readStr();
    const iceJson = readStr();
    if (sessionId == null || iceJson == null) return null;
    let iceServers = [];
    try {
      iceServers = JSON.parse(iceJson);
      if (!Array.isArray(iceServers)) iceServers = [];
    } catch (_) {}
    return { type: 'session:ready', sessionId, iceServers };
  }
  if (mt === SIG_SESSION_CLOSED) {
    const sessionId = readStr();
    readStr();
    if (sessionId == null) return null;
    return { type: 'session:closed', sessionId };
  }
  if (mt === SIG_WEBRTC_ANSWER) {
    const sessionId = readStr();
    const type = readStr();
    const sdp = readStr();
    if (type == null || sdp == null) return null;
    return { type: 'webrtc:answer', sessionId: sessionId || undefined, answer: { type, sdp } };
  }
  if (mt === SIG_WEBRTC_CANDIDATE) {
    const sessionId = readStr();
    const candidate = readStr();
    const sdpMid = readStr();
    const sdpMLineIndex = readVar();
    if (sessionId == null || candidate == null) return null;
    return { type: 'webrtc:candidate', sessionId, candidate: { candidate, sdpMid: sdpMid || '', sdpMLineIndex: sdpMLineIndex != null ? sdpMLineIndex : 0 } };
  }
  if (mt === SIG_ERROR) {
    const code = readStr();
    if (code == null) return null;
    return { type: 'error', code };
  }
  return null;
}
