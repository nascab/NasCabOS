const axios = require('axios');
const os = require('os');
const ResponseUtil = require('../../apiUtils/responseUtil');
const apiConfig = require('../../../config/apiConfig');
const tableConfig = require('../../../db/table/tableConfig');
const nascabAccountUtil = require('./utils/nascabAccountUtil');
const { P2P_SERVERS_CACHE_TTL_MS, normalizeNodeDomain, parseP2pServers } = require('../../../utils/p2pNodeUtil');

function readTokenFromReq(req) {
  const fromBody = req.body && (req.body.jwt ?? req.body.token) ? String(req.body.jwt ?? req.body.token) : '';
  if (fromBody.trim()) return fromBody.trim();
  const fromQuery = req.query && (req.query.jwt ?? req.query.token) ? String(req.query.jwt ?? req.query.token) : '';
  if (fromQuery.trim()) return fromQuery.trim();
  const auth = req.headers && req.headers.authorization ? String(req.headers.authorization) : '';
  const match = auth.match(/^\s*Bearer\s+(.+?)\s*$/i);
  if (match && match[1]) return match[1].trim();
  return '';
}

function readCodeFromReq(req) {
  const fromBody = req.body && req.body.code != null ? String(req.body.code).trim() : '';
  if (fromBody) return fromBody;
  const fromQuery = req.query && req.query.code != null ? String(req.query.code).trim() : '';
  return fromQuery || '';
}

function extractPairCode(v) {
  if (v === undefined || v === null) return '';
  const s = String(v).trim();
  return s ? s : '';
}

function buildDeviceInfo(serverId) {
  const sid = serverId == null ? '' : String(serverId);
  const hostname = os.hostname ? os.hostname() : '';
  return {
    serverId: sid,
    hostname,
    deviceName: hostname,
    platform: `${os.platform()}-${os.arch()}`,
    osPlatform: os.platform(),
    osRelease: os.release(),
    osArch: os.arch(),
    ts: Date.now(),
  };
}

async function isNasCabLoggedIn(req) {
  const token = await nascabAccountUtil.getStoredAccessToken(req.dbMain, tableConfig);
  if (token) return true;
  const refreshToken = await nascabAccountUtil.getStoredRefreshToken(req.dbMain, tableConfig);
  return !!refreshToken;
}

async function ensureP2pServersCacheFresh(knex) {
  const lastAt = await tableConfig.getP2pServersCacheUpdatedAt().catch(() => 0);
  if (Number.isFinite(lastAt) && Date.now() - lastAt < P2P_SERVERS_CACHE_TTL_MS) {
    return await tableConfig.getP2pServersCache().catch(() => []);
  }
  const remote = await nascabAccountUtil.remoteRequestWithAutoRefresh(knex, tableConfig, apiConfig, {
    url: apiConfig.apiP2pServersListPath,
    method: 'GET',
  });
  if (!remote.ok || remote.status < 200 || remote.status >= 300) {
    return await tableConfig.getP2pServersCache().catch(() => []);
  }
  const list = parseP2pServers(remote.json && remote.json.data);
  await tableConfig.setP2pServersCache(list).catch(() => {});
  await tableConfig.setP2pServersCacheUpdatedAt(Date.now()).catch(() => {});
  return list;
}

let processListRequestInFlight = false;
let lastProcessListSnapshot = [];

function cloneProcessListSnapshot(list) {
  if (!Array.isArray(list)) return [];
  return list.map(item => ({ ...item }));
}

class ServiceController {
  async getProcessList(req, res) {
    if (processListRequestInFlight) {
      return ResponseUtil.success(req, res, cloneProcessListSnapshot(lastProcessListSnapshot), 'common.SUCCESS', 200);
    }
    processListRequestInFlight = true;
    const requestId = `process_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const timeoutMs = 6000;
    try {
      return await new Promise(resolve => {
        let timeoutId = null;
        const onMessage = message => {
          if (!message || message.type !== 'getProcessListResponse') return;
          const data = message.data || {};
          if (String(data.requestId || '') !== requestId) return;
          clearTimeout(timeoutId);
          process.off('message', onMessage);
          const list = Array.isArray(data.list) ? data.list : [];
          lastProcessListSnapshot = list.map(item => ({ ...item }));
          resolve(ResponseUtil.success(req, res, list, 'common.SUCCESS', 200));
        };
        process.on('message', onMessage);
        timeoutId = setTimeout(() => {
          process.off('message', onMessage);
          resolve(ResponseUtil.success(req, res, cloneProcessListSnapshot(lastProcessListSnapshot), 'common.SUCCESS', 200));
        }, timeoutMs);
        try {
          if (typeof process.send === 'function') {
            process.send({ type: 'getProcessList', data: { requestId } });
            return;
          }
        } catch (_) {}
        clearTimeout(timeoutId);
        process.off('message', onMessage);
        resolve(ResponseUtil.success(req, res, cloneProcessListSnapshot(lastProcessListSnapshot), 'common.SUCCESS', 200));
      });
    } finally {
      processListRequestInFlight = false;
    }
  }

  async loginNasCabAccount(req, res) {
    const authCode = readCodeFromReq(req);
    let token = '';

    if (authCode) {
      let exchangeRes;
      try {
        const r = await axios.request({
          url: apiConfig.apiAuthCodeExchangePath,
          method: 'POST',
          timeout: 8000,
          headers: { 'Content-Type': 'application/json' },
          data: { code: authCode },
          validateStatus: () => true,
        });
        exchangeRes = r && r.data ? r.data : null;
      } catch (e) {
        console.log('[login/codeExchange] request failed:', {
          url: apiConfig.apiAuthCodeExchangePath,
          code: e && e.code,
          message: e && e.message,
          status: e && e.response && e.response.status,
          cause: e && e.cause && (e.cause.code || e.cause.message),
        });
        if (
          e &&
          (e.code === 'ECONNABORTED' ||
            String(e.message || '')
              .toLowerCase()
              .includes('timeout'))
        ) {
          return ResponseUtil.error(req, res, 'service.NETWORK_TIMEOUT', 504);
        }
        return ResponseUtil.error(req, res, 'service.NETWORK_ERROR', 502);
      }
      const exCode = exchangeRes && exchangeRes.code;
      const exData = exchangeRes && exchangeRes.data ? exchangeRes.data : null;
      token = exData && (exData.accessToken || exData.token) ? String(exData.accessToken || exData.token) : '';
      if (exCode !== 0 || !token) {
        return ResponseUtil.error(req, res, 'service.REMOTE_AUTH_FAILED', 401, {
          code: exCode,
          message: exchangeRes && exchangeRes.message ? exchangeRes.message : '',
        });
      }
    } else {
      token = readTokenFromReq(req);
    }

    if (!nascabAccountUtil.isValidJwtFormat(token)) {
      return ResponseUtil.error(req, res, 'service.INVALID_TOKEN_FORMAT', 400);
    }

    const serverId = await nascabAccountUtil.ensureServerId(tableConfig);
    const deviceId = nascabAccountUtil.resolveDeviceId(serverId);

    let remoteJson;
    try {
      const r = await axios.request({
        url: apiConfig.apiAuthJwtRefreshPath,
        method: 'POST',
        timeout: 8000,
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
        },
        data: { jwt: token, token, deviceId },
        validateStatus: () => true,
      });
      remoteJson = r && r.data ? r.data : null;
    } catch (e) {
      console.log('[login/jwtRefresh] request failed:', {
        url: apiConfig.apiAuthJwtRefreshPath,
        code: e && e.code,
        message: e && e.message,
        status: e && e.response && e.response.status,
        cause: e && e.cause && (e.cause.code || e.cause.message),
      });
      if (
        e &&
        (e.code === 'ECONNABORTED' ||
          String(e.message || '')
            .toLowerCase()
            .includes('timeout'))
      ) {
        return ResponseUtil.error(req, res, 'service.NETWORK_TIMEOUT', 504);
      }
      return ResponseUtil.error(req, res, 'service.NETWORK_ERROR', 502);
    }

    const code = remoteJson && remoteJson.code;
    const data = remoteJson && remoteJson.data ? remoteJson.data : null;
    const newToken = data && (data.accessToken || data.token) ? String(data.accessToken || data.token) : '';
    const refreshToken = data && data.refreshToken ? String(data.refreshToken) : '';
    const user = data && data.user ? data.user : null;
    const membership = data && data.membership ? data.membership : null;
    user.membership = membership;
    if (code !== 0 || !newToken || !refreshToken || !user) {
      if (code === 401) {
        try {
          await req.dbMain.transaction(async trx => {
            await nascabAccountUtil.clearNasCabLoginInfo(trx, tableConfig);
          });
        } catch (_) {}
      }
      return ResponseUtil.error(req, res, 'service.REMOTE_AUTH_FAILED', 401, {
        code,
        message: remoteJson && remoteJson.message ? remoteJson.message : '',
      });
    }

    const userJson = (() => {
      try {
        return JSON.stringify(user);
      } catch (_) {
        return '';
      }
    })();
    if (!userJson) {
      return ResponseUtil.error(req, res, 'service.USER_SERIALIZE_FAILED', 500);
    }
    console.log('userJson', userJson);
    try {
      await req.dbMain.transaction(async trx => {
        await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, nascabAccountUtil.NASCAB_KEYS.accessToken, newToken);
        await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, nascabAccountUtil.NASCAB_KEYS.refreshToken, refreshToken);
        await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, nascabAccountUtil.NASCAB_KEYS.user, userJson);
      });
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_WRITE_FAILED', 500);
    }

    try {
      const sid = serverId || (await tableConfig.ensureServerId()) || '';
      if (sid) process.env.SERVER_ID = String(sid);
      const deviceInfo = buildDeviceInfo(sid);
      const r = await axios.request({
        url: apiConfig.apiP2pDeviceRegisterPath,
        method: 'POST',
        timeout: 8000,
        headers: {
          Authorization: `Bearer ${newToken}`,
          'Content-Type': 'application/json',
        },
        data: {
          serverId: sid,
          deviceName: deviceInfo.deviceName,
          platform: deviceInfo.platform,
          deviceInfo,
        },
        validateStatus: () => true,
      });
      const json = r && r.data ? r.data : null;
      const data = json && json.data ? json.data : null;
      const pairCode = extractPairCode(data && (data.pairCode ?? data.pair_code ?? data.paircode));
      if (json && json.code === 0 && pairCode) {
        await req.dbMain.transaction(async trx => {
          await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, nascabAccountUtil.NASCAB_KEYS.p2pPairCode, pairCode);
        });
      }
    } catch (_) {}

    try {
      if (typeof process.send === 'function') {
        process.send({ type: 'ensureP2pConnectWorker' });
      }
    } catch (_) {}

    return ResponseUtil.success(req, res, user, 'common.SUCCESS', 200);
  }

  async refreshNasCabAccountInfo(req, res) {
    const storedToken = await nascabAccountUtil.getStoredAccessToken(req.dbMain, tableConfig);
    if (!storedToken) {
      const refreshToken = await nascabAccountUtil.getStoredRefreshToken(req.dbMain, tableConfig);
      if (!refreshToken) {
        return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
      }
    }
    const tokenToUse = storedToken || (await nascabAccountUtil.getStoredRefreshToken(req.dbMain, tableConfig));
    if (!tokenToUse) {
      return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
    }
    req.body = req.body || {};
    req.body.jwt = tokenToUse;
    req.body.token = tokenToUse;
    return this.loginNasCabAccount(req, res);
  }

  async getNasCabAccount(req, res) {
    try {
      const decrypted = await nascabAccountUtil.getDecryptedConfigValue(req.dbMain, tableConfig, nascabAccountUtil.NASCAB_KEYS.user);
      if (!decrypted) {
        return ResponseUtil.success(req, res, {}, 'common.SUCCESS', 200);
      }
      try {
        const parsed = JSON.parse(decrypted);
        if (!parsed || typeof parsed !== 'object') {
          return ResponseUtil.success(req, res, {}, 'common.SUCCESS', 200);
        }
        return ResponseUtil.success(req, res, parsed, 'common.SUCCESS', 200);
      } catch (e) {
        return ResponseUtil.error(req, res, 'service.USER_PARSE_FAILED', 500);
      }
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_CONNECTION_FAILED', 500);
    }
  }

  async logoutNasCabAccount(req, res) {
    try {
      await req.dbMain.transaction(async trx => {
        await nascabAccountUtil.clearNasCabLoginInfo(trx, tableConfig);
      });
      try {
        if (typeof process.send === 'function') {
          process.send({ type: 'setP2pRemoteAccessEnabled', data: { enabled: false } });
        }
      } catch (_) {}
      return ResponseUtil.success(req, res, {}, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_WRITE_FAILED', 500);
    }
  }

  async getP2pPairCode(req, res) {
    try {
      const loggedIn = await isNasCabLoggedIn(req);
      if (!loggedIn) {
        return ResponseUtil.success(req, res, { pairCode: '' }, 'common.SUCCESS', 200);
      }
      const pairCode = await nascabAccountUtil.getDecryptedConfigValue(req.dbMain, tableConfig, nascabAccountUtil.NASCAB_KEYS.p2pPairCode);
      return ResponseUtil.success(req, res, { pairCode }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_CONNECTION_FAILED', 500);
    }
  }

  async resetP2pPairCode(req, res) {
    const serverId = (await tableConfig.ensureServerId()) || '';
    if (!serverId) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }

    const remote = await nascabAccountUtil.remoteRequestWithAutoRefresh(req.dbMain, tableConfig, apiConfig, {
      url: apiConfig.apiP2pDevicePairCodeResetPath,
      method: 'POST',
      data: { serverId },
    });
    if (!remote.ok && remote.expired) {
      return ResponseUtil.error(req, res, 'service.NASCAB_SESSION_EXPIRED', 200);
    }
    if (!remote.ok) {
      if (remote.status === 403) {
        return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
      }
      return ResponseUtil.error(req, res, 'service.NETWORK_ERROR', 502);
    }

    const code = remote.json && remote.json.code;
    const data = remote.json && remote.json.data ? remote.json.data : null;
    const pairCode = extractPairCode(data && (data.pairCode ?? data.pair_code ?? data.paircode));
    if (code !== 0 || !pairCode) {
      return ResponseUtil.error(req, res, 'service.PAIR_CODE_RESET_FAILED', 502, {
        code,
        message: remote.json && remote.json.message ? remote.json.message : '',
      });
    }

    try {
      await req.dbMain.transaction(async trx => {
        await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, nascabAccountUtil.NASCAB_KEYS.p2pPairCode, pairCode);
      });
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_WRITE_FAILED', 500);
    }

    return ResponseUtil.success(req, res, { pairCode }, 'common.SUCCESS', 200);
  }

  async customP2pPairCode(req, res) {
    const pairCode = extractPairCode(req.body && (req.body.pairCode ?? req.body.pair_code ?? req.body.paircode));
    if (!pairCode) {
      return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
    }

    const serverId = (await tableConfig.ensureServerId()) || '';
    if (!serverId) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }

    const remote = await nascabAccountUtil.remoteRequestWithAutoRefresh(req.dbMain, tableConfig, apiConfig, {
      url: apiConfig.apiP2pDevicePairCodeCustomPath,
      method: 'POST',
      data: { serverId, pairCode },
    });
    if (!remote.ok && remote.expired) {
      return ResponseUtil.error(req, res, 'service.NASCAB_SESSION_EXPIRED', 200);
    }
    if (!remote.ok) {
      if (remote.status === 403) {
        return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
      }
      return ResponseUtil.error(req, res, 'service.NETWORK_ERROR', 502);
    }

    if (remote.status === 404) {
      return ResponseUtil.error(req, res, 'P2P_CUSTOM_PAIR_CODE_API_NOT_AVAILABLE', 502);
    }
    if (!remote.json || typeof remote.json !== 'object') {
      return ResponseUtil.error(req, res, 'P2P_CUSTOM_PAIR_CODE_FAILED', 502);
    }

    const code = remote.json.code;
    const data = remote.json.data ? remote.json.data : null;
    const errorCode = data && data.errorCode ? String(data.errorCode) : '';
    const newPairCode = extractPairCode(data && (data.pairCode ?? data.pair_code ?? data.paircode));
    if (code !== 0 || !newPairCode) {
      if (errorCode) {
        return ResponseUtil.error(req, res, errorCode, remote.status);
      }
      return ResponseUtil.error(req, res, 'P2P_CUSTOM_PAIR_CODE_FAILED', 502, {
        code,
        message: remote.json.message ? String(remote.json.message) : '',
      });
    }

    try {
      await req.dbMain.transaction(async trx => {
        await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, nascabAccountUtil.NASCAB_KEYS.p2pPairCode, newPairCode);
      });
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_WRITE_FAILED', 500);
    }

    return ResponseUtil.success(req, res, { pairCode: newPairCode }, 'common.SUCCESS', 200);
  }

  async getP2pRemoteAccess(req, res) {
    try {
      const loggedIn = await isNasCabLoggedIn(req);
      const enabled = await tableConfig.getP2pRemoteAccessEnabled();
      const lastP2pError = await tableConfig.getConfigByKey('last_p2p_error');
      const errorCode = lastP2pError && String(lastP2pError).trim() ? String(lastP2pError).trim() : null;
      const p2pConnectedDomain = await tableConfig.getP2pConnectedDomain().catch(() => '');
      const p2pFixNodeDomain = await tableConfig.getP2pFixNodeDomain().catch(() => '');
      let p2pServers = await tableConfig.getP2pServersCache().catch(() => []);

      if (!loggedIn) {
        if (enabled === true) {
          try {
            await tableConfig.setP2pRemoteAccessEnabled(false);
          } catch (_) {}
          try {
            if (typeof process.send === 'function') {
              process.send({ type: 'setP2pRemoteAccessEnabled', data: { enabled: false } });
            }
          } catch (_) {}
        }
        return ResponseUtil.success(req, res, {
          enabled: false,
          pairCode: '',
          p2pConnectedDomain,
          p2pFixNodeDomain,
          p2pServers,
          ...(errorCode && { errorCode })
        }, 'common.SUCCESS', 200);
      }

      p2pServers = await ensureP2pServersCacheFresh(req.dbMain).catch(() => p2pServers);
      const pairCode = await nascabAccountUtil.getDecryptedConfigValue(req.dbMain, tableConfig, nascabAccountUtil.NASCAB_KEYS.p2pPairCode);

      return ResponseUtil.success(req, res, {
        enabled: !!enabled,
        pairCode,
        p2pConnectedDomain,
        p2pFixNodeDomain,
        p2pServers,
        ...(errorCode && { errorCode })
      }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_CONNECTION_FAILED', 500);
    }
  }

  async setP2pNodePreference(req, res) {
    const rawDomain = req.body && req.body.domain != null ? req.body.domain : req.body && req.body.p2pFixNodeDomain;
    const domain = normalizeNodeDomain(rawDomain);
    try {
      const loggedIn = await isNasCabLoggedIn(req);
      if (!loggedIn) {
        return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
      }
      const p2pServers = await ensureP2pServersCacheFresh(req.dbMain).catch(() => []);
      if (domain) {
        const exists = p2pServers.some(item => normalizeNodeDomain(item && item.domain) === domain);
        if (!exists) {
          return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
        }
      }
      await tableConfig.setP2pFixNodeDomain(domain).catch(() => {});
      await tableConfig.setP2pConnectedDomain('').catch(() => {});
      try {
        if (typeof process.send === 'function') {
          process.send({ type: 'restartP2pConnectWorker' });
        }
      } catch (_) {}
      return ResponseUtil.success(req, res, { p2pFixNodeDomain: domain, restarted: true }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_WRITE_FAILED', 500);
    }
  }

  async getNasCabTempCode(req, res) {
    const remote = await nascabAccountUtil.remoteRequestWithAutoRefresh(req.dbMain, tableConfig, apiConfig, {
      url: apiConfig.apiAuthCodeGeneratePath,
      method: 'POST',
    });
    if (!remote.ok && remote.expired) {
      return ResponseUtil.error(req, res, 'service.NASCAB_SESSION_EXPIRED', 200);
    }
    if (!remote.ok) {
      if (remote.status === 403) {
        return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
      }
      return ResponseUtil.error(req, res, 'service.NETWORK_ERROR', 502);
    }
    const code = remote.json && remote.json.code;
    const data = remote.json && remote.json.data ? remote.json.data : null;
    const tmpCode = data && data.code ? String(data.code) : '';
    if (code !== 0 || !tmpCode) {
      return ResponseUtil.error(req, res, 'service.TEMP_CODE_FAILED', 502, {
        code,
        message: remote.json && remote.json.message ? remote.json.message : '',
      });
    }
    return ResponseUtil.success(req, res, { code: tmpCode }, 'common.SUCCESS', 200);
  }

  async setP2pRemoteAccess(req, res) {
    const enabled = req.body && typeof req.body.enabled === 'boolean' ? req.body.enabled : null;
    if (enabled === null) {
      return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
    }

    if (enabled === true) {
      const loggedIn = await isNasCabLoggedIn(req);
      if (!loggedIn) {
        return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
      }
    }

    try {
      const ok = await tableConfig.setP2pRemoteAccessEnabled(enabled);
      if (!ok) return ResponseUtil.error(req, res, 'common.ERROR', 500);
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_WRITE_FAILED', 500);
    }

    try {
      if (typeof process.send === 'function') {
        process.send({ type: 'setP2pRemoteAccessEnabled', data: { enabled } });
      }
    } catch (_) {}

    return ResponseUtil.success(req, res, { enabled }, 'common.SUCCESS', 200);
  }

  async bindP2pDevice(req, res) {
    const loggedIn = await isNasCabLoggedIn(req);
    if (!loggedIn) {
      return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
    }
    const token = await nascabAccountUtil.getStoredAccessToken(req.dbMain, tableConfig);
    if (!nascabAccountUtil.isValidJwtFormat(token)) {
      return ResponseUtil.error(req, res, 'service.NASCAB_LOGIN_REQUIRED', 403);
    }
    const serverId = (await tableConfig.ensureServerId()) || '';
    if (!serverId) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
    const deviceInfo = buildDeviceInfo(serverId);
    let r;
    try {
      r = await axios.request({
        url: apiConfig.apiP2pDeviceBindPath,
        method: 'POST',
        timeout: 8000,
        headers: {
          Authorization: `Bearer ${token}`,
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
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.NETWORK_ERROR', 502);
    }
    const json = r && r.data ? r.data : null;
    const status = r ? r.status : 0;
    const code = json && json.code !== undefined ? Number(json.code) : 0;
    const data = json && json.data ? json.data : null;
    if (status === 403 || code !== 0 || !data) {
      const errorCode = data && data.errorCode ? String(data.errorCode) : '';
      if (errorCode) {
        return ResponseUtil.error(req, res, errorCode, status || 403);
      }
      return ResponseUtil.error(req, res, 'service.P2P_BIND_FAILED', 502, {
        message: json && json.message ? json.message : '',
      });
    }
    const deviceId = data.deviceId ? String(data.deviceId) : '';
    const deviceSecret = data.deviceSecret ? String(data.deviceSecret) : '';
    const deviceToken = data.deviceToken ? String(data.deviceToken) : '';
    const wsUrl = (data.wsUrl && String(data.wsUrl).trim()) || '';
    const pairCode = extractPairCode(data.pairCode ?? data.pair_code ?? data.paircode);
    if (!deviceId || !pairCode) {
      return ResponseUtil.error(req, res, 'service.P2P_BIND_FAILED', 502);
    }
    try {
      await req.dbMain.transaction(async trx => {
        await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, nascabAccountUtil.NASCAB_KEYS.p2pPairCode, pairCode);
        if (deviceId) await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, 'p2p_device_id', deviceId);
        if (deviceSecret) await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, 'p2p_device_secret', deviceSecret);
        if (deviceToken) await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, 'p2p_device_token', deviceToken);
        if (wsUrl) await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, 'p2p_ws_url', wsUrl);
      });
    } catch (e) {
      return ResponseUtil.error(req, res, 'service.DB_WRITE_FAILED', 500);
    }
    try {
      await tableConfig.deleteConfigByKey('last_p2p_error').catch(() => {});
    } catch (_) {}

    try {
      if (typeof process.send === 'function') {
        await new Promise(r => setTimeout(r, 200));
        process.send({ type: 'ensureP2pConnectWorker' });
      }
    } catch (_) {}
    return ResponseUtil.success(req, res, { pairCode }, 'common.SUCCESS', 200);
  }
}

module.exports = new ServiceController();
