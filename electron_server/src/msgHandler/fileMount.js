const path = require('path');
const dbUtil = require('../db/dbUtil');
const remoteAssets = require('../utils/remoteAssetsManager');

function ensureWorker({ singletonWorkerManager, initUtil, Logger, serverId }) {
  const workerName = 'fileMountWorker';
  const status = singletonWorkerManager.getWorkerStatus(workerName);
  if (status && status.running) return singletonWorkerManager.workers.get(workerName);

  const knexMain = dbUtil.getConnectMainDb().knex;
  const worker = singletonWorkerManager.startWorker(workerName, `fileMount${path.sep}fileMountWorker.js`, {
    env: {
      WORKER_TYPE: 'fileMount',
      SERVER_ID: serverId,
      PATH_DATABASE: initUtil.pathDatabase,
      PATH_CACHE: initUtil.pathCache,
    },
    onStart: () => Logger.info(`🧷 fileMount started: ${workerName}`),
    onStop: async (code, signal) => {
      const exitedOk = Number(code || 0) === 0;
      try {
        if (!exitedOk) {
          await knexMain('file_mount')
            .where({ status: 'running' })
            .update({
              status: 'error',
              last_error: `exit:${code ?? ''}:${signal ?? ''}`,
              update_time: new Date(),
            });
        } else {
          await knexMain('file_mount').where({ status: 'running' }).update({
            last_error: null,
            update_time: new Date(),
          });
        }
      } catch (_) {}
      Logger.info(`🧷 fileMount stopped: ${workerName}`, code, signal);
    },
    onError: async err => {
      try {
        await knexMain('file_mount')
          .where({ status: 'running' })
          .update({
            status: 'error',
            last_error: err && err.message ? String(err.message) : String(err),
            update_time: new Date(),
          });
      } catch (_) {}
      Logger.error(`❌ fileMount error: ${workerName}`, err);
    },
  });
  return worker;
}

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

async function setAutoRunning({ idNum, autoRunning }) {
  const knexMain = dbUtil.getConnectMainDb().knex;
  try {
    await knexMain('file_mount')
      .where({ id: idNum })
      .update({
        auto_running: autoRunning ? 1 : 0,
        update_time: new Date(),
      });
  } catch (_) {}
}

function handleStartFileMount({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  const id = message?.data?.id;
  Promise.resolve()
    .then(async () => {
      const idNum = Number(id);
      try {
        Logger.info('[fileMount bridge] startFileMount from express', {
          requestId,
          idNum,
          expressPid: expressWorker && expressWorker.pid,
        });
      } catch (_) {}
      if (!Number.isFinite(idNum) || idNum <= 0) {
        if (requestId) {
          expressWorker.send({ type: 'startFileMountResponse', data: { requestId, started: false, error: 'common.INVALID_PARAMS' } });
        }
        return;
      }

      try {
        remoteAssets.assertFileMountPluginReady();
      } catch (e) {
        if (requestId) {
          expressWorker.send({
            type: 'startFileMountResponse',
            data: { requestId, started: false, error: remoteAssets.PLUGIN_NOT_READY },
          });
        }
        return;
      }

      const worker = ensureWorker({ singletonWorkerManager, initUtil, Logger, serverId });
      try {
        Logger.info('[fileMount bridge] fileMountWorker process', {
          requestId,
          idNum,
          workerPid: worker && worker.pid,
          connected: !!(worker && worker.connected),
          channel: !!(worker && worker.channel),
        });
      } catch (_) {}
      const wait = waitForWorkerMessage({ worker, type: 'fileMountStartResponse', requestId, timeoutMs: 15000 });
      try {
        worker.send({ type: 'start', data: { requestId, id: idNum } });
        try {
          Logger.info('[fileMount bridge] sent start to fileMountWorker', { requestId, idNum, workerPid: worker && worker.pid });
        } catch (_) {}
      } catch (e) {
        try {
          Logger.error('[fileMount bridge] worker.send(start) failed', { requestId, idNum, err: e && e.message });
        } catch (_) {}
        if (requestId) {
          expressWorker.send({ type: 'startFileMountResponse', data: { requestId, started: false, error: 'fileMount.WORKER_SEND_FAILED' } });
        }
        return;
      }

      let res;
      try {
        res = await wait;
      } catch (err) {
        try {
          Logger.error('[fileMount bridge] wait fileMountStartResponse timeout or error', {
            requestId,
            idNum,
            workerPid: worker && worker.pid,
            connected: !!(worker && worker.connected),
            killed: !!(worker && worker.killed),
            errMsg: err && err.message ? String(err.message) : String(err),
          });
        } catch (_) {}
        if (requestId) {
          expressWorker.send({ type: 'startFileMountResponse', data: { requestId, started: false, error: 'fileMount.START_TIMEOUT' } });
        }
        return;
      }

      if (res && res.ok) {
        await setAutoRunning({ idNum, autoRunning: true });
      }

      try {
        Logger.info('[fileMount bridge] fileMountStartResponse received, forwarding to express', {
          requestId,
          idNum,
          ok: !!(res && res.ok),
          error: res && res.error,
        });
      } catch (_) {}

      if (requestId) {
        expressWorker.send({
          type: 'startFileMountResponse',
          data: { requestId, started: !!res.ok, id: idNum, pid: res.pid || null, error: res.error || null, detail: res.detail || null },
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({ type: 'startFileMountResponse', data: { requestId, started: false, error: err && err.message ? String(err.message) : String(err) } });
      } catch (_) {}
    });
}

function handleStopFileMount({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  const id = message?.data?.id;
  Promise.resolve()
    .then(async () => {
      const idNum = Number(id);
      if (!Number.isFinite(idNum) || idNum <= 0) {
        if (requestId) {
          expressWorker.send({ type: 'stopFileMountResponse', data: { requestId, stopped: false, error: 'common.INVALID_PARAMS' } });
        }
        return;
      }

      if (!singletonWorkerManager.isWorkerRunning('fileMountWorker')) {
        await setAutoRunning({ idNum, autoRunning: false });
        try {
          const knexMain = dbUtil.getConnectMainDb().knex;
          await knexMain('file_mount')
            .where({ id: idNum })
            .update({ status: 'stopped', last_error: null, update_time: new Date() });
        } catch (_) {}
        if (requestId) {
          expressWorker.send({
            type: 'stopFileMountResponse',
            data: { requestId, stopped: true, id: idNum },
          });
        }
        return;
      }

      const worker = ensureWorker({ singletonWorkerManager, initUtil, Logger, serverId });
      const wait = waitForWorkerMessage({ worker, type: 'fileMountStopResponse', requestId, timeoutMs: 15000 });
      try {
        worker.send({ type: 'stop', data: { requestId, id: idNum } });
      } catch (e) {
        if (requestId) {
          expressWorker.send({ type: 'stopFileMountResponse', data: { requestId, stopped: false, error: 'fileMount.WORKER_SEND_FAILED' } });
        }
        return;
      }

      let res;
      try {
        res = await wait;
      } catch (_) {
        if (requestId) {
          expressWorker.send({ type: 'stopFileMountResponse', data: { requestId, stopped: false, error: 'fileMount.STOP_TIMEOUT' } });
        }
        return;
      }

      if (res && res.ok) {
        await setAutoRunning({ idNum, autoRunning: false });
      }

      if (requestId) {
        expressWorker.send({
          type: 'stopFileMountResponse',
          data: { requestId, stopped: !!res.ok, id: idNum, error: res.error || null },
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({ type: 'stopFileMountResponse', data: { requestId, stopped: false, error: err && err.message ? String(err.message) : String(err) } });
      } catch (_) {}
    });
}

module.exports = {
  startFileMount: handleStartFileMount,
  stopFileMount: handleStopFileMount,
};
