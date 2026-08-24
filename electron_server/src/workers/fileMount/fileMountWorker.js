const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const Logger = require('../../utils/logger');
const jwtUtil = require('../../utils/jwtUtil');
const rclonePath = require('../../libsPath/rclonePath');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const {
  classifyRcloneStderr,
  classifyForRemoteProbe,
  packLastError,
  parentCheckToCode,
  autoMountSkipCode,
} = require('../../utils/fileMountErrorCodes');

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

function decryptIfEncrypted(value) {
  const text = ensureString(value);
  if (!text) return '';
  if (!jwtUtil.isEncryptedPassword(text)) return text;
  return jwtUtil.decryptPassword(text) || '';
}

function decryptObjectValues(obj) {
  if (!obj || typeof obj !== 'object') return null;
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (typeof v === 'string') out[k] = decryptIfEncrypted(v);
    else out[k] = v;
  }
  return out;
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

/**
 * 供 :ftp: / :sftp: 连接串末尾路径段使用。
 * 空或仅为 / 时必须为 '/'，不能留空：否则会变成 :sftp: 无路径，rclone 列目录异常（用户用 // 才正常即因此）。
 * 绝对路径 /home/a 写成连接串里常见为去掉首字符的 home/a。
 */
function normalizeRemotePathSegment(value) {
  const t = ensureString(value).trim();
  if (!t || t === '/' || /^\/+$/.test(t)) return '/';
  return t.startsWith('/') ? t.slice(1) : t;
}

function normalizeUrlPath(value) {
  const t = ensureString(value).trim();
  if (!t) return '/';
  return t.startsWith('/') ? t : `/${t}`;
}

/** 合并连续斜杠，避免 https://host//dav 导致 RFC WebDAV 根路径解析异常、列目录为空 */
function normalizeWebdavUrlPath(value) {
  let t = ensureString(value).trim();
  if (!t) t = '/';
  if (!t.startsWith('/')) t = `/${t}`;
  t = t.replace(/\/{2,}/g, '/');
  return t;
}

/** 标准 WebDAV（RFC 4918）多数实现不强制集合路径带尾部 /；需要时可 config.webdav_trailing_slash=true */
function webdavUrlPathForMount(cfg) {
  let p = normalizeWebdavUrlPath(cfg && cfg.remote_path);
  if (cfg && cfg.webdav_trailing_slash === true && p.length > 1 && !p.endsWith('/')) {
    p = `${p}/`;
  }
  return p;
}

const WEBDAV_VENDORS = new Set([
  'fastmail',
  'nextcloud',
  'owncloud',
  'infinitescale',
  'sharepoint',
  'sharepoint-ntlm',
  'rclone',
  'other',
]);

function normalizeWebdavVendor(value) {
  const v = ensureString(value).trim().toLowerCase();
  if (WEBDAV_VENDORS.has(v)) return v;
  return 'other';
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

async function checkDirReadableWritable(dirPath) {
  const p = ensureString(dirPath).trim();
  if (!p) return 'mount_parent_not_found';
  let stat;
  try {
    stat = await fs.promises.stat(p);
  } catch (_) {
    return 'mount_parent_not_found';
  }
  if (!stat.isDirectory()) return 'mount_parent_not_dir';
  const mode = fs.constants.R_OK | fs.constants.W_OK | (fs.constants.X_OK || 0);
  try {
    await fs.promises.access(p, mode);
  } catch (_) {
    return 'mount_parent_no_access';
  }
  return '';
}

async function statNoThrow(p) {
  try {
    return await fs.promises.stat(p);
  } catch (_) {
    return null;
  }
}

async function removeDirNoThrow(dirPath) {
  try {
    await fs.promises.rmdir(dirPath);
    return true;
  } catch (_) {
    return false;
  }
}

/** rclone mount 要求挂载点为空（除非 --allow-non-empty）；含 .DS_Store 等隐藏文件也算非空 */
async function isDirEmptyNoThrow(dirPath) {
  try {
    const entries = await fs.promises.readdir(dirPath);
    if (!Array.isArray(entries)) return true;
    return entries.length === 0;
  } catch (_) {
    return true;
  }
}

function argvHasAllowNonEmpty(argv) {
  if (!Array.isArray(argv)) return false;
  return argv.some(a => {
    const s = ensureString(a).trim();
    return s === '--allow-non-empty' || s.startsWith('--allow-non-empty=');
  });
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

async function resolveUniqueMountDir({ parentPath, mountName, startIndex = 0 }) {
  const p = ensureString(parentPath).trim();
  const n = ensureString(mountName).trim();
  if (!p || !n) return null;
  const mustNotExist = process.platform === 'win32';

  for (let i = Number(startIndex) || 0; i < 1000; i++) {
    const suffix = i === 0 ? '' : `(${i})`;
    const candidate = path.join(p, `${n}${suffix}`);
    const st = await statNoThrow(candidate);
    if (!st) {
      // WinFsp 挂目录时要求挂载点路径不存在，由 rclone/WinFsp 自行创建占用。
      if (mustNotExist) {
        return candidate;
      }
      try {
        await fs.promises.mkdir(candidate, { recursive: true });
        return candidate;
      } catch (_) {
        continue;
      }
    }
    if (!st.isDirectory()) continue;
    const empty = await isDirEmptyNoThrow(candidate);
    if (!empty) continue;
    if (mustNotExist) {
      const removed = await removeDirNoThrow(candidate);
      if (removed || !(await statNoThrow(candidate))) {
        return candidate;
      }
      continue;
    }
    return candidate;
  }
  return null;
}

function sanitizeVolname(value) {
  const t = ensureString(value).trim();
  if (!t) return '';
  return t.replace(/[\/\\:]/g, '_').slice(0, 60);
}

function deriveVolname({ name, remote, cfg }) {
  const nameStr = ensureString(name).trim();
  if (nameStr) return nameStr;

  const rp = cfg && typeof cfg === 'object' ? ensureString(cfg.remote_path).trim() : '';
  if (rp) {
    const seg = rp.split('/').filter(Boolean).pop();
    if (seg) return seg;
  }

  const host = cfg && typeof cfg === 'object' ? ensureString(cfg.host).trim() : '';
  if (host) return host;

  const r = ensureString(remote).trim();
  if (!r) return '';
  const idx = r.lastIndexOf('/');
  if (idx >= 0 && idx < r.length - 1) return r.slice(idx + 1);
  return r;
}

function isFatalStartStderr(text) {
  const t = ensureString(text).toLowerCase();
  if (!t) return false;
  if (t.includes('critical:')) return true;
  if (t.includes('fatal error')) return true;
  if (t.includes('failed to create file system')) return true;
  if (t.includes('unsupported protocol scheme')) return true;
  return false;
}

function cleanStderrForError(text) {
  const raw = ensureString(text).trim();
  if (!raw) return '';
  const lines = raw
    .split('\n')
    .map(l => l.trimEnd())
    .filter(Boolean);
  return lines.slice(-15).join('\n');
}

/**
 * mount 前对远端做一次 lsd，强制完成连接与鉴权。
 * 仅靠 rclone mount 时 FUSE 可先就绪，错密码/错端口/错地址常表现为挂上了但目录为空且无 stderr。
 */
function probeRcloneRemoteList({ resolvedRemote, protocolArgs, extraArgs, spawnEnv }) {
  const remote = ensureString(resolvedRemote).trim();
  if (!remote) return { ok: false, output: '' };
  const proto = Array.isArray(protocolArgs) ? protocolArgs.map(a => ensureString(a)).filter(Boolean) : [];
  const extra = Array.isArray(extraArgs) ? extraArgs.map(a => ensureString(a)).filter(Boolean) : [];
  try {
    const res = spawnSync(
      rclonePath.path,
      ['lsd', remote, ...proto, ...extra, '--contimeout=8s', '--timeout=8s', '--retries=1', '--low-level-retries=1', '-vv'],
      {
        windowsHide: true,
        encoding: 'utf8',
        env: spawnEnv || process.env,
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: 10000,
      },
    );
    if (res && res.error && res.error.code === 'ETIMEDOUT') {
      return { ok: false, output: 'probe_timeout' };
    }
    const status = res && res.status;
    const out = `${ensureString(res && res.stderr)}\n${ensureString(res && res.stdout)}`;
    if (status === 0) {
      return { ok: true, output: '' };
    }
    return { ok: false, output: cleanStderrForError(out) };
  } catch (e) {
    return { ok: false, output: e && e.message ? String(e.message) : String(e) };
  }
}

async function ensureMainDbReady() {
  const dbPath = dbUtil.DB_PATHS.MAIN_DB;
  if (!knexUtil.hasConnection(dbPath)) {
    await knexUtil.init(dbPath);
  }
}

/** 调试日志：不含密码；与主进程 [fileMount bridge] / [fileMount API IPC] 对照 requestId */
function fmWorkerLog(event, meta = {}) {
  try {
    Logger.info(`[fileMountWorker] ${event}`, {
      workerPid: process.pid,
      platform: process.platform,
      ...meta,
    });
  } catch (_) {}
}

/** 仅用于日志的 rclone 参数脱敏 */
function redactRcloneArgvForLog(argv) {
  if (!Array.isArray(argv)) return [];
  return argv.map(a => {
    const s = ensureString(a);
    if (/^--(webdav|ftp|sftp)-pass=/i.test(s)) return s.replace(/=(.*)$/, '=(redacted)');
    return s;
  });
}

function stderrTailForLog(text, maxLen = 480) {
  const t = ensureString(text).trim();
  if (!t) return '';
  if (t.length <= maxLen) return t;
  return `…${t.slice(-maxLen)}`;
}

/** fork 后主进程会立刻 send；若在 await DB 后才 process.on('message')，Windows 上易丢消息导致 15s 超时 */
let _fileMountWorkerSingleton = null;
const _fileMountPendingMessages = [];

class FileMountWorker {
  constructor() {
    _fileMountWorkerSingleton = this;
    this._isReady = false;
    this.processes = new Map();
    this.lastStderr = new Map();
    this.pendingStartCount = 0;
    this.preserveRunningOnExitIds = new Set();
    this.knex = null;
    this._idleExitScheduled = false;
    this._shuttingDown = false;
    this._installLifecycleHandlers();
    fmWorkerLog('worker_boot');
    this._init().catch(err => {
      try {
        Logger.error('❌ fileMountWorker _init failed', err);
      } catch (_) {}
      try {
        process.exit(1);
      } catch (_) {}
    });
  }

  async _init() {
    const t0 = Date.now();
    await ensureMainDbReady();
    const dbMs = Date.now() - t0;
    this.knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    this._isReady = true;
    const backlog = _fileMountPendingMessages.splice(0);
    fmWorkerLog('init_ready', { dbInitMs: dbMs, ipcBacklogCount: backlog.length });
    for (const m of backlog) {
      this._dispatchMessage(m);
    }
  }

  _dispatchMessage(message) {
    if (!message || !message.type) return;
    fmWorkerLog('ipc_dispatch', {
      type: message.type,
      requestId: message?.data?.requestId,
      mountId: message?.data?.id,
    });
    if (message.type === 'start') {
      const requestId = message?.data?.requestId;
      const id = message?.data?.id;
      this.startById({ requestId, id }).catch(err => {
        this._reply('fileMountStartResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
      });
    } else if (message.type === 'stop') {
      const requestId = message?.data?.requestId;
      const id = message?.data?.id;
      this.stopById({ requestId, id }).catch(err => {
        this._reply('fileMountStopResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
      });
    } else if (message.type === 'reload') {
      const requestId = message?.data?.requestId;
      this.reloadRunning({ requestId }).catch(err => {
        this._reply('fileMountReloadResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
      });
    }
  }

  _installLifecycleHandlers() {
    const graceful = signal => {
      try {
        Logger.info(`📡 fileMountWorker received ${signal}, exiting`);
      } catch (_) {}
      this._shuttingDown = true;
      this.stopAll({ preserveRunning: false }).finally(() => process.exit(0));
    };
    process.on('SIGTERM', () => graceful('SIGTERM'));
    process.on('SIGINT', () => graceful('SIGINT'));
    process.on('uncaughtException', err => {
      Logger.error('❌ fileMountWorker uncaughtException', err);
      graceful('uncaughtException');
    });
    process.on('unhandledRejection', reason => {
      Logger.error('❌ fileMountWorker unhandledRejection', reason);
      graceful('unhandledRejection');
    });
  }

  _reply(type, data) {
    if (!process.send) {
      fmWorkerLog('reply_skipped_no_channel', { type, requestId: data && data.requestId });
      return;
    }
    try {
      if (type === 'fileMountStartResponse') {
        fmWorkerLog('reply_to_parent', {
          type,
          requestId: data && data.requestId,
          ok: !!(data && data.ok),
          err: data && data.error,
          running: data && data.running,
          rclonePid: data && data.pid,
        });
      } else if (type === 'fileMountReloadResponse' || type === 'fileMountStopResponse') {
        fmWorkerLog('reply_to_parent', { type, requestId: data && data.requestId, ok: !!(data && data.ok) });
      }
      const payload = { type, data };
      const sent = process.send(payload, sendErr => {
        if (sendErr) {
          fmWorkerLog('reply_send_callback_err', { type, err: sendErr && sendErr.message ? String(sendErr.message) : String(sendErr) });
        }
      });
      if (sent === false) {
        fmWorkerLog('reply_send_returned_false', { type, requestId: data && data.requestId });
      }
    } catch (e) {
      fmWorkerLog('reply_send_failed', { type, err: e && e.message ? String(e.message) : String(e) });
    }
  }

  /** 无任何 rclone 子进程时退出 worker；主进程下次挂载会再 fork */
  _maybeExitIfIdle() {
    if (this._shuttingDown) return;
    if (this.processes.size > 0) return;
    if (this.pendingStartCount > 0) return;
    if (this._idleExitScheduled) return;
    this._idleExitScheduled = true;
    /** Windows：立刻 process.exit 会导致 fork IPC 上一条 reply 未送达，express 侧仍等满 15s 超时 */
    const exitDelayMs = process.platform === 'win32' ? 200 : 0;
    setImmediate(() => {
      const doExit = () => {
        try {
          Logger.info('📡 fileMountWorker idle (no active mounts), exiting');
        } catch (_) {}
        process.exit(0);
      };
      if (exitDelayMs > 0) {
        setTimeout(doExit, exitDelayMs);
      } else {
        doExit();
      }
    });
  }

  async _updateRow(idNum, patch) {
    if (!this.knex) return;
    await this.knex('file_mount')
      .where({ id: idNum })
      .update({
        ...patch,
        update_time: new Date(),
      })
      .catch(() => null);
  }

  async _getRow(idNum) {
    if (!this.knex) return null;
    return await this.knex('file_mount')
      .where({ id: idNum })
      .first()
      .catch(() => null);
  }

  async _hasRunningSameTarget({ idNum, parentPath, mountName }) {
    if (!this.knex) return false;
    const mp = ensureString(parentPath).trim();
    const mn = ensureString(mountName).trim();
    if (!mp || !mn) return false;
    const row = await this.knex('file_mount')
      .select('id')
      .where({ status: 'running', mount_path: mp, name: mn })
      .whereNot({ id: Number(idNum) })
      .first()
      .catch(() => null);
    return !!row;
  }

  _collectStderr(idNum, chunk) {
    const prev = this.lastStderr.get(idNum) || '';
    const next = (prev + ensureString(chunk)).slice(-8000);
    this.lastStderr.set(idNum, next);
  }

  _collectStdout(idNum, chunk) {
    const prev = this.lastStderr.get(idNum) || '';
    const next = (prev + ensureString(chunk)).slice(-8000);
    this.lastStderr.set(idNum, next);
  }

  async _waitForStableStart({ idNum, child, timeoutMs }) {
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
            cleanStderrForError(this.lastStderr.get(idNum)) ||
            `exit:${code ?? ''}:${signal ?? ''}`,
        });
      };
      const timer = setTimeout(() => {
        if (done) return;
        done = true;
        child.removeListener('exit', onExit);
        const stderr = cleanStderrForError(this.lastStderr.get(idNum));
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

  _probeRemoteError({ resolvedRemote, protocolArgs, extraArgs, spawnEnv }) {
    const r = probeRcloneRemoteList({ resolvedRemote, protocolArgs, extraArgs, spawnEnv });
    if (r.ok) return '';
    return ensureString(r.output).trim();
  }

  async startById({ requestId, id, auto = false }) {
    this.pendingStartCount += 1;
    try {
    await rclonePath.ensureReady();
    const idNum = Number(id);
    fmWorkerLog('startById_begin', { requestId, idNum, auto });
    if (!Number.isFinite(idNum) || idNum <= 0) {
      this._reply('fileMountStartResponse', { requestId, ok: false, error: 'common.INVALID_PARAMS' });
      return;
    }

    if (this.processes.has(idNum)) {
      await this._updateRow(idNum, { status: 'running', last_error: null });
      this._reply('fileMountStartResponse', { requestId, ok: true, running: true, id: idNum, pid: this.processes.get(idNum).pid });
      return;
    }

    const row = await this._getRow(idNum);
    if (!row) {
      this._reply('fileMountStartResponse', { requestId, ok: false, error: 'common.NOT_FOUND' });
      return;
    }

    const parentPath = ensureString(row.mount_path).trim();
    const remote = ensureString(row.remote).trim();
    const name = ensureString(row.name).trim();
    if (!parentPath) {
      await this._updateRow(idNum, { status: 'error', last_error: 'common.INVALID_PARAMS' });
      this._reply('fileMountStartResponse', { requestId, ok: false, error: 'common.INVALID_PARAMS' });
      return;
    }
    if (!isValidMountFolderName(name)) {
      await this._updateRow(idNum, { status: 'error', last_error: 'fileMount.INVALID_MOUNT_NAME' });
      this._reply('fileMountStartResponse', { requestId, ok: false, error: 'fileMount.INVALID_MOUNT_NAME' });
      return;
    }

    const parentErr = await checkDirReadableWritable(parentPath);
    if (parentErr) {
      const parentCode = parentCheckToCode(parentErr);
      if (auto) {
        const skipCode = autoMountSkipCode(parentErr);
        await this._updateRow(idNum, { status: 'stopped', last_error: skipCode });
        this._reply('fileMountStartResponse', { requestId, ok: false, error: skipCode });
        return;
      }
      await this._updateRow(idNum, { status: 'error', last_error: parentCode });
      this._reply('fileMountStartResponse', { requestId, ok: false, error: parentCode });
      return;
    }

    const conflictRunning = await this._hasRunningSameTarget({ idNum, parentPath, mountName: name });
    const actualMountPath = await resolveUniqueMountDir({ parentPath, mountName: name, startIndex: conflictRunning ? 1 : 0 });
    if (!actualMountPath) {
      await this._updateRow(idNum, { status: 'error', last_error: 'fileMount.MOUNT_PARENT_NO_ACCESS' });
      this._reply('fileMountStartResponse', { requestId, ok: false, error: 'fileMount.MOUNT_PARENT_NO_ACCESS' });
      return;
    }

    const cfg = safeJsonParse(row.config) || {};
    fmWorkerLog('startById_row', {
      requestId,
      idNum,
      protocol: ensureString(cfg.protocol).trim().toLowerCase() || '(rclone_remote)',
      mountParentLen: parentPath.length,
      nameLen: name.length,
      remoteLen: remote.length,
    });
    const extraArgs = Array.isArray(cfg.args) ? cfg.args.map(a => ensureString(a)).filter(Boolean) : [];
    const envExtra = decryptObjectValues(cfg.env) || null;
    const spawnEnv = envExtra ? { ...process.env, ...envExtra } : process.env;

    const protocol = ensureString(cfg.protocol).trim().toLowerCase();
    const isQuick = protocol === 'webdav' || protocol === 'ftp' || protocol === 'sftp';

    let resolvedRemote = remote;
    let protocolArgs = [];
    if (isQuick) {
      const host = ensureString(cfg.host).trim();
      const username = ensureString(cfg.username).trim();
      const passwordPlain = decryptIfEncrypted(cfg.password);
      const portRaw = Number(cfg.port);
      let port = Number.isFinite(portRaw) && portRaw > 0 ? portRaw : null;

      if (!host || !username) {
        await this._updateRow(idNum, { status: 'error', last_error: 'common.INVALID_PARAMS' });
        this._reply('fileMountStartResponse', { requestId, ok: false, error: 'common.INVALID_PARAMS' });
        return;
      }

      const obscured = passwordPlain ? obscurePassword(passwordPlain) : '';
      if (passwordPlain && !obscured) {
        await this._updateRow(idNum, { status: 'error', last_error: 'fileMount.OBSCURE_FAILED' });
        this._reply('fileMountStartResponse', { requestId, ok: false, error: 'fileMount.OBSCURE_FAILED' });
        return;
      }

      if (protocol === 'webdav') {
        const scheme = ensureString(cfg.scheme).trim().toLowerCase() === 'https' ? 'https' : 'http';
        if (!port) port = scheme === 'https' ? 443 : 80;
        const url = `${scheme}://${host}:${port}${webdavUrlPathForMount(cfg)}`;
        const vendor = normalizeWebdavVendor(cfg.vendor);
        resolvedRemote = ':webdav:';
        protocolArgs = [`--webdav-url=${url}`, `--webdav-vendor=${vendor}`, `--webdav-user=${username}`];
        // 默认跳过 TLS 校验（内网/自签名常见）；仅当 webdav_skip_verify === false 时校验证书
        if (scheme === 'https' && cfg.webdav_skip_verify !== false) {
          protocolArgs.push('--no-check-certificate');
        }
        if (obscured) protocolArgs.push(`--webdav-pass=${obscured}`);
      } else if (protocol === 'ftp') {
        if (!port) port = 21;
        const remotePathSeg = normalizeRemotePathSegment(cfg.remote_path);
        resolvedRemote = `:ftp:${remotePathSeg}`;
        protocolArgs = [`--ftp-host=${host}`, `--ftp-port=${port}`, `--ftp-user=${username}`];
        if (obscured) protocolArgs.push(`--ftp-pass=${obscured}`);
      } else if (protocol === 'sftp') {
        if (!port) port = 22;
        const remotePathSeg = normalizeRemotePathSegment(cfg.remote_path);
        resolvedRemote = `:sftp:${remotePathSeg}`;
        protocolArgs = [`--sftp-host=${host}`, `--sftp-port=${port}`, `--sftp-user=${username}`];
        if (obscured) protocolArgs.push(`--sftp-pass=${obscured}`);
      }
    }

    if (!resolvedRemote) {
      await this._updateRow(idNum, { status: 'error', last_error: 'common.INVALID_PARAMS' });
      this._reply('fileMountStartResponse', { requestId, ok: false, error: 'common.INVALID_PARAMS' });
      return;
    }

    const preflight = probeRcloneRemoteList({ resolvedRemote, protocolArgs, extraArgs, spawnEnv });
    if (!preflight.ok) {
      const merged = ensureString(preflight.output).trim();
      fmWorkerLog('preflight_fail', {
        requestId,
        idNum,
        resolvedRemote,
        stderrTail: stderrTailForLog(merged),
      });
      const cls = classifyForRemoteProbe(merged);
      const stored = packLastError(cls);
      await this._updateRow(idNum, { status: 'error', last_error: stored });
      this._reply('fileMountStartResponse', {
        requestId,
        ok: false,
        error: cls.code,
        detail: cls.detail || undefined,
      });
      return;
    }

    fmWorkerLog('preflight_ok', { requestId, idNum, resolvedRemote });

    const tailArgs = [...protocolArgs, ...extraArgs];
    const args = ['mount', resolvedRemote, actualMountPath];
    if (!argvHasAllowNonEmpty(tailArgs)) {
      args.push('--allow-non-empty');
    }
    args.push(...tailArgs);
    if (process.platform === 'darwin') {
      const vol = sanitizeVolname(deriveVolname({ name, remote, cfg }));
      if (vol) args.push(`--volname=${vol}`);
    }
    const child = spawn(rclonePath.path, args, {
      env: spawnEnv,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    fmWorkerLog('rclone_spawned', {
      requestId,
      idNum,
      rclonePath: rclonePath.path,
      childPid: child.pid,
      argvRedacted: redactRcloneArgvForLog(args),
      mountPoint: actualMountPath,
    });
    this.processes.set(idNum, child);
    this.lastStderr.set(idNum, '');

    child.stdout.on('data', data => {
      this._collectStdout(idNum, data);
    });

    child.stderr.on('data', data => {
      this._collectStderr(idNum, data);
    });

    child.on('exit', async (code, signal) => {
      fmWorkerLog('rclone_exit', {
        requestId,
        idNum,
        code,
        signal,
        stderrTail: stderrTailForLog(this.lastStderr.get(idNum)),
      });
      this.processes.delete(idNum);
      const last = this.lastStderr.get(idNum) || '';
      this.lastStderr.delete(idNum);
      if (this.preserveRunningOnExitIds.has(idNum)) {
        this.preserveRunningOnExitIds.delete(idNum);
        await this._updateRow(idNum, { status: 'running', last_error: null });
        this._maybeExitIfIdle();
        return;
      }
      const statusText = Number(code || 0) === 0 ? 'stopped' : 'error';
      let errText = null;
      if (statusText === 'error') {
        const raw = last || `exit:${code ?? ''}:${signal ?? ''}`;
        errText = packLastError(classifyRcloneStderr(raw));
      }
      await this._updateRow(idNum, { status: statusText, last_error: errText });
      this._maybeExitIfIdle();
    });

    const stableMs =
      process.platform === 'win32' ? 4500 : 1200;
    const started = await this._waitForStableStart({ idNum, child, timeoutMs: stableMs });
    fmWorkerLog('stable_start_result', {
      requestId,
      idNum,
      stableMs,
      ok: started.ok,
      errPreview: started.ok ? undefined : stderrTailForLog(ensureString(started.error)),
    });
    if (!started.ok) {
      try {
        child.kill('SIGTERM');
      } catch (_) {}
      await awaitChildExit(child);
      let detail = ensureString(started.error).trim();
      const collected = cleanStderrForError(this.lastStderr.get(idNum));
      if ((!detail || detail.startsWith('exit:')) && !collected) {
        const probed = this._probeRemoteError({ resolvedRemote, protocolArgs, extraArgs, spawnEnv });
        if (probed) detail = probed;
      } else if ((!detail || detail.startsWith('exit:')) && collected) {
        detail = collected;
      }
      const merged =
        collected && detail && collected !== detail
          ? `${detail}\n${collected}`
          : detail || collected || '';
      const cls = classifyForRemoteProbe(merged);
      const stored = packLastError(cls);
      await this._updateRow(idNum, { status: 'error', last_error: stored });
      this._reply('fileMountStartResponse', {
        requestId,
        ok: false,
        error: cls.code,
        detail: cls.detail || undefined,
      });
      return;
    }

    await this._updateRow(idNum, { status: 'running', last_error: null });
    this._reply('fileMountStartResponse', { requestId, ok: true, running: false, id: idNum, pid: child.pid, mountPath: actualMountPath, parentPath });
    } finally {
      this.pendingStartCount = Math.max(0, Number(this.pendingStartCount || 0) - 1);
      this._maybeExitIfIdle();
    }
  }

  async stopById({ requestId, id, preserveRunning = false }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) {
      this._reply('fileMountStopResponse', { requestId, ok: false, error: 'common.INVALID_PARAMS' });
      this._maybeExitIfIdle();
      return;
    }

    const child = this.processes.get(idNum);
    if (!child) {
      if (!preserveRunning) {
        await this._updateRow(idNum, { status: 'stopped', last_error: null });
      }
      this._reply('fileMountStopResponse', { requestId, ok: true, id: idNum, stopped: true, preserved: !!preserveRunning });
      this._maybeExitIfIdle();
      return;
    }

    if (preserveRunning) {
      this.preserveRunningOnExitIds.add(idNum);
    }
    try {
      child.kill('SIGTERM');
    } catch (_) {}
    const timer = setTimeout(() => {
      try {
        child.kill('SIGKILL');
      } catch (_) {}
    }, 5000);

    await new Promise(resolve => {
      child.once('exit', () => resolve());
    }).catch(() => null);
    clearTimeout(timer);

    this.processes.delete(idNum);
    this.lastStderr.delete(idNum);
    if (!preserveRunning) {
      await this._updateRow(idNum, { status: 'stopped', last_error: null });
    } else {
      await this._updateRow(idNum, { status: 'running', last_error: null });
    }
    this._reply('fileMountStopResponse', { requestId, ok: true, id: idNum, stopped: true, preserved: !!preserveRunning });
    this._maybeExitIfIdle();
  }

  async stopAll({ preserveRunning = false } = {}) {
    const ids = Array.from(this.processes.keys());
    for (const idNum of ids) {
      await this.stopById({ requestId: null, id: idNum, preserveRunning });
    }
  }

  async reloadRunning({ requestId }) {
    if (!this.knex) {
      this._reply('fileMountReloadResponse', { requestId, ok: false, error: 'fileMount.DB_NOT_READY' });
      this._maybeExitIfIdle();
      return;
    }
    const rows = await this.knex('file_mount')
      .where({ auto_running: 1 })
      .select('id')
      .catch(() => []);
    fmWorkerLog('reloadRunning', { requestId, autoRunningCount: rows.length });
    for (const r of rows) {
      const idNum = Number(r && r.id);
      if (!Number.isFinite(idNum) || idNum <= 0) continue;
      if (this.processes.has(idNum)) continue;
      await this.startById({ requestId: null, id: idNum, auto: true });
    }
    this._reply('fileMountReloadResponse', { requestId, ok: true });
    this._maybeExitIfIdle();
  }
}

module.exports = FileMountWorker;

if (require.main === module) {
  process.on('message', message => {
    const w = _fileMountWorkerSingleton;
    const ready = !!(w && w._isReady);
    const t = message && message.type;
    try {
      Logger.info('[fileMountWorker] ipc_raw', {
        workerPid: process.pid,
        platform: process.platform,
        type: t,
        ready,
        pendingBefore: _fileMountPendingMessages.length,
      });
    } catch (_) {}
    if (w && w._isReady) {
      w._dispatchMessage(message);
    } else {
      _fileMountPendingMessages.push(message);
      try {
        Logger.info('[fileMountWorker] ipc_queued_until_db_ready', {
          type: t,
          queueLen: _fileMountPendingMessages.length,
        });
      } catch (_) {}
    }
  });
  new FileMountWorker();
}
