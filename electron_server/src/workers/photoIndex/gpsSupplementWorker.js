const Logger = require('../../utils/logger');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const tableConfig = require('../../db/table/tableConfig');
const GpsSupplementService = require('../../api/modules/photo/gps_add/gpsSupplementService');

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

class GpsSupplementWorker {
  constructor() {
    this.isRunning = false;
    this.batchSize = 20;
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
      this.knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
      this.service = new GpsSupplementService(this.knex);
      this.isRunning = true;
      await this._setRunning(true);
      await this.startLoop();
    } catch (err) {
      Logger.error('❌ GPS supplement worker init failed:', err);
      await this._setRunning(false);
      process.exit(1);
    }
  }

  async _setRunning(value) {
    try {
      await tableConfig.setConfigByKey('ai_gps_add_scan_running', value ? '1' : '0');
    } catch (_) {}
  }

  async getCandidateRows() {
    return this.knex('photo_index')
      .select('id', 'path', 'filename', 'camera', 'ext', 'original_time', 'latitude', 'longitude')
      .where({ is_file: 1, in_trash: 0, type: 1, gen_gps_add: 0 })
      .whereIn('ext', ['.jpg', '.jpeg'])
      .andWhere('original_time', '>', 0)
      .where(builder => {
        builder.whereNull('latitude').orWhere('latitude', 0);
      })
      .where(builder => {
        builder.whereNull('longitude').orWhere('longitude', 0);
      })
      .orderBy('original_time', 'asc')
      .orderBy('id', 'asc')
      .limit(this.batchSize)
      .catch(() => []);
  }

  async processOne(row) {
    const activeBatch = await this.service.getActiveBatchRow();
    if (activeBatch && activeBatch.id) return true;

    const referenceRows = await this.service.findReferencePhotos(row, 20);
    if (!referenceRows || referenceRows.length === 0) {
      // Only mark the current source photo as scanned. Nearby same-device photos
      // may still find reference photos when they are evaluated with their own
      // 3-hour window.
      await this.service.markScanned([row.id]);
      return false;
    }

    const pendingRows = await this.service.findPendingPhotos(row);
    if (!pendingRows || pendingRows.length <= 1) {
      await this.service.markScanned([row.id]);
      return false;
    }

    await this.service.createBatch(row, referenceRows, pendingRows);
    return true;
  }

  async startLoop() {
    let foundBatch = false;
    while (this.isRunning && !foundBatch) {
      const rows = await this.getCandidateRows();
      if (!rows || rows.length === 0) break;

      for (const row of rows) {
        if (!this.isRunning) break;
        foundBatch = await this.processOne(row).catch(err => {
          Logger.error('❌ GPS supplement worker process row failed:', err);
          return false;
        });
        if (foundBatch) break;
      }

      await sleep(20);
    }

    await this._setRunning(false);
    process.exit(0);
  }

  stop() {
    this.isRunning = false;
  }
}

const worker = new GpsSupplementWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'stop') worker.stop();
});
