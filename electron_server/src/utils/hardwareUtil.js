const os = require('os');
const Logger = require('./logger');
/**
 * 硬件信息工具类
 * 提供获取CPU、内存等硬件信息的功能
 */
class HardwareUtil {
  constructor() {
    this.init();
  }

  /**
   * 初始化硬件信息工具
   */
  init() {

  }

  /**
   * 获取CPU核心数量
   * @returns {number} CPU核心数量
   */
  getCPUCores() {
    try {
      const cores = os.cpus().length;

      return cores;
    } catch (err) {
      Logger.error('❌ CPU core count failed', err);
      return 0;
    }
  }

  /**
   * 获取CPU详细信息
   * @returns {Object} CPU信息对象
   */
  getCPUInfo() {
    try {
      const cpus = os.cpus();
      const cpuInfo = {
        cores: cpus.length,
        model: cpus[0]?.model || 'Unknown',
        speed: cpus[0]?.speed || 0,
        architecture: os.arch(),
      };


      return cpuInfo;
    } catch (err) {
      Logger.error('❌ CPU info failed', err);
      return {
        cores: 0,
        model: 'Unknown',
        speed: 0,
        architecture: 'Unknown',
      };
    }
  }

  /**
   * 获取内存大小（字节）
   * @returns {number} 总内存大小（字节）
   */
  getTotalMemory() {
    try {
      const totalMemory = os.totalmem();

      return totalMemory;
    } catch (err) {
      Logger.error('❌ Total memory query failed', err);
      return 0;
    }
  }

  /**
   * 获取可用内存大小（字节）
   * @returns {number} 可用内存大小（字节）
   */
  getFreeMemory() {
    try {
      const freeMemory = os.freemem();

      return freeMemory;
    } catch (err) {
      Logger.error('❌ Free memory query failed', err);
      return 0;
    }
  }

  /**
   * 获取内存使用率
   * @returns {number} 内存使用率（0-100）
   */
  getMemoryUsage() {
    try {
      const totalMemory = os.totalmem();
      const freeMemory = os.freemem();
      const usedMemory = totalMemory - freeMemory;
      const usagePercentage = (usedMemory / totalMemory) * 100;


      return usagePercentage;
    } catch (err) {
      Logger.error('❌ Memory usage query failed', err);
      return 0;
    }
  }

  /**
   * 获取完整的硬件信息
   * @returns {Object} 完整的硬件信息对象
   */
  getHardwareInfo() {
    try {
      const hardwareInfo = {
        platform: os.platform(),
        release: os.release(),
        architecture: os.arch(),
        cpu: this.getCPUInfo(),
        memory: {
          total: this.getTotalMemory(),
          free: this.getFreeMemory(),
          usage: this.getMemoryUsage(),
          formatted: {
            total: this.formatBytes(this.getTotalMemory()),
            free: this.formatBytes(this.getFreeMemory()),
            usage: `${this.getMemoryUsage().toFixed(2)}%`,
          },
        },
        hostname: os.hostname(),
        uptime: os.uptime(),
        networkInterfaces: os.networkInterfaces(),
      };


      return hardwareInfo;
    } catch (err) {
      Logger.error('❌ Full hardware info failed', err);
      return {
        platform: 'Unknown',
        release: 'Unknown',
        architecture: 'Unknown',
        cpu: { cores: 0, model: 'Unknown', speed: 0 },
        memory: { total: 0, free: 0, usage: 0 },
        hostname: 'Unknown',
        uptime: 0,
      };
    }
  }

  /**
   * 检查系统是否满足最低硬件要求
   * @param {Object} requirements - 硬件要求配置
   * @returns {Object} 检查结果
   */
  checkSystemRequirements(requirements = {}) {
    const defaultRequirements = {
      minCores: 2,
      minMemory: 2 * 1024 * 1024 * 1024, // 2GB
      minFreeMemory: 512 * 1024 * 1024, // 512MB
      maxMemoryUsage: 90, // 90%
    };

    const req = { ...defaultRequirements, ...requirements };
    const hardwareInfo = this.getHardwareInfo();

    const result = {
      meetsRequirements: true,
      details: {
        cpu: {
          required: req.minCores,
          actual: hardwareInfo.cpu.cores,
          meets: hardwareInfo.cpu.cores >= req.minCores,
        },
        memory: {
          required: this.formatBytes(req.minMemory),
          actual: this.formatBytes(hardwareInfo.memory.total),
          meets: hardwareInfo.memory.total >= req.minMemory,
        },
        freeMemory: {
          required: this.formatBytes(req.minFreeMemory),
          actual: this.formatBytes(hardwareInfo.memory.free),
          meets: hardwareInfo.memory.free >= req.minFreeMemory,
        },
        memoryUsage: {
          maxAllowed: req.maxMemoryUsage + '%',
          actual: hardwareInfo.memory.usage.toFixed(2) + '%',
          meets: hardwareInfo.memory.usage <= req.maxMemoryUsage,
        },
      },
    };

    // 检查所有要求是否满足
    result.meetsRequirements = Object.values(result.details).every(detail => detail.meets);

    if (result.meetsRequirements) {

    } else {
      warn('⚠️ 系统不满足硬件要求', result.details);
    }

    return result;
  }
  /**
   * 格式化字节大小为易读格式
   * @param {number} bytes - 字节数
   * @returns {string} 格式化后的字符串
   */
  formatBytes(bytes, isDisk = false) {
    let useUnit = 1024;
    if (os.platform() === 'darwin' && isDisk) {
      useUnit = 1000;
    }
    if (bytes === null || bytes === undefined || isNaN(bytes) || bytes === 0) return '0 B';

    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(useUnit));

    if (i === 0) {
      return `${bytes} B`;
    } else {
      return `${parseFloat((bytes / Math.pow(useUnit, i)).toFixed(1))} ${sizes[i]}`;
    }
  }
}

// 创建单例实例
const hardwareUtil = new HardwareUtil();
// 导出单例实例
module.exports = hardwareUtil;
