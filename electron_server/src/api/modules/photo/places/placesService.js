const path = require('path');
const { getTranslation } = require('../../../../utils/i18nUtil');
const photoPathQueryUtil = require('../timeline/photoPathQueryUtil');

class PlacesService {
  constructor(knex) {
    this.knex = knex;
  }

  async listPlaces(params = {}) {
    const status = params.status || params.filter || 'visible';
    const locale = params && params.locale ? String(params.locale) : 'zh-CN';
    const validPaths = Array.isArray(params.validPaths) ? params.validPaths.filter(Boolean) : [];

    if (Object.prototype.hasOwnProperty.call(params, 'validPaths') && validPaths.length === 0) {
      return {
        items: [],
        pagination: { total: 0, page: 1, pageSize: 0 },
      };
    }

    let rowsQuery = this.knex('photo_places').select('place_name', 'photo_count', 'is_hide', 'create_time', 'update_time');

    if (validPaths.length > 0) {
      const allowedPlaceNamesQuery = this.knex('photo_places2filehash as p2')
        .join('photo_index as p', 'p.file_hash', 'p2.file_hash')
        .where('p.is_file', 1)
        .where('p.in_trash', 0)
        .select('p2.place_name');
      photoPathQueryUtil.applyPathPrefixFilter(allowedPlaceNamesQuery, 'p.path', validPaths);
      rowsQuery = rowsQuery.whereIn('place_name', allowedPlaceNamesQuery);
    }

    if (status === 'visible' || status === 'visiable') {
      rowsQuery = rowsQuery.andWhere('is_hide', 0);
    } else if (status === 'hide' || status === 'hidden') {
      rowsQuery = rowsQuery.andWhere('is_hide', 1);
    }

    const rows = await rowsQuery.orderBy('photo_count', 'desc').catch(() => []);

    const items = Array.isArray(rows) ? rows : [];
    const total = items.length;
    const placeNames = items
      .map(it => (it && it.place_name ? String(it.place_name) : ''))
      .map(n => n.trim())
      .filter(Boolean);
    const coverByPlaceKey = new Map();

    if (placeNames.length > 0) {
      let coverRows = [];
      if (validPaths.length > 0) {
        let qb = this.knex('photo_places2filehash as p2')
          .join('photo_index as p', 'p.file_hash', 'p2.file_hash')
          .andWhere('p.is_file', 1)
          .andWhere('p.in_trash', 0)
          .whereIn('p2.place_name', placeNames);
        photoPathQueryUtil.applyPathPrefixFilter(qb, 'p.path', validPaths);
        const allCoverCandidates = await qb
          .select('p2.place_name as place_key', 'p2.file_hash as file_hash', 'p.path as path', 'p.filename as filename', 'p.original_time as original_time', 'p.id as photo_id', 'p2.id as p2_id')
          .orderBy('p.original_time', 'desc')
          .orderBy('p.id', 'desc')
          .orderBy('p2.id', 'desc')
          .catch(() => []);
        for (const r of allCoverCandidates) {
          const key = r && r.place_key !== undefined && r.place_key !== null ? String(r.place_key) : '';
          if (!key || coverByPlaceKey.has(key)) continue;
          coverByPlaceKey.set(key, {
            file_hash: r && r.file_hash ? String(r.file_hash) : '',
            path: r && r.path ? String(r.path) : '',
            filename: r && r.filename ? String(r.filename) : '',
            fullpath: r && r.path && r.filename ? path.join(r.path, r.filename) : '',
          });
        }
      } else {
        const placeholders = placeNames.map(() => '?').join(',');
        const keyColumn = 'place_name';
        const sql = `
        SELECT ${keyColumn} AS place_key, file_hash, path, filename
        FROM (
          SELECT
            p2.${keyColumn} AS place_key,
            p2.file_hash AS file_hash,
            p.path AS path,
            p.filename AS filename,
            ROW_NUMBER() OVER (
              PARTITION BY p2.${keyColumn}
              ORDER BY p.original_time DESC, p.id DESC, p2.id DESC
            ) AS rn
          FROM photo_places2filehash AS p2
          JOIN photo_index AS p ON p.file_hash = p2.file_hash
          WHERE p2.${keyColumn} IN (${placeholders})
            AND p.is_file = 1
            AND p.in_trash = 0
        )
        WHERE rn = 1
      `;
        const paramsList = placeNames;
        try {
          const raw = await this.knex.raw(sql, paramsList);
          coverRows = Array.isArray(raw) ? raw : [];
        } catch (_) {
          let qb = this.knex('photo_places2filehash as p2').join('photo_index as p', 'p.file_hash', 'p2.file_hash').andWhere('p.is_file', 1).andWhere('p.in_trash', 0);

          qb = qb.whereIn('p2.place_name', placeNames);

          coverRows = await qb
            .select('p2.place_name as place_key', 'p2.file_hash as file_hash', 'p.path as path', 'p.filename as filename', 'p.original_time as original_time', 'p.id as photo_id', 'p2.id as p2_id')
            .orderBy('p.original_time', 'desc')
            .orderBy('p.id', 'desc')
            .orderBy('p2.id', 'desc')
            .catch(() => []);
        }
      }

      if (validPaths.length === 0) {
        for (const r of coverRows) {
          const key = r && r.place_key !== undefined && r.place_key !== null ? String(r.place_key) : '';
          if (!key) continue;
          if (coverByPlaceKey.has(key)) continue;
          const coverPath = r && r.path ? String(r.path) : '';
          const coverFilename = r && r.filename ? String(r.filename) : '';
          const fullpath = coverPath && coverFilename ? path.join(coverPath, coverFilename) : '';
          coverByPlaceKey.set(key, {
            file_hash: r && r.file_hash ? String(r.file_hash) : '',
            path: coverPath,
            filename: coverFilename,
            fullpath: fullpath || '',
          });
        }
      }
    }

    const enriched = items.map(it => {
      const { place_name: _pn, ...rest } = it || {};
      const rawName = it && it.place_name ? String(it.place_name) : '';
      const coverKey = rawName;
      const cover = coverByPlaceKey.get(coverKey) || null;
      const keyByName = rawName ? `places365.${rawName}` : '';
      const translatedByName = keyByName ? getTranslation(keyByName, locale) : '';
      const localizedName = (translatedByName && translatedByName !== keyByName ? translatedByName : '') || rawName;
      return {
        ...rest,
        place_name_raw: rawName,
        place_name: localizedName,
        is_hide: Number(it && it.is_hide ? it.is_hide : 0) || 0,
        cover,
      };
    });

    return {
      items: enriched,
      pagination: {
        total,
        page: 1,
        pageSize: total,
      },
    };
  }

  async updatePlaceStatus(params = {}) {
    const rawPlaceName = params.place_name ?? params.placeName ?? params.place_name_raw;
    const placeName = rawPlaceName ? String(rawPlaceName).trim() : '';
    const rawStatus = params.status ?? params.state ?? params.is_hide ?? params.isHide;
    if (!placeName) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    let isHide = null;
    if (rawStatus === 'hide' || rawStatus === 'hidden' || rawStatus === 1 || rawStatus === '1' || rawStatus === true) {
      isHide = 1;
    } else if (rawStatus === 'visible' || rawStatus === 'visiable' || rawStatus === 0 || rawStatus === '0' || rawStatus === false) {
      isHide = 0;
    }
    if (isHide === null) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    const existed = await this.knex('photo_places')
      .where({ place_name: placeName })
      .first()
      .catch(() => null);
    if (!existed) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    const where = { place_name: placeName };
    await this.knex('photo_places')
      .where(where)
      .update({ is_hide: isHide, update_time: this.knex.fn.now() })
      .catch(() => {});
    return true;
  }

  async resetPlacesRecognition() {
    return this.knex.transaction(async trx => {
      const resetQuery = trx('photo_index').whereNot('gen_place', 0);
      const resetCount = await resetQuery
        .update({ gen_place: 0 })
        .catch(() => 0);
      const clearedRelationCount = await trx('photo_places2filehash')
        .del()
        .catch(() => 0);
      const clearedPlaceCount = await trx('photo_places')
        .del()
        .catch(() => 0);

      return {
        resetCount: Number(resetCount) || 0,
        clearedRelationCount: Number(clearedRelationCount) || 0,
        clearedPlaceCount: Number(clearedPlaceCount) || 0,
      };
    });
  }
}

module.exports = PlacesService;
