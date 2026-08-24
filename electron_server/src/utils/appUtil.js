let app, BrowserWindow, Menu, Tray, protocol, ipcMain;
const Logger = require('./logger');

try {
  let elec = require('electron');
  app = elec.app;
  BrowserWindow = elec.BrowserWindow;
  Menu = elec.Menu;
  Tray = elec.Tray;
  protocol = elec.protocol;
  ipcMain = elec.ipcMain;
} catch (err) {
  //docker模式 无界面运行
  Logger.info('Clientless service mode');
}
const os = require('os');
const config = require('../config/config');
const path = require('path');
const tableConfig = require('../db/table/tableConfig');
const portfinder = require('portfinder');

class AppUtil {
  constructor() {}
  /**
   * 获取配置的API端口号
   * @param {boolean} getHttps - 是否获取HTTPS端口
   * @returns {number} - 配置的API端口号
   */
  async getConfigApiPort(getHttps) {
    //获取用户设置的api服务端口号
    let configPort = getHttps ? config.app.httpsPort : config.app.port;
    let portConfig = await tableConfig.getConfigByKey(getHttps ? tableConfig.KEY_API_PORT_HTTPS : tableConfig.KEY_API_PORT_HTTP);
    if (portConfig) {
      let dbPort = parseInt(portConfig);
      if (dbPort <= 0 || dbPort > 65535) {
        // 设置的端口无效 还用默认的
      } else {
        configPort = dbPort;
      }
    }
    return configPort;
  }
  /**
   * 获取可用端口
   * @param {number} basePort - 基础端口号
   * @param {function} callback - 回调函数，参数为错误对象和可用端口号
   */
  async getFreePort(basePort) {
    try {
      const freePort = await portfinder.getPortPromise({
        port: basePort, // minimum port
        stopPort: 65535, // maximum port
      });
      return freePort;
    } catch (err) {
      Logger.error('Failed to get free port', err);
      return null;
    }
  }
}

// 创建单例实例
const appUtil = new AppUtil();
// 导出单例实例
module.exports = appUtil;
