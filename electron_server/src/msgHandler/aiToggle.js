const knexUtil = require('../db/knexUtil');
const dbUtil = require('../db/dbUtil');

function handleToggleAiOcr({ initUtil, Logger, message }) {
  const enable = message?.data?.enable ? 1 : 0;
  if (enable) {
    initUtil.startOcrWorker();
    return;
  }

  Promise.resolve()
    .then(() => initUtil.stopOcrWorker())
    .catch(err => Logger.error('❌ stopOcrWorker failed', err));
}

function handleToggleAiFace({ expressWorker, initUtil, Logger, message }) {
  const enable = message?.data?.enable ? 1 : 0;
  const requestId = message?.data?.requestId;
  const sendResponse = (ok, error) => {
    if (!requestId) return;
    try {
      expressWorker.send({
        type: 'toggleAiFaceResponse',
        data: {
          requestId,
          enable,
          ok: !!ok,
          running: typeof initUtil.isFaceWorkerRunning === 'function' ? initUtil.isFaceWorkerRunning() : undefined,
          error: error ? String(error) : undefined,
        },
      });
    } catch (_) {}
  };

  if (enable) {
    try {
      initUtil.startFaceWorker();
      sendResponse(true);
    } catch (err) {
      Logger.error('❌ startFaceWorker failed', err);
      sendResponse(false, err && err.message ? err.message : err);
    }
    return;
  }

  Promise.resolve()
    .then(() => initUtil.stopFaceWorker())
    .then(() => sendResponse(true))
    .catch(err => {
      Logger.error('❌ stopFaceWorker failed', err);
      sendResponse(false, err && err.message ? err.message : err);
    });
}

function handleToggleAiPlace({ initUtil, Logger, message }) {
  const enable = message?.data?.enable ? 1 : 0;
  if (enable) {
    initUtil.startPlacesWorker();
    return;
  }

  Promise.resolve()
    .then(() => initUtil.stopPlacesWorker())
    .catch(err => Logger.error('❌ stopPlacesWorker failed', err));
}

function handleToggleAiSimilar({ initUtil, Logger, message }) {
  const enable = message?.data?.enable ? 1 : 0;
  if (enable) {
    try {
      initUtil.startSimilarWorker();
    } catch (e) {
      Logger.error('❌ startSimilarWorker failed', e);
    }
    return;
  }

  Promise.resolve()
    .then(() => initUtil.stopSimilarWorker())
    .catch(err => Logger.error('❌ stopSimilarWorker failed', err));
}

function handleStartSimilarScan({ initUtil, Logger }) {
  try {
    initUtil.startSimilarWorker();
  } catch (err) {
    Logger.error('❌ startSimilarWorker failed', err);
  }
}

function handleStartGpsSupplementScan({ initUtil, Logger }) {
  try {
    initUtil.startGpsSupplementWorker();
  } catch (err) {
    Logger.error('❌ startGpsSupplementWorker failed', err);
  }
}

function handleToggleAiGpu({ initUtil, Logger, message }) {
  const enable = message?.data?.enable ? 1 : 0;
  const wasEnabled = process.env.AI_GPU_PREFER !== '0';
  const nowEnabled = enable === 1;

  // 设置主进程环境变量，后续 fork 的子进程都会继承
  process.env.AI_GPU_PREFER = nowEnabled ? '1' : '0';

  // 如果状态未发生变化，无需重启 worker
  if (wasEnabled === nowEnabled) return;

  Logger.info(`[aiToggle] GPU prefer ${nowEnabled ? 'enabled' : 'disabled'}, restarting AI workers...`);

  // 检查哪些 AI worker 正在运行，记录需要重启的
  const wasFaceRunning = typeof initUtil.isFaceWorkerRunning === 'function' && initUtil.isFaceWorkerRunning();
  const wasOcrRunning = typeof initUtil.isOcrWorkerRunning === 'function' && initUtil.isOcrWorkerRunning();
  const wasPlacesRunning = typeof initUtil.isPlacesWorkerRunning === 'function' && initUtil.isPlacesWorkerRunning();

  // 停止所有 AI worker
  const stopPromises = [];
  if (wasFaceRunning) stopPromises.push(initUtil.stopFaceWorker().catch(() => {}));
  if (wasOcrRunning) stopPromises.push(initUtil.stopOcrWorker().catch(() => {}));
  if (wasPlacesRunning) stopPromises.push(initUtil.stopPlacesWorker().catch(() => {}));

  Promise.all(stopPromises).then(() => {
    // 重新启动之前运行的 worker（新 worker 会继承更新后的 AI_GPU_PREFER）
    setTimeout(() => {
      if (wasFaceRunning) {
        try { initUtil.startFaceWorker(); } catch (e) { Logger.error('❌ restartFaceWorker failed', e); }
      }
      if (wasOcrRunning) {
        try { initUtil.startOcrWorker(); } catch (e) { Logger.error('❌ restartOcrWorker failed', e); }
      }
      if (wasPlacesRunning) {
        try { initUtil.startPlacesWorker(); } catch (e) { Logger.error('❌ restartPlacesWorker failed', e); }
      }
    }, 1000);
  }).catch(err => {
    Logger.error('❌ stop AI workers for GPU toggle failed:', err);
  });
}

module.exports = {
  toggleAiOcr: handleToggleAiOcr,
  toggleAiFace: handleToggleAiFace,
  toggleAiPlace: handleToggleAiPlace,
  toggleAiSimilar: handleToggleAiSimilar,
  toggleAiGpu: handleToggleAiGpu,
  startSimilarScan: handleStartSimilarScan,
  startGpsSupplementScan: handleStartGpsSupplementScan,
};
