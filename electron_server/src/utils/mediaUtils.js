'use strict';

/**
 * 媒体文件时间工具：统一从照片/视频中获取拍摄或创建时间（original_time），
 * 供加密空间上传、相册索引等模块复用，便于维护。
 */

const fs = require('fs');
const path = require('path');
const config = require('../config/config');
const videoFfprobeUtil = require('./videoFfprobeUtil');
const { getTimeFromFileName, pickEarliestMs, parseExifDate } = require('../workers/photoIndex/photoIndexUtil');

let exifr;
try {
  exifr = require('exifr');
} catch (_) {
  exifr = null;
}

/**
 * 从 ffprobe 返回的 meta 中提取拍摄/创建时间戳（毫秒）
 * @param {object} meta - videoFfprobeUtil.probeVideo 返回的 meta 字段
 * @returns {number|null} 毫秒时间戳，无则 null
 */
function extractVideoOriginalTimeMs(meta) {
  const m = meta && typeof meta === 'object' ? meta : null;
  if (!m) return null;
  const tags = (m.format && m.format.tags) || null;
  const candidates = [];
  if (tags && typeof tags === 'object') {
    for (const k of ['creation_time', 'com.apple.quicktime.creationdate', 'date', 'Date']) {
      if (tags[k]) candidates.push(tags[k]);
    }
  }
  const streams = Array.isArray(m.streams) ? m.streams : [];
  for (const s of streams) {
    const t = s && s.tags ? s.tags : null;
    if (t && typeof t === 'object') {
      for (const k of ['creation_time', 'com.apple.quicktime.creationdate', 'date', 'Date']) {
        if (t[k]) candidates.push(t[k]);
      }
    }
  }
  for (const c of candidates) {
    const str = String(c).trim();
    if (str.startsWith('1970-01-01')) continue;
    const t = parseExifDate(c);
    if (Number.isFinite(t) && t > 0) return t;
  }
  return null;
}

/**
 * 创建时间与修改时间中较早者（毫秒，向上取整），用于「解析时间晚于当前时间」时的回退。
 */
function pickEarliestBirthOrMtimeMs(stat) {
  const list = [stat.birthtimeMs, stat.mtimeMs].filter(v => Number.isFinite(v));
  if (list.length === 0) return Date.now();
  return Math.ceil(Math.min(...list));
}

/**
 * 获取媒体文件拍摄/创建时间（优先 EXIF/元数据，其次文件名，最后文件属性）
 * @param {string} filePath - 文件绝对路径
 * @param {{ filename?: string }} [options] - filename 可选，用于文件名回退（若临时文件与原始名不同可传入原始文件名）
 * @returns {Promise<number>} 毫秒时间戳，保证返回有效数字
 */
async function getFileTime(filePath, options = {}) {
  const defaultTime = Date.now();
  let stat;
  try {
    stat = await fs.promises.stat(filePath);
  } catch (err) {
    return defaultTime;
  }
  if (!stat || !stat.isFile()) return defaultTime;

  const ext = path.extname(filePath).toLowerCase();
  const filename = options.filename && String(options.filename).trim() ? options.filename : path.basename(filePath);
  const imgList = Array.isArray(config.imgTypeList) ? config.imgTypeList : [];
  const rawList = Array.isArray(config.rawImgTypeList) ? config.rawImgTypeList : [];
  const videoList = Array.isArray(config.videoTypeList) ? config.videoTypeList : [];
  const isImage = imgList.includes(ext) || rawList.includes(ext);
  const isVideo = videoList.includes(ext);

  let originalTimeMs = null;

  if (isImage && exifr) {
    try {
      const exif = await exifr.parse(filePath, true).catch(() => null);
      const dateCandidate = exif && (exif.DateTimeOriginal || exif.CreateDate || exif.ModifyDate || exif.DateCreated);
      originalTimeMs = parseExifDate(dateCandidate);
    } catch (_) {}
  } else if (isVideo) {
    try {
      const probe = await videoFfprobeUtil.probeVideo(filePath).catch(() => null);
      originalTimeMs = extractVideoOriginalTimeMs(probe && probe.meta);
    } catch (_) {}
  }

  originalTimeMs = getTimeFromFileName(originalTimeMs, filename) || null;
  if (!originalTimeMs) originalTimeMs = pickEarliestMs(stat);

  const nowMs = Date.now();
  if (Number.isFinite(originalTimeMs) && originalTimeMs > nowMs) {
    originalTimeMs = pickEarliestBirthOrMtimeMs(stat);
  }

  const nowYear = new Date().getFullYear();
  const y = new Date(originalTimeMs).getFullYear();
  if (!Number.isFinite(originalTimeMs) || originalTimeMs <= 0 || !y || y < 1970 || y > nowYear + 1) {
    originalTimeMs = pickEarliestMs(stat);
  }

  return Math.ceil(originalTimeMs);
}

module.exports = {
  getFileTime,
  extractVideoOriginalTimeMs,
};
