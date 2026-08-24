'use strict';
const app = require('../api/app');
const Logger = require('../utils/logger');
const https = require('https');
const fs = require('fs');
const config = require('../config/config');
const certUtil = require('../utils/certUtil');
const { getSingletonWorkerManager } = require('./singletonWorkerManager');
class ExpressWorker {
  constructor() {
    this.app = app;
    this.server = null;
    this.httpsServer = null;
    this.port = null;
    this.httpsPort = null;
    this.isRunning = false;
    this.httpsRunning = false;
    this._gracefulShutdownSetup = false;
    this._handleHttpError = this._handleHttpError.bind(this);
    this._handleHttpsError = this._handleHttpsError.bind(this);
    this.init();
  }

  init() {
    // 获取环境变量中的端口和配置
    this.port = parseInt(process.env.WORKER_PORT) || config.app.port;
    this.httpsPort = parseInt(process.env.WORKER_HTTPS_PORT) || config.app.httpsPort;

    this.setupGracefulShutdown();

    // 启动服务器
    this.startServer();
  }
  async startServer() {
    try {
      // 启动HTTP服务器
      this.server = app.listen(this.port, async () => {
        this.isRunning = true;
        Logger.info(`✅ HTTP server listening on port: ${this.port}`);

        // 立即通知主进程 API 已就绪（不依赖 HTTPS），打包后若证书路径异常导致 HTTPS 失败，界面与后台 Worker 仍能正常
        if (typeof process.send === 'function') {
          process.send({
            type: 'expressStarted',
            data: {
              httpPort: this.port,
              httpsPort: this.httpsPort,
            },
          });
        }
        // HTTP服务器启动成功后尝试启动HTTPS服务器
        this.startHttpsServer();
      });

      if (this.server && typeof this.server.removeListener === 'function') {
        this.server.removeListener('error', this._handleHttpError);
      }
      if (this.server) {
        this.server.on('error', this._handleHttpError);
      }
    } catch (err) {
      Logger.error(`❌ HTTP server start exception:`, err);
      this.isRunning = false;
    }
  }

  _handleHttpError(err) {
    Logger.error(`❌ HTTP server start failed:`, err && err.message ? err.message : err);
    this.isRunning = false;

    if (err && err.code === 'EADDRINUSE') {
      Logger.error(`HTTP port ${this.port} in use, trying fallback`);
      this.port = this.port + 1;
      this.startServer();
      return;
    }

    if (typeof process.send === 'function') {
      process.send({ type: 'expressEnded', data: { port: this.port } });
    }
  }

  // 启动HTTPS服务器
  startHttpsServer() {
    try {
      // 确保证书存在（首次启动自动生成自签名证书）
      const { keyPath, certPath } = certUtil.ensureCert();
      const options = {
        key: fs.readFileSync(keyPath),
        cert: fs.readFileSync(certPath),
      };

      // 创建HTTPS服务器
      this.httpsServer = https.createServer(options, this.app);
      this._attachHttpsUpgradeToExistingWss();

      this.httpsServer.listen(this.httpsPort, async () => {
        this.httpsRunning = true;
        Logger.info(`🔒 HTTPS server listening on port: ${this.httpsPort}`);

        // 仅更新主进程的 HTTPS 端口（expressStarted 已在 HTTP 启动时发送）
        if (typeof process.send === 'function') {
          process.send({
            type: 'expressStartedHttps',
            data: { httpsPort: this.httpsPort },
          });
        }
      });

      if (this.httpsServer && typeof this.httpsServer.removeListener === 'function') {
        this.httpsServer.removeListener('error', this._handleHttpsError);
      }
      if (this.httpsServer) {
        this.httpsServer.on('error', this._handleHttpsError);
      }
    } catch (err) {
      Logger.error(`❌ HTTPS server start exception:`, err);
      this.httpsRunning = false;
      Logger.info(`⚠️  HTTPS unavailable, HTTP only`);
    }
  }

  _handleHttpsError(err) {
    Logger.error(`❌ HTTPS server start failed:`, err && err.message ? err.message : err);
    this.httpsRunning = false;

    if (err && err.code === 'EADDRINUSE') {
      Logger.error(`HTTPS port ${this.httpsPort} in use, trying fallback`);
      this._cleanupHttpsServer();
      this.httpsPort = this.httpsPort + 1;
      this.startHttpsServer();
      return;
    }

    Logger.error(`HTTPS start failed, continuing HTTP only`);
  }

  _cleanupHttpsServer() {
    if (!this.httpsServer) return;
    try {
      this.httpsServer.removeAllListeners();
    } catch (_) {}
    try {
      if (typeof this.httpsServer.close === 'function') this.httpsServer.close();
    } catch (_) {}
    this.httpsServer = null;
  }

  _attachHttpsUpgradeToExistingWss() {
    const expressWs = this.app && this.app.expressWs;
    const wss = expressWs && typeof expressWs.getWss === 'function' ? expressWs.getWss() : null;
    if (!wss || !this.httpsServer) return;

    this.httpsServer.on('upgrade', (req, socket, head) => {
      try {
        wss.handleUpgrade(req, socket, head, ws => {
          wss.emit('connection', ws, req);
        });
      } catch (_) {
        try {
          socket.destroy();
        } catch (_) {}
      }
    });
  }

  async restartServer() {
    Logger.info(`🔄 NasCabOSAPI process restarting...`);

    if (this.server) {
      await this.stopServer();
    }

    // 等待一小段时间后重启
    setTimeout(() => {
      this.startServer();
    }, 1000);
  }

  async stopServer() {
    const stopPromises = [];

    // 关闭HTTP服务器
    if (this.server) {
      stopPromises.push(
        new Promise(resolve => {
          this.server.close(err => {
            if (err) {
              Logger.error(`❌ HTTP server close failed:`, err);
            } else {
              Logger.info(`🛑 HTTP server closed`);
              this.isRunning = false;
              this.server = null;
            }
            resolve();
          });
        })
      );
    }

    // 关闭HTTPS服务器
    if (this.httpsServer) {
      stopPromises.push(
        new Promise(resolve => {
          this.httpsServer.close(err => {
            if (err) {
              Logger.error(`❌ HTTPS server close failed:`, err);
            } else {
              Logger.info(`🔒 HTTPS server closed`);
              this.httpsRunning = false;
              this.httpsServer = null;
            }
            resolve();
          });
        })
      );
    }

    // 等待所有服务器关闭
    await Promise.all(stopPromises);

    try {
      await getSingletonWorkerManager().gracefulShutdown();
    } catch (err) {
      Logger.error('❌ Singleton workers shutdown failed:', err);
    }

    // 发送停止消息
    if (typeof process.send === 'function') {
      process.send({ type: 'expressEnded', data: { port: this.port } });
    }
  }

  setupGracefulShutdown() {
    if (this._gracefulShutdownSetup) return;
    this._gracefulShutdownSetup = true;

    // 优雅关闭处理
    const gracefulShutdown = signal => {
      Logger.info(`📡 Received ${signal}, shutting down NasCabOSAPI ...`);

      this.stopServer()
        .then(() => {
          process.exit(0);
        })
        .catch(err => {
          Logger.error(`❌ NasCabOSAPI shutdown failed:`, err);
          process.exit(1);
        });
    };

    // 注册信号处理
    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));
    process.on('SIGUSR2', () => gracefulShutdown('SIGUSR2')); // nodemon重启信号

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

  // 计算当前负载（示例方法）
  calculateLoad() {
    return {
      memory: process.memoryUsage().rss,
      uptime: process.uptime(),
      activeConnections: this.server ? this.server._connections || 0 : 0,
    };
  }
}

// 启动Express Worker
if (require.main === module) {
  new ExpressWorker();
}
module.exports = ExpressWorker;
