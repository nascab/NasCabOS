const fs = require('fs');
const jwtUtil = require('../../../utils/jwtUtil');
const { assertMountSupportedOnPlatform } = require('../../../utils/mountPlatformUtil');

function safeJsonParse(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function isQuickProtocol(protocol) {
  const p = ensureString(protocol).trim().toLowerCase();
  return p === 'webdav' || p === 'ftp' || p === 'sftp';
}

function normalizeWebPath(raw) {
  const t = ensureString(raw).trim();
  if (!t) return '/';
  return t.startsWith('/') ? t : `/${t}`;
}

function isValidMountFolderName(value) {
  const t = ensureString(value).trim();
  if (!t) return false;
  if (t === '.' || t === '..') return false;
  if (t.includes('/') || t.includes('\\')) return false;
  if (/[\x00-\x1F]/.test(t)) return false;
  if (t.endsWith(' ') || t.endsWith('.')) return false;
  if (/[<>:"|?*]/.test(t)) return false;
  return true;
}

async function ensureDirReadableWritable(dirPath) {
  const p = ensureString(dirPath).trim();
  if (!p) {
    const err = new Error('fileMount.MOUNT_PARENT_NOT_FOUND');
    err.statusCode = 400;
    throw err;
  }

  let stat;
  try {
    stat = await fs.promises.stat(p);
  } catch (_) {
    const err = new Error('fileMount.MOUNT_PARENT_NOT_FOUND');
    err.statusCode = 400;
    throw err;
  }
  if (!stat.isDirectory()) {
    const err = new Error('fileMount.MOUNT_PARENT_NOT_DIR');
    err.statusCode = 400;
    throw err;
  }

  const mode = fs.constants.R_OK | fs.constants.W_OK | (fs.constants.X_OK || 0);
  try {
    await fs.promises.access(p, mode);
  } catch (_) {
    const err = new Error('fileMount.MOUNT_PARENT_NO_ACCESS');
    err.statusCode = 400;
    throw err;
  }
}

function normalizeProtocolConfig(config) {
  if (!config || typeof config !== 'object') return null;

  const protocol = ensureString(config.protocol).trim().toLowerCase();
  if (!isQuickProtocol(protocol)) return config;

  const host = ensureString(config.host).trim();
  const username = ensureString(config.username).trim();
  if (!host || !username) {
    const err = new Error('common.INVALID_PARAMS');
    err.statusCode = 400;
    throw err;
  }

  let scheme = null;
  if (protocol === 'webdav') {
    const s = ensureString(config.scheme).trim().toLowerCase();
    scheme = s === 'https' ? 'https' : 'http';
  }

  const portRaw = Number(config.port);
  let port = Number.isFinite(portRaw) && portRaw > 0 && portRaw <= 65535 ? portRaw : null;
  if (!port) {
    if (protocol === 'sftp') port = 22;
    else if (protocol === 'ftp') port = 21;
    else port = scheme === 'https' ? 443 : 80;
  }

  const remotePath = normalizeWebPath(config.remote_path);
  const out = {
    protocol,
    host,
    port,
    username,
    remote_path: remotePath,
  };

  const password = ensureString(config.password).trim();
  if (password) out.password = password;
  if (protocol === 'webdav') out.scheme = scheme;

  const vendor = ensureString(config.vendor).trim();
  if (protocol === 'webdav' && vendor) out.vendor = vendor;
  if (protocol === 'webdav') {
    if (typeof config.webdav_skip_verify === 'boolean') {
      out.webdav_skip_verify = config.webdav_skip_verify;
    }
    if (typeof config.webdav_trailing_slash === 'boolean') {
      out.webdav_trailing_slash = config.webdav_trailing_slash;
    }
  }

  const args = Array.isArray(config.args) ? config.args.map(a => ensureString(a)).filter(Boolean) : null;
  if (args && args.length) out.args = args;

  if (config.env && typeof config.env === 'object' && !Array.isArray(config.env)) {
    const envOut = {};
    for (const [k, v] of Object.entries(config.env)) {
      const kk = ensureString(k).trim();
      if (!kk) continue;
      envOut[kk] = typeof v === 'string' ? v : v;
    }
    out.env = envOut;
  }

  return out;
}

function buildQuickRemoteDisplay(config) {
  const protocol = ensureString(config.protocol).trim().toLowerCase();
  const host = ensureString(config.host).trim();
  const port = Number(config.port) || 0;
  const remotePath = normalizeWebPath(config.remote_path);
  if (protocol === 'webdav') {
    const scheme = ensureString(config.scheme).trim().toLowerCase() === 'https' ? 'https' : 'http';
    return `${scheme}://${host}:${port}${remotePath}`;
  }
  return `${protocol}://${host}:${port}${remotePath}`;
}

function isEncryptableKey(key) {
  const k = String(key || '').toLowerCase();
  return k.includes('password') || k.includes('secret') || k.includes('token') || k.endsWith('_key') || k.includes('access_key');
}

function deepEncryptSensitive(input) {
  if (input === null || input === undefined) return input;
  if (Array.isArray(input)) return input.map(deepEncryptSensitive);
  if (typeof input !== 'object') return input;
  const out = {};
  for (const [k, v] of Object.entries(input)) {
    if (typeof v === 'string' && v && isEncryptableKey(k)) {
      out[k] = jwtUtil.isEncryptedPassword(v) ? v : jwtUtil.encryptPassword(v);
      continue;
    }
    out[k] = deepEncryptSensitive(v);
  }
  return out;
}

function deepRedactSensitive(input) {
  if (input === null || input === undefined) return input;
  if (Array.isArray(input)) return input.map(deepRedactSensitive);
  if (typeof input !== 'object') return input;
  const out = {};
  for (const [k, v] of Object.entries(input)) {
    if (isEncryptableKey(k)) {
      out[k] = '';
      continue;
    }
    out[k] = deepRedactSensitive(v);
  }
  return out;
}

class FileMountService {
  constructor(knexMain) {
    this.knexMain = knexMain;
    this.tableName = 'file_mount';
  }

  async list({ uid, status } = {}) {
    let q = this.knexMain(this.tableName).select('*').orderBy('id', 'desc');
    if (uid !== undefined) q = q.where({ uid: String(uid) });
    if (status !== undefined) q = q.where({ status: String(status) });
    const rows = await q;
    return rows.map(r => {
      const cfg = safeJsonParse(r.config);
      return {
        ...r,
        config: cfg ? deepRedactSensitive(cfg) : null,
      };
    });
  }

  async upsert({ uid, id, name, mountPath, remote, config }) {
    assertMountSupportedOnPlatform('fileMount.PLATFORM_NOT_SUPPORTED');
    const uidStr = String(uid);
    const idNum = id === undefined || id === null ? null : Number(id);
    const hasId = Number.isFinite(idNum) && idNum > 0;
    const nameStr = String(name || '').trim();
    const mountPathStr = String(mountPath || '').trim();
    let remoteStr = String(remote || '').trim();

    const protocolRaw = config && typeof config === 'object' ? ensureString(config.protocol).trim().toLowerCase() : '';
    const allowEmptyRemote = isQuickProtocol(protocolRaw);

    if (!nameStr || !mountPathStr || (!remoteStr && !allowEmptyRemote)) {
      const err = new Error('common.INVALID_PARAMS');
      err.statusCode = 400;
      throw err;
    }
    if (!isValidMountFolderName(nameStr)) {
      const err = new Error('fileMount.INVALID_MOUNT_NAME');
      err.statusCode = 400;
      throw err;
    }
    await ensureDirReadableWritable(mountPathStr);

    const normalizedConfig = config && typeof config === 'object' ? normalizeProtocolConfig(config) : null;
    if (!remoteStr && normalizedConfig && isQuickProtocol(normalizedConfig.protocol)) {
      remoteStr = buildQuickRemoteDisplay(normalizedConfig);
    }

    if (hasId) {
      const existing = await this.knexMain(this.tableName).where({ id: idNum, uid: uidStr }).first();
      if (!existing) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }

      const prevMountPath = String(existing.mount_path || '').trim();
      const prevName = String(existing.name || '').trim();
      if (String(existing.status || '').trim() === 'running' && (prevMountPath !== mountPathStr || prevName !== nameStr)) {
        const err = new Error('common.INVALID_PARAMS');
        err.statusCode = 400;
        throw err;
      }

      let mergedConfig = null;
      if (normalizedConfig && typeof normalizedConfig === 'object') {
        const incoming = deepEncryptSensitive(normalizedConfig);
        const prev = safeJsonParse(existing.config);
        if (prev && typeof prev === 'object') {
          mergedConfig = { ...prev, ...incoming };
          if (incoming.password === undefined || String(incoming.password || '').trim() === '') {
            if (typeof prev.password === 'string' && prev.password.trim()) {
              mergedConfig.password = prev.password;
            } else {
              delete mergedConfig.password;
            }
          }
        } else {
          mergedConfig = incoming;
        }
      }
      const configText = mergedConfig ? JSON.stringify(mergedConfig) : null;
      await this.knexMain(this.tableName).where({ id: idNum }).update({
        name: nameStr,
        mount_path: mountPathStr,
        remote: remoteStr,
        config: configText,
        update_time: new Date(),
      });
      return { id: idNum };
    }

    const encryptedConfig = normalizedConfig && typeof normalizedConfig === 'object' ? deepEncryptSensitive(normalizedConfig) : null;
    const configText = encryptedConfig ? JSON.stringify(encryptedConfig) : null;

    const [newId] = await this.knexMain(this.tableName).insert({
      uid: uidStr,
      name: nameStr,
      mount_path: mountPathStr,
      remote: remoteStr,
      status: 'stopped',
      auto_running: 0,
      config: configText,
      last_error: null,
      create_time: new Date(),
      update_time: new Date(),
    });
    return { id: newId };
  }

  async remove({ id }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) {
      const err = new Error('validation.ID_INVALID');
      err.statusCode = 400;
      throw err;
    }
    const existed = await this.knexMain(this.tableName).where({ id: idNum }).first();
    if (!existed) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    await this.knexMain(this.tableName).where({ id: idNum }).del();
    return { ok: true };
  }
}

module.exports = { FileMountService };
