// 主动推送模块（中文注释）：定时向渲染进程发送服务状态与最近日志
const NetUtil = require('../utils/netUtil');
const { getSnapshotDatabaseTotalBytes } = require('../utils/databaseDirUiUtil');

function start(window, getExpressState, Logger) {
  const timers = [];
  let lastSeq = 0;
  function pushStatus() {
    const { expressStarted, expressHttpPort, expressHttpsPort } = getExpressState();
    const ips = NetUtil.getIPv4Addresses();
    const httpAddresses = expressHttpPort ? ips.map(ip => `http://${ip}:${expressHttpPort}`) : [];
    const httpsAddresses = expressHttpsPort ? ips.map(ip => `https://${ip}:${expressHttpsPort}`) : [];
    if (!window.isDestroyed()) {
      window.webContents.send('service:status', {
        ipAddresses: ips,
        expressStarted,
        httpPort: expressHttpPort,
        httpAddresses,
        httpsPort: expressHttpsPort,
        httpsAddresses,
        databaseDir: process.env.PATH_DATABASE || '',
        cacheDir: process.env.PATH_CACHE || '',
        databaseTotalBytes: getSnapshotDatabaseTotalBytes(),
      });
    }
  }
  pushStatus();
  // 每秒推送网络状态与Express端口数据库目录等
  timers.push(
    setInterval(() => {
      pushStatus();
    }, 5000)
  );

  // 每秒推送最近日志缓冲（过滤debug，并限制条数）
  timers.push(
    setInterval(() => {
      const newLogs = (Logger.getRecentAfter(lastSeq) || []).filter(l => l.level !== 'debug');
      if (newLogs.length > 0 && !window.isDestroyed()) {
        lastSeq = newLogs[newLogs.length - 1].seq || lastSeq;
        const sliced = newLogs.slice(-200);
        window.webContents.send('logs:recent', sliced);
      }
    }, 5000)
  );

  function stop() {
    timers.forEach(t => clearInterval(t));
  }
  // 供主进程在 API 启动成功时立即推送一次，确保界面及时刷新
  function pushStatusNow() {
    if (!window.isDestroyed()) pushStatus();
  }
  return { stop, pushStatusNow };
}

module.exports = { start };
