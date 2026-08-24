const axios = require('axios');
const nascabAccountUtil = require('../../../api/modules/service/utils/nascabAccountUtil');
const apiConfig = require('../../../config/apiConfig');
const { P2P_SERVERS_CACHE_TTL_MS, parseP2pServers, serializeP2pServers, pickReachablePreferredDomain, replaceUrlHost } = require('../../../utils/p2pNodeUtil');
const { buildDeviceInfo } = require('./net');
const { normalizeP2pWsUrl } = require('./ws');
const { KEY_REMOTE_TOKEN, KEY_P2P_DEVICE_ID, KEY_P2P_DEVICE_SECRET, KEY_P2P_DEVICE_TOKEN, KEY_P2P_WS_URL, KEY_P2P_PAIR_CODE, KEY_LAST_P2P_ERROR, KEY_P2P_FIX_NODE_DOMAIN, KEY_P2P_SERVERS_CACHE, KEY_P2P_SERVERS_CACHE_UPDATED_AT } = require('./constants');

function createDeviceManager({ configStore, signalingClient }) {
  let lastDeviceTokenUpdatedAt = 0;

  const saveP2pServersCache = async list => {
    await configStore.setConfigValue(KEY_P2P_SERVERS_CACHE, serializeP2pServers(list), { encrypt: false }).catch(() => {});
    await configStore.setConfigValue(KEY_P2P_SERVERS_CACHE_UPDATED_AT, String(Date.now()), { encrypt: false }).catch(() => {});
  };

  const ensureP2pServersCache = async userToken => {
    const token = userToken && nascabAccountUtil.isValidJwtFormat(userToken) ? String(userToken).trim() : '';
    if (!token) {
      const raw = await configStore.getConfigValue(KEY_P2P_SERVERS_CACHE);
      return parseP2pServers(raw);
    }
    const lastRaw = await configStore.getConfigValue(KEY_P2P_SERVERS_CACHE_UPDATED_AT);
    const lastAt = Number(lastRaw);
    if (Number.isFinite(lastAt) && Date.now() - lastAt < P2P_SERVERS_CACHE_TTL_MS) {
      const cached = await configStore.getConfigValue(KEY_P2P_SERVERS_CACHE);
      return parseP2pServers(cached);
    }
    try {
      const response = await axios.request({
        url: apiConfig.apiP2pServersListPath,
        method: 'GET',
        timeout: 8000,
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        validateStatus: () => true,
      });
      const json = response && response.data ? response.data : null;
      const list = parseP2pServers(json && json.data);
      if (response && response.status >= 200 && response.status < 300 && list.length) {
        await saveP2pServersCache(list);
        return list;
      }
    } catch (_) {}
    const cached = await configStore.getConfigValue(KEY_P2P_SERVERS_CACHE);
    return parseP2pServers(cached);
  };

  const resolvePreferredNodeDomain = async () => {
    const configured = await configStore.getConfigValue(KEY_P2P_FIX_NODE_DOMAIN);
    return await pickReachablePreferredDomain(configured);
  };

  const buildPreferredApiUrl = async rawUrl => {
    const preferredDomain = await resolvePreferredNodeDomain();
    return preferredDomain ? replaceUrlHost(rawUrl, preferredDomain) : rawUrl;
  };

  const normalizeAndSaveWsUrl = async wsUrl => {
    const normalized = normalizeP2pWsUrl(wsUrl ? String(wsUrl) : '');
    if (normalized) {
      await configStore.setConfigValue(KEY_P2P_WS_URL, normalized, { encrypt: true }).catch(() => {});
    }
    return normalized;
  };

  const ensurePairCodeSaved = async ({ serverId } = {}) => {
    await configStore.initDb();
    const existing = ((await configStore.getConfigValue(KEY_P2P_PAIR_CODE)) || '').trim();
    if (existing) return existing;

    const deviceId = ((await configStore.getConfigValue(KEY_P2P_DEVICE_ID)) || '').trim();
    const deviceSecret = ((await configStore.getConfigValue(KEY_P2P_DEVICE_SECRET)) || '').trim();
    if (deviceId && deviceSecret) {
      try {
        await deviceLogin({ deviceId, deviceSecret });
      } catch (_) {}
    }

    const afterLogin = ((await configStore.getConfigValue(KEY_P2P_PAIR_CODE)) || '').trim();
    if (afterLogin) return afterLogin;

    const userTokenEnc = await configStore.getConfigValue(KEY_REMOTE_TOKEN);
    const userToken = userTokenEnc && nascabAccountUtil.isValidJwtFormat(userTokenEnc) ? userTokenEnc : '';
    const sid = serverId == null ? '' : String(serverId).trim();
    if (userToken && sid) {
      await registerOrRecoverDevice({ userToken, serverId: sid });
    }

    return ((await configStore.getConfigValue(KEY_P2P_PAIR_CODE)) || '').trim();
  };

  const registerOrRecoverDevice = async ({ userToken, serverId }) => {
    await ensureP2pServersCache(userToken).catch(() => {});
    const deviceInfo = buildDeviceInfo(serverId);
    const r = await axios.request({
      url: await buildPreferredApiUrl(apiConfig.apiP2pDeviceRegisterPath),
      method: 'POST',
      timeout: 8000,
      headers: {
        Authorization: `Bearer ${userToken}`,
        'Content-Type': 'application/json',
      },
      data: {
        serverId,
        deviceName: deviceInfo.deviceName,
        platform: deviceInfo.platform,
        deviceInfo,
      },
      validateStatus: () => true,
    });
    const status = r ? r.status : 0;
    const json = r && r.data ? r.data : null;
    const code = json && json.code !== undefined ? Number(json.code) : 0;
    console.log('注册或恢复设备回复', r.data, code, status);

    const errorCode = json && json.data && json.data.errorCode ? String(json.data.errorCode) : '';
    const noRetryErrorCodes = ['P2P.ERR_DEVICE_NOT_BIND', 'P2P.ERR_NEED_VIP', 'P2P.ERR_DEVICE_COUNT_LIMIT'];
    if (errorCode && noRetryErrorCodes.includes(errorCode)) {
      await configStore.setConfigValue(KEY_LAST_P2P_ERROR, errorCode, { encrypt: false }).catch(() => {});
    }
    if (status === 403 || status === 401 || code == 403 || code == 401) {
      if (errorCode && !noRetryErrorCodes.includes(errorCode)) {
        await configStore.setConfigValue(KEY_LAST_P2P_ERROR, errorCode, { encrypt: false }).catch(() => {});
      }
      const msg = json && json.message ? String(json.message) : 'register_failed';
      const err = { code, message: msg };
      err.status = status;
      if (errorCode && noRetryErrorCodes.includes(errorCode)) err.errorCode = errorCode;
      console.log('注册或恢复设备失败', err);
      throw err;
    }
    if (!json || code !== 0 || !json.data) {
      const msg = json && json.message ? String(json.message) : 'register_failed';
      throw new Error(`${msg}${status ? ` (status=${status})` : ''}`);
    }

    const deviceId = json.data.deviceId ? String(json.data.deviceId) : '';
    const deviceSecret = json.data.deviceSecret ? String(json.data.deviceSecret) : '';
    await normalizeAndSaveWsUrl(json.data.wsUrl ? String(json.data.wsUrl) : '');
    const deviceToken = json.data.deviceToken ? String(json.data.deviceToken) : '';
    const pairCode = json.data.pairCode ? String(json.data.pairCode) : json.data.pair_code ? String(json.data.pair_code) : json.data.paircode ? String(json.data.paircode) : '';

    if (!deviceId) throw new Error('device_id_missing');
    await configStore.setConfigValue(KEY_P2P_DEVICE_ID, deviceId, { encrypt: true });
    if (deviceToken) await configStore.setConfigValue(KEY_P2P_DEVICE_TOKEN, deviceToken, { encrypt: true });
    if (deviceSecret) await configStore.setConfigValue(KEY_P2P_DEVICE_SECRET, deviceSecret, { encrypt: true });
    if (pairCode) await configStore.setConfigValue(KEY_P2P_PAIR_CODE, pairCode, { encrypt: true });

    await configStore.clearConfigValue(KEY_LAST_P2P_ERROR).catch(() => {});

    if (!deviceSecret) {
      const existingSecret = await configStore.getConfigValue(KEY_P2P_DEVICE_SECRET);
      if (!existingSecret) {
        const s = await rotateDeviceSecret({ userToken, serverId });
        if (s) await configStore.setConfigValue(KEY_P2P_DEVICE_SECRET, s, { encrypt: true });
      }
    }
  };

  const rotateDeviceSecret = async ({ userToken, serverId }) => {
    const r = await axios.request({
      url: await buildPreferredApiUrl(apiConfig.apiP2pDeviceSecretRotatePath),
      method: 'POST',
      timeout: 8000,
      headers: {
        Authorization: `Bearer ${userToken}`,
        'Content-Type': 'application/json',
      },
      data: { serverId },
      validateStatus: () => true,
    });
    const json = r && r.data ? r.data : null;
    if (!json || json.code !== 0 || !json.data) return null;
    const deviceSecret = json.data.deviceSecret ? String(json.data.deviceSecret) : '';
    const deviceId = json.data.deviceId ? String(json.data.deviceId) : '';
    if (deviceId) await configStore.setConfigValue(KEY_P2P_DEVICE_ID, deviceId, { encrypt: true });
    if (deviceSecret) return deviceSecret;
    return null;
  };

  const deviceLogin = async ({ deviceId, deviceSecret }) => {
    const r = await axios.request({
      url: await buildPreferredApiUrl(apiConfig.apiP2pDeviceLoginPath),
      method: 'POST',
      timeout: 8000,
      headers: { 'Content-Type': 'application/json' },
      data: { deviceId, deviceSecret },
      validateStatus: () => true,
    });
    const json = r && r.data ? r.data : null;
    const status = r ? r.status : 0;
    const code = json && json.code !== undefined ? Number(json.code) : 0;
    if (status === 403 || code === 403) {
      const errorCode = json && json.data && json.data.errorCode ? String(json.data.errorCode) : '';
      if (errorCode) {
        await configStore.setConfigValue(KEY_LAST_P2P_ERROR, errorCode, { encrypt: false }).catch(() => {});
      }
      const err = new Error(json && json.message ? String(json.message) : 'device_login_failed');
      err.status = status;
      err.code = code;
      err.needReregister = false;
      const noRetryErrorCodes = ['P2P.ERR_DEVICE_NOT_BIND', 'P2P.ERR_NEED_VIP', 'P2P.ERR_DEVICE_COUNT_LIMIT'];
      if (errorCode && noRetryErrorCodes.includes(errorCode)) err.errorCode = errorCode;
      throw err;
    }
    if (!json || code !== 0 || !json.data) {
      const err = new Error(json && json.message ? String(json.message) : 'device_login_failed');
      err.status = status;
      err.code = code;
      err.needReregister = status === 401 || code === 401;
      throw err;
    }
    await configStore.clearConfigValue(KEY_LAST_P2P_ERROR).catch(() => {});

    const deviceToken = json.data.deviceToken ? String(json.data.deviceToken) : '';
    const wsUrl = await normalizeAndSaveWsUrl(json.data.wsUrl ? String(json.data.wsUrl) : '');
    const pairCode = json.data.pairCode ? String(json.data.pairCode) : '';
    if (deviceToken) {
      await configStore.setConfigValue(KEY_P2P_DEVICE_TOKEN, deviceToken, { encrypt: true });
      lastDeviceTokenUpdatedAt = Date.now();
    }
    if (pairCode) await configStore.setConfigValue(KEY_P2P_PAIR_CODE, pairCode, { encrypt: true });
    return { deviceToken, wsUrl };
  };

  const refreshDeviceToken = async deviceToken => {
    const r = await axios.request({
      url: await buildPreferredApiUrl(apiConfig.apiP2pDeviceTokenRefreshPath),
      method: 'POST',
      timeout: 8000,
      headers: {
        Authorization: `Bearer ${deviceToken}`,
        'Content-Type': 'application/json',
      },
      data: {},
      validateStatus: () => true,
    });
    const json = r && r.data ? r.data : null;
    if (!json || json.code !== 0 || !json.data) throw new Error('device_token_refresh_failed');
    const next = json.data.deviceToken ? String(json.data.deviceToken) : '';
    if (!next) throw new Error('device_token_refresh_failed');
    await configStore.setConfigValue(KEY_P2P_DEVICE_TOKEN, next, { encrypt: true });
    lastDeviceTokenUpdatedAt = Date.now();
    return next;
  };

  const heartbeat = async (deviceToken, serverId) => {
    const deviceInfo = buildDeviceInfo(serverId);
    const r = await axios.request({
      url: await buildPreferredApiUrl(apiConfig.apiP2pDeviceHeartbeatPath),
      method: 'POST',
      timeout: 8000,
      headers: {
        Authorization: `Bearer ${deviceToken}`,
        'Content-Type': 'application/json',
      },
      data: { deviceInfo },
      validateStatus: () => true,
    });
    const status = r ? r.status : 0;
    if (status === 401 || status === 403) return { ok: false, auth: false };
    if (status < 200 || status >= 300) return { ok: false, auth: true };
    const json = r && r.data ? r.data : null;
    if (!json || json.code !== 0) return { ok: false, auth: true };
    return { ok: true, auth: true };
  };

  const clearLocalDeviceCredentials = async () => {
    await configStore.clearConfigValue(KEY_P2P_DEVICE_ID).catch(() => {});
    await configStore.clearConfigValue(KEY_P2P_DEVICE_SECRET).catch(() => {});
    await configStore.clearConfigValue(KEY_P2P_DEVICE_TOKEN).catch(() => {});
  };

  const ensureDeviceReady = async ({ serverId }, _retriedAfter401 = false) => {
    const userTokenEnc = await configStore.getConfigValue(KEY_REMOTE_TOKEN);
    const userToken = userTokenEnc && nascabAccountUtil.isValidJwtFormat(userTokenEnc) ? userTokenEnc : '';
    if (userToken) {
      await ensureP2pServersCache(userToken).catch(() => {});
    }
    const deviceId = (await configStore.getConfigValue(KEY_P2P_DEVICE_ID)) || '';
    const deviceSecret = (await configStore.getConfigValue(KEY_P2P_DEVICE_SECRET)) || '';
    let deviceToken = (await configStore.getConfigValue(KEY_P2P_DEVICE_TOKEN)) || '';
    const storedWsUrl = (await configStore.getConfigValue(KEY_P2P_WS_URL)) || '';
    let wsUrl = normalizeP2pWsUrl(storedWsUrl);
    const preferredDomain = await resolvePreferredNodeDomain();
    if (preferredDomain) {
      wsUrl = replaceUrlHost(wsUrl, preferredDomain);
    }
    if (wsUrl && wsUrl !== storedWsUrl) {
      await configStore.setConfigValue(KEY_P2P_WS_URL, wsUrl, { encrypt: true }).catch(() => {});
    }

    if (deviceId && deviceSecret && (!deviceToken || !nascabAccountUtil.isValidJwtFormat(deviceToken))) {
      try {
        console.log('[P2pConnectWorker] attempting device login...');
        const loginRes = await deviceLogin({ deviceId, deviceSecret });
        deviceToken = loginRes.deviceToken;
        wsUrl = loginRes.wsUrl || wsUrl;
        console.log('[P2pConnectWorker] device login success');
      } catch (err) {
        const needReregister = err && (err.needReregister === true || err.status === 401 || err.code === 401);
        if (needReregister && !_retriedAfter401) {
          console.log('[P2pConnectWorker] device login 401 (device_id 与远端不一致)，清除本地凭证并重新注册设备');
          await clearLocalDeviceCredentials();
          const sid = serverId == null ? '' : String(serverId).trim();
          if (userToken && sid) {
            await registerOrRecoverDevice({ userToken, serverId: sid });
            return ensureDeviceReady({ serverId }, true);
          }
        }
        console.error('[P2pConnectWorker] device login failed', err ? err.message : err);
        throw err;
      }
    }

    const now = Date.now();
    if (deviceToken && nascabAccountUtil.isValidJwtFormat(deviceToken) && now - lastDeviceTokenUpdatedAt > 12 * 60 * 60 * 1000) {
      try {
        deviceToken = await refreshDeviceToken(deviceToken);
      } catch (err) {
        console.log('[P2pConnectWorker] refreshDeviceToken failed', err ? err.message : err);
        deviceToken = '';
        await configStore.clearConfigValue(KEY_P2P_DEVICE_TOKEN).catch(() => {});
      }
    }

    if (deviceToken && nascabAccountUtil.isValidJwtFormat(deviceToken) && wsUrl) {
      await signalingClient.ensureConnected({ wsUrl, deviceToken }).catch(() => {});
    }
  };

  return {
    ensurePairCodeSaved,
    registerOrRecoverDevice,
    rotateDeviceSecret,
    deviceLogin,
    refreshDeviceToken,
    heartbeat,
    ensureDeviceReady,
  };
}

module.exports = { createDeviceManager };
