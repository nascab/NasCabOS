const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const geohash = require('ngeohash');
const config = require('../../../../config/config');
const dbUtil = require('../../../../db/dbUtil');
const knexUtil = require('../../../../db/knexUtil');
const tableConfig = require('../../../../db/table/tableConfig');
const nascabAccountUtil = require('../../service/utils/nascabAccountUtil');
const photoTimeLineService = require('../timeline/photoTimeLineService');
const defaultTileServerList = config.getDefaultTileServer();
const DEFAULT_MAX_MAP_LEVEL = 18;

function md5(text) {
  return crypto
    .createHash('md5')
    .update(String(text || ''))
    .digest('hex');
}

function normalizeTileServer(input) {
  const obj = input && typeof input === 'object' ? input : null;
  if (!obj) return null;

  const name = String(obj.name || '').trim();
  const server = String(obj.server || '').trim();
  const coordinate = String(obj.coordinate || 'WGS-84').trim() || 'WGS-84';
  const maxLevelNum = Number(obj.maxLevel);

  if (!name || !server) return null;

  return {
    name,
    server,
    coordinate,
    maxLevel: Number.isFinite(maxLevelNum) && maxLevelNum > 0 ? maxLevelNum : DEFAULT_MAX_MAP_LEVEL,
    isDefault: obj.isDefault ? true : false,
  };
}

function parsePositiveInt(input, fallback) {
  const n = Number(input);
  if (!Number.isFinite(n)) return fallback;
  const t = Math.trunc(n);
  return t > 0 ? t : fallback;
}

function pickEvenly(list, maxCount) {
  const arr = Array.isArray(list) ? list : [];
  const n = parsePositiveInt(maxCount, 0);
  if (n <= 0) return [];
  if (arr.length <= n) return arr.slice();
  const out = [];
  const step = arr.length / n;
  for (let i = 0; i < n; i += 1) {
    const idx = Math.min(arr.length - 1, Math.floor(i * step));
    out.push(arr[idx]);
  }
  return out;
}

function thinPhotosByGrid(photos, bounds, maxCount) {
  const list = Array.isArray(photos) ? photos : [];
  const limit = parsePositiveInt(maxCount, 0);
  if (limit <= 0) return [];
  if (list.length <= limit) return list.slice();

  const minLat = bounds && Number.isFinite(bounds.minLat) ? bounds.minLat : null;
  const maxLat = bounds && Number.isFinite(bounds.maxLat) ? bounds.maxLat : null;
  const minLng = bounds && Number.isFinite(bounds.minLng) ? bounds.minLng : null;
  const maxLng = bounds && Number.isFinite(bounds.maxLng) ? bounds.maxLng : null;
  if ([minLat, maxLat, minLng, maxLng].some(v => v === null)) return pickEvenly(list, limit);

  const latSpan = Math.max(0, maxLat - minLat);
  const lngSpan = Math.max(0, maxLng - minLng);
  if (latSpan === 0 || lngSpan === 0) return pickEvenly(list, limit);

  const aspect = lngSpan / latSpan;
  let cols = Math.ceil(Math.sqrt(limit * aspect));
  cols = Math.max(1, Math.min(cols, limit));
  let rows = Math.ceil(limit / cols);
  rows = Math.max(1, Math.min(rows, limit));

  const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
  const timeScore = p => {
    const t = Number(p && p.original_time !== undefined ? p.original_time : 0);
    return Number.isFinite(t) ? t : 0;
  };
  const idScore = p => {
    const id = Number(p && p.id !== undefined ? p.id : 0);
    return Number.isFinite(id) ? id : 0;
  };

  const byCell = new Map();
  for (const p of list) {
    const lat = Number(p && p.latitude !== undefined ? p.latitude : NaN);
    const lng = Number(p && p.longitude !== undefined ? p.longitude : NaN);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    const x = clamp(Math.floor(((lng - minLng) / lngSpan) * cols), 0, cols - 1);
    const y = clamp(Math.floor(((lat - minLat) / latSpan) * rows), 0, rows - 1);
    const key = `${x},${y}`;
    const existing = byCell.get(key);
    if (!existing) {
      byCell.set(key, [p]);
      continue;
    }
    existing.push(p);
  }

  if (byCell.size === 0) return pickEvenly(list, limit);

  for (const bucket of byCell.values()) {
    bucket.sort((a, b) => timeScore(b) - timeScore(a) || idScore(b) - idScore(a));
  }

  const cellKeys = [];
  for (let y = 0; y < rows; y += 1) {
    if (y % 2 === 0) {
      for (let x = 0; x < cols; x += 1) cellKeys.push(`${x},${y}`);
    } else {
      for (let x = cols - 1; x >= 0; x -= 1) cellKeys.push(`${x},${y}`);
    }
  }

  const availableCellKeys = cellKeys.filter(k => byCell.has(k));
  if (availableCellKeys.length === 0) return pickEvenly(list, limit);

  if (availableCellKeys.length > limit) {
    const pickedKeys = pickEvenly(availableCellKeys, limit);
    const out = [];
    for (const k of pickedKeys) {
      const bucket = byCell.get(k);
      if (bucket && bucket.length > 0) out.push(bucket[0]);
      if (out.length >= limit) break;
    }
    return out.length > 0 ? out : pickEvenly(list, limit);
  }

  const out = [];
  for (const k of availableCellKeys) {
    const bucket = byCell.get(k);
    if (bucket && bucket.length > 0) out.push(bucket[0]);
    if (out.length >= limit) return out;
  }

  let round = 1;
  while (out.length < limit) {
    let added = 0;
    for (const k of availableCellKeys) {
      const bucket = byCell.get(k);
      if (!bucket || bucket.length <= round) continue;
      out.push(bucket[round]);
      added += 1;
      if (out.length >= limit) return out;
    }
    if (added === 0) break;
    round += 1;
  }

  return out;
}

class PhotoMapService {
  async getCurrentTileServer() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const raw = await nascabAccountUtil.getDecryptedConfigValue(knex, tableConfig, 'mapTileServer');
    if (raw !== null && raw !== undefined && String(raw).trim()) {
      try {
        const parsed = JSON.parse(String(raw));
        const item = Array.isArray(parsed) ? parsed.find(p => p && p.isDefault) || parsed[0] : parsed;
        const normalized = normalizeTileServer(item);
        if (normalized) return normalized;
      } catch (_) {}
    }
    return defaultTileServerList.length > 0
      ? defaultTileServerList[0]
      : {
          name: 'GaoDe',
          server: 'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}',
          maxLevel: 18,
          coordinate: 'GCJ-02',
        };
  }

  async getZoomInfo() {
    const tileServer = await this.getCurrentTileServer();
    return {
      zoomInfo: { minZoom: 2, maxZoom: Number(tileServer.maxLevel) || DEFAULT_MAX_MAP_LEVEL },
      tileServer,
    };
  }

  async getTileServerList() {
    let list = [];
    const rawList = await tableConfig.getConfigByKey('mapTileServerList', 0);
    if (rawList) {
      try {
        const parsed = JSON.parse(String(rawList));
        if (Array.isArray(parsed)) list = parsed;
      } catch (_) {}
    }
    if (list.length == 0) {
      list = defaultTileServerList;
    }
    // console.log('defaultTileServerList', defaultTileServerList);
    if (!Array.isArray(list)) list = [];

    const currentServer = await this.getCurrentTileServer();
    if (list.length === 0) list.push(currentServer);

    let customList = [];
    const rawCustom = await tableConfig.getConfigByKey('mapTileServerListCustom', 0);
    if (rawCustom) {
      try {
        const parsed = JSON.parse(String(rawCustom));
        if (Array.isArray(parsed)) customList = parsed;
      } catch (_) {}
    }
    if (!Array.isArray(customList)) customList = [];

    for (const s of customList) {
      if (s && typeof s === 'object') {
        s.isCustom = 1;
        list.push(s);
      }
    }

    const currentServerUrl = String(currentServer && currentServer.server ? currentServer.server : '');
    for (const s of list) {
      if (!s || typeof s !== 'object') continue;
      s.current = String(s.server || '') === currentServerUrl ? 1 : 0;
      if (!s.maxLevel) s.maxLevel = DEFAULT_MAX_MAP_LEVEL;
      if (!s.coordinate) s.coordinate = 'WGS-84';
    }

    return list;
  }

  async setTileServer(tileServer) {
    const normalized = normalizeTileServer(tileServer);
    if (!normalized) return false;
    await tableConfig.setConfigByKey('mapTileServer', JSON.stringify(normalized), 0);
    return true;
  }

  async addTileServer(tileServer) {
    const normalized = normalizeTileServer(tileServer);
    if (!normalized) return false;

    let customList = [];
    const rawCustom = await tableConfig.getConfigByKey('mapTileServerListCustom', 0);
    if (rawCustom) {
      try {
        const parsed = JSON.parse(String(rawCustom));
        if (Array.isArray(parsed)) customList = parsed;
      } catch (_) {}
    }
    if (!Array.isArray(customList)) customList = [];

    const serverUrl = String(normalized.server);
    if (!customList.some(s => s && String(s.server || '') === serverUrl)) {
      customList.push(normalized);
      await tableConfig.setConfigByKey('mapTileServerListCustom', JSON.stringify(customList), 0);
    }
    return true;
  }

  async deleteTileServer(tileServer) {
    const normalized = normalizeTileServer(tileServer);
    if (!normalized) return false;

    let customList = [];
    const rawCustom = await tableConfig.getConfigByKey('mapTileServerListCustom', 0);
    if (rawCustom) {
      try {
        const parsed = JSON.parse(String(rawCustom));
        if (Array.isArray(parsed)) customList = parsed;
      } catch (_) {}
    }
    if (!Array.isArray(customList)) customList = [];

    const serverUrl = String(normalized.server);
    const before = customList.length;
    customList = customList.filter(s => !(s && String(s.server || '') === serverUrl));
    if (customList.length !== before) {
      await tableConfig.setConfigByKey('mapTileServerListCustom', JSON.stringify(customList), 0);
    }
    return true;
  }

  async getTileFilePath({ zoom, x, y, baseServerUrl }) {
    const serverHash = md5(baseServerUrl);
    return path.join(config.getMapTileCachePath(), serverHash, String(zoom), String(x), String(y), 'tile.png');
  }

  async fetchToFile(url, filePath, timeoutMs = 10000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const resp = await fetch(url, { method: 'GET', signal: controller.signal });
      if (!resp.ok) return false;
      const ab = await resp.arrayBuffer();
      const buf = Buffer.from(ab);
      if (!buf || buf.length === 0) return false;
      await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
      await fs.promises.writeFile(filePath, buf);
      return true;
    } catch (_) {
      return false;
    } finally {
      clearTimeout(timer);
    }
  }

  async ensureTileCached({ zoom, x, y }) {
    const tileServer = await this.getCurrentTileServer();
    const baseUrl = String(tileServer.server || '').trim();
    if (!baseUrl) return null;

    const url = baseUrl.replace('{z}', String(zoom)).replace('{x}', String(x)).replace('{y}', String(y));
    const filePath = await this.getTileFilePath({ zoom, x, y, baseServerUrl: baseUrl });
    try {
      const st = await fs.promises.stat(filePath);
      if (st && st.size > 0) return filePath;
    } catch (_) {}
    const ok = await this.fetchToFile(url, filePath, 10000);
    if (!ok) return null;
    return filePath;
  }

  getBoundsPhotoPrecision(zoom) {
    const z = Number(zoom);
    if (!Number.isFinite(z)) return 2;
    if (z <= 4) return 2;
    if (z <= 6) return 3;
    if (z <= 8) return 4;
    if (z <= 14) return 5;
    return 6;
  }

  async getLocationStr({ dbGeo, locale }, geohash) {
    const rawHash = String(geohash || '').trim();
    if (!rawHash) return '';
    const hash8 = rawHash.length > 8 ? rawHash.slice(0, 8) : rawHash;

    let lang = 'en';
    if (locale.indexOf('-') > -1) {
      lang = locale.split('-')[0].toLowerCase();
    } else if (locale) {
      lang = locale.toLowerCase();
    }
    const geoColumnMap = {
      8: 'geohash',
      7: 'geohash7',
      6: 'geohash6',
      5: 'geohash5',
      4: 'geohash4',
      3: 'geohash3',
    };
    for (let len = Math.min(8, hash8.length); len >= 3; len -= 1) {
      const prefix = hash8.slice(0, len);
      const geoColumn = geoColumnMap[len] || geoColumnMap[3];
      const rows = await dbGeo
        .raw(
          `
          SELECT
            COALESCE(i_req.name, i_def.name) AS local_name,
            COALESCE(i_en.name, i_def.name, i_req.name) AS en_name
          FROM geonames g
          LEFT JOIN geoname_i18n i_req ON i_req.geonameid = g.geonameid AND i_req.lang = ?
          LEFT JOIN geoname_i18n i_en ON i_en.geonameid = g.geonameid AND i_en.lang = 'en'
          LEFT JOIN geoname_i18n i_def ON i_def.geonameid = g.geonameid AND i_def.lang = 'und'
          WHERE g.${geoColumn} = ?
          ORDER BY g.geonameid ASC
          LIMIT 1
          `,
          [lang, prefix]
        )
        .catch(() => null);
      const row = Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
      const localName = row && row.local_name ? String(row.local_name).trim() : '';
      const enName = row && row.en_name ? String(row.en_name).trim() : '';
      if (localName || enName) {
        if (localName && enName && localName !== enName) return `${localName} ${enName}`;
        return localName || enName;
      }
    }

    return '';
  }

  async getBoundsPhoto({ knexPhoto }, params, user) {
    const { minLat, minLng, maxLat, maxLng, zoom } = params || {};

    const la1 = Number(minLat);
    const lo1 = Number(minLng);
    const la2 = Number(maxLat);
    const lo2 = Number(maxLng);
    const z = Number(zoom);

    if (![la1, lo1, la2, lo2].every(Number.isFinite)) return { mapPhoto: [] };

    const minLa = Math.min(la1, la2);
    const maxLa = Math.max(la1, la2);
    const minLo = Math.min(lo1, lo2);
    const maxLo = Math.max(lo1, lo2);

    const requestedMax = parsePositiveInt((params && (params.maxReturnCount ?? params.maxCount ?? params.limit)) || 0, 150);
    const maxReturnCount = Math.max(1, Math.min(requestedMax, 2000));

    let precision = this.getBoundsPhotoPrecision(z);
    let boxes = [];
    while (precision >= 2) {
      try {
        boxes = geohash.bboxes(minLa, minLo, maxLa, maxLo, precision) || [];
      } catch (_) {
        boxes = [];
      }
      if (Array.isArray(boxes) && boxes.length > 0) {
        const cellTarget = Math.max(maxReturnCount * 8, 600);
        if (boxes.length <= cellTarget || precision === 2) break;
      }
      precision -= 1;
    }
    if (!Array.isArray(boxes) || boxes.length === 0) return { mapPhoto: [] };

    const mapped = { ...(params || {}) };
    const validPaths = await photoTimeLineService.getValidPathsByParams(mapped, user);
    if (!validPaths || validPaths.length === 0) return { mapPhoto: [] };

    const { query: baseQuery } = await photoTimeLineService.buildBaseQuery(mapped, validPaths, user);
    baseQuery.andWhere('photo_index.is_file', 1).andWhere('photo_index.in_trash', 0);

    const geoColumnMap = {
      2: 'photo_index.geohash2',
      3: 'photo_index.geohash3',
      4: 'photo_index.geohash4',
      5: 'photo_index.geohash5',
      6: 'photo_index.geohash6',
    };
    const geoColumn = geoColumnMap[precision] || geoColumnMap[2];

    const uniqueCells = [];
    const seen = new Set();
    for (const cell of boxes) {
      const c = String(cell || '').trim();
      if (!c) continue;
      if (seen.has(c)) continue;
      seen.add(c);
      uniqueCells.push(c);
    }
    if (uniqueCells.length === 0) return { mapPhoto: [] };

    const maxQueryCells = Math.min(Math.max(maxReturnCount * 20, 800), 6000);
    const queryCells = uniqueCells.length > maxQueryCells ? pickEvenly(uniqueCells, maxQueryCells) : uniqueCells;

    // 为了避免一次性 whereIn 塞太多参数（SQLite 常见的变量上限是 999），把 cell 列表按固定大小切块分批查询。
    // chunkSize = 每批最多处理多少个 cell
    const chunkSize = 500;
    const mapByCell = new Map();
    const selectFields = [
      'photo_index.id as id',
      'photo_index.geohash as geohash',
      'photo_index.latitude as latitude',
      'photo_index.longitude as longitude',
      'photo_index.original_time as original_time',
      'photo_index.path as path',
      'photo_index.filename as filename',
      'photo_index.type as type',
      'photo_index.duration as duration',
    ];

    let batchOk = true;
    for (let i = 0; i < queryCells.length; i += chunkSize) {
      // chunk = 当前这一批要查询的 cell（uniqueCells 的一个切片）
      const chunk = queryCells.slice(i, i + chunkSize);
      try {
        const picked = await baseQuery
          .clone()
          .clearSelect()
          .clearOrder()
          // 只查询当前 chunk 里的 cell，避免 whereIn 参数过多导致报错或性能抖动
          .whereIn(geoColumn, chunk)
          .select(knexPhoto.raw('?? as cell', [geoColumn]), knexPhoto.raw('max(photo_index.id) as id'))
          .groupBy(geoColumn)
          .catch(() => null);
        const ids = Array.isArray(picked) ? picked.map(r => Number(r && r.id ? r.id : 0)).filter(n => Number.isFinite(n) && n > 0) : [];
        if (ids.length === 0) continue;
        const rows = await knexPhoto('photo_index')
          .select(...selectFields)
          .whereIn('photo_index.id', ids)
          .catch(() => null);

        const rowById = new Map();
        if (Array.isArray(rows)) {
          for (const r of rows) {
            const id = Number(r && r.id ? r.id : 0);
            if (!Number.isFinite(id) || id <= 0) continue;
            if (!rowById.has(id)) rowById.set(id, r);
          }
        }

        for (const p of picked || []) {
          const cell = String(p && p.cell ? p.cell : '').trim();
          const id = Number(p && p.id ? p.id : 0);
          if (!cell) continue;
          if (!Number.isFinite(id) || id <= 0) continue;
          if (mapByCell.has(cell)) continue;
          const row = rowById.get(id);
          if (row && row.id) mapByCell.set(cell, row);
        }
      } catch (_) {
        batchOk = false;
        break;
      }
    }

    const mapPhoto = [];
    if (batchOk && mapByCell.size > 0) {
      for (const c of queryCells) {
        const row = mapByCell.get(c);
        if (row && row.id) mapPhoto.push({ ...row, fullpath: path.join(row.path, row.filename) });
      }
      return { mapPhoto: thinPhotosByGrid(mapPhoto, { minLat: minLa, minLng: minLo, maxLat: maxLa, maxLng: maxLo }, maxReturnCount) };
    }

    const fallbackMaxFetch = Math.min(Math.max(maxReturnCount * 4, maxReturnCount), 800);
    for (const c of queryCells) {
      const row = await baseQuery
        .clone()
        .andWhere(geoColumn, c)
        .select(
          'photo_index.id',
          'photo_index.geohash',
          'photo_index.latitude',
          'photo_index.longitude',
          'photo_index.original_time',
          'photo_index.path',
          'photo_index.filename',
          'photo_index.type',
          'photo_index.duration'
        )
        .first()
        .catch(() => null);
      if (row && row.id) mapPhoto.push({ ...row, fullpath: path.join(row.path, row.filename) });
      if (mapPhoto.length >= fallbackMaxFetch) break;
    }

    return { mapPhoto: thinPhotosByGrid(mapPhoto, { minLat: minLa, minLng: minLo, maxLat: maxLa, maxLng: maxLo }, maxReturnCount) };
  }

  async getAlbumPhotoForMap({ knexPhoto }, params, user) {
    const maxReturnCount = 200;

    const mapped = { ...(params || {}) };
    if (mapped.ordinaryAlbumId !== undefined && mapped.album_id === undefined) mapped.album_id = mapped.ordinaryAlbumId;
    if (mapped.albumId !== undefined && mapped.smart_album_id === undefined) mapped.smart_album_id = mapped.albumId;
    if (mapped.libraryId !== undefined && mapped.collection_id === undefined) mapped.collection_id = mapped.libraryId;

    const validPaths = await photoTimeLineService.getValidPathsByParams(mapped, user);
    if (!validPaths || validPaths.length === 0) return { mapPhoto: [] };

    const { query: baseQuery } = await photoTimeLineService.buildBaseQuery(mapped, validPaths, user);
    baseQuery
      .andWhere('photo_index.is_file', 1)
      .andWhere('photo_index.in_trash', 0)
      .andWhereRaw('NOT (photo_index.latitude = 0 AND photo_index.longitude = 0)')
      .whereNotNull('photo_index.geohash')
      .andWhere('photo_index.geohash', '!=', '');

    const [{ count }] = await baseQuery.clone().clearSelect().clearOrder().count('* as count');
    const total = Number(count || 0);

    const selectFields = [
      'photo_index.id',
      'photo_index.file_hash',
      'photo_index.path',
      'photo_index.filename',
      'photo_index.type',
      'photo_index.duration',
      'photo_index.original_time',
      'photo_index.geohash',
      'photo_index.latitude',
      'photo_index.longitude',
    ];

    if (total > 0 && total < maxReturnCount) {
      const rows = await baseQuery.clone().select(selectFields).orderBy('photo_index.original_time', 'desc').orderBy('photo_index.id', 'desc');
      const mapPhoto = (rows || []).map(r => ({ ...r, fullpath: path.join(r.path, r.filename) }));
      return { mapPhoto };
    }

    const seenIds = new Set();
    let chosenPrefixes = [];
    let precision = 5;
    for (const p of [5, 4, 3, 2]) {
      const geoColumn = `photo_index.geohash${p}`;
      const rows = await baseQuery
        .clone()
        .clearSelect()
        .clearOrder()
        .whereNotNull(geoColumn)
        .andWhere(geoColumn, '!=', '')
        .select(knexPhoto.raw('?? as prefix', [geoColumn]))
        .groupBy(geoColumn);
      const prefixes = (rows || []).map(r => String(r.prefix || '')).filter(Boolean);
      if (prefixes.length > 0 && prefixes.length <= maxReturnCount) {
        chosenPrefixes = prefixes;
        precision = p;
        break;
      }
      if (p === 2) {
        chosenPrefixes = prefixes.slice(0, maxReturnCount);
        precision = 2;
      }
    }

    const mapPhoto = [];
    const chosenGeoColumn = `photo_index.geohash${precision}`;
    for (const pref of chosenPrefixes) {
      if (mapPhoto.length >= maxReturnCount) break;
      const row = await baseQuery
        .clone()
        .andWhere(chosenGeoColumn, pref)
        .orderBy('photo_index.original_time', 'desc')
        .orderBy('photo_index.id', 'desc')
        .select(selectFields)
        .first()
        .catch(() => null);
      if (!row || !row.id) continue;
      const id = Number(row.id);
      if (seenIds.has(id)) continue;
      seenIds.add(id);
      mapPhoto.push({ ...row, fullpath: path.join(row.path, row.filename) });
    }

    return { mapPhoto };
  }
}

module.exports = new PhotoMapService();
