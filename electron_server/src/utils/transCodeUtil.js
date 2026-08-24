const os = require('os');
/**
 * 硬件信息工具类
 * 提供获取CPU、内存等硬件信息的功能
 */
class TransCodeUtil {
  /**
   * 处理ffmpeg路径
   */
  dealFfmpegPath(fullPath) {
    if (typeof fullPath !== 'string') return fullPath;
    //windows下面路径长度超出259个字符 会出现找不到文件的情况 这里处理
    const platform = os.platform();
    if (platform == 'win32' && fullPath.length > 259) {
      return '\\\\?\\' + fullPath;
    } else {
      return fullPath;
    }
  }
}

// 创建单例实例
const transCodeUtil = new TransCodeUtil();
// 导出单例实例
module.exports = transCodeUtil;
