const path = require('path');
const cluster = require('cluster');
const Logger = require('../utils/logger');
const knexUtil = require('../db/knexUtil');
const dbUtil = require('../db/dbUtil');
const tableConfig = require('../db/table/tableConfig');
const config = require('../config/config');
const { getSingletonWorkerManager } = require('../workers/singletonWorkerManager');
const { getProcessRegistry } = require('../workers/processRegistry');
const { detachSessionsByWorkerPid } = require('../msgHandler/terminalSessions');

const singletonWorkerManager = getSingletonWorkerManager();

function getWorkerEnv(extraEnv = {}) {
  return {
    ...extraEnv,
    userDataFolder: extraEnv.userDataFolder || process.env['userDataFolder'] || (typeof config.getUserDataPath === 'function' ? config.getUserDataPath() : ''),
  };
}

async function getP2pRemoteAccessEnabledSafe() {
  try {
    if (!knexUtil.hasConnection(dbUtil.DB_PATHS.MAIN_DB)) {
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
    }
    const enabled = await tableConfig.getP2pRemoteAccessEnabled();
    return enabled === true;
  } catch (_) {
    return false;
  }
}

async function getDdnsEnabledSafe() {
  try {
    if (!knexUtil.hasConnection(dbUtil.DB_PATHS.MAIN_DB)) {
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
    }
    const raw = await tableConfig.getConfigByKey(tableConfig.KEY_DDNS_ENABLED);
    if (raw === null || raw === undefined) return false;
    const s = typeof raw === 'number' ? String(raw) : String(raw).trim().toLowerCase();
    return s === '1' || s === 'true' || s === 'yes' || s === 'on';
  } catch (_) {
    return false;
  }
}

function getClusterWorkerPid(worker) {
  const pid = Number((worker && worker.process && worker.process.pid) || (worker && worker.pid) || 0);
  return Number.isFinite(pid) && pid > 0 ? pid : 0;
}

module.exports = {
  // 启动FFmpeg硬件加速检测Worker
  startFfmpegHwTestWorker() {
    singletonWorkerManager.startWorker('ffmpegHwTestWorker', 'ffmpegHwTestWorker.js', {
      env: {
        WORKER_TYPE: 'ffmpegHwTest',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      onStart: () => {

      },
      onStop: () => {

      },
      onError: error => {
        if (error) Logger.error('❌ FFmpeg HW probe worker error', error);
      },
    });
  },

  startOneExpressWorker(httpPort, httpsPort, serverId, jwtSecret) {
    const worker = cluster.fork(
      getWorkerEnv({
        WORKER_TYPE: 'express',
        WORKER_PORT: httpPort,
        WORKER_HTTPS_PORT: httpsPort,
        SERVER_ID: serverId,
        JWT_SECRET: jwtSecret,
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      })
    );
    const workerPid = getClusterWorkerPid(worker);
    if (workerPid > 0) {
      getProcessRegistry().registerProcess({ pid: workerPid, workerPath: 'expressWorker.js', role: 'expressWorker' });
    }
    this.msgUtil.bindExpressWorker(worker, { httpPort, httpsPort, serverId, jwtSecret });

    try {
      if (!Array.isArray(this.expressWorkers)) this.expressWorkers = [];
      this.expressWorkers.push(worker);
      worker.on('exit', () => {
        const exitPid = getClusterWorkerPid(worker);
        if (exitPid > 0) getProcessRegistry().removeProcessByPid(exitPid);
        if (exitPid > 0) detachSessionsByWorkerPid(exitPid);
        try {
          this.expressWorkers = (this.expressWorkers || []).filter(w => w && w !== worker && w.isConnected && w.isConnected());
        } catch (_) {
          try {
            this.expressWorkers = (this.expressWorkers || []).filter(w => w && w !== worker);
          } catch (_) {}
        }
      });
    } catch (_) {}

    Logger.info(`🚀 Starting NasCabAPI, ports:`, { http: httpPort, https: httpsPort });
  },

  startFileOperationWorker() {
    singletonWorkerManager.startWorker('fileOperationWorker', 'fileOperationWorker.js', {
      env: {
        WORKER_TYPE: 'fileOperation',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['fileOperationWorker'],
      onStart: worker => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ file operation worker error:`, error);
      },
    });
  },

  startPhotoIndexWorker() {
    const worker = singletonWorkerManager.startWorker('photoIndexWorker', `photoIndex${path.sep}photoIndexWorker.js`, {
      env: {
        WORKER_TYPE: 'photoIndex',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['photoIndexWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ photo index worker error:`, error);
      },
    });
    this.msgUtil.bindPhotoIndexWorker(worker);
    return worker;
  },

  startGpsSupplementWorker() {
    return singletonWorkerManager.startWorker('gpsSupplementWorker', `photoIndex${path.sep}gpsSupplementWorker.js`, {
      env: {
        WORKER_TYPE: 'gpsSupplement',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['gpsSupplementWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ gps supplement worker error:`, error);
      },
    });
  },

  startVideoIndexWorker() {
    const worker = singletonWorkerManager.startWorker('videoIndexWorker', `videoIndex${path.sep}videoIndexWorker.js`, {
      env: {
        WORKER_TYPE: 'videoIndex',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['videoIndexWorker'],
      onStart: () => {
        Logger.info(`🎬 video index worker started`);
      },
      onStop: (code, signal) => {
        Logger.info(`🔚 video index worker exited, code: ${code}, signal: ${signal}`);
      },
      onError: error => {
        if (error) Logger.error(`❌ video index worker error:`, error);
      },
    });
    this.msgUtil.bindVideoIndexWorker(worker);
    return worker;
  },

  startBookIndexWorker() {
    const worker = singletonWorkerManager.startWorker('bookIndexWorker', `bookIndex${path.sep}bookIndexWorker.js`, {
      env: {
        WORKER_TYPE: 'bookIndex',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['bookIndexWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ book index worker error:`, error);
      },
    });
    this.msgUtil.bindBookIndexWorker(worker);
    return worker;
  },

  startMusicIndexWorker() {
    const worker = singletonWorkerManager.startWorker('musicIndexWorker', `musicIndex${path.sep}musicIndexWorker.js`, {
      env: {
        WORKER_TYPE: 'musicIndex',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['musicIndexWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ music index worker error:`, error);
      },
    });
    this.msgUtil.bindMusicIndexWorker(worker);
    return worker;
  },

  async maybeStartSubtitlePreExtractWorker({ requirePending = false } = {}) {
    try {
      const raw = await tableConfig.getConfigByKey('subtitlePreExtractEnable');
      if (raw !== null && raw !== undefined && String(raw).trim() !== '') {
        const s = String(raw).trim().toLowerCase();
        if (s !== '1' && s !== 'true' && s !== 'yes' && s !== 'on') return;
      }
      if (singletonWorkerManager.isWorkerRunning('subtitlePreExtractWorker')) return;
      if (requirePending) {
        const { hasPendingSubtitlePreExtractWork } = require('../workers/videoIndex/subtitlePreExtractWorker/subtitlePreExtractRunner');
        const hasPending = await hasPendingSubtitlePreExtractWork();
        if (!hasPending) return;
      }
      this.startSubtitlePreExtractWorker();
    } catch (error) {
      Logger.error('❌ maybeStartSubtitlePreExtractWorker failed:', error);
    }
  },

  startSubtitlePreExtractWorker() {
    return singletonWorkerManager.startWorker(
      'subtitlePreExtractWorker',
      `videoIndex${path.sep}subtitlePreExtractWorker${path.sep}subtitlePreExtractWorker.js`,
      {
        env: {
          WORKER_TYPE: 'subtitlePreExtract',
          PATH_DATABASE: this.pathDatabase,
          PATH_CACHE: this.pathCache,
        },
        messageTypes: [],
        tags: ['subtitlePreExtractWorker'],
        onStart: () => {},
        onStop: () => {},
        onError: error => {
          if (error) Logger.error('❌ subtitle pre-extract worker error:', error);
        },
      }
    );
  },

  startNfoFetchWorker() {
    const worker = singletonWorkerManager.startWorker('nfoFetchWorker', `videoIndex${path.sep}nfoFetchWorker${path.sep}nfoFetchWorker.js`, {
      env: {
        WORKER_TYPE: 'nfoFetch',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['nfoFetchWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ NFO fetch worker error:`, error);
      },
    });
    return worker;
  },

  startFaceWorker() {
    let that = this;
    return singletonWorkerManager.startWorker('faceWorker', `ai${path.sep}faces${path.sep}faceWorker.js`, {
      env: {
        WORKER_TYPE: 'aiFace',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['faceWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        async function check() {
          const knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);

          // 尝试跳过导致崩溃的图片
          try {
            const nextItem = await knex('photo_index').select('id', 'path').where({ gen_faces: 0, is_file: 1, in_trash: 0 }).whereIn('type', [1, 2]).orderBy('original_time', 'asc').first();

            if (nextItem) {
              console.log(`⚠️ 检测到Worker异常退出，跳过可能导致崩溃的图片: id=${nextItem.id}, path=${nextItem.path}/${nextItem.filename}`);
              await knex('photo_index').where({ id: nextItem.id }).update({ gen_faces: 1 });
            }
          } catch (e) {
            console.error('Skip corrupt image failed:', e);
          }

          let result = await knex('photo_index')
            .where({ gen_faces: 0, is_file: 1, in_trash: 0 })
            .whereIn('type', [1, 2])
            .count('* as total') // 用 as 给计数结果起别名 total
            .first(); // 只取第一条结果（count 结果只有一行）

          if (result && result.total > 0) {
            console.log('人脸检测正在重启,待处理数量：', result.total);

            setTimeout(() => {
              that.startFaceWorker();
            }, 10 * 1000);
          }
        }
        check();
      },
    });
  },

  startPlacesWorker() {
    return singletonWorkerManager.startWorker('placesWorker', `ai${path.sep}places${path.sep}placesWorker.js`, {
      env: {
        WORKER_TYPE: 'aiPlace',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['placesWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ places/scene worker error:`, error);
      },
    });
  },

  startOcrWorker() {
    const scheduleRestartIfNeeded = () => {
      if (this._ocrRestartTimer) return;
      this._ocrRestartTimer = setTimeout(() => {
        this._ocrRestartTimer = null;
        Promise.resolve()
          .then(async () => {
            try {
              if (!knexUtil.hasConnection(dbUtil.DB_PATHS.MAIN_DB)) {
                await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
              }
            } catch (_) {}
            const enabled = await tableConfig.getConfigByKey('ai_ocr_enable').catch(() => '0');
            if (enabled !== '1') return;

            if (!knexUtil.hasConnection(dbUtil.DB_PATHS.PHOTO_DB)) {
              await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);
            }
            const knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
            const pending = await knex('photo_index')
              .where({ gen_ocr: 0, is_file: 1, in_trash: 0 })
              .whereIn('type', [1, 2])
              .count('* as total')
              .first()
              .then(r => Number((r && r.total) || 0))
              .catch(() => 0);
            if (pending <= 0) return;
            if (singletonWorkerManager.isWorkerRunning('ocrWorker')) return;
            Logger.info('🔄 OCR worker auto-restart, pending:', pending);
            this.startOcrWorker();
          })
          .catch(e => {
            Logger.error('❌ OCR worker auto-restart failed:', e);
          });
      }, 5000);
    };

    return singletonWorkerManager.startWorker('ocrWorker', `ai${path.sep}ocr${path.sep}ocrWorker.js`, {
      env: {
        WORKER_TYPE: 'aiOcr',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
        OCR_MAX_RSS_MB: process.env.OCR_MAX_RSS_MB || '1229', //最大内存占用量，超过会重启worker
      },
      messageTypes: [],
      tags: ['ocrWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {
        const normalExit = !signal && Number(code) === 0;
        if (normalExit) scheduleRestartIfNeeded();
      },
      onError: error => {
        if (error) Logger.error(`❌ OCR worker error:`, error);
        scheduleRestartIfNeeded();
      },
    });
  },

  startSimilarWorker() {
    return singletonWorkerManager.startWorker('similarWorker', `ai${path.sep}similar${path.sep}similarWorker.js`, {
      env: {
        WORKER_TYPE: 'aiSimilar',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['similarWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ photo dedupe worker error:`, error);
      },
    });
  },

  async stopOcrWorker() {
    return singletonWorkerManager.stopWorker('ocrWorker');
  },

  async stopSimilarWorker() {
    return singletonWorkerManager.stopWorker('similarWorker');
  },

  async stopGpsSupplementWorker() {
    return singletonWorkerManager.stopWorker('gpsSupplementWorker');
  },

  async stopPhotoIndexWorker() {
    singletonWorkerManager.stopWorker('photoWatchWorker');
    singletonWorkerManager.stopWorker('photoIndexWorker');
    return;
  },

  async stopVideoIndexWorker() {
    singletonWorkerManager.stopWorker('videoWatchWorker');
    singletonWorkerManager.stopWorker('videoIndexWorker');
    return;
  },

  async stopBookIndexWorker() {
    singletonWorkerManager.stopWorker('bookWatchWorker');
    singletonWorkerManager.stopWorker('bookIndexWorker');
    return;
  },

  async stopMusicIndexWorker() {
    const [watchStopped, indexStopped] = await Promise.all([
      singletonWorkerManager.stopWorker('musicWatchWorker').catch(() => false),
      singletonWorkerManager.stopWorker('musicIndexWorker').catch(() => false),
    ]);
    return !!(watchStopped || indexStopped);
  },

  async stopFileAllIndexWorker() {
    return singletonWorkerManager.stopWorker('fileAllIndexWorker');
  },

  async stopFaceWorker() {
    return singletonWorkerManager.stopWorker('faceWorker');
  },

  async stopPlacesWorker() {
    return singletonWorkerManager.stopWorker('placesWorker');
  },

  isFaceWorkerRunning() {
    return singletonWorkerManager.isWorkerRunning('faceWorker');
  },

  isOcrWorkerRunning() {
    return singletonWorkerManager.isWorkerRunning('ocrWorker');
  },

  isPlacesWorkerRunning() {
    return singletonWorkerManager.isWorkerRunning('placesWorker');
  },

  isSimilarWorkerRunning() {
    return singletonWorkerManager.isWorkerRunning('similarWorker');
  },

  isGpsSupplementWorkerRunning() {
    return singletonWorkerManager.isWorkerRunning('gpsSupplementWorker');
  },

  startPhotoWatchWorker() {
    const worker = singletonWorkerManager.startWorker('photoWatchWorker', `photoIndex${path.sep}photoWatchWorker.js`, {
      env: {
        WORKER_TYPE: 'photoWatch',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['photoWatchWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ photo watch worker error:`, error);
      },
    });
    this.msgUtil.bindPhotoWatchWorker(worker);
    return worker;
  },

  startVideoWatchWorker() {
    const worker = singletonWorkerManager.startWorker('videoWatchWorker', `videoIndex${path.sep}videoWatchWorker.js`, {
      env: {
        WORKER_TYPE: 'videoWatch',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['videoWatchWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ video watch worker error:`, error);
      },
    });
    this.msgUtil.bindVideoWatchWorker(worker);
    return worker;
  },

  startBookWatchWorker() {
    const worker = singletonWorkerManager.startWorker('bookWatchWorker', `bookIndex${path.sep}bookWatchWorker.js`, {
      env: {
        WORKER_TYPE: 'bookWatch',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['bookWatchWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ book watch worker error:`, error);
      },
    });
    this.msgUtil.bindBookWatchWorker(worker);
    return worker;
  },

  startMusicWatchWorker() {
    const worker = singletonWorkerManager.startWorker('musicWatchWorker', `musicIndex${path.sep}musicWatchWorker.js`, {
      env: {
        WORKER_TYPE: 'musicWatch',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['musicWatchWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ music watch worker error:`, error);
      },
    });
    this.msgUtil.bindMusicWatchWorker(worker);
    return worker;
  },

  startFileAllIndexWorker() {
    const worker = singletonWorkerManager.startWorker('fileAllIndexWorker', `fileAllIndex${path.sep}fileAllIndexWorker.js`, {
      env: {
        WORKER_TYPE: 'fileAllIndex',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['fileAllIndexWorker'],
      onStart: () => {
        Logger.info(`🧭 full-disk index worker started`);
      },
      onStop: (code, signal) => {
        Logger.info(`🔚 full-disk index worker exited, code: ${code}, signal: ${signal}`);
      },
      onError: error => {
        if (error) Logger.error(`❌ full-disk index worker error:`, error);
      },
    });
    return worker;
  },

  resetPhotoWatchWorker() {
    const worker = this.startPhotoWatchWorker();
    if (worker && typeof worker.send === 'function') {
      try {
        worker.send({ type: 'reset' });
      } catch (_) {}
    }
  },

  resetVideoWatchWorker() {
    const worker = this.startVideoWatchWorker();
    if (worker && typeof worker.send === 'function') {
      try {
        worker.send({ type: 'reset' });
      } catch (_) {}
    }
  },

  resetBookWatchWorker() {
    const worker = this.startBookWatchWorker();
    if (worker && typeof worker.send === 'function') {
      try {
        worker.send({ type: 'reset' });
      } catch (_) {}
    }
  },

  resetMusicWatchWorker() {
    const worker = this.startMusicWatchWorker();
    if (worker && typeof worker.send === 'function') {
      try {
        worker.send({ type: 'reset' });
      } catch (_) {}
    }
  },

  startExpressBroadcastWorker(freePort, serverId) {
    singletonWorkerManager.startWorker('expressBroadcastWorker', 'expressBroadcastWorker.js', {
      env: {
        WORKER_TYPE: 'broadcast',
        WORKER_PORT: freePort,
        SERVER_ID: serverId,
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['expressBroadcastWorker'],
      onStart: worker => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
      },
    });
  },

  async stopExpressBroadcastWorker() {
    try {
      const stopped = await singletonWorkerManager.stopWorker('expressBroadcastWorker');
      return !!stopped;
    } catch (e) {
      Logger.error(`❌ stopExpressBroadcastWorker failed`, e);
      return false;
    }
  },

  startTinyImageWorker() {
    singletonWorkerManager.startWorker('tinyImageWorker', 'tinyImageWorker.js', {
      env: {
        WORKER_TYPE: 'tinyImage',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['tinyImageWorker'],
      onStart: () => {

      },
      onStop: (code, signal) => {

      },
      onError: error => {
        if (error) Logger.error(`❌ TinyImage Worker error:`, error);
      },
    });
  },

  startBackgroundTaskWorker(jwtSecret) {
    let bgWorker = singletonWorkerManager.startWorker('backgroundTaskWorker', 'backgroundTaskWorker.js', {
      env: {
        WORKER_TYPE: 'backgroundTask',
        JWT_SECRET: jwtSecret,
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['backgroundTaskWorker'],
      onStart: worker => {

      },
      onStop: (code, signal) => {
        Logger.info(`🔚 background task worker stopped, code: ${code}, signal: ${signal}`);
        try {
          const pid = bgWorker && bgWorker.pid ? Number(bgWorker.pid) : 0;
          if (pid > 0 && this._backgroundTaskWorkerPid === pid) {
            this._backgroundTaskWorkerPid = 0;
            this.backgroundTaskWorker = null;
          }
        } catch (_) {}
        try {
          if (this._hwMonitorIdleStopTimer) clearTimeout(this._hwMonitorIdleStopTimer);
        } catch (_) {}
        this._hwMonitorIdleStopTimer = null;
      },
      onError: error => {
        if (error) Logger.error(`❌ background task worker error:`, error);
      },
    });
    this.backgroundTaskWorker = bgWorker;
    if (!Array.isArray(this._hwMetricsWaiters)) this._hwMetricsWaiters = [];
    const bgPid = bgWorker && bgWorker.pid ? Number(bgWorker.pid) : 0;
    if (bgPid > 0 && this._backgroundTaskWorkerPid === bgPid) return;
    this._backgroundTaskWorkerPid = bgPid;
    bgWorker.on('message', message => {
      if (!message || !message.type) return;
      switch (message.type) {
        case 'hwMetrics': {
          const payload = message.data;
          this.hwMetricsCache = payload;
          const waiters = Array.isArray(this._hwMetricsWaiters) ? this._hwMetricsWaiters : [];
          this._hwMetricsWaiters = [];
          waiters.forEach(w => {
            try {
              if (w && w.timeoutId) clearTimeout(w.timeoutId);
            } catch (_) {}
            try {
              if (w && typeof w.resolve === 'function') w.resolve(payload);
            } catch (_) {}
          });
          break;
        }
      }
    });
  },

  startDockerTaskWorker() {
    return singletonWorkerManager.startWorker('dockerTaskWorker', 'dockerTaskWorker.js', {
      env: {
        WORKER_TYPE: 'dockerTask',
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      tags: ['dockerTaskWorker'],
      onStart: () => {
        Logger.info('🐳 Docker task worker started');
      },
      onStop: (code, signal) => {
        Logger.info(`🐳 Docker task worker stopped, code: ${code}, signal: ${signal}`);
      },
      onError: error => {
        if (error) Logger.error('❌ Docker task worker error:', error);
      },
    });
  },

  touchHwMetricsRequest() {
    this._hwMetricsLastRequestAt = Date.now();
    const idleMs = 30 * 1000;
    const bgWorker = this.backgroundTaskWorker;
    if (bgWorker && bgWorker.connected) {
      try {
        bgWorker.send({ type: 'hwMonitor:start' });
      } catch (_) {}
    }
    try {
      if (this._hwMonitorIdleStopTimer) clearTimeout(this._hwMonitorIdleStopTimer);
    } catch (_) {}
    this._hwMonitorIdleStopTimer = setTimeout(() => {
      const w = this.backgroundTaskWorker;
      if (w && w.connected) {
        try {
          w.send({ type: 'hwMonitor:stop' });
        } catch (_) {}
      }
    }, idleMs);
  },

  waitForNextHwMetrics(timeoutMs = 2000) {
    return new Promise((resolve, reject) => {
      const waiters = Array.isArray(this._hwMetricsWaiters) ? this._hwMetricsWaiters : [];
      const entry = { resolve: null, reject: null, timeoutId: null };
      entry.resolve = payload => resolve(payload);
      entry.reject = err => reject(err);
      entry.timeoutId = setTimeout(() => {
        try {
          this._hwMetricsWaiters = (Array.isArray(this._hwMetricsWaiters) ? this._hwMetricsWaiters : []).filter(w => w !== entry);
        } catch (_) {}
        try {
          entry.reject(new Error('waitForNextHwMetrics timeout'));
        } catch (_) {}
      }, timeoutMs);
      waiters.push(entry);
      this._hwMetricsWaiters = waiters;
    });
  },

  startP2pConnectWorker(serverId) {
    const sid = serverId == null ? '' : String(serverId);
    this._p2pConnectWorkerLastServerId = sid;
    try {
      if (this._p2pConnectRestartTimer) {
        clearTimeout(this._p2pConnectRestartTimer);
        this._p2pConnectRestartTimer = null;
      }
    } catch (_) {}
    const p2pWorker = singletonWorkerManager.startWorker('p2pConnectWorker', `p2pConnectWorker${path.sep}p2pConnectWorker.js`, {
      env: {
        WORKER_TYPE: 'p2pConnect',
        SERVER_ID: sid,
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      messageTypes: [],
      tags: ['p2pConnectWorker'],
      onStart: () => {
        Logger.info(`🔌 P2P Connect Worker started`);
      },
      onStop: (code, signal) => {
        Logger.info(`🔚 P2P Connect Worker exited, code: ${code}, signal: ${signal}`);
        try {
          const now = Date.now();
          const pid = p2pWorker && p2pWorker.pid ? Number(p2pWorker.pid) : 0;
          if (this._p2pConnectLastExitInfo && this._p2pConnectLastExitInfo.pid === pid && now - this._p2pConnectLastExitInfo.at < 1000) {
            return;
          }
          this._p2pConnectLastExitInfo = { pid, at: now };
        } catch (_) {}

        const codeNum = typeof code === 'number' ? code : Number(code);
        const codeValid = Number.isFinite(codeNum) ? codeNum : null;
        const signalStr = signal ? String(signal) : '';
        const abnormal = !!signalStr || (codeValid !== null && codeValid !== 0);
        if (!abnormal) return;

        if (this._p2pConnectRestartTimer) return;
        this._p2pConnectRestartTimer = setTimeout(() => {
          this._p2pConnectRestartTimer = null;
          Promise.resolve()
            .then(async () => {
              const enabled = await getP2pRemoteAccessEnabledSafe();
              if (!enabled) return;
              if (singletonWorkerManager.isWorkerRunning('p2pConnectWorker')) return;
              this.startP2pConnectWorker(this._p2pConnectWorkerLastServerId || sid);
            })
            .catch(e => {
              Logger.error(`❌ P2P Connect Worker auto-restart failed:`, e);
            });
        }, 5000);
      },
      onError: (error, signal) => {
        if (error) Logger.error(`❌ P2P Connect Worker error:`, error);
        const codeNum = typeof error === 'number' ? error : Number(error);
        const codeValid = Number.isFinite(codeNum) ? codeNum : null;
        const signalStr = signal ? String(signal) : '';
        const abnormal = !!signalStr || (codeValid !== null && codeValid !== 0);
        if (!abnormal) return;

        if (this._p2pConnectRestartTimer) return;
        this._p2pConnectRestartTimer = setTimeout(() => {
          this._p2pConnectRestartTimer = null;
          Promise.resolve()
            .then(async () => {
              const enabled = await getP2pRemoteAccessEnabledSafe();
              if (!enabled) return;
              if (singletonWorkerManager.isWorkerRunning('p2pConnectWorker')) return;
              this.startP2pConnectWorker(this._p2pConnectWorkerLastServerId || sid);
            })
            .catch(e => {
              Logger.error(`❌ P2P Connect Worker auto-restart failed:`, e);
            });
        }, 5000);
      },
      onMessage: message => {
        try {
          if (!message || message.type !== 'ipcProxy:http:req') return;
          const id = message.id == null ? '' : String(message.id);
          const data = message.data && typeof message.data === 'object' ? message.data : {};
          if (!id) return;

          const pool = Array.isArray(this.expressWorkers) ? this.expressWorkers : [];
          const live = pool.filter(w => w && typeof w.send === 'function' && typeof w.isConnected === 'function' && w.isConnected());
          if (!live.length) {
            try {
              p2pWorker.send({
                type: 'ipcProxy:http:res',
                id,
                data: { status: 503, headers: { 'content-type': 'application/json' }, bodyText: '{"code":-1,"message":"express_not_ready"}' },
              });
            } catch (_) {}
            return;
          }

          const cursor = Number.isFinite(this.expressWorkerCursor) ? this.expressWorkerCursor : 0;
          const picked = live[cursor % live.length];
          this.expressWorkerCursor = cursor + 1;

          const pending = this.p2pIpcProxyPending instanceof Map ? this.p2pIpcProxyPending : new Map();
          this.p2pIpcProxyPending = pending;
          pending.set(id, { worker: p2pWorker, ts: Date.now() });
          setTimeout(() => {
            const cur = pending.get(id);
            if (!cur) return;
            pending.delete(id);
            try {
              p2pWorker.send({
                type: 'ipcProxy:http:res',
                id,
                data: { status: 504, headers: { 'content-type': 'application/json' }, bodyText: '{"code":-1,"message":"proxy_timeout"}' },
              });
            } catch (_) {}
          }, 25000);

          picked.send({ type: 'ipcProxy:http:req', id, data });
        } catch (e) {
          Logger.error('❌ ipcProxy:http:req forward failed:', e);
        }
      },
    });
    return p2pWorker;
  },

  async stopP2pConnectWorker() {
    try {
      try {
        if (this._p2pConnectRestartTimer) {
          clearTimeout(this._p2pConnectRestartTimer);
          this._p2pConnectRestartTimer = null;
        }
      } catch (_) {}
      const stopped = await singletonWorkerManager.stopWorker('p2pConnectWorker');
      if (stopped) Logger.info(`🛑 P2P Connect Worker stopped`);
      return !!stopped;
    } catch (e) {
      Logger.error(`❌ stopP2pConnectWorker failed`, e);
      return false;
    }
  },

  startDdnsWorker(serverId) {
    const sid = serverId == null ? '' : String(serverId);
    this._ddnsWorkerLastServerId = sid;
    try {
      if (this._ddnsRestartTimer) {
        clearTimeout(this._ddnsRestartTimer);
        this._ddnsRestartTimer = null;
      }
    } catch (_) {}
    const ddnsWorker = singletonWorkerManager.startWorker('ddnsWorker', `ddnsWorker${path.sep}ddnsWorker.js`, {
      env: {
        WORKER_TYPE: 'ddns',
        SERVER_ID: sid,
        PATH_DATABASE: this.pathDatabase,
        PATH_CACHE: this.pathCache,
      },
      tags: ['ddnsWorker'],
      onStart: () => {
        Logger.info(`🌐 DDNS Worker started`);
      },
      onStop: (code, signal) => {
        Logger.info(`🔚 DDNS Worker exited, code: ${code}, signal: ${signal}`);
        const codeNum = typeof code === 'number' ? code : Number(code);
        const codeValid = Number.isFinite(codeNum) ? codeNum : null;
        const signalStr = signal ? String(signal) : '';
        const abnormal = !!signalStr || (codeValid !== null && codeValid !== 0);
        if (!abnormal) return;
        if (this._ddnsRestartTimer) return;
        this._ddnsRestartTimer = setTimeout(() => {
          this._ddnsRestartTimer = null;
          Promise.resolve()
            .then(async () => {
              const enabled = await getDdnsEnabledSafe();
              if (!enabled) return;
              if (singletonWorkerManager.isWorkerRunning('ddnsWorker')) return;
              this.startDdnsWorker(this._ddnsWorkerLastServerId || sid);
            })
            .catch(e => {
              Logger.error(`❌ DDNS Worker auto-restart failed:`, e);
            });
        }, 5000);
      },
      onError: (error, signal) => {
        if (error) Logger.error(`❌ DDNS Worker error:`, error);
        const codeNum = typeof error === 'number' ? error : Number(error);
        const codeValid = Number.isFinite(codeNum) ? codeNum : null;
        const signalStr = signal ? String(signal) : '';
        const abnormal = !!signalStr || (codeValid !== null && codeValid !== 0);
        if (!abnormal) return;
        if (this._ddnsRestartTimer) return;
        this._ddnsRestartTimer = setTimeout(() => {
          this._ddnsRestartTimer = null;
          Promise.resolve()
            .then(async () => {
              const enabled = await getDdnsEnabledSafe();
              if (!enabled) return;
              if (singletonWorkerManager.isWorkerRunning('ddnsWorker')) return;
              this.startDdnsWorker(this._ddnsWorkerLastServerId || sid);
            })
            .catch(e => {
              Logger.error(`❌ DDNS Worker auto-restart failed:`, e);
            });
        }, 5000);
      },
    });
    return ddnsWorker;
  },

  async stopDdnsWorker() {
    try {
      try {
        if (this._ddnsRestartTimer) {
          clearTimeout(this._ddnsRestartTimer);
          this._ddnsRestartTimer = null;
        }
      } catch (_) {}
      const stopped = await singletonWorkerManager.stopWorker('ddnsWorker');
      if (stopped) Logger.info(`🛑 DDNS Worker stopped`);
      return !!stopped;
    } catch (e) {
      Logger.error(`❌ stopDdnsWorker failed`, e);
      return false;
    }
  },
};
