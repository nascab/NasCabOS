/**
 * P2P 信令紧凑二进制协议（与 quickshare / remote wsServer 一致）
 * 替代原 JSON 信令，用于 WebSocket 上的 session:ready、webrtc:offer/answer/candidate 等。
 */

const SIGNAL_MAGIC = Buffer.from([0x4e, 0x50, 0x53, 0x01]); // NPS\x01

const TYPE_PING = 0x01;
const TYPE_PONG = 0x02;
const TYPE_SESSION_READY = 0x10;
const TYPE_SESSION_CLOSED = 0x11;
const TYPE_WEBRTC_OFFER = 0x20;
const TYPE_WEBRTC_ANSWER = 0x21;
const TYPE_WEBRTC_CANDIDATE = 0x22;
const TYPE_ERROR = 0x23;
const TYPE_DEVICE_READY = 0x30;
const TYPE_DEVICE_PAIR_CODE = 0x31;
const TYPE_SESSION_CLIENT_CONNECTED = 0x32;
const TYPE_WEBRTC_DEVICE_READY = 0x33;

function encodeVarint(n) {
  let v = BigInt(Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : 0);
  const out = [];
  while (v >= 0x80n) {
    out.push(Number((v & 0x7fn) | 0x80n));
    v >>= 7n;
  }
  out.push(Number(v & 0xffn));
  return Buffer.from(out);
}

function decodeVarint(buf, offset0) {
  let offset = offset0;
  let shift = 0n;
  let out = 0n;
  while (offset < buf.length) {
    const b = BigInt(buf[offset] & 0xff);
    offset += 1;
    out |= (b & 0x7fn) << shift;
    if ((b & 0x80n) === 0n) break;
    shift += 7n;
    if (shift > 63n) return null;
  }
  return { value: Number(out <= BigInt(Number.MAX_SAFE_INTEGER) ? out : BigInt(Number.MAX_SAFE_INTEGER)), offset };
}

function encodeString(s) {
  const text = s == null ? '' : String(s);
  const b = Buffer.from(text, 'utf8');
  return Buffer.concat([encodeVarint(b.length), b]);
}

function decodeString(buf, offset0) {
  const v = decodeVarint(buf, offset0);
  if (!v) return null;
  const len = v.value;
  const end = v.offset + len;
  if (end > buf.length) return null;
  const str = len ? buf.slice(v.offset, end).toString('utf8') : '';
  return { value: str, offset: end };
}

function isSignalingBinary(buf) {
  if (!buf || buf.length < 5) return false;
  return buf[0] === SIGNAL_MAGIC[0] && buf[1] === SIGNAL_MAGIC[1] && buf[2] === SIGNAL_MAGIC[2] && buf[3] === SIGNAL_MAGIC[3];
}

function encodeSignaling(msg) {
  const type = msg && msg.type != null ? String(msg.type) : '';
  const parts = [SIGNAL_MAGIC];
  let mt;
  if (type === 'ping') mt = TYPE_PING;
  else if (type === 'pong') mt = TYPE_PONG;
  else if (type === 'session:ready') mt = TYPE_SESSION_READY;
  else if (type === 'session:closed') mt = TYPE_SESSION_CLOSED;
  else if (type === 'webrtc:offer') mt = TYPE_WEBRTC_OFFER;
  else if (type === 'webrtc:answer') mt = TYPE_WEBRTC_ANSWER;
  else if (type === 'webrtc:candidate') mt = TYPE_WEBRTC_CANDIDATE;
  else if (type === 'error') mt = TYPE_ERROR;
  else if (type === 'device:ready') mt = TYPE_DEVICE_READY;
  else if (type === 'device:pairCode') mt = TYPE_DEVICE_PAIR_CODE;
  else if (type === 'session:client_connected') mt = TYPE_SESSION_CLIENT_CONNECTED;
  else if (type === 'webrtc:device_ready') mt = TYPE_WEBRTC_DEVICE_READY;
  else return null;

  parts.push(Buffer.from([mt]));

  if (mt === TYPE_PING || mt === TYPE_PONG) {
    const ts = Number(msg.ts) || 0;
    parts.push(encodeVarint(ts));
    return Buffer.concat(parts);
  }
  if (mt === TYPE_SESSION_READY) {
    parts.push(encodeString(msg.sessionId || ''));
    const iceJson = Array.isArray(msg.iceServers) ? JSON.stringify(msg.iceServers) : msg.iceServers != null ? String(msg.iceServers) : '[]';
    parts.push(encodeString(iceJson));
    return Buffer.concat(parts);
  }
  if (mt === TYPE_SESSION_CLOSED) {
    parts.push(encodeString(msg.sessionId || ''));
    parts.push(encodeString(msg.reason != null ? String(msg.reason) : ''));
    return Buffer.concat(parts);
  }
  if (mt === TYPE_WEBRTC_OFFER) {
    parts.push(encodeString(msg.sessionId || ''));
    const offer = msg.offer && typeof msg.offer === 'object' ? msg.offer : {};
    parts.push(encodeString(offer.type != null ? String(offer.type) : ''));
    parts.push(encodeString(offer.sdp != null ? String(offer.sdp) : ''));
    return Buffer.concat(parts);
  }
  if (mt === TYPE_WEBRTC_ANSWER) {
    parts.push(encodeString(msg.sessionId != null ? String(msg.sessionId) : ''));
    const answer = msg.answer && typeof msg.answer === 'object' ? msg.answer : {};
    parts.push(encodeString(answer.type != null ? String(answer.type) : ''));
    parts.push(encodeString(answer.sdp != null ? String(answer.sdp) : ''));
    return Buffer.concat(parts);
  }
  if (mt === TYPE_WEBRTC_CANDIDATE) {
    parts.push(encodeString(msg.sessionId || ''));
    const c = msg.candidate && typeof msg.candidate === 'object' ? msg.candidate : {};
    parts.push(encodeString(c.candidate != null ? String(c.candidate) : ''));
    parts.push(encodeString(c.sdpMid != null ? String(c.sdpMid) : ''));
    parts.push(encodeVarint(Number(c.sdpMLineIndex) || 0));
    return Buffer.concat(parts);
  }
  if (mt === TYPE_ERROR) {
    parts.push(encodeString(msg.code != null ? String(msg.code) : ''));
    return Buffer.concat(parts);
  }
  if (mt === TYPE_DEVICE_READY || mt === TYPE_DEVICE_PAIR_CODE) {
    parts.push(encodeString(msg.deviceId != null ? String(msg.deviceId) : ''));
    parts.push(encodeString(msg.serverId != null ? String(msg.serverId) : ''));
    parts.push(encodeString(msg.pairCode != null ? String(msg.pairCode) : ''));
    return Buffer.concat(parts);
  }
  if (mt === TYPE_SESSION_CLIENT_CONNECTED) {
    parts.push(encodeString(msg.sessionId || ''));
    const iceJson = Array.isArray(msg.iceServers) ? JSON.stringify(msg.iceServers) : msg.iceServers != null ? String(msg.iceServers) : '[]';
    parts.push(encodeString(iceJson));
    return Buffer.concat(parts);
  }
  if (mt === TYPE_WEBRTC_DEVICE_READY) {
    parts.push(encodeString(msg.sessionId || ''));
    return Buffer.concat(parts);
  }
  return null;
}

function decodeSignaling(buf) {
  if (!buf || !isSignalingBinary(buf)) return null;
  const mt = buf[4] & 0xff;
  let offset = 5;

  const readStr = () => {
    const r = decodeString(buf, offset);
    if (!r) return null;
    offset = r.offset;
    return r.value;
  };
  const readVar = () => {
    const r = decodeVarint(buf, offset);
    if (!r) return null;
    offset = r.offset;
    return r.value;
  };

  if (mt === TYPE_PING) {
    const ts = readVar();
    if (ts == null) return null;
    return { type: 'ping', ts };
  }
  if (mt === TYPE_PONG) {
    const ts = readVar();
    if (ts == null) return null;
    return { type: 'pong', ts };
  }
  if (mt === TYPE_SESSION_READY) {
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
  if (mt === TYPE_SESSION_CLOSED) {
    const sessionId = readStr();
    const reason = readStr();
    if (sessionId == null) return null;
    return { type: 'session:closed', sessionId, reason: reason || undefined };
  }
  if (mt === TYPE_WEBRTC_OFFER) {
    const sessionId = readStr();
    const type = readStr();
    const sdp = readStr();
    if (sessionId == null || type == null || sdp == null) return null;
    return { type: 'webrtc:offer', sessionId, offer: { type, sdp } };
  }
  if (mt === TYPE_WEBRTC_ANSWER) {
    const sessionId = readStr();
    const type = readStr();
    const sdp = readStr();
    if (type == null || sdp == null) return null;
    return { type: 'webrtc:answer', sessionId: sessionId || undefined, answer: { type, sdp } };
  }
  if (mt === TYPE_WEBRTC_CANDIDATE) {
    const sessionId = readStr();
    const candidate = readStr();
    const sdpMid = readStr();
    const sdpMLineIndex = readVar();
    if (sessionId == null || candidate == null) return null;
    return { type: 'webrtc:candidate', sessionId, candidate: { candidate, sdpMid: sdpMid || '', sdpMLineIndex: sdpMLineIndex != null ? sdpMLineIndex : 0 } };
  }
  if (mt === TYPE_ERROR) {
    const code = readStr();
    if (code == null) return null;
    return { type: 'error', code };
  }
  if (mt === TYPE_DEVICE_READY) {
    const deviceId = readStr();
    const serverId = readStr();
    const pairCode = readStr();
    if (deviceId == null || serverId == null || pairCode == null) return null;
    return { type: 'device:ready', deviceId, serverId, pairCode };
  }
  if (mt === TYPE_DEVICE_PAIR_CODE) {
    const deviceId = readStr();
    const serverId = readStr();
    const pairCode = readStr();
    if (deviceId == null || serverId == null || pairCode == null) return null;
    return { type: 'device:pairCode', deviceId, serverId, pairCode };
  }
  if (mt === TYPE_SESSION_CLIENT_CONNECTED) {
    const sessionId = readStr();
    const iceJson = readStr();
    if (sessionId == null || iceJson == null) return null;
    let iceServers = [];
    try {
      iceServers = JSON.parse(iceJson);
      if (!Array.isArray(iceServers)) iceServers = [];
    } catch (_) {}
    return { type: 'session:client_connected', sessionId, iceServers };
  }
  if (mt === TYPE_WEBRTC_DEVICE_READY) {
    const sessionId = readStr();
    if (sessionId == null) return null;
    return { type: 'webrtc:device_ready', sessionId };
  }
  return null;
}

module.exports = {
  isSignalingBinary,
  encodeSignaling,
  decodeSignaling,
  SIGNAL_MAGIC,
};
