const fs = require('fs');
const jwtUtil = require('../../../utils/jwtUtil');
const { assertMountSupportedOnPlatform } = require('../../../utils/mountPlatformUtil');
const { normalizeOpenlistMountPath } = require('../../../utils/mountPathUtil');
const { isAllowedOpenlistDriver } = require('../../../workers/openlist/openlistDriverCatalog');

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
    const err = new Error('openlistMount.MOUNT_PARENT_NOT_FOUND');
    err.statusCode = 400;
    throw err;
  }
  let stat;
  try {
    stat = await fs.promises.stat(p);
  } catch (_) {
    const err = new Error('openlistMount.MOUNT_PARENT_NOT_FOUND');
    err.statusCode = 400;
    throw err;
  }
  if (!stat.isDirectory()) {
    const err = new Error('openlistMount.MOUNT_PARENT_NOT_DIR');
    err.statusCode = 400;
    throw err;
  }
  const mode = fs.constants.R_OK | fs.constants.W_OK | (fs.constants.X_OK || 0);
  try {
    await fs.promises.access(p, mode);
  } catch (_) {
    const err = new Error('openlistMount.MOUNT_PARENT_NO_ACCESS');
    err.statusCode = 400;
    throw err;
  }
}

function isEncryptableKey(key) {
  const k = String(key || '').toLowerCase();
  return (
    k.includes('password') ||
    k.includes('secret') ||
    k.includes('token') ||
    k.includes('refresh') ||
    k.endsWith('_key') ||
    k.includes('access_key')
  );
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

class OpenlistMountService {
  constructor(knexMain) {
    this.knexMain = knexMain;
    this.tableName = 'openlist_mount';
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

  async upsert({ uid, id, name, mountPath, driver, config, openlistMountPath }) {
    assertMountSupportedOnPlatform('openlistMount.PLATFORM_NOT_SUPPORTED');
    const uidStr = String(uid);
    const idNum = id === undefined || id === null ? null : Number(id);
    const hasId = Number.isFinite(idNum) && idNum > 0;
    const nameStr = String(name || '').trim();
    const mountPathStr = String(mountPath || '').trim();
    const driverStr = String(driver || '').trim();

    if (!nameStr || !mountPathStr || !driverStr) {
      const err = new Error('common.INVALID_PARAMS');
      err.statusCode = 400;
      throw err;
    }
    if (!isValidMountFolderName(nameStr)) {
      const err = new Error('openlistMount.INVALID_MOUNT_NAME');
      err.statusCode = 400;
      throw err;
    }
    if (!isAllowedOpenlistDriver(driverStr)) {
      const err = new Error('openlistMount.DRIVER_NOT_ALLOWED');
      err.statusCode = 400;
      throw err;
    }
    await ensureDirReadableWritable(mountPathStr);

    const normalizedConfig = config && typeof config === 'object' ? deepEncryptSensitive(config) : null;
    const configText = normalizedConfig ? JSON.stringify(normalizedConfig) : null;

    if (hasId) {
      const existing = await this.knexMain(this.tableName).where({ id: idNum, uid: uidStr }).first();
      if (!existing) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
      if (String(existing.status || '').trim() === 'running') {
        const err = new Error('common.INVALID_PARAMS');
        err.statusCode = 400;
        throw err;
      }

      let mergedConfig = null;
      if (normalizedConfig && typeof normalizedConfig === 'object') {
        const prev = safeJsonParse(existing.config);
        mergedConfig = prev && typeof prev === 'object' ? { ...prev, ...normalizedConfig } : normalizedConfig;
        if (prev && typeof prev === 'object' && prev.addition && normalizedConfig.addition) {
          mergedConfig.addition = { ...prev.addition, ...normalizedConfig.addition };
        }
      }

      const olPath =
        ensureString(openlistMountPath).trim() ||
        existing.openlist_mount_path ||
        normalizeOpenlistMountPath(nameStr, idNum);
      const remoteStr = `openlist:${olPath}`;

      await this.knexMain(this.tableName).where({ id: idNum }).update({
        name: nameStr,
        mount_path: mountPathStr,
        driver: driverStr,
        openlist_mount_path: olPath,
        remote: remoteStr,
        config: mergedConfig ? JSON.stringify(mergedConfig) : existing.config,
        local_mount_dir:
          String(existing.mount_path || '').trim() !== mountPathStr ? null : existing.local_mount_dir,
        update_time: new Date(),
      });
      return { id: idNum, openlist_mount_path: olPath };
    }

    const [newId] = await this.knexMain(this.tableName).insert({
      uid: uidStr,
      name: nameStr,
      mount_path: mountPathStr,
      driver: driverStr,
      openlist_mount_path: '',
      openlist_storage_id: null,
      remote: '',
      status: 'stopped',
      auto_running: 0,
      config: configText,
      last_error: null,
      create_time: new Date(),
      update_time: new Date(),
    });

    const olPath = normalizeOpenlistMountPath(nameStr, newId);
    const remoteStr = `openlist:${olPath}`;
    await this.knexMain(this.tableName).where({ id: newId }).update({
      openlist_mount_path: olPath,
      remote: remoteStr,
      update_time: new Date(),
    });

    return { id: newId, openlist_mount_path: olPath };
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
    return { ok: true, openlist_storage_id: existed.openlist_storage_id };
  }
}

module.exports = { OpenlistMountService };
