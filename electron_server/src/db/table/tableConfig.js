const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tableConfig {
  constructor() {
    this.tableName = 'config';
  }
  /**
   * 创建配置表
   */
  async createTable() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查表是否已存在
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('uid').notNullable().defaultTo(0); //0代表通用配置
        table.string('key').notNullable();
        table.string('value').nullable();
      });
      Logger.info('✅ config table created');
    }
  }

  /**
   * 创建配置表索引
   */
  async createIndexes() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    // 检查索引是否已存在
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = existingIndexes.map(row => row.name);

    const targetIndexes = [
      { columns: ['uid', 'key'], name: 'uid_key', unique: true },
      { columns: ['key'], name: 'key' },
    ];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable(this.tableName, table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created ${index.unique ? 'unique ' : ''}index ${index.name} on config table`);
      }
    }
  }

  /**
   * 根据键获取配置值
   * @param {string} key - 配置键
   * @param {number} uid - 用户ID，默认为0（通用配置）
   * @returns {string|null} - 配置值
   */
  async getConfigByKey(key, uid = 0) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const config = await knex(this.tableName).where({ key: key, uid: uid }).first();
    return config && config.value ? config.value : null;
  }

  /**
   * 设置配置值
   * @param {string} key - 配置键
   * @param {string} value - 配置值
   * @param {number} uid - 用户ID，默认为0（通用配置）
   * @returns {boolean} - 是否成功
   */
  async setConfigByKey(key, value, uid = 0) {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);

      // 检查配置是否已存在
      const existingConfig = await knex(this.tableName).where({ key: key, uid: uid }).first();

      if (existingConfig) {
        // 更新现有配置
        await knex(this.tableName).where({ key: key, uid: uid }).update({ value: value });
      } else {
        // 插入新配置
        await knex(this.tableName).insert({
          uid: uid,
          key: key,
          value: value,
        });
      }
      return true;
    } catch (err) {
      Logger.error(`❌ save config failed: ${key}`, err);
      return false;
    }
  }

  async deleteConfigByKey(key, uid = 0) {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      await knex(this.tableName).where({ key: key, uid: uid }).del();
      return true;
    } catch (err) {
      Logger.error(`❌ delete config failed: ${key}`, err);
      return false;
    }
  }

  async getJsonConfigByKey(key, uid = 0) {
    const raw = await this.getConfigByKey(key, uid);
    if (!raw) return null;
    try {
      return JSON.parse(String(raw));
    } catch (_) {
      return null;
    }
  }

  async setJsonConfigByKey(key, value, uid = 0) {
    const serialized = value == null ? null : JSON.stringify(value);
    return await this.setConfigByKey(key, serialized, uid);
  }

  /**
   * 保存HTTP端口配置
   * @param {number} port - HTTP端口号
   * @returns {boolean} - 是否成功
   */
  async saveHttpPort(port) {
    return await this.setConfigByKey(this.KEY_API_PORT_HTTP, port.toString());
  }

  /**
   * 保存HTTPS端口配置
   * @param {number} port - HTTPS端口号
   * @returns {boolean} - 是否成功
   */
  async saveHttpsPort(port) {
    return await this.setConfigByKey(this.KEY_API_PORT_HTTPS, port.toString());
  }

  /**
   * 获取服务器唯一标识
   * @returns {string|null} - 服务器ID，如果不存在则返回null
   */
  async getServerId() {
    return await this.getConfigByKey(this.KEY_SERVER_ID);
  }

  /**
   * 设置服务器唯一标识
   * @param {string} serverId - 服务器ID
   * @returns {boolean} - 是否成功
   */
  async setServerId(serverId) {
    return await this.setConfigByKey(this.KEY_SERVER_ID, serverId);
  }

  /**
   * 生成并保存服务器唯一标识
   * @returns {string} - 生成的服务器ID
   */
  async generateAndSaveServerId() {
    const { v4: uuidv4 } = require('uuid');
    const serverId = uuidv4();
    await this.setServerId(serverId);
    return serverId;
  }

  async generateAndSaveJWTSecret() {
    const { v4: uuidv4 } = require('uuid');
    const jwtSecret = uuidv4();
    await this.setConfigByKey(this.KEY_JWT_SECRET, jwtSecret);
    return jwtSecret;
  }

  async generateAndSaveTwoFASecret() {
    const crypto = require('crypto');
    const secret = crypto.randomBytes(48).toString('base64');
    await this.setConfigByKey(this.KEY_2FA_SECRET, secret);
    return secret;
  }
  /**
   * 确保服务器ID存在，如果不存在则生成一个
   * @returns {string} - 服务器ID
   */
  async ensureServerId() {
    let serverId = await this.getServerId();
    if (!serverId) {
      serverId = await this.generateAndSaveServerId();
      Logger.info(`✅ Generated server id: ${serverId}`);
    }
    return serverId;
  }

  async ensureJWTSecret() {
    let jwtSecret = await this.getConfigByKey(this.KEY_JWT_SECRET);
    if (!jwtSecret) {
      jwtSecret = await this.generateAndSaveJWTSecret();

    }
    return jwtSecret;
  }

  async ensureTwoFASecret() {
    let secret = await this.getConfigByKey(this.KEY_2FA_SECRET);
    if (!secret) {
      secret = await this.generateAndSaveTwoFASecret();
      Logger.info(`✅ Generated 2FA secret`);
    }
    return secret;
  }

  async getP2pRemoteAccessEnabled() {
    const raw = await this.getConfigByKey(this.KEY_P2P_REMOTE_ACCESS_ENABLED);
    if (raw === null || raw === undefined) return false;
    if (typeof raw === 'number') return raw === 1;
    const s = String(raw).trim().toLowerCase();
    return s === '1' || s === 'true' || s === 'yes' || s === 'on';
  }

  async setP2pRemoteAccessEnabled(enabled) {
    const v = enabled === true ? '1' : '0';
    return await this.setConfigByKey(this.KEY_P2P_REMOTE_ACCESS_ENABLED, v);
  }

  async getP2pFixNodeDomain() {
    const raw = await this.getConfigByKey(this.KEY_P2P_FIX_NODE_DOMAIN);
    return raw ? String(raw).trim().toLowerCase() : '';
  }

  async setP2pFixNodeDomain(domain) {
    const normalized = domain == null ? '' : String(domain).trim().toLowerCase();
    if (!normalized) {
      return await this.deleteConfigByKey(this.KEY_P2P_FIX_NODE_DOMAIN);
    }
    return await this.setConfigByKey(this.KEY_P2P_FIX_NODE_DOMAIN, normalized);
  }

  async getP2pConnectedDomain() {
    const raw = await this.getConfigByKey(this.KEY_P2P_CONNECTED_DOMAIN);
    return raw ? String(raw).trim().toLowerCase() : '';
  }

  async setP2pConnectedDomain(domain) {
    const normalized = domain == null ? '' : String(domain).trim().toLowerCase();
    if (!normalized) {
      return await this.deleteConfigByKey(this.KEY_P2P_CONNECTED_DOMAIN);
    }
    return await this.setConfigByKey(this.KEY_P2P_CONNECTED_DOMAIN, normalized);
  }

  async getP2pServersCache() {
    const value = await this.getJsonConfigByKey(this.KEY_P2P_SERVERS_CACHE);
    return Array.isArray(value) ? value : [];
  }

  async setP2pServersCache(list) {
    return await this.setJsonConfigByKey(this.KEY_P2P_SERVERS_CACHE, Array.isArray(list) ? list : []);
  }

  async getP2pServersCacheUpdatedAt() {
    const raw = await this.getConfigByKey(this.KEY_P2P_SERVERS_CACHE_UPDATED_AT);
    const num = Number(raw);
    return Number.isFinite(num) ? num : 0;
  }

  async setP2pServersCacheUpdatedAt(ts) {
    const num = Number(ts);
    return await this.setConfigByKey(this.KEY_P2P_SERVERS_CACHE_UPDATED_AT, Number.isFinite(num) ? String(num) : '0');
  }

  async getAutoDiscoverServerEnabled() {
    const raw = await this.getConfigByKey(this.KEY_AUTO_DISCOVER_SERVER_ENABLED);
    if (raw === null || raw === undefined) return true;
    if (typeof raw === 'number') return raw === 1;
    const s = String(raw).trim().toLowerCase();
    return s === '1' || s === 'true' || s === 'yes' || s === 'on';
  }

  async setAutoDiscoverServerEnabled(enabled) {
    const v = enabled === true ? '1' : '0';
    return await this.setConfigByKey(this.KEY_AUTO_DISCOVER_SERVER_ENABLED, v);
  }
}
// 创建单例实例
const tableConfigInstance = new tableConfig();
// 配置键
tableConfigInstance.KEY_API_PORT_HTTP = 'apiPortHttp';
tableConfigInstance.KEY_API_PORT_HTTPS = 'apiPortHttps';
tableConfigInstance.KEY_EXPRESS_API_COUNT = 'expressApiCount';
tableConfigInstance.KEY_LOGIN_WELCOME_TEXT = 'loginWelcomeText';
tableConfigInstance.KEY_SERVER_ID = 'serverId';
tableConfigInstance.KEY_JWT_SECRET = 'jwtSecret';
tableConfigInstance.KEY_2FA_SECRET = 'twofaSecret';
tableConfigInstance.KEY_OPEN_AT_LOGIN = 'openAtLogin';
tableConfigInstance.KEY_MINIMIZE_ON_START = 'minimizeOnStart';
tableConfigInstance.KEY_SERVER_UI_LANGUAGE = 'serverUiLanguage';
tableConfigInstance.KEY_SECURITY_CONFIG = 'securityConfig';
tableConfigInstance.KEY_IS_INITIAL_ADMIN = 'is_initial_admin';
tableConfigInstance.KEY_P2P_REMOTE_ACCESS_ENABLED = 'p2pRemoteAccessEnabled';
tableConfigInstance.KEY_P2P_FIX_NODE_DOMAIN = 'p2pFixNodeDomain';
tableConfigInstance.KEY_P2P_CONNECTED_DOMAIN = 'p2pConnectedDomain';
tableConfigInstance.KEY_P2P_SERVERS_CACHE = 'p2pServers';
tableConfigInstance.KEY_P2P_SERVERS_CACHE_UPDATED_AT = 'p2pServersUpdatedAt';
tableConfigInstance.KEY_DDNS_ENABLED = 'ddnsEnabled';
tableConfigInstance.KEY_DDNS_TYPE = 'ddnsType';
tableConfigInstance.KEY_DDNS_DOMAIN = 'ddnsDomain';
tableConfigInstance.KEY_DDNS_BASE = 'ddnsBase';
tableConfigInstance.KEY_DDNS_LAST_IP = 'ddnsLastIp';
tableConfigInstance.KEY_DDNS_LAST_TIME = 'ddnsLastTime';
tableConfigInstance.KEY_DDNS_LAST_ERROR = 'ddnsLastError';
tableConfigInstance.KEY_CUSTOM_HOSTNAME = 'customHostname';
tableConfigInstance.KEY_AUTO_DISCOVER_SERVER_ENABLED = 'autoDiscoverServerEnabled';
tableConfigInstance.KEY_APP_ACCESS_SCOPE_MODE = 'appAccessScopeMode';
tableConfigInstance.KEY_APP_ACCESS_SCOPE_DIRS = 'appAccessScopeDirs';
tableConfigInstance.KEY_APP_TERMINAL_ENABLED = 'appTerminalEnabled';
tableConfigInstance.KEY_TRANSMISSION_CONFIG = 'transmissionConfig';
tableConfigInstance.KEY_TRANSMISSION_TORRENT_PATHS = 'transmissionTorrentPaths';
// 导出单例实例
module.exports = tableConfigInstance;
