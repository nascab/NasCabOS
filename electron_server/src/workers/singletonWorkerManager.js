'use strict';
const { fork } = require('child_process');
const path = require('path');
const Logger = require('../utils/logger');
const config = require('../config/config');
const { getProcessRegistry } = require('./processRegistry');

/**
 * 单例Worker管理器
 * 提供统一的单例worker管理功能，支持自动重启、状态监控、优雅关闭等
 */
class SingletonWorkerManager {
  constructor() {
    this.workers = new Map(); // 存储所有单例worker
    this.workerConfigs = new Map(); // worker配置信息
    this.init();
  }

  _getWorkerBaseEnv(workerName, optionsEnv = {}) {
    const userDataFolder = optionsEnv.userDataFolder || process.env['userDataFolder'] || (typeof config.getUserDataPath === 'function' ? config.getUserDataPath() : '');

    return {
      ...process.env,
      ...optionsEnv,
      WORKER_NAME: workerName,
      userDataFolder,
    };
  }

  _cleanupWorkerEntry(workerName) {
    this.workers.delete(workerName);
    const config = this.workerConfigs.get(workerName);
    const keepConfig = !!(config && config.options && config.options.keepConfig === true);
    if (!keepConfig) this.workerConfigs.delete(workerName);
  }

  init() {
    Logger.info('🔄 Initializing singleton worker manager');

    // 注册全局错误处理
    this.setupGlobalErrorHandling();
  }

  /**
   * 启动单例worker
   * @param {string} workerName - worker名称（用于标识单例）
   * @param {string} workerPath - worker文件路径
   * @param {Object} options - 启动选项
   * @param {Object} options.env - 环境变量
   * @param {Function} options.onStart - worker启动回调
   * @param {Function} options.onStop - worker停止回调
   * @param {Function} options.onError - worker错误回调
   * @returns {Object} worker实例
   */
  startWorker(workerName, workerPath, options = {}) {
    // 检查是否已有同名worker在运行
    if (this.workers.has(workerName)) {
      const existingWorker = this.workers.get(workerName);
      if (existingWorker.connected) {
        Logger.info(`🔄 ${workerName} already running, skip start`);
        return existingWorker;
      }
    }

    // 保存worker配置
    this.workerConfigs.set(workerName, {
      workerPath,
      options,
      startTime: Date.now(),
      restartCount: 0,
    });

    // 创建worker进程
    const worker = fork(path.resolve(__dirname, workerPath), [], {
      env: this._getWorkerBaseEnv(workerName, options.env),
    });
    getProcessRegistry().registerProcess({ pid: worker.pid, workerPath, role: workerName });

    // 存储worker实例
    this.workers.set(workerName, worker);

    // 直接监听worker消息
    worker.on('message', message => {
      if (message && message.type) {
        // 这里可以添加特定的消息处理逻辑
        // 目前消息处理已经在主进程的cluster.on('message')中统一处理
      }
      try {
        if (options && typeof options.onMessage === 'function') {
          options.onMessage(message, worker);
        }
      } catch (e) {
        Logger.error(`❌ worker ${workerName} onMessage failed:`, e);
      }
    });

    // 设置worker事件监听
    this.setupWorkerEventListeners(workerName, worker, options);

    // 调用启动回调
    if (typeof options.onStart === 'function') {
      options.onStart(worker);
    }

    return worker;
  }

  /**
   * 停止指定worker
   * @param {string} workerName - worker名称
   * @param {number} timeout - 超时时间（毫秒）
   * @returns {Promise<boolean>} 是否成功停止
   */
  stopWorker(workerName, timeout = 5000) {
    if (!this.workers.has(workerName)) {
      Logger.warn(`⚠️ stop requested for unknown worker: ${workerName}`);
      return Promise.resolve(false);
    }

    const worker = this.workers.get(workerName);
    const config = this.workerConfigs.get(workerName);

    return new Promise(resolve => {
      Logger.info(`🛑 Stopping worker: ${workerName}`);

      // 设置超时
      const timeoutId = setTimeout(() => {
        Logger.warn(`⏰ worker ${workerName} stop timed out, killing`);
        try {
          getProcessRegistry().removeProcessByPid(worker && worker.pid);
        } catch (_) {}
        try {
          this._cleanupWorkerEntry(workerName);
        } catch (_) {}
        worker.kill('SIGKILL');
        resolve(false);
      }, timeout);

      // 优雅关闭
      worker.once('exit', (code, signal) => {
        clearTimeout(timeoutId);
        this._cleanupWorkerEntry(workerName);

        Logger.info(`✅ worker ${workerName} stopped, code: ${code}, signal: ${signal}`);

        // 调用停止回调
        if (config && typeof config.options.onStop === 'function') {
          config.options.onStop(code, signal);
        }

        resolve(true);
      });

      try {
        worker.send({ type: 'stop' });
      } catch (_) {}

      setTimeout(() => {
        try {
          if (worker.connected) {
            worker.kill('SIGTERM');
          }
        } catch (_) {}
      }, 200);
    });
  }

  /**
   * 重启指定worker
   * @param {string} workerName - worker名称
   * @returns {Promise<Object>} 新的worker实例
   */
  async restartWorker(workerName) {
    if (!this.workers.has(workerName)) {
      throw new Error(`worker ${workerName} 不存在`);
    }

    const config = this.workerConfigs.get(workerName);
    if (!config) {
      throw new Error(`worker ${workerName} 的配置不存在`);
    }

    Logger.info(`🔄 Restarting worker: ${workerName}`);

    // 先停止worker
    await this.stopWorker(workerName);

    // 增加重启计数
    config.restartCount++;

    // 重新启动worker
    return this.startWorker(workerName, config.workerPath, config.options);
  }

  /**
   * 获取worker状态
   * @param {string} workerName - worker名称
   * @returns {Object} worker状态信息
   */
  getWorkerStatus(workerName) {
    if (!this.workers.has(workerName)) {
      return {
        exists: false,
        running: false,
        message: `worker ${workerName} 不存在`,
      };
    }

    const worker = this.workers.get(workerName);
    const config = this.workerConfigs.get(workerName);

    return {
      exists: true,
      running: worker.connected,
      workerName,
      pid: worker.pid,
      startTime: config ? config.startTime : null,
      restartCount: config ? config.restartCount : 0,
      uptime: config ? Date.now() - config.startTime : 0,
    };
  }

  /**
   * 获取所有worker状态
   * @returns {Object} 所有worker状态
   */
  getAllWorkersStatus() {
    const status = {};
    for (const [workerName] of this.workers) {
      status[workerName] = this.getWorkerStatus(workerName);
    }
    return status;
  }

  /**
   * 检查worker是否存在且运行中
   * @param {string} workerName - worker名称
   * @returns {boolean} 是否运行中
   */
  isWorkerRunning(workerName) {
    const worker = this.workers.get(workerName);
    return worker && worker.connected;
  }

  /**
   * 设置worker事件监听
   * @param {string} workerName - worker名称
   * @param {Object} worker - worker实例
   * @param {Object} options - 配置选项
   */
  setupWorkerEventListeners(workerName, worker, options) {
    const config = this.workerConfigs.get(workerName);

    // 监听worker退出事件
    worker.on('exit', (code, signal) => {


      // 从workers映射中移除
      this._cleanupWorkerEntry(workerName);
      getProcessRegistry().removeProcessByPid(worker.pid);

      // 调用错误回调
      if (config && signal && typeof config.options.onError === 'function') {
        config.options.onError(code, signal);
      } else if (config && typeof config.options.onStop === 'function') {
        config.options.onStop(code, signal);
      }
    });

    // 监听worker错误事件
    worker.on('error', err => {
      Logger.error(`❌ worker ${workerName} error:`, err);

      // 调用错误回调
      if (config && typeof config.options.onError === 'function') {
        config.options.onError(err);
      }
    });

    // 监听消息事件
    worker.on('message', message => {
      // Logger.debug(`📨 收到来自 ${workerName} 的消息:`, message);

      // 可以在这里处理特定的worker消息
      if (message && message.type === 'healthCheck') {
        worker.send({ type: 'healthResponse', data: { status: 'healthy' } });
      }
    });
  }

  /**
   * 设置全局错误处理
   */
  setupGlobalErrorHandling() {
    // uncaughtException处理
    process.on('uncaughtException', err => {
      Logger.error('❌ Singleton worker manager uncaughtException:', err);
    });

    process.on('unhandledRejection', (reason, promise) => {
      Logger.error('❌ Singleton worker manager unhandledRejection:', reason);
    });
  }

  /**
   * 优雅关闭所有worker
   * @returns {Promise} 所有worker关闭完成
   */
  async gracefulShutdown() {
    Logger.info('📡 Shutting down all singleton workers...');

    const stopPromises = [];
    for (const [workerName] of this.workers) {
      const timeout = workerName === 'transmission' ? 12000 : 5000;
      stopPromises.push(this.stopWorker(workerName, timeout));
    }

    await Promise.allSettled(stopPromises);
    Logger.info('✅ All singleton workers stopped');
  }

  /**
   * 销毁管理器（清理资源）
   */
  destroy() {
    Logger.info('🧹 Destroying singleton worker manager');

    // 停止所有worker
    for (const [workerName] of this.workers) {
      if (this.workers.get(workerName).connected) {
        this.workers.get(workerName).kill();
      }
    }

    this.workers.clear();
    this.workerConfigs.clear();
  }
}

// 创建全局单例实例
let singletonInstance = null;

/**
 * 获取单例Worker管理器实例
 * @returns {SingletonWorkerManager} 单例实例
 */
function getSingletonWorkerManager() {
  if (!singletonInstance) {
    singletonInstance = new SingletonWorkerManager();
  }
  return singletonInstance;
}

module.exports = {
  SingletonWorkerManager,
  getSingletonWorkerManager,
};
