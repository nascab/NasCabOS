const { P2P_PROXY_MAX_REQ_BODY_BYTES, P2P_PROXY_REQ_TIMEOUT_MS, P2P_PROXY_MAX_PENDING_REQ, P2P_PROXY_MAX_PENDING_STREAMS, P2P_PROXY_MAX_CONCURRENT } = require('./constants');

function attachDataChannel({ sessionId, dc, pc, webrtcManager, proxyPendingStore, localExpressProxy, wsImpl }) {
  const sid = sessionId == null ? '' : String(sessionId);
  if (!sid || !dc) return;
  const s = webrtcManager.getSession(sid);
  if (!s || !s.pc) return;
  if (pc && s.pc !== pc) return;
  const labelRaw = dc.label ? String(dc.label) : '';
  const label = labelRaw && labelRaw.trim() ? labelRaw.trim() : 'api';
  const prefix = label;
  webrtcManager.registerDataChannel(sid, label, dc);

  const pendingReqBodies = proxyPendingStore.getPendingReqBodies(sid, prefix);
  const pendingStreams = proxyPendingStore.getPendingStreams(sid, prefix);
  const pendingInFlightReqs = new Map();
  const cancelledReqIds = new Set();
  const wsTunnels = new Map();
  const dropPendingReq = (id, status, msg) => {
    const st = pendingReqBodies.get(id);
    if (st) {
      pendingReqBodies.delete(id);
      try {
        if (st.timeoutId) clearTimeout(st.timeoutId);
      } catch (_) {}
    }
    sendResSmall({ id, status, headers: { 'content-type': 'application/json' }, bodyText: JSON.stringify({ code: -1, message: msg }) });
  };

  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const isHighPriorityPrefix = p => p === 'api' || p === 'file';
  const isBulkPrefix = p => p === 'download' || p === 'upload' || p === 'video';
  const isVideoPrefix = p => p === 'video';
  const isLowPriorityPrefix = p => p === 'download' || p === 'upload';
  const getSessionPriorityState = () => {
    const cur = webrtcManager.getSession ? webrtcManager.getSession(sid) : null;
    if (!cur) return null;
    if (!cur.p2pPriorityState || typeof cur.p2pPriorityState !== 'object') {
      cur.p2pPriorityState = {
        highPriorityInFlight: 0,
        videoPriorityInFlight: 0,
        lastTouchMs: Date.now(),
      };
    }
    return cur.p2pPriorityState;
  };
  const enterHighPriority = () => {
    if (!isHighPriorityPrefix(prefix)) return;
    const st = getSessionPriorityState();
    if (!st) return;
    st.highPriorityInFlight = (Number(st.highPriorityInFlight) || 0) + 1;
    st.lastTouchMs = Date.now();
  };
  const leaveHighPriority = () => {
    if (!isHighPriorityPrefix(prefix)) return;
    const st = getSessionPriorityState();
    if (!st) return;
    st.highPriorityInFlight = Math.max(
      0,
      (Number(st.highPriorityInFlight) || 0) - 1
    );
    st.lastTouchMs = Date.now();
  };
  const enterVideoPriority = () => {
    if (!isVideoPrefix(prefix)) return;
    const st = getSessionPriorityState();
    if (!st) return;
    st.videoPriorityInFlight = (Number(st.videoPriorityInFlight) || 0) + 1;
    st.lastTouchMs = Date.now();
  };
  const leaveVideoPriority = () => {
    if (!isVideoPrefix(prefix)) return;
    const st = getSessionPriorityState();
    if (!st) return;
    st.videoPriorityInFlight = Math.max(
      0,
      (Number(st.videoPriorityInFlight) || 0) - 1
    );
    st.lastTouchMs = Date.now();
  };
  const hasHighPriorityContention = () => {
    if (isHighPriorityPrefix(prefix)) return false;
    if (!isBulkPrefix(prefix)) return false;
    const st = getSessionPriorityState();
    if (!st) return false;
    return (Number(st.highPriorityInFlight) || 0) > 0;
  };
  const hasVideoPriorityContention = () => {
    if (!isLowPriorityPrefix(prefix)) return false;
    const st = getSessionPriorityState();
    if (!st) return false;
    return (Number(st.videoPriorityInFlight) || 0) > 0;
  };

  const getBufferedAmount = dc0 => {
    if (!dc0) return 0;
    try {
      if (typeof dc0.bufferedAmount === 'number') return dc0.bufferedAmount;
      if (typeof dc0.bufferedAmount === 'function') return Number(dc0.bufferedAmount());
    } catch (_) {}
    return 0;
  };

  const drainLimitBytes = () => {
    const tk = webrtcManager.getTransportKind(sid) || '';
    const isRelay = tk === '中继';
    if (hasHighPriorityContention()) {
      // 强偏向 API/file：bulk 通道在高优先级竞争时显著收紧发送缓存窗口
      return isRelay ? 64 * 1024 : 128 * 1024;
    }
    if (hasVideoPriorityContention()) {
      // video 优先于 download/upload
      return isRelay ? 96 * 1024 : 192 * 1024;
    }
    if (isRelay && prefix === 'download') return 2 * 1024 * 1024;
    if (isRelay && prefix === 'api') return 512 * 1024;
    return 16 * 1024 * 1024;
  };

  let dcClosedForSend = false;
  const sendQueue = [];

  const P2P_CTRL_MAGIC = Buffer.from([0x4e, 0x50, 0x43, 0x01]);
  const P2P_CTRL_TYPE_READY = 0x01;
  const P2P_CTRL_TYPE_PING = 0x02;
  const P2P_CTRL_TYPE_PONG = 0x03;
  const P2P_CTRL_TYPE_REQ = 0x10;
  const P2P_CTRL_TYPE_REQ_BEGIN = 0x11;
  const P2P_CTRL_TYPE_REQ_END = 0x12;
  const P2P_CTRL_TYPE_REQ_CANCEL = 0x13;
  const P2P_CTRL_TYPE_CANCEL = 0x14;
  const P2P_CTRL_TYPE_RES_BEGIN = 0x20;
  const P2P_CTRL_TYPE_RES_END = 0x21;
  const P2P_CTRL_TYPE_FLOW = 0x22;
  const P2P_CTRL_TYPE_RES = 0x23;
  const P2P_CTRL_TYPE_ACK = 0x30;
  const P2P_CTRL_TYPE_WS_OPEN = 0x40;
  const P2P_CTRL_TYPE_WS_SEND = 0x41;
  const P2P_CTRL_TYPE_WS_CLOSE = 0x42;
  const P2P_CTRL_TYPE_WS_OPEN_OK = 0x43;
  const P2P_CTRL_TYPE_WS_OPEN_ERROR = 0x44;
  const P2P_CTRL_TYPE_WS_MESSAGE = 0x45;
  const P2P_CTRL_TYPE_WS_ERROR = 0x46;

  const isControlBinary = buf => {
    if (!buf || buf.length < 5) return false;
    return buf[0] === P2P_CTRL_MAGIC[0] && buf[1] === P2P_CTRL_MAGIC[1] && buf[2] === P2P_CTRL_MAGIC[2] && buf[3] === P2P_CTRL_MAGIC[3];
  };

  const encodeVarint = n => {
    let v;
    try {
      if (typeof n === 'bigint') v = n;
      else v = BigInt(Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : 0);
    } catch (_) {
      v = 0n;
    }
    const out = [];
    while (v >= 0x80n) {
      out.push(Number((v & 0x7fn) | 0x80n));
      v >>= 7n;
    }
    out.push(Number(v & 0xffn));
    return Buffer.from(out);
  };

  const decodeVarint = (buf, offset0) => {
    let offset = offset0;
    let shift = 0n;
    let out = 0n;
    while (true) {
      if (offset >= buf.length) return null;
      const b = BigInt(buf[offset] & 0xff);
      offset += 1;
      out |= (b & 0x7fn) << shift;
      if ((b & 0x80n) === 0n) break;
      shift += 7n;
      if (shift > 63n) return null;
    }
    const num = out <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(out) : Number.MAX_SAFE_INTEGER;
    return { value: num, offset };
  };

  const encodeString = s => {
    const text = s == null ? '' : String(s);
    if (!text) return Buffer.from([0x00]);
    const b = Buffer.from(text, 'utf8');
    return Buffer.concat([encodeVarint(b.length), b]);
  };

  const encodeBytes = raw => {
    const b = raw && Buffer.isBuffer(raw) ? raw : raw ? Buffer.from(raw) : Buffer.alloc(0);
    return Buffer.concat([encodeVarint(b.length), b]);
  };

  const decodeString = (buf, offset0) => {
    const v = decodeVarint(buf, offset0);
    if (!v) return null;
    const len = v.value;
    let offset = v.offset;
    const end = offset + len;
    if (end > buf.length) return null;
    const s = len ? buf.slice(offset, end).toString('utf8') : '';
    return { value: s, offset: end };
  };

  const decodeBytes = (buf, offset0) => {
    const v = decodeVarint(buf, offset0);
    if (!v) return null;
    const len = v.value;
    let offset = v.offset;
    const end = offset + len;
    if (end > buf.length) return null;
    const out = len ? buf.slice(offset, end) : Buffer.alloc(0);
    return { value: out, offset: end };
  };

  const encodeMapStrStr = obj => {
    const m = obj && typeof obj === 'object' ? obj : {};
    const entries = Object.entries(m).filter(([k]) => k != null && String(k));
    const parts = [encodeVarint(entries.length)];
    for (const [k, v] of entries) {
      parts.push(encodeString(k));
      parts.push(encodeString(v));
    }
    return Buffer.concat(parts);
  };

  const decodeMapStrStr = (buf, offset0) => {
    const v = decodeVarint(buf, offset0);
    if (!v) return null;
    const count = v.value;
    let offset = v.offset;
    const out = {};
    for (let i = 0; i < count; i++) {
      const k = decodeString(buf, offset);
      if (!k) return null;
      const v2 = decodeString(buf, k.offset);
      if (!v2) return null;
      offset = v2.offset;
      if (k.value) out[String(k.value)] = String(v2.value);
    }
    return { value: out, offset };
  };

  const encodeControlBinary = obj => {
    const t = obj && obj.type != null ? String(obj.type) : '';
    if (!t || !t.startsWith(`${prefix}:`)) return null;
    const suffix = t.slice(prefix.length + 1);

    let mt = null;
    if (suffix === 'ping') mt = P2P_CTRL_TYPE_PING;
    else if (suffix === 'pong') mt = P2P_CTRL_TYPE_PONG;
    else if (suffix === 'ready') mt = P2P_CTRL_TYPE_READY;
    else if (suffix === 'req') mt = P2P_CTRL_TYPE_REQ;
    else if (suffix === 'req:begin') mt = P2P_CTRL_TYPE_REQ_BEGIN;
    else if (suffix === 'req:end') mt = P2P_CTRL_TYPE_REQ_END;
    else if (suffix === 'req:cancel') mt = P2P_CTRL_TYPE_REQ_CANCEL;
    else if (suffix === 'cancel') mt = P2P_CTRL_TYPE_CANCEL;
    else if (suffix === 'res') mt = P2P_CTRL_TYPE_RES;
    else if (suffix === 'res:begin') mt = P2P_CTRL_TYPE_RES_BEGIN;
    else if (suffix === 'res:end') mt = P2P_CTRL_TYPE_RES_END;
    else if (suffix === 'flow') mt = P2P_CTRL_TYPE_FLOW;
    else if (suffix === 'ack') mt = P2P_CTRL_TYPE_ACK;
    else if (suffix === 'ws:open') mt = P2P_CTRL_TYPE_WS_OPEN;
    else if (suffix === 'ws:send') mt = P2P_CTRL_TYPE_WS_SEND;
    else if (suffix === 'ws:close') mt = P2P_CTRL_TYPE_WS_CLOSE;
    else if (suffix === 'ws:open:ok') mt = P2P_CTRL_TYPE_WS_OPEN_OK;
    else if (suffix === 'ws:open:error') mt = P2P_CTRL_TYPE_WS_OPEN_ERROR;
    else if (suffix === 'ws:message') mt = P2P_CTRL_TYPE_WS_MESSAGE;
    else if (suffix === 'ws:error') mt = P2P_CTRL_TYPE_WS_ERROR;
    else return null;

    const parts = [P2P_CTRL_MAGIC, Buffer.from([mt])];

    if (mt === P2P_CTRL_TYPE_PING || mt === P2P_CTRL_TYPE_PONG) {
      parts.push(encodeVarint(obj.ts));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_REQ_END || mt === P2P_CTRL_TYPE_REQ_CANCEL || mt === P2P_CTRL_TYPE_CANCEL || mt === P2P_CTRL_TYPE_RES_END) {
      parts.push(encodeString(obj.id));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_ACK) {
      parts.push(encodeString(obj.id));
      parts.push(encodeVarint(obj.delta));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_FLOW) {
      parts.push(encodeString(obj.id));
      parts.push(encodeString(obj.action));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_REQ || mt === P2P_CTRL_TYPE_REQ_BEGIN) {
      parts.push(encodeString(obj.id));
      parts.push(encodeString(obj.method));
      parts.push(encodeString(obj.path));
      parts.push(encodeMapStrStr(obj.headers));
      if (mt === P2P_CTRL_TYPE_REQ_BEGIN) {
        parts.push(encodeVarint(obj.length));
      }
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_RES_BEGIN) {
      parts.push(encodeString(obj.id));
      parts.push(encodeVarint(obj.status));
      parts.push(encodeMapStrStr(obj.headers));
      parts.push(encodeVarint(obj.length));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_RES) {
      parts.push(encodeString(obj.id));
      parts.push(encodeVarint(obj.status));
      parts.push(encodeMapStrStr(obj.headers));
      const body = obj && obj.bodyBytes != null ? obj.bodyBytes : obj && obj.bodyBuf != null ? obj.bodyBuf : Buffer.alloc(0);
      parts.push(encodeBytes(body));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_WS_OPEN) {
      parts.push(encodeString(obj.id));
      parts.push(encodeString(obj.path));
      parts.push(encodeMapStrStr(obj.headers));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_WS_SEND) {
      parts.push(encodeString(obj.id));
      parts.push(encodeString(obj.data));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_WS_CLOSE) {
      parts.push(encodeString(obj.id));
      parts.push(encodeVarint(obj.code));
      parts.push(encodeString(obj.reason));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_WS_OPEN_OK) {
      parts.push(encodeString(obj.id));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_WS_OPEN_ERROR) {
      parts.push(encodeString(obj.id));
      parts.push(encodeString(obj.error));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_WS_MESSAGE) {
      parts.push(encodeString(obj.id));
      parts.push(encodeString(obj.data));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_WS_ERROR) {
      parts.push(encodeString(obj.id));
      parts.push(encodeString(obj.error));
      return Buffer.concat(parts);
    }

    if (mt === P2P_CTRL_TYPE_READY) {
      const features = obj && obj.features && typeof obj.features === 'object' ? obj.features : {};
      parts.push(encodeVarint(features.chunkBinaryV2 ? 1 : 0));
      return Buffer.concat(parts);
    }

    return null;
  };

  const decodeControlBinary = buf => {
    if (!isControlBinary(buf)) return null;
    const mt = buf[4] & 0xff;
    let offset = 5;

    const readVar = () => {
      const v = decodeVarint(buf, offset);
      if (!v) return null;
      offset = v.offset;
      return v.value;
    };
    const readStr = () => {
      const s = decodeString(buf, offset);
      if (!s) return null;
      offset = s.offset;
      return s.value;
    };
    const readMap = () => {
      const m = decodeMapStrStr(buf, offset);
      if (!m) return null;
      offset = m.offset;
      return m.value;
    };
    const readBytes = () => {
      const b = decodeBytes(buf, offset);
      if (!b) return null;
      offset = b.offset;
      return b.value;
    };
    if (mt === P2P_CTRL_TYPE_PING || mt === P2P_CTRL_TYPE_PONG) {
      const ts = readVar();
      if (ts == null) return null;
      return { type: `${prefix}:${mt === P2P_CTRL_TYPE_PING ? 'ping' : 'pong'}`, ts };
    }

    if (mt === P2P_CTRL_TYPE_REQ_END || mt === P2P_CTRL_TYPE_REQ_CANCEL || mt === P2P_CTRL_TYPE_CANCEL || mt === P2P_CTRL_TYPE_RES_END) {
      const id = readStr();
      if (id == null) return null;
      let suffix = '';
      if (mt === P2P_CTRL_TYPE_REQ_END) suffix = 'req:end';
      if (mt === P2P_CTRL_TYPE_REQ_CANCEL) suffix = 'req:cancel';
      if (mt === P2P_CTRL_TYPE_CANCEL) suffix = 'cancel';
      if (mt === P2P_CTRL_TYPE_RES_END) suffix = 'res:end';
      return { type: `${prefix}:${suffix}`, id };
    }

    if (mt === P2P_CTRL_TYPE_ACK) {
      const id = readStr();
      const delta = readVar();
      if (id == null || delta == null) return null;
      return { type: `${prefix}:ack`, id, delta };
    }

    if (mt === P2P_CTRL_TYPE_FLOW) {
      const id = readStr();
      const action = readStr();
      if (id == null || action == null) return null;
      return { type: `${prefix}:flow`, id, action };
    }

    if (mt === P2P_CTRL_TYPE_REQ || mt === P2P_CTRL_TYPE_REQ_BEGIN) {
      const id = readStr();
      const method = readStr();
      const path = readStr();
      const headers = readMap();
      if (id == null || method == null || path == null || headers == null) return null;
      if (mt === P2P_CTRL_TYPE_REQ_BEGIN) {
        const length = readVar();
        if (length == null) return null;
        return { type: `${prefix}:req:begin`, id, method, path, headers, length };
      }
      return { type: `${prefix}:req`, id, method, path, headers };
    }

    if (mt === P2P_CTRL_TYPE_RES_BEGIN) {
      const id = readStr();
      const status = readVar();
      const headers = readMap();
      const length = readVar();
      if (id == null || status == null || headers == null || length == null) return null;
      return { type: `${prefix}:res:begin`, id, status, headers, length };
    }

    if (mt === P2P_CTRL_TYPE_RES) {
      const id = readStr();
      const status = readVar();
      const headers = readMap();
      const bodyBytes = readBytes();
      if (id == null || status == null || headers == null || bodyBytes == null) return null;
      return { type: `${prefix}:res`, id, status, headers, bodyBytes };
    }

    if (mt === P2P_CTRL_TYPE_WS_OPEN) {
      const id = readStr();
      const path = readStr();
      const headers = readMap();
      if (id == null || path == null || headers == null) return null;
      return { type: `${prefix}:ws:open`, id, path, headers };
    }

    if (mt === P2P_CTRL_TYPE_WS_SEND) {
      const id = readStr();
      const data = readStr();
      if (id == null || data == null) return null;
      return { type: `${prefix}:ws:send`, id, data };
    }

    if (mt === P2P_CTRL_TYPE_WS_CLOSE) {
      const id = readStr();
      const code = readVar();
      const reason = readStr();
      if (id == null || code == null || reason == null) return null;
      const out = { type: `${prefix}:ws:close`, id };
      if (code > 0) out.code = code;
      if (reason) out.reason = reason;
      return out;
    }

    if (mt === P2P_CTRL_TYPE_WS_OPEN_OK) {
      const id = readStr();
      if (id == null) return null;
      return { type: `${prefix}:ws:open:ok`, id };
    }

    if (mt === P2P_CTRL_TYPE_WS_OPEN_ERROR) {
      const id = readStr();
      const error = readStr();
      if (id == null || error == null) return null;
      return { type: `${prefix}:ws:open:error`, id, error };
    }

    if (mt === P2P_CTRL_TYPE_WS_MESSAGE) {
      const id = readStr();
      const data = readStr();
      if (id == null || data == null) return null;
      return { type: `${prefix}:ws:message`, id, data };
    }

    if (mt === P2P_CTRL_TYPE_WS_ERROR) {
      const id = readStr();
      const error = readStr();
      if (id == null || error == null) return null;
      return { type: `${prefix}:ws:error`, id, error };
    }

    if (mt === P2P_CTRL_TYPE_READY) {
      const chunkBinaryV2 = readVar();
      if (chunkBinaryV2 == null) return null;
      return { type: `${prefix}:ready`, features: { chunkBinaryV2: !!chunkBinaryV2 } };
    }

    return null;
  };

  const sendMessage = obj => {
    if (dcClosedForSend || !dc) return Promise.resolve(false);
    const bin = encodeControlBinary(obj);
    if (!bin || !bin.length) return Promise.resolve(false);
    try {
      dc.send(bin);
      return Promise.resolve(true);
    } catch (_) {
      return Promise.resolve(false);
    }
  };

  const sendBinary = async (packet, id) => {
    if (dcClosedForSend || !dc) return false;
    const limit = drainLimitBytes();
    while (getBufferedAmount(dc) > limit) {
      if (id != null && cancelledReqIds.has(id)) return false;
      await sleep(5);
      if (dcClosedForSend) return false;
    }
    if (id != null && cancelledReqIds.has(id)) return false;
    try {
      dc.send(packet);
      return true;
    } catch (_) {
      return false;
    }
  };

  const sendResChunkBinary = async ({ id, chunk }) => {
    if (!chunk || !chunk.length) return true;
    const idBuf = Buffer.from(String(id), 'utf8');
    const idLen = idBuf.length;
    if (idLen > 255) return false;
    const header = Buffer.alloc(2 + idLen);
    header[0] = 0x01;
    header[1] = idLen;
    idBuf.copy(header, 2);
    const packet = Buffer.concat([header, chunk]);
    return await sendBinary(packet, id);
  };

  const normalizeWsHeaders = headers => {
    const out = {};
    const src = headers && typeof headers === 'object' ? headers : {};
    const blocked = new Set([
      'connection',
      'host',
      'content-length',
      'transfer-encoding',
      'upgrade',
      'proxy-connection',
      'keep-alive',
      'te',
      'trailer',
      'accept-encoding',
      'sec-websocket-key',
      'sec-websocket-version',
      'sec-websocket-extensions',
    ]);
    for (const [k, v] of Object.entries(src)) {
      const key = String(k || '')
        .trim()
        .toLowerCase();
      if (!key || blocked.has(key)) continue;
      if (v == null) continue;
      out[key] = Array.isArray(v) ? v.map(x => String(x)) : String(v);
    }
    return out;
  };

  const buildLocalWsUrl = async path => {
    const rawPath = path == null ? '' : String(path);
    const base = await localExpressProxy.getLocalExpressBaseUrl();
    if (!base) return '';
    try {
      const u = new URL(rawPath, base);
      u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:';
      return u.toString();
    } catch (_) {
      return '';
    }
  };

  const closeWsTunnel = (id, code, reason) => {
    const key = id == null ? '' : String(id);
    if (!key) return;
    const st = wsTunnels.get(key);
    wsTunnels.delete(key);
    if (!st || !st.ws) return;
    const ws = st.ws;
    try {
      if (typeof ws.terminate === 'function') {
        ws.terminate();
        return;
      }
    } catch (_) {}
    try {
      if (typeof ws.close === 'function') ws.close(code, reason);
    } catch (_) {}
  };

  const sendResSmall = ({ id, status, headers, bodyBuf, bodyText }) => {
    console.log(`[P2pConnectWorker] ${prefix}:res small id=${id} status=${status} body=${bodyText != null ? bodyText.length : bodyBuf ? bodyBuf.length : 0}`);
    const buf = bodyBuf && Buffer.isBuffer(bodyBuf) ? bodyBuf : bodyText != null ? Buffer.from(String(bodyText), 'utf8') : Buffer.alloc(0);
    return Promise.resolve()
      .then(async () => {
        return await sendResChunked({ id, status, headers, bodyBuf: buf, originalLength: buf.length });
      })
      .catch(() => false);
  };

  const sendResChunked = ({ id, status, headers, bodyBuf, originalLength }) => {
    const total = bodyBuf ? bodyBuf.length : 0;
    const rawLen = Number.isFinite(originalLength) && originalLength >= 0 ? originalLength : total;
    console.log(`[P2pConnectWorker] ${prefix}:res chunked begin id=${id} status=${status} total=${total}`);
    return Promise.resolve()
      .then(async () => {
        if (
          !(await sendMessage({
            type: `${prefix}:res:begin`,
            id,
            status,
            headers,
            length: rawLen,
          }))
        ) {
          console.log(`[P2pConnectWorker] ${prefix}:res chunked begin send failed id=${id} state=${dc ? dc.readyState : 'null'}`);
          return false;
        }
        const tkChunk = webrtcManager.getTransportKind(sid) || '';
        const chunkSize = tkChunk === '中继' ? 64 * 1024 : 128 * 1024;
        let offset = 0;
        while (offset < total) {
          const end = Math.min(offset + chunkSize, total);
          const piece = bodyBuf.slice(offset, end);
          const ok = await sendResChunkBinary({ id, chunk: piece });
          if (!ok) return false;
          offset = end;
        }
        const okEnd = await sendMessage({ type: `${prefix}:res:end`, id });
        if (!okEnd) {
          console.log(`[P2pConnectWorker] ${prefix}:res chunked end send failed id=${id} state=${dc ? dc.readyState : 'null'}`);
        }
        return okEnd;
      })
      .catch(() => false);
  };

  const sendResFromStream = ({ id, status, headers, length, stream }) => {
    const total = Number.isFinite(length) && length > 0 ? length : 0;
    return Promise.resolve()
      .then(async () => {
        if (!(await sendMessage({ type: `${prefix}:res:begin`, id, status, headers, length: total }))) return false;
        const startedAt = Date.now();
        let sentBytes = 0;
        let sentWireBytes = 0;
        let sentChunks = 0;
        let lastLogAt = Date.now();
        const st = pendingStreams.get(id);
        if (st && st.stream && typeof st.stream.pause === 'function') {
          try {
            st.stream.pause();
          } catch (_) {}
        }

        const tk = webrtcManager.getTransportKind(sid) || '';
        const isRelay = tk === '中继';
        const chunkSize = (() => {
          if (hasHighPriorityContention()) return 4 * 1024;
          if (hasVideoPriorityContention()) return 6 * 1024;
          if (isRelay && prefix === 'download') return 16 * 1024;
          if (isRelay && prefix === 'upload') return 8 * 1024;
          return 64 * 1024;
        })();
        const waitResume = () =>
          new Promise(resolve => {
            const s0 = pendingStreams.get(id);
            if (!s0 || s0.paused !== true) {
              resolve();
              return;
            }
            if (!Array.isArray(s0.resumeWaiters)) s0.resumeWaiters = [];
            s0.resumeWaiters.push(resolve);
          });

        const waitCredit = needBytes =>
          new Promise(resolve => {
            const s0 = pendingStreams.get(id);
            if (!s0) {
              resolve();
              return;
            }
            const inflight = Number(s0.inflightBytes) || 0;
            const win = Number(s0.windowBytes) || 0;
            if (!Number.isFinite(win) || win <= 0 || inflight + needBytes <= win) {
              resolve();
              return;
            }
            if (!Array.isArray(s0.creditWaiters)) s0.creditWaiters = [];
            s0.creditWaiters.push(resolve);
          });

        let ended = false;
        let failed = false;
        let chain = Promise.resolve();
        let carryParts = [];
        let carryLen = 0;

        const takeCarry = need => {
          if (need <= 0 || carryLen <= 0) return Buffer.alloc(0);
          const parts = [];
          let left = need;
          while (left > 0 && carryParts.length) {
            const p = carryParts[0];
            if (p.length <= left) {
              parts.push(p);
              carryParts.shift();
              carryLen -= p.length;
              left -= p.length;
              continue;
            }
            const head = p.slice(0, left);
            const rest = p.slice(left);
            parts.push(head);
            carryParts[0] = rest;
            carryLen -= head.length;
            left = 0;
          }
          return parts.length === 1 ? parts[0] : Buffer.concat(parts);
        };

        const flushCarry = async force => {
          while (carryLen >= chunkSize || (force && carryLen > 0)) {
            if (cancelledReqIds.has(id)) {
              ended = true;
              failed = true;
              return;
            }
            const cur2 = pendingStreams.get(id);
            if (!cur2) {
              ended = true;
              failed = true;
              return;
            }
            if (cur2.paused === true) {
              try {
                if (cur2.stream && typeof cur2.stream.pause === 'function') cur2.stream.pause();
              } catch (_) {}
              await waitResume();
            }

            const size = carryLen >= chunkSize ? chunkSize : carryLen;
            const piece = takeCarry(size);
            if (!piece || !piece.length) return;

            const outPiece = piece;

            while (true) {
              const curWin = pendingStreams.get(id);
              if (!curWin) {
                ended = true;
                failed = true;
                return;
              }
              if (curWin.paused === true) {
                try {
                  if (curWin.stream && typeof curWin.stream.pause === 'function') curWin.stream.pause();
                } catch (_) {}
                await waitResume();
                continue;
              }
              const inflight = Number(curWin.inflightBytes) || 0;
              const baseWin = Number(curWin.baseWindowBytes) || Number(curWin.windowBytes) || 0;
              const win = hasHighPriorityContention()
                ? Math.max(32 * 1024, Math.min(baseWin || 64 * 1024, isRelay ? 64 * 1024 : 128 * 1024))
                : hasVideoPriorityContention()
                ? Math.max(48 * 1024, Math.min(baseWin || 128 * 1024, isRelay ? 96 * 1024 : 192 * 1024))
                : baseWin;
              curWin.windowBytes = win;
              if (Number.isFinite(win) && win > 0 && inflight + outPiece.length > win) {
                try {
                  if (curWin.stream && typeof curWin.stream.pause === 'function') curWin.stream.pause();
                } catch (_) {}
                await waitCredit(outPiece.length);
                continue;
              }
              break;
            }

            if (cancelledReqIds.has(id)) {
              ended = true;
              failed = true;
              return;
            }
            const ok = await sendResChunkBinary({ id, chunk: outPiece });
            if (!ok) {
              console.log(`[P2pConnectWorker] ${prefix}:res stream send_failed id=${id} piece=${outPiece.length} state=${dc ? dc.readyState : 'null'}`);
              throw new Error('send_failed');
            }
            sentBytes += piece.length;
            sentWireBytes += outPiece.length;
            sentChunks += 1;
            if (sentChunks === 1) {
              console.log(`[P2pConnectWorker] ${prefix}:res stream firstChunk id=${id} bytes=${outPiece.length}`);
            }
            const now = Date.now();
            if (now - lastLogAt >= 3000) {
              lastLogAt = now;
              console.log(
                `[P2pConnectWorker] ${prefix}:res stream progress id=${id} sent=${sentBytes}/${total || '?'} wire=${sentWireBytes} chunks=${sentChunks} paused=${cur2 && cur2.paused ? 1 : 0} inflight=${cur2 ? Number(cur2.inflightBytes) || 0 : 0} win=${cur2 ? Number(cur2.windowBytes) || 0 : 0}`
              );
            }
            const curAck = pendingStreams.get(id);
            if (curAck && Number(curAck.windowBytes) > 0) curAck.inflightBytes = (Number(curAck.inflightBytes) || 0) + outPiece.length;
            // 强偏向 API/file：bulk 发送每片后主动让出事件循环，给高优先级通道抢占窗口
            if (hasHighPriorityContention()) {
              await sleep(isRelay ? 3 : 1);
            } else if (hasVideoPriorityContention()) {
              await sleep(isRelay ? 2 : 1);
            }
          }
        };

        const onData = chunk => {
          try {
            if (stream && typeof stream.pause === 'function') stream.pause();
          } catch (_) {}
          if (ended || failed) return;
          if (cancelledReqIds.has(id)) {
            ended = true;
            failed = true;
            return;
          }
          chain = chain
            .then(async () => {
              if (cancelledReqIds.has(id)) {
                ended = true;
                failed = true;
                return;
              }
              const cur = pendingStreams.get(id);
              if (!cur) {
                ended = true;
                failed = true;
                return;
              }
              if (cur.paused === true) {
                try {
                  if (cur.stream && typeof cur.stream.pause === 'function') cur.stream.pause();
                } catch (_) {}
                await waitResume();
              }
              const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
              if (buf && buf.length) {
                carryParts.push(buf);
                carryLen += buf.length;
              }
              await flushCarry(false);
              const cur3 = pendingStreams.get(id);
              if (cur3 && cur3.paused !== true) {
                try {
                  if (cur3.stream && typeof cur3.stream.resume === 'function') cur3.stream.resume();
                } catch (_) {}
              }
            })
            .catch(() => {
              ended = true;
              failed = true;
            });
        };

        const onEnd = () => {
          ended = true;
          chain = chain
            .then(async () => {
              await flushCarry(true);
            })
            .catch(() => {
              ended = true;
              failed = true;
            });
          console.log(`[P2pConnectWorker] ${prefix}:res stream end id=${id} sent=${sentBytes}/${total || '?'} chunks=${sentChunks} durMs=${Date.now() - startedAt}`);
        };

        const onError = err => {
          failed = true;
          const em = err ? err.message || String(err) : 'stream_error';
          const ec = err && err.code != null ? String(err.code) : '';
          const cur = pendingStreams.get(id);
          const paused = cur && cur.paused ? 1 : 0;
          const inflight = cur ? Number(cur.inflightBytes) || 0 : 0;
          const win = cur ? Number(cur.windowBytes) || 0 : 0;
          const aborted = cur && cur.abortController && cur.abortController.signal && cur.abortController.signal.aborted ? 1 : 0;
          console.log(
            `[P2pConnectWorker] ${prefix}:res stream error id=${id} err=${em}${ec ? ` code=${ec}` : ''} aborted=${aborted} paused=${paused} inflight=${inflight} win=${win} sent=${sentBytes}/${total || '?'} chunks=${sentChunks} durMs=${Date.now() - startedAt}`
          );
        };

        try {
          stream.on('data', onData);
          stream.once('end', onEnd);
          stream.once('error', onError);
          try {
            if (stream && typeof stream.resume === 'function') stream.resume();
          } catch (_) {}
        } catch (_) {}

        const okFinal = await new Promise(resolve => {
          const done = async () => {
            try {
              await chain;
            } catch (_) {
              resolve(false);
              return;
            }
            if (failed) {
              resolve(false);
              return;
            }
            resolve(await sendMessage({ type: `${prefix}:res:end`, id }));
          };
          if (ended) {
            done();
            return;
          }
          stream.once('end', done);
          stream.once('error', () => resolve(false));
        });

        try {
          stream.removeListener('data', onData);
        } catch (_) {}
        console.log(`[P2pConnectWorker] ${prefix}:res stream done id=${id} ok=${okFinal ? 1 : 0} sent=${sentBytes}/${total || '?'} chunks=${sentChunks} durMs=${Date.now() - startedAt}`);
        return okFinal;
      })
      .catch(() => false);
  };

  let proxyConcurrent = 0;
  const proxyPendingQueue = [];

  const runProxy = fn => {
    const run = () => {
      proxyConcurrent++;
      Promise.resolve()
        .then(() => fn())
        .catch(() => {})
        .finally(() => {
          proxyConcurrent--;
          if (proxyPendingQueue.length > 0) {
            const next = proxyPendingQueue.shift();
            setImmediate(next);
          }
        });
    };
    if (proxyConcurrent < P2P_PROXY_MAX_CONCURRENT) {
      setImmediate(run);
    } else {
      proxyPendingQueue.push(run);
    }
  };

  const proxyAndReply = async ({ id, method, path, headers, bodyBufOverride }) => {
    if (isHighPriorityPrefix(prefix)) {
      enterHighPriority();
    }
    if (isVideoPrefix(prefix)) {
      enterVideoPriority();
    }
    try {
    if (cancelledReqIds.has(id)) {
      cancelledReqIds.delete(id);
      return;
    }
    if (pendingStreams.size >= P2P_PROXY_MAX_PENDING_STREAMS) {
      await sendResSmall({
        id,
        status: 429,
        headers: { 'content-type': 'application/json' },
        bodyText: '{"code":-1,"message":"too_many_pending_streams"}',
      });
      return;
    }
    const tk = webrtcManager.getTransportKind(sid) || '未知';
    console.log(`[P2pConnectWorker] P2P 转发请求 sid=${sid} 通道=${prefix} 传输=${tk} ${String(method || 'GET').toUpperCase()} ${String(path.slice(0, 10) || '')}`);
    const inFlightAbort = typeof AbortController !== 'undefined' ? new AbortController() : null;
    if (inFlightAbort) pendingInFlightReqs.set(id, inFlightAbort);
    const clientIp = webrtcManager.getSessionRemoteAddress ? webrtcManager.getSessionRemoteAddress(sid) : '';
    let res;
    try {
      res = await localExpressProxy.forwardToLocalExpressStream({
        method,
        path,
        headers,
        bodyBufOverride,
        signal: inFlightAbort ? inFlightAbort.signal : undefined,
        ...(clientIp ? { clientIp } : {}),
      });
    } catch (err) {
      pendingInFlightReqs.delete(id);
      if (cancelledReqIds.has(id)) cancelledReqIds.delete(id);
      return;
    } finally {
      pendingInFlightReqs.delete(id);
    }
    if (!res || cancelledReqIds.has(id)) {
      cancelledReqIds.delete(id);
      if (res) {
        try {
          if (res.abortController && typeof res.abortController.abort === 'function') res.abortController.abort();
        } catch (_) {}
        try {
          if (res.stream && typeof res.stream.destroy === 'function') res.stream.destroy();
        } catch (_) {}
      }
      return;
    }
    const status = res.status;
    const resHeaders = res.headers;
    const stream = res.stream;
    const abortController = res.abortController || null;
    if (id && (abortController || stream)) {
      const isRelay = tk === '中继';
      const win = prefix === 'download' ? (isRelay ? 512 * 1024 : 4 * 1024 * 1024) : isRelay ? 1024 * 1024 : 4 * 1024 * 1024;
      pendingStreams.set(id, {
        abortController,
        stream,
        paused: false,
        inflightBytes: 0,
        baseWindowBytes: win,
        windowBytes: win,
        creditWaiters: [],
        resumeWaiters: [],
      });
    }
    if (!stream) {
      await sendResSmall({
        id,
        status,
        headers: resHeaders,
        bodyText: res.bodyText || '',
      });
      pendingStreams.delete(id);
      return;
    }
    const clRaw = resHeaders ? resHeaders['content-length'] : '';
    const cl = Array.isArray(clRaw) ? Number.parseInt(String(clRaw[0] || ''), 10) : Number.parseInt(String(clRaw || ''), 10);
    if (Number.isFinite(cl) && cl >= 0 && cl <= 128 * 1024) {
      const chunks = [];
      let total = 0;
      for await (const chunk of stream) {
        const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        chunks.push(buf);
        total += buf.length;
        if (total > 128 * 1024) break;
      }
      const buf = chunks.length ? Buffer.concat(chunks, total) : Buffer.alloc(0);
      await sendResSmall({
        id,
        status,
        headers: resHeaders,
        bodyBuf: buf,
      });
      pendingStreams.delete(id);
      return;
    }
    await sendResFromStream({ id, status, headers: resHeaders, length: cl, stream });
    pendingStreams.delete(id);
    } finally {
      if (isHighPriorityPrefix(prefix)) {
        leaveHighPriority();
      }
      if (isVideoPrefix(prefix)) {
        leaveVideoPriority();
      }
    }
  };

  const onMessage = data => {
    let buf = null;
    try {
      if (data == null) {
        buf = null;
      } else if (typeof data === 'string') {
        const s = data;
        if (!s) return;
        const out = Buffer.allocUnsafe(s.length);
        for (let i = 0; i < s.length; i++) {
          out[i] = s.charCodeAt(i) & 0xff;
        }
        buf = out;
      } else if (Buffer.isBuffer(data)) {
        buf = data;
      } else if (data && typeof ArrayBuffer !== 'undefined' && data instanceof ArrayBuffer) {
        buf = Buffer.from(new Uint8Array(data));
      } else if (data && typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView(data)) {
        buf = Buffer.from(data.buffer, data.byteOffset, data.byteLength);
      }

      if (buf && buf.length >= 2 && buf[0] === 0x01) {
        const idLen = buf[1];
        if (idLen > 0 && 2 + idLen <= buf.length) {
          const id = buf.slice(2, 2 + idLen).toString('utf8');
          const payload = buf.slice(2 + idLen);
          const st = pendingReqBodies.get(id);
          if (st && payload.length) {
            const rawLen = Number(st.rawLength) || 0;
            if (rawLen > 0 && rawLen > P2P_PROXY_MAX_REQ_BODY_BYTES) {
              dropPendingReq(id, 413, 'request_body_too_large');
              return;
            }
            const delta = payload.length;
            if (st.encodedLength + delta > P2P_PROXY_MAX_REQ_BODY_BYTES * 2) {
              dropPendingReq(id, 413, 'request_body_too_large');
              return;
            }
            st.chunks.push(payload);
            st.encodedLength += delta;
            if (st.chunks.length % 64 === 0) {
              console.log(`[P2pConnectWorker] ${prefix}:req:chunk(bin) id=${id} chunks=${st.chunks.length} bytes=${st.encodedLength}`);
            }
          }
        }
        return;
      }
    } catch (_) {}

    if (!buf || !isControlBinary(buf)) return;
    let msg;
    try {
      msg = decodeControlBinary(buf);
    } catch (_) {
      msg = null;
    }
    if (!msg || typeof msg !== 'object') return;
    const type = msg.type ? String(msg.type) : '';
    if (type === `${prefix}:ack`) {
      const ackId = msg.id ? String(msg.id) : '';
      if (ackId && !pendingStreams.has(ackId)) {
        cancelledReqIds.add(ackId);
        return;
      }
    }
    console.log(`[P2pConnectWorker] onMessage: ${type} clientIp=${webrtcManager.getSessionRemoteAddress ? webrtcManager.getSessionRemoteAddress(sid) : ''}`);
    if (type === `${prefix}:req:begin`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      if (pendingReqBodies.size >= P2P_PROXY_MAX_PENDING_REQ) {
        sendResSmall({ id, status: 429, headers: { 'content-type': 'application/json' }, bodyText: '{"code":-1,"message":"too_many_pending_requests"}' });
        return;
      }
      const method = msg.method ? String(msg.method).toUpperCase() : 'GET';
      const path = msg.path ? String(msg.path) : '';
      const headers = msg.headers && typeof msg.headers === 'object' ? msg.headers : {};
      const rawLength = Number.isFinite(msg.length) ? Number(msg.length) : 0;
      console.log(`[P2pConnectWorker] ${prefix}:req:begin id=${id} method=${method} path=${path.slice(0, 10)} headers=${Object.keys(headers).length}`);
      const timeoutId = setTimeout(() => {
        if (!pendingReqBodies.has(id)) return;
        dropPendingReq(id, 408, 'request_timeout');
      }, P2P_PROXY_REQ_TIMEOUT_MS);
      pendingReqBodies.set(id, {
        method,
        path,
        headers,
        rawLength,
        chunks: [],
        encodedLength: 0,
        timeoutId,
      });
      return;
    }
    if (type === `${prefix}:req:end`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      const st = pendingReqBodies.get(id);
      pendingReqBodies.delete(id);
      if (!st) return;
      try {
        if (st.timeoutId) clearTimeout(st.timeoutId);
      } catch (_) {}
      const encodedBodyBuf = st.chunks.length ? Buffer.concat(st.chunks) : null;
      console.log(`[P2pConnectWorker] ${prefix}:req:end id=${id} bytes=${encodedBodyBuf ? encodedBodyBuf.length : st.encodedLength || 0}`);
      runProxy(async () => {
        try {
          const bodyBuf = encodedBodyBuf;
          await proxyAndReply({
            id,
            method: st.method,
            path: st.path,
            headers: st.headers,
            bodyBufOverride: bodyBuf,
          });
        } catch (err) {
          console.log(`[P2pConnectWorker] ${prefix}:req:end error id=${id} err=${err ? err.message || err : 'unknown'}`);
          sendResSmall({ id, status: 502, headers: { 'content-type': 'application/json' }, bodyText: '{"code":-1,"message":"bad_gateway"}' });
        }
      });
      return;
    }
    if (type === `${prefix}:req:cancel`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      cancelledReqIds.add(id);
      for (let i = sendQueue.length - 1; i >= 0; i--) {
        if (sendQueue[i].reqId === id) sendQueue.splice(i, 1);
      }
      const inFlightAbort = pendingInFlightReqs.get(id);
      if (inFlightAbort && typeof inFlightAbort.abort === 'function') {
        try {
          inFlightAbort.abort();
        } catch (_) {}
        pendingInFlightReqs.delete(id);
      }
      const stReq = pendingReqBodies.get(id);
      if (stReq) {
        pendingReqBodies.delete(id);
        try {
          if (stReq.timeoutId) clearTimeout(stReq.timeoutId);
        } catch (_) {}
      }
      const st = pendingStreams.get(id);
      pendingStreams.delete(id);
      console.log(
        `[P2pConnectWorker] 客户端取消请求 sid=${sid} 通道=${prefix} id=${id} hadReq=${!!stReq} hadStream=${!!st} hadInFlight=${!!inFlightAbort} paused=${st && st.paused ? 1 : 0} inflight=${st ? Number(st.inflightBytes) || 0 : 0}`
      );
      if (st) {
        const w1 = Array.isArray(st.resumeWaiters) ? st.resumeWaiters.splice(0, st.resumeWaiters.length) : [];
        const w2 = Array.isArray(st.creditWaiters) ? st.creditWaiters.splice(0, st.creditWaiters.length) : [];
        for (const fn of w1.concat(w2)) {
          try {
            fn();
          } catch (_) {}
        }
        try {
          if (st.abortController && typeof st.abortController.abort === 'function') st.abortController.abort();
        } catch (_) {}
        try {
          if (st.stream && typeof st.stream.destroy === 'function') st.stream.destroy();
        } catch (_) {}
      }
      return;
    }
    if (type === `${prefix}:cancel`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      cancelledReqIds.add(id);
      const st = pendingStreams.get(id);
      pendingStreams.delete(id);
      console.log(
        `[P2pConnectWorker] 客户端取消 sid=${sid} 通道=${prefix} id=${id} paused=${st && st.paused ? 1 : 0} inflight=${st ? Number(st.inflightBytes) || 0 : 0} win=${st ? Number(st.windowBytes) || 0 : 0}`
      );
      if (st) {
        const w1 = Array.isArray(st.resumeWaiters) ? st.resumeWaiters.splice(0, st.resumeWaiters.length) : [];
        const w2 = Array.isArray(st.creditWaiters) ? st.creditWaiters.splice(0, st.creditWaiters.length) : [];
        for (const fn of w1.concat(w2)) {
          try {
            fn();
          } catch (_) {}
        }
        try {
          if (st.abortController && typeof st.abortController.abort === 'function') st.abortController.abort();
        } catch (_) {}
        try {
          if (st.stream) {
            if (typeof st.stream.removeAllListeners === 'function') {
              st.stream.removeAllListeners('data');
              st.stream.removeAllListeners('end');
              st.stream.removeAllListeners('error');
            }
            if (typeof st.stream.destroy === 'function') st.stream.destroy();
          }
        } catch (_) {}
      }
      return;
    }
    if (type === `${prefix}:flow`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      const action = msg.action ? String(msg.action) : '';
      const st = pendingStreams.get(id);
      if (!st) return;
      if (action === 'pause') {
        st.paused = true;
        console.log(`[P2pConnectWorker] 客户端暂停读取 sid=${sid} 通道=${prefix} id=${id}`);
        try {
          if (st.stream && typeof st.stream.pause === 'function') st.stream.pause();
        } catch (_) {}
        return;
      }
      if (action === 'resume') {
        st.paused = false;
        console.log(`[P2pConnectWorker] 客户端恢复读取 sid=${sid} 通道=${prefix} id=${id}`);
        try {
          if (st.stream && typeof st.stream.resume === 'function') st.stream.resume();
        } catch (_) {}
        const waiters = Array.isArray(st.resumeWaiters) ? st.resumeWaiters.splice(0, st.resumeWaiters.length) : [];
        for (const fn of waiters) {
          try {
            fn();
          } catch (_) {}
        }
      }
      return;
    }
    if (type === `${prefix}:ack`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      const delta = Number(msg.delta);
      if (!Number.isFinite(delta) || delta <= 0) return;
      const st = pendingStreams.get(id);
      if (!st) return;
      if (!st._ackLogged) {
        st._ackLogged = true;
        console.log(`[P2pConnectWorker] 收到客户端 ACK sid=${sid} 通道=${prefix} id=${id}`);
      }
      st.inflightBytes = Math.max(0, (Number(st.inflightBytes) || 0) - delta);
      const waiters = Array.isArray(st.creditWaiters) ? st.creditWaiters.splice(0, st.creditWaiters.length) : [];
      for (const fn of waiters) {
        try {
          fn();
        } catch (_) {}
      }
      return;
    }
    if (type === `${prefix}:ping`) {
      sendMessage({ type: `${prefix}:pong`, ts: Date.now() });
      return;
    }
    if (type === `${prefix}:ws:open`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      const path = msg.path ? String(msg.path) : '';
      const headers = msg.headers && typeof msg.headers === 'object' ? msg.headers : {};
      if (!wsImpl) {
        sendMessage({ type: `${prefix}:ws:open:error`, id, error: 'ws_not_supported' });
        return;
      }
      Promise.resolve()
        .then(async () => {
          const wsUrl = await buildLocalWsUrl(path);
          if (!wsUrl) {
            await sendMessage({ type: `${prefix}:ws:open:error`, id, error: 'invalid_ws_url' });
            return;
          }
          closeWsTunnel(id, 4000, 'reopen');
          let ws;
          try {
            ws = new wsImpl(wsUrl, { headers: normalizeWsHeaders(headers) });
          } catch (e) {
            await sendMessage({ type: `${prefix}:ws:open:error`, id, error: e ? e.message || String(e) : 'open_failed' });
            return;
          }
          wsTunnels.set(id, { ws });
          const onOpen = () => {
            sendMessage({ type: `${prefix}:ws:open:ok`, id });
          };
          const onClose = (code, reason) => {
            wsTunnels.delete(id);
            const c = Number.isFinite(code) ? code : undefined;
            const r = reason ? String(reason) : '';
            sendMessage({ type: `${prefix}:ws:close`, id, ...(c != null ? { code: c } : {}), ...(r ? { reason: r } : {}) });
          };
          const onError = err => {
            wsTunnels.delete(id);
            const em = err ? err.message || String(err) : 'ws_error';
            sendMessage({ type: `${prefix}:ws:error`, id, error: em });
            closeWsTunnel(id, 1011, 'error');
          };
          const onMessage = data => {
            if (data == null) return;
            if (typeof data === 'string') {
              sendMessage({ type: `${prefix}:ws:message`, id, data });
              return;
            }
            try {
              const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
              sendMessage({ type: `${prefix}:ws:message`, id, data: buf.toString('utf8') });
            } catch (_) {}
          };
          if (typeof ws.on === 'function') {
            ws.on('open', onOpen);
            ws.on('close', onClose);
            ws.on('error', onError);
            ws.on('message', onMessage);
            return;
          }
          ws.onopen = onOpen;
          ws.onclose = ev => onClose(ev && ev.code, ev && ev.reason);
          ws.onerror = onError;
          ws.onmessage = ev => onMessage(ev && ev.data);
        })
        .catch(e => {
          sendMessage({ type: `${prefix}:ws:open:error`, id, error: e ? e.message || String(e) : 'open_failed' });
        });
      return;
    }
    if (type === `${prefix}:ws:send`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      const st = wsTunnels.get(id);
      const ws = st && st.ws ? st.ws : null;
      if (!ws) return;
      const data = msg.data != null ? String(msg.data) : '';
      if (!data) return;
      try {
        ws.send(data);
      } catch (_) {}
      return;
    }
    if (type === `${prefix}:ws:close`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      closeWsTunnel(id, 1000, 'client_close');
      return;
    }
    if (type !== `${prefix}:req`) return;
    const id = msg.id ? String(msg.id) : '';
    if (!id) return;
    console.log(`[P2pConnectWorker] ${prefix}:req id=${id} method=${msg.method} path=${msg.path}`);
    runProxy(async () => {
      try {
        await proxyAndReply({ id, method: msg.method, path: msg.path, headers: msg.headers });
      } catch (err) {
        console.log(`[P2pConnectWorker] ${prefix}:req error id=${id} err=${err ? err.message || err : 'unknown'}`);
        sendResSmall({ id, status: 502, headers: { 'content-type': 'application/json' }, bodyText: '{"code":-1,"message":"bad_gateway"}' });
      }
    });
  };

  const onOpen = () => {
    console.log(`[P2pConnectWorker] dc open sid=${sid} label=${label}`);
    sendMessage({
      type: `${prefix}:ready`,
      features: {
        chunkBinaryV2: true,
      },
    });
  };

  const onClose = () => {
    console.log(`[P2pConnectWorker] dc close sid=${sid} label=${label}`);
    dcClosedForSend = true;
    sendQueue.length = 0;
    proxyPendingQueue.length = 0;
    webrtcManager.unregisterDataChannel(sid, label, dc);
    cancelledReqIds.clear();
    for (const [id, ac] of pendingInFlightReqs.entries()) {
      try {
        if (ac && typeof ac.abort === 'function') ac.abort();
      } catch (_) {}
      pendingInFlightReqs.delete(id);
    }
    for (const id of wsTunnels.keys()) {
      closeWsTunnel(id, 1001, 'dc_closed');
    }
    for (const [id, st] of pendingReqBodies.entries()) {
      try {
        if (st && st.timeoutId) clearTimeout(st.timeoutId);
      } catch (_) {}
      pendingReqBodies.delete(id);
    }
    for (const [id, st] of pendingStreams.entries()) {
      try {
        if (st.abortController && typeof st.abortController.abort === 'function') st.abortController.abort();
      } catch (_) {}
      try {
        if (st.stream && typeof st.stream.destroy === 'function') st.stream.destroy();
      } catch (_) {}
      pendingStreams.delete(id);
    }
    const reason = `dc_${label || 'unknown'}_closed`;
    const shouldCloseSession = label === 'api' || !webrtcManager.hasAnyDataChannel(sid);
    if (shouldCloseSession && webrtcManager.hasSession(sid)) {
      webrtcManager.closeSession(sid, { notifyPeer: true, reason, expectedPc: pc });
    }
  };

  if (typeof dc.addEventListener === 'function') {
    dc.addEventListener('open', onOpen);
    dc.addEventListener('message', ev => onMessage(ev && ev.data));
    dc.addEventListener('close', onClose);
    return;
  }

  dc.onopen = onOpen;
  dc.onmessage = ev => onMessage(ev && ev.data);
  dc.onclose = onClose;
}

module.exports = { attachDataChannel };
