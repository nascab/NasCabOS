'use strict';

const fs = require('fs');
const path = require('path');

const Logger = require('../../utils/logger');
const dbUtil = require('../../db/dbUtil');
const tableConfig = require('../../db/table/tableConfig');

const FileAllIndexFtsStore = require('./fileAllIndexFtsStore');
const { getAllDiskRoots } = require('./fileAllIndexRoots');
const { shouldIgnorePath } = require('./fileAllIndexFilter');
const { walkAndCollectFiles } = require('./fileAllIndexIndexer');

const CONFIG_KEY_LAST_FULL_SCAN_MS = 'fileAllIndexLastFullScanMs';
const CONFIG_KEY_SCAN_ID = 'fileAllIndexScanId';
const CONFIG_KEY_INTERVAL_HOURS = 'file_all_index_interval_hours';
const DEFAULT_INTERVAL_HOURS = 72;
const FULL_SCAN_INSERT_BATCH_SIZE = 1000;

function _nowMs() {
  return Date.now();
}

function _nextScanId(v) {
  const n = Math.trunc(Number(v));
  const cur = Number.isFinite(n) && n > 0 ? n : 0;
  const next = cur + 1;
  return next >= 2147483647 ? 1 : next;
}

function _safeIntervalHours(v) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return DEFAULT_INTERVAL_HOURS;
  if (n <= 0) return DEFAULT_INTERVAL_HOURS;
  return n;
}

function _hoursToMs(h) {
  return Math.max(1, Number(h) || 0) * 60 * 60 * 1000;
}

function _safeResolve(p) {
  if (!p) return '';
  try {
    return path.resolve(String(p));
  } catch (_) {
    return String(p);
  }
}

function _toFsPath(p) {
  const s = String(p || '');
  if (process.platform !== 'win32') return s;
  if (s.startsWith('\\\\?\\')) return s;
  if (s.startsWith('\\\\')) return s;
  if (s.length < 250) return s;
  return `\\\\?\\${s}`;
}

class FileAllIndexWorker {
  constructor() {
    this.knexReady = false;
    this.store = null;

    this.stopped = false;
    this.fullIndexing = false;
    this.fullScanTimer = null;
    this.fullScanIntervalMs = _hoursToMs(DEFAULT_INTERVAL_HOURS);

    this.init();
  }

  async loadIntervalConfig() {
    const raw = await tableConfig.getConfigByKey(CONFIG_KEY_INTERVAL_HOURS).catch(() => null);
    const hours = _safeIntervalHours(raw);
    this.fullScanIntervalMs = _hoursToMs(hours);
    return this.fullScanIntervalMs;
  }

  async init() {
    try {
      await dbUtil.init(false);
      this.knexReady = true;
      this.store = new FileAllIndexFtsStore();
      const tableFileIndex = require('../../db/table/tableFileIndex');
      await tableFileIndex.createTable(dbUtil.getConnectFileDb()).catch(() => {});
      await tableFileIndex.createIndexes(dbUtil.getConnectFileDb()).catch(() => {});
    } catch (err) {
      Logger.error('❌ fileAllIndexWorker DB init failed:', err);
      this.knexReady = false;
      process.exit(1);
    }

    await this.loadIntervalConfig().catch(() => {});
    await this.runFullIndexIfDue({ reason: 'startup' }).catch(err => Logger.error('❌ fileAllIndexWorker startup full index failed:', err));
    await this.scheduleNextFullIndex().catch(() => {});
  }

  clearTimers() {
    if (this.fullScanTimer) clearTimeout(this.fullScanTimer);
    this.fullScanTimer = null;
  }

  async runFullIndexIfDue({ reason } = {}) {
    if (!this.knexReady || !this.store) return;
    if (this.fullIndexing) return;

    const raw = await tableConfig.getConfigByKey(CONFIG_KEY_LAST_FULL_SCAN_MS).catch(() => null);
    const last = raw ? Number(raw) || 0 : 0;
    const now = _nowMs();
    const intervalMs = this.fullScanIntervalMs || _hoursToMs(DEFAULT_INTERVAL_HOURS);

    if (last > 0 && now - last < intervalMs) {
      const remaining = intervalMs - (now - last);

      return;
    }

    await this.runFullIndex({ reason: String(reason || '') });
  }

  async runFullIndex({ reason } = {}) {
    if (!this.store) return;
    if (this.fullIndexing) return;

    this.fullIndexing = true;
    const start = _nowMs();

    try {
      const scanIdRaw = await tableConfig.getConfigByKey(CONFIG_KEY_SCAN_ID).catch(() => '0');
      const scanId = _nextScanId(scanIdRaw);
      await tableConfig.setConfigByKey(CONFIG_KEY_SCAN_ID, String(scanId)).catch(() => {});

      const roots = await getAllDiskRoots();
      const scanRoots = [];
      for (const r of roots || []) {
        const resolved = _safeResolve(r);
        if (!resolved) continue;
        if (shouldIgnorePath(resolved)) continue;
        scanRoots.push(resolved);
      }

      if (scanRoots.length === 0) {
        Logger.warn('⚠️ fileAllIndexWorker: no scan roots', { reason: String(reason || '') });
        return;
      }

      Logger.info('📚 fileAllIndexWorker full index start', { reason: String(reason || ''), roots: scanRoots.length });

      let batch = [];
      let total = 0;
      let inserted = 0;
      let updatedScanId = 0;
      for (const root of scanRoots) {
        await walkAndCollectFiles(root, async entry => {
          if (!entry) return true;
          if (entry.isDir) {
            batch.push({
              path: entry.dirPath,
              filename: entry.filename,
              ext: '__dir__',
              isDir: 1,
              scanId,
            });
          } else {
            let st = null;
            try {
              st = fs.statSync(_toFsPath(entry.fullPath));
            } catch (_) {
              st = null;
            }
            batch.push({
              path: entry.dirPath,
              filename: entry.filename,
              ext: entry.ext,
              isDir: 0,
              size: st && typeof st.size === 'number' ? st.size : null,
              mtimeMs: st && typeof st.mtimeMs === 'number' ? Math.trunc(st.mtimeMs) : null,
              scanId,
            });
          }
          if (batch.length >= FULL_SCAN_INSERT_BATCH_SIZE) {
            const toWrite = batch;
            batch = [];
            const r = await this.store.upsertFilesBatchIncremental(toWrite, { scanId });
            total += r.total || 0;
            inserted += r.inserted || 0;
            updatedScanId += r.updatedScanId || 0;
          }
          return true;
        });
      }

      if (batch.length > 0) {
        const r = await this.store.upsertFilesBatchIncremental(batch, { scanId });
        total += r.total || 0;
        inserted += r.inserted || 0;
        updatedScanId += r.updatedScanId || 0;
      }

      const removed = await this.store.deleteRowsNotInScanIdUnderRoots(scanId, scanRoots).catch(() => 0);
      await tableConfig.setConfigByKey(CONFIG_KEY_LAST_FULL_SCAN_MS, String(_nowMs()));

      Logger.info('✅ fileAllIndexWorker full index done', {
        scanId,
        total,
        inserted,
        updatedScanId,
        removed,
        costMs: _nowMs() - start,
      });
    } catch (err) {
      Logger.error('❌ fileAllIndexWorker full index failed:', err);
    } finally {
      this.fullIndexing = false;
      await this.scheduleNextFullIndex().catch(() => {});
    }
  }

  async scheduleNextFullIndex() {
    if (this.stopped) return;
    if (this.fullIndexing) return;
    if (this.fullScanTimer) clearTimeout(this.fullScanTimer);
    this.fullScanTimer = null;

    await this.loadIntervalConfig().catch(() => {});
    const raw = await tableConfig.getConfigByKey(CONFIG_KEY_LAST_FULL_SCAN_MS).catch(() => null);
    const last = raw ? Number(raw) || 0 : 0;
    const now = _nowMs();

    const intervalMs = this.fullScanIntervalMs || _hoursToMs(DEFAULT_INTERVAL_HOURS);
    const dueAt = last > 0 ? last + intervalMs : now;
    const delayMs = Math.max(30 * 1000, dueAt - now);

    this.fullScanTimer = setTimeout(() => {
      this.runFullIndexIfDue({ reason: 'scheduled' }).catch(() => {});
    }, delayMs);
  }

  async shutdown() {
    this.stopped = true;
    this.clearTimers();
  }
}

const worker = new FileAllIndexWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'config') {
    const intervalHours = _safeIntervalHours(message?.data?.intervalHours);
    worker.fullScanIntervalMs = _hoursToMs(intervalHours);
    worker.scheduleNextFullIndex().catch(() => {});
  }
  if (message.type === 'fullIndexNow') {
    worker.runFullIndex({ reason: 'manual' }).catch(err => Logger.error('❌ fileAllIndexWorker manual full index failed:', err));
  }
  if (message.type === 'stop') {
    worker.shutdown().finally(() => process.exit(0));
  }
});

process.on('SIGTERM', () => {
  worker.shutdown().finally(() => process.exit(0));
});

process.on('SIGINT', () => {
  worker.shutdown().finally(() => process.exit(0));
});

process.on('uncaughtException', err => {
  Logger.error('❌ fileAllIndexWorker uncaughtException', err);
  worker.shutdown().finally(() => process.exit(0));
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ fileAllIndexWorker unhandledRejection', reason);
  worker.shutdown().finally(() => process.exit(0));
});
