'use strict';
const Logger = require('../utils/logger');
const dbUtil = require('../db/dbUtil');
const knexUtil = require('../db/knexUtil');
const tableFileLog = require('../db/table/tableFileLog');
const fs = require('fs');
const path = require('path');
const checkDiskSpace = require('check-disk-space').default;
const config = require('../config/config');
const crypto = require('crypto');
class FileOperationWorker {
  constructor() {
    this.isRunning = false;
    this.maxConcurrentOps = 5;
    this.currentOps = 0;
    this.pollingInterval = 1000; // 1 second
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);

      this.startLoop();
    } catch (err) {
      Logger.error('❌ file operation worker init failed:', err);
      process.exit(1);
    }
  }

  async startLoop() {
    this.isRunning = true;
    while (this.isRunning) {
      await this.processTasks();
      // 执行间隔，单位毫秒
      await new Promise(resolve => setTimeout(resolve, this.pollingInterval));
    }
  }

  async processTasks() {
    try {
      if (this.currentOps >= this.maxConcurrentOps) {
        return;
      }
      // 当前并发执行任务数
      const availableSlots = this.maxConcurrentOps - this.currentOps;
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);

      // 获取等待执行的任务列表
      const tasks = await knex('file_log').where('state', tableFileLog.STATE_WAIT).orderBy('create_time', 'asc').limit(availableSlots);

      if (tasks.length === 0) {
        // "没有待执行任务后退出" (Exit after no pending tasks)
        // "有多个wait状态的任务需要控制并发数量"
        if (this.currentOps === 0) {
          Logger.info('✅ No pending file tasks, worker exiting');
          process.exit(0);
        }
        return;
      }

      for (const task of tasks) {
        this.currentOps++;
        this.runTask(task);
      }
    } catch (err) {
      Logger.error('❌ file operation loop error:', err);
    }
  }

  async updateTaskState(taskId, state, message = null) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    await knex('file_log').where('id', taskId).update({
      state,
      message,
    });
  }

  async updateTaskProgress(taskId, copiedSize) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    await knex('file_log').where('id', taskId).update({
      copied_size: copiedSize,
    });
  }

  async updateTaskTotalSize(taskId, totalSize) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    await knex('file_log').where('id', taskId).update({
      total_size: totalSize,
    });
  }

  async calculateTotalSize(paths) {
    let total = 0;
    for (const p of paths) {
      try {
        const stat = await fs.promises.lstat(p);
        if (stat.isDirectory()) {
          total += await this.getDirSize(p);
        } else {
          total += stat.size;
        }
      } catch (e) {
        // ignore
      }
    }
    return total;
  }

  async getDirSize(dir) {
    let size = 0;
    try {
      const files = await fs.promises.readdir(dir, { withFileTypes: true });
      for (const file of files) {
        const fullPath = path.join(dir, file.name);
        if (file.isDirectory()) {
          size += await this.getDirSize(fullPath);
        } else if (file.isSymbolicLink()) {
          // Add symlink size itself, don't follow
          const stat = await fs.promises.lstat(fullPath);
          size += stat.size;
        } else {
          const stat = await fs.promises.stat(fullPath);
          size += stat.size;
        }
      }
    } catch (e) {}
    return size;
  }
  // 检查目标目录是否有足够空间
  async checkFreeSpace(targetDir, requiredSize) {
    try {
      // Resolve path to ensure it is absolute
      let checkPath = path.resolve(targetDir);
      while (true) {
        try {
          await fs.promises.access(checkPath, fs.constants.F_OK);
          break; // Found existing path
        } catch {
          const parent = path.dirname(checkPath);
          if (parent === checkPath) {
            break;
          }
          checkPath = parent;
        }
      }

      const diskSpace = await checkDiskSpace(checkPath);
      const freeSpace = BigInt(diskSpace.free);
      if (freeSpace < BigInt(requiredSize)) {
        throw new Error('Insufficient disk space');
      }
    } catch (err) {
      if (err.message === 'Insufficient disk space') throw err;
      Logger.warn(`Failed to check disk space for ${targetDir}: ${err.message}`);
    }
  }

  async runTask(task) {
    try {
      // 标记任务为处理中
      await this.updateTaskState(task.id, tableFileLog.STATE_PROCESSING);
      const sourcePaths = JSON.parse(task.source_path);
      const targetDir = task.target_path;
      const type = task.type;

      // Validate sourcePaths
      if (!Array.isArray(sourcePaths) || sourcePaths.length === 0) {
        throw new Error('Invalid source_path');
      }

      // 计算总大小
      const totalSize = await this.calculateTotalSize(sourcePaths);
      // 更新任务总大小
      await this.updateTaskTotalSize(task.id, totalSize);

      // 检查磁盘空间
      if (type === tableFileLog.TYPE_COPY || type === tableFileLog.TYPE_MOVE) {
        await this.checkFreeSpace(targetDir, totalSize);
      }

      // 执行文件操作
      if (type === tableFileLog.TYPE_COPY) {
        await this.handleCopy(task.id, sourcePaths, targetDir);
      } else if (type === tableFileLog.TYPE_MOVE) {
        await this.handleMove(task.id, sourcePaths, targetDir);
      } else if (type === tableFileLog.TYPE_DELETE) {
        throw new Error(`Unsupported operation type: ${type}`);
      } else {
        throw new Error(`Unknown operation type: ${type}`);
      }
      // Success
      await this.updateTaskState(task.id, tableFileLog.STATE_SUCCESS, 'Success');
      // Ensure 100% progress
      await this.updateTaskProgress(task.id, totalSize);
      Logger.info(`✅ File task (ID:${task.id}) ok, ${totalSize} bytes`, 'source', sourcePaths, 'target', targetDir);
    } catch (err) {
      Logger.error(`❌ file task (ID:${task.id}) failed:`, err);
      if (err.message === 'CANCELLED') {
        await this.updateTaskState(task.id, tableFileLog.STATE_CANCELLED, err.message || 'CANCELLED');
      } else {
        await this.updateTaskState(task.id, tableFileLog.STATE_ERROR);
      }
    } finally {
      this.currentOps--;
    }
  }

  async checkCancelled(taskId, getResult) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const row = await knex('file_log').where('id', taskId).select('state').first();
    if (row && row.state === tableFileLog.STATE_CANCELLED) {
      Logger.info(`File task (ID:${taskId}) cancelled`);
      if (getResult) {
        return true;
      }
      throw new Error('CANCELLED');
    }
    return false;
  }

  async copyFileWithTemp(taskId, src, dest, baseCopiedSize) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const destDir = path.dirname(dest);
    const filename = path.basename(dest);
    const timestamp = Date.now();
    const hash = crypto
      .createHash('md5')
      .update(filename + timestamp)
      .digest('hex');
    const tempFilename = `${config.copyTempFilePrefix}${hash}`;
    const tempPath = path.join(destDir, tempFilename);

    await knex('temp_file').insert({
      path: tempPath,
      type: 'copy',
      create_time: timestamp,
    });

    try {
      // Stream copy with progress
      const readStream = fs.createReadStream(src);
      const writeStream = fs.createWriteStream(tempPath);

      let fileCopiedSize = 0;
      let lastUpdateSize = 0;
      const UPDATE_THRESHOLD = 100 * 1024 * 1024; // 100MB

      await new Promise((resolve, reject) => {
        readStream.on('error', reject);
        writeStream.on('error', reject);

        readStream.on('data', async chunk => {
          fileCopiedSize += chunk.length;
          if (fileCopiedSize - lastUpdateSize >= UPDATE_THRESHOLD) {
            readStream.pause();
            lastUpdateSize = fileCopiedSize;
            if (await this.checkCancelled(taskId, true)) {
              reject(new Error('CANCELLED'));
            }
            await this.updateTaskProgress(taskId, baseCopiedSize + fileCopiedSize);
            readStream.resume();
          }
        });

        writeStream.on('finish', resolve);
        readStream.pipe(writeStream);
      });

      await fs.promises.rename(tempPath, dest);
      await knex('temp_file').where('path', tempPath).del();
    } catch (err) {
      throw err;
    }
  }

  async handleCopy(taskId, sourcePaths, targetDir) {
    if (!targetDir) throw new Error('Target path is required for copy');
    await this.checkCancelled(taskId);
    // 检查目标路径是否存在冲突
    await this.checkTargetConflict(sourcePaths, targetDir);
    await this.checkCancelled(taskId);
    await fs.promises.mkdir(targetDir, { recursive: true });

    let copiedSize = 0;

    // 递归复制文件
    const copyRecursive = async (src, dest) => {
      await this.checkCancelled(taskId);
      const stat = await fs.promises.lstat(src);
      if (stat.isDirectory()) {
        await fs.promises.mkdir(dest, { recursive: true });
        const entries = await fs.promises.readdir(src);
        for (const entry of entries) {
          await copyRecursive(path.join(src, entry), path.join(dest, entry));
        }
      } else if (stat.isSymbolicLink()) {
        const linkTarget = await fs.promises.readlink(src);
        await fs.promises.symlink(linkTarget, dest);
        copiedSize += stat.size;
        await this.updateTaskProgress(taskId, copiedSize);
      } else {
        await this.copyFileWithTemp(taskId, src, dest, copiedSize);
        copiedSize += stat.size;
        await this.updateTaskProgress(taskId, copiedSize);
      }
    };
    // 递归复制每个源文件
    for (const src of sourcePaths) {
      const basename = path.basename(src);
      const dest = path.join(targetDir, basename);
      await copyRecursive(src, dest);
    }
  }

  async handleMove(taskId, sourcePaths, targetDir) {
    if (!targetDir) throw new Error('Target path is required for move');
    await this.checkCancelled(taskId);
    // 检查目标路径是否存在冲突
    await this.checkTargetConflict(sourcePaths, targetDir);
    await this.checkCancelled(taskId);
    await fs.promises.mkdir(targetDir, { recursive: true });

    let movedSize = 0;

    for (const src of sourcePaths) {
      await this.checkCancelled(taskId);
      const basename = path.basename(src);
      const dest = path.join(targetDir, basename);
      try {
        await fs.promises.rename(src, dest);
        const stat = await fs.promises.stat(dest);
        if (stat.isDirectory()) {
          movedSize += await this.getDirSize(dest);
        } else {
          movedSize += stat.size;
        }
        await this.updateTaskProgress(taskId, movedSize);
      } catch (err) {
        if (err.code === 'EXDEV') {
          console.log('跨硬盘rename失败，使用递归复制+删除源文件');
          // 跨硬盘rename失败，使用递归复制+删除源文件
          const copyRecursive = async (s, d) => {
            await this.checkCancelled(taskId);
            const st = await fs.promises.lstat(s);
            if (st.isDirectory()) {
              await fs.promises.mkdir(d, { recursive: true });
              const entries = await fs.promises.readdir(s);
              for (const entry of entries) {
                await copyRecursive(path.join(s, entry), path.join(d, entry));
              }
            } else if (st.isSymbolicLink()) {
              const linkTarget = await fs.promises.readlink(s);
              await fs.promises.symlink(linkTarget, d);
              movedSize += st.size;
              await this.updateTaskProgress(taskId, movedSize);
            } else {
              await this.copyFileWithTemp(taskId, s, d, movedSize);
              movedSize += st.size;
              await this.updateTaskProgress(taskId, movedSize);
            }
          };
          await copyRecursive(src, dest);
          // 递归删除源文件
          await this.checkCancelled(taskId);
          await fs.promises.rm(src, { recursive: true, force: true });
        } else {
          throw err;
        }
      }
    }
  }

  async checkTargetConflict(sourcePaths, targetDir) {
    if (!sourcePaths || !Array.isArray(sourcePaths) || !targetDir) return;

    // Check source contain target
    const target = path.resolve(targetDir);
    for (const src of sourcePaths) {
      const source = path.resolve(src);
      if (target === source) {
        throw new Error(`Target is source: ${path.basename(src)}`);
      }
      const relative = path.relative(source, target);
      if (relative && !relative.startsWith('..') && !path.isAbsolute(relative)) {
        throw new Error(`Target is subdirectory of source: ${path.basename(src)}`);
      }
    }

    try {
      await fs.promises.access(targetDir, fs.constants.F_OK);
    } catch {
      return;
    }
    for (const src of sourcePaths) {
      const basename = path.basename(src);
      const dest = path.join(targetDir, basename);
      try {
        await fs.promises.access(dest, fs.constants.F_OK);
        throw new Error(`Target file already exists: ${basename}`);
      } catch (err) {
        if (err.message.startsWith('Target file already exists')) {
          throw err;
        }
      }
    }
  }
}

new FileOperationWorker();
