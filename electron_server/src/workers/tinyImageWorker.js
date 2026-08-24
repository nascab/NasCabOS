'use strict';

const fs = require('fs');
const path = require('path');

const Logger = require('../utils/logger');
const config = require('../config/config');
const dbUtil = require('../db/dbUtil');
const knexUtil = require('../db/knexUtil');
const fileService = require('../api/modules/file/core/fileService');
const { withHardTimeout, pathAccessible } = require('../utils/asyncTimeoutUtil');

const TINY_PATH_CHECK_MS = 8000;
const TINY_IMAGE_GEN_MS = 90 * 1000;
const TINY_VIDEO_GEN_MS = 3 * 60 * 1000;

function tinyGenTimeoutMs(filePath) {
  const ext = path.extname(String(filePath || '')).toLowerCase();
  const videoTypes = Array.isArray(config.videoTypeList) ? config.videoTypeList : [];
  return videoTypes.includes(ext) ? TINY_VIDEO_GEN_MS : TINY_IMAGE_GEN_MS;
}

async function generateTinyWithTimeout(fullPath) {
  const ms = tinyGenTimeoutMs(fullPath);
  return withHardTimeout(
    fileService.getTinyImgByPath(fullPath, undefined, { deferLargeVideo: false, deferSlowIo: false }),
    ms,
    'file.TINY_TIMEOUT'
  );
}

class TinyImageWorker {
  constructor() {
    this.isRunning = false;
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);
      await knexUtil.init(dbUtil.DB_PATHS.VIDEO_DB);

      this.photoKnex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
      this.videoKnex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
      this.isRunning = true;

      // 来源目录缓存，5 秒刷新一次，避免频繁查库
      this._sourceDirsCache = { dirs: new Set(), fetchedAt: 0 };
      await this._refreshSourceDirs();

      await this.startLoop();
    } catch (err) {
      Logger.error('❌ TinyImage Worker init failed:', err);
      process.exit(1);
    }
  }

  async _refreshSourceDirs() {
    try {
      const photoRows = await this.photoKnex('photo_source')
        .select('path')
        .catch(() => []);
      const videoRows = await this.videoKnex('video_source')
        .select('path')
        .catch(() => []);

      const dirs = new Set();
      for (const row of photoRows || []) {
        const p = row && row.path ? path.resolve(String(row.path)) : '';
        if (p) dirs.add(p);
      }
      for (const row of videoRows || []) {
        const p = row && row.path ? path.resolve(String(row.path)) : '';
        if (p) dirs.add(p);
      }

      this._sourceDirsCache = { dirs, fetchedAt: Date.now() };
    } catch (err) {
      Logger.warn('⚠️ refresh source dirs failed:', err);
    }
  }

  async _ensureSourceDirsFresh() {
    if (Date.now() - this._sourceDirsCache.fetchedAt > 3000) {
      await this._refreshSourceDirs();
    }
  }

  /**
   * 检查文件所在父目录是否属于任一配置的来源目录
   */
  _isUnderSourceDir(fullPath) {
    if (!fullPath) return false;
    const targetDir = path.resolve(path.dirname(fullPath));
    for (const srcDir of this._sourceDirsCache.dirs) {
      if (targetDir === srcDir) return true;
      if (targetDir.startsWith(srcDir + path.sep)) return true;
    }
    return false;
  }

  async startLoop() {
    console.log('TinyImage Worker startLoop');
    let processedCount = 0;
    let updatedCount = 0;
    let failedCount = 0;

    while (this.isRunning) {
      try {
        // 优先级: wait_gen_tiny > photo_index > video_index
        const waitRow = await this.getOneWait();
        if (waitRow) {
          const ok = await this.processOneWait(waitRow);
          processedCount++;
          if (ok) updatedCount++; else failedCount++;
          continue;
        }

        const photoRow = await this.getOnePhoto();
        if (photoRow) {
          const ok = await this.processOnePhoto(photoRow);
          processedCount++;
          if (ok) updatedCount++; else failedCount++;
          continue;
        }

        const videoRow = await this.getOneVideo();
        if (videoRow) {
          const ok = await this.processOneVideo(videoRow);
          processedCount++;
          if (ok) updatedCount++; else failedCount++;
          continue;
        }

        // 全部处理完毕
        break;
      } catch (err) {
        Logger.error('❌ TinyImage Worker loop error:', err);
        await new Promise(r => setTimeout(r, 1000));
      }
    }

    Logger.info(`✅ TinyImage Worker stopped: processed=${processedCount}, updated=${updatedCount}, failed=${failedCount}`);
    process.exit(0);
  }

  async getOnePhoto() {
    return this.photoKnex('photo_index')
      .select('id', 'path', 'filename', 'type')
      .where({ is_file: 1, in_trash: 0 })
      .andWhere(qb => {
        qb.where('gen_tiny', 0).orWhereNull('gen_tiny');
      })
      .whereIn('type', [1, 2])
      .orderBy('id', 'asc')
      .first()
      .catch(() => null);
  }

  async getOneVideo() {
    return this.videoKnex('video_index')
      .select('id', 'path', 'filename', 'ext')
      .where({ is_file: 1 })
      .whereIn('ext', Array.isArray(config.videoTypeList) ? config.videoTypeList : [])
      .andWhere(qb => {
        qb.where('gen_tiny', 0).orWhereNull('gen_tiny');
      })
      .orderBy('id', 'asc')
      .first()
      .catch(() => null);
  }

  async getOneWait() {
    return this.photoKnex('wait_gen_tiny')
      .select('id', 'source_path')
      .orderBy('id', 'desc')
      .first()
      .catch(() => null);
  }

  async processOnePhoto(row) {
    const id = row && row.id ? Number(row.id) : 0;
    if (!id) return false;

    const fullPath = path.join(String(row.path || ''), String(row.filename || ''));

    // 来源目录不存在则跳过
    await this._ensureSourceDirsFresh();
    if (!this._isUnderSourceDir(fullPath)) {
      await this.photoKnex('photo_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }

    if (!fullPath || !(await pathAccessible(fullPath, TINY_PATH_CHECK_MS))) return false;

    try {
      const tinyPath = await generateTinyWithTimeout(fullPath);
      if (!tinyPath) return false;
      await this.photoKnex('photo_index').where({ id }).update({ gen_tiny: 1 });
      return true;
    } catch (err) {
      const msg = err && err.message ? String(err.message) : '';
      if (msg === 'file.TINY_TIMEOUT') {
        Logger.warn(`⏱ thumbnail gen timed out: ${fullPath}`);
      } else {
        Logger.error(`❌ thumbnail gen failed: ${fullPath}`, err);
      }
      await this.photoKnex('photo_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }
  }

  async processOneVideo(row) {
    const id = row && row.id ? Number(row.id) : 0;
    if (!id) return false;

    const fullPath = path.join(String(row.path || ''), String(row.filename || ''));

    // 来源目录不存在则跳过
    await this._ensureSourceDirsFresh();
    if (!this._isUnderSourceDir(fullPath)) {
      await this.videoKnex('video_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }

    if (!fullPath || !(await pathAccessible(fullPath, TINY_PATH_CHECK_MS))) return false;

    try {
      const tinyPath = await generateTinyWithTimeout(fullPath);
      if (!tinyPath) return false;
      await this.videoKnex('video_index').where({ id }).update({ gen_tiny: 1 });
      return true;
    } catch (err) {
      const msg = err && err.message ? String(err.message) : '';
      if (msg === 'file.TINY_TIMEOUT') {
        Logger.warn(`⏱ video thumbnail gen timed out: ${fullPath}`);
      } else {
        Logger.error(`❌ video thumb gen failed: ${fullPath}`, err);
      }
      await this.videoKnex('video_index').where({ id }).update({ gen_tiny: 1 });
      return false;
    }
  }

  async processOneWait(row) {
    const id = row && row.id ? Number(row.id) : 0;
    if (!id) return false;

    const sourcePath = row && row.source_path ? String(row.source_path || '') : '';
    const fullPath = sourcePath ? path.resolve(sourcePath) : '';

    // 来源目录不存在则跳过并删除记录
    await this._ensureSourceDirsFresh();
    if (!this._isUnderSourceDir(fullPath)) {
      await this.photoKnex('wait_gen_tiny').where({ id }).del();
      return false;
    }

    if (!fullPath || !(await pathAccessible(fullPath, TINY_PATH_CHECK_MS))) {
      await this.photoKnex('wait_gen_tiny').where({ id }).del();
      return false;
    }

    try {
      const tinyPath = await generateTinyWithTimeout(fullPath);
      await this.photoKnex('wait_gen_tiny').where({ id }).del();
      return !!tinyPath;
    } catch (err) {
      const msg = err && err.message ? String(err.message) : '';
      if (msg === 'file.TINY_TIMEOUT') {
        Logger.warn(`⏱ pending thumbnail gen timed out: ${fullPath}`);
      } else {
        Logger.error(`❌ pending thumbnail gen failed: ${fullPath}`, err);
      }
      await this.photoKnex('wait_gen_tiny').where({ id }).del();
      return false;
    }
  }

  stop() {
    this.isRunning = false;
  }
}

const worker = new TinyImageWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'stop') worker.stop();
});

process.on('uncaughtException', err => {
  Logger.error('❌ tinyImage worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ tinyImage worker unhandledRejection', reason);
  process.exit(0);
});
