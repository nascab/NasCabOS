const exifr = require('exifr');
const fs = require('fs-extra');

//  处理livephoto的工具类
class LvpUtil {
  constructor() {}
  /**
   * 判断是否是合并后的livephoto
   * @param {string} inputPath - 输入的OPPO实况照片JPG路径
   * @returns {boolean} - 是否是合并后的livephoto
   */
  isMergeLvp(exifData) {
    if (!exifData) {
      return false;
    }
    let hasSign = false;
    let hasDir = false;
    if (exifData['MotionPhoto'] == 1) {
      hasSign = true;
    }
    if (exifData['Directory'] && exifData['Directory'].length > 0) {
      let dirs = exifData['Directory'];
      let videoItem = dirs[dirs.length - 1]['Item'];
      if (videoItem && videoItem['Mime'].indexOf('video/mp4') !== -1 && videoItem['Length']) {
        hasDir = true;
      }
    }
    return hasSign && hasDir;
  }
  /**
   * 提取OPPO实况照片中的MP4视频（修复moov atom not found问题，无需FFmpeg）
   * @param {string} inputPath - 输入的OPPO实况照片JPG路径
   * @param {string} outputPath - 输出的MP4视频路径
   */
  async extractOppoLvpVideo(inputPath, outputPath) {
    try {
      // 步骤1：读取exifr元数据，获取VideoLength（仅用于验证，不再用于截取）
      console.log('正在读取元数据...');
      const metadata = await exifr.parse(inputPath, true);
      if (metadata['Directory'] && metadata['Directory'].length > 0) {
        let dirs = metadata['Directory'];
        let videoItem = dirs[dirs.length - 1]['Item'];
        if (videoItem && videoItem['Mime'].indexOf('video/mp4') !== -1 && videoItem['Length']) {
          videoLength = videoItem['Length'];
        }
      }
      if (videoLength && !isNaN(videoLength)) {
        console.log(`读取到视频长度（元数据）：${videoLength} 字节`);
      } else {
        console.warn('未读取到有效VideoLength');
        return;
      }
      // 步骤2：读取JPG文件的二进制数据
      const fileBuffer = await fs.readFile(inputPath);
      const fileTotalSize = fileBuffer.length;
      console.log(`读取文件成功，文件总大小：${fileTotalSize} 字节`);
      // 步骤3：查找ftyp的起始偏移量
      const ftypOffset = fileTotalSize - videoLength;
      if (ftypOffset === -1) {
        throw new Error('err');
      }
      // 步骤4：【关键修正】从ftyp位置截取到文件末尾（保留完整的MP4数据，包括moov原子）
      const videoBuffer = fileBuffer.slice(ftypOffset);
      const actualVideoSize = videoBuffer.length;
      console.log(`截取的视频数据大小：${actualVideoSize} 字节`);
      // 可选：验证元数据的VideoLength与实际截取的大小是否一致
      if (videoLength && !isNaN(videoLength)) {
        const sizeDiff = Math.abs(actualVideoSize - videoLength);
        if (sizeDiff > 1024) {
          // 差异超过1KB时提示
          console.warn(`警告：元数据的视频长度(${videoLength})与实际截取大小(${actualVideoSize})差异较大（${sizeDiff}字节），但不影响播放`);
        }
      }
      // 步骤5：写入MP4文件
      await fs.writeFile(outputPath, videoBuffer);
      console.log(`视频提取完成！输出路径：${outputPath}，文件大小：${actualVideoSize} 字节`);
    } catch (err) {
      console.error('提取失败：', err.message);
    }
  }
}

// 创建单例实例
const lvpUtil = new LvpUtil();
// 导出单例实例
module.exports = lvpUtil;
