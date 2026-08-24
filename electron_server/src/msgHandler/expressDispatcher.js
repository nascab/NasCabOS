const expressLifecycle = require('./expressLifecycle');
const indexControl = require('./indexControl');
const fileServer = require('./fileServer');
const fileMount = require('./fileMount');
const openlist = require('./openlist');
const fileBackup = require('./fileBackup');
const imgBatchCompress = require('./imgBatchCompress');
const videoTrans = require('./videoTrans');
const audioTrans = require('./audioTrans');
const videoScrape = require('./videoScrape');
const aiToggle = require('./aiToggle');
const resetWatch = require('./resetWatch');
const downloadUrlToFile = require('./downloadUrlToFile');
const transcode = require('./transcode');
const subtitleVtt = require('./subtitleVtt');
const shell = require('./shell');
const encryptedSpaceExport = require('./encryptedSpaceExport');
const securityCenter = require('./securityCenter');
const mediaArrange = require('./mediaArrange');
const fileAllIndexControl = require('./fileAllIndexControl');
const processMonitor = require('./processMonitor');
const terminalSessions = require('./terminalSessions');
const dockerTasks = require('./dockerTasks');
const transmission = require('./transmission');

const handlers = {
  ...expressLifecycle,
  ...indexControl,
  ...fileServer,
  ...fileMount,
  ...openlist,
  ...fileBackup,
  ...imgBatchCompress,
  ...videoTrans,
  ...audioTrans,
  ...videoScrape,
  ...aiToggle,
  ...resetWatch,
  ...downloadUrlToFile,
  ...transcode,
  ...subtitleVtt,
  ...shell,
  ...encryptedSpaceExport,
  ...securityCenter,
  ...mediaArrange,
  ...fileAllIndexControl,
  ...processMonitor,
  ...terminalSessions.handlers,
  ...dockerTasks,
  ...transmission,
};

function dispatchExpressMessage(ctx) {
  const type = ctx && ctx.message ? ctx.message.type : '';
  if (!type) return;
  const handler = handlers[type];
  if (typeof handler !== 'function') {
    if (/filemount|FileMount/i.test(type) && ctx && ctx.Logger) {
      try {
        ctx.Logger.warn('[expressDispatcher] 未注册的消息类型（fileMount 相关）', { type });
      } catch (_) {}
    }
    return;
  }
  handler(ctx);
}

module.exports = dispatchExpressMessage;
