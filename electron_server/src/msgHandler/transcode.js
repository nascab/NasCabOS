function handleStartTranscode({ singletonWorkerManager, initUtil, Logger, message }) {
  const playId = message?.data?.playId;
  const filePath = message?.data?.filePath;
  const options = message?.data?.options;
  const playIdStr = playId ? String(playId) : '';
  if (!playIdStr) return;

  const workerName = `transcode_${playIdStr}`;
  const status = singletonWorkerManager.getWorkerStatus(workerName);
  if (status.running) return;

  const transcodeWorker = singletonWorkerManager.startWorker(workerName, 'transcodeWorker.js', {
    env: {
      WORKER_TYPE: 'transcode',
      PATH_DATABASE: initUtil.pathDatabase,
      PATH_CACHE: initUtil.pathCache,
    },
    onStart: () => Logger.info(`🎥 Transcode started for ${playIdStr}`),
    onStop: () => Logger.info(`🛑 Transcode stopped for ${playIdStr}`),
    onError: error => Logger.error(`❌ Transcode error ${playIdStr}`, error),
  });
  if (transcodeWorker) {
    transcodeWorker.send({ type: 'start', data: { playId: playIdStr, filePath, options } });
  }
}

function handleStopTranscode({ expressWorker, singletonWorkerManager, Logger, message }) {
  const playId = message?.data?.playId;
  const playIdStr = playId ? String(playId) : '';
  if (!playIdStr) return;

  const workerName = `transcode_${playIdStr}`;
  Promise.resolve()
    .then(async () => {
      const stopped = await singletonWorkerManager.stopWorker(workerName);
      expressWorker.send({ type: 'transcodeStopped', data: { playId: playIdStr, stopped } });
    })
    .catch(err => {
      expressWorker.send({
        type: 'transcodeStopped',
        data: { playId: playIdStr, stopped: false },
      });
      Logger.error(`❌ stopTranscode failed: ${playIdStr}`, err);
    });
}

module.exports = {
  startTranscode: handleStartTranscode,
  stopTranscode: handleStopTranscode,
};
