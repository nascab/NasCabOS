import {
  NPC_MAGIC,
  NPC_TYPE_READY,
  NPC_TYPE_PING,
  NPC_TYPE_PONG,
  NPC_TYPE_REQ,
  NPC_TYPE_REQ_BEGIN,
  NPC_TYPE_REQ_END,
  NPC_TYPE_REQ_CANCEL,
  NPC_TYPE_CANCEL,
  NPC_TYPE_RES_BEGIN,
  NPC_TYPE_RES_END,
  NPC_TYPE_FLOW,
  NPC_TYPE_RES,
  NPC_TYPE_ACK,
} from './constants.js';
import {
  qsbWriteVarint,
  qsbReadVarint,
  qsbWriteString,
  qsbReadString,
  qsbReadBool,
  qsbConcat,
} from './qsb-codec.js';

export function npcWriteVarint(parts, value) {
  qsbWriteVarint(parts, value);
}
export function npcReadVarint(bytes, offset0) {
  return qsbReadVarint(bytes, offset0);
}
export function npcWriteString(parts, s) {
  qsbWriteString(parts, s);
}
export function npcReadString(bytes, offset0) {
  return qsbReadString(bytes, offset0);
}
export function npcWriteBool(parts, b) {
  parts.push(new Uint8Array([b ? 1 : 0]));
}
export function npcReadBool(bytes, offset0) {
  return qsbReadBool(bytes, offset0);
}
export function npcWriteBytes(parts, bytes) {
  const b = bytes instanceof Uint8Array ? bytes : bytes ? new Uint8Array(bytes) : new Uint8Array(0);
  npcWriteVarint(parts, b.length);
  if (b.length) parts.push(b);
}
export function npcReadBytes(bytes, offset0) {
  const v = npcReadVarint(bytes, offset0);
  if (!v) return null;
  const len = v.value;
  let offset = v.offset;
  const end = offset + len;
  if (end > bytes.length) return null;
  const out = len ? bytes.subarray(offset, end) : new Uint8Array(0);
  return { value: out, offset: end };
}
export function npcWriteMap(parts, m) {
  const obj = m && typeof m === 'object' ? m : {};
  const entries = Object.entries(obj).filter(([k]) => k != null && String(k));
  npcWriteVarint(parts, entries.length);
  for (const [k, v] of entries) {
    npcWriteString(parts, k);
    npcWriteString(parts, v);
  }
}
export function npcReadMap(bytes, offset0) {
  const n = npcReadVarint(bytes, offset0);
  if (!n) return null;
  let offset = n.offset;
  const out = {};
  for (let i = 0; i < n.value; i++) {
    const k = npcReadString(bytes, offset);
    if (!k) return null;
    offset = k.offset;
    const v = npcReadString(bytes, offset);
    if (!v) return null;
    offset = v.offset;
    if (k.value) out[k.value] = v.value;
  }
  return { value: out, offset };
}

export function isNpc(bytes) {
  return bytes && bytes.length >= 5 && bytes[0] === NPC_MAGIC[0] && bytes[1] === NPC_MAGIC[1] && bytes[2] === NPC_MAGIC[2] && bytes[3] === NPC_MAGIC[3];
}

export function npcEncode(prefix, msg) {
  const type = msg && msg.type != null ? String(msg.type) : '';
  if (!type || !type.startsWith(`${prefix}:`)) return null;
  const suffix = type.slice(prefix.length + 1);
  let mt = null;
  if (suffix === 'ready') mt = NPC_TYPE_READY;
  else if (suffix === 'ping') mt = NPC_TYPE_PING;
  else if (suffix === 'pong') mt = NPC_TYPE_PONG;
  else if (suffix === 'req') mt = NPC_TYPE_REQ;
  else if (suffix === 'req:begin') mt = NPC_TYPE_REQ_BEGIN;
  else if (suffix === 'req:end') mt = NPC_TYPE_REQ_END;
  else if (suffix === 'req:cancel') mt = NPC_TYPE_REQ_CANCEL;
  else if (suffix === 'cancel') mt = NPC_TYPE_CANCEL;
  else if (suffix === 'res') mt = NPC_TYPE_RES;
  else if (suffix === 'res:begin') mt = NPC_TYPE_RES_BEGIN;
  else if (suffix === 'res:end') mt = NPC_TYPE_RES_END;
  else if (suffix === 'flow') mt = NPC_TYPE_FLOW;
  else if (suffix === 'ack') mt = NPC_TYPE_ACK;
  else return null;

  const parts = [NPC_MAGIC, new Uint8Array([mt])];

  if (mt === NPC_TYPE_PING || mt === NPC_TYPE_PONG) {
    npcWriteVarint(parts, msg.ts);
    return qsbConcat(parts);
  }

  if (mt === NPC_TYPE_REQ_END || mt === NPC_TYPE_REQ_CANCEL || mt === NPC_TYPE_CANCEL || mt === NPC_TYPE_RES_END) {
    npcWriteString(parts, msg.id);
    return qsbConcat(parts);
  }

  if (mt === NPC_TYPE_ACK) {
    npcWriteString(parts, msg.id);
    npcWriteVarint(parts, msg.delta);
    return qsbConcat(parts);
  }

  if (mt === NPC_TYPE_FLOW) {
    npcWriteString(parts, msg.id);
    npcWriteString(parts, msg.action);
    return qsbConcat(parts);
  }

  if (mt === NPC_TYPE_READY) {
    const f = msg && msg.features && typeof msg.features === 'object' ? msg.features : {};
    // 与 p2pConnectWorker 一致：仅 chunkBinaryV2，无 chunkEncoding / 压缩协商
    npcWriteVarint(parts, f.chunkBinaryV2 ? 1 : 0);
    return qsbConcat(parts);
  }

  if (mt === NPC_TYPE_REQ || mt === NPC_TYPE_REQ_BEGIN) {
    npcWriteString(parts, msg.id);
    npcWriteString(parts, msg.method);
    npcWriteString(parts, msg.path);
    npcWriteMap(parts, msg.headers);
    if (mt === NPC_TYPE_REQ_BEGIN) {
      npcWriteVarint(parts, msg.length);
    }
    return qsbConcat(parts);
  }

  if (mt === NPC_TYPE_RES_BEGIN) {
    npcWriteString(parts, msg.id);
    npcWriteVarint(parts, msg.status);
    npcWriteMap(parts, msg.headers);
    npcWriteVarint(parts, msg.length);
    return qsbConcat(parts);
  }

  if (mt === NPC_TYPE_RES) {
    npcWriteString(parts, msg.id);
    npcWriteVarint(parts, msg.status);
    npcWriteMap(parts, msg.headers);
    npcWriteBytes(parts, msg.bodyBytes);
    return qsbConcat(parts);
  }

  return null;
}

export function npcDecode(prefix, bytes) {
  if (!isNpc(bytes)) return null;
  const mt = bytes[4] & 0xff;
  let offset = 5;
  const readVar = () => {
    const v = npcReadVarint(bytes, offset);
    if (!v) return null;
    offset = v.offset;
    return v.value;
  };
  const readStr = () => {
    const s = npcReadString(bytes, offset);
    if (!s) return null;
    offset = s.offset;
    return s.value;
  };
  const readMap = () => {
    const m = npcReadMap(bytes, offset);
    if (!m) return null;
    offset = m.offset;
    return m.value;
  };
  const readBytes = () => {
    const b = npcReadBytes(bytes, offset);
    if (!b) return null;
    offset = b.offset;
    return b.value;
  };
  if (mt === NPC_TYPE_PING || mt === NPC_TYPE_PONG) {
    const ts = readVar();
    if (ts == null) return null;
    return { type: `${prefix}:${mt === NPC_TYPE_PING ? 'ping' : 'pong'}`, ts };
  }

  if (mt === NPC_TYPE_REQ_END || mt === NPC_TYPE_REQ_CANCEL || mt === NPC_TYPE_CANCEL || mt === NPC_TYPE_RES_END) {
    const id = readStr();
    if (id == null) return null;
    let suffix = '';
    if (mt === NPC_TYPE_REQ_END) suffix = 'req:end';
    if (mt === NPC_TYPE_REQ_CANCEL) suffix = 'req:cancel';
    if (mt === NPC_TYPE_CANCEL) suffix = 'cancel';
    if (mt === NPC_TYPE_RES_END) suffix = 'res:end';
    return { type: `${prefix}:${suffix}`, id };
  }

  if (mt === NPC_TYPE_ACK) {
    const id = readStr();
    const delta = readVar();
    if (id == null || delta == null) return null;
    return { type: `${prefix}:ack`, id, delta };
  }

  if (mt === NPC_TYPE_FLOW) {
    const id = readStr();
    const action = readStr();
    if (id == null || action == null) return null;
    return { type: `${prefix}:flow`, id, action };
  }

  if (mt === NPC_TYPE_READY) {
    const cbv2 = readVar();
    if (cbv2 == null || offset !== bytes.length) return null;
    return { type: `${prefix}:ready`, features: { chunkBinaryV2: !!cbv2 } };
  }

  if (mt === NPC_TYPE_REQ || mt === NPC_TYPE_REQ_BEGIN) {
    const id = readStr();
    const method = readStr();
    const path = readStr();
    const headers = readMap();
    if (id == null || method == null || path == null || headers == null) return null;
    if (mt === NPC_TYPE_REQ_BEGIN) {
      const length = readVar();
      if (length == null || offset !== bytes.length) return null;
      return { type: `${prefix}:req:begin`, id, method, path, headers, length };
    }
    if (offset !== bytes.length) return null;
    return { type: `${prefix}:req`, id, method, path, headers };
  }

  if (mt === NPC_TYPE_RES_BEGIN) {
    const id = readStr();
    const status = readVar();
    const headers = readMap();
    const length = readVar();
    if (id == null || status == null || headers == null || length == null || offset !== bytes.length) return null;
    return { type: `${prefix}:res:begin`, id, status, headers, length };
  }

  if (mt === NPC_TYPE_RES) {
    const id = readStr();
    const status = readVar();
    const headers = readMap();
    const bodyBytes = readBytes();
    if (id == null || status == null || headers == null || bodyBytes == null) return null;
    return { type: `${prefix}:res`, id, status, headers, bodyBytes };
  }

  return null;
}
