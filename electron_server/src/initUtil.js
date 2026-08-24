let shell;
try {
  shell = require('electron').shell;
} catch (e) {}

const config = require('./config/config');
const databaseDir = config.getDatabasePath(); //数据库目录
const cacheDir = config.getCachePath(); //缓存目录
process.env.PATH_DATABASE = process.env.PATH_DATABASE || databaseDir;
process.env.PATH_CACHE = process.env.PATH_CACHE || cacheDir;
process.env.userDataFolder = process.env.userDataFolder || config.getUserDataPath();

const Logger = require('./utils/logger');
const { getSingletonWorkerManager } = require('./workers/singletonWorkerManager');
const { getProcessRegistry } = require('./workers/processRegistry');
const InitMsgUtil = require('./initMsgUtil');

const singletonWorkerManager = getSingletonWorkerManager();

class InitUtil {
  constructor() {
    this.expressStarted = false;
    this.expressHttpPort = null;
    this.expressHttpsPort = null;
    this.expressWorkers = [];
    this.expressWorkerCursor = 0;
    this.p2pIpcProxyPending = new Map();
    this.hwMetricsCache = null;
    this.pathDatabase = process.env.PATH_DATABASE;
    this.pathCache = process.env.PATH_CACHE;
    this.mainWindow = null;
    this.tray = null;
    this.trayQuitRequested = false;
    /** 当 API 进程启动成功时由 pushUpdater 注册，用于立即推送 service:status 到前端 */
    this._onExpressStartedCallback = null;
    this.msgUtil = new InitMsgUtil({
      initUtil: this,
      singletonWorkerManager,
      Logger,
      shell,
    });
  }

  getExpressApiCount(cpuCores, configuredCount) {
    const cores = parseInt(cpuCores, 10);
    const max = Math.max(2, Number.isFinite(cores) ? cores : 0);
    const raw = parseInt(configuredCount, 10);
    const desired = Number.isFinite(raw) ? raw : 2;
    return Math.max(2, Math.min(max, desired));
  }

  getExpressStatus() {
    return {
      expressStarted: this.expressStarted,
      expressHttpPort: this.expressHttpPort,
      expressHttpsPort: this.expressHttpsPort,
    };
  }

  setOnExpressStartedCallback(cb) {
    this._onExpressStartedCallback = typeof cb === 'function' ? cb : null;
  }

  notifyExpressStarted() {
    if (this._onExpressStartedCallback) this._onExpressStartedCallback();
  }

  getProcessList() {
    return getProcessRegistry().getProcessList();
  }
}

Object.assign(InitUtil.prototype, require('./initHandler/initialSuperAdmin'));
Object.assign(InitUtil.prototype, require('./initHandler/initMain'));
Object.assign(InitUtil.prototype, require('./initHandler/scanTasks'));
Object.assign(InitUtil.prototype, require('./initHandler/fileOperations'));
Object.assign(InitUtil.prototype, require('./initHandler/fileServer'));
Object.assign(InitUtil.prototype, require('./initHandler/fileMount'));
Object.assign(InitUtil.prototype, require('./initHandler/openlistMount'));
Object.assign(InitUtil.prototype, require('./initHandler/fileBackup'));
Object.assign(InitUtil.prototype, require('./initHandler/transmission'));
Object.assign(InitUtil.prototype, require('./initHandler/workers'));
Object.assign(InitUtil.prototype, require('./initHandler/tray'));

const initUtil = new InitUtil();
module.exports = initUtil;
