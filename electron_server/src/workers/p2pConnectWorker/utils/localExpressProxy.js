const axios = require('axios');
const tableConfig = require('../../../db/table/tableConfig');

function readReqBodyBuf(reqMsg) {
  if (!reqMsg || typeof reqMsg !== 'object') return { ok: true, bodyBuf: null };
  if (reqMsg.bodyBufOverride && Buffer.isBuffer(reqMsg.bodyBufOverride)) return { ok: true, bodyBuf: reqMsg.bodyBufOverride };
  if (reqMsg.bodyBase64) {
    try {
      const b64 = String(reqMsg.bodyBase64);
      if (b64.length > 64 * 1024 * 1024) throw new Error('too_large');
      return { ok: true, bodyBuf: Buffer.from(b64, 'base64') };
    } catch (_) {
      return { ok: false, error: 'invalid_body', bodyBuf: null };
    }
  }
  if (reqMsg.body != null) {
    const b = reqMsg.body;
    if (typeof b === 'string') return { ok: true, bodyBuf: Buffer.from(b, 'utf8') };
    if (Buffer.isBuffer(b)) return { ok: true, bodyBuf: b };
    return { ok: true, bodyBuf: Buffer.from(JSON.stringify(b), 'utf8') };
  }
  return { ok: true, bodyBuf: null };
}

function normalizeProxyHeaders(headers) {
  const out = {};
  const src = headers && typeof headers === 'object' ? headers : {};
  const blocked = new Set(['connection', 'host', 'content-length', 'transfer-encoding', 'upgrade', 'proxy-connection', 'keep-alive', 'te', 'trailer', 'accept-encoding']);
  for (const [k, v] of Object.entries(src)) {
    const keyRaw = String(k || '').trim();
    const key = keyRaw.toLowerCase();
    if (!key || blocked.has(key)) continue;
    if (v == null) continue;
    const finalKey = key === 'range' ? 'Range' : key;
    out[finalKey] = Array.isArray(v) ? v.map(x => String(x)) : String(v);
  }
  return out;
}

function createLocalExpressProxy({ initDb }) {
  const getLocalExpressBaseUrl = async () => {
    await initDb();
    const httpPortRaw = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTP).catch(() => null);
    const httpsPortRaw = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTPS).catch(() => null);
    const httpPort = Number(httpPortRaw);
    const httpsPort = Number(httpsPortRaw);
    if (Number.isFinite(httpPort) && httpPort > 0) return `http://127.0.0.1:${httpPort}`;
    if (Number.isFinite(httpsPort) && httpsPort > 0) return `https://127.0.0.1:${httpsPort}`;
    return '';
  };

  const applyRealClientIpHeaders = (headers, clientIp) => {
    if (!headers || typeof headers !== 'object') return headers;
    const ip = clientIp && String(clientIp).trim();
    if (!ip) return headers;
    const out = { ...headers };
    out['x-real-ip'] = ip;
    out['x-forwarded-for'] = ip;
    return out;
  };

  const forwardToLocalExpress = async reqMsg => {
    const method = reqMsg && reqMsg.method ? String(reqMsg.method).toUpperCase() : 'GET';
    const path = reqMsg && reqMsg.path ? String(reqMsg.path) : '';
    if (!path || !path.startsWith('/')) {
      return { status: 400, headers: { 'content-type': 'application/json' }, bodyText: '{"code":-1,"message":"invalid_path"}' };
    }

    let headers = normalizeProxyHeaders(reqMsg ? reqMsg.headers : null);
    headers = applyRealClientIpHeaders(headers, reqMsg && reqMsg.clientIp);
    const body = readReqBodyBuf(reqMsg);
    if (!body.ok) {
      return { status: 400, headers: { 'content-type': 'application/json' }, bodyText: '{"code":-1,"message":"invalid_body"}' };
    }

    const base = await getLocalExpressBaseUrl();
    if (!base) {
      return { status: 503, headers: { 'content-type': 'application/json' }, bodyText: '{"code":-1,"message":"express_not_ready"}' };
    }
    console.log(`[P2pConnectWorker] forwardToLocalExpress: ${method} ${path.substring(0, 20)}`);
    let url = '';
    try {
      url = new URL(path, base).toString();
    } catch (_) {
      return { status: 400, headers: { 'content-type': 'application/json' }, bodyText: '{"code":-1,"message":"invalid_url"}' };
    }

    const r = await axios.request({
      url,
      method,
      headers,
      data: body.bodyBuf,
      timeout: 60000,
      responseType: 'arraybuffer',
      validateStatus: () => true,
    });

    const status = r ? r.status : 502;
    const resHeaders = r && r.headers && typeof r.headers === 'object' ? r.headers : {};
    const buf = r && r.data != null ? Buffer.from(r.data) : Buffer.alloc(0);
    const ctRaw = resHeaders['content-type'] || resHeaders['Content-Type'] || '';
    const ct = ctRaw ? String(ctRaw).toLowerCase() : '';
    if (ct.startsWith('text/') || ct.includes('application/json') || ct.includes('application/javascript') || ct.includes('application/xml')) {
      return { status, headers: resHeaders, bodyText: buf.toString('utf8'), bodyBuf: buf };
    }
    return { status, headers: resHeaders, bodyBuf: buf };
  };

  const forwardToLocalExpressStream = async reqMsg => {
    const method = reqMsg && reqMsg.method ? String(reqMsg.method).toUpperCase() : 'GET';
    const path = reqMsg && reqMsg.path ? String(reqMsg.path) : '';
    if (!path || !path.startsWith('/')) {
      return { status: 400, headers: { 'content-type': 'application/json' }, stream: null, bodyText: '{"code":-1,"message":"invalid_path"}' };
    }

    let headers = normalizeProxyHeaders(reqMsg ? reqMsg.headers : null);
    headers = applyRealClientIpHeaders(headers, reqMsg && reqMsg.clientIp);
    headers['accept-encoding'] = 'identity';
    const body = readReqBodyBuf(reqMsg);
    if (!body.ok) {
      return { status: 400, headers: { 'content-type': 'application/json' }, stream: null, bodyText: '{"code":-1,"message":"invalid_body"}' };
    }

    const base = await getLocalExpressBaseUrl();
    if (!base) {
      return { status: 503, headers: { 'content-type': 'application/json' }, stream: null, bodyText: '{"code":-1,"message":"express_not_ready"}' };
    }
    const range = headers['Range'] || headers['range'] || '';
    console.log(`[P2pConnectWorker] forwardToLocalExpressStream: ${method} ${path.substring(0, 50)} range=${range}`);
    let url = '';
    try {
      url = new URL(path, base).toString();
    } catch (_) {
      return { status: 400, headers: { 'content-type': 'application/json' }, stream: null, bodyText: '{"code":-1,"message":"invalid_url"}' };
    }

    const isLong = path.startsWith('/api/videoPlayer/') || path.startsWith('/api/file/rawFile') || path.startsWith('/api/file/download');
    const externalSignal = reqMsg && reqMsg.signal != null ? reqMsg.signal : null;
    const abortController = externalSignal ? null : typeof AbortController === 'function' ? new AbortController() : null;
    const signal = externalSignal || (abortController ? abortController.signal : null);
    const r = await axios.request({
      url,
      method,
      headers,
      data: body.bodyBuf,
      timeout: isLong ? 0 : 60000,
      responseType: 'stream',
      maxBodyLength: Infinity,
      maxContentLength: Infinity,
      validateStatus: () => true,
      ...(signal ? { signal } : {}),
    });

    const status = r ? r.status : 502;
    const resHeaders = r && r.headers && typeof r.headers === 'object' ? r.headers : {};
    const stream = r && r.data && typeof r.data === 'object' ? r.data : null;
    return { status, headers: resHeaders, stream, abortController };
  };

  return { getLocalExpressBaseUrl, normalizeProxyHeaders, forwardToLocalExpress, forwardToLocalExpressStream };
}

module.exports = { createLocalExpressProxy };
