const tableConfig = require('../../../../db/table/tableConfig');
const ResponseUtil = require('../../../apiUtils/responseUtil');

const CONFIG_KEY_ENABLE = 'file_all_index_enabled';
const CONFIG_KEY_INTERVAL_HOURS = 'file_all_index_interval_hours';

function _safeBool(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v === 1;
  const s = v === undefined || v === null ? '' : String(v).trim().toLowerCase();
  return s === '1' || s === 'true' || s === 'yes' || s === 'on';
}

function _safeIntervalHours(v) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return 72;
  if (n <= 0) return 72;
  return n;
}

function _requestId() {
  return `${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function _sendToMain(type, data, timeoutMs = 10000) {
  if (typeof process.send !== 'function') {
    return Promise.resolve({ ok: false, error: 'process.send not available' });
  }

  const requestId = _requestId();
  return new Promise(resolve => {
    let done = false;
    let onMessage = null;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      if (onMessage) process.off('message', onMessage);
      resolve({ ok: false, timeout: true });
    }, timeoutMs);

    onMessage = msg => {
      if (!msg || !msg.type || !msg.data) return;
      if (msg.data.requestId !== requestId) return;
      if (msg.type !== `${type}Response`) return;

      if (done) return;
      done = true;
      clearTimeout(timer);
      process.off('message', onMessage);
      resolve(msg.data);
    };

    process.on('message', onMessage);
    try {
      process.send({ type, data: { ...data, requestId } });
    } catch (err) {
      clearTimeout(timer);
      process.off('message', onMessage);
      resolve({ ok: false, error: err && err.message ? String(err.message) : String(err) });
    }
  });
}

async function getIndexSettings(req, res) {
  const rawEnable = await tableConfig.getConfigByKey(CONFIG_KEY_ENABLE).catch(() => null);
  const rawInterval = await tableConfig.getConfigByKey(CONFIG_KEY_INTERVAL_HOURS).catch(() => null);

  const enabled = rawEnable === '1';
  const intervalHours = _safeIntervalHours(rawInterval);

  return ResponseUtil.success(
    req,
    res,
    {
      enabled,
      intervalHours,
    },
    'file.CONFIG_FETCH_SUCCESS',
    200
  );
}

async function setIndexSettings(req, res) {
  const enabled = _safeBool(req.body?.enabled);
  const intervalHours = _safeIntervalHours(req.body?.intervalHours);

  await tableConfig.setConfigByKey(CONFIG_KEY_ENABLE, enabled ? '1' : '0');
  await tableConfig.setConfigByKey(CONFIG_KEY_INTERVAL_HOURS, String(intervalHours));

  const resp = await _sendToMain('toggleFileAllIndexWorker', { enable: enabled, intervalHours });

  return ResponseUtil.success(
    req,
    res,
    {
      enabled,
      intervalHours,
      running: !!resp?.running,
    },
    'file.CONFIG_SAVE_SUCCESS',
    200
  );
}

async function resetIndex(req, res) {
  const resp = await _sendToMain('resetFileAllIndex', {});

  return ResponseUtil.success(
    req,
    res,
    {
      ok: !!resp?.ok,
      enabled: !!resp?.enabled,
      triggered: !!resp?.triggered,
    },
    'file.CONFIG_RESET_SUCCESS',
    200
  );
}

module.exports = {
  getIndexSettings,
  setIndexSettings,
  resetIndex,
};
