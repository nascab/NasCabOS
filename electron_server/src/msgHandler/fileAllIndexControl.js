const tableConfig = require('../db/table/tableConfig');
const FileAllIndexFtsStore = require('../workers/fileAllIndex/fileAllIndexFtsStore');

const CONFIG_KEY_ENABLE = 'file_all_index_enabled';
const CONFIG_KEY_INTERVAL_HOURS = 'file_all_index_interval_hours';
const CONFIG_KEY_LAST_FULL_SCAN_MS = 'fileAllIndexLastFullScanMs';

function _safeIntervalHours(v) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return 72;
  if (n <= 0) return 72;
  return n;
}

function _sendResponse(expressWorker, type, payload) {
  if (!expressWorker || typeof expressWorker.send !== 'function') return;
  try {
    expressWorker.send({ type, data: payload });
  } catch (_) {}
}

function toggleFileAllIndexWorker({ expressWorker, initUtil, singletonWorkerManager, message }) {
  const requestId = message?.data?.requestId;
  const enable = !!message?.data?.enable;
  const intervalHours = _safeIntervalHours(message?.data?.intervalHours);

  Promise.resolve()
    .then(async () => {
      if (!enable) {
        const stopped = await initUtil.stopFileAllIndexWorker().catch(() => false);
        if (requestId) {
          _sendResponse(expressWorker, 'toggleFileAllIndexWorkerResponse', {
            requestId,
            ok: true,
            running: false,
            stopped: !!stopped,
          });
        }
        return;
      }

      const worker = initUtil.startFileAllIndexWorker();
      try {
        worker?.send?.({ type: 'config', data: { intervalHours } });
      } catch (_) {}

      const running = singletonWorkerManager.isWorkerRunning('fileAllIndexWorker');
      if (requestId) {
        _sendResponse(expressWorker, 'toggleFileAllIndexWorkerResponse', {
          requestId,
          ok: true,
          running: !!running,
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      _sendResponse(expressWorker, 'toggleFileAllIndexWorkerResponse', {
        requestId,
        ok: false,
        running: singletonWorkerManager.isWorkerRunning('fileAllIndexWorker'),
        error: err && err.message ? String(err.message) : String(err),
      });
    });
}

function resetFileAllIndex({ expressWorker, initUtil, singletonWorkerManager, message }) {
  const requestId = message?.data?.requestId;
  Promise.resolve()
    .then(async () => {
      const store = new FileAllIndexFtsStore();
      await store.clearAll();
      await tableConfig.setConfigByKey(CONFIG_KEY_LAST_FULL_SCAN_MS, '0').catch(() => {});

      const enableRaw = await tableConfig.getConfigByKey(CONFIG_KEY_ENABLE).catch(() => '0');
      const enabled = enableRaw === '1';

      let triggered = false;
      if (enabled) {
        const intervalRaw = await tableConfig.getConfigByKey(CONFIG_KEY_INTERVAL_HOURS).catch(() => null);
        const intervalHours = _safeIntervalHours(intervalRaw);

        const worker = initUtil.startFileAllIndexWorker();
        try {
          worker?.send?.({ type: 'config', data: { intervalHours } });
        } catch (_) {}
        try {
          worker?.send?.({ type: 'fullIndexNow' });
          triggered = true;
        } catch (_) {
          triggered = false;
        }
      }

      const running = singletonWorkerManager.isWorkerRunning('fileAllIndexWorker');
      if (requestId) {
        _sendResponse(expressWorker, 'resetFileAllIndexResponse', {
          requestId,
          ok: true,
          enabled,
          triggered,
          running: !!running,
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      _sendResponse(expressWorker, 'resetFileAllIndexResponse', {
        requestId,
        ok: false,
        error: err && err.message ? String(err.message) : String(err),
      });
    });
}

module.exports = {
  toggleFileAllIndexWorker,
  resetFileAllIndex,
};
