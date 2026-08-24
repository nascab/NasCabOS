const ResponseUtil = require('../../apiUtils/responseUtil');
const UserService = require('./userService');
const jwt = require('jsonwebtoken');
const config = require('../../../config/config');
const NetUtil = require('../../../utils/netUtil');
const UAUtil = require('../../../utils/uaUtil');
const Logger = require('../../../utils/logger');
const { hasPermission } = require('../../../utils/permissionUtil');
const { TwoFAService } = require('../auth/2fa/twofaService');
const authService = require('../auth/authService');
const tableConfig = require('../../../db/table/tableConfig');
const fileService = require('../file/core/fileService');

/**
 * 控制器：封装HTTP与响应行为，调用业务服务
 */
function normalizeAnyOrArray(value) {
  if (value === undefined || value === null) return 'ANY';
  if (value === 'ANY') return 'ANY';
  if (Array.isArray(value)) {
    const list = value.map(v => String(v || '').trim()).filter(Boolean);
    return list.length > 0 ? list : 'ANY';
  }
  if (typeof value === 'string') {
    const text = value.trim();
    if (!text) return 'ANY';
    if (text === 'ANY') return 'ANY';
    try {
      const parsed = JSON.parse(text);
      if (Array.isArray(parsed)) {
        const list = parsed.map(v => String(v || '').trim()).filter(Boolean);
        return list.length > 0 ? list : 'ANY';
      }
    } catch (_) {}
    return [text];
  }
  return 'ANY';
}

function encodeAnyOrArray(value) {
  if (value === 'ANY') return 'ANY';
  if (!Array.isArray(value)) return 'ANY';
  return JSON.stringify(value);
}

class UserController {
  constructor() {
    this.listUsers = this.listUsers.bind(this);
    this.createUser = this.createUser.bind(this);
    this.updateUser = this.updateUser.bind(this);
    this.deleteUsers = this.deleteUsers.bind(this);
    this.getUserPermissions = this.getUserPermissions.bind(this);
    this.setUserPermissions = this.setUserPermissions.bind(this);
    this.getLoginRecords = this.getLoginRecords.bind(this);
    this.getUser2faStatus = this.getUser2faStatus.bind(this);
    this.setupUser2fa = this.setupUser2fa.bind(this);
    this.enableUser2fa = this.enableUser2fa.bind(this);
    this.resetUser2fa = this.resetUser2fa.bind(this);
    this.createScopedToken = this.createScopedToken.bind(this);
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

  async _ensureOperatorTwofaVerified(req, { always = false } = {}) {
    const knexMain = req.dbMain;
    const operatorId = Number(req.user && req.user.id);
    if (!operatorId) throw new Error('common.UNAUTHORIZED');

    const twofa = new TwoFAService(knexMain);
    const enabled = await twofa.isEnabled(operatorId);
    if (!enabled) return { required: false, verified: false };

    const clientIp = NetUtil.getClientIP(req);
    const deviceFingerprint = req.body && req.body.device_fingerprint;
    let deviceInfo = null;
    try {
      deviceInfo = await this._resolveDeviceInfo({
        knexMain,
        userId: operatorId,
        deviceFingerprint,
        clientIp,
      });
    } catch (e) {
      Logger.error('operator_2fa_resolve_device_failed', e, {
        operatorId,
        hasDeviceFingerprint: !!deviceFingerprint,
      });
      deviceInfo = { deviceId: null, deviceName: null, osVersion: null, device: null, isNew: true, isStale: false };
    }
    const needTwoFactor = always ? true : deviceInfo.isNew || deviceInfo.isStale;
    Logger.info('operator_2fa_check', {
      op: 'user',
      operatorId,
      always,
      enabled,
      isNew: deviceInfo.isNew,
      isStale: deviceInfo.isStale,
      needTwoFactor,
      hasCode: !!(req.body && req.body.code),
      hasDeviceFingerprint: !!deviceFingerprint,
      deviceId: deviceInfo.deviceId ? String(deviceInfo.deviceId).slice(0, 12) : null,
    });
    if (!needTwoFactor) return { required: false, verified: false };

    const code = req.body && req.body.code;
    if (!code) throw new Error('twofa.TWO_FACTOR_REQUIRED');
    await twofa.verifyForLogin(operatorId, code);

    if (deviceInfo.deviceId) {
      await authService.upsertUserDevice({
        knexMain,
        userId: operatorId,
        deviceId: deviceInfo.deviceId,
        deviceName: deviceInfo.deviceName,
        osVersion: deviceInfo.osVersion,
        trustedFlag: true,
      });
      await authService.trimUserDevices({ knexMain, userId: operatorId, keep: 500 });
    }

    return { required: true, verified: true };
  }

  async listUsers(req, res) {
    try {
      const service = new UserService(req.dbMain);
      const { page = 1, limit = 20, keyword = '' } = req.body || {};
      const result = await service.listUsers(Number(page), Number(limit), String(keyword));
      return ResponseUtil.paginated(req, res, result.items, result.total, result.page, result.limit);
    } catch (err) {
      return ResponseUtil.error(req, res, 'user.USER_LIST_FETCH_FAILED', 500);
    }
  }

  async createUser(req, res) {
    try {
      await this._ensureOperatorTwofaVerified(req, { always: false });
      const service = new UserService(req.dbMain);
      const payload = req.body;
      const user = await service.createUser(payload);
      return ResponseUtil.success(req, res, user, 'user.USER_CREATE_SUCCESS', 201);
    } catch (err) {
      Logger.error('user_create_failed', err, {
        method: 'createUser',
        operatorId: req.user && req.user.id,
      });
      if (err && err.message && String(err.message).startsWith('twofa.')) {
        const status = err.message === 'twofa.TWO_FACTOR_REQUIRED' ? 401 : 400;
        return ResponseUtil.error(req, res, err.message, status);
      }
      if (err && err.message && String(err.message).startsWith('common.')) {
        const status = err.message === 'common.UNAUTHORIZED' ? 401 : 400;
        return ResponseUtil.error(req, res, err.message, status);
      }
      const msgKey = err.message && err.message.startsWith('user.') ? err.message : 'user.USER_CREATE_FAILED';
      return ResponseUtil.error(req, res, msgKey, 400);
    }
  }

  async updateUser(req, res) {
    try {
      await this._ensureOperatorTwofaVerified(req, { always: false });
      const service = new UserService(req.dbMain);
      const id = Number(req.params.id);
      const payload = req.body;
      await service.updateUser(id, payload);
      const hasUsernameChange = typeof payload?.username === 'string' && payload.username.trim().length > 0;
      const hasPasswordChange = typeof payload?.password === 'string' && payload.password.trim().length > 0;
      if (hasUsernameChange || hasPasswordChange) {
        const target = await req.dbMain('user').where({ id }).select('type').first();
        if (target && target.type === 'super_admin') {
          await tableConfig.deleteConfigByKey(tableConfig.KEY_IS_INITIAL_ADMIN, 0);
        }
      }
      return ResponseUtil.success(req, res, null, 'user.USER_UPDATE_SUCCESS', 200);
    } catch (err) {
      Logger.error('user_update_failed', err, {
        method: 'updateUser',
        operatorId: req.user && req.user.id,
        targetUserId: req.params && req.params.id,
      });
      if (err && err.message && String(err.message).startsWith('twofa.')) {
        const status = err.message === 'twofa.TWO_FACTOR_REQUIRED' ? 401 : 400;
        return ResponseUtil.error(req, res, err.message, status);
      }
      if (err && err.message && String(err.message).startsWith('common.')) {
        const status = err.message === 'common.UNAUTHORIZED' ? 401 : 400;
        return ResponseUtil.error(req, res, err.message, status);
      }
      const msgKey = err.message && err.message.startsWith('user.') ? err.message : 'user.USER_UPDATE_FAILED';
      return ResponseUtil.error(req, res, msgKey, 400);
    }
  }

  async deleteUsers(req, res) {
    try {
      await this._ensureOperatorTwofaVerified(req, { always: false });
      const service = new UserService(req.dbMain);
      const { ids = [] } = req.body;
      const affected = await service.deleteUsers(ids, {
        dbMain: req.dbMain,
        dbVideo: req.dbVideo,
        dbBook: req.dbBook,
        dbMusic: req.dbMusic,
        dbFile: req.dbFile,
        dbPhoto: req.dbPhoto,
        dbGeo: req.dbGeo,
      });
      return ResponseUtil.success(req, res, { affected }, 'user.USER_DELETE_SUCCESS', 200);
    } catch (err) {
      Logger.error('user_delete_failed', err, {
        method: 'deleteUsers',
        operatorId: req.user && req.user.id,
      });
      if (err && err.message && String(err.message).startsWith('twofa.')) {
        const status = err.message === 'twofa.TWO_FACTOR_REQUIRED' ? 401 : 400;
        return ResponseUtil.error(req, res, err.message, status);
      }
      if (err && err.message && String(err.message).startsWith('common.')) {
        const status = err.message === 'common.UNAUTHORIZED' ? 401 : 400;
        return ResponseUtil.error(req, res, err.message, status);
      }
      const msgKey = err.message && err.message.startsWith('user.') ? err.message : 'user.USER_DELETE_FAILED';
      return ResponseUtil.error(req, res, msgKey, 400);
    }
  }

  async getUserPermissions(req, res) {
    try {
      const service = new UserService(req.dbMain);
      const uid = Number((req.body && req.body.uid) || req.params.uid);
      const list = await service.getUserPermissions(uid);
      return ResponseUtil.success(req, res, list, 'permission.PERMISSION_LIST_FETCH_SUCCESS', 200);
    } catch (err) {
      return ResponseUtil.error(req, res, 'permission.PERMISSION_LIST_FETCH_FAILED', 500);
    }
  }

  async setUserPermissions(req, res) {
    try {
      const service = new UserService(req.dbMain);
      const uid = Number(req.params.uid);
      const { permissions = [] } = req.body;
      await service.setUserPermissions(uid, permissions);
      return ResponseUtil.success(req, res, null, 'permission.PERMISSION_SET_SUCCESS', 200);
    } catch (err) {
      const msgKey = err.message && err.message.startsWith('permission.') ? err.message : 'permission.PERMISSION_SET_FAILED';
      if (err.args) {
        return ResponseUtil.errorWithArgs(req, res, msgKey, err.args, 400);
      }
      return ResponseUtil.error(req, res, msgKey, 400);
    }
  }

  async getLoginRecords(req, res) {
    try {
      const service = new UserService(req.dbMain);
      const { uid, page = 1, limit = 20 } = req.body || {};
      const result = await service.getLoginRecords(Number(uid), Number(page), Number(limit));
      return ResponseUtil.paginated(req, res, result.items, result.total, result.page, result.limit);
    } catch (err) {
      return ResponseUtil.error(req, res, 'user.LOGIN_RECORDS_FETCH_FAILED', 500);
    }
  }

  async getUserFileLogs(req, res) {
    try {
      const { uid, types, page = 1, pageSize = 20, stateList, keyword } = req.body || {};
      const logs = await fileService.getFileLogs(Number(uid), types, Number(page), Number(pageSize), stateList, keyword);
      return ResponseUtil.success(req, res, logs, 'file.LOG_LIST_SUCCESS', 200);
    } catch (err) {
      return ResponseUtil.error(req, res, 'file.LOG_LIST_FAILED', 400, { error: err.message });
    }
  }

  async getUser2faStatus(req, res) {
    try {
      const uid = Number(req.body && req.body.uid);
      if (!uid) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      const service = new TwoFAService(req.dbMain);
      const data = await service.getStatus(uid);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message && String(e.message).startsWith('twofa.') ? e.message : 'common.ERROR';
      const status = msgKey === 'common.ERROR' ? 500 : 400;
      return ResponseUtil.error(req, res, msgKey, status);
    }
  }

  async setupUser2fa(req, res) {
    try {
      const uid = Number(req.body && req.body.uid);
      if (!uid) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const user = await req.dbMain('user').where({ id: uid }).first();
      if (!user) return ResponseUtil.error(req, res, 'auth.USER_NOT_FOUND', 400);

      const issuer = req.body && req.body.issuer ? String(req.body.issuer) : 'NasCabOS';
      const accountName = req.body && req.body.accountName ? String(req.body.accountName) : String(user.username || uid);

      const service = new TwoFAService(req.dbMain);
      const secretData = await service.generateSecret(uid, { issuer, accountName });
      const qr = await service.getQrCodeDataUrl(uid, { accountName });
      return ResponseUtil.success(req, res, { ...secretData, qrDataUrl: qr.dataUrl }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message && String(e.message).startsWith('twofa.') ? e.message : 'common.ERROR';
      const status = msgKey === 'common.ERROR' ? 500 : 400;
      return ResponseUtil.error(req, res, msgKey, status);
    }
  }

  async enableUser2fa(req, res) {
    try {
      const uid = Number(req.body && req.body.uid);
      if (!uid) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      const code = req.body && req.body.code;
      const secret = req.body && req.body.secret;
      const service = new TwoFAService(req.dbMain);
      const data = await service.enable(uid, code, { secret });

      await req.dbMain.transaction(async trx => {
        await trx('user_device').where({ user_id: uid }).del();

        const operatorId = Number(req.user && req.user.id);
        if (operatorId === uid) {
          const clientIp = NetUtil.getClientIP(req);
          const deviceFingerprint = req.body && req.body.device_fingerprint;
          let deviceInfo = null;
          try {
            deviceInfo = await this._resolveDeviceInfo({
              knexMain: trx,
              userId: uid,
              deviceFingerprint,
              clientIp,
            });
          } catch (_) {
            deviceInfo = null;
          }
          if (deviceInfo && deviceInfo.deviceId) {
            await authService.upsertUserDevice({
              knexMain: trx,
              userId: uid,
              deviceId: deviceInfo.deviceId,
              deviceName: deviceInfo.deviceName,
              osVersion: deviceInfo.osVersion,
              trustedFlag: true,
            });
          }
        }
      });

      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message && String(e.message).startsWith('twofa.') ? e.message : 'common.ERROR';
      const status = msgKey === 'common.ERROR' ? 500 : 400;
      return ResponseUtil.error(req, res, msgKey, status);
    }
  }

  async resetUser2fa(req, res) {
    try {
      const uid = Number(req.body && req.body.uid);
      if (!uid) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      await this._ensureOperatorTwofaVerified(req, { always: true });
      const service = new TwoFAService(req.dbMain);
      await service.adminReset(uid);
      return ResponseUtil.success(req, res, { reset: true }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message && String(e.message).startsWith('twofa.') ? e.message : 'common.ERROR';
      const status = msgKey === 'common.ERROR' ? 500 : msgKey === 'twofa.TWO_FACTOR_REQUIRED' ? 401 : 400;
      return ResponseUtil.error(req, res, msgKey, status);
    }
  }

  async createScopedToken(req, res) {
    try {
      const uid = Number(req.user && req.user.id);
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const { allow_api, allow_path, expiresIn } = req.body || {};
      const allowApi = normalizeAnyOrArray(allow_api);
      const allowPath = normalizeAnyOrArray(allow_path);

      if (Array.isArray(allowPath)) {
        for (const p of allowPath) {
          const ok = await hasPermission(req.dbMain, req.user, ['view', 'download', 'update', 'delete', 'upload'], p);
          if (!ok) {
            return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
          }
        }
      }

      const tokenExpiresIn = expiresIn || config.jwt.accessTokenExpiresIn;

      const accessToken = jwt.sign(
        {
          userId: uid,
          username: req.user && req.user.username ? req.user.username : '',
          type: req.user && req.user.type ? req.user.type : '',
          tokenType: 'scoped',
          createTime: Date.now(),
        },
        process.env.JWT_SECRET,
        { expiresIn: tokenExpiresIn }
      );

      const decoded = jwt.decode(accessToken);
      const expireTime = decoded && decoded.exp ? new Date(decoded.exp * 1000) : new Date(Date.now() + 15 * 60 * 1000);

      const clientIp = NetUtil.getClientIP(req);
      const userAgent = req.headers['user-agent'] || '';
      const { browser, os, deviceInfo } = UAUtil.parse(userAgent);

      await req.dbMain('user_token').insert({
        user_id: uid,
        token: accessToken,
        client_ip: clientIp,
        device_info: deviceInfo,
        browser,
        os,
        is_valid: true,
        expire_time: expireTime,
        create_time: new Date(),
        last_active_time: new Date(),
        type: 'scoped',
        allow_path: encodeAnyOrArray(allowPath),
        allow_api: encodeAnyOrArray(allowApi),
      });

      const now = Math.floor(Date.now() / 1000);
      const expiresInTs = decoded && decoded.exp ? decoded.exp : now;

      return ResponseUtil.success(
        req,
        res,
        {
          accessToken,
          expiresIn: expiresInTs,
          allow_api: allowApi,
          allow_path: allowPath,
        },
        'user.SCOPED_TOKEN_CREATE_SUCCESS',
        201
      );
    } catch (err) {
      return ResponseUtil.error(req, res, 'user.SCOPED_TOKEN_CREATE_FAILED', 500);
    }
  }
}

module.exports = new UserController();
