const authService = require('./authService');
const ResponseUtil = require('../../apiUtils/responseUtil');
const Logger = require('../../../utils/logger');
const { SERVER_VERSION } = require('../../../config/versionConfig');

const NetUtil = require('../../../utils/netUtil');
const TimeUtil = require('../../../utils/timeUtil');
const os = require('os');
const tableConfig = require('../../../db/table/tableConfig');
const config = require('../../../config/config');
const AppsService = require('../others/apps/appsService');
const AppearanceService = require('../others/appearance/appearanceService');
const userUtil = require('../../../utils/userUtil');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { TwoFAService } = require('./2fa/twofaService');
const { MessageService } = require('../message/messageService');
const {
  getTranslation,
  getLocalizedMessage,
  resolveServerUiLanguageFromDb,
} = require('../../../utils/i18nUtil');

const CONFIG_TABLE = 'config';
const CONFIG_UID = 0;
const KEY_P2P_PAIR_CODE = 'p2p_pair_code';
const ENC_PREFIX = 'enc.v1';

function getConfigEncryptionKey() {
  const serverId = process.env.SERVER_ID ? String(process.env.SERVER_ID) : '';
  if (!serverId.trim()) return null;
  return crypto.createHash('sha256').update(serverId).digest();
}

function decryptConfigValue(value) {
  const raw = value ? String(value) : '';
  if (!raw.trim()) return '';
  if (!raw.startsWith(`${ENC_PREFIX}.`)) return raw;
  const key = getConfigEncryptionKey();
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

async function getP2pPairCodePlain(dbMain) {
  try {
    const row = await dbMain(CONFIG_TABLE).where({ uid: CONFIG_UID, key: KEY_P2P_PAIR_CODE }).first('value');
    const raw = row && row.value ? String(row.value) : '';
    if (!raw.trim()) return '';
    const decrypted = decryptConfigValue(raw);
    if (decrypted === null) return '';
    const code = String(decrypted || '').trim();
    return code;
  } catch (_) {
    return '';
  }
}

function waitForIpcResponse({ requestId, responseType, timeoutMs }) {
  return new Promise((resolve, reject) => {
    if (typeof process.send !== 'function') {
      const err = new Error('common.ERROR');
      err.statusCode = 500;
      reject(err);
      return;
    }

    let done = false;
    const timer = setTimeout(
      () => {
        if (done) return;
        done = true;
        try {
          process.removeListener('message', onMessage);
        } catch (_) {}
        const err = new Error('common.ERROR');
        err.statusCode = 504;
        reject(err);
      },
      Math.max(500, Number(timeoutMs || 0) || 0)
    );

    const onMessage = message => {
      if (!message || message.type !== responseType) return;
      if (!message.data || message.data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      try {
        process.removeListener('message', onMessage);
      } catch (_) {}
      resolve(message.data || {});
    };

    process.on('message', onMessage);
  });
}

async function checkIpBlacklisted(ip) {
  if (typeof process.send !== 'function') return { blacklisted: true };
  const requestId = `securityCheckIp_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const wait = waitForIpcResponse({
    requestId,
    responseType: 'securityCheckIpResponse',
    timeoutMs: 4000,
  });
  process.send({ type: 'securityCheckIp', data: { requestId, ip }, timestamp: Date.now() });
  const data = await wait.catch(() => null);
  if (!data || data.ok !== true) return { blacklisted: false };
  return { blacklisted: data.blacklisted === true, ip: data.ip, entry: data.entry || null };
}

async function recordAuthFailure(ip, action) {
  if (typeof process.send !== 'function') {
    Logger.warn('recordAuthFailure: process.send unavailable; IP lockout may not apply (not a cluster worker?)', { ip, action });
    return { ok: false };
  }
  const requestId = `securityAuthFail_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const wait = waitForIpcResponse({
    requestId,
    responseType: 'securityAuthFailResponse',
    timeoutMs: 4000,
  });
  process.send({ type: 'securityAuthFail', data: { requestId, ip, action }, timestamp: Date.now() });
  const data = await wait.catch(() => null);
  if (!data || data.ok !== true) return { ok: false };
  return {
    ok: true,
    blacklisted: data.blacklisted === true,
    count: data.count,
    entry: data.entry || null,
    ip: data.ip,
  };
}

function recordAuthSuccess(ip) {
  if (typeof process.send !== 'function') return;
  process.send({ type: 'securityAuthSuccess', data: { ip }, timestamp: Date.now() });
}

async function banIpForMinutes(ip, minutes, description) {
  if (typeof process.send !== 'function') return { ok: false };
  const requestId = `securityBanIp_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const wait = waitForIpcResponse({
    requestId,
    responseType: 'securityBanIpResponse',
    timeoutMs: 4000,
  });
  process.send({ type: 'securityBanIp', data: { requestId, ip, minutes, description }, timestamp: Date.now() });
  const data = await wait.catch(() => null);
  if (!data || data.ok !== true) return { ok: false };
  return { ok: true, blacklisted: data.blacklisted === true, entry: data.entry || null };
}

function resolveBlacklistDisplayIp(req, ipHint) {
  let ip = '';
  if (ipHint && typeof ipHint === 'object' && ipHint.ip != null) ip = String(ipHint.ip);
  else if (ipHint != null && typeof ipHint !== 'object') ip = String(ipHint);
  ip = ip.trim();
  if (ip) return ip;
  return String(NetUtil.getClientIP(req) || '').trim();
}

/** 写入 message 表：IP 刚被临时封禁时通知管理员（重要级别，全员可见） */
async function addIpBlacklistAdminMessage(knexMain, bannedIp) {
  if (!knexMain) return;
  const ip = String(bannedIp || '').trim() || '—';
  const locale = await resolveServerUiLanguageFromDb();
  const title = getTranslation('messages.message.IP_BLACKLIST_ADMIN_TITLE', locale);
  const message = getTranslation('messages.message.IP_BLACKLIST_ADMIN_MESSAGE', locale, [ip]);
  const service = new MessageService(knexMain);
  await service.addMessage({
    uid: 0,
    title,
    message,
    action: null,
    level: 1,
    isPublic: 1,
  });
}

/** IP 封禁响应：基础提示 + 安全说明（含客户端 IP，多语言）；可选写入站内消息 */
async function respondIpBlacklisted(req, res, ipHint, options = {}) {
  const ip = resolveBlacklistDisplayIp(req, ipHint) || '—';
  if (options.recordSecurityMessage && req.dbMain) {
    try {
      await addIpBlacklistAdminMessage(req.dbMain, ip);
    } catch (e) {
      Logger.warn('addIpBlacklistAdminMessage failed', e);
    }
  }
  const base = getLocalizedMessage(req, 'security.IP_BLACKLISTED');
  const notice = getLocalizedMessage(req, 'security.IP_BLACKLISTED_SECURITY_NOTICE', [ip]);
  return res.status(403).json({
    success: false,
    message: `${base}\n\n${notice}`,
    code: 'security.IP_BLACKLISTED',
  });
}

class AuthController {
  constructor() {
    this.appsService = new AppsService();
    this.appearanceService = new AppearanceService();
  }

  async _getLoginCommonData() {
    const httpPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTP);
    const httpsPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTPS);
    const serverId = await tableConfig.getServerId();
    if (serverId && !String(process.env.SERVER_ID || '').trim()) {
      process.env.SERVER_ID = String(serverId).trim();
    }
    const shellSupported = await tableConfig.getConfigByKey('shell_supported');
    const customHostnameRaw = await tableConfig.getConfigByKey(tableConfig.KEY_CUSTOM_HOSTNAME, 0);
    const customHostname =
      typeof customHostnameRaw === 'string' && customHostnameRaw.trim().length > 0
        ? customHostnameRaw.trim()
        : null;
    return {
      platform: os.platform(),
      serverPlatform: os.platform(), // 服务器 OS 平台，如 darwin/win32/linux
      hostname: os.hostname(),
      serverId,
      httpPort,
      httpsPort,
      shellSupported,
      customHostname,
    };
  }

  async _sendLoginSuccess(req, res, result) {
    const common = await this._getLoginCommonData();
    const ipAddresses = NetUtil.getIPv4Addresses();
    const preferred = ipAddresses && ipAddresses.find(ip => ip.startsWith('192.') || ip.startsWith('10.'));
    const lanIpv4 = preferred ? String(preferred) : (ipAddresses && ipAddresses[0] ? String(ipAddresses[0]) : '');
    const p2pRemoteAccessEnabled = await tableConfig.getP2pRemoteAccessEnabled().catch(() => false);
    const pairCode = p2pRemoteAccessEnabled ? await getP2pPairCodePlain(req.dbMain) : '';
    const now = Math.floor(Date.now() / 1000);
    const expiresInSeconds = TimeUtil.parseExpiresIn(config.jwt.accessTokenExpiresIn);
    const expiresIn = now + expiresInSeconds;
    return ResponseUtil.success(
      req,
      res,
      {
        user: result.user,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiresIn,
        serverVersion: SERVER_VERSION,
        ...common,
        lanIpv4,
        p2pRemoteAccessEnabled,
        pairCode,
        apps: await this.appsService.getApps(result.user.id),
        wallpaper: await authService.getUserWallpaper(result.user.id),
      },
      'auth.LOGIN_SUCCESS'
    );
  }

  async _resolveDeviceInfo({ knexMain, userId, deviceFingerprint, clientIp }) {
    let fingerprint = deviceFingerprint;
    if (typeof fingerprint === 'string') {
      try {
        fingerprint = JSON.parse(fingerprint);
      } catch (_) {
        fingerprint = null;
      }
    }
    if (!fingerprint || typeof fingerprint !== 'object') {
      return { deviceId: null, deviceName: null, osVersion: null, device: null, isNew: true, isStale: false };
    }
    const storageIdRaw = fingerprint.storage_id ?? fingerprint.storageId;
    const storageId = storageIdRaw === 0 || storageIdRaw ? String(storageIdRaw).trim() : '';
    if (!storageId) {
      return { deviceId: null, deviceName: null, osVersion: null, device: null, isNew: true, isStale: false };
    }

    const built = await authService.buildDeviceId(fingerprint, clientIp);
    const deviceId = built.deviceId;
    const deviceName = built.payload && built.payload.device_name ? built.payload.device_name : null;
    const osVersion = built.payload && built.payload.os_version ? built.payload.os_version : null;
    const device = await authService.getUserDevice({ knexMain, userId, deviceId });
    if (!device) {
      return { deviceId, deviceName, osVersion, device: null, isNew: true, isStale: false };
    }
    const lastSeen = device.last_seen_at ? new Date(device.last_seen_at).getTime() : 0;
    const isStale = Number.isFinite(lastSeen) && Date.now() - lastSeen > 30 * 24 * 60 * 60 * 1000;
    return { deviceId, deviceName, osVersion, device, isNew: false, isStale };
  }

  async _addNewDeviceLoginMessage({ knexMain, uid, deviceName, osVersion }) {
    try {
      const userLocale = await resolveServerUiLanguageFromDb();
      const safeName = deviceName && typeof deviceName === 'string' && deviceName.trim() ? deviceName.trim() : getTranslation('messages.message.UNKNOWN_DEVICE', userLocale);
      const safeOs = osVersion && typeof osVersion === 'string' && osVersion.trim() ? osVersion.trim() : '';
      const title = getTranslation('messages.message.NEW_DEVICE_LOGIN_TITLE', userLocale);
      const messageKey = safeOs ? 'messages.message.NEW_DEVICE_LOGIN_CONTENT_WITH_OS' : 'messages.message.NEW_DEVICE_LOGIN_CONTENT';
      const message = safeOs ? getTranslation(messageKey, userLocale, [safeName, safeOs]) : getTranslation(messageKey, userLocale, [safeName]);
      const service = new MessageService(knexMain);
      await service.addMessage({
        uid,
        title,
        message,
        action: null,
        level: 0,
        isPublic: 0,
      });
    } catch (_) {}
  }

  async _logTwofaAttempt({ knexMain, userId, action, method, clientIp, deviceId, ok, reasonCode }) {
    try {
      await knexMain('user_2fa_verify_log').insert({
        user_id: userId || null,
        action: action || 'login',
        method: method || 'totp',
        client_ip: clientIp || null,
        device_id: deviceId || null,
        ok: ok === true,
        reason_code: reasonCode || null,
        create_time: new Date(),
      });
    } catch (_) {}
  }

  async _countRecentTwofaAttempts({ knexMain, userId, action, windowMs }) {
    const since = new Date(Date.now() - windowMs);
    const rows = await knexMain('user_2fa_verify_log')
      .where({ user_id: userId, action: action || 'login' })
      .andWhere('create_time', '>=', since)
      .count('id as count');
    const count = rows && rows[0] ? Number(rows[0].count) || 0 : 0;
    return count;
  }

  /**
   * 检测用户表中是否已存在超级管理员
   */
  hasSuperAdmin = async (req, res) => {
    try {
      const knexMain = req.dbMain;
      const hasSuperAdmin = await authService.hasSuperAdmin({ knexMain });
      Logger.business('check_super_admin', null, { hasSuperAdmin });
      return ResponseUtil.success(req, res, { hasSuperAdmin }, 'SUPER_ADMIN_CHECK_SUCCESS');
    } catch (err) {
      Logger.error('hasSuperAdmin failed', err, { method: 'hasSuperAdmin' });
      if (err.message && err.message.startsWith('auth.')) {
        return ResponseUtil.error(req, res, err.message, 400);
      }
      return ResponseUtil.serverError(req, res, err);
    }
  };
  /**
   * 获取服务器状态 用于判断是否是nascabos服务器
   */
  isNasCabServer = async (req, res) => {
    const knexMain = req.dbMain;
    try {
      const httpPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTP);
      const httpsPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTPS);
      const hasSuperAdmin = await authService.hasSuperAdmin({ knexMain });
      return ResponseUtil.success(
        req,
        res,
        {
          isNasCabOSServer: true,
          httpPort,
          httpsPort,
          platform: os.platform(),
          hostname: os.hostname(),
          serverId: process.env.SERVER_ID,
          hasSuperAdmin: hasSuperAdmin,
        },
        'SERVER_STATUS_CHECK_SUCCESS'
      );
    } catch (err) {
      return ResponseUtil.serverError(req, res, err);
    }
  };

  /**
   * 创建超级管理员
   */
  createSuperAdmin = async (req, res) => {
    try {
      // 检查请求IP是否为局域网IP
      const clientIp = NetUtil.getClientIP(req);
      console.log('clientIp', clientIp);

      // 检查IP是否为局域网IP
      const isPrivateIP = NetUtil.isPrivateIP(clientIp);

      if (!isPrivateIP) {
        Logger.warn('Non-LAN request tried to create super admin', {
          method: 'createSuperAdmin',
          clientIp: clientIp,
          isPrivateIP: isPrivateIP,
        });
        return ResponseUtil.error(req, res, 'auth.PRIVATE_NETWORK_ONLY_OPERATION', 403);
      }

      const { username, password, phone, question, answer, language = 'zh-CN' } = req.body;

      const knexMain = req.dbMain;

      // 检查是否已经存在超级管理员
      const hasSuperAdmin = await authService.hasSuperAdmin({ knexMain });
      if (hasSuperAdmin) {
        Logger.warn('Super admin already exists', {
          method: 'createSuperAdmin',
          clientIp: clientIp,
          username: username,
        });
        return ResponseUtil.error(req, res, 'auth.SUPER_ADMIN_EXISTS', 400);
      }

      const userData = {
        username,
        password,
        question,
        answer,
        phone,
        language,
      };

      const result = await authService.createSuperAdmin({ knexMain }, userData);

      // 获取客户端信息
      // clientIp已在前面定义
      const userAgent = req.headers['user-agent'] || '';

      // 创建成功后自动登录，生成token
      const loginResult = await authService.login(
        { knexMain },
        {
          username: userData.username,
          password: userData.password,
        },
        clientIp,
        userAgent
      );

      // 设置cookie
      res.cookie('accessToken', loginResult.accessToken);

      Logger.business('create_super_admin', loginResult.user.id, {
        userId: result.userId,
        username: result.username,
      });

      return ResponseUtil.success(
        req,
        res,
        {
          user: loginResult.user,
          accessToken: loginResult.accessToken,
          refreshToken: loginResult.refreshToken,
          platform: os.platform(),
          hostname: os.hostname(),
          serverId: process.env.SERVER_ID,
        },
        'auth.SUPER_ADMIN_CREATED'
      );
    } catch (err) {
      Logger.error('Create super admin failed', err, {
        method: 'createSuperAdmin',
        username: req.body.username,
      });
      if (err.message && err.message.startsWith('auth.')) {
        return ResponseUtil.error(req, res, err.message, 400);
      }
      return ResponseUtil.serverError(req, res, err);
    }
  };

  /**
   * 用户登录
   */
  login = async (req, res) => {
    const knexMain = req.dbMain;
    try {
      const { username, password } = req.body;
      const credentials = { username, password };

      const clientIp = NetUtil.getClientIP(req);
      const userAgent = req.headers['user-agent'] || '';
      const deviceFingerprint = req.body && req.body.device_fingerprint;

      const blackRes = await checkIpBlacklisted(clientIp);
      if (blackRes && blackRes.blacklisted) {
        return await respondIpBlacklisted(req, res, blackRes);
      }

      const user = await authService.verifyCredentials({ knexMain }, credentials);
      const twofa = new TwoFAService(knexMain);
      const enabled = await twofa.isEnabled(user.id);
      const deviceInfo = await this._resolveDeviceInfo({
        knexMain,
        userId: user.id,
        deviceFingerprint,
        clientIp,
      });
      const deviceNeedTwoFactor = deviceInfo.isNew || deviceInfo.isStale;
      const needTwoFactor = enabled && deviceNeedTwoFactor;

      if (needTwoFactor) {
        const common = await this._getLoginCommonData();
        const tempToken = jwt.sign(
          {
            userId: user.id,
            username: user.username,
            type: user.type,
            tokenType: '2fa_temp',
            createTime: Date.now(),
            deviceId: deviceInfo.deviceId,
            deviceName: deviceInfo.deviceName,
          },
          process.env.JWT_SECRET,
          { expiresIn: '5m' }
        );
        Logger.business('user_login_2fa_required', user.id, {
          username: user.username,
          type: user.type,
        });
        return ResponseUtil.success(
          req,
          res,
          {
            twoFactorRequired: true,
            tempToken,
            user: { id: user.id, username: user.username, type: user.type },
            ...common,
          },
          'common.SUCCESS'
        );
      }

      const result = await authService.issueTokensForUser({ knexMain }, user, clientIp, userAgent, deviceInfo.deviceId);
      if (deviceInfo.deviceId) {
        await authService.upsertUserDevice({
          knexMain,
          userId: user.id,
          deviceId: deviceInfo.deviceId,
          deviceName: deviceInfo.deviceName,
          osVersion: deviceInfo.osVersion,
          trustedFlag: true,
        });
        await authService.trimUserDevices({ knexMain, userId: user.id, keep: 500 });
      }
      if (deviceInfo && deviceInfo.isNew) {
        await this._addNewDeviceLoginMessage({
          knexMain,
          uid: user.id,
          deviceName: deviceInfo.deviceName,
          osVersion: deviceInfo.osVersion,
        });
      }
      recordAuthSuccess(clientIp);
      res.cookie('accessToken', result.accessToken);
      Logger.business('user_login', result.user.id, {
        username: result.user.username,
        type: result.user.type,
      });
      return await this._sendLoginSuccess(req, res, result);
    } catch (err) {
      const hasSuperAdmin = await authService.hasSuperAdmin({ knexMain });
      Logger.error('User login failed', err, {
        method: 'login',
        username: req.body.username,
      });
      if (!hasSuperAdmin) {
        return ResponseUtil.error(req, res, 'auth.SYS_NO_INIT', 403);
      }
      //密码错误返回特殊错误码 前端有处理
      if (err.message && err.message.startsWith('auth.INVALID_CREDENTIALS')) {
        const clientIp = NetUtil.getClientIP(req);
        const failRes = await recordAuthFailure(clientIp, 'login');
        if (failRes && failRes.blacklisted) {
          return await respondIpBlacklisted(req, res, failRes, { recordSecurityMessage: true });
        }
        return ResponseUtil.error(req, res, err.message, ResponseUtil.CODE_PWD_ERROR);
      }
      if (err.message && err.message.startsWith('auth.USER_NOT_FOUND')) {
        const clientIp = NetUtil.getClientIP(req);
        const failRes = await recordAuthFailure(clientIp, 'login');
        if (failRes && failRes.blacklisted) {
          return await respondIpBlacklisted(req, res, failRes, { recordSecurityMessage: true });
        }
        return ResponseUtil.error(req, res, err.message, 400);
      }
      if (err.message && err.message.startsWith('auth.')) {
        return ResponseUtil.error(req, res, err.message, 400);
      }
      return ResponseUtil.serverError(req, res, err);
    }
  };

  verify2faLogin = async (req, res) => {
    const knexMain = req.dbMain;
    const clientIp = NetUtil.getClientIP(req);
    try {
      const blackRes = await checkIpBlacklisted(clientIp);
      if (blackRes && blackRes.blacklisted) {
        return await respondIpBlacklisted(req, res, blackRes);
      }

      const { tempToken, code, device_fingerprint: deviceFingerprint } = req.body || {};
      let decoded = null;
      try {
        decoded = jwt.verify(String(tempToken || ''), process.env.JWT_SECRET);
      } catch (e) {
        const failRes = await recordAuthFailure(clientIp, '2fa_login');
        if (failRes && failRes.blacklisted) {
          return await respondIpBlacklisted(req, res, failRes, { recordSecurityMessage: true });
        }
        await this._logTwofaAttempt({
          knexMain,
          userId: null,
          action: 'login',
          method: 'totp',
          clientIp,
          deviceId: null,
          ok: false,
          reasonCode: 'auth.INVALID_TOKEN',
        });
        return ResponseUtil.error(req, res, 'auth.INVALID_TOKEN', 401);
      }

      if (!decoded || decoded.tokenType !== '2fa_temp' || !decoded.userId) {
        const failRes = await recordAuthFailure(clientIp, '2fa_login');
        if (failRes && failRes.blacklisted) {
          return await respondIpBlacklisted(req, res, failRes, { recordSecurityMessage: true });
        }
        await this._logTwofaAttempt({
          knexMain,
          userId: null,
          action: 'login',
          method: 'totp',
          clientIp,
          deviceId: null,
          ok: false,
          reasonCode: 'auth.INVALID_TOKEN',
        });
        return ResponseUtil.error(req, res, 'auth.INVALID_TOKEN', 401);
      }

      const userId = Number(decoded.userId);
      const user = await knexMain('user').where({ id: userId }).first();
      if (!user) return ResponseUtil.error(req, res, 'auth.USER_NOT_FOUND', 400);

      const recentCount = await this._countRecentTwofaAttempts({
        knexMain,
        userId,
        action: 'login',
        windowMs: 60 * 1000,
      });
      if (recentCount >= 3) {
        await this._logTwofaAttempt({
          knexMain,
          userId,
          action: 'login',
          method: 'totp',
          clientIp,
          deviceId: decoded.deviceId || null,
          ok: false,
          reasonCode: 'twofa.TOO_MANY_ATTEMPTS',
        });
        await banIpForMinutes(clientIp, 1, '2fa_rate_limit');
        return ResponseUtil.error(req, res, 'twofa.TOO_MANY_ATTEMPTS', 429);
      }

      const twofa = new TwoFAService(knexMain);
      let verifyResult = null;
      try {
        verifyResult = await twofa.verifyForLogin(userId, code);
      } catch (e) {
        await this._logTwofaAttempt({
          knexMain,
          userId,
          action: 'login',
          method: 'totp',
          clientIp,
          deviceId: decoded.deviceId || null,
          ok: false,
          reasonCode: e && e.message ? String(e.message) : 'twofa.INVALID_CODE',
        });
        throw e;
      }

      let deviceId = decoded.deviceId || null;
      let deviceName = decoded.deviceName || null;
      let osVersion = null;
      let isNewDevice = false;
      if (deviceFingerprint && typeof deviceFingerprint === 'object') {
        try {
          const built = await authService.buildDeviceId(deviceFingerprint, clientIp);
          osVersion = built.payload && built.payload.os_version ? built.payload.os_version : null;
        } catch (_) {}
      }
      if (!deviceId && deviceFingerprint) {
        const resolved = await this._resolveDeviceInfo({
          knexMain,
          userId,
          deviceFingerprint,
          clientIp,
        });
        deviceId = resolved.deviceId;
        deviceName = resolved.deviceName;
        osVersion = resolved.osVersion;
        isNewDevice = resolved.isNew === true;
      }
      if (!isNewDevice && deviceId) {
        try {
          const existing = await authService.getUserDevice({ knexMain, userId, deviceId });
          isNewDevice = !existing;
        } catch (_) {}
      }
      if (deviceId) {
        await authService.upsertUserDevice({
          knexMain,
          userId,
          deviceId,
          deviceName,
          osVersion,
          trustedFlag: true,
        });
        await authService.trimUserDevices({ knexMain, userId, keep: 500 });
      }
      if (isNewDevice) {
        await this._addNewDeviceLoginMessage({
          knexMain,
          uid: userId,
          deviceName,
          osVersion,
        });
      }

      const userAgent = req.headers['user-agent'] || '';
      const result = await authService.issueTokensForUser({ knexMain }, user, clientIp, userAgent, deviceId);
      await this._logTwofaAttempt({
        knexMain,
        userId,
        action: 'login',
        method: verifyResult && verifyResult.method ? verifyResult.method : 'totp',
        clientIp,
        deviceId,
        ok: true,
        reasonCode: null,
      });
      recordAuthSuccess(clientIp);
      res.cookie('accessToken', result.accessToken);
      Logger.business('user_login_2fa_verified', userId, {
        username: user.username,
        type: user.type,
      });
      return await this._sendLoginSuccess(req, res, result);
    } catch (err) {
      Logger.error('2FA login verify failed', err, { method: 'verify2faLogin' });
      const failRes = await recordAuthFailure(clientIp, '2fa_login');
      if (failRes && failRes.blacklisted) {
        return await respondIpBlacklisted(req, res, failRes, { recordSecurityMessage: true });
      }
      if (err && err.message && String(err.message).startsWith('twofa.')) {
        return ResponseUtil.error(req, res, err.message, 400);
      }
      return ResponseUtil.error(req, res, 'common.ERROR', 400);
    }
  };

  twofaStatus = async (req, res) => {
    try {
      const uid = Number(req.user && req.user.id);
      if (!uid) return ResponseUtil.unauthorized(req, res);
      const service = new TwoFAService(req.dbMain);
      const data = await service.getStatus(uid);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message && String(e.message).startsWith('twofa.') ? e.message : 'common.ERROR';
      const status = msgKey === 'common.ERROR' ? 500 : 400;
      return ResponseUtil.error(req, res, msgKey, status);
    }
  };

  twofaSetup = async (req, res) => {
    try {
      const uid = Number(req.user && req.user.id);
      if (!uid) return ResponseUtil.unauthorized(req, res);
      const body = req.body || {};
      const issuer = body.issuer ? String(body.issuer) : 'NasCabOS';
      const accountName = body.accountName ? String(body.accountName) : req.user && req.user.username ? String(req.user.username) : String(uid);

      const service = new TwoFAService(req.dbMain);
      const secretData = await service.generateSecret(uid, { issuer, accountName });
      const qr = await service.getQrCodeDataUrl(uid, { accountName });
      return ResponseUtil.success(req, res, { ...secretData, qrDataUrl: qr.dataUrl }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message && String(e.message).startsWith('twofa.') ? e.message : 'common.ERROR';
      const status = msgKey === 'common.ERROR' ? 500 : 400;
      return ResponseUtil.error(req, res, msgKey, status);
    }
  };

  twofaEnable = async (req, res) => {
    try {
      const uid = Number(req.user && req.user.id);
      if (!uid) return ResponseUtil.unauthorized(req, res);
      const code = req.body && req.body.code;
      const secret = req.body && req.body.secret;
      const service = new TwoFAService(req.dbMain);
      const data = await service.enable(uid, code, { secret });

      const clientIp = NetUtil.getClientIP(req);
      const deviceFingerprint = req.body && req.body.device_fingerprint;
      let deviceInfo = { deviceId: null, deviceName: null, osVersion: null };
      try {
        const resolved = await this._resolveDeviceInfo({
          knexMain: req.dbMain,
          userId: uid,
          deviceFingerprint,
          clientIp,
        });
        deviceInfo = {
          deviceId: resolved.deviceId,
          deviceName: resolved.deviceName,
          osVersion: resolved.osVersion,
        };
      } catch (_) {}

      await req.dbMain.transaction(async trx => {
        await trx('user_device').where({ user_id: uid }).del();
        if (deviceInfo.deviceId) {
          await authService.upsertUserDevice({
            knexMain: trx,
            userId: uid,
            deviceId: deviceInfo.deviceId,
            deviceName: deviceInfo.deviceName,
            osVersion: deviceInfo.osVersion,
            trustedFlag: true,
          });
        }
      });

      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message && String(e.message).startsWith('twofa.') ? e.message : 'common.ERROR';
      const status = msgKey === 'common.ERROR' ? 500 : 400;
      return ResponseUtil.error(req, res, msgKey, status);
    }
  };

  twofaDisable = async (req, res) => {
    try {
      const uid = Number(req.user && req.user.id);
      if (!uid) return ResponseUtil.unauthorized(req, res);
      const code = req.body && req.body.code;
      const service = new TwoFAService(req.dbMain);
      await service.disable(uid, code);
      return ResponseUtil.success(req, res, { disabled: true }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message && String(e.message).startsWith('twofa.') ? e.message : 'common.ERROR';
      const status = msgKey === 'common.ERROR' ? 500 : 400;
      return ResponseUtil.error(req, res, msgKey, status);
    }
  };

  twofaRotateBackupCodes = async (req, res) => {
    try {
      const uid = Number(req.user && req.user.id);
      if (!uid) return ResponseUtil.unauthorized(req, res);
      const code = req.body && req.body.code;
      const service = new TwoFAService(req.dbMain);
      await service.verifyForLogin(uid, code);
      const backupCodes = await service.generateBackupCodes(uid, { count: 10 });
      return ResponseUtil.success(req, res, { backupCodes }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message && String(e.message).startsWith('twofa.') ? e.message : 'common.ERROR';
      const status = msgKey === 'common.ERROR' ? 500 : 400;
      return ResponseUtil.error(req, res, msgKey, status);
    }
  };

  /**
   * 刷新JWT token
   */
  refreshJwt = async (req, res) => {
    try {
      // 从请求中获取refresh token
      let refreshToken = req.body.refreshToken || req.cookies.refreshToken;

      if (!refreshToken) {
        return ResponseUtil.error(req, res, 'auth.REFRESH_TOKEN_MISSING', 401);
      }

      const knexMain = req.dbMain;
      const result = await authService.refreshToken({ knexMain }, refreshToken);

      // 设置新的cookie
      res.cookie('accessToken', result.accessToken);

      Logger.business('token_refresh', result.user.id, {
        username: result.user.username,
      });

      // 计算token过期时间戳
      const now = Math.floor(Date.now() / 1000);
      const expiresInSeconds = TimeUtil.parseExpiresIn(config.jwt.accessTokenExpiresIn);
      const expiresIn = now + expiresInSeconds;
      const returnData = {
        serverId: process.env.SERVER_ID,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken, // 返回新的刷新token
        expiresIn: expiresIn, // 返回token过期时间戳
        user: result.user,
      };
      return ResponseUtil.success(req, res, returnData, 'auth.TOKEN_REFRESH_SUCCESS');
    } catch (err) {
      Logger.error('JWT refresh failed', err, { method: 'refreshJwt', clientIp: NetUtil.getClientIP(req) });

      if (err.name === 'TokenExpiredError' || err.name === 'JsonWebTokenError') {
        // 清除无效的cookie
        res.clearCookie('accessToken');
        res.clearCookie('refreshToken');

        return ResponseUtil.error(req, res, 'auth.REFRESH_TOKEN_INVALID', 401);
      }

      if (err.message && err.message.startsWith('auth.')) {
        return ResponseUtil.error(req, res, err.message, 401);
      }

      return ResponseUtil.serverError(req, res, err);
    }
  };

  /**
   * 获取找回密码所需信息（按用户名，无需权限）
   */
  getRecoverInfo = async (req, res) => {
    try {
      const clientIp = NetUtil.getClientIP(req);
      if (!NetUtil.isPrivateIP(clientIp)) {
        Logger.warn('Non-LAN getRecoverInfo attempt', {
          method: 'getRecoverInfo',
          clientIp,
        });
        return ResponseUtil.error(req, res, 'auth.PRIVATE_NETWORK_ONLY_OPERATION', 403);
      }

      const knexMain = req.dbMain;
      const username = (req.query.username || '').trim();
      const result = await authService.getRecoverInfo({ knexMain }, { username });

      Logger.business('get_recover_info', null, {
        username,
      });

      return ResponseUtil.success(req, res, result, 'auth.RECOVER_INFO_FETCH_SUCCESS');
    } catch (err) {
      Logger.error('getRecoverInfo failed', err, { method: 'getRecoverInfo' });
      if (err.message && err.message.startsWith('auth.')) {
        return ResponseUtil.error(req, res, err.message, 400);
      }
      return ResponseUtil.error(req, res, 'auth.RECOVER_INFO_FETCH_FAILED', 400);
    }
  };

  /**
   * 找回用户密码（仅局域网）
   */
  recoverPassword = async (req, res) => {
    try {
      const clientIp = NetUtil.getClientIP(req);
      const isPrivateIP = NetUtil.isPrivateIP(clientIp);
      if (!isPrivateIP) {
        Logger.warn('Non-LAN password recovery attempt', {
          method: 'recoverPassword',
          clientIp,
          isPrivateIP,
        });
        return ResponseUtil.error(req, res, 'auth.PRIVATE_NETWORK_ONLY_OPERATION', 403);
      }

      const blackRes = await checkIpBlacklisted(clientIp);
      if (blackRes && blackRes.blacklisted) {
        return await respondIpBlacklisted(req, res, blackRes);
      }

      const { username, answer, newPassword } = req.body;
      const knexMain = req.dbMain;

      const result = await authService.recoverUserPassword(
        { knexMain },
        {
          username,
          answer,
          newPassword,
          code: req.body && req.body.code,
          device_fingerprint: req.body && req.body.device_fingerprint,
          clientIp,
        }
      );

      Logger.business('recover_password', result.userId, {
        username: result.username,
      });
      recordAuthSuccess(clientIp);

      return ResponseUtil.success(req, res, { userId: result.userId, username: result.username }, 'auth.PASSWORD_RESET_SUCCESS');
    } catch (err) {
      Logger.error('Password recovery failed', err, {
        method: 'recoverPassword',
        username: req.body.username,
      });
      if (err && err.message && String(err.message).startsWith('twofa.')) {
        const status = err.message === 'twofa.TWO_FACTOR_REQUIRED' ? 401 : 400;
        return ResponseUtil.error(req, res, err.message, status);
      }
      if (err.message && err.message.startsWith('auth.')) {
        const clientIp = NetUtil.getClientIP(req);
        const failRes = await recordAuthFailure(clientIp, 'recover');
        if (failRes && failRes.blacklisted) {
          return await respondIpBlacklisted(req, res, failRes, { recordSecurityMessage: true });
        }
        return ResponseUtil.error(req, res, err.message, 400);
      }
      return ResponseUtil.error(req, res, 'auth.PASSWORD_RESET_FAILED', 400);
    }
  };

  /**
   * 用户退出登录
   */
  logout = async (req, res) => {
    try {
      const refreshToken = req.cookies.refreshToken || req.body.refreshToken;

      // 如果有refreshToken，调用service将其失效
      if (refreshToken) {
        const knexMain = req.dbMain;
        await authService.logout({ knexMain }, refreshToken);
      }

      // 清除cookie
      res.clearCookie('accessToken');
      res.clearCookie('refreshToken');

      Logger.business('user_logout', req.user.id, {
        username: req.user.username,
      });

      return ResponseUtil.success(req, res, null, 'auth.LOGOUT_SUCCESS');
    } catch (err) {
      Logger.error('Logout failed', err, {
        method: 'logout',
        userId: req.user?.userId,
      });

      if (err.message && err.message.startsWith('auth.')) {
        return ResponseUtil.error(req, res, err.message, 400);
      }

      return ResponseUtil.serverError(req, res, err);
    }
  };

  /**
   * 获取当前用户信息
   */
  getProfile = async (req, res) => {
    try {
      const knexMain = req.dbMain;

      const user = await authService.getUserProfile({ knexMain }, req.user.id);

      Logger.business('get_user_profile', req.user.id, {
        username: user.username,
      });

      return ResponseUtil.success(req, res, { user }, 'auth.PROFILE_FETCH_SUCCESS');
    } catch (err) {
      Logger.error('Get user profile failed', err, {
        method: 'getProfile',
        userId: req.user.id,
      });

      if (err.message === 'auth.USER_NOT_FOUND') {
        return ResponseUtil.notFound(req, res, 'USER');
      }

      if (err.message && err.message.startsWith('auth.')) {
        return ResponseUtil.error(req, res, err.message, 400);
      }

      return ResponseUtil.serverError(req, res, err);
    }
  };

  listDevices = async (req, res) => {
    try {
      const uid = Number(req.user && req.user.id);
      if (!uid) return ResponseUtil.unauthorized(req, res);
      const knexMain = req.dbMain;
      const devices = await authService.listUserDevices({ knexMain, userId: uid, limit: 10 });
      return ResponseUtil.success(req, res, { items: devices }, 'common.SUCCESS', 200);
    } catch (err) {
      Logger.error('List devices failed', err, {
        method: 'listDevices',
        userId: req.user && req.user.id,
      });
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  };

  kickDevice = async (req, res) => {
    try {
      const uid = Number(req.user && req.user.id);
      if (!uid) return ResponseUtil.unauthorized(req, res);
      const deviceId = req.body && req.body.deviceId ? String(req.body.deviceId).trim() : '';
      if (!deviceId) return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      const knexMain = req.dbMain;
      await authService.invalidateTokensForDevice({ knexMain, userId: uid, deviceId });
      await authService.removeUserDevice({ knexMain, userId: uid, deviceId });
      return ResponseUtil.success(req, res, { removed: true }, 'common.SUCCESS', 200);
    } catch (err) {
      Logger.error('Kick device failed', err, {
        method: 'kickDevice',
        userId: req.user && req.user.id,
      });
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  };

  /**
   * 获取在线用户列表
   */
  getOnlineUsers = async (req, res) => {
    try {
      // 检查权限（仅超级管理员）
      if (!userUtil.isSuperAdmin(req.user)) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }

      const knexMain = req.dbMain;
      const users = await authService.getOnlineUsers({ knexMain });

      return ResponseUtil.success(req, res, { users }, 'auth.ONLINE_USERS_FETCH_SUCCESS');
    } catch (err) {
      Logger.error('List online users failed', err, {
        method: 'getOnlineUsers',
        userId: req.user.id,
      });
      if (err.message && err.message.startsWith('auth.')) {
        return ResponseUtil.error(req, res, err.message, 400);
      }
      return ResponseUtil.serverError(req, res, err);
    }
  };
}

module.exports = new AuthController();
