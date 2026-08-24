const sharp = require('./sharpConfigured');
const path = require('path');
const fs = require('fs');
const Logger = require('./logger');
/**
 * 图片处理工具类 - 支持HEIC格式
 * 提供HEIC解码、格式转换、缩略图生成等功能
 */
class ImageUtil {
  constructor() {
    this.supportedFormats = [
      'jpg',
      'jpeg',
      'png',
      'webp',
      'tiff',
      'gif',
      'svg',
      'heic',
      'heif', // HEIC格式支持
    ];

    this.init();
  }

  /**
   * 初始化sharp配置
   */
  init() {
    // 检查HEIC支持
    this.checkHEICSupport();
  }

  /**
   * 检查HEIC支持状态
   */
  checkHEICSupport() {
    try {
      // 测试HEIC格式支持
      const testBuffer = Buffer.from('');
      sharp(testBuffer, {
        failOnError: false,
        limitInputPixels: false,
      });

      Logger.info('✅ sharp loaded, checking HEIC support...');

      // 检查HEIC编解码器支持
      const metadata = sharp.format;
      const heicSupported = metadata.heic && metadata.heic.input;
      const heifSupported = metadata.heif && metadata.heif.input;

      Logger.info(`📊 HEIC input: ${heicSupported}`);
      Logger.info(`📊 HEIF input: ${heifSupported}`);

      if (!heicSupported && !heifSupported) {
        Logger.warn('⚠️ sharp build lacks HEIC; reinstall a HEIC-capable sharp if needed');
        this.installHEICSupportInstructions();
      }
    } catch (error) {
      console.error('❌ sharp init failed:', error.message);
    }
  }

  /**
   * 显示HEIC支持安装指南
   */
  installHEICSupportInstructions() {
    Logger.info(`
🔧 安装支持HEIC的sharp版本：

方法1 - 使用预编译版本（推荐）：
  npm uninstall sharp
  npm install sharp --platform=win32 --arch=x64 --libvips=8.14.5

方法2 - 从源码编译：
  npm uninstall sharp
  npm install -g node-gyp
  npm install --global --production windows-build-tools
  npm install sharp --build-from-source

方法3 - 使用环境变量：
  set SHARP_IGNORE_GLOBAL_LIBVIPS=1
  npm install sharp

安装完成后重启应用。
        `);
  }

  /**
   * 检测图片格式
   * @param {string} filePath - 图片文件路径
   * @returns {Promise<string>} 图片格式
   */
  async detectFormat(filePath) {
    try {
      const metadata = await sharp(filePath).metadata();
      return metadata.format;
    } catch (error) {
      console.error(`❌ detect image format failed: ${filePath}`, error.message);
      return null;
    }
  }

  /**
   * 检查是否为HEIC格式
   * @param {string} filePath - 图片文件路径
   * @returns {Promise<boolean>} 是否为HEIC格式
   */
  async isHEICFormat(filePath) {
    const format = await this.detectFormat(filePath);
    return format === 'heic' || format === 'heif';
  }

  /**
   * HEIC转JPEG
   * @param {string} inputPath - 输入文件路径
   * @param {string} outputPath - 输出文件路径
   * @param {Object} options - 转换选项
   * @returns {Promise<boolean>} 转换是否成功
   */
  async convertHEICtoJPEG(inputPath, outputPath, options = {}) {
    try {
      const { quality = 80, width = null, height = null, fit = 'cover' } = options;

      let pipeline = sharp(inputPath);

      // 调整尺寸
      if (width || height) {
        pipeline = pipeline.resize(width, height, {
          fit: fit,
          withoutEnlargement: true,
        });
      }

      // 转换为JPEG
      await pipeline
        .jpeg({
          quality: quality,
          mozjpeg: true,
        })
        .toFile(outputPath);

      Logger.info(`✅ HEIC to JPEG ok: ${inputPath} -> ${outputPath}`);
      return true;
    } catch (error) {
      error(`❌ HEIC to JPEG failed: ${inputPath}`, error.message);
      return false;
    }
  }

  /**
   * 生成缩略图
   * @param {string} inputPath - 输入文件路径
   * @param {string} outputPath - 输出文件路径
   * @param {number} width - 缩略图宽度
   * @param {number} height - 缩略图高度
   * @param {Object} options - 选项
   * @returns {Promise<boolean>} 生成是否成功
   */
  async generateThumbnail(inputPath, outputPath, width = 200, height = 200, options = {}) {
    try {
      const { quality = 70, fit = 'cover', position = 'center' } = options;

      // 检查是否为HEIC格式
      const isHEIC = await this.isHEICFormat(inputPath);

      let pipeline = sharp(inputPath);

      // 生成缩略图
      await pipeline
        .resize(width, height, {
          fit: fit,
          position: position,
          withoutEnlargement: true,
        })
        .jpeg({
          quality: quality,
        })
        .toFile(outputPath);


      return true;
    } catch (error) {
      error(`❌ thumbnail gen failed: ${inputPath}`, error.message);
      return false;
    }
  }

  /**
   * 获取图片信息
   * @param {string} filePath - 图片文件路径
   * @returns {Promise<Object>} 图片信息
   */
  async getImageInfo(filePath) {
    try {
      const stats = fs.statSync(filePath);
      const metadata = await sharp(filePath).metadata();

      return {
        path: filePath,
        format: metadata.format,
        width: metadata.width,
        height: metadata.height,
        size: stats.size,
        hasAlpha: metadata.hasAlpha,
        space: metadata.space,
        channels: metadata.channels,
        density: metadata.density,
        isHEIC: metadata.format === 'heic' || metadata.format === 'heif',
        orientation: metadata.orientation,
      };
    } catch (error) {
      error(`❌ get image metadata failed: ${filePath}`, error.message);
      return null;
    }
  }

  /**
   * 批量处理HEIC文件
   * @param {Array} fileList - 文件列表
   * @param {Function} processor - 处理函数
   * @param {number} concurrency - 并发数
   * @returns {Promise<Array>} 处理结果
   */
  async batchProcessHEIC(fileList, processor, concurrency = 3) {
    const results = [];

    // 分组处理，控制并发
    for (let i = 0; i < fileList.length; i += concurrency) {
      const batch = fileList.slice(i, i + concurrency);
      const batchPromises = batch.map(async file => {
        try {
          const result = await processor(file);
          return { file, success: true, result };
        } catch (error) {
          return { file, success: false, error: error.message };
        }
      });

      const batchResults = await Promise.all(batchPromises);
      results.push(...batchResults);

      Logger.info(`📊 Batch progress: ${Math.min(i + concurrency, fileList.length)}/${fileList.length}`);
    }

    return results;
  }

  /**
   * 创建图片预览（适用于HEIC）
   * @param {string} inputPath - 输入文件路径
   * @param {string} previewPath - 预览文件路径
   * @param {number} maxWidth - 最大宽度
   * @param {number} maxHeight - 最大高度
   * @returns {Promise<boolean>} 创建是否成功
   */
  async createPreview(inputPath, previewPath, maxWidth = 800, maxHeight = 600) {
    try {
      const info = await this.getImageInfo(inputPath);
      if (!info) return false;

      // 计算预览图尺寸
      let width = info.width;
      let height = info.height;

      if (width > maxWidth || height > maxHeight) {
        const ratio = Math.min(maxWidth / width, maxHeight / height);
        width = Math.round(width * ratio);
        height = Math.round(height * ratio);
      }

      // 生成预览图
      return await this.generateThumbnail(inputPath, previewPath, width, height, {
        quality: 85,
        fit: 'inside',
      });
    } catch (error) {
      error(`❌ create preview failed: ${inputPath}`, error.message);
      return false;
    }
  }

  /**
   * 验证HEIC文件完整性
   * @param {string} filePath - 文件路径
   * @returns {Promise<boolean>} 文件是否完整
   */
  async validateHEICFile(filePath) {
    try {
      const metadata = await sharp(filePath).metadata();
      return metadata.format === 'heic' || metadata.format === 'heif';
    } catch (error) {
      return false;
    }
  }
}

// 创建单例实例
const imageUtil = new ImageUtil();

// 导出单例实例
module.exports = imageUtil;
