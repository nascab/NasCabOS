'use strict';

const fs = require('fs');
const path = require('path');
const Watchpack = require('watchpack');

const Logger = require('../../utils/logger');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const fileUtil = require('../../utils/fileUtil');
const { isMusicFileExt, shouldSkipFilename, resolvePath } = require('./musicIndexShared');

class MusicWatchWorker {
  constructor() {
    this.knex = null;
    this.watchpack = null;
    this.watchedRoots = [];
    this.pendingChangedPaths = new Set();
    this.pendingRemovedPaths = new Set();
    this.flushTimer = null;
    this.startIndexDebounceTimer = null;
    this.startIndexDebounceMs = 1500;
    this.maxFineGrainedTasks = 200;
    this.processing = false;
    this.reflushRequested = false;
    this.init();
  }

  sendMessage(type, data = undefined) {
    if (typeof process.send !== 'function') return;
    try {
      process.send({ type, data });
    } catch (_) {}
  }

  scheduleStartMusicIndexWorker() {
    if (this.startIndexDebounceTimer) {
      clearTimeout(this.startIndexDebounceTimer);
    }
    this.startIndexDebounceTimer = setTimeout(
      () => {
        this.startIndexDebounceTimer = null;
        this.sendMessage('startMusicIndexWorker');
      },
      Math.max(200, Number(this.startIndexDebounceMs || 0) || 0)
    );
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.MUSIC_DB);
      this.knex = knexUtil.getInstance(dbUtil.DB_PATHS.MUSIC_DB);
      await this.resetWatchers();

    } catch (err) {
      Logger.error('❌ musicWatchWorker init failed:', err);
      process.exit(1);
    }
  }

  async getWatchedSourcePaths() {
    const rows = await this.knex('music_source')
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

  buildWatchedRoots(paths) {
    const roots = [];
    for (const p of paths) {
      const rp = resolvePath(p);
      const prefix = rp.endsWith(path.sep) ? rp : `${rp}${path.sep}`;
      roots.push({ root: rp, prefix });
    }
    roots.sort((a, b) => a.prefix.length - b.prefix.length);
    return roots;
  }

  isWithinWatchedRoot(targetPath) {
    if (!targetPath) return false;
    const rp = resolvePath(targetPath);
    for (const r of this.watchedRoots) {
      if (rp === r.root) return true;
      if (rp.startsWith(r.prefix)) return true;
    }
    return false;
  }

  getMatchedWatchedRoot(targetPath) {
    const rp = resolvePath(targetPath);
    if (!rp) return '';
    let best = '';
    for (const r of this.watchedRoots) {
      if (rp === r.root || rp.startsWith(r.prefix)) {
        if (!best || r.root.length > best.length) best = r.root;
      }
    }
    return best;
  }

  checkMatchedRootExists(targetPath) {
    const root = this.getMatchedWatchedRoot(targetPath);
    if (!root) return false;
    try {
      return fs.existsSync(root);
    } catch (_) {
      return false;
    }
  }

  closeWatchpack() {
    if (!this.watchpack) return;
    try {
      this.watchpack.close();
    } catch (_) {}
    this.watchpack = null;
  }

  async resetWatchers() {
    this.closeWatchpack();
    this.pendingChangedPaths.clear();
    this.pendingRemovedPaths.clear();

    const sourcePaths = await this.getWatchedSourcePaths();
    this.watchedRoots = this.buildWatchedRoots(sourcePaths);

    if (!sourcePaths || sourcePaths.length === 0) {
      Logger.info('ℹ️ scan_when_change=1 but no sources, musicWatchWorker exiting');
      return process.exit(0);
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

  scheduleFromPath(p, isRemove) {
    if (!p) return;
    const resolved = resolvePath(p);
    if (!this.isWithinWatchedRoot(resolved)) return;

    const filename = path.basename(resolved);
    if (shouldSkipFilename(filename)) return;

    if (isRemove) {
      this.pendingRemovedPaths.add(resolved);
    } else {
      this.pendingChangedPaths.add(resolved);
    }

    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      this.flushPending().catch(err => Logger.error('❌ musicWatchWorker flushPending error:', err));
    }, 800);
  }

  async enqueueScanTasks(scanPaths, remark) {
    const unique = Array.from(new Set((scanPaths || []).map(p => (p ? String(p) : '')).filter(Boolean)));
    if (unique.length === 0) return 0;

    const inserted = await this.knex.transaction(async trx => {
      const existingRows = await trx('music_scan_task')
        .select('scan_path')
        .whereIn('scan_path', unique)
        .catch(() => []);

      const existing = new Set();
      for (const r of existingRows || []) {
        const s = r && r.scan_path ? String(r.scan_path) : '';
        if (s) existing.add(s);
      }

      const toInsert = [];
      for (const p of unique) {
        if (!existing.has(p)) {
          toInsert.push({
            scan_path: p,
            remark,
            create_time: new Date(),
          });
        }
      }

      if (toInsert.length === 0) return 0;
      await trx('music_scan_task').insert(toInsert);
      return toInsert.length;
    });

    return Number(inserted || 0) || 0;
  }

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
      const scanPathSet = new Set();

      const considerPath = p => {
        if (!p) return;
        scanPathSet.add(p);
      };

      const total = removedPaths.length + changedPaths.length;
      const coarseMode = total > Math.max(1, Number(this.maxFineGrainedTasks || 0) || 0);

      if (coarseMode) {
        const considerCoarse = p => {
          if (!p) return;
          const root = this.getMatchedWatchedRoot(p);
          if (!root) return;
          if (!this.checkMatchedRootExists(root)) return;
          scanPathSet.add(root);
        };
        for (const p of removedPaths) {
          if (!this.isWithinWatchedRoot(p)) continue;
          considerCoarse(p);
        }
        for (const p of changedPaths) {
          if (!this.isWithinWatchedRoot(p)) continue;
          considerCoarse(p);
        }
      } else {
        for (const p of removedPaths) {
          if (!this.isWithinWatchedRoot(p)) continue;
          if (!this.checkMatchedRootExists(p)) continue;
          considerPath(p);
        }

        for (const p of changedPaths) {
          if (!this.isWithinWatchedRoot(p)) continue;
          if (!this.checkMatchedRootExists(p)) continue;
          let st = null;
          try {
            st = fs.statSync(p);
          } catch (_) {
            considerPath(p);
            continue;
          }
          if (st && st.isFile()) {
            const ext = path.extname(p).toLowerCase();
            if (!isMusicFileExt(ext)) continue;
            considerPath(p);
            continue;
          }
          if (st && st.isDirectory()) {
            considerPath(p);
          }
        }
      }

      const scanPaths = Array.from(scanPathSet);
      if (scanPaths.length > 0) {
        await this.enqueueScanTasks(scanPaths, 'watch_change').catch(() => 0);
        this.scheduleStartMusicIndexWorker();
      }
    } finally {
      this.processing = false;
    }

    if (this.reflushRequested) {
      this.reflushRequested = false;
      await this.flushPending();
    }
  }
}

const worker = new MusicWatchWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'reset') {
    worker.resetWatchers().catch(err => Logger.error('❌ musicWatchWorker reset failed:', err));
  }
  if (message.type === 'stop') {
    process.exit(0);
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ musicWatchWorker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ musicWatchWorker unhandledRejection', reason);
  process.exit(0);
});
