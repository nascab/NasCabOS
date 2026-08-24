const path = require('path');

function handleStartVideoScrape({ expressWorker, singletonWorkerManager, initUtil, Logger, message }) {
  const requestId = message?.data?.requestId;
  const indexId = Number(message?.data?.indexId || 0) || 0;
  const tmdbId = message?.data?.tmdbId ? Number(message.data.tmdbId || 0) || 0 : 0;
  const mode = message?.data?.mode ? String(message.data.mode).trim() : '';

  if (!indexId) {
    try {
      if (requestId) {
        expressWorker.send({
          type: 'startVideoScrapeResponse',
          data: { requestId, started: false, error: 'invalid_index_id' },
        });
      }
    } catch (_) {}
    return;
  }

  const workerName = `videoScrape_${indexId}`;
  const status = singletonWorkerManager.getWorkerStatus(workerName);
  if (status && status.running) {
    try {
      if (requestId) {
        expressWorker.send({
          type: 'startVideoScrapeResponse',
          data: { requestId, started: true, running: true },
        });
      }
    } catch (_) {}
    return;
  }

  const worker = singletonWorkerManager.startWorker(workerName, `videoIndex${path.sep}videoScrapeWorker${path.sep}videoScrapeWorker.js`, {
    env: {
      WORKER_TYPE: 'videoScrape',
      PATH_DATABASE: initUtil.pathDatabase,
      PATH_CACHE: initUtil.pathCache,
      SCRAPE_MODE: mode || undefined,
    },
    onStart: () => Logger.info(`🎬 videoScrape started: ${workerName}`),
    onStop: (code, signal) => Logger.info(`🎬 videoScrape stopped: ${workerName}`, code, signal),
    onError: error => Logger.error(`❌ videoScrape error: ${workerName}`, error),
  });

  if (worker && typeof worker.send === 'function') {
    try {
      worker.send({ type: 'start', data: { indexId, tmdbId } });
    } catch (_) {}
  }

  try {
    if (requestId) {
      expressWorker.send({
        type: 'startVideoScrapeResponse',
        data: { requestId, started: true, running: false },
      });
    }
  } catch (_) {}
}

module.exports = {
  startVideoScrape: handleStartVideoScrape,
};
