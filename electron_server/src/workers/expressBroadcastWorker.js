'use strict';
const dgram = require('dgram');
const os = require('os');
const Logger = require('../utils/logger');
const packageInfo = require('../../package.json');
class ExpressBroadcastWorker {
  constructor() {
    this.broadcastInterval = null;
    this.isRunning = false;
    this.expressPort = null;
    this.targetBroadcastPort = 8888; // Flutter客户端监听的目标端口
    this.broadcastIntervalMs = 5000; // 5秒广播一次
    this.serviceName = 'nascab-pro-service';
    this.broadcastCount = 0;
    this.init();
  }

  init() {
    // 获取环境变量中的Express端口
    this.expressPort = parseInt(process.env.WORKER_PORT);
    // 启动广播服务
    this.startBroadcast();
  }
  /**
   * 获取本机局域网IP地址
   */
  getLocalIP() {
    const interfaces = os.networkInterfaces();
    for (const interfaceName in interfaces) {
      const addresses = interfaces[interfaceName];
      for (const address of addresses) {
        // 跳过内部和IPv6地址
        if (address.family === 'IPv4' && !address.internal) {
          return address.address;
        }
      }
    }
    return '127.0.0.1';
  }

  /**
   * 获取广播地址
   */
  getBroadcastAddress() {
    const interfaces = os.networkInterfaces();
    for (const interfaceName in interfaces) {
      const addresses = interfaces[interfaceName];
      for (const address of addresses) {
        if (address.family === 'IPv4' && !address.internal) {
          // 计算广播地址（假设子网掩码为255.255.255.0）
          const ipParts = address.address.split('.');
          return `${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.255`;
        }
      }
    }
    return '255.255.255.255'; // 全网广播
  }

  /**
   * 创建广播消息
   */
  createBroadcastMessage() {
    const localIP = this.getLocalIP();
    const hostname = os.hostname();
    const timestamp = new Date().toISOString();
    const platform = os.platform();
    return JSON.stringify({
      service: this.serviceName,
      version: packageInfo.version,
      host: localIP,
      hostname: hostname,
      port: this.expressPort,
      timestamp: timestamp,
      platform: platform,
      serverId: process.env.SERVER_ID,
    });
  }

  /**
   * 启动广播服务
   */
  startBroadcast() {
    try {
      this.isRunning = true;


      // 发送启动成功消息给主进程
      process.send({
        type: 'broadcastWorkerStarted',
        data: {
          expressPort: this.expressPort,
          targetBroadcastPort: this.targetBroadcastPort,
        },
      });

      // 启动定时广播
      this.startBroadcastInterval();

      // 优雅关闭处理
      this.setupGracefulShutdown();
    } catch (err) {
      Logger.error(`❌ NasCabOSAPI broadcast worker start error:`, err);
      this.isRunning = false;
    }
  }

  /**
   * 启动定时广播
   */
  startBroadcastInterval() {
    if (this.broadcastInterval) {
      clearInterval(this.broadcastInterval);
    }

    this.broadcastInterval = setInterval(() => {
      this.broadcastServiceInfo();
    }, this.broadcastIntervalMs);

    // 立即广播一次
    this.broadcastServiceInfo();
  }

  /**
   * 启动定时广播
   */
  startBroadcastInterval() {
    if (this.broadcastInterval) {
      clearInterval(this.broadcastInterval);
    }

    this.broadcastInterval = setInterval(() => {
      this.broadcastServiceInfo();
    }, this.broadcastIntervalMs);

    // 立即广播一次
    this.broadcastServiceInfo();
  }

  /**
   * 广播服务信息
   */
  broadcastServiceInfo() {
    if (!this.isRunning) {
      return;
    }

    try {
      const message = this.createBroadcastMessage();
      const broadcastAddress = this.getBroadcastAddress();

      // 创建新的UDP socket（不绑定固定端口）
      const socket = dgram.createSocket('udp4');

      socket.on('error', err => {
        Logger.error(`❌ UDP broadcast socket error:`, err);
        socket.close();
      });

      // 绑定到端口0（系统自动分配）
      socket.bind(0, () => {
        // 设置广播选项
        socket.setBroadcast(true);

        // 发送广播消息
        socket.send(message, this.targetBroadcastPort, broadcastAddress, err => {
          if (err) {
            Logger.error(`❌ UDP broadcast send failed:`, err);
          } else {
            this.broadcastCount++;

          }
          // 发送完成后关闭socket
          socket.close();
        });
      });
    } catch (err) {
      Logger.error(`❌ broadcast service error:`, err);
    }
  }

  /**
   * 停止广播
   */
  stopBroadcast() {
    if (this.broadcastInterval) {
      clearInterval(this.broadcastInterval);
      this.broadcastInterval = null;
    }

    this.isRunning = false;
    Logger.info(`🛑 NasCabOSAPI broadcast worker stopped`);

    // 发送停止消息
    process.send({ type: 'broadcastWorkerStopped' });
  }

  /**
   * 优雅关闭处理
   */
  setupGracefulShutdown() {
    const gracefulShutdown = signal => {
      Logger.info(`📡 Received ${signal}, shutting down broadcast worker ...`);
      this.stopBroadcast();
    };

    // 注册信号处理
    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));

    // uncaughtException处理
    process.on('uncaughtException', err => {
      Logger.error('❌ Uncaught exception:', err);
      gracefulShutdown('uncaughtException');
    });

    process.on('unhandledRejection', (reason, promise) => {
      Logger.error('❌ Unhandled rejection:', reason);
      gracefulShutdown('unhandledRejection');
    });
  }
}
if (require.main === module) {
  new ExpressBroadcastWorker();
}

module.exports = ExpressBroadcastWorker;
