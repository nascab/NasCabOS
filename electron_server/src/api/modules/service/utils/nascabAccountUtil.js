const axios = require('axios');
const crypto = require('crypto');
const os = require('os');

const CONFIG_TABLE = 'config';
const CONFIG_UID = 0;
const ENC_PREFIX = 'enc.v1';

const NASCAB_KEYS = {
  accessToken: 'nascab_token',
  refreshToken: 'nascab_refresh_token',
  user: 'nascab_user',
  membership: 'nascab_membership',
  p2pPairCode: 'p2p_pair_code',
};

/** 登出时一并清除，避免切换账号后仍用旧设备凭证导致 device_id 与远端不一致 */
const P2P_DEVICE_KEYS_CLEAR_ON_LOGOUT = ['p2p_device_id', 'p2p_device_secret', 'p2p_device_token', 'p2p_ws_url'];

function isValidJwtFormat(token) {
  if (typeof token !== 'string') return false;
  const t = token.trim();
  if (!t) return false;
  if (t.length < 20 || t.length > 4096) return false;
  return /^[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+$/.test(t);
}

async function ensureServerId(tableConfig) {
  if (process.env.SERVER_ID && String(process.env.SERVER_ID).trim()) return String(process.env.SERVER_ID).trim();
  try {
    const sid = await tableConfig.getServerId().catch(() => '');
    if (sid && String(sid).trim()) {
      process.env.SERVER_ID = String(sid).trim();
      return String(sid).trim();
    }
  } catch (_) {}
  try {
    const sid = await tableConfig.ensureServerId();
    if (sid && String(sid).trim()) {
      process.env.SERVER_ID = String(sid).trim();
      return String(sid).trim();
    }
  } catch (_) {}
  return '';
}

function resolveDeviceId(serverId) {
  const sid = serverId == null ? '' : String(serverId).trim();
  if (sid) return sid;
  return os.hostname ? os.hostname() : '';
}

function getConfigEncryptionKey(serverId) {
  const sid = serverId == null ? '' : String(serverId).trim();
  if (!sid) return null;
  return crypto.createHash('sha256').update(sid).digest();
}

function encryptConfigValue(plainText, serverId) {
  const key = getConfigEncryptionKey(serverId);
  if (!key) return String(plainText);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const cipherText = Buffer.concat([cipher.update(String(plainText), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${ENC_PREFIX}.${iv.toString('base64')}.${tag.toString('base64')}.${cipherText.toString('base64')}`;
}

function decryptConfigValue(value, serverId) {
  const raw = value ? String(value) : '';
  if (!raw.trim()) return '';
  if (!raw.startsWith(`${ENC_PREFIX}.`)) return raw;
  const key = getConfigEncryptionKey(serverId);
  if (!key) return null;
  const parts = raw.split('.');
  if (parts.length !== 5) return null;
  try {
    const iv = Buffer.from(parts[2], 'base64');
    const tag = Buffer.from(parts[3], 'base64');
    const cipherText = Buffer.from(parts[4], 'base64');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    const plain = Buffer.concat([decipher.update(cipherText), decipher.final()]);
    return plain.toString('utf8');
  } catch (_) {
    return null;
  }
}

async function getDecryptedConfigValue(knex, tableConfig, key) {
  const serverId = await ensureServerId(tableConfig);
  const row = await knex(CONFIG_TABLE).where({ uid: CONFIG_UID, key }).first('value');
  const raw = row && row.value ? String(row.value) : '';
  if (!raw.trim()) return '';
  const decrypted = decryptConfigValue(raw, serverId);
  if (decrypted === null) return '';
  return String(decrypted || '').trim();
}

async function upsertConfig(trx, key, value) {
  const existing = await trx(CONFIG_TABLE).where({ uid: CONFIG_UID, key }).first('id');
  if (existing && existing.id) {
    await trx(CONFIG_TABLE).where({ id: existing.id }).update({ value });
    return;
  }
  await trx(CONFIG_TABLE).insert({ uid: CONFIG_UID, key, value });
}

async function setConfigValue(trx, key, value) {
  if (value === null) {
    const existing = await trx(CONFIG_TABLE).where({ uid: CONFIG_UID, key }).first('id');
    if (!existing || !existing.id) return;
    await trx(CONFIG_TABLE).where({ id: existing.id }).update({ value: null });
    return;
  }
  await upsertConfig(trx, key, String(value));
}

async function setEncryptedConfigValue(trx, tableConfig, key, plainValue) {
  if (plainValue === null) {
    await setConfigValue(trx, key, null);
    return;
  }
  const serverId = await ensureServerId(tableConfig);
  await setConfigValue(trx, key, encryptConfigValue(plainValue, serverId));
}

async function clearNasCabLoginInfo(trx, tableConfig) {
  await setConfigValue(trx, NASCAB_KEYS.accessToken, null);
  await setConfigValue(trx, NASCAB_KEYS.refreshToken, null);
  await setConfigValue(trx, NASCAB_KEYS.user, null);
  await setConfigValue(trx, NASCAB_KEYS.p2pPairCode, null);
  await setConfigValue(trx, tableConfig.KEY_P2P_REMOTE_ACCESS_ENABLED, '0');
  for (const key of P2P_DEVICE_KEYS_CLEAR_ON_LOGOUT) {
    await setConfigValue(trx, key, null);
  }
}

async function getStoredAccessToken(knex, tableConfig) {
  const token = await getDecryptedConfigValue(knex, tableConfig, NASCAB_KEYS.accessToken);
  return isValidJwtFormat(token) ? token : '';
}

async function getStoredRefreshToken(knex, tableConfig) {
  const token = await getDecryptedConfigValue(knex, tableConfig, NASCAB_KEYS.refreshToken);
  if (!token) return '';
  if (token.length < 16 || token.length > 2048) return '';
  return token;
}

async function refreshNasCabTokens(knex, tableConfig, apiConfig) {
  const refreshToken = await getStoredRefreshToken(knex, tableConfig);
  console.log('refreshToken', refreshToken);
  if (!refreshToken) return { ok: false, reason: 'missing' };

  const serverId = await ensureServerId(tableConfig);
  const deviceId = resolveDeviceId(serverId);

  let status = 502;
  let json;
  try {
    const r = await axios.request({
      url: apiConfig.apiAuthTokenRefreshPath,
      method: 'POST',
      timeout: 8000,
      headers: {
        'Content-Type': 'application/json',
        'X-Device-Id': deviceId,
      },
      data: { refreshToken, deviceId },
      validateStatus: () => true,
    });
    status = typeof r.status === 'number' ? r.status : 502;
    json = r && r.data ? r.data : null;
  } catch (_) {
    return { ok: false, reason: 'network' };
  }

  const code = json && json.code;
  const data = json && json.data ? json.data : null;
  const accessToken = data && (data.accessToken || data.token) ? String(data.accessToken || data.token) : '';
  const nextRefreshToken = data && data.refreshToken ? String(data.refreshToken) : '';
  // console.log('NasCab账号登录状态刷新', data);
  if (status === 200 && code === 0 && accessToken && nextRefreshToken) {
    try {
      await knex.transaction(async trx => {
        await setEncryptedConfigValue(trx, tableConfig, NASCAB_KEYS.accessToken, accessToken);
        await setEncryptedConfigValue(trx, tableConfig, NASCAB_KEYS.refreshToken, nextRefreshToken);
      });
      return { ok: true, accessToken };
    } catch (_) {
      return { ok: false, reason: 'db' };
    }
  }

  if (status === 401) {
    try {
      await knex.transaction(async trx => {
        await clearNasCabLoginInfo(trx, tableConfig);
      });
    } catch (_) {}
    return { ok: false, reason: 'expired' };
  }

  return { ok: false, reason: 'failed' };
}

async function ensureNasCabAccessToken(knex, tableConfig, apiConfig) {
  const existing = await getStoredAccessToken(knex, tableConfig);
  if (existing) return { token: existing, expired: false };
  const hasRefresh = !!(await getStoredRefreshToken(knex, tableConfig));
  if (!hasRefresh) return { token: '', expired: false };
  const refreshed = await refreshNasCabTokens(knex, tableConfig, apiConfig);
  if (refreshed.ok) return { token: refreshed.accessToken, expired: false };
  return { token: '', expired: refreshed.reason === 'expired' };
}

async function remoteRequestWithAutoRefresh(knex, tableConfig, apiConfig, axiosOpts) {
  const ensured = await ensureNasCabAccessToken(knex, tableConfig, apiConfig);
  if (!ensured.token) return { ok: false, expired: ensured.expired, status: ensured.expired ? 401 : 403, json: null };

  const serverId = await ensureServerId(tableConfig);
  const deviceId = resolveDeviceId(serverId);

  const doReq = async token => {
    const r = await axios.request({
      timeout: 8000,
      validateStatus: () => true,
      ...axiosOpts,
      headers: {
        ...(axiosOpts && axiosOpts.headers ? axiosOpts.headers : {}),
        Authorization: `Bearer ${token}`,
        'X-Device-Id': deviceId,
        'Content-Type': 'application/json',
      },
    });
    const status = r && typeof r.status === 'number' ? r.status : 502;
    const json = r && r.data ? r.data : null;
    return { status, json };
  };

  let first;
  try {
    first = await doReq(ensured.token);
  } catch (_) {
    return { ok: false, expired: false, status: 502, json: null };
  }
  if (first.status !== 401) return { ok: true, expired: false, status: first.status, json: first.json };

  const refreshed = await refreshNasCabTokens(knex, tableConfig, apiConfig);
  if (!refreshed.ok) {
    return { ok: false, expired: refreshed.reason === 'expired', status: 401, json: first.json };
  }

  try {
    const second = await doReq(refreshed.accessToken);
    return { ok: true, expired: false, status: second.status, json: second.json };
  } catch (_) {
    return { ok: false, expired: false, status: 502, json: null };
  }
}

module.exports = {
  NASCAB_KEYS,
  isValidJwtFormat,
  ensureServerId,
  resolveDeviceId,
  encryptConfigValue,
  decryptConfigValue,
  getDecryptedConfigValue,
  setConfigValue,
  setEncryptedConfigValue,
  clearNasCabLoginInfo,
  getStoredAccessToken,
  getStoredRefreshToken,
  refreshNasCabTokens,
  ensureNasCabAccessToken,
  remoteRequestWithAutoRefresh,
};
