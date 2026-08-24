const ipSecurityManager = require('../security/ipSecurityManager');
const tableConfig = require('../db/table/tableConfig');
const Logger = require('../utils/logger');

function sendResponse(ctx, type, payload) {
  const { expressWorker } = ctx || {};
  if (!expressWorker || typeof expressWorker.send !== 'function') return;
  try {
    expressWorker.send({ type, data: payload });
  } catch (_) {}
}

function safeJsonParse(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

let _loadedOnce = false;
let _loading = null;

async function readConfigFromDb() {
  const raw = await tableConfig.getConfigByKey(tableConfig.KEY_SECURITY_CONFIG);
  const obj = safeJsonParse(raw);
  if (!obj || typeof obj !== 'object') return null;
  return obj;
}

async function ensureConfigLoaded() {
  if (_loadedOnce) return;
  if (_loading) return await _loading;
  _loading = (async () => {
    try {
      const dbConfig = await readConfigFromDb();
      if (dbConfig) ipSecurityManager.setConfig(dbConfig);
    } catch (e) {
      Logger.error('securityCenter load config failed', e);
    } finally {
      _loadedOnce = true;
      _loading = null;
    }
  })();
  return await _loading;
}

async function handleGetSecurityConfig(ctx) {
  const requestId = ctx && ctx.message && ctx.message.data ? ctx.message.data.requestId : null;
  try {
    await ensureConfigLoaded();
    const config = ipSecurityManager.getConfig();
    if (requestId) {
      sendResponse(ctx, 'securityGetConfigResponse', { requestId, ok: true, config });
    }
  } catch (e) {
    Logger.error('securityCenter get config failed', e);
    if (requestId) {
      sendResponse(ctx, 'securityGetConfigResponse', { requestId, ok: false });
    }
  }
}

async function handleSetSecurityConfig(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const requestId = data.requestId || null;
  try {
    await ensureConfigLoaded();
    const current = (await readConfigFromDb()) || ipSecurityManager.getConfig();
    const merged = {
      ...current,
      banEnabled: typeof data.banEnabled === 'boolean' ? data.banEnabled : current.banEnabled,
      maxFailedAttempts: data.maxFailedAttempts ?? current.maxFailedAttempts,
      banMinutes: data.banMinutes ?? current.banMinutes,
      bypassLanAuth: typeof data.bypassLanAuth === 'boolean' ? data.bypassLanAuth : current.bypassLanAuth,
    };
    const applied = ipSecurityManager.setConfig(merged);
    await tableConfig.setConfigByKey(tableConfig.KEY_SECURITY_CONFIG, JSON.stringify(applied));

    const reloaded = (await readConfigFromDb()) || applied;
    ipSecurityManager.setConfig(reloaded);

    if (requestId) {
      sendResponse(ctx, 'securitySetConfigResponse', { requestId, ok: true, config: ipSecurityManager.getConfig() });
    }
  } catch (e) {
    Logger.error('securityCenter set config failed', e);
    if (requestId) {
      sendResponse(ctx, 'securitySetConfigResponse', { requestId, ok: false });
    }
  }
}

async function handleSecurityCheckIp(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const requestId = data.requestId || null;
  const ip = data.ip;
  try {
    await ensureConfigLoaded();
    const res = ipSecurityManager.isBlacklisted(ip);
    if (requestId) {
      sendResponse(ctx, 'securityCheckIpResponse', { requestId, ok: true, ...res });
    }
  } catch (e) {
    Logger.error('securityCenter check ip failed', e);
    if (requestId) {
      sendResponse(ctx, 'securityCheckIpResponse', { requestId, ok: false });
    }
  }
}

async function handleSecurityAuthFail(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const requestId = data.requestId || null;
  const ip = data.ip;
  const action = data.action;
  const desc = action === 'recover' ? 'recover_password_failed' : 'login_failed';
  try {
    await ensureConfigLoaded();
    const res = ipSecurityManager.recordFailure(ip, { description: desc });
    if (requestId) {
      sendResponse(ctx, 'securityAuthFailResponse', { requestId, ok: true, ...res });
    }
  } catch (e) {
    Logger.error('securityCenter auth fail failed', e);
    if (requestId) {
      sendResponse(ctx, 'securityAuthFailResponse', { requestId, ok: false });
    }
  }
}

function handleSecurityAuthSuccess(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const ip = data.ip;
  ipSecurityManager.clearFailures(ip);
}

async function handleSecurityBanIp(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const requestId = data.requestId || null;
  const ip = data.ip;
  const minutes = data.minutes;
  const description = data.description;
  try {
    await ensureConfigLoaded();
    const res = ipSecurityManager.banIp(ip, { minutes, description });
    if (requestId) {
      sendResponse(ctx, 'securityBanIpResponse', { requestId, ok: true, ...res });
    }
  } catch (e) {
    Logger.error('securityCenter ban ip failed', e);
    if (requestId) {
      sendResponse(ctx, 'securityBanIpResponse', { requestId, ok: false });
    }
  }
}

function handleListIpBlacklist(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const requestId = data.requestId || null;
  const items = ipSecurityManager.listBlacklist();
  if (requestId) {
    sendResponse(ctx, 'securityListIpBlacklistResponse', { requestId, ok: true, items });
  }
}

function handleDeleteIpBlacklist(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const requestId = data.requestId || null;
  const ip = data.ip;
  const deleted = ipSecurityManager.deleteBlacklist(ip);
  if (requestId) {
    sendResponse(ctx, 'securityDeleteIpBlacklistResponse', { requestId, ok: true, deleted: !!deleted });
  }
}

function handleClearIpBlacklist(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const requestId = data.requestId || null;
  const cleared = ipSecurityManager.clearBlacklist();
  if (requestId) {
    sendResponse(ctx, 'securityClearIpBlacklistResponse', { requestId, ok: true, cleared });
  }
}

module.exports = {
  securityGetConfig: handleGetSecurityConfig,
  securitySetConfig: handleSetSecurityConfig,
  securityCheckIp: handleSecurityCheckIp,
  securityAuthFail: handleSecurityAuthFail,
  securityAuthSuccess: handleSecurityAuthSuccess,
  securityBanIp: handleSecurityBanIp,
  securityListIpBlacklist: handleListIpBlacklist,
  securityDeleteIpBlacklist: handleDeleteIpBlacklist,
  securityClearIpBlacklist: handleClearIpBlacklist,
};
