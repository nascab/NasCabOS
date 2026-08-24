'use strict';

const fs = require('fs');
const path = require('path');
const Logger = require('../../utils/logger');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const config = require('../../config/config');
const sharpUtils = require('../../utils/sharpUtils');
const { isMusicFileExt, shouldSkipFilename, getBestMatchedItemByPath } = require('./musicIndexShared');
const MusicTagReader = require('./musicTagReader');
const { buildMusicIndexRow } = require('./musicIndexRowBuilder');
const { ensureInnerCoverTiny } = require('./musicCoverUtil');
const { getFirstLetter } = require('../../utils/firstLetterUtil');

class MusicIndexWorker {
  constructor() {
    this.tagReader = new MusicTagReader();
    this.init();
  }

  async upsertSeriesIndexesForDirChain({ knex, dirPath, boundaryRoot }) {
    const leaf = dirPath ? path.resolve(String(dirPath)) : '';
    if (!leaf) return;
    const boundary = boundaryRoot ? path.resolve(String(boundaryRoot)) : '';
    const boundaryPrefix = boundary ? (boundary.endsWith(path.sep) ? boundary : `${boundary}${path.sep}`) : '';

    if (boundary) {
      const inside = leaf === boundary || (boundaryPrefix && leaf.startsWith(boundaryPrefix));
      if (!inside) return;
    }
    await this.upsertFolderIndex(knex, leaf);
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.MUSIC_DB);

      await this.runUntilEmpty();
      process.exit(0);
    } catch (err) {
      Logger.error('❌ music index worker init failed:', err);
      process.exit(1);
    }
  }

  async getNextTask() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const tasks = await knex('music_scan_task').orderBy('create_time', 'asc').limit(1);
    if (!tasks || tasks.length === 0) return null;
    return tasks[0];
  }

  async deleteTask(task) {
    if (!task || !task.id) return;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    await knex('music_scan_task')
      .where({ id: task.id })
      .delete()
      .catch(() => {});
  }

  async getMatchedSourceByScanPath(scanPath) {
    const resolved = scanPath ? path.resolve(String(scanPath)) : '';
    if (!resolved) return null;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const sources = await knex('music_source')
      .select('id', 'path', 'show_type')
      .orderBy('id', 'asc')
      .catch(() => []);
    return getBestMatchedItemByPath(sources, resolved);
  }

  async deleteIndexesByPathPrefix({ knex, targetPath }) {
    const targetDir = targetPath ? path.resolve(String(targetPath)) : '';
    if (!targetDir) return 0;
    const prefix = targetDir.endsWith(path.sep) ? targetDir : `${targetDir}${path.sep}`;
    const affected = await knex('music_index')
      .where(qb => {
        qb.where('path', targetDir).orWhere('path', 'like', `${prefix}%`);
      })
      .delete()
      .catch(() => 0);
    return Number(affected || 0) || 0;
  }

  async deleteMissingIndexes({ knex, scanPath }) {
    const root = scanPath ? path.resolve(String(scanPath)) : '';
    if (!root) return;

    const deleteSubtreeByPathPrefix = async targetDir => {
      if (!targetDir) return;
      const prefix = targetDir.endsWith(path.sep) ? targetDir : `${targetDir}${path.sep}`;
      await knex('music_index')
        .where(qb => {
          qb.where('path', targetDir).orWhere('path', 'like', `${prefix}%`);
        })
        .delete()
        .catch(() => {});
    };

    try {
      fs.statSync(root);
    } catch (_) {
      await deleteSubtreeByPathPrefix(root);
      return;
    }

    let fileDeleteIds = [];

    const flushFileDeletes = async () => {
      if (fileDeleteIds.length === 0) return;
      const ids = fileDeleteIds;
      fileDeleteIds = [];
      await knex('music_index')
        .whereIn('id', ids)
        .delete()
        .catch(() => {});
    };

    const rootPrefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
    let lastId = 0;
    while (true) {
      const pageSize = 5000;
      const rows = await knex('music_index')
        .select('id', 'path', 'filename', 'show_type')
        .andWhere(qb => {
          qb.where('path', root).orWhere('path', 'like', `${rootPrefix}%`);
        })
        .andWhere('id', '>', lastId)
        .orderBy('id', 'asc')
        .limit(pageSize)
        .catch(() => []);

      if (!rows || rows.length === 0) break;

      for (const r of rows) {
        const id = r && r.id ? Number(r.id) : 0;
        if (id > lastId) lastId = id;

        const parent = r && r.path ? String(r.path) : '';
        const name = r && r.filename ? String(r.filename) : '';
        const showType = r && r.show_type ? String(r.show_type) : '';
        if (!parent || !name) {
          if (id) fileDeleteIds.push(id);
          if (fileDeleteIds.length >= 1000) await flushFileDeletes();
          continue;
        }
        const targetPath = path.join(parent, name);
        try {
          fs.statSync(targetPath);
        } catch (err) {
          if (err && err.code && err.code !== 'ENOENT') continue;
          const isFolderIndex = String(showType || '').toLowerCase() === 'series';
          if (isFolderIndex) {
            if (id) {
              await knex('music_index')
                .where({ id })
                .delete()
                .catch(() => {});
            }
            await deleteSubtreeByPathPrefix(targetPath);
          } else {
            if (id) fileDeleteIds.push(id);
            if (fileDeleteIds.length >= 1000) await flushFileDeletes();
          }
        }
      }

      if (rows.length < pageSize) break;
      if (fileDeleteIds.length >= 1000) await flushFileDeletes();
    }

    await flushFileDeletes();
  }

  async upsertIndex(knex, row) {
    if (!row || !row.path || !row.filename) return 0;
    await knex('music_index').insert(row).onConflict(['path', 'filename']).merge(row);
    const existed = await knex('music_index')
      .where({ path: row.path, filename: row.filename })
      .first('id')
      .catch(() => null);
    return existed && existed.id ? Number(existed.id || 0) || 0 : 0;
  }

  splitIndexKeyText(text) {
    const raw = text === undefined || text === null ? '' : String(text);
    const parts = raw.split(/[,，、|\/；;]+/).map(s => String(s || '').trim());
    const res = [];
    const seen = new Set();
    for (const p of parts) {
      if (!p) continue;
      if (seen.has(p)) continue;
      seen.add(p);
      res.push(p);
    }
    return res;
  }

  isMeaninglessGenreText(text) {
    const raw = text === undefined || text === null ? '' : String(text);
    const condensed = raw.replace(/[,，、|\/；;]+/g, ' ').trim();
    if (!condensed) return false;
    if (!condensed.includes('_')) return false;
    return /^[\d_\s-]+$/.test(condensed);
  }

  async syncMusicIndex2KeyFromRow({ knex, indexId, row }) {
    const id = Number(indexId || 0) || 0;
    if (!id) return false;
    const base = row || {};

    const rows = [];
    for (const key of this.splitIndexKeyText(base.artist)) {
      rows.push({ index_id: id, key, key_fl: getFirstLetter(key), key_type: 'artist' });
    }
    for (const key of this.splitIndexKeyText(base.album)) {
      rows.push({ index_id: id, key, key_fl: getFirstLetter(key), key_type: 'album' });
    }
    if (!this.isMeaninglessGenreText(base.genre)) {
      for (const key of this.splitIndexKeyText(base.genre)) {
        rows.push({ index_id: id, key, key_fl: getFirstLetter(key), key_type: 'genre' });
      }
    }

    await knex('music_index2key')
      .where({ index_id: id })
      .delete()
      .catch(() => {});

    if (rows.length === 0) return true;

    await knex('music_index2key')
      .insert(rows)
      .onConflict(['index_id', 'key', 'key_type'])
      .ignore()
      .catch(() => {});

    return true;
  }

  async deleteIndexByFullPath({ knex, fullPath }) {
    const p = fullPath ? path.resolve(String(fullPath)) : '';
    if (!p) return 0;
    const dir = path.dirname(p);
    const name = path.basename(p);
    if (!dir || !name) return 0;
    const affected = await knex('music_index')
      .where({ path: dir, filename: name })
      .delete()
      .catch(() => 0);
    return Number(affected || 0) || 0;
  }

  async upsertFolderIndex(knex, dirPath) {
    const fullDir = dirPath ? path.resolve(String(dirPath)) : '';
    if (!fullDir) return 0;
    const parentDir = path.dirname(fullDir);
    const folderName = path.basename(fullDir);
    if (!parentDir || !folderName) return 0;

    let st = null;
    try {
      st = await fs.promises.stat(fullDir);
    } catch (_) {}

    const countRow = await knex('music_index')
      .count({ cnt: 'id' })
      .where({ show_type: 'submusic' })
      .andWhere({ path: fullDir })
      .first()
      .catch(() => null);
    const musicCount = Math.max(0, Number((countRow && (countRow.cnt ?? countRow['count(`id`)'] ?? countRow['count(*)'])) || 0) || 0);

    if (!musicCount) {
      await knex('music_index')
        .where({ path: parentDir, filename: folderName })
        .andWhere({ show_type: 'series' })
        .delete()
        .catch(() => {});
      return 0;
    }

    const row = {
      path: parentDir,
      filename: folderName,
      ext: '',
      size: 0,
      duration: 0,
      file_hash: '',
      ctime: st ? new Date(st.ctimeMs) : null,
      mtime: st ? new Date(st.mtimeMs) : null,
      birthtime: st ? new Date(st.birthtimeMs) : null,
      title: folderName,
      title_fl: getFirstLetter(folderName),
      artist: '',
      artist_fl: '',
      album: '',
      album_fl: '',
      year: '',
      genre: '',
      lyrics: '',
      stream_info: '',
      lyrics_get_state: 0,
      has_inner_cover: 0,
      show_type: 'series',
      music_count: musicCount,
    };

    return await this.upsertIndex(knex, row);
  }

  async scanFileToIndex({ knex, fullPath, showType }) {
    const p = fullPath ? path.resolve(String(fullPath)) : '';
    if (!p) return 0;
    const ext = path.extname(p).toLowerCase();
    if (!isMusicFileExt(ext)) return 0;

    let st = null;
    try {
      st = await fs.promises.stat(p);
    } catch (_) {}
    if (!st || !st.isFile()) return 0;

    const [tags, probe] = await Promise.all([this.tagReader.readAudioTags(p), this.tagReader.probeAudio(p)]);
    const row = buildMusicIndexRow({ fullPath: p, stat: st, tags, probe, tagReader: this.tagReader });
    if (!row) return 0;

    const coverBuffer = this.tagReader.extractInnerCoverBuffer(tags);
    const hasCover = coverBuffer && row.file_hash ? await ensureInnerCoverTiny({ fileHash: row.file_hash, coverBuffer, size: 500 }) : false;
    row.has_inner_cover = hasCover ? 1 : 0;
    const stRaw = showType ? String(showType).trim().toLowerCase() : '';
    row.show_type = stRaw || 'music';

    const indexId = await this.upsertIndex(knex, row);
    if (indexId) {
      await this.syncMusicIndex2KeyFromRow({ knex, indexId, row });
    }
    return indexId ? 1 : 0;
  }

  async scanDirectoryToIndex({ knex, rootDir, sourceRoot, showType }) {
    const root = rootDir ? path.resolve(String(rootDir)) : '';
    if (!root) return 0;

    let indexed = 0;
    const isSeriesMode = String(showType || '').toLowerCase() === 'series';

    const stack = [root];
    while (stack.length > 0) {
      const rawDir = stack.pop();
      const dir = rawDir ? path.resolve(String(rawDir)) : '';
      if (!dir) continue;

      let entries = [];
      try {
        entries = await fs.promises.readdir(dir, { withFileTypes: true });
      } catch (_) {
        continue;
      }

      let hasDirectMusic = false;
      const subDirs = [];

      for (let i = entries.length - 1; i >= 0; i -= 1) {
        const ent = entries[i];
        const name = ent && ent.name ? String(ent.name) : '';
        if (!name) continue;
        if (shouldSkipFilename(name)) continue;

        const fullPath = path.join(dir, name);
        if (ent.isDirectory()) {
          subDirs.push(fullPath);
          continue;
        }
        if (!ent.isFile()) continue;

        const ext = path.extname(name).toLowerCase();
        if (!isMusicFileExt(ext)) continue;

        if (isSeriesMode) hasDirectMusic = true;
        const ok = await this.scanFileToIndex({ knex, fullPath, showType: isSeriesMode ? 'submusic' : 'music' });
        if (ok) indexed += 1;
      }

      if (isSeriesMode) {
        if (hasDirectMusic) {
          await this.upsertFolderIndex(knex, dir);
        } else {
          const parentDir = path.dirname(dir);
          const folderName = path.basename(dir);
          if (parentDir && folderName) {
            await knex('music_index')
              .where({ path: parentDir, filename: folderName })
              .andWhere({ show_type: 'series' })
              .delete()
              .catch(() => {});
          }
        }
      }

      for (let i = subDirs.length - 1; i >= 0; i -= 1) {
        const d = subDirs[i];
        if (d) stack.push(d);
      }
    }

    return indexed;
  }

  async isSourceStillExists(sourceId) {
    const id = Number(sourceId || 0) || 0;
    if (!id) return false;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const row = await knex('music_source').where({ id }).first('id');
    return !!(row && row.id);
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
      const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
      await Promise.all([this.deleteIndexByFullPath({ knex, fullPath: scanPath }), this.deleteIndexesByPathPrefix({ knex, targetPath: scanPath })]);

      const matchedSource = await this.getMatchedSourceByScanPath(scanPath).catch(() => null);
      const showTypeRaw = matchedSource && matchedSource.show_type ? String(matchedSource.show_type).trim().toLowerCase() : '';
      if (showTypeRaw === 'series') {
        const resolved = scanPath ? path.resolve(String(scanPath)) : '';
        const parentDir = resolved ? path.dirname(resolved) : '';
        const baseName = resolved ? path.basename(resolved) : '';
        if (parentDir && baseName) {
          await knex('music_index')
            .where({ path: parentDir, filename: baseName })
            .andWhere({ show_type: 'series' })
            .delete()
            .catch(() => {});
          await this.upsertFolderIndex(knex, parentDir).catch(() => 0);
        }
      }

      Logger.info('Scan path no longer exists', scanPath);
      await this.deleteTask(task);
      return;
    }
    const isDir = stat.isDirectory();
    const isFile = stat.isFile();
    if (!isDir && !isFile) {
      Logger.info('Scan path is neither file nor directory', scanPath);
      await this.deleteTask(task);
      return;
    }

    const start = Date.now();
    Logger.info('Music library: start scan', scanPath);

    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
    const source = await this.getMatchedSourceByScanPath(scanPath);
    if (!source) {
      Logger.info('Music library: source missing, cancel scan', scanPath);
      await this.deleteTask(task);
      return;
    }

    const sourceId = Number(source.id || 0) || 0;
    const showTypeRaw = source && source.show_type ? String(source.show_type).trim().toLowerCase() : 'music';
    const sourceRoot = source && source.path ? String(source.path) : '';
    const sourceStillExistsAtStart = await this.isSourceStillExists(sourceId);
    if (!sourceStillExistsAtStart) {
      Logger.info('Music library: source removed, cancel scan', scanPath);
      await this.deleteTask(task);
      return;
    }

    await knex('music_source')
      .where({ id: sourceId })
      .update({ last_scan_time: Date.now() })
      .catch(() => {});

    let indexedCount = 0;
    try {
      if (isFile) {
        const ext = path.extname(scanPath).toLowerCase();
        if (!isMusicFileExt(ext)) {
          await this.deleteIndexByFullPath({ knex, fullPath: scanPath });
          indexedCount = 0;
        } else {
          const isSeriesMode = showTypeRaw === 'series';
          indexedCount = await this.scanFileToIndex({ knex, fullPath: scanPath, showType: isSeriesMode ? 'submusic' : 'music' });
          if (isSeriesMode) {
            const dirPath = path.dirname(path.resolve(scanPath));
            if (dirPath) await this.upsertSeriesIndexesForDirChain({ knex, dirPath, boundaryRoot: sourceRoot || dirPath });
          }
        }
      } else {
        await this.deleteMissingIndexes({ knex, scanPath });
        indexedCount = await this.scanDirectoryToIndex({ knex, rootDir: scanPath, sourceRoot, showType: showTypeRaw });
      }
    } catch (err) {
      Logger.error('❌ music scan error:', err);
    }

    await this.deleteTask(task);
    const cost = Date.now() - start;
    Logger.info(`Music library: scan done indexed=${indexedCount} costMs=${cost} path=${scanPath}`);
  }

  async runUntilEmpty() {
    while (true) {
      const task = await this.getNextTask();
      if (!task) {
        Logger.info('✅ No pending music scan tasks, worker exiting');
        if (process.send) {
          try {
            process.send({ type: 'musicIndexingFinished' });
          } catch (_) {}
        }
        return;
      }
      try {
        await this.runTask(task);
      } catch (err) {
        Logger.error('❌ Music index task failed:', err && err.message ? err.message : err);
        await this.deleteTask(task);
      }
    }
  }
}

if (require.main === module) {
  new MusicIndexWorker();

  process.on('message', message => {
    if (message && message.type === 'stop') {
      process.exit(0);
    }
  });

  process.on('uncaughtException', err => {
    Logger.error('❌ musicIndex worker uncaughtException', err);
    process.exit(0);
  });

  process.on('unhandledRejection', reason => {
    Logger.error('❌ musicIndex worker unhandledRejection', reason);
    process.exit(0);
  });
} else {
  module.exports = MusicIndexWorker;
}
