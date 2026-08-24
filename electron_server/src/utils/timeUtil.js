const os = require('os');
/**
 * 硬件信息工具类
 * 提供获取CPU、内存等硬件信息的功能
 */
class TimeUtil {
  /**
   * 解析时间字符串为秒数
   * @param {string} expiresIn - 时间字符串，如 '15m', '7d', '2h'
   * @returns {number} 秒数
   */
  parseExpiresIn(expiresIn) {
    const unitMap = {
      s: 1, // 秒
      m: 60, // 分钟
      h: 60 * 60, // 小时
      d: 24 * 60 * 60, // 天
    };

    const match = expiresIn.match(/^(\d+)([smhd])$/);
    if (!match) {
      throw new Error(`无效的时间格式: ${expiresIn}`);
    }

    const value = parseInt(match[1]);
    const unit = match[2];
    return value * unitMap[unit];
  }
}

// 创建单例实例
const timeUtil = new TimeUtil();
// 导出单例实例
module.exports = timeUtil;
