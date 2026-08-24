const path = require('path');
const { loadConfig, saveConfig, isRpcReachable, probeTransmissionRuntime, reconcileTransmissionConfigIfStale } = require('../workers/transmission/transmissionConfig');
const { WORKER_NAME, findPidsOnPort } = require('../workers/transmission/transmissionWorker');

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
      reject(new Error('ipc_timeout'));
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

function ensureTransmissionWorker({ singletonWorkerManager, initUtil, Logger, serverId }) {
  const workerName = WORKER_NAME;
  if (singletonWorkerManager.workers.has(workerName)) {
    return singletonWorkerManager.workers.get(workerName);
  }

  return singletonWorkerManager.startWorker(workerName, `transmission${path.sep}transmissionWorker.js`, {
    env: {
      WORKER_TYPE: 'transmission',
      SERVER_ID: serverId,
      PATH_DATABASE: initUtil.pathDatabase,
      PATH_CACHE: initUtil.pathCache,
    },
    onStop: async () => {
      try {
        const { forceStopTransmissionProcesses } = require('../workers/transmission/transmissionWorker');
        const cfg = await loadConfig().catch(() => null);
        await forceStopTransmissionProcesses(cfg);
        await saveConfig({ status: 'stopped', enabled: false, started_at: null, actual_rpc_port: null });
      } catch (err) {
        Logger.warn('[transmission] onStop cleanup failed', err);
      }
    },
  });
}

let transmissionStartLock = null;

function runTransmissionStartLocked(task) {
  const prev = transmissionStartLock || Promise.resolve();
  const next = prev.catch(() => {}).then(task);
  transmissionStartLock = next.finally(() => {
    if (transmissionStartLock === next) transmissionStartLock = null;
  });
  return next;
}

function handleStartTransmission({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  const restart = !!message?.data?.restart;
  runTransmissionStartLocked(async () => {
    try {
      const workerName = WORKER_NAME;
      const cfg = await loadConfig();
      if (!restart && (await isRpcReachable(cfg))) {
        if (requestId) {
          expressWorker.send({
            type: 'startTransmissionResponse',
            data: {
              requestId,
              started: true,
              running: true,
              actual_rpc_port: cfg.actual_rpc_port || cfg.rpc_port,
              adopted: true,
            },
          });
        }
        return;
      }

      const status = singletonWorkerManager.getWorkerStatus(workerName);
      if (status && status.exists && !restart) {
        const worker = singletonWorkerManager.workers.get(workerName);
        const innerStatusId = `transStatus_${Date.now()}_${Math.random().toString(16).slice(2)}`;
        worker.send({ type: 'status', data: { requestId: innerStatusId } });
        const statusData = await waitForWorkerMessage({
          worker,
          type: 'transmissionStatusResponse',
          requestId: innerStatusId,
          timeoutMs: 5000,
        });

        if (statusData.running) {
          if (requestId) {
            expressWorker.send({
              type: 'startTransmissionResponse',
              data: { requestId, started: true, running: true, ...statusData },
            });
          }
          return;
        }

        const innerStartId = `transStart_${Date.now()}_${Math.random().toString(16).slice(2)}`;
        worker.send({ type: 'start', data: { requestId: innerStartId } });
        const data = await waitForWorkerMessage({
          worker,
          type: 'transmissionStartResponse',
          requestId: innerStartId,
          timeoutMs: 25000,
        });
        if (requestId) {
          expressWorker.send({
            type: 'startTransmissionResponse',
            data: {
              requestId,
              started: !!data.ok,
              running: !!data.running,
              error: data.error || null,
              pid: data.pid || null,
              actual_rpc_port: data.actual_rpc_port || null,
            },
          });
        }
        return;
      }

      if (restart && status && status.exists) {
        await singletonWorkerManager.stopWorker(workerName, 10000);
      }

      const worker = ensureTransmissionWorker({ singletonWorkerManager, initUtil, Logger, serverId });
      const innerRequestId = `transStart_${Date.now()}_${Math.random().toString(16).slice(2)}`;
      worker.send({ type: 'start', data: { requestId: innerRequestId } });
      const data = await waitForWorkerMessage({
        worker,
        type: 'transmissionStartResponse',
        requestId: innerRequestId,
        timeoutMs: 25000,
      });

      if (requestId) {
        expressWorker.send({
          type: 'startTransmissionResponse',
          data: {
            requestId,
            started: !!data.ok,
            running: !!data.running,
            error: data.error || null,
            pid: data.pid || null,
            actual_rpc_port: data.actual_rpc_port || null,
          },
        });
      }
    } catch (err) {
      Logger.error('[transmission] start failed', err);
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'startTransmissionResponse',
          data: { requestId, started: false, running: false, error: err && err.message ? String(err.message) : 'start_failed' },
        });
      } catch (_) {}
    }
  });
}

function handleStopTransmission({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  Promise.resolve()
    .then(async () => {
      const workerName = WORKER_NAME;
      const status = singletonWorkerManager.getWorkerStatus(workerName);
      if (status && status.running) {
        const worker = singletonWorkerManager.workers.get(workerName);
        const innerRequestId = `transStop_${Date.now()}_${Math.random().toString(16).slice(2)}`;
        worker.send({ type: 'stop', data: { requestId: innerRequestId } });
        await waitForWorkerMessage({
          worker,
          type: 'transmissionStopResponse',
          requestId: innerRequestId,
          timeoutMs: 15000,
        });
        await singletonWorkerManager.stopWorker(workerName, 8000);
      } else {
        const { forceStopTransmissionProcesses } = require('../workers/transmission/transmissionWorker');
        let cfg = await loadConfig().catch(() => null);
        const probe = await probeTransmissionRuntime(cfg);
        await forceStopTransmissionProcesses(cfg, {
          actualRpcPort: probe.actual_rpc_port || (cfg && cfg.rpc_port),
          graceful: true,
        });
        await saveConfig({ status: 'stopped', enabled: false, started_at: null, actual_rpc_port: null });
        cfg = await loadConfig().catch(() => null);
        if (cfg && (await isRpcReachable(cfg))) {
          await forceStopTransmissionProcesses(cfg, { graceful: false });
        }
      }

      if (requestId) {
        expressWorker.send({
          type: 'stopTransmissionResponse',
          data: { requestId, stopped: true },
        });
      }
    })
    .catch(err => {
      Logger.error('[transmission] stop failed', err);
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopTransmissionResponse',
          data: { requestId, stopped: false, error: err && err.message ? String(err.message) : 'stop_failed' },
        });
      } catch (_) {}
    });
}

function handleGetTransmissionStatus({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  Promise.resolve()
    .then(async () => {
      let cfg = await loadConfig();
      let probe = await probeTransmissionRuntime(cfg);
      cfg = await reconcileTransmissionConfigIfStale(cfg, probe);
      if (!cfg.enabled) {
        probe = await probeTransmissionRuntime(cfg);
      }

      const workerName = WORKER_NAME;
      const workerStatus = singletonWorkerManager.getWorkerStatus(workerName);
      let pid = null;

      if (probe.running) {
        if (workerStatus && workerStatus.running) {
          try {
            const worker = singletonWorkerManager.workers.get(workerName);
            const innerRequestId = `transStatus_${Date.now()}_${Math.random().toString(16).slice(2)}`;
            worker.send({ type: 'status', data: { requestId: innerRequestId } });
            const statusData = await waitForWorkerMessage({
              worker,
              type: 'transmissionStatusResponse',
              requestId: innerRequestId,
              timeoutMs: 5000,
            });
            pid = statusData.pid || null;
          } catch (_) {}
        }
        if (!pid && probe.actual_rpc_port) {
          const pids = findPidsOnPort(probe.actual_rpc_port);
          pid = pids.length ? pids[0] : null;
        }
      }

      const running = !!probe.running && !!cfg.enabled;

      if (requestId) {
        expressWorker.send({
          type: 'getTransmissionStatusResponse',
          data: {
            requestId,
            status: running ? 'running' : 'stopped',
            enabled: cfg.enabled,
            configured_rpc_port: probe.configured_rpc_port || cfg.rpc_port,
            actual_rpc_port: running ? probe.actual_rpc_port : probe.stale_rpc_port || null,
            port_mismatch: !!probe.port_mismatch,
            pid,
            running,
            last_error: running ? null : cfg.last_error,
            started_at: running ? cfg.started_at : null,
            auto_start: cfg.auto_start,
          },
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'getTransmissionStatusResponse',
          data: { requestId, running: false, error: err && err.message ? String(err.message) : 'status_failed' },
        });
      } catch (_) {}
    });
}

module.exports = {
  startTransmission: handleStartTransmission,
  stopTransmission: handleStopTransmission,
  getTransmissionStatus: handleGetTransmissionStatus,
};
