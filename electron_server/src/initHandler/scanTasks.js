const Logger = require('../utils/logger');
const dbUtil = require('../db/dbUtil');
const tablePhotoSource = require('../db/table/tablePhotoSource');
const tablePhotoScanTask = require('../db/table/tablePhotoScanTask');
const tableVideoSource = require('../db/table/tableVideoSource');
const tableVideoScanTask = require('../db/table/tableVideoScanTask');
const tableBookSource = require('../db/table/tableBookSource');
const tableBookScanTask = require('../db/table/tableBookScanTask');
const tableMusicSource = require('../db/table/tableMusicSource');
const tableMusicScanTask = require('../db/table/tableMusicScanTask');

module.exports = {
  // 扫描所有照片源
  async enqueueStartupPhotoScanTasks() {
    try {
      const scanPaths = await tablePhotoSource.getScanWhenStartPaths(dbUtil.getConnectPhotoDb());
      if (!scanPaths || scanPaths.length === 0) return;
      Logger.info(`🔍 Found ${scanPaths.length} photo source(s) to scan`);
      await tablePhotoScanTask.enqueueScanPaths(scanPaths, 'scan_when_start');
      const hasAny = await tablePhotoScanTask.hasAnyTask();
      if (hasAny) this.startPhotoIndexWorker();
    } catch (err) {
      Logger.error('❌  init photo scan tasks failed:', err);
    }
  },

  async enqueueStartupVideoScanTasks() {
    try {
      const scanPaths = await tableVideoSource.getScanWhenStartPaths(dbUtil.getConnectVideoDb());
      if (!scanPaths || scanPaths.length === 0) return;
      Logger.info(`🔍 Found ${scanPaths.length} video source(s) to scan`);
      await tableVideoScanTask.enqueueScanPaths(scanPaths, 'scan_when_start');
      const hasAny = await tableVideoScanTask.hasAnyTask();
      if (hasAny) this.startVideoIndexWorker();
    } catch (err) {
      Logger.error('❌  init video scan tasks failed:', err);
    }
  },

  async enqueueStartupBookScanTasks() {
    try {
      const scanPaths = await tableBookSource.getScanWhenStartPaths(dbUtil.getConnectBookDb());
      if (!scanPaths || scanPaths.length === 0) return;
      Logger.info(`🔍 Found ${scanPaths.length} book source(s) to scan`);
      await tableBookScanTask.enqueueScanPaths(scanPaths, 'scan_when_start');
      const hasAny = await tableBookScanTask.hasAnyTask();
      if (hasAny) this.startBookIndexWorker();
    } catch (err) {
      Logger.error('❌  init book scan tasks failed:', err);
    }
  },

  async enqueueStartupMusicScanTasks() {
    try {
      const scanPaths = await tableMusicSource.getScanWhenStartPaths(dbUtil.getConnectMusicDb());
      if (!scanPaths || scanPaths.length === 0) return;
      Logger.info(`🔍 Found ${scanPaths.length} music source(s) to scan`);
      await tableMusicScanTask.enqueueScanPaths(scanPaths, 'scan_when_start');
      const hasAny = await tableMusicScanTask.hasAnyTask();
      if (hasAny) this.startMusicIndexWorker();
    } catch (err) {
      Logger.error('❌  init music scan tasks failed:', err);
    }
  },
};
