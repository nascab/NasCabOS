'use strict';

const fs = require('fs');
const path = require('path');
const Watchpack = require('watchpack');

const Logger = require('../../utils/logger');
const FileUtil = require('../../utils/fileUtil');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const photoIndexIndexUtil = require('./photoIndexIndexUtil');
const { getMediaTypeByExt } = require('./photoIndexUtil');
const fileUtil = require('../../utils/fileUtil');
/**
 * photoWatchWorker（常驻）：
 * - 监听 photo_source 表里 scan_when_change=1 的来源目录
 * - 发生新增/删除/修改时，增量同步 photo_index 索引表
 *   - 文件新增：生成索引
 *   - 文件删除：删除索引（并顺带清理 live_filename/raw_filename 的引用）
 *   - 文件已存在：对比 size，不一致则删除旧索引并重建
 *
 * 设计要点：
 * - 使用 watchpack 聚合变动（aggregateTimeout），避免频繁触发导致的抖动
 * - 维护 pendingChangedPaths/pendingRemovedPaths 两个集合：
 *   - pendingChangedPaths：待处理的“变动路径”（文件/目录）
 *   - pendingRemovedPaths：待处理的“删除路径”（文件/目录）
 * - flushPending 串行执行（processing 锁），确保同一时间只跑一轮增量同步
 * - resetWatchers 支持重设监听：关闭旧监听 -> 重新读 DB -> 重新 watch
 *
 * 进程间协议：
 * - 主进程通过 worker.send({type:'reset'}) 触发重设监听
 * - worker 收到 {type:'stop'} 退出
 */
class PhotoWatchWorker {
  constructor() {
    this.knex = null;
    this.watchpack = null;
    this.watchedRoots = [];
    this.pendingChangedPaths = new Set();
    this.pendingRemovedPaths = new Set();
    this.flushTimer = null;
    this.newPhotoDebounceTimer = null;
    this.newPhotoDebounceMs = 10 * 1000;
    this.processing = false;
    this.reflushRequested = false;
    this.exiting = false;
    this.init();
  }

  sendMessage(type, data = undefined) {
    if (typeof process.send !== 'function') return;
    try {
      process.send({ type, data });
    } catch (_) {}
  }

  scheduleNewPhotoCome() {
    if (this.newPhotoDebounceTimer) clearTimeout(this.newPhotoDebounceTimer);
    this.newPhotoDebounceTimer = setTimeout(() => {
      this.newPhotoDebounceTimer = null;
      this.sendMessage('newPhotoCome');
    }, this.newPhotoDebounceMs);
  }

  async requestExit(code = 0, reason = '') {
    if (this.exiting) return;
    this.exiting = true;

    if (reason) Logger.info(reason);

    // 先做资源清理，尽量减少“退出卡住”的概率。
    this.closeWatchpack();
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    if (this.newPhotoDebounceTimer) {
      clearTimeout(this.newPhotoDebounceTimer);
      this.newPhotoDebounceTimer = null;
    }

    try {
      if (this.knex && typeof this.knex.destroy === 'function') {
        await this.knex.destroy();
      }
    } catch (_) {}

    // 正常退出兜底：若事件循环异常卡住，超时后强制结束进程。
    const forceTimer = setTimeout(() => {
      try {
        process.kill(process.pid, 'SIGKILL');
      } catch (_) {}
    }, 2000);
    if (typeof forceTimer.unref === 'function') forceTimer.unref();

    try {
      process.exit(Number.isFinite(Number(code)) ? Number(code) : 0);
    } catch (_) {
      try {
        process.kill(process.pid, 'SIGKILL');
      } catch (_) {}
    }
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);
      this.knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
      await this.resetWatchers();

    } catch (err) {
      Logger.error('❌ photoWatchWorker init failed:', err);
      process.exit(1);
    }
  }

  /**
   * 读取需要监听的来源目录列表：
   * - 从 photo_source 取 scan_when_change=1 的 path
   * - 去重后校验目录存在且为目录
   */
  async getWatchedSourcePaths() {
    const rows = await this.knex('photo_source')
      .select('path')
      .where({ scan_when_change: 1 })
      .catch(() => []);

    const unique = new Set();
    for (const r of rows || []) {
      const p = r && r.path ? String(r.path) : '';
      if (p) unique.add(p);
    }

    const res = [];
    for (const p of unique) {
      try {
        const stat = await fs.promises.stat(p);
        if (stat && stat.isDirectory()) res.push(p);
      } catch (_) {}
    }
    return res;
  }

  /**
   * 构建“监听根目录”列表，用于快速判断某个变动是否属于监听范围。
   * - root: 规范化后的绝对路径
   * - prefix: root + path.sep（用于 startsWith）
   */
  buildWatchedRoots(paths) {
    const roots = [];
    for (const p of paths) {
      const rp = path.resolve(p);
      const prefix = rp.endsWith(path.sep) ? rp : `${rp}${path.sep}`;
      roots.push({ root: rp, prefix });
    }
    roots.sort((a, b) => a.prefix.length - b.prefix.length);
    return roots;
  }

  /**
   * 判断路径是否在任意监听根目录下（包含根目录自身）。
   */
  isWithinWatchedRoot(targetPath) {
    if (!targetPath) return false;
    const rp = path.resolve(targetPath);
    for (const r of this.watchedRoots) {
      if (rp === r.root) return true;
      if (rp.startsWith(r.prefix)) return true;
    }
    return false;
  }

  /**
   * 检测目标目录所属的根目录是否还存在
   */
  checkRootPathExist(targetPath) {
    if (!targetPath) return false;
    const rp = path.resolve(targetPath);
    let rootPath = null;
    for (const r of this.watchedRoots) {
      if (rp === r.root) {
        rootPath = r.root;
        break;
      }
      if (rp.startsWith(r.prefix)) {
        rootPath = r.root;
        break;
      }
    }
    return fs.existsSync(rootPath);
  }

  isWatchedRoot(targetPath) {
    if (!targetPath) return false;
    const rp = path.resolve(targetPath);
    for (const r of this.watchedRoots) {
      if (rp === r.root) return true;
    }
    return false;
  }

  async ensureDirectorySelfIndexed(dirPath) {
    if (!dirPath) return;
    const resolved = path.resolve(dirPath);
    const parentDir = path.dirname(resolved);
    const folderName = path.basename(resolved);
    if (!parentDir || !folderName) return;

    const existed = await this.knex('photo_index')
      .where({ path: parentDir, filename: folderName, is_file: 0 })
      .first('id')
      .catch(() => null);
    if (existed && existed.id) return;

    await photoIndexIndexUtil.indexOneDirectory({
      knex: this.knex,
      fullPath: resolved,
      dirPath: parentDir,
      filename: folderName,
    });
  }

  /**
   * 关闭当前 watchpack（若存在）。
   */
  closeWatchpack() {
    if (!this.watchpack) return;
    try {
      this.watchpack.close();
    } catch (_) {}
    this.watchpack = null;
  }

  /**
   * 重设监听：
   * - 关闭旧监听
   * - 清空 pending 队列
   * - 重新读取 scan_when_change=1 的来源目录
   * - 若无目录需要监听：按需求直接退出 worker
   * - 启动 watchpack 监听目录树
   */
  async resetWatchers() {
    this.closeWatchpack();
    this.pendingChangedPaths.clear();
    this.pendingRemovedPaths.clear();

    const sourcePaths = await this.getWatchedSourcePaths();
    this.watchedRoots = this.buildWatchedRoots(sourcePaths);

    if (!sourcePaths || sourcePaths.length === 0) {
      await this.requestExit(0, 'ℹ️ scan_when_change=1 的来源目录为空，photoWatchWorker 将退出');
      return;
    }

    const wp = new Watchpack({
      aggregateTimeout: 1000,
      poll: false,
      ignored: fileUtil.watchIgnoredList,
    });

    wp.on('change', p => {
      this.scheduleFromPath(String(p || ''), false);
    });
    wp.on('remove', p => {
      this.scheduleFromPath(String(p || ''), true);
    });
    wp.watch({ directories: sourcePaths, startTime: Date.now() });
    this.watchpack = wp;
  }

  /**
   * 将变动路径加入“待处理队列”：
   * - remove：记录到 pendingRemovedPaths
   * - change：记录到 pendingChangedPaths
   * - 通过 setTimeout 做二次去抖（800ms），避免高频触发下过多 DB/IO
   */
  scheduleFromPath(p, isRemove) {
    if (!p) return;
    // console.log('文件/目录变动:', p);
    const resolved = path.resolve(p);
    if (!this.isWithinWatchedRoot(resolved)) return;

    if (isRemove) {
      this.pendingRemovedPaths.add(resolved);
    } else {
      this.pendingChangedPaths.add(resolved);
    }

    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      this.flushPending().catch(err => Logger.error('❌ photoWatchWorker flushPending error:', err));
    }, 800);
  }

  /**
   * 执行一轮增量同步：
   * - 用 processing 锁保证串行，避免多轮并发导致重复/交错的 DB 写入
   * - 若执行期间又来了一波变动，则置 reflushRequested=true，结束后再补跑一轮
   */
  async flushPending() {
    if (this.processing) {
      this.reflushRequested = true;
      return;
    }
    this.processing = true;

    const removedPaths = Array.from(this.pendingRemovedPaths);
    const changedPaths = Array.from(this.pendingChangedPaths);
    this.pendingRemovedPaths.clear();
    this.pendingChangedPaths.clear();

    try {
      // 删除事件：尽量只做“单目标删除”
      for (const p of removedPaths) {
        if (!this.isWithinWatchedRoot(p)) continue;
        await this.handleRemovedPath(p);
      }

      // 变动事件：
      // - 文件：只检查该文件本身（是否存在、索引是否存在、size 是否一致）
      // - 目录：同步该目录（不处理父目录）
      for (const p of changedPaths) {
        if (!this.isWithinWatchedRoot(p)) continue;
        await this.handleChangedPath(p);
      }
    } finally {
      this.processing = false;
    }

    if (this.reflushRequested) {
      this.reflushRequested = false;
      await this.flushPending();
    }
  }

  /**
   * 清理被删除文件可能留下的“配对引用”：
   * - live_filename：LivePhoto 分离视频配对
   * - raw_filename：RAW 配对
   *
   * 注意：这里只做引用字段置空，索引行的删除由本 worker 的删除逻辑负责。
   */
  async unlinkMissingPairRefs(removedPath) {
    const dirPath = path.dirname(removedPath);
    const filename = path.basename(removedPath);
    if (!dirPath || !filename) return;

    await this.knex('photo_index')
      .where({ path: dirPath, live_filename: filename })
      .update({ live_filename: null, check_time: Date.now() })
      .catch(() => {});

    await this.knex('photo_index')
      .where({ path: dirPath, raw_filename: filename })
      .update({ raw_filename: null, check_time: Date.now() })
      .catch(() => {});
  }

  async deleteFileIndex(dirPath, filename) {
    console.log('删除文件索引', dirPath, filename);
    if (!dirPath || !filename) return;
    await this.knex('photo_index')
      .where({ path: dirPath, filename, is_file: 1 })
      .delete()
      .catch(() => {});
  }

  async deleteDirectoryIndexes(dirPath) {
    console.log('删除目录索引', dirPath);
    if (!dirPath) return;
    const resolved = path.resolve(dirPath);
    const scanPrefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;

    await this.knex('photo_index')
      .where(qb => {
        qb.where('path', resolved).orWhere('path', 'like', `${scanPrefix}%`);
      })
      .delete()
      .catch(() => {});

    const parentDir = path.dirname(resolved);
    const folderName = path.basename(resolved);
    if (parentDir && folderName) {
      await this.knex('photo_index')
        .where({ path: parentDir, filename: folderName, is_file: 0 })
        .delete()
        .catch(() => {});
    }
  }

  async handleRemovedPath(p) {
    //如果文件还存在直接返回
    try {
      const exists = fs.existsSync(p);
      if (exists) return;
    } catch (_) {}

    const filename = path.basename(p);
    const ext = path.extname(filename).toLowerCase();
    const mediaType = getMediaTypeByExt(ext);

    if (mediaType === 1 || mediaType === 2 || FileUtil.isTemporaryOrDownloadingFile(filename) || FileUtil.isHideFile(filename)) {
      const dirPath = path.dirname(p);
      await this.deleteFileIndex(dirPath, filename);
      await this.unlinkMissingPairRefs(p);
      return;
    }

    await this.deleteDirectoryIndexes(p);
  }

  async handleChangedPath(p) {
    // 变动的文件所在的根目录不存在了 不处理
    if (!this.checkRootPathExist(p)) {
      Logger.info('File event: root missing, skip', p);
      return;
    }
    // 确保文件存在 不存在则走删除
    let stat;
    try {
      stat = fs.statSync(p);
    } catch (_) {
      await this.handleRemovedPath(p);
      return;
    }

    if (stat.isDirectory()) {
      if (!this.isWatchedRoot(p)) {
        await this.ensureDirectorySelfIndexed(p);
      }
      await this.syncDirectory(p);
      return;
    }

    if (!stat.isFile()) return;
    const filename = path.basename(p);
    if (FileUtil.shouldSkipIndexingFilename(filename)) return;
    const ext = path.extname(filename).toLowerCase();
    const mediaType = getMediaTypeByExt(ext);
    if (mediaType !== 1 && mediaType !== 2) return;

    const dirPath = path.dirname(p);
    const existed = await this.knex('photo_index')
      .where({ path: dirPath, filename, is_file: 1 })
      .first('id', 'size')
      .catch(() => null);

    if (existed && existed.id) {
      const oldSize = Number(existed.size || 0) || 0;
      if (oldSize === Number(stat.size || 0)) {

        return;
      }
      await this.knex('photo_index')
        .where({ id: existed.id })
        .delete()
        .catch(() => {});
    }
    Logger.info('File event: reindex file');
    const isNew = !(existed && existed.id);
    const ok = await photoIndexIndexUtil.indexOneFile({
      knex: this.knex,
      fullPath: p,
      dirPath,
      filename,
      ext,
    });
    if (isNew && ok) this.scheduleNewPhotoCome();
  }

  /**
   * 同步一个目录：
   * - 如果 dirPath 不存在：
   *   - 直接按 path 前缀删除该目录下所有索引
   * - 如果是目录：
   *   - 深度遍历目录树：
   *     - 子目录：补齐目录索引（is_file=0）
   *     - 文件：若为图片/RAW/视频则做索引增量（新增 / size 不一致重建）
   */
  async syncDirectory(dirPath) {
    console.log('同步目录索引', dirPath);
    if (!dirPath) return;
    let stat;
    try {
      stat = await fs.promises.stat(dirPath);
    } catch (_) {
      await this.deleteDirectoryIndexes(dirPath);
      return;
    }
    if (!stat.isDirectory()) return;

    const stack = [dirPath];
    const seenDirs = new Set();

    while (stack.length > 0) {
      const currentDir = stack.pop();
      const resolvedDir = path.resolve(currentDir);
      if (seenDirs.has(resolvedDir)) continue;
      seenDirs.add(resolvedDir);

      let entries;
      try {
        entries = await fs.promises.readdir(currentDir, { withFileTypes: true });
      } catch (_) {
        continue;
      }

      for (const ent of entries) {
        const name = ent.name;
        if (FileUtil.isSystemFile(name)) continue;
        if (FileUtil.isHideFile(name)) continue;
        if (FileUtil.isTemporaryOrDownloadingFile(name)) continue;
        const fullPath = path.join(currentDir, name);

        if (ent.isDirectory()) {
          await photoIndexIndexUtil.indexOneDirectory({
            knex: this.knex,
            fullPath,
            dirPath: currentDir,
            filename: name,
          });
          stack.push(fullPath);
          continue;
        }

        if (!ent.isFile()) continue;
        const ext = path.extname(name).toLowerCase();
        const mediaType = getMediaTypeByExt(ext);
        if (mediaType !== 1 && mediaType !== 2) continue;

        let fileStat;
        try {
          fileStat = await fs.promises.stat(fullPath);
        } catch (_) {
          continue;
        }
        if (!fileStat.isFile()) continue;

        const existed = await this.knex('photo_index')
          .where({ path: currentDir, filename: name, is_file: 1 })
          .first('id', 'size')
          .catch(() => null);

        if (existed && existed.id) {
          const oldSize = Number(existed.size || 0) || 0;
          if (oldSize === Number(fileStat.size || 0)) continue;
          await this.knex('photo_index')
            .where({ id: existed.id })
            .delete()
            .catch(() => {});
        }

        const isNew = !(existed && existed.id);
        const ok = await photoIndexIndexUtil.indexOneFile({
          knex: this.knex,
          fullPath,
          dirPath: currentDir,
          filename: name,
          ext,
        });
        if (isNew && ok) this.scheduleNewPhotoCome();
      }
    }
  }
}

const worker = new PhotoWatchWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'reset') {
    // 来源目录增删/配置变更时，主进程触发此消息，让 worker 重新读取来源目录并重建监听
    worker.resetWatchers().catch(err => Logger.error('❌ photoWatchWorker reset failed:', err));
  }
  if (message.type === 'stop') {
    worker.requestExit(0, '🛑 photoWatchWorker 收到 stop 指令，准备退出').catch(() => {
      process.exit(0);
    });
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ photoWatchWorker uncaughtException', err);
  worker.requestExit(1, '❌ photoWatchWorker 因uncaughtException退出').catch(() => {
    process.exit(1);
  });
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ photoWatchWorker unhandledRejection', reason);
  worker.requestExit(1, '❌ photoWatchWorker 因unhandledRejection退出').catch(() => {
    process.exit(1);
  });
});
