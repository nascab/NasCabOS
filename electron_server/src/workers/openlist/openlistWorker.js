const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const Logger = require('../../utils/logger');
const jwtUtil = require('../../utils/jwtUtil');
const rclonePath = require('../../libsPath/rclonePath');
const openlistPath = require('../../libsPath/openlistPath');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const tableUser = require('../../db/table/tableUser');
const {
  ensureString,
  isValidMountFolderName,
  checkDirReadableWritable,
  resolveUniqueMountDir,
  resolveMountDir,
} = require('../../utils/mountPathUtil');
const {
  getDataPath,
  writeConfigIfNeeded,
  buildWebdavUrl,
  getBaseUrlForDataPath,
  readHttpPortFromConfig,
} = require('./openlistConfig');
const { OpenlistApiClient } = require('./openlistApiClient');
const { mergeAdditionDefaults } = require('./openlistDriverUi');
const { getStaticDriverList } = require('./openlistDriverCatalog');
const { ensureVfsCacheDir, buildDefaultMountPerfArgs } = require('../../utils/rcloneMountPerf');

function safeJsonParse(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

function decryptIfEncrypted(value) {
  const text = ensureString(value);
  if (!text) return '';
  if (!jwtUtil.isEncryptedPassword(text)) return text;
  return jwtUtil.decryptPassword(text) || '';
}

function obscurePassword(plainText) {
  const raw = ensureString(plainText);
  if (!raw) return '';
  try {
    const res = spawnSync(rclonePath.path, ['obscure', raw], {
      windowsHide: true,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return ensureString(res && res.stdout).trim();
  } catch (_) {
    return '';
  }
}

function decryptObjectValues(obj) {
  if (!obj || typeof obj !== 'object') return null;
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (typeof v === 'string') out[k] = decryptIfEncrypted(v);
    else if (v && typeof v === 'object' && !Array.isArray(v)) out[k] = decryptObjectValues(v);
    else out[k] = v;
  }
  return out;
}

function buildAdditionString(config, driver) {
  const cfg = config && typeof config === 'object' ? config : {};
  const addition = cfg.addition && typeof cfg.addition === 'object' ? cfg.addition : cfg;
  const plain = decryptObjectValues(addition) || {};
  const merged = mergeAdditionDefaults(ensureString(driver), plain);
  return JSON.stringify(merged);
}

function isFatalStartStderr(text) {
  const t = ensureString(text).toLowerCase();
  if (!t) return false;
  if (t.includes('critical:')) return true;
  if (t.includes('fatal error')) return true;
  if (t.includes('failed to create file system')) return true;
  return false;
}

function cleanStderrForError(text) {
  const raw = ensureString(text).trim();
  if (!raw) return '';
  return raw
    .split('\n')
    .map(l => l.trimEnd())
    .filter(Boolean)
    .slice(-15)
    .join('\n');
}

function awaitChildExit(child, timeoutMs = 8000) {
  return new Promise(resolve => {
    if (!child) return resolve();
    const ms = Number(timeoutMs) || 8000;
    const t = setTimeout(resolve, ms);
    child.once('exit', () => {
      clearTimeout(t);
      resolve();
    });
  });
}

let _workerSingleton = null;
const _pendingMessages = [];

class OpenlistWorker {
  constructor() {
    _workerSingleton = this;
    this.knex = null;
    this._isReady = false;
    this.openlistChild = null;
    this.openlistStarting = null;
    this.rcloneProcesses = new Map();
    this.rcloneStarting = new Map(); // id -> Promise, prevent duplicate start
    this.rcloneLastStderr = new Map();
    this.api = new OpenlistApiClient();
    this.nascabAdminUsername = '';
    this.adminPassword = '';
    this._initDb();
  }

  async _sleep(ms) {
    await new Promise(r => setTimeout(r, Number(ms || 0) || 0));
  }

  async _ensureMainDbReady() {
    const mainDbPath = dbUtil.DB_PATHS.MAIN_DB;
    if (!knexUtil.hasConnection(mainDbPath)) {
      await knexUtil.init(mainDbPath);
    }
    return mainDbPath;
  }

  async _initDb() {
    try {
      const mainDbPath = await this._ensureMainDbReady();
      this.knex = knexUtil.getInstance(mainDbPath);
    } catch (e) {
      Logger.error('[openlistWorker] db init failed', e);
    }
    await this._loadAdminCredentials();
    this._isReady = true;
    const queued = _pendingMessages.splice(0);
    for (const msg of queued) {
      this._dispatchMessage(msg);
    }
  }

  async _loadAdminCredentials() {
    if (!this.knex) {
      Logger.warn('[openlistWorker] loadAdminCredentials skipped: main db not ready');
      return;
    }
    try {
      const row = await this.knex('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();
      if (!row) {
        Logger.warn('[openlistWorker] no super_admin user in main db', {
          mainDbPath: dbUtil.DB_PATHS.MAIN_DB,
        });
        return;
      }
      this.nascabAdminUsername = ensureString(row.username).trim();
      const password = jwtUtil.isEncryptedPassword(row.password)
        ? jwtUtil.decryptPassword(row.password)
        : jwtUtil.decodeClientPassword(row.password);
      if (!password) {
        Logger.warn('[openlistWorker] super_admin password empty after decrypt', {
          username: this.nascabAdminUsername,
          serverIdPresent: !!process.env.SERVER_ID,
          encrypted: jwtUtil.isEncryptedPassword(row.password),
        });
        return;
      }
      this.adminPassword = password;
      // OpenList 管理账号固定为 admin；密码与 Nascab super_admin 同步
      this.api.setCredentials({ username: 'admin', password });
      this._logCredentialsDebug('loadAdminCredentials');
    } catch (e) {
      Logger.error('[openlistWorker] load admin credentials failed', e);
    }
  }

  _refreshApiBaseUrl(dataPath) {
    const baseUrl = getBaseUrlForDataPath(dataPath);
    this.api.setBaseUrl(baseUrl);
    return baseUrl;
  }

  _logCredentialsDebug(stage) {
    try {
      const dataPath = getDataPath();
      Logger.info('[openlistWorker] credentials_debug', {
        stage: ensureString(stage),
        dataPath,
        httpPort: readHttpPortFromConfig(dataPath),
        baseUrl: this.api.baseUrl,
        nascabSuperAdminUsername: this.nascabAdminUsername || null,
        openlistLoginUsername: 'admin',
        passwordLength: this.adminPassword ? this.adminPassword.length : 0,
        mainDbPath: dbUtil.DB_PATHS.MAIN_DB,
        hasApiToken: !!this.api.token,
        apiTokenPrefix: this.api.token ? this.api.token.slice(0, 24) : null,
        serverIdPresent: !!process.env.SERVER_ID,
        pathDatabase: process.env.PATH_DATABASE || null,
      });
    } catch (_) {}
  }

  _fetchAdminTokenCli(dataPath) {
    const attempts = [
      ['--data', dataPath, 'admin', 'token'],
      ['admin', 'token', '--data', dataPath],
    ];
    let lastErr = '';
    for (const argv of attempts) {
      const res = spawnSync(openlistPath.path, argv, {
        cwd: dataPath,
        encoding: 'utf8',
        timeout: 25000,
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      const code = Number(res && res.status);
      const stderr = ensureString(res && res.stderr).trim();
      const stdout = ensureString(res && res.stdout).trim();
      const combined = `${stdout}\n${stderr}`.trim();
      try {
        Logger.info('[openlistWorker] admin_token_attempt', {
          argv,
          exitCode: code,
          stdoutTail: stdout ? stdout.slice(-500) : '',
          stderrTail: stderr ? stderr.slice(-500) : '',
        });
      } catch (_) {}
      if (code !== 0) {
        lastErr = stderr || stdout || `exit:${code}`;
        continue;
      }
      const match = combined.match(/Admin token:\s*(\S+)/i);
      if (match && match[1]) return match[1].trim();
      const line = combined
        .split('\n')
        .map(s => s.trim())
        .find(s => s.startsWith('openlist-'));
      if (line) return line;
      lastErr = combined || 'openlistMount.ADMIN_TOKEN_PARSE_FAILED';
    }
    throw new Error(lastErr || 'openlistMount.ADMIN_TOKEN_FAILED');
  }

  async _applyOpenlistAuthWhileStopped(dataPath) {
    if (this.openlistChild && !this.openlistChild.killed) {
      await this._stopOpenlistChild(this.openlistChild, 8000);
      await this._sleep(500);
    }
    if (!this.adminPassword) {
      throw new Error('openlistMount.ADMIN_PASSWORD_MISSING');
    }
    await this._syncAdminPassword();
    const token = this._fetchAdminTokenCli(dataPath);
    this.api.setToken(token);
    this._logCredentialsDebug('afterAdminToken');
    return token;
  }

  _spawnOpenlistServer(dataPath) {
    const child = spawn(openlistPath.path, ['server', '--data', dataPath], {
      cwd: dataPath,
      env: { ...process.env, UMASK: '022' },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    this.openlistChild = child;
    child.on('exit', () => {
      if (this.openlistChild === child) this.openlistChild = null;
    });
    child.stderr.on('data', buf => {
      const t = ensureString(buf).trim();
      if (t) Logger.debug('[openlistWorker] openlist_stderr', t.slice(-800));
    });
    child.stdout.on('data', buf => {
      const t = ensureString(buf).trim();
      if (t) Logger.debug('[openlistWorker] openlist_stdout', t.slice(-800));
    });
    return child;
  }

  async _refreshApiAuthIfNeeded(dataPath) {
    this._refreshApiBaseUrl(dataPath);
    if (this.openlistChild && !this.openlistChild.killed && this.api.token) {
      try {
        const ok = await this._waitForPing(3000);
        if (ok && (await this.api.ping())) {
          return;
        }
      } catch (e) {
        Logger.warn('[openlistWorker] cached token invalid, refreshing', e && e.message);
        this.api.setToken('');
      }
    }
    if (this.openlistChild && !this.openlistChild.killed) {
      await this._stopOpenlistChild(this.openlistChild, 8000);
      await this._sleep(500);
    }
    await this._applyOpenlistAuthWhileStopped(dataPath);
    this._spawnOpenlistServer(dataPath);
    const ok = await this._waitForPing(45000);
    if (!ok) throw new Error('openlistMount.SERVICE_START_TIMEOUT');
    if (!(await this.api.ping())) {
      throw new Error('openlistMount.SERVICE_START_TIMEOUT');
    }
  }

  _dataDbExists(dataPath) {
    try {
      return fs.existsSync(path.join(dataPath, 'data.db'));
    } catch (_) {
      return false;
    }
  }

  async _stopOpenlistChild(child, timeoutMs = 8000) {
    const c = child || this.openlistChild;
    if (!c) return;
    try {
      c.kill('SIGTERM');
    } catch (_) {}
    const done = await Promise.race([
      new Promise(resolve => {
        try {
          c.once('exit', () => resolve(true));
        } catch (_) {
          resolve(true);
        }
      }),
      this._sleep(timeoutMs).then(() => false),
    ]);
    if (!done) {
      try {
        c.kill('SIGKILL');
      } catch (_) {}
      await Promise.race([this._sleep(800), this._sleep(0)]).catch(() => null);
    }
    if (this.openlistChild === c) this.openlistChild = null;
  }

  _reply(type, data) {
    if (!process.send) return;
    try {
      process.send({ type, data });
    } catch (_) {}
  }

  _dispatchMessage(message) {
    const type = message && message.type;
    const data = (message && message.data) || {};
    if (type === 'ensureOpenList') {
      this.ensureOpenListRunning({ requestId: data.requestId }).catch(err => {
        this._reply('openlistEnsureResponse', { requestId: data.requestId, ok: false, error: err && err.message });
      });
      return;
    }
    if (type === 'getDrivers') {
      this.getDrivers({ requestId: data.requestId }).catch(err => {
        this._reply('openlistGetDriversResponse', { requestId: data.requestId, ok: false, error: err && err.message });
      });
      return;
    }
    if (type === 'syncStorage') {
      this.syncStorageById({ requestId: data.requestId, id: data.id }).catch(err => {
        this._reply('openlistSyncStorageResponse', { requestId: data.requestId, ok: false, error: err && err.message });
      });
      return;
    }
    if (type === 'deleteStorage') {
      this.deleteStorageById({ requestId: data.requestId, id: data.id }).catch(err => {
        this._reply('openlistDeleteStorageResponse', { requestId: data.requestId, ok: false, error: err && err.message });
      });
      return;
    }
    if (type === 'start') {
      this.startById({ requestId: data.requestId, id: data.id, auto: !!data.auto }).catch(err => {
        this._reply('openlistMountStartResponse', { requestId: data.requestId, ok: false, error: err && err.message });
      });
      return;
    }
    if (type === 'stop') {
      this.stopById({ requestId: data.requestId, id: data.id }).catch(err => {
        this._reply('openlistMountStopResponse', { requestId: data.requestId, ok: false, error: err && err.message });
      });
      return;
    }
    if (type === 'reload') {
      this.reloadRunning({ requestId: data.requestId }).catch(err => {
        this._reply('openlistMountReloadResponse', { requestId: data.requestId, ok: false, error: err && err.message });
      });
    }
  }

  async _syncAdminPassword() {
    if (!this.adminPassword) return;
    const dataPath = getDataPath();
    try {
      // OpenList CLI uses global --data flag. Some versions are picky about flag position.
      const attempts = [
        ['--data', dataPath, 'admin', 'set', this.adminPassword],
        ['admin', 'set', this.adminPassword, '--data', dataPath],
      ];
      let lastErr = '';
      for (const argv of attempts) {
        const res = spawnSync(openlistPath.path, argv, {
          cwd: dataPath,
          encoding: 'utf8',
          timeout: 25000,
          windowsHide: true,
          stdio: ['ignore', 'pipe', 'pipe'],
        });
        const code = Number(res && res.status);
        const stderr = ensureString(res && res.stderr).trim();
        const stdout = ensureString(res && res.stdout).trim();
        try {
          Logger.info('[openlistWorker] admin_set_attempt', {
            argv,
            exitCode: code,
            stderrTail: stderr ? stderr.slice(-500) : '',
            stdoutTail: stdout ? stdout.slice(-500) : '',
          });
        } catch (_) {}
        if (code === 0) {
          this.api.setCredentials({ username: 'admin', password: this.adminPassword });
          return;
        }
        lastErr = stderr || stdout || `exit:${code}`;
      }
      throw new Error(lastErr || 'openlistMount.ADMIN_SET_FAILED');
    } catch (e) {
      Logger.warn('[openlistWorker] admin set failed', e && e.message);
      throw e;
    }
  }

  async _waitForPing(maxMs = 30000) {
    const start = Date.now();
    while (Date.now() - start < maxMs) {
      try {
        if (await this.api.ping()) return true;
      } catch (_) {}
      await new Promise(r => setTimeout(r, 400));
    }
    return false;
  }

  async ensureOpenListRunning({ requestId } = {}) {
    await this._loadAdminCredentials();
    const dataPath = getDataPath();
    writeConfigIfNeeded(dataPath);
    this._refreshApiBaseUrl(dataPath);
    this._logCredentialsDebug('ensureOpenList_start');

    if (this.openlistStarting) {
      await this.openlistStarting;
      this._reply('openlistEnsureResponse', { requestId, ok: true, running: true });
      return;
    }

    this.openlistStarting = (async () => {
      await openlistPath.ensureReady();
      await rclonePath.ensureReady();
      if (!fs.existsSync(openlistPath.path)) {
        throw new Error('openlistMount.BINARY_NOT_FOUND');
      }

      if (this.openlistChild && !this.openlistChild.killed) {
        const ok = await this._waitForPing(5000);
        if (ok && this.api.token) {
          try {
            if (await this.api.ping()) {
              return;
            }
          } catch (e) {
            Logger.warn('[openlistWorker] running instance auth failed, restarting openlist', e && e.message);
            this.api.setToken('');
            await this._stopOpenlistChild(this.openlistChild, 8000);
            await this._sleep(500);
          }
        } else {
          await this._stopOpenlistChild(this.openlistChild, 8000);
          await this._sleep(500);
        }
      }

      const hasDbBefore = this._dataDbExists(dataPath);
      if (!hasDbBefore) {
        const first = this._spawnOpenlistServer(dataPath);
        const ok = await this._waitForPing(45000);
        if (!ok) throw new Error('openlistMount.SERVICE_START_TIMEOUT');
        await this._stopOpenlistChild(first, 8000);
        if (!this._dataDbExists(dataPath)) {
          throw new Error('openlistMount.DB_INIT_FAILED');
        }
      }

      await this._refreshApiAuthIfNeeded(dataPath);
    })();

    try {
      await this.openlistStarting;
      this._reply('openlistEnsureResponse', { requestId, ok: true, running: true });
    } catch (e) {
      this._reply('openlistEnsureResponse', { requestId, ok: false, error: e && e.message });
      throw e;
    } finally {
      this.openlistStarting = null;
    }
  }

  async getDrivers({ requestId }) {
    const drivers = getStaticDriverList();
    this._reply('openlistGetDriversResponse', { requestId, ok: true, drivers });
  }

  async _getRow(idNum) {
    if (!this.knex) return null;
    return this.knex('openlist_mount').where({ id: idNum }).first();
  }

  async _updateRow(idNum, patch) {
    if (!this.knex) return;
    await this.knex('openlist_mount')
      .where({ id: idNum })
      .update({ ...patch, update_time: new Date() });
  }

  _collectRcloneStderr(idNum, chunk) {
    const prev = this.rcloneLastStderr.get(idNum) || '';
    const next = (prev + ensureString(chunk)).slice(-8000);
    this.rcloneLastStderr.set(idNum, next);
  }

  async _waitForStableRcloneStart({ idNum, child, timeoutMs }) {
    const ms = Number(timeoutMs || 2000) || 2000;
    return await new Promise(resolve => {
      let done = false;
      const onExit = (code, signal) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve({
          ok: false,
          error:
            cleanStderrForError(this.rcloneLastStderr.get(idNum)) ||
            `exit:${code ?? ''}:${signal ?? ''}`,
        });
      };
      const timer = setTimeout(() => {
        if (done) return;
        done = true;
        child.removeListener('exit', onExit);
        const stderr = cleanStderrForError(this.rcloneLastStderr.get(idNum));
        if (isFatalStartStderr(stderr)) {
          resolve({ ok: false, error: stderr || 'fatal' });
          return;
        }
        resolve({ ok: true });
      }, ms);

      if (typeof child.prependOnceListener === 'function') {
        child.prependOnceListener('exit', onExit);
      } else {
        child.once('exit', onExit);
      }
    });
  }

  _storagePayloadFromRow(row) {
    const cfg = safeJsonParse(row.config) || {};
    return {
      mount_path: row.openlist_mount_path,
      order: 0,
      driver: row.driver,
      addition: buildAdditionString(cfg, row.driver),
      remark: row.name || '',
      disabled: false,
      cache_expiration: 60,
      webdav_policy: 'native_proxy',
      disable_index: false,
      enable_sign: false,
    };
  }

  async syncStorageById({ requestId, id }) {
    const idNum = Number(id);
    const row = await this._getRow(idNum);
    if (!row) {
      this._reply('openlistSyncStorageResponse', { requestId, ok: false, error: 'common.NOT_FOUND' });
      return;
    }
    await this.ensureOpenListRunning({ requestId: null });
    const storageId = await this._upsertOpenlistStorage(row);
    await this._updateRow(idNum, { openlist_storage_id: storageId });
    this._reply('openlistSyncStorageResponse', { requestId, ok: true, storageId });
  }

  async _assertStorageHealthy(mountPath, storageId) {
    const list = await this.api.listStorages();
    const storage = list.find(
      s =>
        (Number.isFinite(Number(storageId)) && Number(s.id) === Number(storageId)) ||
        s.mount_path === mountPath
    );
    if (!storage) {
      throw new Error('openlistMount.STORAGE_NOT_FOUND');
    }
    const status = String(storage.status || '').trim();
    if (status && status !== 'work') {
      throw new Error(`openlistMount.STORAGE_INIT_FAILED:${status}`);
    }
    return storage;
  }

  async _upsertOpenlistStorage(row) {
    const payload = this._storagePayloadFromRow(row);
    const existingId = Number(row.openlist_storage_id);
    if (Number.isFinite(existingId) && existingId > 0) {
      await this.api.updateStorage({ id: existingId, ...payload });
      await this._assertStorageHealthy(row.openlist_mount_path, existingId);
      return existingId;
    }
    const created = await this.api.createStorage(payload);
    const id = created && (created.id ?? created);
    if (Number.isFinite(Number(id)) && Number(id) > 0) {
      await this._assertStorageHealthy(row.openlist_mount_path, Number(id));
      return Number(id);
    }
    const list = await this.api.listStorages();
    const found = list.find(s => s.mount_path === row.openlist_mount_path);
    if (found) {
      await this._assertStorageHealthy(row.openlist_mount_path, found.id);
      return Number(found.id);
    }
    return null;
  }

  async deleteStorageById({ requestId, id }) {
    const idNum = Number(id);
    const row = await this._getRow(idNum);
    if (!row) {
      this._reply('openlistDeleteStorageResponse', { requestId, ok: false, error: 'common.NOT_FOUND' });
      return;
    }
    const storageId = Number(row.openlist_storage_id);
    if (Number.isFinite(storageId) && storageId > 0) {
      try {
        await this.ensureOpenListRunning({ requestId: null });
        await this.api.deleteStorage(storageId);
      } catch (e) {
        Logger.warn('[openlistWorker] delete storage', e && e.message);
      }
    }
    this._reply('openlistDeleteStorageResponse', { requestId, ok: true });
  }

  async startById({ requestId, id, auto = false }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) {
      this._reply('openlistMountStartResponse', { requestId, ok: false, error: 'common.INVALID_PARAMS' });
      return;
    }

    if (this.rcloneProcesses.has(idNum)) {
      await this._updateRow(idNum, { status: 'running', last_error: null });
      this._reply('openlistMountStartResponse', {
        requestId,
        ok: true,
        id: idNum,
        pid: this.rcloneProcesses.get(idNum).pid,
      });
      return;
    }

    // Prevent re-entrant rclone start for the same mount id.
    // If another start is in-flight, wait for it and return final state.
    if (this.rcloneStarting.has(idNum)) {
      try {
        await this.rcloneStarting.get(idNum);
      } catch (_) {}
      if (this.rcloneProcesses.has(idNum)) {
        await this._updateRow(idNum, { status: 'running', last_error: null });
        this._reply('openlistMountStartResponse', {
          requestId,
          ok: true,
          id: idNum,
          pid: this.rcloneProcesses.get(idNum).pid,
        });
        return;
      }
      const row = await this._getRow(idNum);
      const err = (row && row.last_error) || 'openlistMount.RCLONE_START_FAILED';
      await this._updateRow(idNum, { status: auto ? 'stopped' : 'error', last_error: err });
      this._reply('openlistMountStartResponse', { requestId, ok: false, error: err });
      return;
    }

    const startPromise = (async () => {
    const row = await this._getRow(idNum);
    if (!row) {
      this._reply('openlistMountStartResponse', { requestId, ok: false, error: 'common.NOT_FOUND' });
      return;
    }

    const parentPath = ensureString(row.mount_path).trim();
    const name = ensureString(row.name).trim();
    if (!parentPath || !isValidMountFolderName(name)) {
      await this._updateRow(idNum, { status: 'error', last_error: 'openlistMount.INVALID_MOUNT_NAME' });
      this._reply('openlistMountStartResponse', { requestId, ok: false, error: 'openlistMount.INVALID_MOUNT_NAME' });
      return;
    }

    const parentErr = await checkDirReadableWritable(parentPath);
    if (parentErr) {
      const code = `openlistMount.${parentErr.toUpperCase()}`;
      await this._updateRow(idNum, { status: auto ? 'stopped' : 'error', last_error: code });
      this._reply('openlistMountStartResponse', { requestId, ok: false, error: code });
      return;
    }

    await this.ensureOpenListRunning({ requestId: null });
    try {
      const storageId = await this._upsertOpenlistStorage(row);
      if (storageId) await this._updateRow(idNum, { openlist_storage_id: storageId });
    } catch (e) {
      const errMsg = e && e.message ? String(e.message) : 'openlistMount.STORAGE_SYNC_FAILED';
      await this._updateRow(idNum, { status: 'error', last_error: errMsg });
      this._reply('openlistMountStartResponse', { requestId, ok: false, error: errMsg });
      return;
    }

    const actualMountPath = await resolveMountDir({
      parentPath,
      mountName: name,
      preferredPath: row.local_mount_dir,
      startIndex: 0,
    });
    if (!actualMountPath) {
      await this._updateRow(idNum, { status: 'error', last_error: 'openlistMount.MOUNT_PARENT_NO_ACCESS' });
      this._reply('openlistMountStartResponse', { requestId, ok: false, error: 'openlistMount.MOUNT_PARENT_NO_ACCESS' });
      return;
    }

    const webdavUrl = buildWebdavUrl(row.openlist_mount_path, this.api.baseUrl);
    const obscured = obscurePassword(this.adminPassword);
    if (!obscured) {
      await this._updateRow(idNum, { status: 'error', last_error: 'openlistMount.OBSCURE_FAILED' });
      this._reply('openlistMountStartResponse', { requestId, ok: false, error: 'openlistMount.OBSCURE_FAILED' });
      return;
    }

    const protocolArgs = [
      `--webdav-url=${webdavUrl}`,
      '--webdav-vendor=other',
      '--webdav-user=admin',
      `--webdav-pass=${obscured}`,
      '--no-check-certificate',
    ];
    const perfArgs = buildDefaultMountPerfArgs({
      vfsCacheDir: ensureVfsCacheDir(idNum),
    });
    const args = ['mount', ':webdav:', actualMountPath, '--allow-non-empty', ...perfArgs, ...protocolArgs];

    const child = spawn(rclonePath.path, args, {
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    this.rcloneProcesses.set(idNum, child);
    this.rcloneLastStderr.set(idNum, '');

    child.stderr.on('data', buf => {
      this._collectRcloneStderr(idNum, buf);
    });
    child.on('exit', async (code, signal) => {
      this.rcloneProcesses.delete(idNum);
      this.rcloneLastStderr.delete(idNum);
      const statusText = Number(code || 0) === 0 ? 'stopped' : 'error';
      const errText = statusText === 'error' ? `exit:${code ?? ''}:${signal ?? ''}` : null;
      await this._updateRow(idNum, { status: statusText, last_error: errText });
    });

    const stableMs = process.platform === 'win32' ? 4500 : 1200;
    const started = await this._waitForStableRcloneStart({ idNum, child, timeoutMs: stableMs });
    if (!started.ok) {
      try {
        child.kill('SIGTERM');
      } catch (_) {}
      await awaitChildExit(child);
      this.rcloneProcesses.delete(idNum);
      const detail = cleanStderrForError(this.rcloneLastStderr.get(idNum)) || ensureString(started.error).trim();
      this.rcloneLastStderr.delete(idNum);
      const errMsg = detail || 'openlistMount.RCLONE_START_FAILED';
      await this._updateRow(idNum, { status: auto ? 'stopped' : 'error', last_error: errMsg });
      this._reply('openlistMountStartResponse', {
        requestId,
        ok: false,
        error: 'openlistMount.RCLONE_START_FAILED',
        detail: detail || undefined,
      });
      return;
    }

    await this._updateRow(idNum, {
      status: 'running',
      last_error: null,
      local_mount_dir: actualMountPath,
    });
    this._reply('openlistMountStartResponse', {
      requestId,
      ok: true,
      id: idNum,
      pid: child.pid,
      mountPath: actualMountPath,
    });
    })();

    this.rcloneStarting.set(idNum, startPromise);
    try {
      await startPromise;
    } finally {
      if (this.rcloneStarting.get(idNum) === startPromise) {
        this.rcloneStarting.delete(idNum);
      }
    }
  }

  async stopById({ requestId, id }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) {
      this._reply('openlistMountStopResponse', { requestId, ok: false, error: 'common.INVALID_PARAMS' });
      return;
    }

    const child = this.rcloneProcesses.get(idNum);
    if (child) {
      try {
        child.kill('SIGTERM');
      } catch (_) {}
      await new Promise(resolve => {
        child.once('exit', () => resolve());
        setTimeout(() => {
          try {
            child.kill('SIGKILL');
          } catch (_) {}
          resolve();
        }, 5000);
      });
      this.rcloneProcesses.delete(idNum);
    }

    await this._updateRow(idNum, { status: 'stopped', last_error: null });
    this._reply('openlistMountStopResponse', { requestId, ok: true, id: idNum });
  }

  async reloadRunning({ requestId }) {
    if (!this.knex) {
      this._reply('openlistMountReloadResponse', { requestId, ok: false, error: 'openlistMount.DB_NOT_READY' });
      return;
    }
    const rows = await this.knex('openlist_mount').where({ auto_running: 1 }).select('id');
    for (const r of rows) {
      const idNum = Number(r && r.id);
      if (!Number.isFinite(idNum) || idNum <= 0) continue;
      if (this.rcloneProcesses.has(idNum)) continue;
      await this.startById({ requestId: null, id: idNum, auto: true });
    }
    this._reply('openlistMountReloadResponse', { requestId, ok: true });
  }
}

module.exports = OpenlistWorker;

if (require.main === module) {
  process.on('message', message => {
    const w = _workerSingleton;
    if (w && w._isReady) {
      w._dispatchMessage(message);
    } else {
      _pendingMessages.push(message);
    }
  });
  new OpenlistWorker();
}
