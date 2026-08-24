'use strict';

const fs = require('fs');
const path = require('path');
const ffmpeg = require('fluent-ffmpeg');
const FileUtil = require('../../utils/fileUtil');
const ffmpegPath = require('../../libsPath/ffmpegPath');
const ffprobePath = require('../../libsPath/ffprobePath');
const photoIndexLvpUtil = require('./photoIndexLvpUtil');
const photoIndexRawUtil = require('./photoIndexRawUtil');

const { encodeGeohash, formatDateYmd, parseIso6709Location, getTimeFromFileName, pickEarliestMs, getImageBasicInfo, getMediaTypeByExt, normalizeLatLon, parseExifDate } = require('./photoIndexUtil');

let exifr;
try {
  exifr = require('exifr');
} catch (_) {
  exifr = null;
}

ffmpeg.setFfmpegPath(ffmpegPath.path);
ffmpeg.setFfprobePath(ffprobePath.path);

async function deleteMissingIndexes({ knex, scanPath }) {
  const root = scanPath ? path.resolve(String(scanPath)) : '';
  if (!root) return;

  const deleteSubtreeByPathPrefix = async targetDir => {
    if (!targetDir) return;
    const prefix = targetDir.endsWith(path.sep) ? targetDir : `${targetDir}${path.sep}`;
    await knex('photo_index')
      .where(qb => {
        qb.where('path', targetDir).orWhere('path', 'like', `${prefix}%`);
      })
      .delete()
      .catch(() => {});
  };

  try {
    fs.statSync(root);
  } catch (_) {
    await deleteSubtreeByPathPrefix(root);
    return;
  }

  let fileDeleteIds = [];

  const flushFileDeletes = async () => {
    if (fileDeleteIds.length === 0) return;
    const ids = fileDeleteIds;
    fileDeleteIds = [];
    await knex('photo_index')
      .whereIn('id', ids)
      .delete()
      .catch(() => {});
  };

  const rootPrefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
  let lastId = 0;
  while (true) {
    const pageSize = 5000;
    const rows = await knex('photo_index')
      .select('id', 'path', 'filename', 'is_file')
      .andWhere(qb => {
        qb.where('path', root).orWhere('path', 'like', `${rootPrefix}%`);
      })
      .andWhere('id', '>', lastId)
      .orderBy('id', 'asc')
      .limit(pageSize)
      .catch(() => []);

    if (!rows || rows.length === 0) break;

    for (const r of rows) {
      const id = r && r.id ? Number(r.id) : 0;
      if (id > lastId) lastId = id;

      const parent = r && r.path ? String(r.path) : '';
      const name = r && r.filename ? String(r.filename) : '';
      if (!parent || !name) {
        if (id) fileDeleteIds.push(id);
        if (fileDeleteIds.length >= 1000) await flushFileDeletes();
        continue;
      }

      const targetPath = path.join(parent, name);
      try {
        fs.statSync(targetPath);
      } catch (err) {
        // 目录或者文件不存在 清理索引
        if (err && err.code && err.code !== 'ENOENT') continue;
        const isFile = Number(r.is_file) === 1;
        if (isFile) {
          if (id) fileDeleteIds.push(id);
          if (fileDeleteIds.length >= 1000) await flushFileDeletes();
        } else {
          if (id) {
            await knex('photo_index')
              .where({ id })
              .delete()
              .catch(() => {});
          }
          await deleteSubtreeByPathPrefix(targetPath);
        }
      }
    }

    if (rows.length < pageSize) break;
    if (fileDeleteIds.length >= 1000) await flushFileDeletes();
  }

  await flushFileDeletes();
}
// 插入目录索引
async function indexOneDirectory({ knex, fullPath, dirPath, filename }) {
  let stat;
  try {
    stat = await fs.promises.stat(fullPath);
  } catch {
    return false;
  }
  if (!stat.isDirectory()) return false;

  const base = {
    path: dirPath,
    filename,
    file_hash: null,
    is_file: 0,
    in_trash: 0,
    in_trash_time: null,
    ctime: new Date(stat.ctimeMs),
    mtime: new Date(stat.mtimeMs),
    original_time: new Date(0),
    original_date: null,
    is_lvp: 0,
    is_merge_lvp: 0,
    live_filename: null,
    size: 0,
    type: 0,
    width: 0,
    height: 0,
    duration: 0,
    latitude: 0,
    longitude: 0,
    geohash: null,
    ext: '',
    raw_filename: null,
    camera: null,
    check_time: Date.now(),
    is_show: '1',
  };

  try {
    await knex('photo_index').insert(base);
    return true;
  } catch {
    return false;
  }
}

async function extractImageMeta(fullPath) {
  if (!exifr) return null;
  const exif = await exifr.parse(fullPath, true).catch(() => null);
  return exif;
}

async function extractVideoMeta(fullPath) {
  const filename = path.basename(fullPath);
  const meta = await new Promise(resolve => {
    ffmpeg.ffprobe(fullPath, (err, data) => {
      if (err) return resolve(null);
      resolve(data);
    });
  });
  if (!meta) return null;

  let width = 0;
  let height = 0;
  let duration = 0;
  let camera = null;
  let latitude = 0;
  let longitude = 0;
  let originalTimeMs = null;

  if (meta.streams && Array.isArray(meta.streams)) {
    const vs = meta.streams.find(s => s && s.codec_type === 'video');
    if (vs) {
      width = Number(vs.width || 0) || 0;
      height = Number(vs.height || 0) || 0;
    }
  }
  if (meta.format) {
    duration = Number(meta.format.duration || 0) || 0;
    const tags = meta.format.tags || {};
    if (tags['com.apple.quicktime.model']) camera = String(tags['com.apple.quicktime.model']);
    const appleCreate = tags['com.apple.quicktime.creationdate'];
    const createTime = tags['creation_time'];
    if (appleCreate) {
      originalTimeMs = parseExifDate(appleCreate);
    } else if (createTime && !String(createTime).startsWith('1970-01-01')) {
      originalTimeMs = parseExifDate(createTime);
    }

    const appleGps = tags['com.apple.quicktime.location.ISO6709'];
    if (appleGps) {
      const gps = parseIso6709Location(appleGps);
      if (gps) {
        latitude = gps.latitude;
        longitude = gps.longitude;
      }
    }
    let androidGps = tags['location'] || tags['location-eng'];
    if (androidGps && (!latitude || !longitude)) {
      androidGps = String(androidGps).replace('/', '');
      const gps = parseIso6709Location(androidGps);
      if (gps) {
        latitude = gps.latitude;
        longitude = gps.longitude;
      }
    }
  }

  originalTimeMs = getTimeFromFileName(originalTimeMs, filename);

  return { width, height, duration, camera, latitude, longitude, originalTimeMs };
}

async function indexOneFile({ knex, fullPath, dirPath, filename, ext }) {
  const mediaType = getMediaTypeByExt(ext);
  if (mediaType !== 1 && mediaType !== 2) {
    console.log('不支持的文件类型', ext);
    return false;
  }

  const isRaw = mediaType === 1 && photoIndexRawUtil.isRawExt(ext);
  if (isRaw) {
    const rawRes = await photoIndexRawUtil.handleRawFile({ knex, dirPath, filename });
    if (rawRes && rawRes.handled) {
      return false;
    }
  }

  const isCandidateLvpVideo = mediaType === 2 && (ext === '.mp4' || ext === '.mov');
  if (isCandidateLvpVideo) {
    const linked = await knex('photo_index').where({ path: dirPath, live_filename: filename }).first('id');
    if (linked && linked.id) {
      return false;
    }
  }

  const exists = await knex('photo_index').where({ path: dirPath, filename }).first('id', 'path', 'live_filename', 'raw_filename');
  if (exists && exists.id) {
    // 如果live_filename或raw_filename非空 检查对应文件是否还存在,不存在清空此字段
    if (exists.live_filename && !fs.existsSync(path.join(exists.path, exists.live_filename))) {
      await knex('photo_index').where({ id: exists.id }).update({ live_filename: null });
    }
    if (exists.raw_filename && !fs.existsSync(path.join(exists.path, exists.raw_filename))) {
      await knex('photo_index').where({ id: exists.id }).update({ raw_filename: null });
    }
    return false;
  }

  let stat;
  try {
    stat = await fs.promises.stat(fullPath);
  } catch {
    console.log('无法获取文件统计信息', filename);
    return false;
  }

  const fileHash = await FileUtil.getFileHash(fullPath);
  const base = {
    path: dirPath,
    filename,
    file_hash: fileHash,
    is_file: 1,
    in_trash: 0,
    in_trash_time: null,
    ctime: new Date(stat.ctimeMs),
    mtime: new Date(stat.mtimeMs),
    size: stat.size,
    type: mediaType,
    is_lvp: 0,
    is_merge_lvp: 0,
    width: 0,
    height: 0,
    duration: 0,
    latitude: 0,
    longitude: 0,
    geohash: null,
    geohash6: null,
    geohash5: null,
    geohash4: null,
    geohash3: null,
    geohash2: null,
    ext: ext || '',
    raw_filename: null,
    live_filename: null,
    camera: null,
    check_time: Date.now(),
    is_show: '1',
  };

  let originalTimeMs = null;
  let latitude = 0;
  let longitude = 0;

  if (mediaType === 1) {
    if (!isRaw) {
      const imageMeta = await extractImageMeta(fullPath).catch(() => null);
      if (imageMeta) {
        originalTimeMs =
          parseExifDate(imageMeta.DateTimeOriginal) ||
          parseExifDate(imageMeta.CreateDate) ||
          parseExifDate(imageMeta.ModifyDate) ||
          parseExifDate(imageMeta.DateCreated) ||
          parseExifDate(imageMeta.CreationDate) ||
          null;
        if (imageMeta.Model) base.camera = String(imageMeta.Model);

        const rawLat = imageMeta.latitude ?? imageMeta.GPSLatitude ?? imageMeta.gpsLatitude;
        const rawLon = imageMeta.longitude ?? imageMeta.GPSLongitude ?? imageMeta.gpsLongitude;
        const gps = normalizeLatLon(rawLat, rawLon);
        latitude = gps.latitude;
        longitude = gps.longitude;
        photoIndexLvpUtil.applyMergeLvpFlags(base, imageMeta);
      }
      const wh = await getImageBasicInfo(fullPath);
      base.width = wh.width;
      base.height = wh.height;
    }
  } else if (mediaType === 2) {
    const v = await extractVideoMeta(fullPath).catch(() => null);
    if (v) {
      if (Number.isFinite(v.duration) && v.duration > 0) base.duration = v.duration;
      if (Number.isFinite(v.width) && v.width > 0) base.width = v.width;
      if (Number.isFinite(v.height) && v.height > 0) base.height = v.height;
      if (v.camera) base.camera = v.camera;
      if (v.originalTimeMs) originalTimeMs = v.originalTimeMs;
      if (v.latitude || v.longitude) {
        latitude = v.latitude;
        longitude = v.longitude;
      }
    }
  } else {
    console.log('不支持的文件类型', ext);
    return false;
  }

  originalTimeMs = getTimeFromFileName(originalTimeMs, filename);
  if (!originalTimeMs) originalTimeMs = pickEarliestMs(stat);

  const nowYear = new Date().getFullYear();
  const oy = new Date(originalTimeMs).getFullYear();
  if (!oy || oy < 1970 || oy > nowYear + 1) {
    originalTimeMs = pickEarliestMs(stat);
  }

  base.original_time = new Date(originalTimeMs);
  base.original_date = formatDateYmd(originalTimeMs);

  const gpsFinal = normalizeLatLon(latitude, longitude);
  base.latitude = gpsFinal.latitude;
  base.longitude = gpsFinal.longitude;
  if (base.latitude && base.longitude) {
    const geohash = encodeGeohash(base.latitude, base.longitude, 8);
    base.geohash = geohash;
    base.geohash6 = geohash.length >= 6 ? geohash.substring(0, 6) : geohash;
    base.geohash5 = geohash.length >= 5 ? geohash.substring(0, 5) : geohash;
    base.geohash4 = geohash.length >= 4 ? geohash.substring(0, 4) : geohash;
    base.geohash3 = geohash.length >= 3 ? geohash.substring(0, 3) : geohash;
    base.geohash2 = geohash.length >= 2 ? geohash.substring(0, 2) : geohash;
  }

  let pairedVideo = null;
  let rawIndexIdsToDelete = [];

  if (mediaType === 1) {
    const lvpRes = await photoIndexLvpUtil.handleSeparatedLvpForPhoto({
      knex,
      dirPath,
      filename,
      ext,
      photoOriginalTimeMs: originalTimeMs,
      base,
    });
    pairedVideo = lvpRes && lvpRes.pairedVideo ? lvpRes.pairedVideo : null;

    if (ext === '.jpg' || ext === '.jpeg' || ext === '.heic' || ext === '.heif') {
      const rawRes = await photoIndexRawUtil.attachRawToPhotoBase({
        knex,
        dirPath,
        filename,
        base,
      });
      rawIndexIdsToDelete = rawRes.rawIndexIdsToDelete || [];
    }
  }

  if (mediaType === 2) {
    const lvpRes = await photoIndexLvpUtil.handleSeparatedLvpForVideo({
      knex,
      dirPath,
      filename,
      ext,
      videoOriginalTimeMs: originalTimeMs,
      duration: base.duration,
    });
    if (lvpRes && lvpRes.matched) {
      return false;
    }
  }

  let insertedOrUpdated = false;
  try {
    await knex('photo_index').insert(base);
    insertedOrUpdated = true;
  } catch (err) {
    console.log(err);
    try {
      const existed = await knex('photo_index').where({ path: dirPath, filename, is_file: 1 }).orderBy('id', 'asc').first('id');
      if (existed && existed.id) {
        await knex('photo_index').where({ id: existed.id }).update(base);
        insertedOrUpdated = true;
      }
    } catch {
      console.log('索引照片失败', filename);
      insertedOrUpdated = false;
    }
  }

  if (insertedOrUpdated && pairedVideo && pairedVideo.id) {
    await knex('photo_index')
      .where({ id: pairedVideo.id })
      .delete()
      .catch(() => {});
  }

  if (insertedOrUpdated && Array.isArray(rawIndexIdsToDelete) && rawIndexIdsToDelete.length > 0) {
    await knex('photo_index')
      .whereIn('id', rawIndexIdsToDelete)
      .delete()
      .catch(() => {});
  }
  return insertedOrUpdated;
}

module.exports = {
  deleteMissingIndexes,
  indexOneDirectory,
  indexOneFile,
  extractImageMeta,
  extractVideoMeta,
};
