import {
  QSB_MAGIC,
  QSB_MSG_AUTH_REQ,
  QSB_MSG_AUTH_RES,
  QSB_MSG_LIST_RES,
} from './constants.js';

export function qsbWriteVarint(parts, value) {
  let v = 0n;
  try {
    if (typeof value === 'bigint') v = value;
    else v = BigInt(Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : 0);
  } catch (_) {
    v = 0n;
  }
  const out = [];
  while (v >= 0x80n) {
    out.push(Number((v & 0x7fn) | 0x80n));
    v >>= 7n;
  }
  out.push(Number(v & 0xffn));
  parts.push(new Uint8Array(out));
}

export function qsbReadVarint(bytes, offset0) {
  let offset = offset0;
  let shift = 0n;
  let out = 0n;
  while (true) {
    if (offset >= bytes.length) return null;
    const b = BigInt(bytes[offset] & 0xff);
    offset += 1;
    out |= (b & 0x7fn) << shift;
    if ((b & 0x80n) === 0n) break;
    shift += 7n;
    if (shift > 63n) return null;
  }
  const num = out <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(out) : Number.MAX_SAFE_INTEGER;
  return { value: num, offset };
}

export function qsbWriteString(parts, s) {
  const text = s == null ? '' : String(s);
  const b = text ? new TextEncoder().encode(text) : new Uint8Array(0);
  qsbWriteVarint(parts, b.length);
  if (b.length) parts.push(b);
}

export function qsbReadString(bytes, offset0) {
  const v = qsbReadVarint(bytes, offset0);
  if (!v) return null;
  const len = v.value;
  let offset = v.offset;
  const end = offset + len;
  if (end > bytes.length) return null;
  const s = len ? new TextDecoder().decode(bytes.subarray(offset, end)) : '';
  return { value: s, offset: end };
}

export function qsbReadBool(bytes, offset0) {
  if (offset0 >= bytes.length) return null;
  return { value: bytes[offset0] !== 0, offset: offset0 + 1 };
}

export function qsbConcat(parts) {
  let n = 0;
  for (const p of parts) n += p.length;
  const out = new Uint8Array(n);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

export function qsbEncodeAuthReq({ qt, pwdHash, pwd } = {}) {
  const parts = [QSB_MAGIC, new Uint8Array([QSB_MSG_AUTH_REQ])];
  qsbWriteString(parts, qt || '');
  qsbWriteString(parts, pwdHash || '');
  qsbWriteString(parts, pwd || '');
  return qsbConcat(parts);
}

export function qsbDecodeEnvelope(bytes) {
  if (!bytes || bytes.length < 6) return null;
  if (bytes[0] !== QSB_MAGIC[0] || bytes[1] !== QSB_MAGIC[1] || bytes[2] !== QSB_MAGIC[2] || bytes[3] !== QSB_MAGIC[3]) return null;
  const msgType = bytes[4] & 0xff;
  let offset = 5;
  const ok = qsbReadBool(bytes, offset);
  if (!ok) return null;
  offset = ok.offset;
  const code = qsbReadVarint(bytes, offset);
  if (!code) return null;
  offset = code.offset;
  return { msgType, ok: ok.value, code: code.value, offset };
}

export function qsbDecodeAuthRes(bytes) {
  const env = qsbDecodeEnvelope(bytes);
  if (!env || env.msgType !== QSB_MSG_AUTH_RES) return null;
  if (!env.ok) return { ok: false, code: env.code };
  const qsat = qsbReadString(bytes, env.offset);
  if (!qsat) return null;
  return { ok: true, qsat: qsat.value };
}

export function qsbDecodeListRes(bytes) {
  const env = qsbDecodeEnvelope(bytes);
  if (!env || env.msgType !== QSB_MSG_LIST_RES) return null;
  if (!env.ok) return { ok: false, code: env.code };
  let offset = env.offset;

  const remark = qsbReadString(bytes, offset);
  if (!remark) return null;
  offset = remark.offset;
  const endTimeMs = qsbReadVarint(bytes, offset);
  if (!endTimeMs) return null;
  offset = endTimeMs.offset;
  const hasPwd = qsbReadBool(bytes, offset);
  if (!hasPwd) return null;
  offset = hasPwd.offset;
  const base = qsbReadString(bytes, offset);
  if (!base) return null;
  offset = base.offset;

  const segCount = qsbReadVarint(bytes, offset);
  if (!segCount) return null;
  offset = segCount.offset;
  const segments = [];
  for (let i = 0; i < segCount.value; i++) {
    const name = qsbReadString(bytes, offset);
    if (!name) return null;
    offset = name.offset;
    const relPath = qsbReadString(bytes, offset);
    if (!relPath) return null;
    offset = relPath.offset;
    segments.push({ name: name.value, relPath: relPath.value });
  }

  const itemCount = qsbReadVarint(bytes, offset);
  if (!itemCount) return null;
  offset = itemCount.offset;
  const items = [];
  for (let i = 0; i < itemCount.value; i++) {
    const name = qsbReadString(bytes, offset);
    if (!name) return null;
    offset = name.offset;
    const relPath = qsbReadString(bytes, offset);
    if (!relPath) return null;
    offset = relPath.offset;
    const type = qsbReadString(bytes, offset);
    if (!type) return null;
    offset = type.offset;
    const ext = qsbReadString(bytes, offset);
    if (!ext) return null;
    offset = ext.offset;
    const hasSize = qsbReadBool(bytes, offset);
    if (!hasSize) return null;
    offset = hasSize.offset;
    let size = null;
    if (hasSize.value) {
      const sizeV = qsbReadVarint(bytes, offset);
      if (!sizeV) return null;
      offset = sizeV.offset;
      size = sizeV.value;
    }
    const mtimeMs = qsbReadVarint(bytes, offset);
    if (!mtimeMs) return null;
    offset = mtimeMs.offset;
    const ctimeMs = qsbReadVarint(bytes, offset);
    if (!ctimeMs) return null;
    offset = ctimeMs.offset;
    items.push({
      name: name.value,
      relPath: relPath.value,
      type: type.value,
      ext: ext.value,
      size,
      mtimeMs: mtimeMs.value,
      ctimeMs: ctimeMs.value || null,
    });
  }

  return {
    ok: true,
    data: {
      share: {
        remark: remark.value || null,
        end_time: endTimeMs.value > 0 ? new Date(endTimeMs.value).toISOString() : null,
        hasPwd: !!hasPwd.value,
      },
      base: base.value,
      segments,
      items,
    },
  };
}