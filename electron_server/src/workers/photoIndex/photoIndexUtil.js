const fs = require('fs');
const path = require('path');
const sharp = require('../../utils/sharpConfigured');
const FileUtil = require('../../utils/fileUtil');
const config = require('../../config/config');
const geohash = require('ngeohash');

try {
  sharp.cache(false);
  sharp.concurrency(1);
} catch (_) {}

/**
 * geohash 编码（base32），仅用于写入索引表以便后续按区域聚合/筛选。
 * precision=8 时，约为几十米级别（与纬度相关），符合“仅保留8位即可”的需求。
 */
function encodeGeohash(latitude, longitude, precision = 8) {
  let geohashStr = geohash.encode(latitude, longitude, precision);
  return geohashStr;
}

function pad2(n) {
  return n >= 10 ? String(n) : `0${n}`;
}

/**
 * 把毫秒时间戳格式化为 YYYY-MM-DD，用于 photo_index.original_date（便于按日查询）。
 */
function formatDateYmd(ms) {
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/**
 * 解析各种可能的拍摄时间输入，统一返回“毫秒时间戳”：
 * - Date
 * - number(毫秒)
 * - string（兼容 EXIF 常见的 `YYYY:MM:DD HH:mm:ss`，以及 ISO 字符串）
 */
function parseExifDate(value) {
  if (!value) return null;
  if (value instanceof Date) {
    const t = value.getTime();
    return Number.isFinite(t) ? t : null;
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) ? new Date(value).getTime() : null;
  }
  const s = String(value).trim();
  if (!s) return null;

  const m = s.match(/^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
  if (m) {
    const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
    const t = d.getTime();
    return Number.isFinite(t) ? t : null;
  }

  const t = new Date(s).getTime();
  return Number.isFinite(t) ? t : null;
}

/**
 * 由 YYYYMMDD 与 HHmmss 两段数字构造本地时间的毫秒时间戳；含年月日与范围校验。
 */
function buildMsFromYmdAndHms(datePart, timePart) {
  try {
    if (!datePart || !timePart || datePart.length !== 8 || timePart.length !== 6) return null;
    const y = Number(datePart.substring(0, 4));
    const mo = Number(datePart.substring(4, 6));
    const d = Number(datePart.substring(6, 8));
    const hh = Number(timePart.substring(0, 2));
    const mm = Number(timePart.substring(2, 4));
    const ss = Number(timePart.substring(4, 6));
    if (![y, mo, d, hh, mm, ss].every(Number.isFinite)) return null;
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || hh > 23 || mm > 59 || ss > 59) return null;
    const date = new Date(y, mo - 1, d, hh, mm, ss);
    const nowYear = new Date().getFullYear();
    const yy = date.getFullYear();
    if (!yy || yy < 1970 || yy > nowYear) return null;
    const ts = date.getTime();
    return Number.isFinite(ts) ? ts : null;
  } catch {
    return null;
  }
}

/** 提取出的媒体时间不得晚于当前时刻，避免误解析 */
function isMediaTimeNotInFutureMs(ms) {
  return Number.isFinite(ms) && ms > 0 && ms <= Date.now();
}

/**
 * 从文件名中按不同正则提取日期/时间信息，并返回毫秒时间戳。
 * 旧项目中支持的文件名样式较多，这里尽量保持兼容：
 * - 20170928
 * - 2018-08-07
 * - 20210509213715 / _20240509213715
 * - _20180807_105942
 * - _20250430_202326（下划线分隔日期与时间，共 16 字符）
 * - 2022_06_30_11_31_47
 * - 10/13位时间戳等
 */
function extractTimestampFromFilename(datePattern, filename) {
  try {
    const match = String(filename || '').match(datePattern);
    if (!match) return null;
    const dateString = match[0];
    let date = null;

    // _YYYYMMDD_HHmmss：完整匹配为 16 字符，须用捕获组拼日期，否则会落到后面的 13 位数字误判为时间戳
    if (match[1] && match[2] && dateString.length === 16 && dateString[0] === '_' && dateString[9] === '_') {
      const fromGroups = buildMsFromYmdAndHms(match[1], match[2]);
      if (fromGroups != null) return isMediaTimeNotInFutureMs(fromGroups) ? fromGroups : null;
    }

    if (dateString.length === 8) {
      const year = dateString.substring(0, 4);
      const month = dateString.substring(4, 6);
      const day = dateString.substring(6, 8);
      date = new Date(Number(year), Number(month) - 1, Number(day));
    } else if (dateString.length === 10 && dateString[4] === '-' && dateString[7] === '-') {
      date = new Date(dateString);
    } else if (dateString.length === 13) {
      date = new Date(Number(dateString));
    } else if (dateString.length === 10) {
      date = new Date(Number(dateString) * 1000);
    } else if (dateString.length === 15 && dateString.startsWith('_')) {
      const [, datePart, timePart] = match;
      const dateTimeStr = `${datePart.substring(0, 4)}-${datePart.substring(4, 6)}-${datePart.substring(6, 8)} ${timePart.substring(0, 2)}:${timePart.substring(2, 4)}:${timePart.substring(4, 6)}`;
      date = new Date(dateTimeStr);
    } else if (dateString.length === 14) {
      const [, datePart, timePart] = match;
      const dateTimeStr = `${datePart.substring(0, 4)}-${datePart.substring(4, 6)}-${datePart.substring(6, 8)} ${timePart.substring(0, 2)}:${timePart.substring(2, 4)}:${timePart.substring(4, 6)}`;
      date = new Date(dateTimeStr);
    } else if (dateString.length === 19 && dateString[4] === '_' && dateString[7] === '_' && dateString[10] === '_' && dateString[13] === '_' && dateString[16] === '_') {
      const dateTimeStr = `${dateString.substring(0, 4)}-${dateString.substring(5, 7)}-${dateString.substring(
        8,
        10
      )} ${dateString.substring(11, 13)}:${dateString.substring(14, 16)}:${dateString.substring(17, 19)}`;
      date = new Date(dateTimeStr);
    }

    if (!date) return null;
    const nowYear = new Date().getFullYear();
    const y = date.getFullYear();
    if (!y || y < 1970 || y > nowYear) return null;
    const ts = date.getTime();
    if (!Number.isFinite(ts)) return null;
    return isMediaTimeNotInFutureMs(ts) ? ts : null;
  } catch {
    return null;
  }
}

/**
 * 尝试从文件名中提取拍摄时间作为回退：
 * - 如果 originalTimeMsOrValue 已有值，会先尝试 parseExifDate 解析；
 * - 如果解析失败，则按多个正则逐个尝试，从文件名提取。
 *
 * 返回：毫秒时间戳或 null（表示未能提取到合规时间）。
 */
function getTimeFromFileName(originalTimeMsOrValue, filename) {
  let originalTime = parseExifDate(originalTimeMsOrValue);
  if (originalTime && !isMediaTimeNotInFutureMs(originalTime)) originalTime = null;
  // 手机相机常见 IMG_YYYYMMDD_HHmmss…，应优先于文件名中的长数字串（易被误判为毫秒时间戳）
  if (!originalTime) {
    const imgM = String(filename || '').match(/^IMG_(\d{8})_(\d{6})(?!\d)/i);
    if (imgM) originalTime = buildMsFromYmdAndHms(imgM[1], imgM[2]);
  }
  if (!originalTime) {
    const datePattern = /(\d{4}-\d{2}-\d{2})/;
    originalTime = extractTimestampFromFilename(datePattern, filename);
  }
  if (!originalTime) {
    const datePattern = /_(\d{8})_(\d{6})/;
    originalTime = extractTimestampFromFilename(datePattern, filename);
  }
  if (!originalTime) {
    const datePattern = /_(\d{8})(\d{6})(?!\d)/;
    originalTime = extractTimestampFromFilename(datePattern, filename);
  }
  if (!originalTime) {
    // 须为独立数字段，避免 QQ1793149577526473083_0.jpg 等长 ID 中被截出一段误判为 Ymd+Hms
    const datePattern = /(?<!\d)(\d{8})(\d{6})(?!\d)/;
    originalTime = extractTimestampFromFilename(datePattern, filename);
  }
  if (!originalTime) {
    // 仅采纳「整段」10/13 位 unix 毫秒/秒，长度超出或嵌入更长数字串的一律忽略
    const datePattern = /(?<!\d)(\d{13}|\d{10})(?!\d)/;
    originalTime = extractTimestampFromFilename(datePattern, filename);
  }
  if (!originalTime) {
    const datePattern = /(\d{4})(\d{2})(\d{2})/;
    originalTime = extractTimestampFromFilename(datePattern, filename);
  }
  if (!originalTime) {
    const datePattern = /(\d{4})_(\d{2})_(\d{2})_(\d{2})_(\d{2})_(\d{2})/;
    originalTime = extractTimestampFromFilename(datePattern, filename);
  }

  if (originalTime) {
    const nowYear = new Date().getFullYear();
    const y = new Date(originalTime).getFullYear();
    if (!y || y < 1970 || y > nowYear) return null;
    if (!isMediaTimeNotInFutureMs(originalTime)) return null;
  }
  return originalTime || null;
}

/**
 * 从文件的几个常见时间里，选取“最早”的时间作为回退拍摄时间：
 * - birthtimeMs / mtimeMs / atimeMs / ctimeMs
 */
function pickEarliestMs(stat) {
  const list = [stat.birthtimeMs, stat.mtimeMs, stat.atimeMs, stat.ctimeMs].filter(v => Number.isFinite(v));
  if (list.length === 0) return Date.now();
  return Math.ceil(Math.min(...list));
}

/**
 * 解析 ISO6709 GPS 字符串（常见于 iOS QuickTime tag）：
 * - 形如：`-38.3268+176.3038+365.983`
 * - 或：`+39.1234+116.1234/`
 *
 * 返回：{ latitude, longitude } 或 null
 */
function parseIso6709Location(str) {
  const s = String(str || '').trim();
  if (!s) return null;
  const signIdx = [];
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '+' || s[i] === '-') signIdx.push(i);
  }
  if (signIdx.length < 2) return null;
  const latStr = s.substring(signIdx[0], signIdx[1]);
  const lonStr = signIdx.length >= 3 ? s.substring(signIdx[1], signIdx[2]) : s.substring(signIdx[1]);
  const lat = Number(latStr);
  const lon = Number(lonStr);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
  return { latitude: lat, longitude: lon };
}

/**
 * 获取图片的基础宽高信息（用于 photo_index.width/height）。
 * 这里不依赖 EXIF，只取像素尺寸，失败时返回 0。
 */
async function getImageBasicInfo(fullPath) {
  try {
    const metadata = await sharp(fullPath, { failOnError: false }).metadata();
    const width = metadata && metadata.width ? Number(metadata.width) : 0;
    const height = metadata && metadata.height ? Number(metadata.height) : 0;
    return { width: width || 0, height: height || 0 };
  } catch {
    return { width: 0, height: 0 };
  }
}

/**
 * 判断扩展名是否属于“需要建立照片索引”的媒体类型：
 * - 图片（含 RAW）
 * - 视频
 */
function isMediaFileExt(ext) {
  const e = String(ext || '').toLowerCase();
  if (!e) return false;
  return (config.imgTypeList && config.imgTypeList.includes(e)) || (config.rawImgTypeList && config.rawImgTypeList.includes(e)) || (config.videoTypeList && config.videoTypeList.includes(e));
}

/**
 * 扩展名 => 索引表 type 字段
 * - 1：图片（含 RAW）
 * - 2：视频
 * - 0：其它（不处理）
 */
function getMediaTypeByExt(ext) {
  const e = String(ext || '').toLowerCase();
  if (config.imgTypeList.includes(e) || config.rawImgTypeList.includes(e)) return 1;
  if (config.videoTypeList.includes(e)) return 2;
  return 0;
}

/**
 * 深度遍历 rootPath 下的媒体文件（不依赖 OS watcher）：
 * - 跳过系统文件（.DS_Store 等）和隐藏文件（以 . 开头）
 * - 仅回调媒体文件（图片/RAW/视频）
 *
 * onEntry({ fullPath, dirPath, filename, ext })
 */
async function walkMediaFiles(rootPath, onEntry) {
  const cachePath = typeof config.getCachePath === 'function' ? config.getCachePath() : '';
  const cachePrefix = cachePath && cachePath.endsWith(path.sep) ? cachePath : cachePath ? `${cachePath}${path.sep}` : '';

  const resolvedRoot = rootPath ? path.resolve(rootPath) : '';
  // 跳过缓存目录
  if (cachePath && (resolvedRoot === cachePath || resolvedRoot.startsWith(cachePrefix))) {
    return true;
  }

  const stack = [rootPath];
  while (stack.length > 0) {
    const current = stack.pop();
    const resolvedCurrent = current ? path.resolve(current) : '';
    if (cachePath && (resolvedCurrent === cachePath || resolvedCurrent.startsWith(cachePrefix))) {
      continue;
    }
    let entries;
    try {
      entries = await fs.promises.readdir(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const ent of entries) {
      const name = ent.name;
      if (FileUtil.isSystemFile(name)) continue;
      const fullPath = path.join(current, name);
      const resolvedFull = path.resolve(fullPath);
      if (cachePath && (resolvedFull === cachePath || resolvedFull.startsWith(cachePrefix))) {
        continue;
      }
      if (ent.isDirectory()) {
        stack.push(fullPath);
        continue;
      }
      if (!ent.isFile()) continue;
      if (FileUtil.isHideFile(name)) continue;
      if (FileUtil.isTemporaryOrDownloadingFile(name)) continue;
      const ext = path.extname(name).toLowerCase();
      if (!isMediaFileExt(ext)) continue;
      const res = await onEntry({ fullPath, dirPath: current, filename: name, ext });
      if (res === false) {
        return false;
      }
    }
  }
  return true;
}

async function walkPhotoEntries(rootPath, { onDirectory, onMediaFile }) {
  const cachePath = typeof config.getCachePath === 'function' ? config.getCachePath() : '';
  const cachePrefix = cachePath && cachePath.endsWith(path.sep) ? cachePath : cachePath ? `${cachePath}${path.sep}` : '';

  const resolvedRoot = rootPath ? path.resolve(rootPath) : '';
  if (cachePath && (resolvedRoot === cachePath || resolvedRoot.startsWith(cachePrefix))) {
    return true;
  }

  const stack = [rootPath];
  while (stack.length > 0) {
    const current = stack.pop();
    const resolvedCurrent = current ? path.resolve(current) : '';
    if (cachePath && (resolvedCurrent === cachePath || resolvedCurrent.startsWith(cachePrefix))) {
      continue;
    }
    let dir;
    try {
      dir = await fs.promises.opendir(current);
    } catch {
      continue;
    }
    try {
      for await (const ent of dir) {
        const name = ent && ent.name ? String(ent.name) : '';
        if (!name) continue;
        if (FileUtil.isSystemFile(name)) continue;
        const fullPath = path.join(current, name);
        const resolvedFull = path.resolve(fullPath);
        if (cachePath && (resolvedFull === cachePath || resolvedFull.startsWith(cachePrefix))) {
          continue;
        }

        if (ent.isDirectory()) {
          if (typeof onDirectory === 'function') {
            const res = await onDirectory({ fullPath, dirPath: current, filename: name });
            if (res === false) return false;
          }
          stack.push(fullPath);
          continue;
        }

        if (!ent.isFile()) continue;
        if (FileUtil.isHideFile(name)) continue;
        if (FileUtil.isTemporaryOrDownloadingFile(name)) continue;
        const ext = path.extname(name).toLowerCase();
        if (!isMediaFileExt(ext)) continue;
        if (typeof onMediaFile === 'function') {
          const res = await onMediaFile({ fullPath, dirPath: current, filename: name, ext });
          if (res === false) return false;
        }
      }
    } finally {
      await dir.close().catch(() => {});
    }
  }

  return true;
}

/**
 * 经纬度有效性校验与归一化：
 * - 任一非数字 => (0,0)
 * - 超出范围 => (0,0)
 * - (0,0) 视为无效
 */
function normalizeLatLon(latitude, longitude) {
  const lat = Number(latitude);
  const lon = Number(longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return { latitude: 0, longitude: 0 };
  if (lat === 0 && lon === 0) return { latitude: 0, longitude: 0 };
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return { latitude: 0, longitude: 0 };
  return { latitude: lat, longitude: lon };
}

module.exports = {
  encodeGeohash,
  formatDateYmd,
  parseIso6709Location,
  getTimeFromFileName,
  pickEarliestMs,
  getImageBasicInfo,
  walkMediaFiles,
  walkPhotoEntries,
  getMediaTypeByExt,
  normalizeLatLon,
  parseExifDate,
};
