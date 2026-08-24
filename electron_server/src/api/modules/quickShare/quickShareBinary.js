const MAGIC = Buffer.from([0x51, 0x53, 0x42, 0x01]);

const MSG_AUTH_REQ = 0x01;
const MSG_AUTH_RES = 0x81;
const MSG_LIST_RES = 0x82;

function writeVarint(parts, value) {
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
  parts.push(Buffer.from(out));
}

function readVarint(buf, offset0) {
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
}

function writeString(parts, s) {
  const text = s == null ? '' : String(s);
  const b = text ? Buffer.from(text, 'utf8') : Buffer.alloc(0);
  writeVarint(parts, b.length);
  if (b.length) parts.push(b);
}

function readString(buf, offset0) {
  const v = readVarint(buf, offset0);
  if (!v) return null;
  const len = v.value;
  let offset = v.offset;
  const end = offset + len;
  if (end > buf.length) return null;
  const s = len ? buf.slice(offset, end).toString('utf8') : '';
  return { value: s, offset: end };
}

function writeBool(parts, b) {
  parts.push(Buffer.from([b ? 1 : 0]));
}

function readBool(buf, offset0) {
  if (offset0 >= buf.length) return null;
  return { value: buf[offset0] !== 0, offset: offset0 + 1 };
}

function encodeEnvelope({ msgType, ok, code, writePayload } = {}) {
  const parts = [MAGIC, Buffer.from([msgType & 0xff])];
  writeBool(parts, ok === true);
  writeVarint(parts, Number.isFinite(code) ? code : 0);
  if (ok === true && typeof writePayload === 'function') {
    writePayload(parts);
  }
  return Buffer.concat(parts);
}

function decodeAuthRequest(buf) {
  const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf || []);
  if (b.length < 5) return null;
  if (!b.slice(0, 4).equals(MAGIC)) return null;
  if (b[4] !== MSG_AUTH_REQ) return null;
  let offset = 5;
  const token = readString(b, offset);
  if (!token) return null;
  offset = token.offset;
  const pwdHash = readString(b, offset);
  if (!pwdHash) return null;
  offset = pwdHash.offset;
  const pwd = readString(b, offset);
  if (!pwd) return null;
  return { qt: token.value, pwdHash: pwdHash.value, pwd: pwd.value };
}

function encodeAuthResponse({ qsat } = {}) {
  const token = qsat == null ? '' : String(qsat);
  return encodeEnvelope({
    msgType: MSG_AUTH_RES,
    ok: true,
    code: 0,
    writePayload: parts => {
      writeString(parts, token);
    },
  });
}

function encodeError({ msgType, code } = {}) {
  return encodeEnvelope({
    msgType: Number.isFinite(msgType) ? msgType : MSG_LIST_RES,
    ok: false,
    code: Number.isFinite(code) ? code : 0,
  });
}

function writeStringList(parts, list) {
  const arr = Array.isArray(list) ? list : [];
  writeVarint(parts, arr.length);
  for (const s of arr) writeString(parts, s);
}

function writeItem(parts, it) {
  const item = it && typeof it === 'object' ? it : {};
  writeString(parts, item.name);
  writeString(parts, item.relPath);
  writeString(parts, item.type);
  writeString(parts, item.ext);
  const size = item.size;
  if (size == null) {
    writeBool(parts, false);
  } else {
    writeBool(parts, true);
    writeVarint(parts, Number(size) || 0);
  }
  writeVarint(parts, Number(item.mtimeMs) || 0);
  writeVarint(parts, Number(item.ctimeMs) || 0);
}

function encodeListResponse({ share, base, segments, items } = {}) {
  const s = share && typeof share === 'object' ? share : {};
  const segs = Array.isArray(segments) ? segments : [];
  const list = Array.isArray(items) ? items : [];

  return encodeEnvelope({
    msgType: MSG_LIST_RES,
    ok: true,
    code: 0,
    writePayload: parts => {
      writeString(parts, s.remark || '');
      const endTimeMs = s.end_time ? new Date(s.end_time).getTime() : 0;
      writeVarint(parts, Number.isFinite(endTimeMs) && endTimeMs > 0 ? endTimeMs : 0);
      writeBool(parts, s.hasPwd === true);
      writeString(parts, base || '');

      writeVarint(parts, segs.length);
      for (const seg of segs) {
        const cur = seg && typeof seg === 'object' ? seg : {};
        writeString(parts, cur.name || '');
        writeString(parts, cur.relPath || '');
      }

      writeVarint(parts, list.length);
      for (const it of list) writeItem(parts, it);
    },
  });
}

function decodeEnvelope(buf) {
  const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf || []);
  if (b.length < 6) return null;
  if (!b.slice(0, 4).equals(MAGIC)) return null;
  const msgType = b[4] & 0xff;
  let offset = 5;
  const ok = readBool(b, offset);
  if (!ok) return null;
  offset = ok.offset;
  const code = readVarint(b, offset);
  if (!code) return null;
  offset = code.offset;
  return { msgType, ok: ok.value, code: code.value, offset, buf: b };
}

function decodeAuthResponse(buf) {
  const env = decodeEnvelope(buf);
  if (!env || env.msgType !== MSG_AUTH_RES) return null;
  if (!env.ok) return { ok: false, code: env.code };
  const qsat = readString(env.buf, env.offset);
  if (!qsat) return null;
  return { ok: true, code: 0, qsat: qsat.value };
}

function decodeListResponse(buf) {
  const env = decodeEnvelope(buf);
  if (!env || env.msgType !== MSG_LIST_RES) return null;
  if (!env.ok) return { ok: false, code: env.code };
  let offset = env.offset;

  const remark = readString(env.buf, offset);
  if (!remark) return null;
  offset = remark.offset;
  const endTimeMs = readVarint(env.buf, offset);
  if (!endTimeMs) return null;
  offset = endTimeMs.offset;
  const hasPwd = readBool(env.buf, offset);
  if (!hasPwd) return null;
  offset = hasPwd.offset;
  const base = readString(env.buf, offset);
  if (!base) return null;
  offset = base.offset;

  const segCount = readVarint(env.buf, offset);
  if (!segCount) return null;
  offset = segCount.offset;
  const segments = [];
  for (let i = 0; i < segCount.value; i++) {
    const name = readString(env.buf, offset);
    if (!name) return null;
    offset = name.offset;
    const relPath = readString(env.buf, offset);
    if (!relPath) return null;
    offset = relPath.offset;
    segments.push({ name: name.value, relPath: relPath.value });
  }

  const itemCount = readVarint(env.buf, offset);
  if (!itemCount) return null;
  offset = itemCount.offset;
  const items = [];
  for (let i = 0; i < itemCount.value; i++) {
    const name = readString(env.buf, offset);
    if (!name) return null;
    offset = name.offset;
    const relPath = readString(env.buf, offset);
    if (!relPath) return null;
    offset = relPath.offset;
    const type = readString(env.buf, offset);
    if (!type) return null;
    offset = type.offset;
    const ext = readString(env.buf, offset);
    if (!ext) return null;
    offset = ext.offset;
    const hasSize = readBool(env.buf, offset);
    if (!hasSize) return null;
    offset = hasSize.offset;
    let size = null;
    if (hasSize.value) {
      const sizeV = readVarint(env.buf, offset);
      if (!sizeV) return null;
      offset = sizeV.offset;
      size = sizeV.value;
    }
    const mtimeMs = readVarint(env.buf, offset);
    if (!mtimeMs) return null;
    offset = mtimeMs.offset;
    const ctimeMs = readVarint(env.buf, offset);
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
    code: 0,
    data: {
      share: {
        remark: remark.value,
        end_time: endTimeMs.value > 0 ? new Date(endTimeMs.value).toISOString() : null,
        hasPwd: hasPwd.value,
      },
      base: base.value,
      segments,
      items,
    },
  };
}

module.exports = {
  MSG_AUTH_REQ,
  MSG_AUTH_RES,
  MSG_LIST_RES,
  decodeAuthRequest,
  encodeAuthResponse,
  encodeListResponse,
  encodeError,
  decodeAuthResponse,
  decodeListResponse,
};
