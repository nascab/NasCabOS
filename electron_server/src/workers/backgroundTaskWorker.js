'use strict';
const Logger = require('../utils/logger');
const dbUtil = require('../db/dbUtil');
const knexUtil = require('../db/knexUtil');
const tableConfig = require('../db/table/tableConfig');
const HardwareMonitor = require('./hwMonitor');
const nascabAccountUtil = require('../api/modules/service/utils/nascabAccountUtil');
const fsNative = require('fs');
const fs = require('fs-extra');
const path = require('path');
const axios = require('axios');
const apiConfig = require('../config/apiConfig');
const config = require('../config/config');

/**
 * 后台任务Worker
 * 处理常驻后台的定时任务
 */
class BackgroundTaskWorker {
  constructor() {
    this.isRunning = false;
    this.tasks = [];
    this.nascabTokenRefreshMinIntervalMs = 24 * 60 * 60 * 1000;
    this.init();
    this.hwMonitor = new HardwareMonitor();
    this.hwMonitorRunning = false;
    this.bindMessages();
  }

  bindMessages() {
    process.on('message', message => {
      const type = message && message.type ? String(message.type) : '';
      if (!type) return;
      if (type === 'hwMonitor:start') {
        this.startHwMonitor();
        return;
      }
      if (type === 'hwMonitor:stop') {
        this.stopHwMonitor();
        return;
      }
      if (type === 'stop') {
        this.stopHwMonitor();
        try {
          process.exit(0);
        } catch (_) {}
      }
    });
  }

  async init() {
    // 初始化数据库连接
    await dbUtil.init(false);

    await this.cleanupTwofaVerifyLogOnStartup();

    // await this.cleanupTinyCacheTempFiles();

    // 启动任务调度
    this.startTasks();
  }

  async cleanupTwofaVerifyLogOnStartup() {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const tableExists = await knex.schema.hasTable('user_2fa_verify_log');
      if (!tableExists) return;
      await knex('user_2fa_verify_log').del();
    } catch (error) {
      Logger.error('❌  clear 2FA verify log table failed:', error);
    }
  }

  async cleanupTinyCacheTempFiles() {
    try {
      const tinyTempDir = config.getTinyCacheTempPath();
      if (await fs.pathExists(tinyTempDir)) {
        await fs.remove(tinyTempDir);
      }
    } catch (error) {
      Logger.error('❌  clean thumb temp dir failed:', error);
    }
  }

  /**
   * 启动所有定时任务
   */
  startTasks() {
    this.isRunning = true;

    // 1. 清理过期Token任务 (每12小时执行一次)
    this.scheduleTokenCleanup();

    // 2. 清理过期临时文件任务 (每12小时执行一次)
    this.scheduleTempFileCleanup();

    // 3. 清理转码临时文件任务 (每12小时执行一次)
    this.scheduleTranscodeCleanup();

    // 5.清理压缩图片临时目录
    try {
      const zipImgTempPath = config.getZipImgTempPath();
      Logger.info('🧹 Cleaning zip img temp dir:', zipImgTempPath);
      fs.rm(zipImgTempPath, { recursive: true, force: true });
    } catch (e) {
      Logger.error('❌ Failed to clean zip img temp dir:', e);
    }

    // 6. 清理超过 90 天的文件操作日志 (每 24 小时执行一次)
    this.scheduleFileLogCleanup();

    this.scheduleNasCabTokenRefresh();

    // 获取远端默认配置并写入 config 表：启动时调用一次，然后每 24 小时调用一次（与 Token 刷新同周期）
    this.scheduleRemoteDefaultConfigRefresh();

    Promise.resolve()
      .then(async () => {
        if (this.hwMonitor && typeof this.hwMonitor.collectOnce === 'function') {
          await this.hwMonitor.collectOnce();
        } else if (this.hwMonitor) {
          try {
            if (typeof this.hwMonitor.stop === 'function') this.hwMonitor.stop();
          } catch (_) {}
          try {
            await this.hwMonitor.collectDiskMetrics();
          } catch (_) {}
          try {
            await this.hwMonitor.collectFastMetrics();
          } catch (_) {}
        }
      })
      .catch(() => {});
  }

  startHwMonitor() {
    if (this.hwMonitorRunning) return;
    this.hwMonitorRunning = true;
    console.log("开始采集CPU,内存信息")
    try {
      this.hwMonitor.start();
    } catch (e) {
      this.hwMonitorRunning = false;
    }
  }

  stopHwMonitor() {
    console.log("停止采集CPU,内存信息")
    if (!this.hwMonitorRunning) return;
    this.hwMonitorRunning = false;
    try {
      if (this.hwMonitor && typeof this.hwMonitor.stop === 'function') {
        this.hwMonitor.stop();
      }
    } catch (_) {}
  }

  scheduleNasCabTokenRefresh() {
    const intervalMs = 24 * 60 * 60 * 1000;
    const minIntervalMs = typeof this.nascabTokenRefreshMinIntervalMs === 'number' && this.nascabTokenRefreshMinIntervalMs > 0 ? this.nascabTokenRefreshMinIntervalMs : intervalMs;
    const lastOkKey = 'nascab_token_refresh_last_ok_at';
    const run = async () => {
      try {
        const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
        const lastOkRaw = await nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, lastOkKey);
        const lastOk = lastOkRaw ? Number(lastOkRaw) : 0;
        if (Number.isFinite(lastOk) && lastOk > 0 && Date.now() - lastOk < minIntervalMs) return;

        const refreshed = await nascabAccountUtil.refreshNasCabTokens(knex, tableConfig, apiConfig);
        if (refreshed && refreshed.ok) {
          await knex.transaction(async trx => {
            await nascabAccountUtil.setConfigValue(trx, lastOkKey, String(Date.now()));
          });
        }
      } catch (error) {
        Logger.error('❌  refresh NasCab token failed:', error);
      }
    };
    run();
    setInterval(run, intervalMs);
  }

  /**
   * 定时拉取远端默认配置并写入 config 表（tmdbApiTokenDefault、tmdbApiUrl、mapTileServer）
   * 带 client_server_id 时远端返回 AES 加密结果，本地解密后用 serverId 加密存入 config 表
   * 启动时执行一次，之后每 24 小时执行一次
   */
  scheduleRemoteDefaultConfigRefresh() {
    const intervalMs = 24 * 60 * 60 * 1000;
    const run = async () => {
      try {
        const serverId = await nascabAccountUtil.ensureServerId(tableConfig);
        if (!serverId) return;
        const url = `${apiConfig.apiRemoteDefaultConfigPath}?client_server_id=${encodeURIComponent(serverId)}`;
        const res = await axios.get(url, { timeout: 15000 });
        const data = res.data;
        if (!data || typeof data !== 'object') return;
        if (!data.encrypted) return;

        const decrypted = nascabAccountUtil.decryptConfigValue(data.encrypted, serverId);
        if (decrypted === null) return;
        let payload;
        try {
          payload = JSON.parse(decrypted);
        } catch (_) {
          return;
        }
        const { tmdbConfig, tileServer } = payload || {};
        const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
        await knex.transaction(async trx => {
          if (tmdbConfig && typeof tmdbConfig === 'object') {
            if (typeof tmdbConfig.tmdbApiToken === 'string') {
              await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, 'tmdbApiTokenDefault', tmdbConfig.tmdbApiToken);
            }
            if (typeof tmdbConfig.tmdbApiUrl === 'string') {
              await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, 'tmdbApiUrl', tmdbConfig.tmdbApiUrl);
            }
          }
          if (Array.isArray(tileServer) && tileServer.length > 0) {
            await nascabAccountUtil.setEncryptedConfigValue(trx, tableConfig, 'mapTileServer', JSON.stringify(tileServer));
          }
        });
      } catch (error) {
        Logger.error('❌  fetch remote default config failed:', error?.message || error);
      }
    };
    run();
    setInterval(run, intervalMs);
  }

  scheduleTranscodeCleanup() {
    // 立即执行一次
    this.cleanupTranscodeFiles();

    // 设置定时器 (12小时 = 12 * 60 * 60 * 1000 毫秒)
    const intervalMs = 12 * 60 * 60 * 1000;

    setInterval(() => {
      this.cleanupTranscodeFiles();
    }, intervalMs);


  }

  /**
   * 清理过期转码目录的具体逻辑
   */
  async cleanupTranscodeFiles() {
    try {
      let deletedCount = 0;

      const transcodeDirs = await this._resolveTranscodeDirsToCleanup();
      const safeFolderName = config.getTranscodeTempSafeFolderName();
      const now = Date.now();
      const twelveHoursMs = 12 * 60 * 60 * 1000;

      for (const transcodeDir of transcodeDirs) {
        if (path.basename(String(transcodeDir || '')) !== safeFolderName) continue;
        if (!(await fs.pathExists(transcodeDir))) continue;

        const files = await fs.readdir(transcodeDir);
        for (const file of files) {
          const filePath = path.join(transcodeDir, file);
          try {
            const stats = await fs.stat(filePath);
            if (!stats.isDirectory()) continue;
            if (path.basename(path.dirname(filePath)) !== safeFolderName) continue;

            const marker = path.join(filePath, 'index.m3u8');
            if (!(await fs.pathExists(marker))) continue;

            const creationTime = stats.birthtimeMs > 0 ? stats.birthtimeMs : stats.mtimeMs;
            if (now - creationTime > twelveHoursMs) {
              await fs.remove(filePath);

              deletedCount++;
            }
          } catch (_) {}
        }
      }

      if (deletedCount > 0) {

      }
    } catch (error) {
      Logger.error('❌  clean expired transcode files failed:', error);
    }
  }

  async _resolveTranscodeDirsToCleanup() {
    const dirs = [];
    const safeFolderName = config.getTranscodeTempSafeFolderName();
    const add = v => {
      const p = String(v || '').trim();
      if (!p) return;
      if (dirs.includes(p)) return;
      dirs.push(p);
    };

    const resolveSafeDir = rootDir => {
      const raw = String(rootDir || '').trim();
      if (!raw) return '';
      const resolved = path.resolve(raw);
      if (path.basename(resolved) === safeFolderName) return resolved;
      return path.join(resolved, safeFolderName);
    };

    const fallbackRoot = config.getTranscodeTempPath();
    add(resolveSafeDir(fallbackRoot));

    let configured = '';
    try {
      const v = await tableConfig.getConfigByKey('transcodeTempDir');
      configured = v ? String(v).trim() : '';
    } catch (_) {}

    if (configured) {
      const ok = await this._testWritableDir(configured);
      if (ok) add(resolveSafeDir(configured));
    }

    return dirs;
  }

  async _testWritableDir(dir) {
    const safeFolderName = config.getTranscodeTempSafeFolderName();
    const raw = String(dir || '').trim();
    if (!raw) return false;
    const resolved = path.resolve(raw);
    try {
      const st = await fs.stat(resolved);
      if (!st.isDirectory()) return false;
      const safeDir = path.basename(resolved) === safeFolderName ? resolved : path.join(resolved, safeFolderName);
      await fs.ensureDir(safeDir);
      await fs.access(safeDir, fsNative.constants.W_OK);
      const name = `.nascabos_write_test_${Date.now()}_${Math.random().toString(16).slice(2)}.tmp`;
      const p = path.join(safeDir, name);
      await fs.writeFile(p, 'ok', 'utf8');
      await fs.unlink(p);
      return true;
    } catch (_) {
      return false;
    }
  }
  /**
   * 调度 file_log 表清理任务：每 24 小时清理超过 90 天的操作记录
   */
  scheduleFileLogCleanup() {
    this.cleanupOldFileLogs();

    const intervalMs = 24 * 60 * 60 * 1000;
    setInterval(() => {
      this.cleanupOldFileLogs();
    }, intervalMs);
  }

  /**
   * 清理超过 90 天的文件操作日志
   */
  async cleanupOldFileLogs() {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const tableExists = await knex.schema.hasTable('file_log');
      if (!tableExists) return;

      const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
      const count = await knex('file_log').where('create_time', '<', ninetyDaysAgo).delete();

      if (count > 0) {
        Logger.info(`🧹 Purged ${count} file_log rows older than 90 days`);
      }
    } catch (error) {
      Logger.error('❌  clean expired file_log failed:', error);
    }
  }

  /**
   * 调度Token清理任务
   */
  scheduleTokenCleanup() {
    // 立即执行一次
    this.cleanupExpiredTokens();

    // 设置定时器 (12小时 = 12 * 60 * 60 * 1000 毫秒)
    const intervalMs = 12 * 60 * 60 * 1000;

    setInterval(() => {
      this.cleanupExpiredTokens();
    }, intervalMs);


  }

  /**
   * 清理过期Token的具体逻辑
   */
  async cleanupExpiredTokens() {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const now = new Date();

      // 删除expire_time小于当前时间的记录
      const count = await knex('user_token').where('expire_time', '<', now).delete();

      if (count > 0) {
        Logger.info(`🧹 Purged ${count} expired tokens`);
      } else {
        // Logger.debug('🧹 没有需要清理的过期Token');
      }
    } catch (error) {
      Logger.error('❌  clean expired tokens failed:', error);
    }
  }

  /**
   * 调度临时文件清理任务
   */
  scheduleTempFileCleanup() {
    // 立即执行一次
    this.cleanupTempFiles();

    // 设置定时器 (12小时 = 12 * 60 * 60 * 1000 毫秒)
    const intervalMs = 12 * 60 * 60 * 1000;

    setInterval(() => {
      this.cleanupTempFiles();
    }, intervalMs);


  }

  /**
   * 清理过期临时文件的具体逻辑
   */
  async cleanupTempFiles() {
    try {
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const config = require('../config/config');
      const fs = require('fs-extra');

      // 计算24小时前的时间（使用时间戳）
      const now = Date.now();
      const twentyFourHoursAgo = now - 24 * 60 * 60 * 1000;

      // 查询24小时前创建的临时文件记录
      const oldTempFiles = await knex('temp_file').where('create_time', '<', twentyFourHoursAgo).select('id', 'path');

      let deletedCount = 0;
      let filesDeleted = 0;
      const path = require('path');

      for (const tempFile of oldTempFiles) {
        const { id, path: filePath } = tempFile;

        // 验证文件名必须以uploadTempPartPrefix开头
        const filename = path.basename(filePath);
        if (filename.startsWith(config.copyTempFilePrefix)) {
          // 删除文件
          try {
            if (await fs.pathExists(filePath)) {
              await fs.remove(filePath);

              filesDeleted++;
            }
          } catch (error) {
            Logger.error(`❌  clean temp file failed: ${filePath}`, error);
          } finally {
            // 删除数据库记录
            await knex('temp_file').where('id', id).del();
          }
        } else if (filename.startsWith(config.uploadTempPartPrefix)) {
          try {
            // 删除文件
            if (await fs.pathExists(filePath)) {
              await fs.remove(filePath);

              filesDeleted++;
            }

            // 检查并删除对应的分块目录
            const filename = path.basename(filePath);
            const hashPart = filename.replace(config.uploadTempPartPrefix, '');
            const chunkDirName = `${config.uploadTempFilePrefix}${hashPart}`;
            const chunkDir = path.dirname(filePath) + '/' + chunkDirName;

            if (await fs.pathExists(chunkDir)) {
              await fs.remove(chunkDir);

              filesDeleted++;
            }

            deletedCount++;
          } catch (error) {
            Logger.error(`❌  clean temp file failed: ${filePath}`, error);
          } finally {
            // 删除数据库记录
            await knex('temp_file').where('id', id).del();
          }
        }
      }

      if (deletedCount > 0) {
        Logger.info(`🧹 Purged ${deletedCount} expired temp-file rows, deleted ${filesDeleted} files`);
      } else {
        // Logger.debug('🧹 没有需要清理的过期临时文件');
      }
    } catch (error) {
      Logger.error('❌  clean expired temp files failed:', error);
    }
  }
}

// 启动Worker实例
new BackgroundTaskWorker();
