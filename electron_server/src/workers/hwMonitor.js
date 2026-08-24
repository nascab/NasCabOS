const si = require('systeminformation');
const Logger = require('../utils/logger');
const os = require('os');
const hwUtil = require('../utils/hardwareUtil');
class HardwareMonitor {
  constructor() {
    this.sampleIntervalMs = 3000;
    this.diskIntervalMs = 10 * 60 * 1000;
    this.lastDiskStats = { usage: [], physical: [] };
    this.sampleTimer = null;
    this.diskTimer = null;
    this.cpuInfo = null;
    this.mem = null;
    this.graphics = null;
    this.lastNetworkStats = { rx_bytes: 0, tx_bytes: 0, timestamp: Date.now() }; // 新增：保存上一次的网络统计
  }

  formatNum(num) {
    if (num === null || num === undefined || isNaN(num)) return 0;
    return parseFloat(Number(num).toFixed(1));
  }

  normalizeTemperature(value) {
    if (value === null || value === undefined || value === '') return null;
    const num = Number(value);
    if (!Number.isFinite(num) || num <= 0) return null;
    return parseFloat(num.toFixed(1));
  }

  collectTemperatureSamples(cpuTemp) {
    if (!cpuTemp || typeof cpuTemp !== 'object') return [];

    const orderedSamples = [cpuTemp.main, cpuTemp.max, cpuTemp.socket];
    if (Array.isArray(cpuTemp.cores)) {
      orderedSamples.push(...cpuTemp.cores);
    }

    return orderedSamples
      .map(value => this.normalizeTemperature(value))
      .filter(value => value !== null);
  }

  // 新增：网络速度单位转换函数
  formatNetworkSpeed(bytesPerSec) {
    if (bytesPerSec === null || bytesPerSec === undefined || isNaN(bytesPerSec)) return '0 KB/s';

    const kbPerSec = bytesPerSec / 1024; // 转换为KB/s

    if (kbPerSec < 100) {
      // 小于100KB/s，保留一位小数
      return `${parseFloat(kbPerSec.toFixed(1))} KB/s`;
    } else {
      // 大于等于100KB/s，转换为MB/s，保留一位小数
      let mbPerSec = kbPerSec / 1024;
      if (mbPerSec > 100) {
        mbPerSec = 0;
      }
      return `${parseFloat(mbPerSec.toFixed(1))} MB/s`;
    }
  }

  // 新增：计算3秒内的平均网络速度
  calculateNetworkSpeed(currentStats) {
    const now = Date.now();
    const timeDiff = (now - this.lastNetworkStats.timestamp) / 1000; // 转换为秒

    if (timeDiff <= 0) {
      return {
        downloadSpeed: '0 KB/s',
        uploadSpeed: '0 KB/s',
        downloadBytesPerSec: 0,
        uploadBytesPerSec: 0,
      };
    }

    // 计算3秒内的平均速度（字节/秒）
    const downloadBytesPerSec = (currentStats.rx_bytes - this.lastNetworkStats.rx_bytes) / timeDiff;
    const uploadBytesPerSec = (currentStats.tx_bytes - this.lastNetworkStats.tx_bytes) / timeDiff;

    // 格式化速度
    const downloadSpeed = this.formatNetworkSpeed(downloadBytesPerSec);
    const uploadSpeed = this.formatNetworkSpeed(uploadBytesPerSec);

    // 更新上一次的网络统计
    this.lastNetworkStats = {
      rx_bytes: currentStats.rx_bytes,
      tx_bytes: currentStats.tx_bytes,
      timestamp: now,
    };

    return {
      downloadSpeed,
      uploadSpeed,
      downloadBytesPerSec: this.formatNum(downloadBytesPerSec),
      uploadBytesPerSec: this.formatNum(uploadBytesPerSec),
    };
  }

  start() {
    this.stop();
    this.collectDiskMetrics();
    this.collectFastMetrics();
    this.sampleTimer = setInterval(() => this.collectFastMetrics(), this.sampleIntervalMs);
    this.diskTimer = setInterval(() => this.collectDiskMetrics(), this.diskIntervalMs);

  }

  async collectOnce() {
    this.stop();
    await this.collectDiskMetrics();
    await this.collectFastMetrics();
  }

  stop() {
    try {
      if (this.sampleTimer != null) clearInterval(this.sampleTimer);
    } catch (_) {}
    try {
      if (this.diskTimer != null) clearInterval(this.diskTimer);
    } catch (_) {}
    this.sampleTimer = null;
    this.diskTimer = null;
    this.lastNetworkStats = { rx_bytes: 0, tx_bytes: 0, timestamp: Date.now() };
  }

  async collectFastMetrics() {
    try {
      const [load, cpuTemp, netStats] = await Promise.all([si.currentLoad(), si.cpuTemperature(), si.networkStats().catch(() => [])]);
      if (this.cpuInfo === null) {
        this.cpuInfo = await si.cpu().catch(() => ({ controllers: [] }));
      }
      if (this.mem === null) {
        this.mem = await si.mem().catch(() => ({ controllers: [] }));
      }
      if (this.graphics === null) {
        this.graphics = await si.graphics().catch(() => ({ controllers: [] }));
      }
      let useCpuInfo = this.cpuInfo
        ? {
            manufacturer: this.cpuInfo.manufacturer || null,
            brand: this.cpuInfo.brand || null,
            speed: this.formatNum(this.cpuInfo.speed || null),
            performanceCores: this.cpuInfo.performanceCores || null,
            efficiencyCores: this.cpuInfo.efficiencyCores || null,
            cores: this.cpuInfo.cores || null,
          }
        : null;

      const gpuInfos = (this.graphics.controllers || []).map(g => ({
        vendor: g.vendor || null,
        model: g.model || null,
        vramTotal: g.vramTotal || g.memoryTotal || null,
        vramUtilization: this.formatNum(g.vramUtilization || g.utilizationMemory || g.memoryUtilization),
        utilizationGpu: this.formatNum(g.utilizationGpu || g.gpuUtilization),
        temperature: this.formatNum(g.temperatureGpu || g.temperature),
      }));

      // Calculate total GPU usage (average of all active GPUs)
      let totalGpuLoad = 0;
      let gpuCount = 0;
      gpuInfos.forEach(g => {
        if (g.utilizationGpu !== null && g.utilizationGpu !== undefined) {
          totalGpuLoad += g.utilizationGpu;
          gpuCount++;
        }
      });
      const avgGpuLoad = gpuCount > 0 ? this.formatNum(totalGpuLoad / gpuCount) : 0;

      // 简化网络信息处理
      const networkInterfaces = Array.isArray(netStats)
        ? netStats.map(n => ({
            iface: n.iface,
            operstate: n.operstate,
            rx_bytes: n.rx_bytes,
            tx_bytes: n.tx_bytes,
          }))
        : [];

      // 计算总的上传和下载字节数
      const currentNetworkStats = networkInterfaces.reduce(
        (acc, n) => ({
          rx_bytes: acc.rx_bytes + (n.rx_bytes || 0),
          tx_bytes: acc.tx_bytes + (n.tx_bytes || 0),
        }),
        { rx_bytes: 0, tx_bytes: 0 }
      );

      // 计算3秒内的平均网络速度
      const networkSpeed = this.calculateNetworkSpeed(currentNetworkStats);

      const cpuTemperatureSamples = this.collectTemperatureSamples(cpuTemp);
      const cpuTemperature = cpuTemperatureSamples.length > 0 ? cpuTemperatureSamples[0] : null;
      const cpuTemperatureMax = cpuTemperatureSamples.length > 0 ? Math.max(...cpuTemperatureSamples) : null;

      // 格式化内存信息
      const memoryInfo = {
        total: this.mem.total,
        used: this.mem.used,
        free: this.mem.free,
        available: this.mem.available,
        usage: this.formatNum(this.mem.total ? (this.mem.used / this.mem.total) * 100 : 0),
        // 新增：格式化后的容量
        totalFormatted: hwUtil.formatBytes(this.mem.total),
        usedFormatted: hwUtil.formatBytes(this.mem.used),
        freeFormatted: hwUtil.formatBytes(this.mem.free),
        availableFormatted: hwUtil.formatBytes(this.mem.available),
      };
      const payload = {
        timestamp: Date.now(),
        cpuInfo: useCpuInfo || null,
        cpu: {
          usage: this.formatNum(load.currentLoad),
          avgLoad: load.avgLoad || null,
          // cpus: load.cpus || [],
          temperature: cpuTemperature,
          temperatureMax: cpuTemperatureMax,
          coreTemperatures: cpuTemperatureSamples,
        },
        gpu: {
          controllers: gpuInfos,
          usage: avgGpuLoad,
        },
        memory: memoryInfo,
        network: networkSpeed,
        disks: this.lastDiskStats,
      };
      process.send({ type: 'hwMetrics', data: payload });
    } catch (error) {
      Logger.error('❌ Quick hardware metrics failed', error);
    }
  }

  async collectDiskMetrics() {
    try {
      const fsSizes = await si.fsSize().catch(() => []);
      let useSize = [];
      //根据平台处理
      if (os.platform() == 'darwin') {
        for (let fs of fsSizes) {
          // 过滤出根目录的磁盘指标
          if (fs.mount == '/') {
            useSize.push(fs);
          }
        }
        if (useSize.length == 0) {
          useSize = fsSizes.length > 0 ? [fsSizes[0]] : [];
        }
      } else {
        useSize = fsSizes;
      }

      const usage = useSize.map(fs => ({
        fs: fs.fs || fs.mount || null,
        type: fs.type || null,
        available: fs.available || null,
        mount: fs.mount || null,
        // 新增：格式化后的容量
        sizeFormatted: hwUtil.formatBytes(fs.size || 0, true),
        availableFormatted: fs.available ? hwUtil.formatBytes(fs.available, true) : '0 B',
      }));

      this.lastDiskStats = {
        usage,
      };
      // Logger.debug('🧮 更新磁盘指标');
    } catch (error) {
      Logger.error('❌ Disk metrics failed', error);
    }
  }
}

module.exports = HardwareMonitor;
