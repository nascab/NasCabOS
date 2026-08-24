const Logger = require('../../utils/logger');
const apiConfig = require('../../config/apiConfig');
const tableConfig = require('../../db/table/tableConfig');
const nascabAccountUtil = require('../../api/modules/service/utils/nascabAccountUtil');
const configStore = require('./utils/configStore');

function isWorkerDebugEnabled() {
  const v = process.env.DDNS_WORKER_DEBUG;
  return v === '1' || v === 'true';
}

function logDebug(...args) {
  if (!isWorkerDebugEnabled()) return;
  console.log('[ddns][worker]', ...args);
}

function safeBool(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v === 1;
  const s = v === undefined || v === null ? '' : String(v).trim().toLowerCase();
  return s === '1' || s === 'true' || s === 'yes' || s === 'on';
}

function normalizeDdnsType(v) {
  const s = v == null ? '' : String(v).trim().toLowerCase();
  if (s === 'ipv4') return 'ipv4';
  if (s === 'ipv6') return 'ipv6';
  return '';
}

async function getConfigByKeyOrDefault(key, fallback = '') {
  try {
    const value = await tableConfig.getConfigByKey(key);
    return value == null ? fallback : value;
  } catch (_) {
    return fallback;
  }
}

async function getLocalDdnsStatusFromDb() {
  const enabledRaw = await getConfigByKeyOrDefault(tableConfig.KEY_DDNS_ENABLED, '0');
  const ddnsType = await getConfigByKeyOrDefault(tableConfig.KEY_DDNS_TYPE, '');
  const ddnsDomain = await getConfigByKeyOrDefault(tableConfig.KEY_DDNS_DOMAIN, '');
  const ddnsBase = await getConfigByKeyOrDefault(tableConfig.KEY_DDNS_BASE, '');
  const ddnsLastIp = await getConfigByKeyOrDefault(tableConfig.KEY_DDNS_LAST_IP, '');
  const ddnsLastTime = await getConfigByKeyOrDefault(tableConfig.KEY_DDNS_LAST_TIME, '');
  const ddnsLastError = await getConfigByKeyOrDefault(tableConfig.KEY_DDNS_LAST_ERROR, '');
  return {
    enabled: safeBool(enabledRaw),
    ddnsType: normalizeDdnsType(ddnsType),
    ddnsDomain: ddnsDomain ? String(ddnsDomain).trim().toLowerCase() : '',
    ddnsBase: ddnsBase ? String(ddnsBase).trim() : '',
    ddnsLastIp: ddnsLastIp ? String(ddnsLastIp).trim() : '',
    ddnsLastTime: ddnsLastTime ? String(ddnsLastTime).trim() : '',
    ddnsLastError: ddnsLastError ? String(ddnsLastError).trim() : '',
  };
}

function getDdnsBaseUrlByFamily(family) {
  if (family === 6) return apiConfig.apiDdnsIpv6BaseUrl || apiConfig.apiP2pBaseUrl;
  return apiConfig.apiDdnsIpv4BaseUrl || apiConfig.apiP2pBaseUrl;
}

async function fetchPublicIp({ knex, family }) {
  const base = getDdnsBaseUrlByFamily(family);
  const url = `${base}/api/ddns/ip`;
  const r = await nascabAccountUtil.remoteRequestWithAutoRefresh(knex, tableConfig, apiConfig, {
    method: 'GET',
    url,
  });
  logDebug('fetchPublicIp', { url, family, ok: !!(r && r.ok), status: r && r.status, expired: !!(r && r.expired) });
  return r;
}

async function updateRemoteDdns({ knex, deviceId, family }) {
  const base = getDdnsBaseUrlByFamily(family);
  const url = `${base}/api/ddns/update`;
  const r = await nascabAccountUtil.remoteRequestWithAutoRefresh(knex, tableConfig, apiConfig, {
    method: 'POST',
    url,
    data: { deviceId },
  });
  return r;
}

class DdnsWorker {
  constructor() {
    this.stopping = false;
    this.timer = null;
  }

  async tick() {
    console.log("-------ddns tick-------")
    if (this.stopping) return;
    try {
      await configStore.initDb();
      const knex = configStore.getKnex();
      if (!knex) return;

      const enabledRaw = await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_ENABLED).catch(() => '0');
      const enabled = safeBool(enabledRaw);
      if (!enabled) {
        logDebug('disabled -> exit');
        this.stop();
        process.exit(0);
        return;
      }

      const deviceId = ((await configStore.getConfigValue('p2p_device_id')) || '').trim();
      if (!deviceId) {
        logDebug('device not bound -> stop', { error: 'P2P.ERR_DEVICE_NOT_BIND' });
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, 'P2P.ERR_DEVICE_NOT_BIND').catch(() => {});
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_ENABLED, '0').catch(() => {});
        this.stop();
        process.exit(0);
        return;
      }

      const ddnsType = normalizeDdnsType(await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_TYPE).catch(() => ''));
      const ddnsDomain = ((await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_DOMAIN).catch(() => '')) || '').trim();
      if (!ddnsType || !ddnsDomain) {
        logDebug('not configured -> stop', { ddnsType, hasDomain: !!ddnsDomain });
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, 'DDNS_NOT_CONFIGURED').catch(() => {});
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_ENABLED, '0').catch(() => {});
        this.stop();
        process.exit(0);
        return;
      }

      const family = ddnsType === 'ipv6' ? 6 : 4;

      const ensured = await nascabAccountUtil.ensureNasCabAccessToken(knex, tableConfig, apiConfig);
      if (!ensured || !nascabAccountUtil.isValidJwtFormat(ensured.token)) {
        logDebug('token missing/invalid -> stop');
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, 'service.NASCAB_LOGIN_REQUIRED').catch(() => {});
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_ENABLED, '0').catch(() => {});
        this.stop();
        process.exit(0);
        return;
      }

      const statusLocal = await getLocalDdnsStatusFromDb().catch(() => null);
      console.log('statusLocal', statusLocal);
      if (statusLocal) {
        const lastType = normalizeDdnsType(statusLocal.ddnsType);
        if (lastType && lastType !== ddnsType) {
          logDebug('type changed, sync local', { ddnsType, lastType });
          await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_TYPE, lastType).catch(() => {});
          await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_IP, '').catch(() => {});
          await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_TIME, '').catch(() => {});
          await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, '').catch(() => {});
          return;
        }
      }

      const ipRes = await fetchPublicIp({ knex, family });
      if (!ipRes.ok) {
        if (ipRes.expired || ipRes.status === 401) {
          console.log('DDNS session expired -> stop');
          await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, 'service.NASCAB_SESSION_EXPIRED').catch(() => {});
          await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_ENABLED, '0').catch(() => {});
          this.stop();
          process.exit(0);
          return;
        }
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, 'service.NETWORK_ERROR').catch(() => {});
        return;
      }

      const ipJson = ipRes.json;
      const ipData = ipJson && ipJson.data ? ipJson.data : null;
      const publicIp = ipData && ipData.ip ? String(ipData.ip).trim() : '';
      if (!publicIp) {
        console.log('public ip empty');
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, 'service.NETWORK_ERROR').catch(() => {});
        return;
      }

      const lastIp = ((await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_LAST_IP).catch(() => '')) || '').trim();
      console.log('lastIp', lastIp);
      console.log('publicIp', publicIp);
      if (lastIp && lastIp === publicIp) {
        logDebug('ip unchanged -> skip', { ip: publicIp });
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, '').catch(() => {});
        return;
      }
      console.log('ip changed -> update', { lastIp, publicIp, ddnsType, deviceId });
      const upd = await updateRemoteDdns({ knex, deviceId, family });
      console.log("upd",upd)
      if (!upd.ok) {
        if (upd.expired || upd.status === 401) {
          await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, 'service.NASCAB_SESSION_EXPIRED').catch(() => {});
          await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_ENABLED, '0').catch(() => {});
          this.stop();
          process.exit(0);
          return;
        }
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, 'service.NETWORK_ERROR').catch(() => {});
        return;
      }

      const json = upd.json;
      const code = json && json.code !== undefined ? Number(json.code) : -1;
      const data = json && json.data ? json.data : null;
      const errorCode = data && data.errorCode ? String(data.errorCode).trim() : '';

      if (upd.status === 403 && (errorCode === 'P2P.ERR_DEVICE_NOT_BIND' || errorCode === 'P2P.ERR_NEED_VIP')) {
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, errorCode).catch(() => {});
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_ENABLED, '0').catch(() => {});
        this.stop();
        process.exit(0);
        return;
      }

      if (upd.status !== 200 || code !== 0) {
        logDebug('update failed', { status: upd.status, code, errorCode });
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, errorCode || 'common.ERROR').catch(() => {});
        return;
      }

      const ddnsIp = data && data.ddnsIp ? String(data.ddnsIp).trim() : publicIp;
      const ddnsLastTime = data && data.ddnsLastTime ? String(data.ddnsLastTime) : new Date().toISOString();
      logDebug('update ok', { ddnsIp, ddnsLastTime });
      await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_IP, ddnsIp).catch(() => {});
      await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_TIME, ddnsLastTime).catch(() => {});
      await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, '').catch(() => {});
    } catch (e) {
      Logger.error('[DdnsWorker] tick error', e ? e.message : e);
      try {
        await tableConfig.setConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR, 'common.ERROR');
      } catch (_) {}
    }
  }

  start() {
    if (this.timer) return;
    this.stopping = false;
    this.timer = setInterval(() => this.tick(), 60 * 1000);
    this.tick();
  }

  stop() {
    this.stopping = true;
    if (this.timer) {
      try {
        clearInterval(this.timer);
      } catch (_) {}
      this.timer = null;
    }
  }
}

let worker = null;

process.on('message', (msg) => {
  if (!msg || typeof msg !== 'object') return;
  if (msg.type === 'start') {
    if (!worker) worker = new DdnsWorker();
    worker.start();
  } else if (msg.type === 'stop') {
    if (worker) worker.stop();
    worker = null;
  }
});

if (require.main === module) {
  if (!worker) worker = new DdnsWorker();
  worker.start();
}
