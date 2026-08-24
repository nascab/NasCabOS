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
      Number(timeoutMs || 15000) || 15000
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

async function hasAutoRunningMounts(knexMain) {
  try {
    const row = await knexMain('openlist_mount').where({ auto_running: 1 }).first('id');
    return !!row;
  } catch (_) {
    return false;
  }
}

module.exports = {
  async restoreOpenlistMountsOnStartup({ serverId }) {
    const serverIdStr = serverId === undefined || serverId === null ? '' : String(serverId).trim();
    if (!serverIdStr) return;

    const knexMain = dbUtil.getConnectMainDb().knex;
    const any = await hasAutoRunningMounts(knexMain);
    if (!any) return;

    const workerName = 'openlistWorker';

    const ensureStartedAndReload = async () => {
      const status = singletonWorkerManager.getWorkerStatus(workerName);
      if (status && status.running) {
        const worker = singletonWorkerManager.workers.get(workerName);
        if (worker && typeof worker.send === 'function') {
          const requestId = `startup_openlist_reload_${Date.now()}`;
          const wait = waitForWorkerMessage({ worker, type: 'openlistMountReloadResponse', requestId, timeoutMs: 120000 });
          try {
            worker.send({ type: 'reload', data: { requestId } });
            await wait.catch(() => null);
          } catch (_) {}
        }
        return;
      }

      const worker = singletonWorkerManager.startWorker(workerName, `openlist${path.sep}openlistWorker.js`, {
        env: {
          WORKER_TYPE: 'openlist',
          SERVER_ID: serverIdStr,
          PATH_DATABASE: this.pathDatabase,
          PATH_CACHE: this.pathCache,
        },
        onStart: () => Logger.info(`🧷 openlist started: ${workerName}`),
        onStop: async (code, signal) => {
          Logger.info(`🧷 openlist stopped: ${workerName}`, code, signal);
        },
        onError: async err => {
          Logger.error(`❌ openlist error: ${workerName}`, err);
        },
      });

      const requestId = `startup_openlist_reload_${Date.now()}`;
      const wait = waitForWorkerMessage({ worker, type: 'openlistMountReloadResponse', requestId, timeoutMs: 120000 });
      try {
        worker.send({ type: 'reload', data: { requestId } });
        await wait.catch(() => null);
      } catch (_) {}
    };

    await ensureStartedAndReload();
  },
};
