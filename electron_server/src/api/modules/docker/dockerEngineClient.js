const http = require('http');
const https = require('https');
const fs = require('fs');
const { URL } = require('url');

const DEFAULT_API_VERSION = 'v1.44';
const DEFAULT_REQUEST_TIMEOUT_MS = 12 * 1000;
const API_VERSION_FALLBACKS = ['v1.52', 'v1.47', 'v1.44', 'v1.43', 'v1.41', 'v1.40'];

function trimText(value) {
  return value == null ? '' : String(value).trim();
}

function parseJsonBuffer(buffer, fallback = null) {
  const text = Buffer.isBuffer(buffer) ? buffer.toString('utf8').trim() : String(buffer || '').trim();
  if (!text) return fallback;
  try {
    return JSON.parse(text);
  } catch (_) {
    return fallback;
  }
}

function parseApiErrorMessage(buffer) {
  const parsed = parseJsonBuffer(buffer, null);
  if (parsed && typeof parsed.message === 'string' && parsed.message.trim()) {
    return parsed.message.trim();
  }
  const text = Buffer.isBuffer(buffer) ? buffer.toString('utf8').trim() : String(buffer || '').trim();
  return text;
}

function resolveDockerEndpoint() {
  const host = trimText(process.env.DOCKER_HOST);
  if (host) {
    if (host.startsWith('unix://')) {
      return { transport: 'socket', socketPath: host.slice('unix://'.length) };
    }
    if (host.startsWith('npipe://')) {
      let pipePath = host.slice('npipe://'.length).replace(/\//g, '\\');
      if (!pipePath.startsWith('\\\\.\\pipe\\')) {
        pipePath = `\\\\.\\pipe\\${pipePath.replace(/^\\+/, '')}`;
      }
      return { transport: 'socket', socketPath: pipePath };
    }
    const parsed = new URL(host.includes('://') ? host : `tcp://${host}`);
    const isHttps = parsed.protocol === 'https:';
    return {
      transport: 'tcp',
      protocol: isHttps ? 'https' : 'http',
      hostname: parsed.hostname,
      port: Number(parsed.port || (isHttps ? 2376 : 2375)),
    };
  }
  if (process.platform === 'win32') {
    return { transport: 'socket', socketPath: '\\\\.\\pipe\\docker_engine' };
  }
  return { transport: 'socket', socketPath: '/var/run/docker.sock' };
}

function buildApiPath(apiVersion, path, query) {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  const queryString = query && Object.keys(query).length > 0
    ? `?${new URLSearchParams(query).toString()}`
    : '';
  return `/${apiVersion}${normalizedPath}${queryString}`;
}

function createEngineError(message, { statusCode = 500, timedOut = false, cause = null } = {}) {
  const error = cause instanceof Error ? cause : new Error(message || 'Docker API request failed');
  if (message) error.message = message;
  error.statusCode = statusCode;
  error.timedOut = timedOut;
  return error;
}

function demuxDockerFrames(chunk, state, onFrame) {
  state.buffer = Buffer.concat([state.buffer, chunk]);
  while (state.buffer.length >= 8) {
    const streamType = state.buffer[0];
    const size = state.buffer.readUInt32BE(4);
    if (state.buffer.length < 8 + size) break;
    const payload = state.buffer.slice(8, 8 + size);
    state.buffer = state.buffer.slice(8 + size);
    onFrame(payload, streamType === 2 ? 'stderr' : 'stdout');
  }
}

function parseMemoryToBytes(value) {
  const raw = trimText(value).toLowerCase();
  if (!raw) return null;
  const match = /^(\d+(?:\.\d+)?)([bkmg])?$/i.exec(raw);
  if (!match) return null;
  const amount = Number(match[1]);
  if (!Number.isFinite(amount) || amount < 0) return null;
  const unit = (match[2] || 'b').toLowerCase();
  const multipliers = { b: 1, k: 1024, m: 1024 ** 2, g: 1024 ** 3 };
  return Math.floor(amount * (multipliers[unit] || 1));
}

function parseCpusToNano(value) {
  const num = Number(trimText(value));
  if (!Number.isFinite(num) || num <= 0) return null;
  return Math.floor(num * 1e9);
}

function splitImageRef(imageRef) {
  const ref = trimText(imageRef);
  const tagIndex = ref.lastIndexOf(':');
  const slashIndex = ref.lastIndexOf('/');
  const hasTag = tagIndex > slashIndex;
  return {
    fromImage: hasTag ? ref.slice(0, tagIndex) : ref,
    tag: hasTag ? ref.slice(tagIndex + 1) : 'latest',
  };
}

class DockerEngineClient {
  constructor(options = {}) {
    this.apiVersion = trimText(options.apiVersion) || DEFAULT_API_VERSION;
    this.defaultTimeoutMs = Number(options.defaultTimeoutMs) || DEFAULT_REQUEST_TIMEOUT_MS;
    this.endpoint = resolveDockerEndpoint();
    this._negotiatedApiVersion = trimText(options.apiVersion) || '';
    this._negotiatePromise = null;
  }

  async ensureApiVersion() {
    if (this._negotiatedApiVersion) {
      this.apiVersion = this._negotiatedApiVersion;
      return this._negotiatedApiVersion;
    }
    if (this._negotiatePromise) {
      return this._negotiatePromise;
    }
    this._negotiatePromise = this._negotiateApiVersion()
      .then(version => {
        this._negotiatedApiVersion = version;
        this.apiVersion = version;
        return version;
      })
      .finally(() => {
        this._negotiatePromise = null;
      });
    return this._negotiatePromise;
  }

  async _negotiateApiVersion() {
    try {
      const result = await this._doRequestRaw({
        unversioned: true,
        method: 'GET',
        path: '/version',
        timeoutMs: 8000,
      });
      const parsed = parseJsonBuffer(result.buffer, {});
      const apiVersion = trimText(parsed && parsed.ApiVersion);
      if (apiVersion) {
        const normalized = apiVersion.startsWith('v') ? apiVersion : `v${apiVersion}`;
        this.apiVersion = normalized;
        await this._doRequestRaw({
          method: 'GET',
          path: '/_ping',
          timeoutMs: 5000,
        });
        return normalized;
      }
    } catch (_) {}

    for (const candidate of API_VERSION_FALLBACKS) {
      try {
        this.apiVersion = candidate;
        await this._doRequestRaw({
          method: 'GET',
          path: '/_ping',
          timeoutMs: 4000,
        });
        return candidate;
      } catch (_) {}
    }
    throw createEngineError('Unable to negotiate Docker Engine API version', { statusCode: 503 });
  }

  getDockerHostLabel() {
    const host = trimText(process.env.DOCKER_HOST);
    return host || 'local';
  }

  _getTransport() {
    if (this.endpoint.transport === 'socket') {
      return http;
    }
    return this.endpoint.protocol === 'https' ? https : http;
  }

  _buildRequestOptions({ method, path, headers = {}, timeoutMs, signal }) {
    const options = {
      method,
      path,
      headers: {
        ...headers,
      },
      timeout: timeoutMs > 0 ? timeoutMs : undefined,
    };

    if (this.endpoint.transport === 'socket') {
      options.socketPath = this.endpoint.socketPath;
    } else {
      options.hostname = this.endpoint.hostname;
      options.port = this.endpoint.port;
    }

    return { options, signal };
  }

  _doRequestRaw({ method = 'GET', path, query, headers = {}, body = null, timeoutMs, signal, unversioned = false }) {
    const effectiveTimeout = timeoutMs === 0 ? 0 : (timeoutMs != null ? timeoutMs : this.defaultTimeoutMs);
    const apiPath = unversioned
      ? (path.startsWith('/') ? path : `/${path}`)
      : buildApiPath(this.apiVersion, path, query);
    const transport = this._getTransport();
    const requestHeaders = { ...headers };
    let payload = null;
    if (body != null) {
      if (Buffer.isBuffer(body)) {
        payload = body;
      } else if (typeof body === 'string') {
        payload = body;
      } else {
        if (!requestHeaders['Content-Type']) {
          requestHeaders['Content-Type'] = 'application/json';
        }
        payload = JSON.stringify(body);
      }
    }
    const { options } = this._buildRequestOptions({
      method,
      path: apiPath,
      headers: requestHeaders,
      timeoutMs: effectiveTimeout,
      signal,
    });

    return new Promise((resolve, reject) => {
      let settled = false;
      const finish = (error, value) => {
        if (settled) return;
        settled = true;
        if (error) reject(error);
        else resolve(value);
      };

      const req = transport.request(options, res => {
        const chunks = [];
        res.on('data', chunk => chunks.push(chunk));
        res.on('end', () => {
          const buffer = Buffer.concat(chunks);
          if (res.statusCode >= 400) {
            finish(createEngineError(parseApiErrorMessage(buffer) || `Docker API HTTP ${res.statusCode}`, {
              statusCode: res.statusCode,
            }));
            return;
          }
          finish(null, {
            statusCode: res.statusCode,
            headers: res.headers,
            buffer,
          });
        });
      });

      req.on('error', error => {
        finish(createEngineError(error.message || 'Docker API connection failed', {
          statusCode: 503,
          cause: error,
        }));
      });

      req.on('timeout', () => {
        req.destroy();
        finish(createEngineError('Docker API request timed out', {
          statusCode: 503,
          timedOut: true,
        }));
      });

      if (signal) {
        const onAbort = () => {
          req.destroy();
          finish(createEngineError('Docker API request aborted', { statusCode: 499 }));
        };
        if (signal.aborted) {
          onAbort();
          return;
        }
        signal.addEventListener('abort', onAbort, { once: true });
      }

      if (payload != null) {
        req.write(payload);
      }
      req.end();
    });
  }

  async _requestRaw(options) {
    if (!options.unversioned) {
      await this.ensureApiVersion();
    }
    return this._doRequestRaw(options);
  }

  async requestJson(options) {
    const result = await this._requestRaw(options);
    return parseJsonBuffer(result.buffer, null);
  }

  async requestText(options) {
    const result = await this._requestRaw(options);
    return result.buffer.toString('utf8');
  }

  async _requestStream({ method = 'GET', path, query, headers = {}, body = null, timeoutMs = 0, signal, onData }) {
    await this.ensureApiVersion();
    const apiPath = buildApiPath(this.apiVersion, path, query);
    const transport = this._getTransport();
    const { options } = this._buildRequestOptions({
      method,
      path: apiPath,
      headers,
      timeoutMs,
      signal,
    });

    return new Promise((resolve, reject) => {
      let settled = false;
      const req = transport.request(options, res => {
        if (res.statusCode >= 400) {
          const chunks = [];
          res.on('data', chunk => chunks.push(chunk));
          res.on('end', () => {
            if (settled) return;
            settled = true;
            reject(createEngineError(parseApiErrorMessage(Buffer.concat(chunks)) || `Docker API HTTP ${res.statusCode}`, {
              statusCode: res.statusCode,
            }));
          });
          return;
        }

        res.on('data', chunk => {
          if (typeof onData === 'function') onData(chunk);
        });
        res.on('end', () => {
          if (settled) return;
          settled = true;
          resolve({ statusCode: res.statusCode });
        });
      });

      req.on('error', error => {
        if (settled) return;
        settled = true;
        reject(createEngineError(error.message || 'Docker API stream failed', {
          statusCode: 503,
          cause: error,
        }));
      });

      if (signal) {
        const onAbort = () => {
          req.destroy();
          if (!settled) {
            settled = true;
            reject(createEngineError('Docker API stream aborted', { statusCode: 499 }));
          }
        };
        if (signal.aborted) {
          onAbort();
          return;
        }
        signal.addEventListener('abort', onAbort, { once: true });
      }

      if (body != null) {
        if (Buffer.isBuffer(body)) req.write(body);
        else req.write(typeof body === 'string' ? body : JSON.stringify(body));
      }
      req.end();
    });
  }

  async ping(options = {}) {
    await this.ensureApiVersion();
    await this._doRequestRaw({
      method: 'GET',
      path: '/_ping',
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
    return true;
  }

  async info(options = {}) {
    return await this.requestJson({
      method: 'GET',
      path: '/info',
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
  }

  async listImages({ all = true } = {}, options = {}) {
    return await this.requestJson({
      method: 'GET',
      path: '/images/json',
      query: { all: all ? 'true' : 'false' },
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
  }

  async inspectImage(name, options = {}) {
    return await this.requestJson({
      method: 'GET',
      path: `/images/${encodeURIComponent(name)}/json`,
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
  }

  async deleteImage(name, { force = false } = {}, options = {}) {
    return await this.requestJson({
      method: 'DELETE',
      path: `/images/${encodeURIComponent(name)}`,
      query: force ? { force: 'true' } : {},
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
  }

  async tagImage(name, { repo, tag }, options = {}) {
    return await this.requestJson({
      method: 'POST',
      path: `/images/${encodeURIComponent(name)}/tag`,
      query: { repo, tag },
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
  }

  async pullImage(imageRef, { auth, onProgress, signal, checkCancelled } = {}) {
    const { fromImage, tag } = splitImageRef(imageRef);
    const headers = {};
    if (auth && auth.username && auth.password) {
      const serveraddress = trimText(auth.registry || auth.serveraddress || fromImage.split('/')[0]);
      headers['X-Registry-Auth'] = Buffer.from(JSON.stringify({
        username: auth.username,
        password: auth.password,
        serveraddress,
      })).toString('base64');
    }

    return await this._requestStream({
      method: 'POST',
      path: '/images/create',
      query: { fromImage, tag },
      headers,
      signal,
      onData: chunk => {
        if (typeof checkCancelled === 'function') checkCancelled();
        if (typeof onProgress !== 'function') return;
        const text = chunk.toString('utf8');
        text.split(/\r?\n/).forEach(line => {
          const trimmed = line.trim();
          if (!trimmed) return;
          const parsed = parseJsonBuffer(trimmed, null);
          if (parsed && parsed.status) onProgress(parsed.status);
          else if (parsed && parsed.error) onProgress(parsed.error);
          else onProgress(trimmed);
        });
      },
    });
  }

  async loadImage(archivePath, { onProgress, signal, checkCancelled } = {}) {
    await this.ensureApiVersion();
    const apiPath = buildApiPath(this.apiVersion, '/images/load');
    const transport = this._getTransport();
    const { options } = this._buildRequestOptions({
      method: 'POST',
      path: apiPath,
      headers: { 'Content-Type': 'application/x-tar' },
      timeoutMs: 0,
      signal,
    });

    return new Promise((resolve, reject) => {
      let settled = false;
      const finish = (error, value) => {
        if (settled) return;
        settled = true;
        if (error) reject(error);
        else resolve(value);
      };

      const req = transport.request(options, res => {
        if (res.statusCode >= 400) {
          const chunks = [];
          res.on('data', chunk => chunks.push(chunk));
          res.on('end', () => {
            finish(createEngineError(parseApiErrorMessage(Buffer.concat(chunks)) || `Docker API HTTP ${res.statusCode}`, {
              statusCode: res.statusCode,
            }));
          });
          return;
        }
        res.on('data', chunk => {
          if (typeof checkCancelled === 'function') checkCancelled();
          if (typeof onProgress !== 'function') return;
          chunk.toString('utf8').split(/\r?\n/).forEach(line => {
            const trimmed = line.trim();
            if (!trimmed) return;
            const parsed = parseJsonBuffer(trimmed, null);
            if (parsed && parsed.stream) onProgress(parsed.stream);
            else onProgress(trimmed);
          });
        });
        res.on('end', () => finish(null, { statusCode: res.statusCode }));
      });

      req.on('error', error => {
        finish(createEngineError(error.message || 'Docker API load failed', {
          statusCode: 503,
          cause: error,
        }));
      });

      if (signal) {
        const onAbort = () => {
          req.destroy();
          finish(createEngineError('Docker API load aborted', { statusCode: 499 }));
        };
        if (signal.aborted) {
          onAbort();
          return;
        }
        signal.addEventListener('abort', onAbort, { once: true });
      }

      const stream = fs.createReadStream(archivePath);
      stream.on('error', error => {
        req.destroy();
        finish(createEngineError(error.message || 'Failed to read image archive', { statusCode: 500, cause: error }));
      });
      stream.on('data', () => {
        if (typeof checkCancelled === 'function') checkCancelled();
      });
      stream.pipe(req);
    });
  }

  async listContainers({ all = true, filters = null } = {}, options = {}) {
    const query = { all: all ? 'true' : 'false', size: 'false' };
    if (filters && typeof filters === 'object' && Object.keys(filters).length > 0) {
      query.filters = JSON.stringify(filters);
    }
    return await this.requestJson({
      method: 'GET',
      path: '/containers/json',
      query,
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
  }

  async inspectContainer(id, options = {}) {
    return await this.requestJson({
      method: 'GET',
      path: `/containers/${encodeURIComponent(id)}/json`,
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
  }

  async createContainer(spec, { name = '' } = {}, options = {}) {
    const query = name ? { name } : {};
    return await this.requestJson({
      method: 'POST',
      path: '/containers/create',
      query,
      body: spec,
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
  }

  async startContainer(id, options = {}) {
    await this._requestRaw({
      method: 'POST',
      path: `/containers/${encodeURIComponent(id)}/start`,
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
    return { id };
  }

  async stopContainer(id, { timeout = 10 } = {}, options = {}) {
    await this._requestRaw({
      method: 'POST',
      path: `/containers/${encodeURIComponent(id)}/stop`,
      query: { t: String(timeout) },
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
    return { id };
  }

  async deleteContainer(id, { force = false, removeVolumes = false } = {}, options = {}) {
    const query = {};
    if (force) query.force = 'true';
    if (removeVolumes) query.v = 'true';
    await this._requestRaw({
      method: 'DELETE',
      path: `/containers/${encodeURIComponent(id)}`,
      query,
      timeoutMs: options.timeoutMs,
      signal: options.signal,
    });
    return { id };
  }

  async getContainerLogs(id, {
    tail = 200,
    since = '',
    until = '',
    follow = false,
    onLine,
    signal,
    checkCancelled,
  } = {}) {
    const query = {
      stdout: 'true',
      stderr: 'true',
      timestamps: 'true',
      tail: String(tail),
    };
    if (since) query.since = since;
    if (until) query.until = until;
    if (follow) query.follow = 'true';

    if (!follow) {
      const result = await this._requestRaw({
        method: 'GET',
        path: `/containers/${encodeURIComponent(id)}/logs`,
        query,
        timeoutMs: 0,
        signal,
      });
      const lines = [];
      const state = { buffer: Buffer.alloc(0) };
      demuxDockerFrames(result.buffer, state, (payload, source) => {
        payload.toString('utf8').split(/\r?\n/).forEach(line => {
          const text = line.trimEnd();
          if (text) lines.push({ text, source });
        });
      });
      if (state.buffer.length > 0) {
        const text = state.buffer.toString('utf8').trimEnd();
        if (text) lines.push({ text, source: 'stdout' });
      }
      return lines;
    }

    const state = { buffer: Buffer.alloc(0) };
    let textRemain = '';
    await this._requestStream({
      method: 'GET',
      path: `/containers/${encodeURIComponent(id)}/logs`,
      query,
      signal,
      onData: chunk => {
        if (typeof checkCancelled === 'function') checkCancelled();
        demuxDockerFrames(chunk, state, (payload, source) => {
          const combined = textRemain + payload.toString('utf8');
          const parts = combined.split(/\r?\n/);
          textRemain = parts.pop() || '';
          parts.forEach(line => {
            const text = line.trimEnd();
            if (!text) return;
            if (typeof onLine === 'function') onLine(text, source);
          });
        });
      },
    });
    if (textRemain.trim()) {
      if (typeof onLine === 'function') onLine(textRemain.trimEnd(), 'stdout');
    }
    return { followed: true };
  }
}

module.exports = {
  DockerEngineClient,
  parseMemoryToBytes,
  parseCpusToNano,
  splitImageRef,
  resolveDockerEndpoint,
};
