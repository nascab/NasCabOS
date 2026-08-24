const path = require('path');
const Logger = require('../utils/logger');
const { getSingletonWorkerManager } = require('../workers/singletonWorkerManager');
const { loadConfig, reconcileTransmissionConfigIfStale, probeTransmissionRuntime } = require('../workers/transmission/transmissionConfig');
const { WORKER_NAME } = require('../workers/transmission/transmissionWorker');

const singletonWorkerManager = getSingletonWorkerManager();

function waitForWorkerMessage({ worker, type, requestId, timeoutMs }) {
  return new Promise((resolve, reject) => {
    let done = false;
    const ms = Math.max(500, Number(timeoutMs || 0) || 0);
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      try {
        worker.removeListener('message', onMessage);
      } catch (_) {}
      reject(new Error('start_timeout'));
    }, ms);

    const onMessage = msg => {
      if (!msg || msg.type !== type) return;
      const data = msg.data || {};
      if (requestId && data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      try {
        worker.removeListener('message', onMessage);
      } catch (_) {}
      resolve(data);
    };

    worker.on('message', onMessage);
  });
}

module.exports = {
  async restoreTransmissionOnStartup({ serverId }) {
    const serverIdStr = serverId === undefined || serverId === null ? '' : String(serverId).trim();
    if (!serverIdStr) return;

    let cfg;
    try {
      cfg = await loadConfig();
      const probe = await probeTransmissionRuntime(cfg);
      cfg = await reconcileTransmissionConfigIfStale(cfg, probe);
    } catch (err) {
      Logger.error('[transmission] load config on startup failed', err);
      return;
    }

    const shouldRestore = cfg.auto_start || cfg.enabled;
    if (!shouldRestore) return;

    const workerName = WORKER_NAME;
    const status = singletonWorkerManager.getWorkerStatus(workerName);
    if (status && status.running) return;

    Logger.info('[transmission] restoring daemon on startup');
    try {
      const worker = singletonWorkerManager.startWorker(workerName, `transmission${path.sep}transmissionWorker.js`, {
        env: {
          WORKER_TYPE: 'transmission',
          SERVER_ID: serverIdStr,
          PATH_DATABASE: this.pathDatabase,
          PATH_CACHE: this.pathCache,
        },
        onStop: async () => {
          try {
            const { forceStopTransmissionProcesses } = require('../workers/transmission/transmissionWorker');
            const { saveConfig } = require('../workers/transmission/transmissionConfig');
            const cfg = await loadConfig().catch(() => null);
            await forceStopTransmissionProcesses(cfg);
            await saveConfig({ status: 'stopped', enabled: false, started_at: null, actual_rpc_port: null });
          } catch (_) {}
        },
      });

      const requestId = `startup_transmission_${Date.now()}`;
      worker.send({ type: 'start', data: { requestId } });
      const startRes = await waitForWorkerMessage({
        worker,
        type: 'transmissionStartResponse',
        requestId,
        timeoutMs: 25000,
      });

      if (!startRes || !startRes.ok) {
        Logger.warn('[transmission] restore on startup failed', startRes && startRes.error ? startRes.error : 'unknown');
        await singletonWorkerManager.stopWorker(workerName, 8000).catch(() => false);
      }
    } catch (err) {
      Logger.error('[transmission] restore on startup error', err);
    }
  },
};
