const config = require('../../../config/config');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const tableUser = require('../../../db/table/tableUser');
const tableConfig = require('../../../db/table/tableConfig');
const UAUtil = require('../../../utils/uaUtil');
const TimeUtil = require('../../../utils/timeUtil');
const jwtUtil = require('../../../utils/jwtUtil');
const AppsService = require('../others/apps/appsService');
const AppearanceService = require('../others/appearance/appearanceService');
const fs = require('fs');
const path = require('path');
const NetUtil = require('../../../utils/netUtil');
const userUtil = require('../../../utils/userUtil');
const { TwoFAService } = require('./2fa/twofaService');

class AuthService {
  constructor() {
    this.appsService = new AppsService();
    this.appearanceService = new AppearanceService();
  }

  /**
   * 检查是否存在超级管理员
   */
  async hasSuperAdmin({ knexMain }) {
    try {
      const result = await knexMain('user').where({ type: tableUser.TYPE_SUPER_ADMIN }).first();

      return result ? true : false;
    } catch (error) {
      throw new Error('auth.SUPER_ADMIN_CHECK_FAILED');
    }
  }

  /**
   * 创建超级管理员
   * @param {Object} userData - 用户数据
   */
  async createSuperAdmin({ knexMain }, userData) {
    try {
      const { username, password, question, answer } = userData;

      // 检查是否已经存在超级管理员
      const hasSuperAdmin = await this.hasSuperAdmin({ knexMain });
      if (hasSuperAdmin) {
        throw new Error('auth.SUPER_ADMIN_EXISTS');
      }

      // 检查用户名是否已存在
      const existingUser = await knexMain('user').where({ username }).first();

      if (existingUser) {
        throw new Error('auth.USERNAME_EXISTS');
      }

      // 加密密码
      const passwordPlain = jwtUtil.decodeClientPassword(password);
      const encryptedPassword = jwtUtil.encryptPassword(passwordPlain);
      // 加密问题答案
      const hashedAnswer = await bcrypt.hash(answer, 10);
      // 创建用户
      const [userId] = await knexMain('user').insert({
        username,
        password: encryptedPassword,
        question,
        answer: hashedAnswer,
        type: tableUser.TYPE_SUPER_ADMIN,
        create_time: new Date(),
      });

      return { userId, username, type: tableUser.TYPE_SUPER_ADMIN };
    } catch (error) {
      if (error.message.startsWith('auth.')) throw error;
      throw new Error('auth.SUPER_ADMIN_CREATE_FAILED');
    }
  }

  /**
   * 用户登录
   * @param {Object} credentials - 登录凭据
   * @param {string} ip - 客户端IP
   * @param {string} userAgent - 客户端User-Agent
   */
  async verifyCredentials({ knexMain }, credentials) {
    try {
      const { username, password } = credentials;
      const passwordPlain = jwtUtil.decodeClientPassword(password);

      // 查找用户
      const user = await knexMain('user').where({ username }).first();

      if (!user) {
        throw new Error('auth.USER_NOT_FOUND');
      }

      // 验证密码
      const isPasswordValid = await jwtUtil.verifyPassword(passwordPlain, user.password);
      if (!isPasswordValid) {
        throw new Error('auth.INVALID_CREDENTIALS');
      }
      if (!jwtUtil.isEncryptedPassword(user.password)) {
        const encryptedPassword = jwtUtil.encryptPassword(passwordPlain);
        await knexMain('user').where({ id: user.id }).update({ password: encryptedPassword });
      }
      return user;
    } catch (error) {
      if (error.message.startsWith('auth.')) throw error;
      throw new Error('auth.LOGIN_FAILED');
    }
  }

  async issueTokensForUser({ knexMain }, user, ip, userAgent, deviceId = null) {
    try {
      // 生成JWT令牌
      const accessToken = jwt.sign(
        {
          userId: user.id,
          username: user.username,
          type: user.type,
          createTime: Date.now(),
          tokenType: 'access',
        },
        process.env.JWT_SECRET,
        { expiresIn: config.jwt.accessTokenExpiresIn }
      );

      const refreshToken = jwt.sign(
        {
          userId: user.id,
          tokenType: 'refresh', // 明确标识这是刷新token
          createTime: Date.now(),
        },
        process.env.JWT_SECRET,
        {
          expiresIn: config.jwt.refreshTokenExpiresIn,
        }
      );

      // 解析UA信息
      const { browser, os, deviceInfo } = UAUtil.parse(userAgent);

      // 计算过期时间
      const expiresInSeconds = TimeUtil.parseExpiresIn(config.jwt.refreshTokenExpiresIn);
      const expireTime = new Date(Date.now() + expiresInSeconds * 1000);

      // 存储会话信息到数据库（refresh + access 均入库，便于服务端校验）
      await knexMain('user_token').insert({
        user_id: user.id,
        token: refreshToken,
        client_ip: ip,
        device_info: deviceInfo,
        browser: browser,
        os: os,
        device_id: deviceId,
        is_valid: true,
        expire_time: expireTime,
        create_time: new Date(),
        last_active_time: new Date(),
        type: 'login', // 登录 refresh token
      });

      const accessExpiresInSeconds = TimeUtil.parseExpiresIn(config.jwt.accessTokenExpiresIn);
      const accessExpireTime = new Date(Date.now() + accessExpiresInSeconds * 1000);
      await knexMain('user_token').insert({
        user_id: user.id,
        token: accessToken,
        client_ip: ip,
        device_info: deviceInfo,
        browser: browser,
        os: os,
        device_id: deviceId,
        is_valid: true,
        expire_time: accessExpireTime,
        create_time: new Date(),
        last_active_time: new Date(),
        type: 'access',
      });

      const result = {
        accessToken,
        refreshToken,
        user: {
          id: user.id,
          username: user.username,
          type: user.type,
          phone: user.phone,
          language: user.language,
          avatar: user.avatar,
        },
      };
      return result;
    } catch (error) {
      if (error.message.startsWith('auth.')) throw error;
      throw new Error('auth.LOGIN_FAILED');
    }
  }

  async login({ knexMain }, credentials, ip, userAgent, deviceId = null) {
    const user = await this.verifyCredentials({ knexMain }, credentials);
    return await this.issueTokensForUser({ knexMain }, user, ip, userAgent, deviceId);
  }

  /**
   * 刷新JWT令牌
   * @param {string} refreshToken - 刷新令牌
   */
  async refreshToken({ knexMain }, refreshToken) {
    try {
      const decoded = jwt.verify(refreshToken, process.env.JWT_SECRET);
      // 验证token类型
      if (decoded.tokenType !== 'refresh') {
        throw new Error('auth.INVALID_TOKEN');
      }
      // 验证token是否在数据库中且有效
      const tokenRecord = await knexMain('user_token').where({ token: refreshToken, is_valid: true }).first();

      if (!tokenRecord) {
        throw new Error('auth.REFRESH_TOKEN_INVALID');
      }

      // 查找用户
      const user = await knexMain('user').where({ id: decoded.userId }).first();

      if (!user) {
        throw new Error('auth.USER_NOT_FOUND');
      }

      // 生成新的访问令牌
      const newAccessToken = jwt.sign(
        {
          userId: user.id,
          username: user.username,
          type: user.type,
        },
        process.env.JWT_SECRET,
        { expiresIn: config.jwt.accessTokenExpiresIn }
      );

      // 滚动刷新：生成新的刷新令牌
      const newRefreshToken = jwt.sign(
        {
          userId: user.id,
          tokenType: 'refresh', // 明确标识这是刷新token
        },
        process.env.JWT_SECRET,
        {
          expiresIn: config.jwt.refreshTokenExpiresIn,
        }
      );

      // 计算新token的过期时间
      const expiresInSeconds = TimeUtil.parseExpiresIn(config.jwt.refreshTokenExpiresIn);
      const expireTime = new Date(Date.now() + expiresInSeconds * 1000);

      // 事务操作：标记旧会话 token 无效，插入新 refresh + access
      const accessExpiresInSeconds = TimeUtil.parseExpiresIn(config.jwt.accessTokenExpiresIn);
      const accessExpireTime = new Date(Date.now() + accessExpiresInSeconds * 1000);

      await knexMain.transaction(async trx => {
        // 按同一会话（user_id + device_id）使旧 token 失效，便于登出时一并失效
        await trx('user_token').where({ user_id: user.id, device_id: tokenRecord.device_id }).update({ is_valid: false });

        await trx('user_token').insert({
          user_id: user.id,
          token: newRefreshToken,
          client_ip: tokenRecord.client_ip,
          device_info: tokenRecord.device_info,
          browser: tokenRecord.browser,
          os: tokenRecord.os,
          device_id: tokenRecord.device_id,
          is_valid: true,
          expire_time: expireTime,
          create_time: new Date(),
          last_active_time: new Date(),
          type: 'refresh',
        });

        await trx('user_token').insert({
          user_id: user.id,
          token: newAccessToken,
          client_ip: tokenRecord.client_ip,
          device_info: tokenRecord.device_info,
          browser: tokenRecord.browser,
          os: tokenRecord.os,
          device_id: tokenRecord.device_id,
          is_valid: true,
          expire_time: accessExpireTime,
          create_time: new Date(),
          last_active_time: new Date(),
          type: 'access',
        });
      });

      return {
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
        user: {
          id: user.id,
          username: user.username,
          type: user.type,
        },
      };
    } catch (error) {
      if (error.message.startsWith('auth.')) throw error;
      throw new Error('auth.TOKEN_REFRESH_FAILED');
    }
  }

  /**
   * 用户登出
   * @param {string} refreshToken - 刷新令牌
   */
  async logout({ knexMain }, refreshToken) {
    try {
      if (refreshToken) {
        const row = await knexMain('user_token').where({ token: refreshToken }).first();
        if (row) {
          // 使该会话下所有 token（含 access）失效
          await knexMain('user_token').where({ user_id: row.user_id, device_id: row.device_id }).update({ is_valid: false });
        } else {
          await knexMain('user_token').where({ token: refreshToken }).update({ is_valid: false });
        }
      }
      return true;
    } catch (error) {
      throw new Error('auth.LOGOUT_FAILED');
    }
  }

  /**
   * 获取在线用户列表（仅超级管理员）
   */
  async getOnlineUsers({ knexMain }) {
    try {
      const users = await knexMain('user_token')
        .join('user', 'user_token.user_id', 'user.id')
        .where('user_token.is_valid', true)
        .andWhere('user_token.expire_time', '>', new Date())
        .select(
          'user_token.id',
          'user.username',
          'user.type',
          'user_token.client_ip',
          'user_token.device_info',
          'user_token.browser',
          'user_token.os',
          'user_token.create_time', // 登录时间
          'user_token.last_active_time'
        )
        .orderBy('user_token.last_active_time', 'desc');

      return users;
    } catch (error) {
      throw new Error('auth.GET_ONLINE_USERS_FAILED');
    }
  }

  /**
   * 获取用户信息
   * @param {number} userId - 用户ID
   */
  async getUserProfile({ knexMain }, userId) {
    try {
      const user = await knexMain('user').where({ id: userId }).select('id', 'username', 'role', 'create_time', 'updated_at').first();

      if (!user) {
        throw new Error('auth.USER_NOT_FOUND');
      }

      return user;
    } catch (error) {
      if (error.message.startsWith('auth.')) throw error;
      throw new Error('auth.PROFILE_FETCH_FAILED');
    }
  }

  /**
   * 更新用户信息
   * @param {number} userId - 用户ID
   * @param {Object} updateData - 更新数据
   */
  async updateUserProfile({ knexMain }, userId, updateData) {
    try {
      const allowedFields = ['username', 'question', 'answer'];
      const filteredData = {};

      // 过滤允许更新的字段
      Object.keys(updateData).forEach(key => {
        if (allowedFields.includes(key)) {
          filteredData[key] = updateData[key];
        }
      });

      // 如果更新密码，需要加密
      if (filteredData.password) {
        filteredData.password = jwtUtil.encryptPassword(filteredData.password);
      }
      // 如果更新问题答案，需要加密
      if (filteredData.answer) {
        filteredData.answer = await bcrypt.hash(filteredData.answer, 10);
      }

      filteredData.updated_at = new Date();

      const result = await knexMain('user').where({ id: userId }).update(filteredData);

      if (result === 0) {
        throw new Error('auth.USER_NOT_FOUND');
      }

      return { success: true };
    } catch (error) {
      if (error.message.startsWith('auth.')) throw error;
      throw new Error('auth.UPDATE_USER_PROFILE_FAILED');
    }
  }

  /**
   * 获取找回密码所需信息（按用户名，仅管理员）
   * @param {{username?:string}} payload
   */
  async getRecoverInfo({ knexMain }, payload) {
    try {
      const { username } = payload;

      if (!username || String(username).trim() === '') {
        throw new Error('auth.RECOVER_ADMIN_LAN_ONLY');
      }

      const trimmed = String(username).trim();
      const user = await knexMain('user').where({ username: trimmed }).select('username', 'question', 'type').first();
      if (!user) {
        throw new Error('auth.USER_NOT_FOUND');
      }
      if (!userUtil.isAdmin(user)) {
        throw new Error('auth.RECOVER_ADMIN_LAN_ONLY');
      }

      return {
        question: user.question,
        username: user.username,
      };
    } catch (error) {
      if (error.message.startsWith('auth.')) throw error;
      throw new Error('auth.RECOVER_INFO_FETCH_FAILED');
    }
  }

  /**
   * 找回任意用户密码
   * @param {{username:string, answer:string, newPassword:string}} payload
   */
  async recoverUserPassword({ knexMain }, payload) {
    try {
      const { username, answer, newPassword, code, device_fingerprint: deviceFingerprint, clientIp } = payload;
      const newPasswordPlain = jwtUtil.decodeClientPassword(newPassword);
      const user = await knexMain('user').where({ username }).first();
      if (!user) {
        throw new Error('auth.USER_NOT_FOUND');
      }
      if (!userUtil.isAdmin(user)) {
        throw new Error('auth.RECOVER_ADMIN_LAN_ONLY');
      }
      const twofa = new TwoFAService(knexMain);
      const enabled = await twofa.isEnabled(user.id);
      let deviceId = null;
      let deviceName = null;
      let osVersion = null;
      let deviceNeedTwoFactor = true;
      if (enabled) {
        try {
          if (deviceFingerprint && typeof deviceFingerprint === 'object' && clientIp) {
            const built = await this.buildDeviceId(deviceFingerprint, clientIp);
            deviceId = built.deviceId;
            deviceName = built.payload && built.payload.device_name ? built.payload.device_name : null;
            osVersion = built.payload && built.payload.os_version ? built.payload.os_version : null;
            const device = await this.getUserDevice({ knexMain, userId: user.id, deviceId });
            if (device) {
              const lastSeen = device.last_seen_at ? new Date(device.last_seen_at).getTime() : 0;
              const isStale = Number.isFinite(lastSeen) && Date.now() - lastSeen > 30 * 24 * 60 * 60 * 1000;
              const isTrusted = device.trusted_flag === true || device.trusted_flag === 1;
              deviceNeedTwoFactor = !isTrusted || isStale;
            } else {
              deviceNeedTwoFactor = true;
            }
          }
        } catch (_) {}

        if (deviceNeedTwoFactor) {
          if (!code) throw new Error('twofa.TWO_FACTOR_REQUIRED');
          await twofa.verifyForLogin(user.id, code);
          if (deviceId) {
            await this.upsertUserDevice({
              knexMain,
              userId: user.id,
              deviceId,
              deviceName,
              osVersion,
              trustedFlag: true,
            });
            await this.trimUserDevices({ knexMain, userId: user.id, keep: 500 });
          }
        } else if (deviceId) {
          await this.upsertUserDevice({
            knexMain,
            userId: user.id,
            deviceId,
            deviceName,
            osVersion,
            trustedFlag: true,
          });
          await this.trimUserDevices({ knexMain, userId: user.id, keep: 500 });
        }
      }
      console.log('answer', answer);
      const answerMatch = await bcrypt.compare(answer, user.answer);
      if (!answerMatch) {
        throw new Error('auth.SECURITY_ANSWER_INCORRECT');
      }
      const encryptedNewPassword = jwtUtil.encryptPassword(newPasswordPlain);
      await knexMain('user').where({ id: user.id }).update({
        password: encryptedNewPassword,
        last_login_time: new Date(),
      });
      return { userId: user.id, username: user.username };
    } catch (error) {
      console.log(error);
      if (error && error.message && (error.message.startsWith('auth.') || error.message.startsWith('twofa.'))) throw error;
      throw new Error('auth.PASSWORD_RESET_FAILED');
    }
  }

  async buildDeviceId(deviceFingerprint, clientIp) {
    const serverId = await this._ensureServerId();
    const payload = this._normalizeDeviceFingerprint(deviceFingerprint, clientIp);
    const content = this._stableStringify(payload);
    const deviceId = crypto.createHmac('sha256', serverId).update(content, 'utf8').digest('hex');
    return { deviceId, payload };
  }

  async upsertUserDevice({ knexMain, userId, deviceId, deviceName, osVersion, riskScore = 0, trustedFlag = false }) {
    const now = new Date();
    const existing = await knexMain('user_device').where({ user_id: userId, device_id: deviceId }).first();
    if (existing) {
      const nextName = deviceName || existing.device_name || null;
      const nextOsVersion = osVersion || existing.os_version || null;
      await knexMain('user_device').where({ id: existing.id }).update({
        device_name: nextName,
        os_version: nextOsVersion,
        last_seen_at: now,
        risk_score: riskScore,
        trusted_flag: trustedFlag,
      });
      return {
        isNew: false,
        device: {
          ...existing,
          device_name: nextName,
          os_version: nextOsVersion,
          last_seen_at: now,
          risk_score: riskScore,
          trusted_flag: trustedFlag,
        },
      };
    }
    await knexMain('user_device').insert({
      user_id: userId,
      device_id: deviceId,
      device_name: deviceName || null,
      os_version: osVersion || null,
      first_seen_at: now,
      last_seen_at: now,
      risk_score: riskScore,
      trusted_flag: trustedFlag,
    });
    const device = await knexMain('user_device').where({ user_id: userId, device_id: deviceId }).first();
    return { isNew: true, device };
  }

  async getUserDevice({ knexMain, userId, deviceId }) {
    return await knexMain('user_device').where({ user_id: userId, device_id: deviceId }).first();
  }

  async listUserDevices({ knexMain, userId, limit = 10 }) {
    return await knexMain('user_device').where({ user_id: userId }).orderBy('last_seen_at', 'desc').limit(limit).select('*');
  }

  async removeUserDevice({ knexMain, userId, deviceId }) {
    return await knexMain('user_device').where({ user_id: userId, device_id: deviceId }).delete();
  }

  async invalidateTokensForDevice({ knexMain, userId, deviceId }) {
    return await knexMain('user_token').where({ user_id: userId, device_id: deviceId, is_valid: true }).update({ is_valid: false });
  }

  async trimUserDevices({ knexMain, userId, keep = 500 }) {
    const devices = await knexMain('user_device').where({ user_id: userId }).orderBy('last_seen_at', 'desc').select('id');
    if (devices.length <= keep) return 0;
    const removeIds = devices.slice(keep).map(row => row.id);
    await knexMain('user_device').whereIn('id', removeIds).delete();
    return removeIds.length;
  }

  _normalizeDeviceFingerprint(deviceFingerprint, clientIp) {
    const fp = deviceFingerprint && typeof deviceFingerprint === 'object' ? deviceFingerprint : {};
    const timezoneOffsetRaw = fp.timezone_offset ?? fp.timezoneOffset;
    const timezoneOffset = timezoneOffsetRaw === 0 || timezoneOffsetRaw ? Number(timezoneOffsetRaw) : '';
    return {
      user_agent: fp.user_agent ?? fp.userAgent ?? '',
      platform: fp.platform ?? '',
      os_version: fp.os_version ?? fp.osVersion ?? '',
      device_model: fp.device_model ?? fp.deviceModel ?? '',
      device_name: fp.device_name ?? fp.deviceName ?? '',
      language: fp.language ?? '',
      timezone_offset: Number.isFinite(timezoneOffset) ? timezoneOffset : '',
      timezone_name: fp.timezone_name ?? fp.timezoneName ?? '',
      storage_id: fp.storage_id ?? fp.storageId ?? '',
      storage_type: fp.storage_type ?? fp.storageType ?? '',
    };
  }

  _stableStringify(payload) {
    const keys = Object.keys(payload || {}).sort();
    const ordered = {};
    keys.forEach(key => {
      const value = payload[key];
      ordered[key] = value === undefined || value === null ? '' : value;
    });
    return JSON.stringify(ordered);
  }

  _extractIpSegment(ip) {
    const normalized = NetUtil.normalizeIP(String(ip || '').trim());
    if (!normalized) return '';
    if (normalized.includes('.')) {
      const parts = normalized.split('.');
      if (parts.length === 4) {
        return `${parts[0]}.${parts[1]}.${parts[2]}.0/24`;
      }
      return '';
    }
    if (normalized.includes(':')) {
      const parts = normalized.split(':').filter(part => part !== '');
      const prefix = parts.slice(0, 4).join(':');
      return prefix ? `${prefix}::/64` : '';
    }
    return '';
  }

  async _ensureServerId() {
    const existing = process.env.SERVER_ID ? String(process.env.SERVER_ID).trim() : '';
    if (existing) return existing;
    const serverId = await tableConfig.ensureServerId();
    if (serverId) process.env.SERVER_ID = serverId;
    return serverId;
  }

  /**
   * 获取用户墙纸
   * @param {number} userId - 用户ID
   */
  async getUserWallpaper(userId) {
    try {
      const cfg = await tableConfig.getConfigByKey('user_wallpaper', userId);
      if (cfg && cfg.trim() !== '') {
        let pref = null;
        try {
          pref = JSON.parse(cfg);
        } catch (_) {}
        if (pref && pref.type === 'system') {
          const filename = (pref.filename || '').toString();
          if (filename) {
            const list = await this.appearanceService.getWallpapers();
            const found = list.find(w => w.name === filename);
            if (found) return found;
          }
        }
        if (pref && pref.type === 'custom') {
          const filename = (pref.filename || '').toString();
          if (filename) {
            const found = await this.appearanceService.getUserCustomWallpaperByName(userId, filename);
            if (found) return found;
          }
        }
      }
      return await this.appearanceService.getRandomWallpaper();
    } catch (error) {
      console.error('Get user wallpaper failed:', error);
      return await this.appearanceService.getRandomWallpaper();
    }
  }
}

module.exports = new AuthService();
