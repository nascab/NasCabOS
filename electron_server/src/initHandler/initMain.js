const path = require('path');
const cluster = require('cluster');
const Logger = require('../utils/logger');
const hardwareUtil = require('../utils/hardwareUtil');
const dbUtil = require('../db/dbUtil');
const appUtil = require('../utils/appUtil');
const tableConfig = require('../db/table/tableConfig');
const config = require('../config/config');
let shell,app;

try {
  shell = require('electron').shell;
  app = require('electron').app;
} catch (e) {}

module.exports = {
  async init() {
    Logger.debug('🚀 初始化主进程');
    const remoteAssets = require('../utils/remoteAssetsManager');
    if (remoteAssets.shouldUseRemoteAssets()) {
      Logger.info('[remoteAssets] startup sync before AI workers');
      void remoteAssets.syncOnnxModelsAtStartup().catch(err => {
        Logger.warn('[remoteAssets] startup ONNX sync failed', {
          error: err && err.message ? err.message : String(err),
        });
      });
    }

    const sysInfo = hardwareUtil.getHardwareInfo();

    await dbUtil.init(true);

    this.startFfmpegHwTestWorker();
    this.startPhotoWatchWorker();
    this.startVideoWatchWorker();
    this.startBookWatchWorker();
    this.startMusicWatchWorker();
    const fileAllIndexEnable = await tableConfig.getConfigByKey('file_all_index_enabled');
    if (fileAllIndexEnable === '1') {
      this.startFileAllIndexWorker();
    }

    // 重置所有待处理文件操作为失败
    await this.resetPendingFileOperations();
    // 扫描所有源
    await this.enqueueStartupPhotoScanTasks();
    await this.enqueueStartupVideoScanTasks();
    await this.enqueueStartupBookScanTasks();
    await this.enqueueStartupMusicScanTasks();
    // 读取 GPU 优先设置（默认为开启），在启动 AI worker 前设置环境变量
    const aiGpuPrefer = await tableConfig.getConfigByKey('ai_gpu_prefer');
    process.env.AI_GPU_PREFER = aiGpuPrefer === '0' ? '0' : '1';

    // 启动OCR Worker 如果配置已开启
    const aiOcrEnable = await tableConfig.getConfigByKey('ai_ocr_enable');
    if (aiOcrEnable === '1') {
      this.startOcrWorker();
    }
    // 启动人脸检测 Worker 如果配置已开启
    const aiFaceEnable = await tableConfig.getConfigByKey('ai_face_enable');
    if (aiFaceEnable === '1') {
      this.startFaceWorker();
    }
    // 启动场景识别 Worker 如果配置已开启
    const aiPlaceEnable = await tableConfig.getConfigByKey('ai_place_enable');
    if (aiPlaceEnable === '1') {
      this.startPlacesWorker();
    }
    const aiSimilarEnable = await tableConfig.getConfigByKey('ai_similar_enable');
    if (aiSimilarEnable === '1') {
      this.startSimilarWorker();
    }
    // 检查是否支持 shell
    const isShellSupported = !!shell;

    // 保存shell支持状态到数据库
    tableConfig.setConfigByKey('shell_supported', isShellSupported ? '1' : '0');

    const serverId = await tableConfig.ensureServerId();
    const jwtSecret = await tableConfig.ensureJWTSecret();
    await tableConfig.ensureTwoFASecret();
    process.env.SERVER_ID = process.env.SERVER_ID || serverId;
    process.env.JWT_SECRET = process.env.JWT_SECRET || jwtSecret;
    Logger.info(`🎯 Server id: ${serverId}`);

    if (remoteAssets.shouldUseRemoteAssets()) {
      void remoteAssets
        .syncMountLibsAtStartup()
        .then(() => {
          Logger.info('[remoteAssets] mount libs ready, restoring mount/share');
          return Promise.all([
            this.restoreFileServersOnStartup({ serverId }),
            this.restoreFileMountsOnStartup({ serverId }),
            this.restoreOpenlistMountsOnStartup({ serverId }),
          ]);
        })
        .catch(err => {
          Logger.warn('[remoteAssets] mount libs sync or restore failed', {
            error: err && err.message ? err.message : String(err),
          });
        });
    } else {
      await this.restoreFileServersOnStartup({ serverId });
      setTimeout(() => {
        this.restoreFileMountsOnStartup({ serverId });
      }, 5000);
      setTimeout(() => {
        this.restoreOpenlistMountsOnStartup({ serverId });
      }, 6000);
    }

    await this.ensureInitialSuperAdmin();
    setTimeout(async () => {
      try {
        const info = await this.getInitialSuperAdminInfo();
        if ((info && info.isInitialAdmin && info.username && info.password)) {
          Logger.info(`Default admin in use; change soon. \nusername:${info.username} \npassword:${info.password}`);
        } 
        await this.writeLinuxHeadlessAdminAccountFileIfNeeded();
      } catch {}
    }, 10000);

    setTimeout(() => {
      this.reloadFileBackupsScheduler({ serverId, reconcileRunning: true });
    }, 7000);
    setTimeout(() => {
      this.restoreTransmissionOnStartup({ serverId });
    }, 8000);

    const forbidden = new Set((config && config.forbiddenPorts) || []);
    const desiredHttp = await appUtil.getConfigApiPort(false);
    const desiredHttps = await appUtil.getConfigApiPort(true);
    const safeDesiredHttp = forbidden.has(desiredHttp) ? config.app.port : desiredHttp;
    const safeDesiredHttps = forbidden.has(desiredHttps) ? config.app.httpsPort : desiredHttps;

    const getFreeAllowedPort = async (basePort, avoidPorts = new Set()) => {
      let cursor = basePort;
      while (true) {
        const p = await appUtil.getFreePort(cursor);
        if (!p) return null;
        if (forbidden.has(p) || avoidPorts.has(p)) {
          cursor = p + 1;
          continue;
        }
        return p;
      }
    };

    const freeHttpPort = await getFreeAllowedPort(safeDesiredHttp);
    const freeHttpsPort = await getFreeAllowedPort(safeDesiredHttps, new Set([freeHttpPort]));
    Logger.info('Free ports:', { http: freeHttpPort, https: freeHttpsPort });

    const cpuCores = sysInfo.cpu.cores;
    const rawApiCount = await tableConfig.getConfigByKey(tableConfig.KEY_EXPRESS_API_COUNT, 0);
    let expressApiCount = this.getExpressApiCount(cpuCores, rawApiCount);
    //开发模式固定为1
    if (process.env.NODE_ENV === 'development') {
      expressApiCount = 1;
    }
    //cluster专门用于启用多个express worker进程
    cluster.setupPrimary({
      exec: path.resolve(__dirname, '..', 'workers', 'expressWorker.js'),
    });
    for (let i = 0; i < expressApiCount; i++) {
      this.startOneExpressWorker(freeHttpPort, freeHttpsPort, serverId, jwtSecret);
    }
    Logger.info(`🎯 Started ${expressApiCount} NasCab OS API worker(s)`);
  },
};
