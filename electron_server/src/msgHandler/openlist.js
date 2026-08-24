const path = require('path');
const dbUtil = require('../db/dbUtil');
const remoteAssets = require('../utils/remoteAssetsManager');

function ensureWorker({ singletonWorkerManager, initUtil, Logger, serverId }) {
  const workerName = 'openlistWorker';
  const status = singletonWorkerManager.getWorkerStatus(workerName);
  if (status && status.running) return singletonWorkerManager.workers.get(workerName);

  const knexMain = dbUtil.getConnectMainDb().knex;
  const config = require('../config/config');
  const openlistDataPath = config.getOpenListDataPath();
  const worker = singletonWorkerManager.startWorker(workerName, `openlist${path.sep}openlistWorker.js`, {
    env: {
      WORKER_TYPE: 'openlist',
      SERVER_ID: serverId,
      PATH_DATABASE: initUtil.pathDatabase,
      PATH_CACHE: initUtil.pathCache,
      PATH_OPENLIST_DATA: openlistDataPath,
    },
    onStart: () => Logger.info(`🧷 openlist started: ${workerName}`),
    onStop: async (code, signal) => {
      const exitedOk = Number(code || 0) === 0;
      try {
        if (!exitedOk) {
          await knexMain('openlist_mount')
            .where({ status: 'running' })
            .update({
              status: 'error',
              last_error: `exit:${code ?? ''}:${signal ?? ''}`,
              update_time: new Date(),
            });
        }
      } catch (_) {}
      Logger.info(`🧷 openlist stopped: ${workerName}`, code, signal);
    },
    onError: async err => {
      try {
        await knexMain('openlist_mount')
          .where({ status: 'running' })
          .update({
            status: 'error',
            last_error: err && err.message ? String(err.message) : String(err),
            update_time: new Date(),
          });
      } catch (_) {}
      Logger.error(`❌ openlist error: ${workerName}`, err);
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
      Number(timeoutMs || 20000) || 20000
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
    await knexMain('openlist_mount')
      .where({ id: idNum })
      .update({
        auto_running: autoRunning ? 1 : 0,
        update_time: new Date(),
      });
  } catch (_) {}
}

function forwardToWorker({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId, workerMsgType, responseType, timeoutMs }) {
  const requestId = message?.data?.requestId;
  Promise.resolve()
    .then(async () => {
      const worker = ensureWorker({ singletonWorkerManager, initUtil, Logger, serverId });
      const wait = waitForWorkerMessage({ worker, type: responseType, requestId, timeoutMs });
      try {
        worker.send({ type: workerMsgType, data: message.data });
      } catch (e) {
        if (requestId) {
          expressWorker.send({
            type: responseType,
            data: { requestId, ok: false, error: 'openlistMount.WORKER_SEND_FAILED' },
          });
        }
        return;
      }
      let res;
      try {
        res = await wait;
      } catch (_) {
        if (requestId) {
          expressWorker.send({
            type: responseType,
            data: { requestId, ok: false, error: 'openlistMount.TIMEOUT' },
          });
        }
        return;
      }
      if (requestId) {
        expressWorker.send({ type: responseType, data: { requestId, ...res } });
      }
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: responseType,
          data: { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

function handleEnsureOpenList(ctx) {
  forwardToWorker({
    ...ctx,
    workerMsgType: 'ensureOpenList',
    responseType: 'openlistEnsureResponse',
    timeoutMs: 60000,
  });
}

function handleOpenlistGetDrivers(ctx) {
  forwardToWorker({
    ...ctx,
    workerMsgType: 'getDrivers',
    responseType: 'openlistGetDriversResponse',
    timeoutMs: 30000,
  });
}

function handleOpenlistDeleteStorage(ctx) {
  forwardToWorker({
    ...ctx,
    workerMsgType: 'deleteStorage',
    responseType: 'openlistDeleteStorageResponse',
    timeoutMs: 20000,
  });
}

function handleStartOpenlistMount({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  const id = message?.data?.id;
  Promise.resolve()
    .then(async () => {
      const idNum = Number(id);
      if (!Number.isFinite(idNum) || idNum <= 0) {
        if (requestId) {
          expressWorker.send({
            type: 'openlistMountStartResponse',
            data: { requestId, ok: false, error: 'common.INVALID_PARAMS' },
          });
        }
        return;
      }

      try {
        remoteAssets.assertOpenlistMountPluginReady();
      } catch (e) {
        if (requestId) {
          expressWorker.send({
            type: 'openlistMountStartResponse',
            data: { requestId, ok: false, error: remoteAssets.PLUGIN_NOT_READY },
          });
        }
        return;
      }

      const worker = ensureWorker({ singletonWorkerManager, initUtil, Logger, serverId });
      const wait = waitForWorkerMessage({ worker, type: 'openlistMountStartResponse', requestId, timeoutMs: 90000 });
      try {
        worker.send({ type: 'start', data: { requestId, id: idNum } });
      } catch (e) {
        if (requestId) {
          expressWorker.send({
            type: 'openlistMountStartResponse',
            data: { requestId, ok: false, error: 'openlistMount.WORKER_SEND_FAILED' },
          });
        }
        return;
      }

      let res;
      try {
        res = await wait;
      } catch (_) {
        if (requestId) {
          expressWorker.send({
            type: 'openlistMountStartResponse',
            data: { requestId, ok: false, error: 'openlistMount.START_TIMEOUT' },
          });
        }
        return;
      }

      if (res && res.ok) {
        await setAutoRunning({ idNum, autoRunning: true });
      }

      if (requestId) {
        expressWorker.send({
          type: 'openlistMountStartResponse',
          data: {
            requestId,
            ok: !!res.ok,
            id: idNum,
            pid: res.pid || null,
            error: res.error || null,
            mountPath: res.mountPath || null,
          },
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'openlistMountStartResponse',
          data: { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

function handleStopOpenlistMount({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  const id = message?.data?.id;
  Promise.resolve()
    .then(async () => {
      const idNum = Number(id);
      if (!Number.isFinite(idNum) || idNum <= 0) {
        if (requestId) {
          expressWorker.send({
            type: 'openlistMountStopResponse',
            data: { requestId, ok: false, error: 'common.INVALID_PARAMS' },
          });
        }
        return;
      }

      if (!singletonWorkerManager.isWorkerRunning('openlistWorker')) {
        await setAutoRunning({ idNum, autoRunning: false });
        try {
          const knexMain = dbUtil.getConnectMainDb().knex;
          await knexMain('openlist_mount')
            .where({ id: idNum })
            .update({ status: 'stopped', last_error: null, update_time: new Date() });
        } catch (_) {}
        if (requestId) {
          expressWorker.send({ type: 'openlistMountStopResponse', data: { requestId, ok: true, id: idNum } });
        }
        return;
      }

      const worker = ensureWorker({ singletonWorkerManager, initUtil, Logger, serverId });
      const wait = waitForWorkerMessage({ worker, type: 'openlistMountStopResponse', requestId, timeoutMs: 15000 });
      try {
        worker.send({ type: 'stop', data: { requestId, id: idNum } });
      } catch (e) {
        if (requestId) {
          expressWorker.send({
            type: 'openlistMountStopResponse',
            data: { requestId, ok: false, error: 'openlistMount.WORKER_SEND_FAILED' },
          });
        }
        return;
      }

      let res;
      try {
        res = await wait;
      } catch (_) {
        if (requestId) {
          expressWorker.send({
            type: 'openlistMountStopResponse',
            data: { requestId, ok: false, error: 'openlistMount.STOP_TIMEOUT' },
          });
        }
        return;
      }

      if (res && res.ok) {
        await setAutoRunning({ idNum, autoRunning: false });
      }

      if (requestId) {
        expressWorker.send({
          type: 'openlistMountStopResponse',
          data: { requestId, ok: !!res.ok, id: idNum, error: res.error || null },
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'openlistMountStopResponse',
          data: { requestId, ok: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

module.exports = {
  ensureOpenList: handleEnsureOpenList,
  openlistGetDrivers: handleOpenlistGetDrivers,
  openlistDeleteStorage: handleOpenlistDeleteStorage,
  startOpenlistMount: handleStartOpenlistMount,
  stopOpenlistMount: handleStopOpenlistMount,
};
