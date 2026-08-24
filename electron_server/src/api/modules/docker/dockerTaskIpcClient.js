const { randomUUID } = require('crypto');

function createRequestId(prefix = 'dockerTask') {
  if (typeof randomUUID === 'function') {
    return `${prefix}_${randomUUID()}`;
  }
  return `${prefix}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function waitForIpcResponse({ requestId, responseType, timeoutMs }) {
  return new Promise((resolve, reject) => {
    if (typeof process.send !== 'function') {
      const err = new Error('common.ERROR');
      err.code = 'common.ERROR';
      err.statusCode = 500;
      reject(err);
      return;
    }

    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      try {
        process.removeListener('message', onMessage);
      } catch (_) {}
      const err = new Error('common.ERROR');
      err.code = 'common.ERROR';
      err.statusCode = 504;
      reject(err);
    }, Math.max(500, Number(timeoutMs || 0) || 0));

    const onMessage = message => {
      if (!message || message.type !== responseType) return;
      if (!message.data || message.data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      try {
        process.removeListener('message', onMessage);
      } catch (_) {}
      resolve(message.data || {});
    };

    process.on('message', onMessage);
  });
}

async function requestDockerTask(action, payload = {}, { timeoutMs = 15000 } = {}) {
  const requestId = createRequestId(action || 'dockerTask');
  const wait = waitForIpcResponse({
    requestId,
    responseType: 'dockerTaskResponse',
    timeoutMs,
  });
  process.send({
    type: 'dockerTaskRequest',
    data: {
      requestId,
      action: String(action || '').trim(),
      payload: payload && typeof payload === 'object' ? payload : {},
    },
    timestamp: Date.now(),
  });
  return await wait;
}

module.exports = {
  requestDockerTask,
  waitForIpcResponse,
};
