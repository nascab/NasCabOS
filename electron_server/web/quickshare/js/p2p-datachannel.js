import { createDeferred } from './p2p-deferred.js';
import { npcEncode, npcDecode } from './npc-codec.js';
import { qsbConcat } from './qsb-codec.js';

export function makeDcClient(prefix, dc) {
  const ready = createDeferred();
  const pending = new Map();
  const pendingChunks = new Map();
  const pendingStreams = new Map();

  const waitForDrain = async ({ maxBufferedAmount, timeoutMs } = {}) => {
    const cur = dc;
    if (!cur || cur.readyState !== 'open') throw new Error('p2p_dc_not_open');
    if (typeof cur.bufferedAmount !== 'number') return true;
    const max = Number.isFinite(maxBufferedAmount) && maxBufferedAmount > 0 ? maxBufferedAmount : 2 * 1024 * 1024;
    if (cur.bufferedAmount <= max) return true;
    return await new Promise(resolve => {
      let done = false;
      const finish = ok => {
        if (done) return;
        done = true;
        try {
          cur.removeEventListener('bufferedamountlow', onLow);
        } catch (_) {}
        clearTimeout(timer);
        resolve(ok);
      };
      const onLow = () => {
        if (cur.bufferedAmount <= max) finish(true);
      };
      try {
        cur.bufferedAmountLowThreshold = max;
      } catch (_) {}
      const timer = setTimeout(() => finish(cur.bufferedAmount <= max), Math.max(500, Number(timeoutMs) || 15000));
      try {
        cur.addEventListener('bufferedamountlow', onLow);
      } catch (_) {}
      onLow();
    });
  };

  const sendCtrl = payload => {
    const cur = dc;
    if (!cur || cur.readyState !== 'open') return false;
    const bin = npcEncode(prefix, payload);
    if (!bin) return false;
    try {
      cur.send(bin);
      return true;
    } catch (_) {
      return false;
    }
  };

  const cleanup = id => {
    const p = pending.get(id);
    if (p && p.timer) clearTimeout(p.timer);
    pending.delete(id);
    const c = pendingChunks.get(id);
    if (c && c.timer) clearTimeout(c.timer);
    pendingChunks.delete(id);
    const s = pendingStreams.get(id);
    if (s && s.timer) clearTimeout(s.timer);
    if (s && Array.isArray(s.queue)) s.queue.length = 0;
    pendingStreams.delete(id);
  };

  const scheduleStreamProgress = st => {
    if (!st || typeof st.onProgress !== 'function') return;
    const now = Date.now();
    if (st._lastProgressAt && now - st._lastProgressAt < 500) return;
    st._lastProgressAt = now;
    try {
      st.onProgress({ received: st.received, total: st.total });
    } catch (_) {}
  };

  const maybeSendAck = (id, st) => {
    if (!st) return;
    const every = Number.isFinite(st.ackEveryBytes) && st.ackEveryBytes > 0 ? st.ackEveryBytes : 512 * 1024;
    if (!Number.isFinite(st.lastAckedEncodedBytes)) st.lastAckedEncodedBytes = 0;
    if (!Number.isFinite(st.ackReceivedBytes)) st.ackReceivedBytes = 0;
    const delta = (Number(st.ackReceivedBytes) || 0) - st.lastAckedEncodedBytes;
    if (delta <= 0) return;
    const now = Date.now();
    const force = !st.queue || st.queue.length === 0;
    if (!force && delta < every && st._lastAckAt && now - st._lastAckAt < 500) return;
    st._lastAckAt = now;
    st.lastAckedEncodedBytes += delta;
    sendCtrl({ type: `${prefix}:ack`, id, delta });
  };

  const maybeUpdateFlowControl = (id, st) => {
    if (!st) return;
    if (!Number.isFinite(st.queueBytes)) st.queueBytes = 0;
    const hi = 8 * 1024 * 1024;
    const lo = 2 * 1024 * 1024;
    if (st.flowPaused !== true && st.queueBytes > hi) {
      st.flowPaused = true;
      sendCtrl({ type: `${prefix}:flow`, id, action: 'pause' });
      return;
    }
    if (st.flowPaused === true && st.queueBytes < lo) {
      st.flowPaused = false;
      sendCtrl({ type: `${prefix}:flow`, id, action: 'resume' });
    }
  };

  const drainStreamQueue = (id, st) => {
    if (!st || st.aborted) return;
    if (st.draining) return;
    st.draining = true;
    st.drainPromise = (async () => {
      while (!st.aborted && st.queue && st.queue.length) {
        const item = st.queue.shift();
        const chunk = item && item.data ? item.data : item;
        const encodedLen = item && Number.isFinite(item.encodedLen) ? item.encodedLen : chunk ? chunk.length : 0;
        if (!chunk || !chunk.length) continue;
        await st.onChunk(chunk);
        st.received += chunk.length;
        st.queueBytes -= chunk.length;
        if (st.queueBytes < 0) st.queueBytes = 0;
        scheduleStreamProgress(st);
        maybeUpdateFlowControl(id, st);
        if (!Number.isFinite(st.ackReceivedBytes)) st.ackReceivedBytes = 0;
        st.ackReceivedBytes += encodedLen;
        maybeSendAck(id, st);
      }
    })()
      .catch(err => {
        st.aborted = true;
        cleanup(id);
        st.reject(err || new Error('p2p_stream_write_failed'));
      })
      .finally(() => {
        if (st) st.draining = false;
      });
  };

  const handleBinaryChunk = bytes => {
    if (!bytes || bytes.length < 3) return;
    const ver = bytes[0];
    if (ver !== 0x01 && ver !== 0x02) return;
    const hasFlags = ver === 0x02;
    const idLen = bytes[1];
    if (idLen <= 0) return;
    const headerLen = 2 + idLen + (hasFlags ? 1 : 0);
    if (headerLen > bytes.length) return;
    let id = '';
    try {
      id = new TextDecoder().decode(bytes.subarray(2, 2 + idLen));
    } catch (_) {
      id = '';
    }
    if (!id) return;
    const payload = bytes.subarray(headerLen);
    if (!payload.length) return;
    const encodedLen = payload.length;
    const out = payload;
    const s = pendingStreams.get(id);
    if (s && typeof s.onChunk === 'function') {
      if (s.aborted) return;
      if (!Array.isArray(s.queue)) s.queue = [];
      s.queue.push({ data: out, encodedLen });
      s.queueBytes += out.length;
      maybeUpdateFlowControl(id, s);
      drainStreamQueue(id, s);
      return;
    }
    const st = pendingChunks.get(id);
    if (!st) return;
    st.chunks.push(out);
  };

  const normalizeHeaders = headers => {
    const out = {};
    const src = headers && typeof headers === 'object' ? headers : {};
    for (const [k, v] of Object.entries(src)) {
      const key = String(k || '')
        .trim()
        .toLowerCase();
      if (!key) continue;
      out[key] = v == null ? '' : Array.isArray(v) ? String(v[0] ?? '') : String(v);
    }
    return out;
  };

  const onCtrl = msg => {
    const type = msg.type ? String(msg.type) : '';
    if (type === `${prefix}:ready`) {
      if (ready.resolve) ready.resolve(true);
      return;
    }
    if (type === `${prefix}:pong` || type === `${prefix}:ping`) {
      return;
    }
    if (type === `${prefix}:res`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      const s = pendingStreams.get(id);
      if (s) {
        cleanup(id);
        const status = Number.parseInt(String(msg.status ?? ''), 10) || 500;
        const headers = normalizeHeaders(msg.headers);
        const bytes = msg.bodyBytes instanceof Uint8Array ? msg.bodyBytes : new Uint8Array(0);
        Promise.resolve()
          .then(async () => {
            s.status = status;
            s.headers = headers;
            s.total = bytes.length;
            if (typeof s.onBegin === 'function') await s.onBegin({ status, headers, length: bytes.length });
            if (typeof s.onChunk === 'function') await s.onChunk(bytes);
            if (typeof s.onEnd === 'function') await s.onEnd();
            s.resolve({ status, headers, length: bytes.length });
          })
          .catch(err => s.reject(err || new Error('p2p_stream_failed')));
        return;
      }
      const p = pending.get(id);
      if (!p) return;
      cleanup(id);
      const status = Number.parseInt(String(msg.status ?? ''), 10) || 500;
      const headers = normalizeHeaders(msg.headers);
      const bytes = msg.bodyBytes instanceof Uint8Array ? msg.bodyBytes : new Uint8Array(0);
      p.resolve({ status, headers, bytes, blob: new Blob([bytes], { type: headers['content-type'] || '' }) });
      return;
    }
    if (type === `${prefix}:res:begin`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      const s = pendingStreams.get(id);
      if (s) {
        const status = Number.parseInt(String(msg.status ?? ''), 10) || 500;
        const headers = normalizeHeaders(msg.headers);
        const length = Number.parseInt(String(msg.length ?? ''), 10);
        s.status = status;
        s.headers = headers;
        s.total = Number.isFinite(length) && length >= 0 ? length : null;
        Promise.resolve()
          .then(async () => {
            if (typeof s.onBegin === 'function') await s.onBegin({ status, headers, length: s.total });
            scheduleStreamProgress(s);
          })
          .catch(err => {
            s.aborted = true;
            cleanup(id);
            s.reject(err || new Error('p2p_stream_begin_failed'));
          });
        return;
      }
      const p = pending.get(id);
      if (!p) return;
      const status = Number.parseInt(String(msg.status ?? ''), 10) || 500;
      const headers = normalizeHeaders(msg.headers);
      pendingChunks.set(id, { status, headers, chunks: [], resolve: p.resolve, reject: p.reject, timer: p.timer });
      pending.delete(id);
      return;
    }
    if (type === `${prefix}:res:end`) {
      const id = msg.id ? String(msg.id) : '';
      if (!id) return;
      const s = pendingStreams.get(id);
      if (s) {
        pendingStreams.delete(id);
        Promise.resolve()
          .then(async () => {
            if (s.drainPromise) await s.drainPromise;
            if (typeof s.onEnd === 'function') await s.onEnd();
            cleanup(id);
            s.resolve({ status: s.status || 200, headers: s.headers || {}, length: s.received });
          })
          .catch(err => {
            cleanup(id);
            s.reject(err || new Error('p2p_stream_end_failed'));
          });
        return;
      }
      const st = pendingChunks.get(id);
      if (!st) return;
      cleanup(id);
      const bytes = st.chunks && st.chunks.length ? qsbConcat(st.chunks) : new Uint8Array(0);
      const blob = new Blob([bytes], { type: st.headers['content-type'] || '' });
      st.resolve({ status: st.status, headers: st.headers, bytes, blob });
    }
  };

  let incomingChain = Promise.resolve();

  const processBytes = async bytes => {
    if (!bytes || !bytes.length) return;
    if (bytes[0] === 0x01 || bytes[0] === 0x02) {
      await handleBinaryChunk(bytes);
      return;
    }
    const msg = npcDecode(prefix, bytes);
    if (!msg) return;
    onCtrl(msg);
  };

  const processRaw = async raw => {
    if (raw == null) return;
    if (raw instanceof ArrayBuffer) {
      await processBytes(new Uint8Array(raw));
      return;
    }
    if (ArrayBuffer.isView(raw)) {
      await processBytes(new Uint8Array(raw.buffer, raw.byteOffset, raw.byteLength));
      return;
    }
    if (typeof Blob !== 'undefined' && raw instanceof Blob) {
      const ab = await raw.arrayBuffer().catch(() => null);
      if (!ab) return;
      await processBytes(new Uint8Array(ab));
      return;
    }
  };

  const onMessage = ev => {
    const raw = ev && ev.data != null ? ev.data : ev;
    if (raw == null) return;
    incomingChain = incomingChain.then(() => processRaw(raw)).catch(() => {});
  };

  if (typeof dc.addEventListener === 'function') {
    dc.addEventListener('message', onMessage);
    dc.addEventListener('open', () => {});
  } else {
    dc.onmessage = onMessage;
  }

  const request = async ({ method, path, headers, body, bodyBytes, timeoutMs } = {}) => {
    const id = `${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const p = createDeferred();
    const timer = setTimeout(
      () => {
        cleanup(id);
        p.reject(new Error('p2p_timeout'));
      },
      Math.max(1000, Number(timeoutMs) || 30000)
    );
    pending.set(id, { resolve: p.resolve, reject: p.reject, timer });
    try {
      const ok = await waitForDrain({ maxBufferedAmount: 2 * 1024 * 1024, timeoutMs: 15000 });
      if (!ok) throw new Error('p2p_backpressure');
      const rawBytes = bodyBytes instanceof Uint8Array ? bodyBytes : bodyBytes ? new Uint8Array(bodyBytes) : null;
      const textBytes = body != null ? new TextEncoder().encode(String(body)) : new Uint8Array(0);
      const outBytes = rawBytes != null ? rawBytes : textBytes;
      const beginBin = npcEncode(prefix, {
        type: `${prefix}:req:begin`,
        id,
        method: String(method || 'GET').toUpperCase(),
        path: String(path || '/'),
        headers: headers || {},
        length: outBytes.length,
      });
      if (!beginBin) throw new Error('p2p_ctrl_unsupported_type');
      dc.send(beginBin);
      if (outBytes.length) {
        const idBytes = new TextEncoder().encode(id);
        if (idBytes.length > 255) throw new Error('p2p_id_too_long');
        const header = new Uint8Array(2 + idBytes.length);
        header[0] = 0x01;
        header[1] = idBytes.length;
        header.set(idBytes, 2);
        const packet = new Uint8Array(header.length + outBytes.length);
        packet.set(header, 0);
        packet.set(outBytes, header.length);
        dc.send(packet);
      }
      const endBin = npcEncode(prefix, { type: `${prefix}:req:end`, id });
      if (!endBin) throw new Error('p2p_ctrl_unsupported_type');
      dc.send(endBin);
    } catch (_) {
      cleanup(id);
      p.reject(new Error('p2p_send_failed'));
    }
    return await p.promise;
  };

  const requestStream = ({ method, path, headers, body, bodyBytes, timeoutMs, onBegin, onChunk, onEnd, onProgress } = {}) => {
    const id = `${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const p = createDeferred();
    const timer = setTimeout(
      () => {
        cleanup(id);
        p.reject(new Error('p2p_timeout'));
      },
      Math.max(1000, Number(timeoutMs) || 30000)
    );
    const st = {
      timer,
      resolve: p.resolve,
      reject: p.reject,
      onBegin,
      onChunk,
      onEnd,
      onProgress,
      received: 0,
      total: null,
      status: null,
      headers: null,
      aborted: false,
      queue: [],
      queueBytes: 0,
      draining: false,
      drainPromise: null,
      _lastProgressAt: 0,
      _lastAckAt: 0,
      lastAckedEncodedBytes: 0,
      ackReceivedBytes: 0,
      ackEveryBytes: 2 * 1024 * 1024,
      flowPaused: false,
      abort: () => {
        st.aborted = true;
        st.queue.length = 0;
        st.queueBytes = 0;
        sendCtrl({ type: `${prefix}:cancel`, id });
        cleanup(id);
        p.reject(new Error('p2p_abort'));
      },
    };
    pendingStreams.set(id, st);
    Promise.resolve()
      .then(async () => {
        const ok = await waitForDrain({ maxBufferedAmount: 2 * 1024 * 1024, timeoutMs: 15000 });
        if (!ok) throw new Error('p2p_backpressure');
        const rawBytes = bodyBytes instanceof Uint8Array ? bodyBytes : bodyBytes ? new Uint8Array(bodyBytes) : null;
        const textBytes = body != null ? new TextEncoder().encode(String(body)) : new Uint8Array(0);
        const outBytes = rawBytes != null ? rawBytes : textBytes;
        const beginBin = npcEncode(prefix, {
          type: `${prefix}:req:begin`,
          id,
          method: String(method || 'GET').toUpperCase(),
          path: String(path || '/'),
          headers: headers || {},
          length: outBytes.length,
        });
        if (!beginBin) throw new Error('p2p_ctrl_unsupported_type');
        dc.send(beginBin);
        if (outBytes.length) {
          const idBytes = new TextEncoder().encode(id);
          if (idBytes.length > 255) throw new Error('p2p_id_too_long');
          const header = new Uint8Array(2 + idBytes.length);
          header[0] = 0x01;
          header[1] = idBytes.length;
          header.set(idBytes, 2);
          const packet = new Uint8Array(header.length + outBytes.length);
          packet.set(header, 0);
          packet.set(outBytes, header.length);
          dc.send(packet);
        }
        const endBin = npcEncode(prefix, { type: `${prefix}:req:end`, id });
        if (!endBin) throw new Error('p2p_ctrl_unsupported_type');
        dc.send(endBin);
      })
      .catch(() => {
        cleanup(id);
        p.reject(new Error('p2p_send_failed'));
      });
    return { id, promise: p.promise, abort: st.abort };
  };

  return { ready: ready.promise, request, requestStream };
}
