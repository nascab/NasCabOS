'use strict';

/**
 * 统一加载 sharp 并收紧 libvips 操作缓存，降低常驻与峰值内存。
 * 须在本进程内任何 sharp 图像操作之前被 require（请用本模块替代 require('sharp')）。
 *
 * 加载顺序：
 *   1) 项目内置 libs/sharp/<platform>/<arch>（buildScripts/build-sharp-heif-mac.sh 生成，
 *      源码构建、原生支持 HEIC/HEIF；不受 npm install 影响）
 *   2) npm 包 sharp（官方预编译，无 HEVC 解码；HEIC 由 sharpUtils 的 wasm worker 兜底）
 *
 * 可选环境变量：
 *   SHARP_CACHE_MEMORY_MB — 缓存内存上限（MB），默认 32（sharp 默认约 50）
 *   SHARP_CACHE_FILES — 可同时缓存打开的文件数，默认 8（默认 20）
 *   SHARP_CACHE_ITEMS — 缓存操作条目数，默认 32（默认 100）
 *   SHARP_CONCURRENCY — libvips 线程数；仅当设置正整数时生效，用于压低并发解码峰值
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

function vendoredSharpDir() {
  let platform = os.platform();
  if (platform === 'darwin') platform = 'mac';
  else if (platform === 'win32') platform = 'win';
  const rel = path.join('libs', 'sharp', platform, os.arch());
  const candidates = [
    path.join(__dirname, '../../', rel), // 开发环境（src/utils -> 项目根）
  ];
  try {
    const config = require('../config/config');
    candidates.push(path.join(config.getRootPath(), rel)); // 生产/Worker（与 ffmpeg 等 libs 同一约定）
  } catch (e) {}
  if (process.resourcesPath) {
    candidates.push(path.join(process.resourcesPath, rel)); // electron-builder extraFiles 落点
  }
  for (const dir of candidates) {
    try {
      if (fs.existsSync(path.join(dir, 'package.json'))) return dir;
    } catch (e) {}
  }
  return null;
}

let sharp;
const vendoredDir = vendoredSharpDir();
if (vendoredDir) {
  sharp = require(vendoredDir);
  // 让所有 require('sharp')（sharp-phash、sharp-bmp 等）也拿到内置版
  try {
    const npmKey = require.resolve('sharp');
    if (!npmKey.includes('libs/sharp')) {
      require.cache[npmKey] = { exports: sharp };
    }
  } catch (_) {}
} else {
  sharp = require('sharp');
}

function envInt(name, fallback, min, max) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const n = parseInt(String(raw), 10);
  if (!Number.isFinite(n)) return fallback;
  let v = n;
  if (typeof min === 'number' && v < min) v = min;
  if (typeof max === 'number' && v > max) v = max;
  return v;
}

sharp.cache({
  memory: envInt('SHARP_CACHE_MEMORY_MB', 64, 8, 512),
  files: envInt('SHARP_CACHE_FILES', 8, 1, 1000),
  items: envInt('SHARP_CACHE_ITEMS', 32, 1, 10000),
});

const concRaw = process.env.SHARP_CONCURRENCY;
if (concRaw !== undefined && concRaw !== '') {
  const c = parseInt(String(concRaw), 10);
  if (Number.isFinite(c) && c >= 1) {
    try {
      sharp.concurrency(Math.min(64, c));
    } catch (_) {}
  }
}

module.exports = sharp;
