const knex = require('knex');
const path = require('path');
const Logger = require('../utils/logger');
const config = require('../config/config');

class KnexUtil {
  constructor() {
    if (KnexUtil.instance) {
      return KnexUtil.instance;
    }

    this._connections = new Map(); // 存储所有数据库连接
    this._defaultDbPath = null; // 默认数据库路径
    KnexUtil.instance = this;
  }

  /**
   * 初始化数据库连接
   * @param {string} dbPath - 数据库文件路径
   * @param {Object} options - 额外配置选项
   * @returns {Promise<Object>} Knex实例
   */
  async init(dbPath, options = {}) {
    // 检查是否已存在该路径的连接
    if (this._connections.has(dbPath)) {
      Logger.warn(`Database connection already exists, reusing: ${dbPath}`);
      return this._connections.get(dbPath);
    }

    // 设置默认数据库路径（第一个初始化的连接）
    if (!this._defaultDbPath) {
      this._defaultDbPath = dbPath;
    }

    const defaultOptions = {
      client: 'better-sqlite3',
      connection: {
        filename: dbPath,
      },
      useNullAsDefault: true,
      pool: {
        min: 0, // 最小连接数，即使空闲也会保持
        max: 5, // 最大连接数
        acquireTimeoutMillis: 60000, // 获取连接的超时时间（60秒）
        idleTimeoutMillis: 30000, // 空闲连接的超时时间（30秒）
      },
      ...options,
    };

    try {
      const knexInstance = knex(defaultOptions);

      // 测试连接
      await knexInstance.raw('SELECT 1');

      // 启用WAL模式（Write-Ahead Logging）
      await knexInstance.raw('PRAGMA journal_mode = WAL');

      const busyTimeoutMs = Math.max(0, Math.min(60000, Number(process.env.SQLITE_BUSY_TIMEOUT_MS ?? 5000)));
      if (busyTimeoutMs > 0) {
        await knexInstance.raw(`PRAGMA busy_timeout = ${busyTimeoutMs}`);
      }


      // 存储连接实例
      this._connections.set(dbPath, knexInstance);

      return knexInstance;
    } catch (error) {
      Logger.error('❌ Knex init failed:', error.message, { dbPath });
      throw error;
    }
  }

  /**
   * 获取Knex实例
   * @param {string} dbPath - 数据库文件路径（可选，不传则使用默认连接）
   * @returns {Object} Knex实例
   */
  getInstance(dbPath = null) {
    const targetDbPath = dbPath || this._defaultDbPath;

    if (!targetDbPath) {
      throw new Error('Knex实例未初始化，请先调用init()方法');
    }

    if (!this._connections.has(targetDbPath)) {
      throw new Error(`数据库连接不存在，请先调用init('${targetDbPath}')方法`);
    }

    return this._connections.get(targetDbPath);
  }

  /**
   * 获取数据库路径
   * @param {string} dbPath - 数据库文件路径（可选，不传则返回默认路径）
   * @returns {string} 数据库文件路径
   */
  getDbPath(dbPath = null) {
    const targetDbPath = dbPath || this._defaultDbPath;
    return targetDbPath;
  }

  /**
   * 获取所有已初始化的数据库路径
   * @returns {Array<string>} 数据库路径数组
   */
  getAllDbPaths() {
    return Array.from(this._connections.keys());
  }

  /**
   * 检查数据库连接是否存在
   * @param {string} dbPath - 数据库文件路径
   * @returns {boolean} 是否存在
   */
  hasConnection(dbPath) {
    return this._connections.has(dbPath);
  }

  /**
   * 关闭数据库连接
   * @param {string} dbPath - 数据库文件路径（可选，不传则关闭所有连接）
   */
  async destroy(dbPath = null) {
    if (dbPath) {
      // 关闭指定连接
      if (this._connections.has(dbPath)) {
        try {
          await this._connections.get(dbPath).destroy();
          this._connections.delete(dbPath);

          // 如果关闭的是默认连接，重新设置默认连接
          if (this._defaultDbPath === dbPath) {
            const remainingPaths = Array.from(this._connections.keys());
            this._defaultDbPath = remainingPaths.length > 0 ? remainingPaths[0] : null;
          }

          Logger.info(`✅ Knex connection closed: ${dbPath}`);
        } catch (error) {
          Logger.error(`❌ Failed to close Knex (${dbPath}):`, error.message);
        }
      }
    } else {
      // 关闭所有连接
      const closePromises = Array.from(this._connections.entries()).map(async ([path, instance]) => {
        try {
          await instance.destroy();
          Logger.info(`✅ Knex connection closed: ${path}`);
        } catch (error) {
          Logger.error(`❌ Failed to close Knex (${path}):`, error.message);
        }
      });

      await Promise.all(closePromises);
      this._connections.clear();
      this._defaultDbPath = null;
      KnexUtil.instance = null;
      Logger.info('✅ All Knex connections closed');
    }
  }

  /**
   * 执行原生SQL查询
   * @param {string} sql - SQL语句
   * @param {Array} params - 参数数组
   * @param {string} dbPath - 数据库文件路径（可选）
   * @returns {Promise} 查询结果
   */
  async raw(sql, params = [], dbPath = null) {
    const instance = this.getInstance(dbPath);
    return await instance.raw(sql, params);
  }

  /**
   * 开始事务
   * @param {string} dbPath - 数据库文件路径（可选）
   * @param {Function} callback - 事务回调函数（可选，如果提供则自动执行）
   * @returns {Promise} 事务对象或事务结果
   */
  async transaction(dbPath = null, callback = null) {
    const instance = this.getInstance(dbPath);

    if (callback && typeof callback === 'function') {
      // 自动执行事务
      return await instance.transaction(callback);
    } else {
      // 返回事务对象
      return new Promise((resolve, reject) => {
        instance
          .transaction(trx => {
            resolve(trx);
          })
          .catch(reject);
      });
    }
  }

  /**
   * 检查表是否存在
   * @param {string} tableName - 表名
   * @param {string} dbPath - 数据库文件路径（可选）
   * @returns {Promise<boolean>} 是否存在
   */
  async tableExists(tableName, dbPath = null) {
    try {
      const result = await this.raw("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [tableName], dbPath);
      return result.length > 0;
    } catch (error) {
      error('Check table exists failed:', error.message);
      return false;
    }
  }

  /**
   * 获取表结构信息
   * @param {string} tableName - 表名
   * @param {string} dbPath - 数据库文件路径（可选）
   * @returns {Promise<Array>} 表结构信息
   */
  async getTableSchema(tableName, dbPath = null) {
    try {
      return await this.raw(`PRAGMA table_info(${tableName})`, [], dbPath);
    } catch (error) {
      console.error('Get table schema failed:', error.message);
      return [];
    }
  }

  /**
   * 批量插入数据
   * @param {string} tableName - 表名
   * @param {Array} data - 数据数组
   * @param {number} chunkSize - 分批大小，默认100
   * @param {string} dbPath - 数据库文件路径（可选）
   * @returns {Promise} 插入结果
   */
  async batchInsert(tableName, data, chunkSize = 100, dbPath = null) {
    const instance = this.getInstance(dbPath);
    return await instance.batchInsert(tableName, data, chunkSize);
  }

  /**
   * 获取所有数据库连接的状态信息
   * @returns {Object} 连接状态信息
   */
  getConnectionStatus() {
    const status = {
      totalConnections: this._connections.size,
      defaultDbPath: this._defaultDbPath,
      connections: {},
    };

    for (const [dbPath, instance] of this._connections.entries()) {
      status.connections[dbPath] = {
        isDefault: dbPath === this._defaultDbPath,
        client: instance.client.config.client,
      };
    }

    return status;
  }

  /**
   * 安全地构建WHERE条件
   * @param {Object} conditions - 条件对象
   * @returns {Object} Knex查询构建器
   */
  buildWhere(query, conditions) {
    if (!conditions || typeof conditions !== 'object') {
      return query;
    }

    Object.entries(conditions).forEach(([key, value]) => {
      if (Array.isArray(value)) {
        query.whereIn(key, value);
      } else if (value === null) {
        query.whereNull(key);
      } else if (typeof value === 'object' && value !== null) {
        // 支持操作符: { $gt: 10 }, { $like: '%test%' }
        Object.entries(value).forEach(([operator, opValue]) => {
          switch (operator) {
            case '$gt':
              query.where(key, '>', opValue);
              break;
            case '$gte':
              query.where(key, '>=', opValue);
              break;
            case '$lt':
              query.where(key, '<', opValue);
              break;
            case '$lte':
              query.where(key, '<=', opValue);
              break;
            case '$like':
              query.where(key, 'like', opValue);
              break;
            case '$in':
              query.whereIn(key, opValue);
              break;
            default:
              query.where(key, opValue);
          }
        });
      } else {
        query.where(key, value);
      }
    });

    return query;
  }
}

// 创建单例实例
const knexUtilInstance = new KnexUtil();
module.exports = knexUtilInstance;
