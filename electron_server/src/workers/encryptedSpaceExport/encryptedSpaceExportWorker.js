const fs = require('fs');
const path = require('path');
const Logger = require('../../utils/logger');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const jwtUtil = require('../../utils/jwtUtil');
const { getIndexDb, ensureIndexDbSchema, decryptFileToStream, configFolderName } = require('../../api/modules/encryptedSpace/encryptedSpaceFileUtil');

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function toInt(v, fallback = 0) {
  const n = Number.parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) ? n : fallback;
}

async function ensureMainDbReady() {
  const dbPath = dbUtil.DB_PATHS.MAIN_DB;
  if (!knexUtil.hasConnection(dbPath)) {
    await knexUtil.init(dbPath);
  }
  return knexUtil.getInstance(dbPath);
}

function safeDecodeBase64Name(text) {
  const raw = ensureString(text).trim();
  if (!raw) return '';
  try {
    const buf = Buffer.from(raw, 'base64');
    const s = buf.toString('utf8');
    if (s && s.length > 0) return s;
  } catch (_) {}
  return raw;
}

function sanitizeRelativePath(rel) {
  const raw = ensureString(rel).trim();
  if (!raw) return '';
  const replaced = raw.replace(/\\/g, '/');
  const parts = replaced.split('/').filter(p => p && p !== '.' && p !== '..');
  return parts.join(path.sep);
}

async function resolveUniqueFilePath(fullPath) {
  const baseDir = path.dirname(fullPath);
  const ext = path.extname(fullPath);
  const name = path.basename(fullPath, ext);

  for (let i = 0; i < 2000; i++) {
    const candidate = i === 0 ? fullPath : path.join(baseDir, `${name} (${i})${ext}`);
    const exists = await fs.promises
      .access(candidate, fs.constants.F_OK)
      .then(() => true)
      .catch(() => false);
    if (!exists) return candidate;
  }

  const stamp = Date.now();
  return path.join(baseDir, `${name} (${stamp})${ext}`);
}

class EncryptedSpaceExportWorker {
  constructor() {
    this.taskId = null;
    this.knex = null;
    this.stopRequested = false;
    this.runningPromise = null;
    this._onStarted = null;
    this._startedNotified = false;
    this._lastProgressTs = 0;
    this._init();
  }

  async _init() {
    this.knex = await ensureMainDbReady();
    this._bindProcessEvents();
  }

  _reply(type, data) {
    if (!process.send) return;
    try {
      process.send({ type, data });
    } catch (_) {}
  }

  _notifyStarted(payload) {
    if (this._startedNotified) return;
    this._startedNotified = true;
    if (typeof this._onStarted === 'function') {
      try {
        this._onStarted(payload || { ok: true });
      } catch (_) {}
    }
  }

  _scheduleExit(code) {
    setTimeout(() => {
      try {
        process.exit(Number.isFinite(Number(code)) ? Number(code) : 0);
      } catch (_) {
        process.exit(0);
      }
    }, 200);
  }

  async _getTaskRow() {
    const idNum = Number(this.taskId);
    if (!Number.isFinite(idNum) || idNum <= 0) return null;
    return await this.knex('encrypted_space_export')
      .where({ id: idNum })
      .first()
      .catch(() => null);
  }

  async _updateTask(fields) {
    const idNum = Number(this.taskId);
    if (!Number.isFinite(idNum) || idNum <= 0) return;
    const now = new Date();
    const payload = { ...fields, update_time: now };
    await this.knex('encrypted_space_export').where({ id: idNum }).update(payload);
  }

  async _resolveSpacePwd({ spaceId }) {
    const row = await this.knex('encrypted_space')
      .where({ id: Number(spaceId) })
      .first()
      .catch(() => null);
    if (!row) return null;
    const enc = row.space_pwd ? String(row.space_pwd) : '';
    const pwd = jwtUtil.decryptPassword(enc);
    return pwd || null;
  }

  async bind({ requestId, taskId }) {
    const idNum = Number(taskId);
    if (!Number.isFinite(idNum) || idNum <= 0) {
      this._reply('encryptedSpaceExportBindResponse', { requestId, ok: false, error: 'invalid_params' });
      return;
    }
    this.taskId = idNum;
    this._reply('encryptedSpaceExportBindResponse', { requestId, ok: true, taskId: idNum });
  }

  async start({ requestId }) {
    if (this.runningPromise) {
      this._reply('encryptedSpaceExportStartResponse', { requestId, ok: true, already_running: true });
      return;
    }

    this._startedNotified = false;
    let done = false;
    const startedRes = await new Promise(resolve => {
      const timer = setTimeout(() => {
        if (done) return;
        done = true;
        resolve({ ok: true });
      }, 3000);

      this._onStarted = payload => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(payload || { ok: true });
      };

      this.runningPromise = this.run({ requestId })
        .catch(async err => {
          const errorText = err && err.message ? String(err.message) : String(err);
          this._notifyStarted({ ok: false, error: errorText });
          await this._updateTask({
            status: 'error',
            last_error: errorText || 'failed',
            progress: '',
            last_end_time: new Date(),
          }).catch(() => null);
          this._reply('encryptedSpaceExportRunResponse', { requestId, ok: false, error: errorText || 'failed' });
          this._scheduleExit(0);
        })
        .finally(() => {
          this.runningPromise = null;
          this._onStarted = null;
          this._startedNotified = false;
        });
    });

    this._reply('encryptedSpaceExportStartResponse', { requestId, ...(startedRes || { ok: true }) });
  }

  async run({ requestId }) {
    const row = await this._getTaskRow();
    if (!row) {
      this._reply('encryptedSpaceExportRunResponse', { requestId, ok: false, error: 'not_found' });
      this._notifyStarted({ ok: false, error: 'not_found' });
      this._scheduleExit(0);
      return;
    }

    const spaceId = Number(row.space_id);
    const spacePath = ensureString(row.space_path).trim();
    const targetPath = ensureString(row.target_path).trim();

    if (!Number.isFinite(spaceId) || spaceId <= 0 || !spacePath || !targetPath) {
      await this._updateTask({ status: 'error', last_error: 'invalid_config', progress: '', last_end_time: new Date() }).catch(() => null);
      this._reply('encryptedSpaceExportRunResponse', { requestId, ok: false, error: 'invalid_config' });
      this._notifyStarted({ ok: false, error: 'invalid_config' });
      this._scheduleExit(0);
      return;
    }

    const resolvedSpacePath = path.resolve(spacePath);
    const resolvedTargetPath = path.resolve(targetPath);
    if (resolvedTargetPath.startsWith(resolvedSpacePath.endsWith(path.sep) ? resolvedSpacePath : resolvedSpacePath + path.sep)) {
      await this._updateTask({ status: 'error', last_error: 'invalid_target', progress: '', last_end_time: new Date() }).catch(() => null);
      this._reply('encryptedSpaceExportRunResponse', { requestId, ok: false, error: 'invalid_target' });
      this._notifyStarted({ ok: false, error: 'invalid_target' });
      this._scheduleExit(0);
      return;
    }

    const pwd = await this._resolveSpacePwd({ spaceId });
    if (!pwd) {
      await this._updateTask({ status: 'error', last_error: 'missing_password', progress: '', last_end_time: new Date() }).catch(() => null);
      this._reply('encryptedSpaceExportRunResponse', { requestId, ok: false, error: 'missing_password' });
      this._notifyStarted({ ok: false, error: 'missing_password' });
      this._scheduleExit(0);
      return;
    }

    this.stopRequested = false;
    this._lastProgressTs = 0;
    await fs.promises.mkdir(resolvedTargetPath, { recursive: true });
    await this._updateTask({
      status: 'running',
      last_error: null,
      progress: 'starting',
      last_start_time: new Date(),
      last_end_time: null,
    }).catch(() => null);

    this._notifyStarted({ ok: true, pid: process.pid });

    const privateIndexDb = getIndexDb(resolvedSpacePath);
    ensureIndexDbSchema(privateIndexDb);
    const rows = privateIndexDb.prepare('SELECT * FROM private_space_index ORDER BY id ASC').all();

    const totalFiles = Array.isArray(rows) ? rows.length : 0;
    let doneFiles = 0;
    let processedCount = 0;
    let skippedCount = 0;
    let handledInputBytes = BigInt(0);
    let handledOutputBytes = BigInt(0);

    await this._updateTask({ total_files: totalFiles, done_files: 0, processed_count: 0, skipped_count: 0 }).catch(() => null);

    for (const r of rows || []) {
      if (this.stopRequested) break;

      const filenameEnc = ensureString(r && r.filename_enc).trim();
      const filenameBase64 = ensureString(r && r.filename).trim();
      if (!filenameEnc) {
        skippedCount += 1;
        doneFiles += 1;
        continue;
      }

      const relEnc = filenameEnc.replace(/\\/g, '/');
      if (relEnc === configFolderName || relEnc.startsWith(`${configFolderName}/`)) {
        skippedCount += 1;
        doneFiles += 1;
        continue;
      }

      const inFullPath = path.resolve(resolvedSpacePath, relEnc);
      if (!inFullPath.startsWith(resolvedSpacePath.endsWith(path.sep) ? resolvedSpacePath : resolvedSpacePath + path.sep)) {
        skippedCount += 1;
        doneFiles += 1;
        continue;
      }

      const inStat = await fs.promises.stat(inFullPath).catch(() => null);
      if (!inStat || !inStat.isFile()) {
        skippedCount += 1;
        doneFiles += 1;
        continue;
      }

      let decodedName = safeDecodeBase64Name(filenameBase64);
      decodedName = decodedName ? decodedName : `file_${String(r && r.id ? r.id : doneFiles + 1)}`;
      const safeRel = sanitizeRelativePath(decodedName) || path.basename(decodedName);
      const outCandidate = path.resolve(resolvedTargetPath, safeRel);
      const outFullPath = outCandidate.startsWith(resolvedTargetPath.endsWith(path.sep) ? resolvedTargetPath : resolvedTargetPath + path.sep)
        ? outCandidate
        : path.resolve(resolvedTargetPath, path.basename(safeRel));

      await fs.promises.mkdir(path.dirname(outFullPath), { recursive: true });
      const outUnique = await resolveUniqueFilePath(outFullPath);

      try {
        await decryptFileToStream(pwd, inFullPath, fs.createWriteStream(outUnique));
        const outStat = await fs.promises.stat(outUnique).catch(() => null);
        handledInputBytes += BigInt(inStat.size || 0);
        handledOutputBytes += BigInt(outStat && outStat.isFile() ? outStat.size || 0 : 0);
        processedCount += 1;
      } catch (e) {
        try {
          await fs.promises.unlink(outUnique);
        } catch (_) {}
        skippedCount += 1;
      }

      doneFiles += 1;

      const now = Date.now();
      if (now - this._lastProgressTs >= 600 || doneFiles === totalFiles) {
        this._lastProgressTs = now;
        const percent = totalFiles > 0 ? Math.round((doneFiles / totalFiles) * 100) : 0;
        await this._updateTask({
          done_files: doneFiles,
          processed_count: processedCount,
          skipped_count: skippedCount,
          handled_input_bytes: handledInputBytes.toString(),
          handled_output_bytes: handledOutputBytes.toString(),
          progress: `${percent}%`,
        }).catch(() => null);
      }
    }

    if (this.stopRequested) {
      await this._updateTask({
        status: 'error',
        last_error: 'stopped',
        progress: '',
        done_files: doneFiles,
        processed_count: processedCount,
        skipped_count: skippedCount,
        handled_input_bytes: handledInputBytes.toString(),
        handled_output_bytes: handledOutputBytes.toString(),
        last_end_time: new Date(),
      }).catch(() => null);
      this._reply('encryptedSpaceExportRunResponse', { requestId, ok: false, stopped: true });
      this._scheduleExit(0);
      return;
    }

    await this._updateTask({
      status: 'success',
      last_error: null,
      progress: '',
      done_files: doneFiles,
      processed_count: processedCount,
      skipped_count: skippedCount,
      handled_input_bytes: handledInputBytes.toString(),
      handled_output_bytes: handledOutputBytes.toString(),
      last_end_time: new Date(),
    }).catch(() => null);
    this._reply('encryptedSpaceExportRunResponse', { requestId, ok: true });
    this._scheduleExit(0);
  }

  async stop({ requestId }) {
    this.stopRequested = true;
    await this._updateTask({ status: 'error', last_error: 'stopped', progress: '', last_end_time: new Date() }).catch(() => null);
    this._reply('encryptedSpaceExportStopResponse', { requestId, ok: true, stopped: true });
    this._scheduleExit(0);
  }

  _bindProcessEvents() {
    process.on('message', message => {
      if (!message || !message.type) return;
      if (message.type === 'bind') {
        const requestId = message?.data?.requestId;
        const taskId = message?.data?.taskId;
        this.bind({ requestId, taskId }).catch(err => {
          this._reply('encryptedSpaceExportBindResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
        });
      } else if (message.type === 'start') {
        const requestId = message?.data?.requestId;
        this.start({ requestId }).catch(err => {
          this._reply('encryptedSpaceExportStartResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
        });
      } else if (message.type === 'stop') {
        const requestId = message?.data?.requestId;
        this.stop({ requestId }).catch(err => {
          this._reply('encryptedSpaceExportStopResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
        });
      }
    });

    const graceful = signal => {
      try {
        Logger.info(`📡 encryptedSpaceExportWorker received ${signal}, exiting`);
      } catch (_) {}
      this.stop({ requestId: null }).catch(() => null);
    };

    process.on('SIGTERM', () => graceful('SIGTERM'));
    process.on('SIGINT', () => graceful('SIGINT'));
    process.on('uncaughtException', err => {
      Logger.error('❌ encryptedSpaceExportWorker uncaughtException', err);
      graceful('uncaughtException');
    });
    process.on('unhandledRejection', reason => {
      Logger.error('❌ encryptedSpaceExportWorker unhandledRejection', reason);
      graceful('unhandledRejection');
    });
  }
}

if (require.main === module) {
  new EncryptedSpaceExportWorker();
}

module.exports = EncryptedSpaceExportWorker;
