const path = require('path');
const Logger = require('../utils/logger');
const dbUtil = require('../db/dbUtil');
const { getSingletonWorkerManager } = require('../workers/singletonWorkerManager');

const singletonWorkerManager = getSingletonWorkerManager();

function waitForWorkerMessage({ worker, type, requestId, timeoutMs }) {
  return new Promise((resolve, reject) => {
    let done = false;
    const timer = setTimeout(
      () => {
        if (done) return;
        done = true;
        try {
          worker.removeListener('message', onMessage);
        } catch (_) {}
        reject(new Error('timeout'));
      },
      Number(timeoutMs || 8000) || 8000
    );

    const onMessage = msg => {
      if (done) return;
      if (!msg || msg.type !== type) return;
      const rid = msg && msg.data ? msg.data.requestId : null;
      if (rid !== requestId) return;
      done = true;
      clearTimeout(timer);
      try {
        worker.removeListener('message', onMessage);
      } catch (_) {}
      resolve(msg.data || {});
    };
    worker.on('message', onMessage);
  });
}

function clampIntervalMs(ms) {
  const n = Number(ms);
  if (!Number.isFinite(n) || n <= 0) return 60 * 60 * 1000;
  return Math.max(60 * 1000, Math.min(30 * 24 * 60 * 60 * 1000, n));
}

function ensureSchedulerStore(initUtil) {
  if (!initUtil._fileBackupScheduler) {
    initUtil._fileBackupScheduler = {
      timers: new Map(),
    };
  }
  return initUtil._fileBackupScheduler;
}

async function triggerTaskNow({ initUtil, serverId, idNum }) {
  const serverIdStr = serverId === undefined || serverId === null ? '' : String(serverId).trim();
  if (!serverIdStr) return { ok: false, error: 'invalid_server_id' };

  const workerName = `fileBackupTask_${idNum}`;
  const worker = singletonWorkerManager.startWorker(workerName, `fileBackup${path.sep}fileBackupTaskWorker.js`, {
    env: {
      WORKER_TYPE: 'fileBackup',
      SERVER_ID: serverIdStr,
      PATH_DATABASE: initUtil.pathDatabase,
      PATH_CACHE: initUtil.pathCache,
      FILE_BACKUP_TASK_ID: String(idNum),
    },
    onStart: () => Logger.info(`🧷 fileBackup started: ${workerName}`),
    onStop: (code, signal) => Logger.info(`🧷 fileBackup stopped: ${workerName}`, code, signal),
    onError: err => Logger.error(`❌ fileBackup error: ${workerName}`, err),
  });

  const bindRequestId = `fileBackupBind_${idNum}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const bindWait = waitForWorkerMessage({ worker, type: 'fileBackupBindResponse', requestId: bindRequestId, timeoutMs: 8000 });
  try {
    worker.send({ type: 'bind', data: { requestId: bindRequestId, taskId: idNum } });
  } catch (_) {
    return { ok: false, error: 'send_failed' };
  }

  const bindRes = await bindWait.catch(() => null);
  if (!bindRes || !bindRes.ok) return { ok: false, error: (bindRes && bindRes.error) || 'bind_failed' };

  try {
    worker.send({ type: 'start', data: { requestId: `fileBackupStart_${idNum}_${Date.now()}` } });
  } catch (_) {
    return { ok: false, error: 'send_failed' };
  }
  return { ok: true };
}

async function shouldRunTask({ idNum }) {
  const knexMain = dbUtil.getConnectMainDb().knex;
  const row = await knexMain('file_backup')
    .where({ id: idNum })
    .select('status')
    .first()
    .catch(() => null);
  const status = row && row.status !== undefined && row.status !== null ? String(row.status).trim().toLowerCase() : '';
  if (!status) return false;
  if (status === 'disabled') return false;
  if (status === 'running') return false;
  return true;
}

module.exports = {
  stopFileBackupsScheduler() {
    const store = ensureSchedulerStore(this);
    for (const [, t] of store.timers) {
      if (t && t.timeoutId) clearTimeout(t.timeoutId);
      if (t && t.intervalId) clearInterval(t.intervalId);
    }
    store.timers.clear();
  },

  async reloadFileBackupsScheduler({ serverId, reconcileRunning = false }) {
    this.stopFileBackupsScheduler();
    await this.restoreFileBackupsOnStartup({ serverId, reconcileRunning });
  },

  async restoreFileBackupsOnStartup({ serverId, reconcileRunning = false }) {
    const serverIdStr = serverId === undefined || serverId === null ? '' : String(serverId).trim();
    if (!serverIdStr) return;

    const knexMain = dbUtil.getConnectMainDb().knex;
    const rows = await knexMain('file_backup')
      .whereNot({ status: 'disabled' })
      .select('id', 'frenquence', 'last_success_time', 'create_time', 'status')
      .catch(() => []);
    if (!rows || rows.length === 0) return;

    const store = ensureSchedulerStore(this);
    for (const r of rows) {
      const idNum = Number(r && r.id);
      if (!Number.isFinite(idNum) || idNum <= 0) continue;

      const freqHours = Number(r && r.frenquence);
      const intervalMs = clampIntervalMs((Number.isFinite(freqHours) ? freqHours : 24) * 60 * 60 * 1000);

      const status = r && r.status !== undefined && r.status !== null ? String(r.status).trim().toLowerCase() : '';
      const interrupted = status === 'running';
      if (reconcileRunning && interrupted) {
        await knexMain('file_backup')
          .where({ id: idNum })
          .update({ status: 'stopped', progress: '', last_error: 'interrupted' })
          .catch(() => null);
      }

      const baseTs = interrupted ? Date.now() : r && r.last_success_time ? new Date(r.last_success_time).getTime() : r && r.create_time ? new Date(r.create_time).getTime() : Date.now();
      const baseOk = Number.isFinite(baseTs) && baseTs > 0;
      const nextTs = (baseOk ? baseTs : Date.now()) + intervalMs;
      const delayMs = Math.max(2000, nextTs - Date.now());

      let inflight = false;
      const tick = async () => {
        if (inflight) return;
        inflight = true;
        try {
          const ok = await shouldRunTask({ idNum }).catch(() => false);
          if (!ok) return;
          await triggerTaskNow({ initUtil: this, serverId: serverIdStr, idNum }).catch(() => null);
        } finally {
          inflight = false;
        }
      };

      const t = { timeoutId: null, intervalId: null, intervalMs };
      const timeoutId = setTimeout(async () => {
        t.timeoutId = null;
        await tick();
        if (!t.intervalId) {
          t.intervalId = setInterval(() => {
            tick().catch(() => null);
          }, intervalMs);
        }
      }, delayMs);
      t.timeoutId = timeoutId;
      store.timers.set(idNum, t);
    }

    Logger.info(`🧷 fileBackup scheduler restored: ${rows.length} tasks`);
  },
};
