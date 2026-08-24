const sharp = require('./sharpConfigured');
const path = require('path');
const ffmpeg = require('fluent-ffmpeg');
const fs = require('fs');
const Logger = require('./logger');
const crypto = require('crypto');
const { Worker } = require('worker_threads');
const config = require('../config/config');
const transCodeUtil = require('./transCodeUtil');
const ffmpegPath = require('../libsPath/ffmpegPath');
const ffprobePath = require('../libsPath/ffprobePath');
ffmpeg.setFfmpegPath(ffmpegPath.path);
ffmpeg.setFfprobePath(ffprobePath.path);
// Optional dependencies
let dcraw;
let PSD;
let sharpBmp;

const VIDEO_FFMPEG_TIMEOUT_SECONDS = 180;

try {
  dcraw = require('dcraw');
} catch (e) {}
try {
  PSD = require('psd');
} catch (e) {}
try {
  sharpBmp = require('sharp-bmp');
} catch (e) {}

// 开关：设为 true 可暂时禁用自编译 sharp 的 HEIF 原生解码，回退到 wasm 方案
const DISABLE_HEIF_NATIVE_DECODE = false;

// 预编译包 @img/sharp-* 仅有 AVIF，无 HEVC 解码器；
// 内置 libs/sharp/<platform>/<arch>（buildScripts/build-sharp-heif-mac.sh 生成）源码构建、
// 原生支持 HEIC/HEIF/AVIF 解码与 EXIF 方向，heif 后缀如实上报 .heic/.heif/.avif。
const heifNativeSupport = (() => {
  if (DISABLE_HEIF_NATIVE_DECODE) return false;
  try {
    const suffix = sharp && sharp.format && sharp.format.heif && sharp.format.heif.input && sharp.format.heif.input.fileSuffix;
    if (Array.isArray(suffix) && (suffix.includes('.heic') || suffix.includes('.heif'))) return true;
    // vendored sharp 路径含 "libs/sharp"（不受 require.cache 注入影响）
    if (Object.keys(require.cache).some(k => k.includes('libs' + path.sep + 'sharp'))) return true;
  } catch (e) {}
  return false;
})();

class SharpUtils {
  constructor() {}

  getDcraw() {
    return dcraw;
  }

  getPsd() {
    return PSD;
  }

  extractThumbnailFromRaw(filePathOrBuffer, ext) {
    return new Promise((resolve, reject) => {
      if (ext && ext.toLowerCase() == '.psd') {
        const PSD = this.getPsd();
        if (!PSD) return reject(new Error('PSD module not found'));

        try {
          if (typeof filePathOrBuffer == 'string') {
            // For PSD, we save as PNG first then Sharp converts it
            // To avoid polluting cache with temp files, we try to use buffer or temp path
            // Old code saved to cachePath + sha256 + '_psd.png'
            const tempPngPath = path.join(config.getTinyCachePath(), crypto.createHash('sha256').update(filePathOrBuffer).digest('hex') + '_psd.png');

            fs.stat(tempPngPath, (err, stat) => {
              if (!err && stat.size > 0) {
                return resolve(tempPngPath);
              }

              try {
                const psd = PSD.fromFile(filePathOrBuffer);
                psd.parse();
                psd.image
                  .saveAsPng(tempPngPath)
                  .then(() => {
                    resolve(tempPngPath);
                  })
                  .catch(err => {
                    reject(err);
                  });
              } catch (err) {
                reject(err);
              }
            });
          } else {
            reject(new Error('Buffer input for PSD not fully implemented'));
          }
        } catch (err) {
          reject(err);
        }
      } else {
        // Other RAW formats
        const dcraw = this.getDcraw();
        if (!dcraw) return reject(new Error('dcraw module not found'));

        // dcraw（emscripten）返回 Uint8Array，统一转成 Buffer 供 sharp 使用
        const toBuffer = v => (Buffer.isBuffer(v) ? v : Buffer.from(v));

        const dealBuffer = buf => {
          // 1) 先尝试提取内嵌 JPEG 缩略图（dcraw -e，最快）
          try {
            const outBuf = dcraw(buf, { extractThumbnail: true, identify: true });
            // 无内嵌缩略图时 dcraw 可能返回错误消息字符串，需排除
            if (outBuf && outBuf.length && typeof outBuf !== 'string') {
              return resolve(toBuffer(outBuf));
            }
          } catch (err) {
            // 无内嵌预览（部分相机/手机 DNG 不含 preview），落到完整渲染
          }
          // 2) 降级：dcraw 完整 debayer 渲染（半尺寸 TIFF，约数百毫秒）。
          //    注意：libvips 把 DNG 当 TIFF 读只能得到 Bayer mosaic（multiband），
          //    无法转 sRGB 显示（vips_colourspace: no known route from 'multiband' to 'srgb'），
          //    必须由 dcraw 完成去马赛克/白平衡/颜色矩阵。
          //    输出已按 EXIF orientation 旋转（orientation=1），sharp 侧 rotate() 不会二次旋转。
          try {
            const outTiff = dcraw(buf, {
              useCameraWhiteBalance: true,
              setHalfSizeMode: true,
              setNoStretchMode: true,
              exportAsTiff: true,
            });
            if (outTiff && outTiff.length && typeof outTiff !== 'string') {
              return resolve(toBuffer(outTiff));
            }
            reject(new Error('No image decoded from RAW'));
          } catch (err) {
            reject(err);
          }
        };

        if (typeof filePathOrBuffer == 'string') {
          fs.readFile(filePathOrBuffer, (err, buf) => {
            if (err) reject(err);
            else dealBuffer(buf);
          });
        } else if (Buffer.isBuffer(filePathOrBuffer)) {
          dealBuffer(filePathOrBuffer);
        } else {
          reject(new Error('Invalid input for RAW'));
        }
      }
    });
  }

  /**
   * 使用 libheif-js wasm 在 worker_threads 中解码 HEIC，避免主线程崩溃/阻塞
   * @param {Buffer} inputBuffer
   * @returns {Promise<{data: Uint8ClampedArray, width: number, height: number} | null>}
   */
  runTransHeicWorker(inputBuffer, timeoutMs = 15000) {
    return new Promise((resolve, reject) => {
      if (!Buffer.isBuffer(inputBuffer)) return reject(new Error('inputBuffer must be a Buffer'));

      const workerPath = path.resolve(__dirname, '../workers/transHeicWorker.js');
      const worker = new Worker(workerPath, { workerData: { inputBuffer } });

      let timeout = null;
      let settled = false;
      let terminatePromise = null;

      const terminateOnce = async () => {
        if (!terminatePromise) terminatePromise = await worker.terminate().catch(() => {});
        return terminatePromise;
      };

      const cleanup = () => {
        worker.removeAllListeners('message');
        worker.removeAllListeners('error');
        worker.removeAllListeners('exit');
      };

      try {
        if (typeof worker.unref === 'function') worker.unref();
      } catch (_) {}

      timeout = setTimeout(async () => {
        if (settled) return;
        settled = true;
        cleanup();
        await terminateOnce();
        reject(new Error('HEIC decode timeout'));
      }, timeoutMs);

      worker.once('message', async msg => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        await terminateOnce();
        if (msg && msg.code === 0) return resolve(msg.output || null);
        reject(new Error('HEIC decode worker failed'));
      });

      worker.once('error', async err => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        await terminateOnce();
        reject(err || new Error('HEIC decode worker error'));
      });

      worker.once('exit', async code => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        await terminateOnce();
        if (code === 0) return resolve(null);
        reject(new Error(`HEIC decode worker exited: ${code}`));
      });
    });
  }

  /**
   * 转换特殊格式为Sharp-compatible输入（Buffer或Path）
   * 返回Promise，解析为Sharp需要的输入（Buffer或Path）
   */
  transSpcielFormat(fullPath) {
    return new Promise(resolve => {
      if (!fullPath) return resolve(fullPath);
      if (Buffer.isBuffer(fullPath)) return resolve(fullPath);
      if (fullPath instanceof ArrayBuffer) return resolve(Buffer.from(new Uint8Array(fullPath)));
      if (ArrayBuffer.isView(fullPath)) return resolve(Buffer.from(fullPath.buffer, fullPath.byteOffset, fullPath.byteLength));
      if (fullPath && typeof fullPath === 'object' && fullPath.type === 'Buffer' && Array.isArray(fullPath.data)) return resolve(Buffer.from(fullPath.data));
      if (fullPath && typeof fullPath === 'object' && fullPath.input && fullPath.options) return resolve(fullPath);
      if (typeof fullPath !== 'string') return resolve(fullPath);
      let ext = path.extname(fullPath).toLowerCase();

      if (ext === '.heic' || ext === '.heif' || ext === '.hif') {
        // sharp 原生支持 HEIF 时直接返回路径，由 sharp 管线解码（远快于 wasm）
        if (heifNativeSupport){
           console.log(`[sharp heif] native decode: ${fullPath}`);
           return resolve(fullPath);
        }else{
          console.log(`[sharp heif] wasm decode: ${fullPath}`);
        }
        fs.readFile(fullPath, (err, inputBuffer) => {
          if (err) return resolve(fullPath);
          this.runTransHeicWorker(inputBuffer)
            .then(displayData => {
              if (!displayData || !displayData.data || !displayData.width || !displayData.height) {
                return resolve(fullPath);
              }
              const rawBuffer = Buffer.from(displayData.data);
              resolve({
                input: rawBuffer,
                options: {
                  raw: {
                    width: displayData.width,
                    height: displayData.height,
                    channels: 4,
                  },
                },
              });
            })
            .catch(err2 => {
              console.error('HEIC wasm convert failed:', err2);
              Logger.error('HEIC wasm convert failed:', err2);
              resolve(fullPath);
            });
        });
      } else if (ext === '.bmp') {
        if (!sharpBmp) return resolve(fullPath);
        fs.readFile(fullPath, (err, buffer) => {
          if (err) return resolve(fullPath);
          try {
            const bitmap = sharpBmp.decode(buffer);
            // bitmap is { width, height, data }
            resolve({
              input: bitmap.data,
              options: {
                raw: {
                  width: bitmap.width,
                  height: bitmap.height,
                  channels: 4,
                },
              },
            });
          } catch (err) {
            resolve(fullPath);
          }
        });
      } else if (config.rawImgTypeList && config.rawImgTypeList.includes(ext)) {
        this.extractThumbnailFromRaw(fullPath, ext)
          .then(outbuffer => {
            // outbuffer is usually JPEG buffer extracted from RAW
            resolve(outbuffer);
          })
          .catch(() => {
            resolve(fullPath);
          });
      } else {
        resolve(fullPath);
      }
    });
  }

  /**
   * 生成缩略图
   */
  async genTinyFile(sourcePath, saveFolderPath, saveFileName, fileType, targetSize) {
    const targetFullPath = path.join(saveFolderPath, saveFileName) + '.webp';
    // 默认缩略图尺寸
    const size = targetSize ? parseInt(targetSize) : 640;

    try {
      const stat = await fs.promises.stat(targetFullPath);
      if (stat.isFile() && stat.size > 0) return targetFullPath;
    } catch (e) {}

    if (!fs.existsSync(saveFolderPath)) {
      await fs.promises.mkdir(saveFolderPath, { recursive: true });
    }

    const tinyCachePath = typeof config.getTinyCachePath === 'function' ? config.getTinyCachePath() : null;
    const tinyTempPath = typeof config.getTinyCacheTempPath === 'function' ? config.getTinyCacheTempPath() : null;
    const tempFolderPath = tinyCachePath && tinyTempPath && path.resolve(saveFolderPath) === path.resolve(tinyCachePath) ? tinyTempPath : path.join(saveFolderPath, 'temp');

    if (!fs.existsSync(tempFolderPath)) {
      await fs.promises.mkdir(tempFolderPath, { recursive: true });
    }

    const tempFileName = `${saveFileName}.${process.pid}.${Date.now()}.${crypto.randomBytes(6).toString('hex')}.webp`;
    const tempFullPath = path.join(tempFolderPath, tempFileName);

    const finalize = async () => {
      try {
        const stat = await fs.promises.stat(targetFullPath);
        if (stat.isFile() && stat.size > 0) {
          await fs.promises.unlink(tempFullPath).catch(() => {});
          return targetFullPath;
        }
      } catch (e) {}

      try {
        await fs.promises.rename(tempFullPath, targetFullPath);
        return targetFullPath;
      } catch (err) {
        if (err && err.code === 'EXDEV') {
          await fs.promises.copyFile(tempFullPath, targetFullPath);
          await fs.promises.unlink(tempFullPath).catch(() => {});
          return targetFullPath;
        }
        throw err;
      }
    };

    if (fileType === 'image') {
      try {
        // 转换特殊格式为Sharp-compatible输入（Buffer或Path）
        const processed = await this.transSpcielFormat(sourcePath);
        let pipeline;
        if (processed && processed.input && processed.options) {
          pipeline = sharp(processed.input, processed.options);
        } else {
          // processed is string (path) or Buffer
          pipeline = sharp(processed, { failOnError: false });
        }
        // Resize
        await pipeline
          .rotate() // Auto-rotate based on EXIF
          .resize(size, size, { fit: 'inside', withoutEnlargement: true })
          .webp({ quality: 70 })
          .toFile(tempFullPath);
        // console.log('缩略图生成成功', targetFullPath);
        return await finalize();
      } catch (err) {
        await fs.promises.unlink(tempFullPath).catch(() => {});
        console.error('GenTinyFile Image Error:', err);
        throw err;
      }
    } else if (fileType === 'video') {
      return new Promise((resolve, reject) => {
        const inputPath = transCodeUtil.dealFfmpegPath(sourcePath);
        const runScreenshot = timestamp =>
          new Promise((innerResolve, innerReject) => {
            const cmd = ffmpeg(inputPath);
            let timeoutId = null;
            let settled = false;

            timeoutId = setTimeout(() => {
              if (settled) return;
              try { cmd.kill('SIGKILL'); } catch (_) {}
            }, VIDEO_FFMPEG_TIMEOUT_SECONDS * 1000);

            cmd.on('end', async () => {
              if (settled) return;
              settled = true;
              if (timeoutId) { clearTimeout(timeoutId); timeoutId = null; }
              try {
                const out = await finalize();
                innerResolve(out);
              } catch (e) {
                innerReject(e);
              }
            });
            cmd.on('error', async err => {
              if (settled) return;
              settled = true;
              if (timeoutId) { clearTimeout(timeoutId); timeoutId = null; }
              await fs.promises.unlink(tempFullPath).catch(() => {});
              innerReject(err);
            });
            cmd.screenshots({
              timestamps: [timestamp],
              filename: tempFileName,
              folder: tempFolderPath,
              size: `${size}x?`,
            });
          });

        runScreenshot('10%')
          .then(resolve)
          .catch(err => {
            const msg = String((err && err.message) || err || '').toLowerCase();
            const canFallback =
              msg.includes('output stream closed') ||
              msg.includes('could not get input duration') ||
              msg.includes('specify fixed timemarks') ||
              msg.includes('error with ffmpeg') ||
              msg.includes('timed out') ||
              msg.includes('killed');
            if (!canFallback) {
              reject(err);
              return;
            }
            runScreenshot('1')
              .then(resolve)
              .catch(reject);
          });
      });
    } else {
      throw new Error('Unsupported file type');
    }
  }

  /**
   * 处理并返回图片流给响应
   */
  async processToResponse(res, fullPath, size, quality) {
    try {
      const processed = await this.transSpcielFormat(fullPath);
      let pipeline;
      if (processed && processed.input && processed.options) {
        pipeline = sharp(processed.input, processed.options);
      } else {
        pipeline = sharp(processed, { failOnError: false });
      }

      // Rotate based on EXIF
      pipeline = pipeline.rotate();

      // Resize if needed
      if (size) {
        const s = parseInt(size);
        if (s > 0) {
          pipeline = pipeline.resize(s, s, { fit: 'inside', withoutEnlargement: true });
        }
      }

      // Output format (default to jpeg like old code, or webp if preferred?)
      // Old code used jpeg with quality
      const q = quality ? parseInt(quality) : 70;
      pipeline = pipeline.jpeg({ quality: q });

      // Pipe to response
      res.type('image/jpeg');
      pipeline.pipe(res);

      pipeline.on('error', err => {
        console.error('Sharp pipeline error:', err);
        if (!res.headersSent) {
          res.status(500).end();
        }
      });
    } catch (err) {
      console.error('ProcessToResponse Error:', err);
      if (!res.headersSent) {
        res.status(500).send(err.message);
      }
    }
  }
}

module.exports = new SharpUtils();
