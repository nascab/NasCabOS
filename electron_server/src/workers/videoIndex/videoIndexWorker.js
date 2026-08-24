'use strict';

const fs = require('fs');
const path = require('path');
const Logger = require('../../utils/logger');
const FileUtil = require('../../utils/fileUtil');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const { walkVideoEntries } = require('./videoIndexUtil');
const videoIndexIndexUtil = require('./videoIndexIndexUtil');

class VideoIndexWorker {
  constructor() {
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.VIDEO_DB);

      await this.runUntilEmpty();
      process.exit(0);
    } catch (err) {
      Logger.error('❌ video index worker init failed:', err);
      process.exit(1);
    }
  }

  async runUntilEmpty() {
    while (true) {
      const task = await this.getNextTask();
      if (!task) {
        Logger.info('✅ No pending video scan tasks, worker exiting');
        return;
      }
      try {
        await this.runTask(task);
      } catch (err) {
        Logger.error('❌ Video scan task failed:', err);
        await this.deleteTask(task);
      }
    }
  }

  async getNextTask() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const tasks = await knex('video_scan_task').orderBy('create_time', 'asc').limit(1);
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
    Logger.info('Video library: start scan', scanPath);

    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const source = await this.getMatchedSourceByScanPath(scanPath);
    if (!source) {
      Logger.info('Video library: source missing, cancel scan', scanPath);
      await this.deleteTask(task);
      return;
    }

    const sourceId = Number(source.id || 0) || 0;
    const sourceMediaType = source.media_type ? String(source.media_type) : 'movie';
    const isTvSource = sourceMediaType === 'tv';

    await knex('video_source')
      .where({ id: sourceId })
      .update({ last_scan_time: Date.now() })
      .catch(() => {});

    await videoIndexIndexUtil.deleteMissingIndexes({ knex, scanPath });

    const showStats = new Map();
    const seasonStats = new Map();
    const showSeasons = new Map();
    const dirtyShowKeys = new Set();
    const dirtySeasonKeys = new Set();

    let indexedCount = 0;
    let aborted = false;
    let processedVideoCount = 0;

    const flushTvFolderIndexes = async () => {
      if (!isTvSource) return;

      for (const showKey of Array.from(dirtyShowKeys)) {
        const s = showStats.get(showKey);
        if (!s) continue;
        const seasons = showSeasons.get(showKey);
        const seasonCount = seasons ? seasons.size : 0;
        await videoIndexIndexUtil.indexTvShowFolder({
          knex,
          showFolder: s.showFolder,
          seasonCount,
          episodCount: s.episodeCount,
        });
      }
      for (const seasonKey of Array.from(dirtySeasonKeys)) {
        const s = seasonStats.get(seasonKey);
        if (!s) continue;
        await videoIndexIndexUtil.indexSeasonFolder({
          knex,
          seasonFolder: s.seasonFolder,
          episodCount: s.episodeCount,
        });
      }

      dirtyShowKeys.clear();
      dirtySeasonKeys.clear();
    };

    const completed = await walkVideoEntries(scanPath, {
      onDirectory: async () => {
        const stillExists = await this.isSourceStillExists(sourceId);
        if (!stillExists) {
          aborted = true;
          return false;
        }
        return true;
      },
      onDiscFolder: async entry => {
        const stillExists = await this.isSourceStillExists(sourceId);
        if (!stillExists) {
          aborted = true;
          return false;
        }
        if (isTvSource) return true;
        const mediaType = entry && entry.mediaType ? String(entry.mediaType) : '';
        const ok = mediaType === 'video_ts'
          ? await videoIndexIndexUtil.indexVideoTsFolder({ knex, ...entry })
          : await videoIndexIndexUtil.indexBdmvFolder({ knex, ...entry });
        if (ok) {
          indexedCount += 1;
          processedVideoCount += 1;
        }
        return true;
      },
      onVideoFile: async entry => {
        const stillExists = await this.isSourceStillExists(sourceId);
        if (!stillExists) {
          aborted = true;
          return false;
        }
        if (FileUtil.shouldSkipIndexingFilename(entry && entry.filename ? String(entry.filename) : '')) {
          return true;
        }

        // 根据 Jellyfin 约定：Sample 文件夹下的样片跳过索引
        const parentFolderName = path.basename(path.dirname(String(entry.fullPath || '')));
        if (String(parentFolderName || '').toLowerCase() === 'sample') {
          return true;
        }

        processedVideoCount += 1;

        if (isTvSource) {
          const { showFolder, seasonFolder } = videoIndexIndexUtil.getTvFoldersFromEpisode({ fullPath: entry.fullPath });

          const showKey = videoIndexIndexUtil.buildShowKey(showFolder);
          const prevShow = showStats.get(showKey) || { showFolder, episodeCount: 0 };
          prevShow.episodeCount += 1;
          showStats.set(showKey, prevShow);
          dirtyShowKeys.add(showKey);

          if (!showSeasons.has(showKey)) showSeasons.set(showKey, new Set());
          if (seasonFolder) {
            showSeasons.get(showKey).add(path.resolve(seasonFolder));
            const seasonKey = videoIndexIndexUtil.buildSeasonKey(seasonFolder);
            const prevSeason = seasonStats.get(seasonKey) || { seasonFolder, episodeCount: 0 };
            prevSeason.episodeCount += 1;
            seasonStats.set(seasonKey, prevSeason);
            dirtySeasonKeys.add(seasonKey);
          }

          const ok = await videoIndexIndexUtil.indexEpisodeFile({ knex, ...entry });
          if (ok) indexedCount += 1;
        } else {
          const ok = await videoIndexIndexUtil.indexMovieFile({ knex, ...entry });
          if (ok) indexedCount += 1;
        }

        // 扫描过程中分批生成“剧/季”索引，避免全部文件结束后才生成
        if (isTvSource && processedVideoCount % 50 === 0) {
          await flushTvFolderIndexes();
        }
        return true;
      },
    });
    if (completed === false) aborted = true;

    await flushTvFolderIndexes();

    Logger.info('Video library: scan done ' + scanPath, 'elapsedMs:', Date.now() - start, 'files:', indexedCount);

    if (process.send) {
      try {
        process.send({ type: 'videoIndexingFinished', data: { scanPath, indexedCount, aborted } });
      } catch (_) {}
    }

    await this.deleteTask(task);
  }

  async deleteTask(task) {
    if (!task || !task.id) return;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    await knex('video_scan_task')
      .where({ id: task.id })
      .delete()
      .catch(() => {});
  }

  async isSourceStillExists(sourceId) {
    const id = Number(sourceId || 0) || 0;
    if (!id) return false;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const row = await knex('video_source').where({ id }).first('id');
    return !!(row && row.id);
  }

  async getMatchedSourceByScanPath(scanPath) {
    const resolvedScan = scanPath ? path.resolve(String(scanPath)) : '';
    if (!resolvedScan) return null;

    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    const rows = await knex('video_source')
      .select('id', 'path', 'media_type')
      .catch(() => []);

    let best = null;
    for (const r of rows || []) {
      const root = r && r.path ? path.resolve(String(r.path)) : '';
      if (!root) continue;
      const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
      if (resolvedScan !== root && !resolvedScan.startsWith(prefix)) continue;
      if (!best || root.length > path.resolve(String(best.path || '')).length) best = r;
    }
    return best;
  }
}

new VideoIndexWorker();

process.on('message', message => {
  if (message && message.type === 'stop') {
    process.exit(0);
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ videoIndex worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ videoIndex worker unhandledRejection', reason);
  process.exit(0);
});
