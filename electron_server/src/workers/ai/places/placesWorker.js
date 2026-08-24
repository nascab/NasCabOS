'use strict';

const path = require('path');
const fs = require('fs');
const Logger = require('../../../utils/logger');
const dbUtil = require('../../../db/dbUtil');
const knexUtil = require('../../../db/knexUtil');
const tableConfig = require('../../../db/table/tableConfig');
const { predictPlace, ensurePlaces365Ready, isRemoteModelError } = require('./placesUtil');
const fileService = require('../../../api/modules/file/core/fileService');

const PLACE_CONF_THRESH = Math.max(0, Math.min(1, Number(process.env.PLACE_CONF_THRESH ?? 0.4)));

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

class PlacesWorker {
  constructor() {
    this.isRunning = false;
    this.batchSize = 10;
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
      this.knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
      const enabled = await tableConfig.getConfigByKey('ai_place_enable').catch(() => '0');
      if (enabled !== '1') {
        process.exit(0);
      }
      Logger.info('[placesWorker] waiting for remote places365 model...');
      await ensurePlaces365Ready();
      Logger.info('[placesWorker] places365 model ready');
      this.isRunning = true;

      await this.startLoop();
    } catch (err) {
      Logger.error('❌ Places Worker init failed:', err);
      process.exit(1);
    }
  }

  async startLoop() {
    while (this.isRunning) {
      try {
        const rows = await this.getNextBatch();
        if (!rows || rows.length === 0) {
          Logger.info('✅ No pending scene tasks, worker exiting');
          process.exit(0);
        }

        for (const row of rows) {
          if (!this.isRunning) break;
          try {
            await this.processOne(row);
          } catch (err) {
            if (isRemoteModelError(err)) {
              Logger.warn('[placesWorker] model not ready, retry later', {
                error: err && err.message ? err.message : String(err),
              });
              await sleep(5000);
              break;
            }
            throw err;
          }
        }
      } catch (err) {
        if (isRemoteModelError(err)) {
          Logger.warn('[placesWorker] model not ready in loop, retry later', {
            error: err && err.message ? err.message : String(err),
          });
          await sleep(5000);
          continue;
        }
        Logger.error('❌ Places Worker loop error:', err);
        await sleep(1000);
      }
    }
    process.exit(0);
  }

  async getNextBatch() {
    return this.knex('photo_index')
      .select('id', 'path', 'filename', 'file_hash', 'type')
      .where({ gen_place: 0, is_file: 1, in_trash: 0 })
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

    const existed = await this.knex('photo_places2filehash')
      .where({ file_hash: fileHash })
      .first('id')
      .catch(() => null);
    if (existed && existed.id) {
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

    let pred = null;
    try {
      pred = await predictPlace(imagePath);
    } catch (err) {
      if (isRemoteModelError(err)) {
        throw err;
      }
      Logger.error(`❌  scene recognition failed: ${imagePath}`, err);
      await this.markIndexDone(id);
      return;
    }

    const prob = pred && Number.isFinite(pred.prob) ? Number(pred.prob) : 0;
    if (prob < PLACE_CONF_THRESH) {
      await this.markIndexDone(id);
      return;
    }

    const placeName = pred && pred.label ? String(pred.label) : '';
    if (!placeName) {
      await this.markIndexDone(id);
      return;
    }

    try {
      await this.knex.transaction(async trx => {
        await trx('photo_places')
          .insert({
            place_name: placeName,
            photo_count: 0,
            is_hide: 0,
            update_time: trx.fn.now(),
            create_time: trx.fn.now(),
          })
          .onConflict(['place_name'])
          .ignore();

        const inserted = await trx('photo_places2filehash')
          .insert({
            place_name: placeName,
            file_hash: fileHash,
            create_time: trx.fn.now(),
          })
          .onConflict(['file_hash'])
          .ignore();

        const didInsert = typeof inserted === 'number' ? inserted > 0 : Array.isArray(inserted) ? inserted.length > 0 : !!inserted;
        if (didInsert) {
          await trx('photo_places')
            .where({ place_name: placeName })
            .update({ photo_count: trx.raw('photo_count + 1'), update_time: trx.fn.now() })
            .catch(() => {});
        }

        await trx('photo_index').where({ id }).update({ gen_place: 1 });
      });
    } catch (err) {
      Logger.error('❌  scene DB write failed:', err);
      await this.markIndexDone(id);
    }
  }

  async markIndexDone(id) {
    await this.knex('photo_index')
      .where({ id })
      .update({ gen_place: 1 })
      .catch(() => {});
  }

  stop() {
    this.isRunning = false;
  }
}

const worker = new PlacesWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'stop') worker.stop();
});

process.on('uncaughtException', err => {
  Logger.error('❌ places worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ places worker unhandledRejection', reason);
  process.exit(0);
});
