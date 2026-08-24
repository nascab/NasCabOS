'use strict';

const path = require('path');
const fs = require('fs');
const Logger = require('../../../utils/logger');
const dbUtil = require('../../../db/dbUtil');
const knexUtil = require('../../../db/knexUtil');
const tableConfig = require('../../../db/table/tableConfig');
const { getOcrEngine } = require('./ocrOnnxUtil');
const fileService = require('../../../api/modules/file/core/fileService');
const { ensureNodejiebaDictLoaded } = require('../../../utils/nodejiebaInit');
const nodejieba = require('nodejieba');

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function tokenizeForFts(text) {
  const raw = String(text || '').trim();
  if (!raw) return '';
  ensureNodejiebaDictLoaded();
  const tokens = nodejieba.cutAll(raw);
  if (!Array.isArray(tokens) || tokens.length === 0) return raw;
  const normalized = tokens.map(t => String(t || '').trim()).filter(Boolean);
  if (normalized.length === 0) return raw;
  const uniq = [];
  const seen = new Set();
  for (const token of normalized) {
    if (seen.has(token)) continue;
    seen.add(token);
    uniq.push(token);
  }
  if (uniq.length === 0) return raw;
  return uniq.join(' ');
}

class OcrWorker {
  constructor() {
    this.isRunning = false;
    this.batchSize = 10;
    this.processedCount = 0;
    this.lastMemLogAt = 0;
    this.maxRssMb = Math.floor(Number(process.env.OCR_MAX_RSS_MB || 0));
    this.gcEveryN = Math.floor(Number(process.env.OCR_GC_EVERY_N || 0));
    this.exitForMem = false;
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
      this.knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
      const enabled = await tableConfig.getConfigByKey('ai_ocr_enable').catch(() => '0');
      if (enabled !== '1') {
        process.exit(0);
      }
      Logger.info('[ocrWorker] waiting for remote OCR model...');
      this.ocrEngine = await getOcrEngine();
      Logger.info('[ocrWorker] OCR model ready');
      this.isRunning = true;

      await this.startLoop();
    } catch (err) {
      Logger.error('❌ OCR Worker init failed:', err);
      process.exit(1);
    }
  }

  async startLoop() {
    while (this.isRunning) {
      try {
        if (this.shouldExitForMem()) {
          this.exitForMem = true;
          Logger.warn('⚠️ OCR worker RSS limit reached, exiting for recycle', this.maxRssMb);
          break;
        }
        const rows = await this.getNextBatch();
        if (!rows || rows.length === 0) {
          Logger.info('✅ No pending OCR tasks, worker exiting');
          process.exit(0);
        }

        for (const row of rows) {
          if (!this.isRunning) break;
          await this.processOne(row);
          this.processedCount++;
          this.maybeLogMemory();
          this.maybeRunGc();
          if (this.shouldExitForMem()) {
            this.exitForMem = true;
            Logger.warn('⚠️ OCR worker RSS limit reached after item, exiting for recycle', this.maxRssMb);
            this.isRunning = false;
            break;
          }
        }
      } catch (err) {
        Logger.error('❌ OCR Worker loop error:', err);
        await sleep(1000);
      }
    }
    if (this.exitForMem && process.send) {
      try {
        process.send({ type: 'ocrWorkerRecycle', data: { reason: 'rss_limit', maxRssMb: this.maxRssMb } });
      } catch (_) {}
    }
    process.exit(0);
  }

  async getNextBatch() {
    return this.knex('photo_index')
      .select('id', 'path', 'filename', 'file_hash', 'type')
      .where({ gen_ocr: 0, is_file: 1, in_trash: 0 })
      .whereIn('type', [1, 2])
      .orderBy('id', 'asc')
      .limit(this.batchSize)
      .catch(() => []);
  }

  async processOne(row) {
    const id = row && row.id ? Number(row.id) : 0;
    if (!id) return;

    const fileHash = row.file_hash ? String(row.file_hash) : '';
    if (!fileHash) {
      await this.markIndexDone(id);
      return;
    }

    const hasOcr = await this.knex('photo_info_fts')
      .where({ file_hash: fileHash })
      .whereNotNull('ocr')
      .whereNot('ocr', '')
      .first('ocr')
      .then(r => !!(r && r.ocr))
      .catch(() => false);

    if (hasOcr) {
      await this.markIndexDone(id);
      return;
    }

    const fullPath = path.join(String(row.path || ''), String(row.filename || ''));
    if (!fullPath || !fs.existsSync(fullPath)) {
      await this.markIndexDone(id);
      return;
    }

    const type = row && row.type ? Number(row.type) : 0;
    let imagePath = fullPath;
    if (type === 2) {
      try {
        imagePath = await fileService.getTinyImgByPath(fullPath, undefined, { deferSlowIo: false });
      } catch (err) {
        Logger.error(`❌  video thumbnail failed: ${fullPath}`, err);
        await this.markIndexDone(id);
        return;
      }
    }
    if (!imagePath || !fs.existsSync(imagePath)) {
      await this.markIndexDone(id);
      return;
    }

    let ocrValue = '';
    try {
      const ocrRes = await this.ocrEngine.ocrImage(imagePath);
      if (!ocrRes || ocrRes === '' || !ocrRes.text || String(ocrRes.text).trim() === '') {
        await this.markIndexDone(id);
        return;
      }
      ocrValue = String(ocrRes.text);
    } catch (err) {
      Logger.error(`❌  OCR failed: ${imagePath}`, err);
      await this.markIndexDone(id);
      return;
    }

    ocrValue = tokenizeForFts(ocrValue);
    if (!ocrValue) {
      await this.markIndexDone(id);
      return;
    }

    const filename = row && row.filename ? String(row.filename) : '';
    try {
      await this.knex.transaction(async trx => {
        const updated = await trx('photo_info_fts').where({ file_hash: fileHash }).update({ filename, ocr: ocrValue });
        if (!updated) {
          await trx('photo_info_fts').insert({ file_hash: fileHash, filename, ocr: ocrValue });
        }
        await trx('photo_index').where({ id }).update({ gen_ocr: 1 });
      });
    } catch (err) {
      Logger.error('❌  OCR DB write failed:', err);
    }
  }

  async markIndexDone(id) {
    await this.knex('photo_index')
      .where({ id })
      .update({ gen_ocr: 1 })
      .catch(() => {});
  }

  shouldExitForMem() {
    if (!Number.isFinite(this.maxRssMb) || this.maxRssMb <= 0) return false;
    const rssMb = Math.round(process.memoryUsage().rss / 1024 / 1024);
    return rssMb >= this.maxRssMb;
  }

  maybeLogMemory() {
    const now = Date.now();
    if (now - this.lastMemLogAt < 30 * 1000) return;
    this.lastMemLogAt = now;
    const mu = process.memoryUsage();
    // Logger.info('🧠 OCR worker memory', {
    //   rssMb: Math.round(mu.rss / 1024 / 1024),
    //   heapUsedMb: Math.round(mu.heapUsed / 1024 / 1024),
    //   externalMb: Math.round(mu.external / 1024 / 1024),
    //   processedCount: this.processedCount,
    // });
  }

  maybeRunGc() {
    if (!Number.isFinite(this.gcEveryN) || this.gcEveryN <= 0) return;
    if (this.processedCount <= 0 || this.processedCount % this.gcEveryN !== 0) return;
    if (typeof global.gc !== 'function') return;
    try {
      global.gc();
    } catch (_) {}
  }

  stop() {
    this.isRunning = false;
  }
}

const worker = new OcrWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'stop') {
    worker.stop();
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ ocr worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ ocr worker unhandledRejection', reason);
  process.exit(0);
});
