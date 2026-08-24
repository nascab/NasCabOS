const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function handleDownloadUrlToFile({ singletonWorkerManager, initUtil, Logger, message }) {
  const url = message?.data?.url ? String(message.data.url).trim() : '';
  const targetPath = message?.data?.targetPath ? String(message.data.targetPath).trim() : '';
  const allowProxy = !!message?.data?.allowProxy;
  const timeoutMs = Math.min(120000, Math.max(1000, Number(message?.data?.timeoutMs || 30000) || 30000));
  if (!url || !targetPath) return;

  Promise.resolve()
    .then(async () => {
      try {
        const st = await fs.promises.stat(targetPath);
        if (st && st.isFile()) return;
      } catch (_) {}

      const dir = path.dirname(targetPath);
      await fs.promises.mkdir(dir, { recursive: true });

      const hash = crypto.createHash('sha1').update(url).digest('hex');
      const tmpPath = path.join(dir, `${hash}.tmp`);
      const workerName = `downloadUrl_${hash}`;
      const status = singletonWorkerManager.getWorkerStatus(workerName);
      if (status && status.running) return;

      const worker = singletonWorkerManager.startWorker(workerName, 'downloadUrlToFileWorker.js', {
        env: {
          WORKER_TYPE: 'downloadUrlToFile',
          PATH_DATABASE: initUtil.pathDatabase,
          PATH_CACHE: initUtil.pathCache,
        },
        onStart: () => Logger.info(`🖼️ downloadUrl started: ${workerName}`),
        onStop: () => Logger.info(`🖼️ downloadUrl stopped: ${workerName}`),
        onError: error => Logger.error(`❌ downloadUrl error: ${workerName}`, error),
      });
      if (worker) {
        worker.send({ type: 'start', data: { url, targetPath, tmpPath, timeoutMs, allowProxy } });
      }
    })
    .catch(err => {
      Logger.error('❌ downloadUrlToFile failed', err);
    });
}

module.exports = {
  downloadUrlToFile: handleDownloadUrlToFile,
};
