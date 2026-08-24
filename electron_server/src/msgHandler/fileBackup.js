const path = require('path');
const dbUtil = require('../db/dbUtil');

function ensureTaskWorker({ singletonWorkerManager, initUtil, Logger, serverId, taskId }) {
  const workerName = `fileBackupTask_${taskId}`;
  const status = singletonWorkerManager.getWorkerStatus(workerName);
  if (status && status.running) return singletonWorkerManager.workers.get(workerName);

  const knexMain = dbUtil.getConnectMainDb().knex;
  const worker = singletonWorkerManager.startWorker(workerName, `fileBackup${path.sep}fileBackupTaskWorker.js`, {
    env: {
      WORKER_TYPE: 'fileBackup',
      SERVER_ID: serverId,
      PATH_DATABASE: initUtil.pathDatabase,
      PATH_CACHE: initUtil.pathCache,
      FILE_BACKUP_TASK_ID: String(taskId),
    },
    onStart: () => Logger.info(`🧷 fileBackup started: ${workerName}`),
    onStop: async (code, signal) => {
      const exitedOk = Number(code || 0) === 0;
      try {
        if (exitedOk) {
          await knexMain('file_backup').where({ id: taskId, status: 'running' }).update({ status: 'stopped', progress: '' });
        } else {
          await knexMain('file_backup')
            .where({ id: taskId, status: 'running' })
            .update({
              status: 'stopped',
              progress: '',
              last_error: `exit:${code ?? ''}:${signal ?? ''}`,
            });
        }
      } catch (_) {}
      Logger.info(`🧷 fileBackup stopped: ${workerName}`, code, signal);
    },
    onError: async err => {
      try {
        await knexMain('file_backup')
          .where({ id: taskId, status: 'running' })
          .update({
            status: 'stopped',
            progress: '',
            last_error: err && err.message ? String(err.message) : String(err),
          });
      } catch (_) {}
      Logger.error(`❌ fileBackup error: ${workerName}`, err);
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

async function ensureTaskExists({ idNum }) {
  const knexMain = dbUtil.getConnectMainDb().knex;
  return await knexMain('file_backup')
    .where({ id: idNum })
    .first()
    .catch(() => null);
}

function handleReloadFileBackupTasks({ expressWorker, initUtil, message, serverId }) {
  const requestId = message?.data?.requestId;
  if (!requestId) return;
  Promise.resolve()
    .then(async () => {
      try {
        if (initUtil && typeof initUtil.reloadFileBackupsScheduler === 'function') {
          await initUtil.reloadFileBackupsScheduler({ serverId });
        }
      } catch (_) {}
      try {
        expressWorker.send({ type: 'reloadFileBackupTasksResponse', data: { requestId, ok: true } });
      } catch (_) {}
    })
    .catch(() => {
      try {
        expressWorker.send({ type: 'reloadFileBackupTasksResponse', data: { requestId, ok: false } });
      } catch (_) {}
    });
}

function handleStartFileBackupTask({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  const id = message?.data?.id;
  Promise.resolve()
    .then(async () => {
      const idNum = Number(id);
      if (!Number.isFinite(idNum) || idNum <= 0) {
        if (requestId) {
          expressWorker.send({ type: 'startFileBackupTaskResponse', data: { requestId, started: false, error: 'invalid_params' } });
        }
        return;
      }

      const existed = await ensureTaskExists({ idNum });
      if (!existed) {
        if (requestId) {
          expressWorker.send({ type: 'startFileBackupTaskResponse', data: { requestId, started: false, error: 'not_found' } });
        }
        return;
      }

      const workerName = `fileBackupTask_${idNum}`;
      const status = singletonWorkerManager.getWorkerStatus(workerName);
      if (status && status.running) {
        try {
          const knexMain = dbUtil.getConnectMainDb().knex;
          await knexMain('file_backup').where({ id: idNum }).update({ status: 'running' });
        } catch (_) {}
      }

      const worker = ensureTaskWorker({ singletonWorkerManager, initUtil, Logger, serverId, taskId: idNum });

      const bindWait = waitForWorkerMessage({ worker, type: 'fileBackupBindResponse', requestId, timeoutMs: 8000 });
      try {
        worker.send({ type: 'bind', data: { requestId, taskId: idNum } });
      } catch (_) {
        if (requestId) {
          expressWorker.send({ type: 'startFileBackupTaskResponse', data: { requestId, started: false, error: 'send_failed' } });
        }
        return;
      }

      const bindRes = await bindWait.catch(() => null);
      if (!bindRes || !bindRes.ok) {
        if (requestId) {
          expressWorker.send({
            type: 'startFileBackupTaskResponse',
            data: { requestId, started: false, id: idNum, error: (bindRes && bindRes.error) || 'bind_failed' },
          });
        }
        return;
      }

      const wait = waitForWorkerMessage({ worker, type: 'fileBackupStartResponse', requestId, timeoutMs: 15000 });
      try {
        worker.send({ type: 'start', data: { requestId } });
      } catch (_) {
        if (requestId) {
          expressWorker.send({ type: 'startFileBackupTaskResponse', data: { requestId, started: false, error: 'send_failed' } });
        }
        return;
      }

      const res = await wait.catch(() => null);
      if (!res) {
        if (requestId) {
          expressWorker.send({ type: 'startFileBackupTaskResponse', data: { requestId, started: false, id: idNum, error: 'start_timeout' } });
        }
        return;
      }

      const started = !!res.ok || !!res.already_running;
      if (requestId) {
        expressWorker.send({
          type: 'startFileBackupTaskResponse',
          data: { requestId, started, id: idNum, pid: res.pid || null, error: res.error || null },
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'startFileBackupTaskResponse',
          data: { requestId, started: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

function handleStopFileBackupTask({ expressWorker, singletonWorkerManager, message }) {
  const requestId = message?.data?.requestId;
  const id = message?.data?.id;
  Promise.resolve()
    .then(async () => {
      const idNum = Number(id);
      if (!Number.isFinite(idNum) || idNum <= 0) {
        if (requestId) {
          expressWorker.send({ type: 'stopFileBackupTaskResponse', data: { requestId, stopped: false, error: 'invalid_params' } });
        }
        return;
      }

      const workerName = `fileBackupTask_${idNum}`;
      const status = singletonWorkerManager.getWorkerStatus(workerName);
      if (!status || !status.exists) {
        try {
          const knexMain = dbUtil.getConnectMainDb().knex;
          await knexMain('file_backup').where({ id: idNum }).update({ status: 'stopped', last_error: null, progress: '' });
        } catch (_) {}
        if (requestId) {
          expressWorker.send({ type: 'stopFileBackupTaskResponse', data: { requestId, stopped: true, id: idNum } });
        }
        return;
      }

      const worker = singletonWorkerManager.workers.get(workerName);
      if (!worker) {
        if (requestId) {
          expressWorker.send({ type: 'stopFileBackupTaskResponse', data: { requestId, stopped: true, id: idNum } });
        }
        return;
      }

      const wait = waitForWorkerMessage({ worker, type: 'fileBackupStopResponse', requestId, timeoutMs: 20000 });
      try {
        worker.send({ type: 'stop', data: { requestId, timeoutMs: 15000 } });
      } catch (_) {
        if (requestId) {
          expressWorker.send({ type: 'stopFileBackupTaskResponse', data: { requestId, stopped: false, id: idNum, error: 'send_failed' } });
        }
        return;
      }

      const res = await wait.catch(() => null);
      await singletonWorkerManager.stopWorker(workerName, 8000).catch(() => null);

      if (!res) {
        if (requestId) {
          expressWorker.send({ type: 'stopFileBackupTaskResponse', data: { requestId, stopped: false, id: idNum, error: 'stop_timeout' } });
        }
        return;
      }

      if (requestId) {
        expressWorker.send({
          type: 'stopFileBackupTaskResponse',
          data: { requestId, stopped: !!res.ok, id: idNum, error: res.error || null },
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopFileBackupTaskResponse',
          data: { requestId, stopped: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

module.exports = {
  reloadFileBackupTasks: handleReloadFileBackupTasks,
  startFileBackupTask: handleStartFileBackupTask,
  stopFileBackupTask: handleStopFileBackupTask,
};
