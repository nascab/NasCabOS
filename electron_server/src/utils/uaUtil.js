const UAParser = require('ua-parser-js');

class UAUtil {
  /**
   * 解析User-Agent字符串
   * @param {string} userAgent
   * @returns {Object} { browser, os, device, deviceInfo }
   */
  static parse(userAgent) {
    if (!userAgent) {
      return {
        browser: '',
        os: '',
        device: '',
        deviceInfo: 'Unknown',
      };
    }

    // 1. 尝试解析自定义Flutter客户端UA格式
    // 格式: AppName/Version (Platform; OS Version; Device Model)
    // 例如: NasCabOS/1.0.0+1 (macOS; 26.1.0; Mac15,9)
    try {
      const customUARegex = /^([^\/]+)\/([^\s]+)\s+\(([^;]+);\s*([^;]+);\s*([^)]+)\)/;
      const match = userAgent.match(customUARegex);

      if (match && match.length >= 6) {
        const appName = match[1] || 'NasCab Client';
        // const version = match[2]; // 暂时未用到版本号
        const platform = match[3] || 'Unknown Platform';
        const osVer = match[4] || 'Unknown OS Version';
        const deviceModel = match[5] || 'Unknown Device';

        return {
          browser: `${appName} Client`,
          os: `${platform} ${osVer}`,
          device: deviceModel,
          deviceInfo: deviceModel,
        };
      }
    } catch (e) {
      // 忽略正则解析错误，降级到通用解析
      console.error('Custom UA parsing failed:', e);
    }

    // 2. 使用通用库解析标准UA
    const parser = new UAParser(userAgent);
    const result = parser.getResult();

    const browser = `${result.browser.name || ''} ${result.browser.version || ''}`.trim();
    const os = `${result.os.name || ''} ${result.os.version || ''}`.trim();
    const device = `${result.device.vendor || ''} ${result.device.model || ''}`.trim();
    const deviceInfo = device || 'Desktop';

    return {
      browser,
      os,
      device,
      deviceInfo,
    };
  }
}

module.exports = UAUtil;
