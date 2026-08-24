const ResponseUtil = require('../../../apiUtils/responseUtil');
const apiConfig = require('../../../../config/apiConfig');
const tableConfig = require('../../../../db/table/tableConfig');
const nascabAccountUtil = require('../utils/nascabAccountUtil');

function _safeBool(v) {
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

function normalizeDdnsDomain(v) {
  return v == null ? '' : String(v).trim().toLowerCase();
}

function getDdnsBaseUrlByType(ddnsType, apiConfig) {
  const t = normalizeDdnsType(ddnsType);
  if (t === 'ipv6') return apiConfig.apiDdnsIpv6BaseUrl || apiConfig.apiP2pBaseUrl;
  return apiConfig.apiDdnsIpv4BaseUrl || apiConfig.apiP2pBaseUrl;
}

function isNasCabLoggedInByToken(token) {
  return nascabAccountUtil.isValidJwtFormat(token);
}

async function getLocalDdnsConfig(knex) {
  const enabledRaw = await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_ENABLED).catch(() => '0');
  const ddnsType = (await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_TYPE).catch(() => '')) || '';
  const ddnsDomain = (await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_DOMAIN).catch(() => '')) || '';
  const ddnsBase = (await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_BASE).catch(() => '')) || '';
  const lastIp = (await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_LAST_IP).catch(() => '')) || '';
  const lastTime = (await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_LAST_TIME).catch(() => '')) || '';
  const lastError = (await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_LAST_ERROR).catch(() => '')) || '';
  const deviceId = (await nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, 'p2p_device_id').catch(() => '')) || '';
  return {
    enabled: _safeBool(enabledRaw),
    ddnsType: normalizeDdnsType(ddnsType),
    ddnsDomain: normalizeDdnsDomain(ddnsDomain),
    ddnsBase: String(ddnsBase || '').trim(),
    ddnsLastIp: String(lastIp || '').trim(),
    ddnsLastTime: String(lastTime || '').trim(),
    ddnsLastError: String(lastError || '').trim(),
    deviceId: String(deviceId || '').trim(),
  };
}

async function saveLocalDdnsConfig(updates) {
  const pairs = Object.entries(updates || {}).filter(([k]) => typeof k === 'string' && k);
  if (!pairs.length) return;
  for (const [key, value] of pairs) {
    await tableConfig.setConfigByKey(key, value == null ? null : String(value)).catch(() => {});
  }
}

async function stopDdnsWorkerIfRunning() {
  try {
    if (typeof process.send === 'function') {
      process.send({ type: 'setDdnsEnabled', data: { enabled: false } });
    }
  } catch (_) {}
}

async function clearDdnsError() {
  await saveLocalDdnsConfig({ [tableConfig.KEY_DDNS_LAST_ERROR]: '' });
}

async function setDdnsErrorAndStop(errorCode) {
  await saveLocalDdnsConfig({
    [tableConfig.KEY_DDNS_LAST_ERROR]: errorCode || 'common.ERROR',
    [tableConfig.KEY_DDNS_ENABLED]: '0',
  });
  await stopDdnsWorkerIfRunning();
}

async function ensureLoggedIn(req) {
  const token = await nascabAccountUtil.getStoredAccessToken(req.dbMain, tableConfig);
  return { token: token || '', loggedIn: isNasCabLoggedInByToken(token || '') };
}

module.exports = {
  async getStatus(req, res) {
    const local = await getLocalDdnsConfig(req.dbMain).catch(() => null);
    if (!local) return ResponseUtil.error(req, res, 'service.DB_CONNECTION_FAILED', 500);

    const { loggedIn } = await ensureLoggedIn(req);
    if (!loggedIn) {
      if (local.enabled) {
        await setDdnsErrorAndStop('service.NASCAB_LOGIN_REQUIRED').catch(() => {});
      }
      return ResponseUtil.success(req, res, {
        ...local,
        enabled: false,
      }, 'common.SUCCESS', 200);
    }

    if (local.enabled) {
      try {
        if (typeof process.send === 'function') {
          process.send({ type: 'ensureDdnsWorker' });
        }
      } catch (_) {}
    }

    let remoteStatus = null;
    let remoteIp = null;
    let remoteErrorCode = '';
    const ddnsIpBase = getDdnsBaseUrlByType(local.ddnsType, apiConfig);
    const r2 = await nascabAccountUtil.remoteRequestWithAutoRefresh(req.dbMain, tableConfig, apiConfig, {
      url: `${ddnsIpBase}/api/ddns/ip`,
      method: 'GET',
    });
    if (r2.ok && r2.status === 200 && r2.json && Number(r2.json.code) === 0) {
      remoteIp = r2.json.data || null;
    }

    if (!local.deviceId) {
      remoteErrorCode = 'P2P.ERR_DEVICE_NOT_BIND';
    } else {
      const r1 = await nascabAccountUtil.remoteRequestWithAutoRefresh(req.dbMain, tableConfig, apiConfig, {
        url: apiConfig.apiDdnsStatusPath,
        method: 'GET',
        params: { deviceId: local.deviceId },
      });
      if (!r1.ok && r1.expired) {
        await setDdnsErrorAndStop('service.NASCAB_SESSION_EXPIRED').catch(() => {});
        return ResponseUtil.success(req, res, { ...local, enabled: false }, 'common.SUCCESS', 200);
      }
      if (r1.ok && r1.status === 200 && r1.json && Number(r1.json.code) === 0) {
        remoteStatus = r1.json.data || null;
      } else {
        const data = r1.json && r1.json.data ? r1.json.data : null;
        remoteErrorCode = data && data.errorCode ? String(data.errorCode) : '';
      }
    }

    if (remoteErrorCode === 'P2P.ERR_DEVICE_NOT_BIND' || remoteErrorCode === 'P2P.ERR_NEED_VIP') {
      if (local.enabled) {
        await setDdnsErrorAndStop(remoteErrorCode).catch(() => {});
      } else {
        await saveLocalDdnsConfig({ [tableConfig.KEY_DDNS_LAST_ERROR]: remoteErrorCode }).catch(() => {});
      }
    } else if (remoteErrorCode) {
      await saveLocalDdnsConfig({ [tableConfig.KEY_DDNS_LAST_ERROR]: remoteErrorCode }).catch(() => {});
    }

    if (remoteStatus && typeof remoteStatus === 'object') {
      const ddnsType = normalizeDdnsType(remoteStatus.ddnsType);
      const ddnsDomain = normalizeDdnsDomain(remoteStatus.ddnsDomain);
      const ddnsBase = remoteStatus.ddnsBase ? String(remoteStatus.ddnsBase).trim() : '';
      const ddnsLastIp = remoteStatus.ddnsIp ? String(remoteStatus.ddnsIp).trim() : '';
      const ddnsLastTime = remoteStatus.ddnsLastTime ? String(remoteStatus.ddnsLastTime) : '';
      await saveLocalDdnsConfig({
        [tableConfig.KEY_DDNS_TYPE]: ddnsType,
        [tableConfig.KEY_DDNS_DOMAIN]: ddnsDomain,
        [tableConfig.KEY_DDNS_BASE]: ddnsBase,
        [tableConfig.KEY_DDNS_LAST_IP]: ddnsLastIp,
        ...(ddnsLastTime ? { [tableConfig.KEY_DDNS_LAST_TIME]: ddnsLastTime } : {}),
      }).catch(() => {});
      await clearDdnsError().catch(() => {});
    }

    const local2 = await getLocalDdnsConfig(req.dbMain).catch(() => local);
    const ddnsFullDomain = local2.ddnsDomain && local2.ddnsBase ? `${local2.ddnsDomain}.${local2.ddnsBase}` : '';
    const publicIp = remoteIp && remoteIp.ip ? String(remoteIp.ip) : '';
    return ResponseUtil.success(req, res, {
      ...local2,
      ddnsFullDomain,
      publicIp,
      loggedIn: true,
    }, 'common.SUCCESS', 200);
  },

  async setDomain(req, res) {
    const { loggedIn } = await ensureLoggedIn(req);
    if (!loggedIn) return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);

    const ddnsDomain = normalizeDdnsDomain(req.body && (req.body.ddnsDomain || req.body.domain));
    if (!ddnsDomain) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

    const deviceId = await nascabAccountUtil.getDecryptedConfigValue(req.dbMain, tableConfig, 'p2p_device_id').catch(() => '');
    const did = deviceId ? String(deviceId).trim() : '';
    if (!did) return ResponseUtil.error(req, res, 'P2P.ERR_DEVICE_NOT_BIND', 403);
    const currentTypeRaw = await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_TYPE).catch(() => '');
    const ddnsCallBase = getDdnsBaseUrlByType(currentTypeRaw, apiConfig);
    const remote = await nascabAccountUtil.remoteRequestWithAutoRefresh(req.dbMain, tableConfig, apiConfig, {
      url: `${ddnsCallBase}/api/ddns/domain`,
      method: 'POST',
      data: { deviceId: did, ddnsDomain },
    });
    console.log("调用设置DDN域名",`${ddnsCallBase}/api/ddns/domain`,ddnsDomain,deviceId)
    console.log("remote",remote)
    if (!remote.ok && remote.expired) {
      await setDdnsErrorAndStop('service.NASCAB_SESSION_EXPIRED').catch(() => {});
      return ResponseUtil.error(req, res, 'service.NASCAB_SESSION_EXPIRED', 200);
    }
    if (!remote.ok) return ResponseUtil.error(req, res, 'service.NETWORK_ERROR', 502);

    const code = remote.json && remote.json.code;
    const data = remote.json && remote.json.data ? remote.json.data : null;
    if (remote.status !== 200 || Number(code) !== 0 || !data) {
      const errorCode = data && data.errorCode ? String(data.errorCode) : '';
      if (errorCode) {
        if (errorCode === 'P2P.ERR_DEVICE_NOT_BIND' || errorCode === 'P2P.ERR_NEED_VIP') {
          await setDdnsErrorAndStop(errorCode).catch(() => {});
        } else {
          await saveLocalDdnsConfig({ [tableConfig.KEY_DDNS_LAST_ERROR]: errorCode }).catch(() => {});
        }
        return ResponseUtil.error(req, res, errorCode, remote.status || 400);
      }
      return ResponseUtil.error(req, res, 'common.ERROR', remote.status || 500);
    }

    const ddnsBase = data.ddnsBase ? String(data.ddnsBase).trim() : '';
    const appliedErrorCode = data.errorCode ? String(data.errorCode).trim() : '';
    const applied = data.applied === true;
    const ddnsIp = data.ddnsIp ? String(data.ddnsIp).trim() : '';
    const ddnsLastTime = applied && ddnsIp ? new Date().toISOString() : '';
    await saveLocalDdnsConfig({
      [tableConfig.KEY_DDNS_DOMAIN]: ddnsDomain,
      ...(ddnsBase ? { [tableConfig.KEY_DDNS_BASE]: ddnsBase } : {}),
      [tableConfig.KEY_DDNS_LAST_IP]: applied && ddnsIp ? ddnsIp : '',
      [tableConfig.KEY_DDNS_LAST_TIME]: ddnsLastTime,
      [tableConfig.KEY_DDNS_LAST_ERROR]: appliedErrorCode,
    }).catch(() => {});

    const ddnsFullDomain = ddnsDomain && ddnsBase ? `${ddnsDomain}.${ddnsBase}` : '';
    return ResponseUtil.success(req, res, {
      ddnsDomain,
      ddnsBase,
      ddnsFullDomain,
      ...(applied && ddnsIp ? { ddnsIp, ddnsLastTime } : {}),
      ...(appliedErrorCode ? { errorCode: appliedErrorCode } : {}),
    }, 'common.SUCCESS', 200);
  },

  async setType(req, res) {
    const { loggedIn } = await ensureLoggedIn(req);
    if (!loggedIn) return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);

    const ddnsType = normalizeDdnsType(req.body && req.body.ddnsType);
    if (!ddnsType) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

    const deviceId = await nascabAccountUtil.getDecryptedConfigValue(req.dbMain, tableConfig, 'p2p_device_id').catch(() => '');
    const did = deviceId ? String(deviceId).trim() : '';
    if (!did) return ResponseUtil.error(req, res, 'P2P.ERR_DEVICE_NOT_BIND', 403);

    const ddnsCallBase = getDdnsBaseUrlByType(ddnsType, apiConfig);
    const remote = await nascabAccountUtil.remoteRequestWithAutoRefresh(req.dbMain, tableConfig, apiConfig, {
      url: `${ddnsCallBase}/api/ddns/type`,
      method: 'POST',
      data: { deviceId: did, ddnsType },
    });
    if (!remote.ok && remote.expired) {
      await setDdnsErrorAndStop('service.NASCAB_SESSION_EXPIRED').catch(() => {});
      return ResponseUtil.error(req, res, 'service.NASCAB_SESSION_EXPIRED', 200);
    }
    if (!remote.ok) return ResponseUtil.error(req, res, 'service.NETWORK_ERROR', 502);

    const code = remote.json && remote.json.code;
    const data = remote.json && remote.json.data ? remote.json.data : null;
    if (remote.status !== 200 || Number(code) !== 0 || !data) {
      const errorCode = data && data.errorCode ? String(data.errorCode) : '';
      if (errorCode) {
        if (errorCode === 'P2P.ERR_DEVICE_NOT_BIND' || errorCode === 'P2P.ERR_NEED_VIP') {
          await setDdnsErrorAndStop(errorCode).catch(() => {});
        } else {
          await saveLocalDdnsConfig({ [tableConfig.KEY_DDNS_LAST_ERROR]: errorCode }).catch(() => {});
        }
        return ResponseUtil.error(req, res, errorCode, remote.status || 400);
      }
      return ResponseUtil.error(req, res, 'common.ERROR', remote.status || 500);
    }

    const appliedErrorCode = data.errorCode ? String(data.errorCode).trim() : '';
    const applied = data.applied === true;
    const ddnsIp = data.ddnsIp ? String(data.ddnsIp).trim() : '';
    const ddnsLastTime = applied && ddnsIp ? new Date().toISOString() : '';
    await saveLocalDdnsConfig({
      [tableConfig.KEY_DDNS_TYPE]: ddnsType,
      [tableConfig.KEY_DDNS_LAST_IP]: applied && ddnsIp ? ddnsIp : '',
      [tableConfig.KEY_DDNS_LAST_TIME]: ddnsLastTime,
      [tableConfig.KEY_DDNS_LAST_ERROR]: appliedErrorCode,
    }).catch(() => {});

    return ResponseUtil.success(req, res, {
      ddnsType,
      ...(applied && ddnsIp ? { ddnsIp, ddnsLastTime } : {}),
      ...(appliedErrorCode ? { errorCode: appliedErrorCode } : {}),
    }, 'common.SUCCESS', 200);
  },

  async setEnabled(req, res) {
    const enabled = req.body && typeof req.body.enabled === 'boolean' ? req.body.enabled : null;
    if (enabled === null) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

    let local = null;
    if (enabled === true) {
      local = await getLocalDdnsConfig(req.dbMain).catch(() => null);
      if (!local) return ResponseUtil.error(req, res, 'service.DB_CONNECTION_FAILED', 500);
      const { loggedIn } = await ensureLoggedIn(req);
      if (!loggedIn) return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
      if (!local.deviceId) return ResponseUtil.error(req, res, 'P2P.ERR_DEVICE_NOT_BIND', 403);
      if (!local.ddnsDomain || !local.ddnsType) return ResponseUtil.error(req, res, 'DDNS_NOT_CONFIGURED', 400);
    }

    await saveLocalDdnsConfig({
      [tableConfig.KEY_DDNS_ENABLED]: enabled ? '1' : '0',
      ...(enabled ? { [tableConfig.KEY_DDNS_LAST_ERROR]: '' } : {}),
    }).catch(() => {});

    try {
      if (typeof process.send === 'function') {
        process.send({ type: 'setDdnsEnabled', data: { enabled } });
        if (enabled) process.send({ type: 'ensureDdnsWorker' });
      }
    } catch (_) {}

    if (enabled !== true) {
      return ResponseUtil.success(req, res, { enabled }, 'common.SUCCESS', 200);
    }

    local = local || (await getLocalDdnsConfig(req.dbMain).catch(() => null));
    if (!local || !local.deviceId) {
      return ResponseUtil.success(req, res, { enabled }, 'common.SUCCESS', 200);
    }

    const remote = await nascabAccountUtil.remoteRequestWithAutoRefresh(req.dbMain, tableConfig, apiConfig, {
      url: apiConfig.apiDdnsUpdatePath,
      method: 'POST',
      data: { deviceId: local.deviceId },
    });
    if (!remote.ok && remote.expired) {
      await setDdnsErrorAndStop('service.NASCAB_SESSION_EXPIRED').catch(() => {});
      return ResponseUtil.success(req, res, { enabled: false }, 'common.SUCCESS', 200);
    }
    if (!remote.ok) {
      await saveLocalDdnsConfig({ [tableConfig.KEY_DDNS_LAST_ERROR]: 'service.NETWORK_ERROR' }).catch(() => {});
      return ResponseUtil.success(req, res, { enabled }, 'common.SUCCESS', 200);
    }

    const code = remote.json && remote.json.code !== undefined ? Number(remote.json.code) : -1;
    const data = remote.json && remote.json.data ? remote.json.data : null;
    if (remote.status !== 200 || code !== 0 || !data) {
      const errorCode = data && data.errorCode ? String(data.errorCode) : '';
      if (errorCode === 'P2P.ERR_DEVICE_NOT_BIND' || errorCode === 'P2P.ERR_NEED_VIP') {
        await setDdnsErrorAndStop(errorCode).catch(() => {});
        return ResponseUtil.success(req, res, { enabled: false, errorCode }, 'common.SUCCESS', 200);
      }
      await saveLocalDdnsConfig({ [tableConfig.KEY_DDNS_LAST_ERROR]: errorCode || 'common.ERROR' }).catch(() => {});
      return ResponseUtil.success(req, res, { enabled, ...(errorCode ? { errorCode } : {}) }, 'common.SUCCESS', 200);
    }

    const ddnsIp = data.ddnsIp ? String(data.ddnsIp).trim() : '';
    const ddnsLastTime = data.ddnsLastTime ? String(data.ddnsLastTime) : new Date().toISOString();
    await saveLocalDdnsConfig({
      [tableConfig.KEY_DDNS_LAST_IP]: ddnsIp,
      [tableConfig.KEY_DDNS_LAST_TIME]: ddnsLastTime,
      [tableConfig.KEY_DDNS_LAST_ERROR]: '',
    }).catch(() => {});

    return ResponseUtil.success(req, res, { enabled, ddnsIp, ddnsLastTime }, 'common.SUCCESS', 200);
  }
};
