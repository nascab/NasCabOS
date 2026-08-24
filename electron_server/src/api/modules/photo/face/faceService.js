const fs = require('fs');
const path = require('path');
const sharp = require('../../../../utils/sharpConfigured');
const sharpUtils = require('../../../../utils/sharpUtils');
const fileService = require('../../file/core/fileService');
const tableConfig = require('../../../../db/table/tableConfig');
const photoPathQueryUtil = require('../timeline/photoPathQueryUtil');

function clampNumber(v, min, max) {
  if (!Number.isFinite(v)) return min;
  return Math.max(min, Math.min(max, v));
}

function createSharpFromConverted(converted) {
  if (converted && typeof converted === 'object' && !Buffer.isBuffer(converted) && converted.input && converted.options) {
    return sharp(converted.input, converted.options);
  }
  return sharp(converted);
}

class FaceService {
  constructor(knex) {
    this.knex = knex;
  }

  async toggleAiFaceInMainProcess(enable, { timeoutMs = 15000 } = {}) {
    if (!process.send) {
      const err = new Error('common.ERROR');
      err.statusCode = 500;
      throw err;
    }

    const requestId = `toggleAiFace_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        process.off('message', handleResponse);
        reject(new Error('common.ERROR'));
      }, timeoutMs);

      const handleResponse = message => {
        if (!message || message.type !== 'toggleAiFaceResponse') return;
        const data = message.data || {};
        if (data.requestId !== requestId) return;
        clearTimeout(timeout);
        process.off('message', handleResponse);
        if (!data.ok) {
          const err = new Error('common.ERROR');
          err.statusCode = 500;
          reject(err);
          return;
        }
        resolve({
          enable: !!enable,
          running: data.running,
        });
      };

      process.on('message', handleResponse);
      try {
        process.send({
          type: 'toggleAiFace',
          data: {
            enable: enable ? 1 : 0,
            requestId,
          },
          timestamp: Date.now(),
        });
      } catch (e) {
        clearTimeout(timeout);
        process.off('message', handleResponse);
        reject(e);
      }
    });
  }

  async resetFaceRecognition() {
    await this.toggleAiFaceInMainProcess(false);

    await this.knex.transaction(async trx => {
      await trx('photo_face2filehash')
        .del()
        .catch(() => {});
      await trx('photo_face_samples')
        .del()
        .catch(() => {});
      await trx('photo_faces')
        .del()
        .catch(() => {});
      await trx('photo_index')
        .update({ gen_faces: 0 })
        .catch(() => {});
    });

    await this.toggleAiFaceInMainProcess(true);

    return true;
  }

  async getRootFaceId(faceId) {
    let cur = Number(faceId) || 0;
    let hop = 0;
    while (cur > 0 && hop < 16) {
      const row = await this.knex('photo_faces')
        .select('belong_face_id')
        .where({ face_id: cur })
        .first()
        .catch(() => null);
      const next = row && row.belong_face_id ? Number(row.belong_face_id) : 0;
      if (!next || next === cur) return cur;
      cur = next;
      hop += 1;
    }
    return Number(faceId) || 0;
  }

  async listFaces(params = {}) {
    const page = Math.max(1, Number(params.page) || 1);
    const pageSize = Math.max(1, Math.min(200, Number(params.pageSize ?? params.page_size) || 60));
    const offset = (page - 1) * pageSize;
    const status = params.status || params.filter || 'visiable';
    const keywordRaw = params.keyword ?? params.q ?? params.name ?? '';
    const keyword = typeof keywordRaw === 'string' ? keywordRaw.trim() : '';
    const escapeLike = s => String(s).replace(/[\\%_]/g, m => `\\${m}`);
    const validPaths = Array.isArray(params.validPaths) ? params.validPaths.filter(Boolean) : [];
    if (Object.prototype.hasOwnProperty.call(params, 'validPaths') && validPaths.length === 0) {
      return {
        items: [],
        pagination: { total: 0, page, pageSize },
      };
    }

    let minShowCount = 0;
    try {
      const raw = await tableConfig.getConfigByKey('ai_face_min_show_count');
      const parsed = Math.floor(Number(raw));
      minShowCount = Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
    } catch (_) {
      minShowCount = 0;
    }

    let totalQuery = this.knex('photo_faces').where('face_count', '>=', minShowCount).whereNull('belong_face_id');
    let rowsQuery = this.knex('photo_faces')
      .select('face_id', 'face_count', 'belong_face_id', 'is_hide', 'name', 'create_time', 'update_time')
      .where('face_count', '>=', minShowCount)
      .whereNull('belong_face_id');

    if (validPaths.length > 0) {
      const allowedFaceIdsQuery = this.knex('photo_face2filehash as f2')
        .join('photo_index as p', 'p.file_hash', 'f2.file_hash')
        .where('p.is_file', 1)
        .where('p.in_trash', 0)
        .select('f2.face_id');
      photoPathQueryUtil.applyPathPrefixFilter(allowedFaceIdsQuery, 'p.path', validPaths);
      totalQuery = totalQuery.whereIn('face_id', allowedFaceIdsQuery);
      rowsQuery = rowsQuery.whereIn('face_id', allowedFaceIdsQuery);
    }

    if (status === 'visible' || status === 'visiable') {
      totalQuery = totalQuery.andWhere('is_hide', 0);
      rowsQuery = rowsQuery.andWhere('is_hide', 0);
    } else if (status === 'hide' || status === 'hidden') {
      totalQuery = totalQuery.andWhere('is_hide', 1);
      rowsQuery = rowsQuery.andWhere('is_hide', 1);
    }
    if (keyword) {
      const like = `%${escapeLike(keyword)}%`;
      totalQuery = totalQuery.andWhereRaw(`CAST(name AS TEXT) LIKE ? ESCAPE '\\'`, [like]);
      rowsQuery = rowsQuery.andWhereRaw(`CAST(name AS TEXT) LIKE ? ESCAPE '\\'`, [like]);
    }

    const totalRow = await totalQuery
      .count({ total: 'face_id' })
      .first()
      .catch(() => ({ total: 0 }));
    const total = Number(totalRow && totalRow.total ? totalRow.total : 0) || 0;

    const rows = await rowsQuery
      .orderBy('face_count', 'desc')
      .orderBy('face_id', 'desc')
      .limit(pageSize)
      .offset(offset)
      .catch(() => []);

    const items = Array.isArray(rows) ? rows : [];
    const faceIds = items.map(it => Number(it.face_id)).filter(id => Number.isFinite(id) && id > 0);
    const coverByFaceId = new Map();

    if (faceIds.length > 0) {
      let coverQuery = this.knex('photo_face2filehash as f2')
        .join('photo_index as p', 'p.file_hash', 'f2.file_hash')
        .whereIn('f2.face_id', faceIds)
        .andWhere('p.is_file', 1)
        .andWhere('p.in_trash', 0)
        .select('f2.face_id as face_id', 'f2.file_hash as file_hash', 'p.original_time as original_time', 'p.id as photo_id', 'f2.id as f2_id')
        .orderBy('f2.is_cover', 'desc')
        .orderBy('p.original_time', 'desc')
        .orderBy('p.id', 'desc')
        .orderBy('f2.id', 'desc');
      if (validPaths.length > 0) {
        photoPathQueryUtil.applyPathPrefixFilter(coverQuery, 'p.path', validPaths);
      }
      const coverRows = await coverQuery.catch(() => []);

      for (const r of coverRows) {
        const fid = Number(r && r.face_id ? r.face_id : 0);
        if (!Number.isFinite(fid) || fid <= 0) continue;
        if (coverByFaceId.has(fid)) continue;
        const hash = r && r.file_hash ? String(r.file_hash) : '';
        coverByFaceId.set(fid, hash || null);
      }
    }

    const enriched = items.map(it => {
      const fid = Number(it && it.face_id ? it.face_id : 0);
      const nameBuf = it && it.name ? it.name : null;
      const name = Buffer.isBuffer(nameBuf) && nameBuf.length > 0 ? nameBuf.toString('utf8') : typeof nameBuf === 'string' && nameBuf ? nameBuf : null;
      const isHide = Number(it && it.is_hide ? it.is_hide : 0) || 0;
      const { name: _name, ...rest } = it || {};
      return { ...rest, name, is_hide: isHide, cover_file_hash: coverByFaceId.get(fid) ?? null };
    });

    return {
      items: enriched,
      pagination: {
        total,
        page,
        pageSize,
      },
    };
  }

  async setFaceCover(params = {}) {
    const rawFaceId = Number(params.faceId ?? params.face_id);
    const fileHash = params.fileHash ?? params.file_hash;
    if (!Number.isFinite(rawFaceId) || rawFaceId <= 0 || !fileHash) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    const faceId = await this.getRootFaceId(rawFaceId);
    const hash = String(fileHash);

    await this.knex.transaction(async trx => {
      await trx('photo_face2filehash')
        .where({ face_id: faceId })
        .update({ is_cover: 0 })
        .catch(() => {});
      const changed = await trx('photo_face2filehash')
        .where({ face_id: faceId, file_hash: hash })
        .update({ is_cover: 1 })
        .catch(() => 0);
      if (!changed) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
    });

    return true;
  }

  async updateFaceName(params = {}) {
    const rawFaceId = Number(params.faceId ?? params.face_id);
    const name = params.name;
    if (!Number.isFinite(rawFaceId) || rawFaceId <= 0 || typeof name !== 'string') {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    const faceId = await this.getRootFaceId(rawFaceId);
    const buf = Buffer.from(String(name), 'utf8');
    await this.knex('photo_faces')
      .where({ face_id: faceId })
      .update({ name: buf, update_time: this.knex.fn.now() })
      .catch(() => {});
    return true;
  }

  async refreshFaceAggregateInTrx(trx, faceId, options = {}) {
    const rawFaceId = Number(faceId) || 0;
    if (!rawFaceId) return 0;

    const keepCoverHashRaw = options.keepCoverHash;
    const keepCoverHash = keepCoverHashRaw ? String(keepCoverHashRaw).trim() : '';

    const countRow = await trx('photo_face2filehash')
      .where({ face_id: rawFaceId })
      .countDistinct({ total: 'file_hash' })
      .first()
      .catch(() => ({ total: 0 }));
    const nextCount = Math.max(
      0,
      Number(countRow && countRow.total ? countRow.total : 0) || 0
    );

    await trx('photo_face2filehash')
      .where({ face_id: rawFaceId })
      .update({ is_cover: 0 })
      .catch(() => {});

    let coverHash = '';
    if (keepCoverHash) {
      const keepRow = await trx('photo_face2filehash')
        .where({ face_id: rawFaceId, file_hash: keepCoverHash })
        .first('file_hash')
        .catch(() => null);
      if (keepRow && keepRow.file_hash) {
        coverHash = String(keepRow.file_hash);
      }
    }

    if (!coverHash && nextCount > 0) {
      const coverRow = await trx('photo_face2filehash as f2')
        .join('photo_index as p', 'p.file_hash', 'f2.file_hash')
        .where('f2.face_id', rawFaceId)
        .andWhere('p.is_file', 1)
        .andWhere('p.in_trash', 0)
        .orderBy('p.original_time', 'desc')
        .orderBy('p.id', 'desc')
        .orderBy('f2.id', 'desc')
        .first('f2.file_hash as file_hash')
        .catch(() => null);
      if (coverRow && coverRow.file_hash) {
        coverHash = String(coverRow.file_hash);
      }
    }

    if (coverHash) {
      await trx('photo_face2filehash')
        .where({ face_id: rawFaceId, file_hash: coverHash })
        .update({ is_cover: 1 })
        .catch(() => {});
    }

    await trx('photo_faces')
      .where({ face_id: rawFaceId })
      .update({ face_count: nextCount, update_time: trx.fn.now() })
      .catch(() => {});

    return nextCount;
  }

  async mergeTwoFacesInTrx(trx, fromFaceId, toFaceId) {
    const [fromRow, toRow] = await Promise.all([
      trx('photo_faces')
        .select('face_id', 'face_count', 'name')
        .where({ face_id: fromFaceId })
        .first()
        .catch(() => null),
      trx('photo_faces')
        .select('face_id', 'face_count', 'name')
        .where({ face_id: toFaceId })
        .first()
        .catch(() => null),
    ]);
    if (!fromRow || !toRow) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const isEmptyName = v => v == null || (Buffer.isBuffer(v) ? v.length === 0 : typeof v === 'string' ? v.length === 0 : false);
    const inheritName = isEmptyName(toRow && toRow.name) && !isEmptyName(fromRow && fromRow.name) ? fromRow.name : undefined;

    const toCover = await trx('photo_face2filehash')
      .where({ face_id: toFaceId, is_cover: 1 })
      .first('file_hash')
      .catch(() => null);
    const fromCover = await trx('photo_face2filehash')
      .where({ face_id: fromFaceId, is_cover: 1 })
      .first('file_hash')
      .catch(() => null);
    const keepCoverHash = (toCover && toCover.file_hash ? String(toCover.file_hash) : '') || (fromCover && fromCover.file_hash ? String(fromCover.file_hash) : '');

    await trx
      .raw(
        `INSERT OR IGNORE INTO photo_face2filehash (file_hash, face_id, box_left, box_top, box_width, box_height, is_cover, create_time)
       SELECT file_hash, ?, box_left, box_top, box_width, box_height, 0 as is_cover, create_time FROM photo_face2filehash WHERE face_id = ?`,
        [toFaceId, fromFaceId]
      )
      .catch(() => {});
    await trx('photo_face2filehash')
      .where({ face_id: fromFaceId })
      .del()
      .catch(() => {});

    await trx('photo_face2filehash')
      .where({ face_id: toFaceId })
      .update({ is_cover: 0 })
      .catch(() => {});
    if (keepCoverHash) {
      await trx('photo_face2filehash')
        .where({ face_id: toFaceId, file_hash: keepCoverHash })
        .update({ is_cover: 1 })
        .catch(() => {});
    }

    const fromCount = Math.max(0, Number(fromRow && fromRow.face_count ? fromRow.face_count : 0) || 0);
    const toCount = Math.max(0, Number(toRow && toRow.face_count ? toRow.face_count : 0) || 0);
    const updateTo = { face_count: toCount + fromCount, update_time: trx.fn.now() };
    if (inheritName !== undefined) updateTo.name = inheritName;
    await trx('photo_faces')
      .where({ face_id: toFaceId })
      .update(updateTo)
      .catch(() => {});

    await trx('photo_faces')
      .where({ face_id: fromFaceId })
      .update({ belong_face_id: toFaceId, face_count: 0, update_time: trx.fn.now() })
      .catch(() => {});

    await trx('photo_faces')
      .where({ belong_face_id: fromFaceId })
      .update({ belong_face_id: toFaceId, update_time: trx.fn.now() })
      .catch(() => {});

    return true;
  }

  async mergeFacesMultiple(params = {}) {
    const raw = params.faceIds ?? params.face_ids ?? [];
    if (!Array.isArray(raw) || raw.length < 2) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    const ids = raw.map(v => Number(v)).filter(v => Number.isFinite(v) && v > 0);
    if (ids.length < 2) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    const rootIdsRaw = await Promise.all(ids.map(id => this.getRootFaceId(id)));
    const rootIds = [];
    const seen = new Set();
    for (const id of rootIdsRaw) {
      const fid = Number(id) || 0;
      if (!fid) continue;
      if (seen.has(fid)) continue;
      seen.add(fid);
      rootIds.push(fid);
    }
    if (rootIds.length < 2) return true;

    const fileCountRows = await this.knex('photo_face2filehash')
      .whereIn('face_id', rootIds)
      .groupBy('face_id')
      .select('face_id')
      .countDistinct({ file_count: 'file_hash' })
      .catch(() => []);
    const fileCountById = new Map();
    for (const r of fileCountRows || []) {
      const fid = Number(r && r.face_id ? r.face_id : 0);
      const c = Number(r && r.file_count ? r.file_count : 0) || 0;
      if (fid) fileCountById.set(fid, c);
    }
    const faceCountRows = await this.knex('photo_faces')
      .whereIn('face_id', rootIds)
      .select('face_id', 'face_count')
      .catch(() => []);
    const faceCountById = new Map();
    for (const r of faceCountRows || []) {
      const fid = Number(r && r.face_id ? r.face_id : 0);
      const c = Number(r && r.face_count ? r.face_count : 0) || 0;
      if (fid) faceCountById.set(fid, c);
    }

    let toFaceId = rootIds[0];
    for (const id of rootIds) {
      const a = fileCountById.get(id) ?? 0;
      const b = fileCountById.get(toFaceId) ?? 0;
      if (a > b) {
        toFaceId = id;
        continue;
      }
      if (a < b) continue;
      const fa = faceCountById.get(id) ?? 0;
      const fb = faceCountById.get(toFaceId) ?? 0;
      if (fa > fb) {
        toFaceId = id;
        continue;
      }
      if (fa < fb) continue;
      if (id > toFaceId) toFaceId = id;
    }

    await this.knex.transaction(async trx => {
      for (const fromFaceId of rootIds) {
        if (fromFaceId === toFaceId) continue;
        await this.mergeTwoFacesInTrx(trx, fromFaceId, toFaceId);
      }
    });

    return true;
  }

  async mergeFaces(params = {}) {
    const faceIds = params.faceIds ?? params.face_ids;
    if (Array.isArray(faceIds) && faceIds.length > 0) {
      return this.mergeFacesMultiple({ faceIds });
    }
    const rawFromId = Number(params.fromFaceId ?? params.from_face_id);
    const rawToId = Number(params.toFaceId ?? params.to_face_id);
    if (!Number.isFinite(rawFromId) || rawFromId <= 0 || !Number.isFinite(rawToId) || rawToId <= 0 || rawFromId === rawToId) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const fromFaceId = await this.getRootFaceId(rawFromId);
    const toFaceId = await this.getRootFaceId(rawToId);
    if (!fromFaceId || !toFaceId || fromFaceId === toFaceId) return true;

    await this.knex.transaction(async trx => {
      await this.mergeTwoFacesInTrx(trx, fromFaceId, toFaceId);
    });

    return true;
  }

  async updateFaceStatus(params = {}) {
    const rawFaceId = Number(params.faceId ?? params.face_id);
    const rawStatus = params.status ?? params.state ?? params.is_hide ?? params.isHide;
    if (!Number.isFinite(rawFaceId) || rawFaceId <= 0) {
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
    const faceId = await this.getRootFaceId(rawFaceId);
    await this.knex('photo_faces')
      .where({ face_id: faceId })
      .update({ is_hide: isHide, update_time: this.knex.fn.now() })
      .catch(() => {});
    return true;
  }

  async listPhotoFaces(params = {}) {
    const fileHashRaw = params.fileHash ?? params.file_hash;
    const fileHash = fileHashRaw ? String(fileHashRaw).trim() : '';
    if (!fileHash) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const validPaths = Array.isArray(params.validPaths) ? params.validPaths.filter(Boolean) : [];
    if (Object.prototype.hasOwnProperty.call(params, 'validPaths') && validPaths.length === 0) {
      return [];
    }

    let query = this.knex('photo_face2filehash as f2')
      .join('photo_index as p', 'p.file_hash', 'f2.file_hash')
      .join('photo_faces as pf', 'pf.face_id', 'f2.face_id')
      .where('f2.file_hash', fileHash)
      .andWhere('p.is_file', 1)
      .andWhere('p.in_trash', 0)
      .select(
        'pf.face_id as face_id',
        'pf.face_count as face_count',
        'pf.is_hide as is_hide',
        'pf.name as name'
      )
      .orderBy('pf.face_count', 'desc')
      .orderBy('pf.face_id', 'desc');

    if (validPaths.length > 0) {
      photoPathQueryUtil.applyPathPrefixFilter(query, 'p.path', validPaths);
    }

    const rows = await query.catch(() => []);
    return (Array.isArray(rows) ? rows : []).map(row => {
      const nameBuf = row && row.name ? row.name : null;
      const name =
        Buffer.isBuffer(nameBuf) && nameBuf.length > 0
          ? nameBuf.toString('utf8')
          : typeof nameBuf === 'string' && nameBuf
            ? nameBuf
            : null;
      return {
        face_id: Number(row && row.face_id ? row.face_id : 0) || 0,
        face_count: Number(row && row.face_count ? row.face_count : 0) || 0,
        is_hide: Number(row && row.is_hide ? row.is_hide : 0) || 0,
        name,
      };
    });
  }

  async removePhotoFromFace(params = {}) {
    const rawFaceId = Number(params.faceId ?? params.face_id);
    const fileHashRaw = params.fileHash ?? params.file_hash;
    const fileHash = fileHashRaw ? String(fileHashRaw).trim() : '';
    if (!Number.isFinite(rawFaceId) || rawFaceId <= 0 || !fileHash) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const faceId = await this.getRootFaceId(rawFaceId);

    await this.knex.transaction(async trx => {
      const currentCover = await trx('photo_face2filehash')
        .where({ face_id: faceId, is_cover: 1 })
        .first('file_hash')
        .catch(() => null);
      const existed = await trx('photo_face2filehash as f2')
        .join('photo_index as p', 'p.file_hash', 'f2.file_hash')
        .where('f2.face_id', faceId)
        .andWhere('f2.file_hash', fileHash)
        .andWhere('p.is_file', 1)
        .andWhere('p.in_trash', 0)
        .first('f2.id as id')
        .catch(() => null);
      if (!existed || !existed.id) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }

      const removed = await trx('photo_face2filehash')
        .where({ face_id: faceId, file_hash: fileHash })
        .del()
        .catch(() => 0);
      if (!removed) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }

      await this.refreshFaceAggregateInTrx(trx, faceId, {
        keepCoverHash:
            currentCover && currentCover.file_hash !== fileHash
                ? currentCover.file_hash
                : '',
      });
    });

    return true;
  }

  async movePhotoToFace(params = {}) {
    const rawFromFaceId = Number(params.fromFaceId ?? params.from_face_id);
    const rawToFaceId = Number(params.toFaceId ?? params.to_face_id);
    const rawFileHashes = params.fileHashes ?? params.file_hashes ?? [];
    if (
      !Number.isFinite(rawFromFaceId) ||
      rawFromFaceId <= 0 ||
      !Number.isFinite(rawToFaceId) ||
      rawToFaceId <= 0
    ) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const fileHashes = (Array.isArray(rawFileHashes) ? rawFileHashes : [rawFileHashes])
      .map(v => (v == null ? '' : String(v).trim()))
      .filter(Boolean);
    const uniqueFileHashes = [...new Set(fileHashes)];
    if (uniqueFileHashes.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const fromFaceId = await this.getRootFaceId(rawFromFaceId);
    const toFaceId = await this.getRootFaceId(rawToFaceId);
    if (!fromFaceId || !toFaceId) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    if (fromFaceId === toFaceId) return true;

    await this.knex.transaction(async trx => {
      const fromRow = await trx('photo_faces')
        .where({ face_id: fromFaceId })
        .first('face_id')
        .catch(() => null);
      const toRow = await trx('photo_faces')
        .where({ face_id: toFaceId })
        .first('face_id')
        .catch(() => null);
      if (!fromRow || !toRow) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }

      const currentCover = await trx('photo_face2filehash')
        .where({ face_id: fromFaceId, is_cover: 1 })
        .first('file_hash')
        .catch(() => null);
      const targetCover = await trx('photo_face2filehash')
        .where({ face_id: toFaceId, is_cover: 1 })
        .first('file_hash')
        .catch(() => null);

      const existedRows = await trx('photo_face2filehash as f2')
        .join('photo_index as p', 'p.file_hash', 'f2.file_hash')
        .where('f2.face_id', fromFaceId)
        .whereIn('f2.file_hash', uniqueFileHashes)
        .andWhere('p.is_file', 1)
        .andWhere('p.in_trash', 0)
        .select('f2.file_hash')
        .catch(() => []);
      const movableHashes = [...new Set((existedRows || []).map(row => (row && row.file_hash ? String(row.file_hash) : '')).filter(Boolean))];
      if (movableHashes.length === 0) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }

      const placeholders = movableHashes.map(() => '?').join(', ');
      await trx
        .raw(
          `INSERT OR IGNORE INTO photo_face2filehash (file_hash, face_id, box_left, box_top, box_width, box_height, is_cover, create_time)
           SELECT file_hash, ?, box_left, box_top, box_width, box_height, 0 as is_cover, create_time
           FROM photo_face2filehash
           WHERE face_id = ? AND file_hash IN (${placeholders})`,
          [toFaceId, fromFaceId, ...movableHashes]
        )
        .catch(() => {});

      await trx('photo_face2filehash')
        .where({ face_id: fromFaceId })
        .whereIn('file_hash', movableHashes)
        .del()
        .catch(() => 0);

      await this.refreshFaceAggregateInTrx(trx, fromFaceId, {
        keepCoverHash:
            currentCover && !movableHashes.includes(String(currentCover.file_hash || ''))
                ? currentCover.file_hash
                : '',
      });
      await this.refreshFaceAggregateInTrx(trx, toFaceId, {
        keepCoverHash:
            targetCover && targetCover.file_hash ? targetCover.file_hash : movableHashes.first,
      });
    });

    return true;
  }

  async getFaceImageBuffer(params = {}) {
    const rawFaceId = Number(params.faceId);
    if (!Number.isFinite(rawFaceId) || rawFaceId <= 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    const faceId = await this.getRootFaceId(rawFaceId);

    const fileHash = params.fileHash ? String(params.fileHash) : '';
    const size = Number(params.size);
    const qualityNum = Number(params.quality);
    const quality = Number.isFinite(qualityNum) && qualityNum >= 1 && qualityNum <= 100 ? qualityNum : 85;
    const validPaths = Array.isArray(params.validPaths) ? params.validPaths.filter(Boolean) : [];

    let query = this.knex('photo_face2filehash')
      .join('photo_index', 'photo_index.file_hash', 'photo_face2filehash.file_hash')
      .select(
        'photo_face2filehash.file_hash as file_hash',
        'photo_face2filehash.box_left as box_left',
        'photo_face2filehash.box_top as box_top',
        'photo_face2filehash.box_width as box_width',
        'photo_face2filehash.box_height as box_height',
        'photo_index.path as path',
        'photo_index.filename as filename',
        'photo_index.type as type'
      )
      .where('photo_face2filehash.face_id', faceId)
      .andWhere('photo_index.is_file', 1)
      .andWhere('photo_index.in_trash', 0);

    if (validPaths.length > 0) {
      photoPathQueryUtil.applyPathPrefixFilter(query, 'photo_index.path', validPaths);
    }

    if (fileHash) {
      query = query.andWhere('photo_face2filehash.file_hash', fileHash);
    } else {
      query = query
        .orderBy('photo_face2filehash.is_cover', 'desc')
        .orderByRaw(`CASE WHEN LOWER(COALESCE(photo_index.filename, '')) LIKE '%.jpg' OR LOWER(COALESCE(photo_index.filename, '')) LIKE '%.jpeg' THEN 1 ELSE 0 END DESC`)
        .orderBy('photo_index.original_time', 'desc')
        .orderBy('photo_index.id', 'desc');
    }

    const row = await query.first().catch(() => null);
    if (!row) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const fullPath = path.join(String(row.path || ''), String(row.filename || ''));
    if (!fullPath || !fs.existsSync(fullPath)) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const type = row && row.type ? Number(row.type) : 0;
    let sourcePath = fullPath;
    if (type === 2) {
      try {
        sourcePath = await fileService.getTinyImgByPath(fullPath);
      } catch (_) {
        const err = new Error('common.NOT_FOUND');
        err.statusCode = 404;
        throw err;
      }
    }
    if (!sourcePath || !fs.existsSync(sourcePath)) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const converted = await sharpUtils.transSpcielFormat(sourcePath);
    let img = createSharpFromConverted(converted).rotate();

    const meta = await img.metadata();
    const w = Number(meta && meta.width ? meta.width : 0);
    const h = Number(meta && meta.height ? meta.height : 0);
    if (!w || !h) {
      const err = new Error('common.ERROR');
      err.statusCode = 500;
      throw err;
    }

    const leftRaw = Number(row.box_left);
    const topRaw = Number(row.box_top);
    const widthRaw = Number(row.box_width);
    const heightRaw = Number(row.box_height);

    const left = Number.isFinite(leftRaw) ? leftRaw : 0;
    const top = Number.isFinite(topRaw) ? topRaw : 0;
    const width = Number.isFinite(widthRaw) ? widthRaw : 0;
    const height = Number.isFinite(heightRaw) ? heightRaw : 0;

    const extend = clampNumber(Number(process.env.FACE_IMAGE_EXTEND ?? 0.2), 0, 1);
    const topExtra = clampNumber(Number(process.env.FACE_IMAGE_TOP_EXTRA ?? 0.12), 0, 1);

    const boxW = Math.max(2, Math.floor(width));
    const boxH = Math.max(2, Math.floor(height));
    const cx = left + boxW / 2;
    const cy = top + boxH / 2;
    const base = Math.max(boxW, boxH);

    let cropSize = Math.max(2, Math.round(base * (1 + extend * 2)));
    cropSize = Math.min(cropSize, Math.max(2, Math.min(w, h)));

    let cropLeft = Math.round(cx - cropSize / 2);
    let cropTop = Math.round(cy - cropSize / 2 - base * topExtra);
    cropLeft = Math.max(0, Math.min(w - cropSize, cropLeft));
    cropTop = Math.max(0, Math.min(h - cropSize, cropTop));

    const cropW = Math.max(2, Math.min(w - cropLeft, cropSize));
    const cropH = Math.max(2, Math.min(h - cropTop, cropSize));

    img = img.extract({ left: cropLeft, top: cropTop, width: cropW, height: cropH });
    if (Number.isFinite(size) && size > 0) {
      img = img.resize(size, size, { fit: 'inside' });
    }

    const buffer = await img.jpeg({ quality }).toBuffer();
    return { buffer, mime: 'image/jpeg' };
  }

  async listFacePhotoIndexRows(params = {}) {
    const rawFaceIds = params.faceIds ?? params.face_ids ?? params.faceId ?? params.face_id;
    const validPaths = Array.isArray(params.validPaths) ? params.validPaths : [];
    const faceIdsInput = Array.isArray(rawFaceIds) ? rawFaceIds : rawFaceIds === null || rawFaceIds === undefined ? [] : [rawFaceIds];
    const faceIds = [];
    for (const v of faceIdsInput) {
      if (v === null || v === undefined || v === '') continue;
      if (typeof v === 'string' && v.includes(',')) {
        for (const part of v.split(',')) {
          const id = Number(part);
          if (Number.isFinite(id) && id > 0) faceIds.push(id);
        }
        continue;
      }
      const id = Number(v);
      if (Number.isFinite(id) && id > 0) faceIds.push(id);
    }
    if (faceIds.length === 0) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }

    const rootIds = [];
    for (const id of faceIds) {
      const root = await this.getRootFaceId(id);
      if (Number.isFinite(root) && root > 0) rootIds.push(root);
    }
    const uniqueRootIds = [...new Set(rootIds)];
    if (uniqueRootIds.length === 0) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const query = this.knex('photo_face2filehash as f2')
      .join('photo_index as p', 'p.file_hash', 'f2.file_hash')
      .whereIn('f2.face_id', uniqueRootIds)
      .andWhere('p.is_file', 1)
      .andWhere('p.in_trash', 0)
      .orderBy('p.original_time', 'desc')
      .orderBy('p.id', 'desc');

    if (validPaths.length > 0) {
      photoPathQueryUtil.applyPathPrefixFilter(query, 'p.path', validPaths);
    }

    const rows = await query.select('p.id as photo_id', 'p.path as path', 'p.filename as filename', 'p.file_hash as file_hash', 'p.original_time as original_time').catch(() => []);

    return Array.isArray(rows) ? rows : [];
  }
}

module.exports = FaceService;
