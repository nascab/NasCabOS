const fs = require('fs');
const path = require('path');
const sharp = require('../../../../utils/sharpConfigured');
const tableConfig = require('../../../../db/table/tableConfig');
const { encodeGeohash, normalizeLatLon } = require('../../../../workers/photoIndex/photoIndexUtil');

const GPS_ADD_STATUS = {
  PENDING: 0,
  APPLIED: 1,
  SKIPPED: 2,
};

const GPS_WINDOW_MS = 3 * 60 * 60 * 1000;
const SUPPORTED_EXTS = new Set(['.jpg', '.jpeg']);

function parseJsonIdArray(raw) {
  if (!raw) return [];
  if (Array.isArray(raw)) return raw.map(v => Number(v)).filter(v => Number.isFinite(v) && v > 0);
  try {
    const parsed = JSON.parse(String(raw));
    return Array.isArray(parsed) ? parsed.map(v => Number(v)).filter(v => Number.isFinite(v) && v > 0) : [];
  } catch (_) {
    return [];
  }
}

function uniqueIds(list) {
  return [...new Set((Array.isArray(list) ? list : []).map(v => Number(v)).filter(v => Number.isFinite(v) && v > 0))];
}

function pad2(v) {
  return v < 10 ? `0${v}` : String(v);
}

function buildPhotoFullPath(row) {
  const dir = row && row.path ? String(row.path) : '';
  const filename = row && row.filename ? String(row.filename) : '';
  return dir && filename ? path.join(dir, filename) : '';
}

function buildGpsExifPayload(latitude, longitude) {
  const lat = Number(latitude);
  const lon = Number(longitude);
  const latRef = lat >= 0 ? 'N' : 'S';
  const lonRef = lon >= 0 ? 'E' : 'W';

  const toDms = value => {
    const abs = Math.abs(Number(value) || 0);
    const degree = Math.floor(abs);
    const minuteFloat = (abs - degree) * 60;
    const minute = Math.floor(minuteFloat);
    const secondFloat = (minuteFloat - minute) * 60;
    const secondScaled = Math.max(0, Math.round(secondFloat * 10000));
    return `${degree}/1 ${minute}/1 ${secondScaled}/10000`;
  };

  return {
    // sharp expects GPS EXIF tags under IFD3 rather than a GPS root object.
    IFD3: {
      GPSVersionID: '2 3 0 0',
      GPSLatitudeRef: latRef,
      GPSLatitude: toDms(lat),
      GPSLongitudeRef: lonRef,
      GPSLongitude: toDms(lon),
      GPSMapDatum: 'WGS-84',
    },
  };
}

function buildGpsIndexUpdate(latitude, longitude) {
  const normalized = normalizeLatLon(latitude, longitude);
  if (!normalized) return null;
  const { latitude: lat, longitude: lon } = normalized;
  return {
    latitude: lat,
    longitude: lon,
    geohash: encodeGeohash(lat, lon, 8),
    geohash2: encodeGeohash(lat, lon, 2),
    geohash3: encodeGeohash(lat, lon, 3),
    geohash4: encodeGeohash(lat, lon, 4),
    geohash5: encodeGeohash(lat, lon, 5),
    geohash6: encodeGeohash(lat, lon, 6),
  };
}

class GpsSupplementService {
  constructor(knex) {
    this.knex = knex;
  }

  getWindowRange(originalTime) {
    const center = Math.floor(Number(originalTime) || 0);
    return {
      start: Math.max(0, center - GPS_WINDOW_MS),
      end: center + GPS_WINDOW_MS,
    };
  }

  isSupportedExt(ext) {
    return SUPPORTED_EXTS.has(String(ext || '').toLowerCase());
  }

  async getActiveBatchRow() {
    return this.knex('gps_add')
      .where({ status: GPS_ADD_STATUS.PENDING })
      .orderBy('id', 'desc')
      .first()
      .catch(() => null);
  }

  async buildBatchPayload(row) {
    if (!row || !row.id) return null;
    const referenceIds = uniqueIds(parseJsonIdArray(row.reference_index_ids));
    const pendingIds = uniqueIds(parseJsonIdArray(row.pending_index_ids));
    const allIds = uniqueIds([...referenceIds, ...pendingIds]);

    if (allIds.length === 0) {
      await this.knex('gps_add').where({ id: row.id }).del().catch(() => {});
      return null;
    }

    const photoRows = await this.knex('photo_index')
      .whereIn('id', allIds)
      .select(
        'id',
        'path',
        'filename',
        'size',
        'is_lvp',
        'type',
        'width',
        'height',
        'original_date',
        'original_time',
        'duration',
        'file_hash',
        'live_filename',
        'raw_filename',
        'ext',
        'camera',
        'latitude',
        'longitude'
      )
      .orderBy('original_time', 'asc')
      .orderBy('id', 'asc')
      .catch(() => []);

    const photoMap = new Map(
      photoRows.map(item => [
        Number(item.id),
        {
          ...item,
          fullpath: buildPhotoFullPath(item),
          is_favorite: 0,
        },
      ])
    );

    const referencePhotos = referenceIds.map(id => photoMap.get(id)).filter(Boolean);
    const pendingPhotos = pendingIds.map(id => photoMap.get(id)).filter(Boolean);

    if (pendingPhotos.length === 0) {
      await this.knex('gps_add').where({ id: row.id }).del().catch(() => {});
      return null;
    }

    return {
      id: Number(row.id),
      batchKey: row.batch_key ? String(row.batch_key) : '',
      sourceIndexId: Number(row.source_index_id) || 0,
      camera: row.camera ? String(row.camera) : '',
      latitude: Number(row.latitude) || 0,
      longitude: Number(row.longitude) || 0,
      status: Number(row.status) || 0,
      windowStart: Number(row.window_start) || 0,
      windowEnd: Number(row.window_end) || 0,
      createTime: row.create_time || null,
      updateTime: row.update_time || null,
      referencePhotos,
      pendingPhotos,
    };
  }

  async getStatus() {
    const [runningRaw, activeBatch] = await Promise.all([
      this._getConfig('ai_gps_add_scan_running', '0'),
      this.getActiveBatchRow(),
    ]);

    const running = runningRaw === '1';
    const batch = await this.buildBatchPayload(activeBatch);
    const allCompleted = !running && !batch
      ? !(await this.hasSearchableCandidates())
      : false;
    return {
      running,
      hasPendingBatch: !!batch,
      allCompleted,
      batch,
    };
  }

  async hasSearchableCandidates() {
    const row = await this.knex('photo_index')
      .first('id')
      .where({ is_file: 1, in_trash: 0, type: 1, gen_gps_add: 0 })
      .whereIn('ext', ['.jpg', '.jpeg'])
      .andWhere('original_time', '>', 0)
      .where(builder => {
        builder.whereNull('latitude').orWhere('latitude', 0);
      })
      .where(builder => {
        builder.whereNull('longitude').orWhere('longitude', 0);
      })
      .catch(() => null);
    return !!(row && row.id);
  }

  async createBatch(row, referenceRows, pendingRows) {
    const normalized = normalizeLatLon(referenceRows && referenceRows[0] ? referenceRows[0].latitude : 0, referenceRows && referenceRows[0] ? referenceRows[0].longitude : 0);
    const windowRange = this.getWindowRange(row && row.original_time);
    const payload = {
      batch_key: `gps_add_${Date.now()}_${Number(row && row.id) || 0}`,
      source_index_id: Number(row && row.id) || 0,
      camera: row && row.camera ? String(row.camera) : '',
      status: GPS_ADD_STATUS.PENDING,
      latitude: normalized ? normalized.latitude : 0,
      longitude: normalized ? normalized.longitude : 0,
      reference_index_ids: JSON.stringify(uniqueIds(referenceRows.map(item => item.id))),
      pending_index_ids: JSON.stringify(uniqueIds(pendingRows.map(item => item.id))),
      window_start: windowRange.start,
      window_end: windowRange.end,
      update_time: this.knex.fn.now(),
    };

    const ids = uniqueIds(pendingRows.map(item => item.id));

    await this.knex.transaction(async trx => {
      await trx('gps_add').insert(payload);
      if (ids.length > 0) {
        await trx('photo_index').whereIn('id', ids).update({ gen_gps_add: 1 });
      }
    });
  }

  async markScanned(ids) {
    const cleanIds = uniqueIds(ids);
    if (cleanIds.length === 0) return;
    await this.knex('photo_index').whereIn('id', cleanIds).update({ gen_gps_add: 1 }).catch(() => {});
  }

  async skipBatch(batchId) {
    const batch = await this.knex('gps_add')
      .where({ id: Number(batchId) || 0, status: GPS_ADD_STATUS.PENDING })
      .first()
      .catch(() => null);
    if (!batch || !batch.id) return false;

    const pendingIds = uniqueIds(parseJsonIdArray(batch.pending_index_ids));
    await this.knex.transaction(async trx => {
      if (pendingIds.length > 0) {
        await trx('photo_index').whereIn('id', pendingIds).update({ gen_gps_add: 2 });
      }
      await trx('gps_add').where({ id: batch.id }).update({ status: GPS_ADD_STATUS.SKIPPED, update_time: trx.fn.now() });
    });
    return true;
  }

  async resetAll() {
    return this.knex.transaction(async trx => {
      const resetResult = await trx('photo_index')
        .whereNot('gen_gps_add', 0)
        .update({ gen_gps_add: 0 });
      const clearedBatches = await trx('gps_add').del();
      return {
        resetCount: Number(resetResult) || 0,
        clearedBatchCount: Number(clearedBatches) || 0,
      };
    });
  }

  async applyBatchGps(batchId, latitude, longitude, selectedIds = []) {
    const normalized = normalizeLatLon(latitude, longitude);
    if (!normalized) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const batch = await this.knex('gps_add')
      .where({ id: Number(batchId) || 0, status: GPS_ADD_STATUS.PENDING })
      .first()
      .catch(() => null);
    if (!batch || !batch.id) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const pendingIds = uniqueIds(parseJsonIdArray(batch.pending_index_ids));
    if (pendingIds.length === 0) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const requestedIds = uniqueIds(selectedIds);
    const targetIds = requestedIds.length > 0
      ? pendingIds.filter(id => requestedIds.includes(id))
      : pendingIds;
    if (targetIds.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const rows = await this.knex('photo_index')
      .whereIn('id', targetIds)
      .select('id', 'path', 'filename', 'ext')
      .catch(() => []);

    if (!rows || rows.length === 0) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    for (const row of rows) {
      await this.writeGpsToJpeg(row, normalized.latitude, normalized.longitude);
    }

    const gpsUpdate = buildGpsIndexUpdate(normalized.latitude, normalized.longitude);
    await this.knex.transaction(async trx => {
      await trx('photo_index')
        .whereIn('id', rows.map(item => item.id))
        .update({
          ...gpsUpdate,
          gen_gps_add: 1,
        });
      const remainIds = pendingIds.filter(id => !targetIds.includes(id));
      if (remainIds.length > 0) {
        await trx('gps_add')
          .where({ id: batch.id })
          .update({
            pending_index_ids: JSON.stringify(remainIds),
            latitude: normalized.latitude,
            longitude: normalized.longitude,
            update_time: trx.fn.now(),
          });
      } else {
        await trx('gps_add')
          .where({ id: batch.id })
          .update({
            status: GPS_ADD_STATUS.APPLIED,
            latitude: normalized.latitude,
            longitude: normalized.longitude,
            update_time: trx.fn.now(),
          });
      }
    });

    return rows.length;
  }

  async writeGpsToJpeg(row, latitude, longitude) {
    const ext = row && row.ext ? String(row.ext).toLowerCase() : '';
    if (!this.isSupportedExt(ext)) {
      const err = new Error(`Unsupported image type: ${ext}`);
      err.statusCode = 400;
      throw err;
    }

    const fullPath = buildPhotoFullPath(row);
    if (!fullPath || !fs.existsSync(fullPath)) {
      const err = new Error(`Photo not found: ${fullPath}`);
      err.statusCode = 404;
      throw err;
    }

    const tempPath = `${fullPath}.gps_add_tmp_${Date.now()}`;
    try {
      await sharp(fullPath, { failOnError: false })
        .keepMetadata()
        .withExifMerge(buildGpsExifPayload(latitude, longitude))
        .jpeg({ quality: 100, chromaSubsampling: '4:4:4' })
        .toFile(tempPath);

      const stat = fs.statSync(fullPath);
      fs.renameSync(tempPath, fullPath);
      try {
        fs.utimesSync(fullPath, stat.atime, stat.mtime);
      } catch (_) {}
    } catch (err) {
      try {
        if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
      } catch (_) {}
      throw err;
    }
  }

  async findReferencePhotos(row, limit = 20) {
    const range = this.getWindowRange(row && row.original_time);
    const refs = await this.knex('photo_index')
      .select('id', 'path', 'filename', 'original_time', 'latitude', 'longitude', 'camera')
      .where({ is_file: 1, in_trash: 0, type: 1 })
      .whereBetween('original_time', [range.start, range.end])
      .andWhere('id', '!=', Number(row && row.id) || 0)
      .whereNotNull('latitude')
      .whereNotNull('longitude')
      .whereNot('latitude', 0)
      .whereNot('longitude', 0)
      .orderByRaw('ABS(original_time - ?) asc', [Number(row && row.original_time) || 0])
      .orderBy('id', 'asc')
      .limit(limit)
      .catch(() => []);
    return (refs || []).filter(item => normalizeLatLon(item.latitude, item.longitude));
  }

  async findPendingPhotos(row) {
    const range = this.getWindowRange(row && row.original_time);
    const camera = row && row.camera ? String(row.camera).trim() : '';
    if (!camera) return [];

    const baseQuery = this.knex('photo_index')
      .select('id', 'path', 'filename', 'original_time', 'camera', 'ext')
      .where({ is_file: 1, in_trash: 0, type: 1, gen_gps_add: 0 })
      .whereBetween('original_time', [range.start, range.end])
      .where(builder => {
        builder.whereNull('latitude').orWhere('latitude', 0);
      })
      .where(builder => {
        builder.whereNull('longitude').orWhere('longitude', 0);
      });

    baseQuery.andWhere('camera', camera);

    const rows = await baseQuery.orderBy('original_time', 'asc').orderBy('id', 'asc').catch(() => []);
    return (rows || []).filter(item => this.isSupportedExt(item.ext));
  }

  async _getConfig(key, fallback = '') {
    try {
      const value = await tableConfig.getConfigByKey(key);
      return value == null ? fallback : String(value);
    } catch (_) {
      return fallback;
    }
  }
}

GpsSupplementService.GPS_ADD_STATUS = GPS_ADD_STATUS;
GpsSupplementService.GPS_WINDOW_MS = GPS_WINDOW_MS;

module.exports = GpsSupplementService;
