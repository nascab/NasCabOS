const path = require('path');
const dbUtil = require('../db/dbUtil');

function ensureTaskWorker({ singletonWorkerManager, initUtil, Logger, serverId, taskId }) {
  const workerName = `mediaArrangeTask_${taskId}`;
  const status = singletonWorkerManager.getWorkerStatus(workerName);
  if (status && status.running) return singletonWorkerManager.workers.get(workerName);

  const knexMain = dbUtil.getConnectMainDb().knex;
  const worker = singletonWorkerManager.startWorker(workerName, `mediaTool${path.sep}mediaArrange${path.sep}mediaArrangeWorker.js`, {
    env: {
      WORKER_TYPE: 'mediaArrange',
      SERVER_ID: serverId,
      PATH_DATABASE: initUtil.pathDatabase,
      PATH_CACHE: initUtil.pathCache,
      MEDIA_ARRANGE_TASK_ID: String(taskId),
    },
    onStart: () => Logger.info(`🧷 mediaArrange started: ${workerName}`),
    onStop: async (code, signal) => {
      try {
        await knexMain('media_tool_arrange').where({ id: taskId, status: 'running' }).update({
          status: 'stopped',
          progress: '',
          last_error: null,
          update_time: new Date(),
          last_end_time: new Date(),
        });
      } catch (_) {}
      Logger.info(`🧷 mediaArrange stopped: ${workerName}`, code, signal);
    },
    onError: async err => {
      try {
        await knexMain('media_tool_arrange').where({ id: taskId, status: 'running' }).update({
          status: 'stopped',
          progress: '',
          last_error: null,
          update_time: new Date(),
          last_end_time: new Date(),
        });
      } catch (_) {}
      Logger.error(`❌ mediaArrange error: ${workerName}`, err);
    },
  });
  return worker;
}

function waitForWorkerMessage({ worker, type, requestId, timeoutMs }) {
  return new Promise(resolve => {
    if (!worker) {
      resolve({});
      return;
    }

    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      worker.removeListener('message', onMessage);
      resolve({ error: 'timeout' });
    }, timeoutMs);

    const onMessage = message => {
      if (!message || message.type !== type) return;
      if (requestId && message.data && message.data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      worker.removeListener('message', onMessage);
      resolve(message.data || {});
    };

    worker.on('message', onMessage);
  });
}

async function ensureTaskExists({ idNum }) {
  const knexMain = dbUtil.getConnectMainDb().knex;
  return await knexMain('media_tool_arrange')
    .where({ id: idNum })
    .first()
    .catch(() => null);
}

function handleStartMediaArrangeTask({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  const id = message?.data?.id;
  Promise.resolve()
    .then(async () => {
      const idNum = Number(id);
      if (!Number.isFinite(idNum) || idNum <= 0) {
        if (requestId) {
          expressWorker.send({ type: 'startMediaArrangeTaskResponse', data: { requestId, started: false, error: 'invalid_params' } });
        }
        return;
      }

      const existed = await ensureTaskExists({ idNum });
      if (!existed) {
        if (requestId) {
          expressWorker.send({ type: 'startMediaArrangeTaskResponse', data: { requestId, started: false, error: 'not_found' } });
        }
        return;
      }

      const workerName = `mediaArrangeTask_${idNum}`;
      const status = singletonWorkerManager.getWorkerStatus(workerName);
      if (status && status.running) {
        try {
          const knexMain = dbUtil.getConnectMainDb().knex;
          await knexMain('media_tool_arrange').where({ id: idNum }).update({ status: 'running', update_time: new Date() });
        } catch (_) {}
      }

      const worker = ensureTaskWorker({ singletonWorkerManager, initUtil, Logger, serverId, taskId: idNum });
      const wait = waitForWorkerMessage({ worker, type: 'mediaArrangeStartResponse', requestId, timeoutMs: 20000 });
      try {
        worker.send({ type: 'start', data: { requestId, taskId: idNum } });
        const data = await wait;
        if (requestId) {
          expressWorker.send({ type: 'startMediaArrangeTaskResponse', data: { requestId, started: data.ok, error: data.error } });
        }
      } catch (err) {
        if (requestId) {
          expressWorker.send({ type: 'startMediaArrangeTaskResponse', data: { requestId, started: false, error: 'start_timeout' } });
        }
      }
    })
    .catch(err => {
      Logger.error('handleStartMediaArrangeTask error', err);
      if (requestId) {
        expressWorker.send({ type: 'startMediaArrangeTaskResponse', data: { requestId, started: false, error: 'unknown_error' } });
      }
    });
}

function handleStopMediaArrangeTask({ expressWorker, singletonWorkerManager, message }) {
  const requestId = message?.data?.requestId;
  const id = message?.data?.id;
  Promise.resolve()
    .then(async () => {
      const idNum = Number(id);
      if (!Number.isFinite(idNum) || idNum <= 0) {
        if (requestId) {
          expressWorker.send({ type: 'stopMediaArrangeTaskResponse', data: { requestId, stopped: false, error: 'invalid_params' } });
        }
        return;
      }

      const workerName = `mediaArrangeTask_${idNum}`;
      const status = singletonWorkerManager.getWorkerStatus(workerName);
      if (!status || !status.exists) {
        try {
          const knexMain = dbUtil.getConnectMainDb().knex;
          await knexMain('media_tool_arrange').where({ id: idNum }).update({ status: 'stopped', last_error: null, progress: '', update_time: new Date(), last_end_time: new Date() });
        } catch (_) {}
        if (requestId) {
          expressWorker.send({ type: 'stopMediaArrangeTaskResponse', data: { requestId, stopped: true, id: idNum } });
        }
        return;
      }

      const worker = singletonWorkerManager.workers.get(workerName);
      if (!worker) {
        if (requestId) {
          expressWorker.send({ type: 'stopMediaArrangeTaskResponse', data: { requestId, stopped: true, id: idNum } });
        }
        return;
      }

      const wait = waitForWorkerMessage({ worker, type: 'mediaArrangeStopResponse', requestId, timeoutMs: 30000 });
      try {
        worker.send({ type: 'stop', data: { requestId } });
        const res = await wait.catch(() => null);
        await singletonWorkerManager.stopWorker(workerName, 8000).catch(() => null);

        if (!res) {
          if (requestId) {
            expressWorker.send({ type: 'stopMediaArrangeTaskResponse', data: { requestId, stopped: false, id: idNum, error: 'stop_timeout' } });
          }
          return;
        }

        if (requestId) {
          expressWorker.send({
            type: 'stopMediaArrangeTaskResponse',
            data: { requestId, stopped: !!res.ok, id: idNum, error: res.error || null },
          });
        }
      } catch (err) {
        if (requestId) {
          await singletonWorkerManager.stopWorker(workerName, 8000).catch(() => null);
          expressWorker.send({ type: 'stopMediaArrangeTaskResponse', data: { requestId, stopped: false, id: idNum, error: 'stop_timeout' } });
        }
      }
    })
    .catch(err => {

      if (requestId) {
        expressWorker.send({ type: 'stopMediaArrangeTaskResponse', data: { requestId, stopped: false, error: 'unknown_error' } });
      }
    });
}

module.exports = {
  startMediaArrangeTask: handleStartMediaArrangeTask,
  stopMediaArrangeTask: handleStopMediaArrangeTask,
};
