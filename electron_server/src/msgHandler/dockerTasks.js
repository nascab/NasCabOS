function sendResponse(expressWorker, payload) {
  if (!expressWorker || typeof expressWorker.send !== 'function') return;
  try {
    expressWorker.send({
      type: 'dockerTaskResponse',
      data: payload,
    });
  } catch (_) {}
}

function waitForWorkerMessage({ worker, type, requestId, timeoutMs }) {
  return new Promise((resolve, reject) => {
    if (!worker) {
      reject(new Error('docker_task_worker_unavailable'));
      return;
    }

    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      try {
        worker.removeListener('message', onMessage);
      } catch (_) {}
      reject(new Error('docker_task_worker_timeout'));
    }, Math.max(500, Number(timeoutMs || 0) || 0));

    const onMessage = message => {
      if (!message || message.type !== type) return;
      if (!message.data || message.data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      try {
        worker.removeListener('message', onMessage);
      } catch (_) {}
      resolve(message.data || {});
    };

    worker.on('message', onMessage);
  });
}

function handleDockerTaskRequest({ expressWorker, initUtil, Logger, message }) {
  const data = message && message.data && typeof message.data === 'object' ? message.data : {};
  const requestId = data.requestId ? String(data.requestId) : '';
  const action = data.action ? String(data.action) : '';
  const payload = data.payload && typeof data.payload === 'object' ? data.payload : {};
  if (!requestId || !action) return;

  Promise.resolve()
    .then(async () => {
      const worker = initUtil.startDockerTaskWorker();
      const wait = waitForWorkerMessage({
        worker,
        type: 'dockerTaskResponse',
        requestId,
        timeoutMs: 30000,
      });
      worker.send({
        type: 'dockerTaskRequest',
        data: {
          requestId,
          action,
          payload,
        },
      });
      const response = await wait;
      sendResponse(expressWorker, response);
    })
    .catch(error => {
      if (Logger) {
        Logger.error('dockerTaskRequest failed', error);
      }
      sendResponse(expressWorker, {
        requestId,
        ok: false,
        error: {
          code: 'common.ERROR',
          statusCode: 500,
          message: error && error.message ? String(error.message) : 'docker task request failed',
        },
      });
    });
}

module.exports = {
  dockerTaskRequest: handleDockerTaskRequest,
};
