const path = require('path');
const FileUtil = require('../utils/fileUtil');

// pending requestId -> expressWorker
const _pendingById = new Map();
// fileHash -> Set<requestId>
const _pendingByHash = new Map();

function _normalizeText(v) {
  if (v === undefined || v === null) return '';
  return String(v).trim();
}

function _ensureWorker({ singletonWorkerManager, initUtil, Logger, fileHash }) {
  const hash = _normalizeText(fileHash);
  if (!hash) return null;
  const workerName = `subtitleVtt_${hash}`;
  if (singletonWorkerManager.isWorkerRunning(workerName)) {
    return singletonWorkerManager.startWorker(workerName, 'subtitleVttWorker.js', { keepConfig: false });
  }
  return singletonWorkerManager.startWorker(workerName, 'subtitleVttWorker.js', {
    keepConfig: false,
    env: {
      WORKER_TYPE: 'subtitleVtt',
      PATH_DATABASE: initUtil.pathDatabase,
      PATH_CACHE: initUtil.pathCache,
    },
    onStart: () => {
      try {
        Logger.info(`📝 subtitleVttWorker started hash=${hash}`);
      } catch (_) {}
    },
    onStop: (code, signal) => {
      try {
        Logger.info(`📝 subtitleVttWorker stopped hash=${hash}, code=${code}, signal=${signal}`);
      } catch (_) {}
    },
    onError: err => {
      try {
        Logger.error(`❌ subtitleVttWorker error hash=${hash}`, err);
      } catch (_) {}
    },
    onMessage: message => {
      try {
        if (!message || message.type !== 'subtitleVtt:done') return;
        const data = message.data && typeof message.data === 'object' ? message.data : {};
        const doneHash = _normalizeText(data.fileHash);
        if (!doneHash) return;
        const ids = _pendingByHash.get(doneHash);
        if (!ids || ids.size === 0) return;
        _pendingByHash.delete(doneHash);
        for (const id of ids) {
          const w = _pendingById.get(id);
          if (!w) continue;
          _pendingById.delete(id);
          w.send({ type: 'subtitleVtt:result', data: { id, ...data } });
        }
      } catch (e) {
        try {
          Logger.error('[subtitleVtt] forward result failed', e);
        } catch (_) {}
      }
    },
  });
}

async function subtitleVttGenerate({ expressWorker, singletonWorkerManager, initUtil, Logger, message }) {
  const data = message && message.data && typeof message.data === 'object' ? message.data : {};
  const id = _normalizeText(data.id);
  const filePath = _normalizeText(data.filePath);
  const providedHash = _normalizeText(data.fileHash);
  const subtitleCodecs = Array.isArray(data.subtitleCodecs) ? data.subtitleCodecs : null;
  const subtitleIndexRaw = data.subtitleIndex;
  const subtitleIndex = Number.isFinite(Number(subtitleIndexRaw)) ? Math.floor(Number(subtitleIndexRaw)) : null;
  if (!id || !filePath || subtitleIndex == null || subtitleIndex < 0) return;

  const resolved = path.resolve(filePath);
  const fileHash = providedHash || (await FileUtil.getFileHash(resolved).catch(() => null));
  const hash = _normalizeText(fileHash);
  if (!hash) {
    expressWorker.send({
      type: 'subtitleVtt:result',
      data: { id, ok: false, code: 'HASH_FAILED', message: 'hash failed' },
    });
    return;
  }

  _pendingById.set(id, expressWorker);
  const set = _pendingByHash.get(hash) || new Set();
  set.add(id);
  _pendingByHash.set(hash, set);

  // If worker already running for this hash, just wait.
  if (singletonWorkerManager.isWorkerRunning(`subtitleVtt_${hash}`)) return;

  const worker = _ensureWorker({ singletonWorkerManager, initUtil, Logger, fileHash: hash });
  if (!worker || typeof worker.send !== 'function') {
    _pendingById.delete(id);
    const cur = _pendingByHash.get(hash);
    if (cur) {
      cur.delete(id);
      if (cur.size === 0) _pendingByHash.delete(hash);
    }
    expressWorker.send({
      type: 'subtitleVtt:result',
      data: { id, ok: false, code: 'WORKER_NOT_READY', message: 'subtitle worker not ready' },
    });
    return;
  }

  try {
    worker.send({
      type: 'extractAll',
      data: { fileHash: hash, filePath: resolved, subtitleCodecs },
    });
  } catch (e) {
    _pendingById.delete(id);
    const cur = _pendingByHash.get(hash);
    if (cur) {
      cur.delete(id);
      if (cur.size === 0) _pendingByHash.delete(hash);
    }
    expressWorker.send({
      type: 'subtitleVtt:result',
      data: { id, ok: false, code: 'WORKER_SEND_FAILED', message: e && e.message ? e.message : String(e) },
    });
  }
}

module.exports = {
  'subtitleVtt:generate': subtitleVttGenerate,
};

