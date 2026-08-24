const fs = require('fs');
const path = require('path');
const geohash = require('ngeohash');
const Logger = require('../../../../utils/logger');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const { parseExifDate, getTimeFromFileName, pickEarliestMs, getImageBasicInfo, normalizeLatLon } = require('../../../../workers/photoIndex/photoIndexUtil');
const photoMapService = require('../map/photoMapService');

let exifr;
try {
  exifr = require('exifr');
} catch (_) {
  exifr = null;
}

function asNumber(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function toISOStringOrNull(ms) {
  const t = asNumber(ms);
  if (!t) return null;
  try {
    return new Date(t).toISOString();
  } catch {
    return null;
  }
}

function pickExifValue(exif, keys) {
  if (!exif) return null;
  for (const k of keys) {
    const v = exif[k];
    if (v === undefined || v === null) continue;
    if (typeof v === 'string' && !v.trim()) continue;
    return v;
  }
  return null;
}

function buildExifSummary(exif) {
  if (!exif) return null;
  const res = {};
  const add = (key, v) => {
    if (v === undefined || v === null) return;
    if (typeof v === 'string' && !v.trim()) return;
    res[key] = v;
  };

  add('make', pickExifValue(exif, ['Make']));
  add('model', pickExifValue(exif, ['Model']));
  add('lensModel', pickExifValue(exif, ['LensModel', 'Lens']));
  add('fNumber', pickExifValue(exif, ['FNumber']));
  add('apertureValue', pickExifValue(exif, ['ApertureValue']));
  add('exposureTime', pickExifValue(exif, ['ExposureTime']));
  add('shutterSpeedValue', pickExifValue(exif, ['ShutterSpeedValue']));
  add('exposureProgram', pickExifValue(exif, ['ExposureProgram']));
  add('exposureCompensation', pickExifValue(exif, ['ExposureCompensation', 'ExposureBiasValue']));
  add('iso', pickExifValue(exif, ['ISO', 'ISOSpeedRatings']));
  add('focalLength', pickExifValue(exif, ['FocalLength']));
  add('focalLengthIn35mm', pickExifValue(exif, ['FocalLengthIn35mmFormat']));
  add('flash', pickExifValue(exif, ['Flash']));
  add('whiteBalance', pickExifValue(exif, ['WhiteBalance']));
  add('meteringMode', pickExifValue(exif, ['MeteringMode']));
  add('software', pickExifValue(exif, ['Software']));
  add('orientation', pickExifValue(exif, ['Orientation']));

  const dt = pickExifValue(exif, ['DateTimeOriginal', 'CreateDate', 'ModifyDate', 'DateCreated', 'CreationDate']);
  add('dateTime', dt);

  const lat = pickExifValue(exif, ['latitude', 'GPSLatitude', 'gpsLatitude', 'Latitude']);
  const lng = pickExifValue(exif, ['longitude', 'GPSLongitude', 'gpsLongitude', 'Longitude']);
  const gps = normalizeLatLon(lat, lng);
  if (gps.latitude && gps.longitude) {
    add('latitude', gps.latitude);
    add('longitude', gps.longitude);
  }

  return Object.keys(res).length > 0 ? res : null;
}

async function readExif(fullPath) {
  if (!exifr) return null;
  return exifr.parse(fullPath, true).catch(() => null);
}

async function readFileDetail(fullPath, filename) {
  let stat;
  try {
    stat = await fs.promises.stat(fullPath);
  } catch {
    return null;
  }

  const size = asNumber(stat.size) || 0;
  const mtimeMs = asNumber(stat.mtimeMs);
  const ctimeMs = asNumber(stat.ctimeMs);
  const birthtimeMs = asNumber(stat.birthtimeMs);
  const createTimeMs = birthtimeMs || ctimeMs || null;

  const wh = await getImageBasicInfo(fullPath);
  const exif = await readExif(fullPath);

  let lat = 0;
  let lng = 0;
  let camera = null;
  let originalTimeMs = null;

  if (exif) {
    originalTimeMs =
      parseExifDate(exif.DateTimeOriginal) || parseExifDate(exif.CreateDate) || parseExifDate(exif.ModifyDate) || parseExifDate(exif.DateCreated) || parseExifDate(exif.CreationDate) || null;
    if (exif.Model) camera = String(exif.Model);

    const rawLat = exif.latitude ?? exif.GPSLatitude ?? exif.gpsLatitude;
    const rawLng = exif.longitude ?? exif.GPSLongitude ?? exif.gpsLongitude;
    const gps = normalizeLatLon(rawLat, rawLng);
    lat = gps.latitude;
    lng = gps.longitude;
  }

  originalTimeMs = getTimeFromFileName(originalTimeMs, filename);
  if (!originalTimeMs) originalTimeMs = pickEarliestMs(stat);

  const nowYear = new Date().getFullYear();
  const oy = new Date(originalTimeMs).getFullYear();
  if (!oy || oy < 1970 || oy > nowYear + 1) {
    originalTimeMs = pickEarliestMs(stat);
  }

  return {
    size,
    width: wh.width || 0,
    height: wh.height || 0,
    mtime: toISOStringOrNull(mtimeMs),
    ctime: toISOStringOrNull(ctimeMs),
    createTime: toISOStringOrNull(createTimeMs),
    originalTime: toISOStringOrNull(originalTimeMs),
    camera,
    latitude: lat,
    longitude: lng,
    exif: buildExifSummary(exif),
    exifRaw: exif || null,
  };
}

class PhotoPropertiesController {
  async get(req, res) {
    try {
      const rawPath = (req.body && req.body.path ? String(req.body.path) : '').trim();
      if (!rawPath) {
        return ResponseUtil.error(req, res, 'common.ERROR', 400);
      }

      const fullpath = path.normalize(rawPath);
      const dirPath = path.dirname(fullpath);
      const filename = path.basename(fullpath);
      if (!dirPath || !filename) {
        return ResponseUtil.error(req, res, 'common.ERROR', 400);
      }

      const indexRow = await req
        .dbPhoto('photo_index')
        .where({ path: dirPath, filename })
        .first('id', 'path', 'filename', 'file_hash', 'size', 'width', 'height', 'ctime', 'mtime', 'original_time', 'camera', 'latitude', 'longitude', 'geohash', 'ext', 'type', 'live_filename', 'raw_filename')
        .catch(() => null);

      const fileDetail = await readFileDetail(fullpath, filename);
      if (!fileDetail) {
        return ResponseUtil.error(req, res, 'common.ERROR', 404);
      }

      const latFromIndex = indexRow ? asNumber(indexRow.latitude) || 0 : 0;
      const lngFromIndex = indexRow ? asNumber(indexRow.longitude) || 0 : 0;
      const gpsFinal = normalizeLatLon(fileDetail.latitude || latFromIndex, fileDetail.longitude || lngFromIndex);
      const hasGps = gpsFinal && gpsFinal.latitude && gpsFinal.longitude;

      let locale = '';
      try {
        locale = typeof req.getLocale === 'function' ? String(req.getLocale() || '') : '';
      } catch (_) {
        locale = '';
      }

      let geo = '';
      if (hasGps) {
        const hash = (indexRow && indexRow.geohash ? String(indexRow.geohash) : '') || geohash.encode(gpsFinal.latitude, gpsFinal.longitude, 8);
        if (hash) {
          geo = await photoMapService.getLocationStr({ dbGeo: req.dbGeo, locale }, hash).catch(() => '');
        }
      }

      const data = {
        fullpath,
        dirPath,
        filename,
        size: fileDetail.size,
        width: fileDetail.width,
        height: fileDetail.height,
        createTime: fileDetail.createTime,
        ctime: fileDetail.ctime,
        mtime: fileDetail.mtime,
        originalTime: fileDetail.originalTime,
        exif: fileDetail.exif,
        latitude: gpsFinal.latitude,
        longitude: gpsFinal.longitude,
        geo,
        photoIndex: indexRow
          ? {
              id: indexRow.id,
              fileHash: indexRow.file_hash,
              camera: indexRow.camera,
              geohash: indexRow.geohash,
              ext: indexRow.ext,
              type: indexRow.type,
              liveFilename: indexRow.live_filename,
              rawFilename: indexRow.raw_filename,
              originalTime: indexRow.original_time ? new Date(indexRow.original_time).toISOString() : null,
              ctime: indexRow.ctime ? new Date(indexRow.ctime).toISOString() : null,
              mtime: indexRow.mtime ? new Date(indexRow.mtime).toISOString() : null,
            }
          : null,
      };

      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('photo properties error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }
}

module.exports = new PhotoPropertiesController();
