const os = require('os');

function pickLanIps() {
  const ifaces = os.networkInterfaces();
  const ips = [];
  for (const name of Object.keys(ifaces || {})) {
    const addrs = ifaces[name] || [];
    for (const addr of addrs) {
      if (!addr || addr.family !== 'IPv4' || addr.internal) continue;
      const ip = String(addr.address || '');
      if (!ip) continue;
      ips.push(ip);
    }
  }
  return Array.from(new Set(ips));
}

function buildDeviceInfo(serverId) {
  const hostname = os.hostname ? os.hostname() : '';
  return {
    serverId,
    hostname,
    deviceName: hostname,
    platform: `${os.platform()}-${os.arch()}`,
    osPlatform: os.platform(),
    osRelease: os.release(),
    osArch: os.arch(),
    lanIps: pickLanIps(),
    ts: Date.now(),
  };
}

module.exports = { buildDeviceInfo };
