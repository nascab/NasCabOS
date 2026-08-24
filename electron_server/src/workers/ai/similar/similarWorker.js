const fs = require('fs');
const path = require('path');
const Logger = require('../../../utils/logger');
const dbUtil = require('../../../db/dbUtil');
const knexUtil = require('../../../db/knexUtil');
const tableConfig = require('../../../db/table/tableConfig');
const sharpUtils = require('../../../utils/sharpUtils');
// 确保 worker 线程中 sharp-phash 也拿到内置版（带 HEIC 支持）
require('../../../utils/sharpConfigured');

const phash = require('sharp-phash');
const phashDistance = require('sharp-phash/distance');

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function asInt(v, fallback = 0) {
  const n = Math.floor(Number(v));
  return Number.isFinite(n) ? n : fallback;
}

class SimilarWorker {
  constructor() {
    this.isRunning = false;
    this.forceRebuild = false;
    this.batchSize = 15;
    this.rebuildPageSize = 1000;
    this.prefixLen = 12;
    this.maxBucketSize = 400;
    this.distanceThreshold = 6;
    this.scanProgressMinIntervalMs = 30 * 1000;
    this.lastScanProgressAt = 0;
    this.init();
  }

  async _setConfig(key, value) {
    try {
      await tableConfig.setConfigByKey(key, String(value));
    } catch (_) {}
  }

  async _updateScanProgress({ running, force = false }) {
    if (!this.knex) return;

    const now = Date.now();
    if (!force && this.lastScanProgressAt > 0 && now - this.lastScanProgressAt < this.scanProgressMinIntervalMs) {
      return;
    }
    this.lastScanProgressAt = now;

    const row = await this.knex('photo_index')
      .where({ is_file: 1, in_trash: 0, type: 1 })
      .select(this.knex.raw('COUNT(1) as total'), this.knex.raw('SUM(CASE WHEN gen_phash >= 1 THEN 1 ELSE 0 END) as done'))
      .first()
      .catch(() => null);

    const total = asInt(row && row.total, 0);
    const done = asInt(row && row.done, 0);
    const percent = total > 0 ? Math.floor((Math.min(done, total) * 100) / total) : 0;

    await Promise.allSettled([
      this._setConfig('ai_similar_scan_running', running ? 1 : 0),
      this._setConfig('ai_similar_scan_total', total),
      this._setConfig('ai_similar_scan_done', done),
      this._setConfig('ai_similar_scan_percent', percent),
    ]);
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
      this.knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
      const enabled = await tableConfig.getConfigByKey('ai_similar_enable').catch(() => '0');
      if (enabled !== '1') {
        process.exit(0);
      }
      this.isRunning = true;
      const pendingCompare = await this.knex('photo_index')
        .where({ type: 1, is_file: 1, in_trash: 0, gen_phash: 1 })
        .whereNotNull('phash')
        .andWhere('phash', '!=', '')
        .first('id')
        .catch(() => null);

      this.forceRebuild = !!(pendingCompare && pendingCompare.id);
      await Promise.allSettled([this._setConfig('ai_similar_scan_running', 0), this._setConfig('ai_similar_compare_running', 0)]);

      await this.startLoop();
    } catch (err) {
      Logger.error('❌ Similar Worker init failed:', err);
      process.exit(1);
    }
  }

  async startLoop() {
    let processedAny = false;

    while (this.isRunning) {
      const rows = await this.getNextBatch();
      if (!rows || rows.length === 0) break;

      await this._updateScanProgress({ running: true }).catch(() => null);
      for (const row of rows) {
        if (!this.isRunning) break;
        const ok = await this.processOne(row).catch(() => false);
        if (ok) processedAny = true;
      }
      await sleep(20);
    }

    await this._updateScanProgress({ running: false, force: true }).catch(() => null);

    if (this.isRunning && (processedAny || this.forceRebuild)) {
      await this.comparePendingGroups().catch(err => Logger.error('❌ comparePendingGroups failed', err));
    }

    await Promise.allSettled([this._updateScanProgress({ running: false, force: true }), this._setConfig('ai_similar_compare_running', 0)]);

    process.exit(0);
  }

  async getNextBatch() {
    return this.knex('photo_index')
      .select('id', 'path', 'filename', 'file_hash')
      .where({ gen_phash: 0, is_file: 1, in_trash: 0, type: 1 })
      .where(builder => builder.whereNull('phash').orWhere('phash', ''))
      .orderBy('id', 'asc')
      .limit(this.batchSize)
      .catch(() => []);
  }

  async processOne(row) {
    const id = row && row.id ? Number(row.id) : 0;
    if (!id) return false;

    const fileHash = row && row.file_hash ? String(row.file_hash) : '';
    if (!fileHash) {
      await this.markDone(id);
      return false;
    }

    const dirPath = row && row.path ? String(row.path) : '';
    const filename = row && row.filename ? String(row.filename) : '';
    const fullPath = dirPath && filename ? path.join(dirPath, filename) : '';
    if (!fullPath) {
      await this.markDone(id);
      return false;
    }
    try {
      if (!fs.existsSync(fullPath)) {
        await this.markDone(id);
        return false;
      }
    } catch (_) {
      await this.markDone(id);
      return false;
    }

    let converted;
    try {
      converted = await sharpUtils.transSpcielFormat(fullPath);
    } catch (_) {
      converted = fullPath;
    }

    let imageArg = converted;
    let sharpOptions = undefined;
    if (converted && typeof converted === 'object' && !Buffer.isBuffer(converted) && converted.input && converted.options) {
      imageArg = converted.input;
      sharpOptions = converted.options;
    }

    let fingerprint = '';
    try {
      fingerprint = await phash(imageArg, sharpOptions);
    } catch (_) {
      fingerprint = '';
    }

    if (!fingerprint || typeof fingerprint !== 'string' || fingerprint.length !== 64) {
      await this.markDone(id);
      return false;
    }

    await this.knex('photo_index')
      .where({ id })
      .update({ phash: fingerprint, gen_phash: 1 })
      .catch(() => {});

    return true;
  }

  async markDone(id) {
    await this.knex('photo_index')
      .where({ id })
      .update({ gen_phash: 2 })
      .catch(() => {});
  }

  async comparePendingGroups() {
    const parseFileHashList = v => {
      if (!v) return [];
      try {
        const arr = JSON.parse(String(v));
        return Array.isArray(arr) ? arr.map(x => String(x || '')).filter(Boolean) : [];
      } catch (_) {
        return [];
      }
    };

    const upsertGroup = async ({ leaderId, leaderFileHash, fileHash }) => {
      if (!leaderId || !leaderFileHash || !fileHash) return;

      const findGroupRowsByHash = async hash => {
        if (!hash) return [];
        return this.knex('photo_similar')
          .select('id', 'index_id', 'similar_file_hash')
          .whereRaw('instr(similar_file_hash, ?) > 0', [`"${hash}"`])
          .catch(() => []);
      };

      const findGroupRowByIndexId = async indexId => {
        if (!indexId) return null;
        return this.knex('photo_similar')
          .where({ index_id: indexId })
          .first('id', 'index_id', 'similar_file_hash')
          .catch(() => null);
      };

      const [byIndexId, rowsByLeaderHash, rowsByFileHash] = await Promise.all([findGroupRowByIndexId(leaderId), findGroupRowsByHash(leaderFileHash), findGroupRowsByHash(fileHash)]);

      const groupRows = [];
      if (byIndexId && byIndexId.id) groupRows.push(byIndexId);
      for (const r of rowsByLeaderHash) {
        if (r && r.id) groupRows.push(r);
      }
      for (const r of rowsByFileHash) {
        if (r && r.id) groupRows.push(r);
      }

      const uniq = new Map();
      for (const r of groupRows) {
        const rid = Number(r && r.id) || 0;
        if (!rid) continue;
        if (!uniq.has(rid)) uniq.set(rid, r);
      }
      const rows = Array.from(uniq.values());

      let canonicalIndexId = Number(leaderId) || 0;
      for (const r of rows) {
        const idx = Number(r && r.index_id) || 0;
        if (idx > 0 && (canonicalIndexId <= 0 || idx < canonicalIndexId)) canonicalIndexId = idx;
      }
      if (!canonicalIndexId) canonicalIndexId = Number(leaderId) || 0;
      if (!canonicalIndexId) return;

      const set = new Set([leaderFileHash, fileHash]);
      for (const r of rows) {
        const list = parseFileHashList(r && r.similar_file_hash);
        for (const h of list) set.add(h);
      }
      if (set.size < 2) return;

      await this.knex.transaction(async trx => {
        const payload = { similar_file_hash: JSON.stringify(Array.from(set)) };

        let canonicalRow = rows.find(r => Number(r && r.index_id) === canonicalIndexId) || null;
        if (!canonicalRow || !canonicalRow.id) {
          canonicalRow = await trx('photo_similar')
            .where({ index_id: canonicalIndexId })
            .first('id', 'index_id')
            .catch(() => null);
        }

        if (canonicalRow && canonicalRow.id) {
          await trx('photo_similar')
            .where({ id: canonicalRow.id })
            .update(payload)
            .catch(() => {});
        } else {
          await trx('photo_similar')
            .insert({ index_id: canonicalIndexId, ...payload })
            .catch(() => {});
        }

        const keepId = canonicalRow && canonicalRow.id ? Number(canonicalRow.id) : 0;
        const deleteIds = rows.map(r => Number(r && r.id) || 0).filter(id => id > 0 && id !== keepId);
        if (deleteIds.length > 0) {
          await trx('photo_similar')
            .whereIn('id', deleteIds)
            .del()
            .catch(() => {});
        }
      });
    };

    const findBestCandidateInPrefix = async ({ id, prefix, fp }) => {
      let leaderId = 0;
      let leaderFileHash = '';
      let bestDist = Number.POSITIVE_INFINITY;
      let cursorId = Number.MAX_SAFE_INTEGER;

      while (this.isRunning) {
        const candidates = await this.knex('photo_index')
          .select('id', 'file_hash', 'phash')
          .where({ is_file: 1, in_trash: 0, type: 1 })
          .andWhere('id', '<', cursorId)
          .andWhere(builder => builder.where('gen_phash', 2).orWhere(inner => inner.where('gen_phash', 1).andWhere('id', '<', id)))
          .where('phash', 'like', `${prefix}%`)
          .orderBy('id', 'desc')
          .limit(this.maxBucketSize)
          .catch(() => []);

        if (!candidates || candidates.length === 0) break;

        for (const c of candidates) {
          const cid = c && c.id ? Number(c.id) : 0;
          const cfh = c && c.file_hash ? String(c.file_hash) : '';
          const cfp = c && c.phash ? String(c.phash) : '';
          if (!cid || !cfh || cfp.length !== 64) continue;
          const d = phashDistance(fp, cfp);
          if (d < bestDist) {
            bestDist = d;
            leaderId = cid;
            leaderFileHash = cfh;
            if (bestDist === 0) break;
          }
        }

        if (bestDist === 0) break;

        const last = candidates[candidates.length - 1];
        const lastId = last && last.id ? Number(last.id) : 0;
        if (!lastId) break;
        cursorId = lastId;
        if (candidates.length < this.maxBucketSize) break;
      }

      return { leaderId, leaderFileHash, bestDist };
    };

    const totalRow = await this.knex('photo_index')
      .where({ is_file: 1, in_trash: 0, type: 1, gen_phash: 1 })
      .whereNotNull('phash')
      .andWhere('phash', '!=', '')
      .count({ count: '*' })
      .first()
      .catch(() => null);
    const total = asInt(totalRow && (totalRow.count ?? totalRow['count(*)']), 0);

    await Promise.allSettled([
      this._setConfig('ai_similar_compare_running', total > 0 ? 1 : 0),
      this._setConfig('ai_similar_compare_total', total),
      this._setConfig('ai_similar_compare_done', 0),
      this._setConfig('ai_similar_compare_percent', total > 0 ? 0 : 100),
    ]);

    if (total <= 0) {
      this.forceRebuild = false;
      return 0;
    }

    let done = 0;
    let lastProgressAt = 0;
    const updateProgress = async force => {
      const now = Date.now();
      if (!force && lastProgressAt > 0 && now - lastProgressAt < 2000) return;
      lastProgressAt = now;
      const percent = total > 0 ? Math.floor((Math.min(done, total) * 100) / total) : 100;
      await Promise.allSettled([this._setConfig('ai_similar_compare_running', 1), this._setConfig('ai_similar_compare_done', done), this._setConfig('ai_similar_compare_percent', percent)]);
    };

    try {
      while (this.isRunning) {
        const rows = await this.knex('photo_index')
          .select('id', 'file_hash', 'phash')
          .where({ is_file: 1, in_trash: 0, type: 1, gen_phash: 1 })
          .whereNotNull('phash')
          .andWhere('phash', '!=', '')
          .orderBy('id', 'asc')
          .limit(this.rebuildPageSize)
          .catch(() => []);

        if (!rows || rows.length === 0) break;

        for (const r of rows) {
          if (!this.isRunning) break;

          const id = r && r.id ? Number(r.id) : 0;
          const fileHash = r && r.file_hash ? String(r.file_hash) : '';
          const fp = r && r.phash ? String(r.phash) : '';
          if (!id || !fileHash || fp.length !== 64) {
            if (id) await this.markDone(id);
            done += 1;
            await updateProgress(false);
            continue;
          }

          const prefix = fp.slice(0, this.prefixLen);
          const { leaderId, leaderFileHash, bestDist } = await findBestCandidateInPrefix({ id, prefix, fp });

          if (leaderId && bestDist <= this.distanceThreshold) {
            await upsertGroup({ leaderId, leaderFileHash, fileHash });
          }

          await this.markDone(id);
          done += 1;
          await updateProgress(false);
        }

        if (rows.length < this.rebuildPageSize) break;
        await sleep(10);
      }
    } finally {
      const finalPercent = total > 0 ? Math.floor((Math.min(done, total) * 100) / total) : 100;
      await Promise.allSettled([
        this._setConfig('ai_similar_compare_running', 0),
        this._setConfig('ai_similar_compare_done', done),
        this._setConfig('ai_similar_compare_percent', finalPercent),
        this._setConfig('ai_similar_compare_time', Date.now()),
      ]);
    }

    this.forceRebuild = false;
    return done;
  }

  stop() {
    this.isRunning = false;
  }
}

const worker = new SimilarWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'stop') worker.stop();
});

process.on('uncaughtException', err => {
  Logger.error('❌ similar worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ similar worker unhandledRejection', reason);
  process.exit(0);
});
