const fs = require('fs');
const path = require('path');
const Logger = require('../../utils/logger');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const tableFileBackup = require('../../db/table/tableFileBackup');
const tableFileBackupRecord = require('../../db/table/tableFileBackupRecord');
const { NodeFileBackupEngine, summarizeProgress } = require('./nodeFileBackupEngine');

const MAX_ERROR_FILES_TOTAL = 100;

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

function ensureStringArray(v) {
  if (!Array.isArray(v)) return [];
  return v.map(x => ensureString(x).trim()).filter(Boolean);
}

async function ensureMainDbReady() {
  await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
  const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
  await knex.raw('SELECT 1');
  return knex;
}

async function checkDirReadable(dirPath) {
  const p = ensureString(dirPath).trim();
  if (!p) return 'source_not_found';
  let stat;
  try {
    stat = await fs.promises.stat(p);
  } catch (_) {
    return 'source_not_found';
  }
  if (!stat.isDirectory()) return 'source_not_dir';
  const mode = fs.constants.R_OK | (fs.constants.X_OK || 0);
  try {
    await fs.promises.access(p, mode);
  } catch (_) {
    return 'source_no_access';
  }
  return '';
}

async function checkDirReadableWritable(dirPath) {
  const p = ensureString(dirPath).trim();
  if (!p) return 'target_not_found';
  let stat;
  try {
    stat = await fs.promises.stat(p);
  } catch (_) {
    return 'target_not_found';
  }
  if (!stat.isDirectory()) return 'target_not_dir';
  const mode = fs.constants.R_OK | fs.constants.W_OK | (fs.constants.X_OK || 0);
  try {
    await fs.promises.access(p, mode);
  } catch (_) {
    return 'target_no_access';
  }
  return '';
}

function normalizeRootName(p) {
  const raw = ensureString(p).trim();
  if (!raw) return '';
  const trimmed = raw.replace(/[\/\\]+$/, '');
  if (!trimmed) {
    if (raw.startsWith('/') || raw.startsWith('\\')) return 'root';
    return 'root';
  }
  const base = path.basename(trimmed);
  if (base) return base;
  const m = trimmed.match(/^([a-zA-Z]):$/);
  if (m) return m[1];
  return 'root';
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, Math.max(0, Number(ms) || 0)));
}

async function withTimeout(promise, timeoutMs, label = 'async_operation') {
  const ms = Math.max(0, Number(timeoutMs) || 0);
  if (!ms) {
    return {
      timedOut: false,
      completed: true,
      value: await promise,
    };
  }

  let settled = false;
  let timeoutId = null;
  const observedPromise = Promise.resolve(promise)
    .then(value => {
      settled = true;
      if (timeoutId) clearTimeout(timeoutId);
      return {
        timedOut: false,
        completed: true,
        value,
      };
    })
    .catch(error => {
      settled = true;
      if (timeoutId) clearTimeout(timeoutId);
      throw error;
    });

  const timeoutPromise = new Promise(resolve => {
    timeoutId = setTimeout(() => {
      if (settled) return;
      resolve({
        timedOut: true,
        completed: false,
        value: null,
      });
    }, ms);
  });

  const result = await Promise.race([observedPromise, timeoutPromise]);
  if (result && result.timedOut) {
    Logger.warn(`[fileBackupTaskWorker] ${label} timed out after ${ms}ms; operation will continue in background`);
    observedPromise
      .then(() => {
        Logger.warn(`[fileBackupTaskWorker] ${label} completed after timeout`);
      })
      .catch(err => {
        Logger.warn(`[fileBackupTaskWorker] ${label} failed after timeout: ${err && err.message ? err.message : String(err)}`);
      });
  }
  return result;
}

class FileBackupTaskWorker {
  constructor() {
    this.taskId = null;
    this.knex = null;
    this.engine = null;
    this.stopRequested = false;
    this.runningPromise = null;
    this._onStarted = null;
    this._startedNotified = false;
    this._lastProgressTs = 0;
    this._runLabel = '';
    this._runIndex = 0;
    this._runTotal = 0;
    this._ignoreOutput = false;
    this._backupRecordId = null;
    this._backupRecordStartMs = 0;
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

  async _updateTask(patch) {
    const idNum = Number(this.taskId);
    if (!this.knex || !Number.isFinite(idNum) || idNum <= 0) return;
    await this.knex('file_backup')
      .where({ id: idNum })
      .update({ ...patch })
      .catch(() => null);
  }

  async _getTaskRow() {
    const idNum = Number(this.taskId);
    if (!this.knex || !Number.isFinite(idNum) || idNum <= 0) return null;
    return await this.knex('file_backup')
      .where({ id: idNum })
      .first()
      .catch(() => null);
  }

  async _pruneBackupRecords(taskId) {
    const idNum = Number(taskId);
    if (!this.knex || !Number.isFinite(idNum) || idNum <= 0) return;
    const limit = tableFileBackupRecord.MAX_ROWS_PER_TASK;
    const keep = await this.knex('file_backup_record')
      .where({ task_id: idNum })
      .orderBy('id', 'desc')
      .limit(limit)
      .pluck('id')
      .catch(() => []);
    if (!keep || keep.length < limit) return;
    await this.knex('file_backup_record')
      .where({ task_id: idNum })
      .whereNotIn('id', keep)
      .del()
      .catch(() => null);
  }

  _mergeFileErrors(targetList, more) {
    if (!Array.isArray(more) || !Array.isArray(targetList)) return;
    for (const item of more) {
      if (targetList.length >= MAX_ERROR_FILES_TOTAL) break;
      if (item && typeof item === 'object') {
        targetList.push({
          path: ensureString(item.path),
          error: ensureString(item.error),
        });
      }
    }
  }

  async _insertFinishedBackupRecord(patch) {
    if (!this.knex) return;
    const idNum = Number(this.taskId);
    if (!Number.isFinite(idNum) || idNum <= 0) return;
    const startMs = Date.now();
    const endMs = Date.now();
    try {
      await this.knex('file_backup_record').insert({
        task_id: idNum,
        start_time: new Date(startMs),
        end_time: new Date(endMs),
        status: patch.status,
        files_copied_count: patch.files_copied_count ?? 0,
        files_skipped_count: patch.files_skipped_count ?? 0,
        files_removed_count: patch.files_removed_count ?? 0,
        bytes_copied_count: patch.bytes_copied_count ?? 0,
        error_file_list: patch.error_file_list ?? '[]',
        duration_ms: Math.max(0, endMs - startMs),
      });
      await this._pruneBackupRecords(idNum);
    } catch (_) {}
  }

  async _insertRunningBackupRecord() {
    this._backupRecordId = null;
    this._backupRecordStartMs = Date.now();
    if (!this.knex) return;
    const idNum = Number(this.taskId);
    if (!Number.isFinite(idNum) || idNum <= 0) return;
    try {
      const [newId] = await this.knex('file_backup_record').insert({
        task_id: idNum,
        start_time: new Date(this._backupRecordStartMs),
        end_time: null,
        status: tableFileBackupRecord.STATUS_RUNNING,
        files_copied_count: 0,
        files_skipped_count: 0,
        files_removed_count: 0,
        bytes_copied_count: 0,
        error_file_list: '[]',
        duration_ms: null,
      });
      this._backupRecordId = newId;
      await this._pruneBackupRecords(idNum);
    } catch (_) {
      this._backupRecordId = null;
    }
  }

  async _finishRunningBackupRecord(patch) {
    if (!this.knex || !this._backupRecordId) {
      this._backupRecordId = null;
      this._backupRecordStartMs = 0;
      return;
    }
    const idNum = Number(this.taskId);
    const recordId = Number(this._backupRecordId);
    const endMs = Date.now();
    const startMs = this._backupRecordStartMs || endMs;
    try {
      await this.knex('file_backup_record')
        .where({ id: recordId })
        .update({
          end_time: new Date(endMs),
          duration_ms: Math.max(0, endMs - startMs),
          status: patch.status,
          files_copied_count: patch.files_copied_count ?? 0,
          files_skipped_count: patch.files_skipped_count ?? 0,
          files_removed_count: patch.files_removed_count ?? 0,
          bytes_copied_count: patch.bytes_copied_count ?? 0,
          error_file_list: patch.error_file_list ?? '[]',
        });
      if (Number.isFinite(idNum) && idNum > 0) {
        await this._pruneBackupRecords(idNum);
      }
    } catch (_) {}
    this._backupRecordId = null;
    this._backupRecordStartMs = 0;
  }

  _updateProgress(sourceLabel, progress, force = false) {
    if (this.stopRequested || this._ignoreOutput) return;
    const now = Date.now();
    if (!force && now - this._lastProgressTs < 800) return;
    this._lastProgressTs = now;

    const parts = [];
    if (this._runLabel) {
      parts.push(this._runLabel);
    }
    if (sourceLabel) parts.push(sourceLabel);
    parts.push(progress && progress.summary ? progress.summary : summarizeProgress(progress || {}));
    this._updateTask({ progress: parts.join(' ') }).catch(() => null);
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

  async bind({ requestId, taskId }) {
    const idNum = Number(taskId);
    if (!Number.isFinite(idNum) || idNum <= 0) {
      this._reply('fileBackupBindResponse', { requestId, ok: false, error: 'invalid_params' });
      return;
    }
    this.taskId = idNum;
    this._reply('fileBackupBindResponse', { requestId, ok: true, taskId: idNum });
  }

  async start({ requestId }) {
    if (this.runningPromise) {
      this._reply('fileBackupStartResponse', { requestId, ok: true, already_running: true });
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
          this._ignoreOutput = true;
          await withTimeout(
            this._updateTask({
              status: tableFileBackup.STATUS_STOPPED,
              progress: '',
              last_error: errorText || 'failed',
            }),
            5000,
            'update_task_start_failure'
          ).catch(() => null);
          this._reply('fileBackupRunResponse', { requestId, ok: false, error: errorText || 'failed' });
          this._scheduleExit(0);
        })
        .finally(() => {
          this.runningPromise = null;
          this._onStarted = null;
          this._startedNotified = false;
        });
    });

    this._reply('fileBackupStartResponse', { requestId, ...(startedRes || { ok: true }) });
  }

  async run({ requestId }) {
    if (this.engine) {
      this._reply('fileBackupRunResponse', { requestId, ok: false, error: 'already_running' });
      this._notifyStarted({ ok: true, already_running: true });
      return;
    }
    this._ignoreOutput = false;
    this._backupRecordId = null;
    this._backupRecordStartMs = 0;

    const row = await this._getTaskRow();
    if (!row) {
      await this._insertFinishedBackupRecord({
        status: tableFileBackupRecord.STATUS_FAILED,
      });
      this._reply('fileBackupRunResponse', { requestId, ok: false, error: 'not_found' });
      this._notifyStarted({ ok: false, error: 'not_found' });
      this._scheduleExit(0);
      return;
    }

    const type = ensureString(row.type).trim();
    const targetRoot = ensureString(row.target_path).trim();
    const sourceList = ensureStringArray(safeJsonParse(row.source_path) || []);
    const excludeList = ensureStringArray(safeJsonParse(row.exclude_list) || []);
    const taskConfig = safeJsonParse(row.task_config) || {};

    if (!targetRoot || sourceList.length === 0) {
      await withTimeout(this._updateTask({ status: tableFileBackup.STATUS_ERROR, last_error: 'invalid_config', progress: '' }), 5000, 'update_task_invalid_config');
      await this._insertFinishedBackupRecord({
        status: tableFileBackupRecord.STATUS_FAILED,
      });
      this._reply('fileBackupRunResponse', { requestId, ok: false, error: 'invalid_config' });
      this._notifyStarted({ ok: false, error: 'invalid_config' });
      this._scheduleExit(0);
      return;
    }

    const targetErr = await checkDirReadableWritable(targetRoot);
    if (targetErr) {
      await withTimeout(this._updateTask({ status: tableFileBackup.STATUS_ERROR, last_error: targetErr, progress: '' }), 5000, 'update_task_target_error');
      await this._insertFinishedBackupRecord({
        status: tableFileBackupRecord.STATUS_FAILED,
      });
      this._reply('fileBackupRunResponse', { requestId, ok: false, error: targetErr });
      this._notifyStarted({ ok: false, error: targetErr });
      this._scheduleExit(0);
      return;
    }

    this.stopRequested = false;
    this._ignoreOutput = false;
    this._lastProgressTs = 0;
    await this._insertRunningBackupRecord();
    await withTimeout(this._updateTask({ status: tableFileBackup.STATUS_RUNNING, last_error: null, progress: 'starting' }), 5000, 'update_task_running');
    this._notifyStarted({ ok: true });

    const agg = {
      filesCopied: 0,
      filesSkipped: 0,
      filesRemoved: 0,
      bytesCopied: 0,
    };
    const mergedErrors = [];
    let sourceLevelFailure = false;
    let stopped = false;

    for (let idx = 0; idx < sourceList.length; idx++) {
      const src = sourceList[idx];
      const srcErr = await checkDirReadable(src);
      if (srcErr) {
        sourceLevelFailure = true;
        this._mergeFileErrors(mergedErrors, [{ path: src, error: srcErr }]);
        continue;
      }

      const srcName = normalizeRootName(src);
      const dest = path.join(targetRoot, srcName || `src_${idx + 1}`);
      try {
        await fs.promises.mkdir(dest, { recursive: true });
      } catch (e) {
        sourceLevelFailure = true;
        const msg = e && e.message ? String(e.message) : String(e);
        this._mergeFileErrors(mergedErrors, [{ path: dest, error: msg }]);
        continue;
      }

      const destErr = await checkDirReadableWritable(dest);
      if (destErr) {
        sourceLevelFailure = true;
        this._mergeFileErrors(mergedErrors, [{ path: dest, error: destErr }]);
        continue;
      }

      const runLabel = `running ${idx + 1}/${sourceList.length} ${src} -> ${dest}`;
      this._runLabel = runLabel;
      this._runIndex = idx + 1;
      this._runTotal = sourceList.length;
      await withTimeout(this._updateTask({ progress: runLabel }), 5000, 'update_task_progress_label');
      const sourceLabel = srcName ? `[${srcName}]` : '';

      try {
        this.engine = new NodeFileBackupEngine({
          type,
          sourceRoot: src,
          targetRoot: dest,
          excludeList,
          taskConfig,
          logger: Logger,
          shouldStop: () => this.stopRequested,
          onProgress: progress => this._updateProgress(sourceLabel, progress),
        });
        const result = await this.engine.run();
        agg.filesCopied += Number(result.filesCopied) || 0;
        agg.filesSkipped += Number(result.filesSkipped) || 0;
        agg.filesRemoved += Number(result.filesRemoved) || 0;
        agg.bytesCopied += Number(result.bytesCopied) || 0;
        this._mergeFileErrors(mergedErrors, result.fileErrors || []);
        this._updateProgress(
          sourceLabel,
          {
            phase: 'completed',
            ...result,
            currentRelativePath: '',
          },
          true
        );
        Logger.info(`🧷 fileBackup completed: ${src} -> ${dest}`, result);
      } catch (err) {
        if (err && err.code === 'STOPPED') {
          stopped = true;
          break;
        }
        sourceLevelFailure = true;
        const msg = err && err.message ? String(err.message) : String(err);
        this._mergeFileErrors(mergedErrors, [{ path: src, error: msg }]);
        Logger.error(`❌ fileBackup failed: ${src} -> ${dest}`, err);
      } finally {
        this.engine = null;
      }

      this._runLabel = '';
      this._runIndex = 0;
      this._runTotal = 0;

      if (this.stopRequested) {
        stopped = true;
        break;
      }
    }

    const errListJson = JSON.stringify(mergedErrors);
    const recordPayload = {
      files_copied_count: agg.filesCopied,
      files_skipped_count: agg.filesSkipped,
      files_removed_count: agg.filesRemoved,
      bytes_copied_count: agg.bytesCopied,
      error_file_list: errListJson,
    };

    if (this.stopRequested || stopped) {
      this._ignoreOutput = true;
      await withTimeout(this._updateTask({ status: tableFileBackup.STATUS_STOPPED, progress: '', last_error: null }), 5000, 'update_task_stopped');
      await this._finishRunningBackupRecord({
        ...recordPayload,
        status: tableFileBackupRecord.STATUS_STOPPED,
      });
      this._reply('fileBackupRunResponse', { requestId, ok: false, stopped: true });
      this._scheduleExit(0);
      return;
    }

    const recordOk = !sourceLevelFailure;
    const lastErrMsg =
      mergedErrors.length > 0 ? ensureString(mergedErrors[0].error).trim() || 'failed' : 'failed';

    if (recordOk) {
      this._ignoreOutput = true;
      await withTimeout(
        this._updateTask({
          status: tableFileBackup.STATUS_STOPPED,
          progress: '',
          last_error: null,
          last_success_time: new Date(),
        }),
        5000,
        'update_task_success'
      );
      await this._finishRunningBackupRecord({
        ...recordPayload,
        status: tableFileBackupRecord.STATUS_SUCCESS,
      });
      this._reply('fileBackupRunResponse', { requestId, ok: true });
      this._scheduleExit(0);
      return;
    }

    this._ignoreOutput = true;
    await withTimeout(
      this._updateTask({ status: tableFileBackup.STATUS_ERROR, progress: '', last_error: lastErrMsg }),
      5000,
      'update_task_failed'
    );
    await this._finishRunningBackupRecord({
      ...recordPayload,
      status: tableFileBackupRecord.STATUS_FAILED,
    });
    this._reply('fileBackupRunResponse', { requestId, ok: false, error: lastErrMsg });
    this._scheduleExit(0);
  }

  async stop({ requestId, timeoutMs }) {
    this.stopRequested = true;
    this._ignoreOutput = true;
    const engine = this.engine;
    if (!engine && !this.runningPromise) {
      await withTimeout(this._updateTask({ status: tableFileBackup.STATUS_STOPPED, progress: '', last_error: null }), 5000, 'update_task_stop_without_engine');
      this._reply('fileBackupStopResponse', { requestId, ok: true, stopped: true });
      this._scheduleExit(0);
      return;
    }

    try {
      if (engine) engine.cancel();
    } catch (_) {}

    const ms = Math.max(1000, Number(timeoutMs || 0) || 0);
    const completionPromise =
      this.runningPromise ||
      new Promise(resolve => {
        const timer = setInterval(() => {
          if (!this.engine) {
            clearInterval(timer);
            resolve(true);
          }
        }, 100);
      });
    const stopped = await Promise.race([
      Promise.resolve(completionPromise).then(() => true).catch(() => true),
      new Promise(resolve => setTimeout(() => resolve(false), ms)),
    ]);

    this.engine = null;
    await withTimeout(this._updateTask({ status: tableFileBackup.STATUS_STOPPED, progress: '', last_error: null }), 5000, 'update_task_stop_completed');
    this._reply('fileBackupStopResponse', { requestId, ok: true, stopped: true, graceful: !!stopped });
    this._scheduleExit(0);
  }

  _bindProcessEvents() {
    process.on('message', message => {
      if (!message || !message.type) return;
      if (message.type === 'bind') {
        const requestId = message?.data?.requestId;
        const taskId = message?.data?.taskId;
        this.bind({ requestId, taskId }).catch(err => {
          this._reply('fileBackupBindResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
        });
      } else if (message.type === 'start') {
        const requestId = message?.data?.requestId;
        this.start({ requestId }).catch(err => {
          this._reply('fileBackupStartResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
        });
      } else if (message.type === 'run') {
        const requestId = message?.data?.requestId;
        this.run({ requestId }).catch(err => {
          this._reply('fileBackupRunResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
        });
      } else if (message.type === 'stop') {
        const requestId = message?.data?.requestId;
        const timeoutMs = message?.data?.timeoutMs;
        this.stop({ requestId, timeoutMs }).catch(err => {
          this._reply('fileBackupStopResponse', { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) });
        });
      }
    });

    const graceful = signal => {
      try {
        Logger.info(`📡 fileBackupTaskWorker received ${signal}, exiting`);
      } catch (_) {}
      this.stop({ requestId: null, timeoutMs: 5000 })
        .catch(() => null)
        .finally(() => process.exit(0));
    };
    process.on('SIGTERM', () => graceful('SIGTERM'));
    process.on('SIGINT', () => graceful('SIGINT'));
    process.on('uncaughtException', err => {
      Logger.error('❌ fileBackupTaskWorker uncaughtException', err);
      graceful('uncaughtException');
    });
    process.on('unhandledRejection', reason => {
      Logger.error('❌ fileBackupTaskWorker unhandledRejection', reason);
      graceful('unhandledRejection');
    });
  }
}

if (require.main === module) {
  new FileBackupTaskWorker();
}

module.exports = FileBackupTaskWorker;
