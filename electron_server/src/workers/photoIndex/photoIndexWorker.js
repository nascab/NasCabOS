'use strict';
const fs = require('fs');
const Logger = require('../../utils/logger');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const photoIndexIndexUtil = require('./photoIndexIndexUtil');

const { walkPhotoEntries } = require('./photoIndexUtil');

class PhotoIndexWorker {
  constructor() {
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);

      await this.runUntilEmpty();
      process.exit(0);
    } catch (err) {
      Logger.error('❌ photo index worker init failed:', err);
      process.exit(1);
    }
  }

  /**
   * 启动后把任务队列清空，队列为空则退出。
   * 这样只有“有扫描需求时才会有 Worker 进程”，资源更节省。
   */
  async runUntilEmpty() {
    while (true) {
      const task = await this.getNextTask();
      if (!task) {
        Logger.info('✅ No pending photo scan tasks, worker exiting');
        return;
      }
      try {
        await this.runTask(task);
      } catch (err) {
        Logger.error('❌ Photo scan task failed:', err);
        await this.deleteTask(task);
      }
    }
  }

  /**
   * 取队列里最早的一条扫描任务（FIFO）。
   * 返回 null 表示任务队列为空。
   */
  async getNextTask() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    const tasks = await knex('photo_scan_task').orderBy('create_time', 'asc').limit(1);
    if (!tasks || tasks.length === 0) return null;
    return tasks[0];
  }

  async runTask(task) {
    const scanPath = task && task.scan_path ? String(task.scan_path) : '';
    if (!scanPath) {
      await this.deleteTask(task);
      return;
    }

    let stat;
    try {
      stat = await fs.promises.stat(scanPath);
    } catch {
      Logger.info('Scan path no longer exists', scanPath);
      await this.deleteTask(task);
      return;
    }
    if (!stat.isDirectory()) {
      Logger.info('Scan path is not a directory', scanPath);
      await this.deleteTask(task);
      return;
    }

    const start = Date.now();

    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    // 若来源目录已被用户删除（photo_source 中不存在），则立即结束任务
    const sourceStillExistsAtStart = await this.isSourceStillExists(scanPath);
    if (!sourceStillExistsAtStart) {
      Logger.info('Photo library: source removed, cancel scan', scanPath);
      await this.deleteTask(task);
      return;
    }

    // 记录来源目录最后一次扫描时间（如果来源记录仍存在）
    await knex('photo_source')
      .where({ path: scanPath })
      .update({ last_scan_time: Date.now() })
      .catch(() => {});

    // 扫描前：把索引库中 scanPath 下“已不存在”的文件索引清理掉
    await photoIndexIndexUtil.deleteMissingIndexes({ knex, scanPath });

    let indexedCount = 0;
    let aborted = false;
    let lastMemLogAt = 0;
    // const maxRssMb = Math.floor(Number(process.env.PHOTO_INDEX_MAX_RSS_MB || 0));
    // const shouldAbortForMem = () => {
    //   if (!Number.isFinite(maxRssMb) || maxRssMb <= 0) return false;
    //   const rssMb = Math.round(process.memoryUsage().rss / 1024 / 1024);
    //   return rssMb >= maxRssMb;
    // };
    const maybeLogMem = () => {
      const now = Date.now();
      if (now - lastMemLogAt < 30 * 1000) return;
      lastMemLogAt = now;
      const mu = process.memoryUsage();
    };
    const completed = await walkPhotoEntries(scanPath, {
      onDirectory: async entry => {
        const stillExists = await this.isSourceStillExists(scanPath);
        if (!stillExists) {
          aborted = true;
          return false;
        }
        await photoIndexIndexUtil.indexOneDirectory({ knex, ...entry });
        return true;
      },
      onMediaFile: async entry => {
        const stillExists = await this.isSourceStillExists(scanPath);
        if (!stillExists) {
          aborted = true;
          return false;
        }

        // if (shouldAbortForMem()) {
        //   aborted = true;
        //   Logger.error('photoIndexWorker RSS limit, stopping scan early', 'maxRssMb', maxRssMb);
        //   return false;
        // }

        const ok = await photoIndexIndexUtil.indexOneFile({ knex, ...entry });
        if (ok) indexedCount++;
        maybeLogMem();
        return true;
      },
    });
    if (completed === false) aborted = true;

    Logger.info('Photo library: scan done ' + scanPath, 'elapsedMs:', Date.now() - start, 'files:', indexedCount);

    if (process.send) {
      try {
        process.send({ type: 'photoIndexingFinished', data: { scanPath, indexedCount, aborted } });
      } catch (_) {}
    }

    await this.deleteTask(task);
  }

  async deleteTask(task) {
    if (!task || !task.id) return;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    await knex('photo_scan_task')
      .where({ id: task.id })
      .delete()
      .catch(() => {});
  }

  async isSourceStillExists(scanPath) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    const row = await knex('photo_source').where({ path: scanPath }).first('id');
    return !!(row && row.id);
  }
}

new PhotoIndexWorker();

process.on('message', message => {
  if (message && message.type === 'stop') {
    process.exit(0);
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ photoIndex worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ photoIndex worker unhandledRejection', reason);
  process.exit(0);
});
