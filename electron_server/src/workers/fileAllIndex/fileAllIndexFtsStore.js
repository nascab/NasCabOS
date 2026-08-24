'use strict';

const path = require('path');
const knexUtil = require('../../db/knexUtil');
const dbUtil = require('../../db/dbUtil');

class FileAllIndexFtsStore {
  constructor() {
    this.tableName = 'file_index_fts';
    this.knex = knexUtil.getInstance(dbUtil.DB_PATHS.FILE_DB);
    this.maxInsertChunkSize = 400;
    this.maxWhereInChunkSize = 350;
  }

  _toIntOrNull(v) {
    if (v === null || v === undefined) return null;
    const n = Math.trunc(Number(v));
    if (!Number.isFinite(n)) return null;
    return n;
  }

  _toBoolInt(v) {
    return v ? 1 : 0;
  }

  _normalizeDirPath(p) {
    if (!p) return '';
    let resolved = '';
    try {
      resolved = path.resolve(String(p));
    } catch (_) {
      resolved = String(p);
    }
    if (resolved.length > 1 && resolved.endsWith(path.sep)) resolved = resolved.slice(0, -1);
    return resolved;
  }

  _normalizeRow(r) {
    if (!r) return null;
    const p = this._normalizeDirPath(r.path || r.dirPath || '');
    const filename = r.filename ? String(r.filename) : '';
    const ext = r.ext ? String(r.ext) : '';
    if (!p || !filename) return null;

    const mtimeMs = this._toIntOrNull(r.mtimeMs);
    const size = this._toIntOrNull(r.size);
    const isDir = r.isDir === undefined || r.isDir === null ? (ext === '__dir__' ? 1 : 0) : this._toBoolInt(r.isDir);
    const scanId = this._toIntOrNull(r.scanId);

    const row = { path: p, filename, ext };
    if (mtimeMs !== null) row.mtimeMs = String(mtimeMs);
    if (size !== null) row.size = String(size);
    row.isDir = String(isDir);
    if (scanId !== null) row.scanId = String(scanId);
    return row;
  }

  async clearAll() {
    await this.knex.raw(`DELETE FROM ${this.tableName}`).catch(() => {});
  }

  async insertBatch(rows) {
    if (!rows || rows.length === 0) return 0;
    const cleaned = [];
    for (const r of rows) {
      const row = this._normalizeRow(r);
      if (!row) continue;
      cleaned.push(row);
    }
    if (cleaned.length === 0) return 0;

    await this.knex.transaction(async trx => {
      for (let i = 0; i < cleaned.length; i += this.maxInsertChunkSize) {
        const chunk = cleaned.slice(i, i + this.maxInsertChunkSize);
        await trx(this.tableName).insert(chunk);
      }
    });
    return cleaned.length;
  }

  async upsertFile({ dirPath, filename, ext, mtimeMs = null, size = null, isDir = 0, scanId = null }) {
    const row = this._normalizeRow({ dirPath, filename, ext, mtimeMs, size, isDir, scanId });
    if (!row) return false;

    await this.knex.transaction(async trx => {
      await trx(this.tableName)
        .where({ path: row.path, filename: row.filename })
        .del()
        .catch(() => {});
      await trx(this.tableName)
        .insert(row)
        .catch(() => {});
    });
    return true;
  }

  async upsertFilesBatch(rows) {
    if (!rows || rows.length === 0) return 0;

    const cleaned = [];
    for (const r of rows) {
      const row = this._normalizeRow(r);
      if (!row) continue;
      cleaned.push(row);
    }

    if (cleaned.length === 0) return 0;

    await this.knex.transaction(async trx => {
      for (let i = 0; i < cleaned.length; i += this.maxInsertChunkSize) {
        const chunk = cleaned.slice(i, i + this.maxInsertChunkSize);
        const pairs = chunk.map(r => [r.path, r.filename]);
        try {
          await trx(this.tableName).whereIn(['path', 'filename'], pairs).del();
        } catch (_) {
          for (const row of chunk) {
            await trx(this.tableName)
              .where({ path: row.path, filename: row.filename })
              .del()
              .catch(() => {});
          }
        }
      }
      for (let i = 0; i < cleaned.length; i += this.maxInsertChunkSize) {
        const chunk = cleaned.slice(i, i + this.maxInsertChunkSize);
        await trx(this.tableName)
          .insert(chunk)
          .catch(() => {});
      }
    });
    return cleaned.length;
  }

  async deleteFile({ dirPath, filename }) {
    const p = this._normalizeDirPath(dirPath);
    const name = filename ? String(filename) : '';
    if (!p || !name) return 0;
    const affected = await this.knex(this.tableName)
      .where({ path: p, filename: name })
      .del()
      .catch(() => 0);
    return Number(affected || 0) || 0;
  }

  async deleteByDirPrefix(dirPath) {
    const dir = this._normalizeDirPath(dirPath);
    if (!dir) return 0;
    const prefix = dir.endsWith(path.sep) ? dir : `${dir}${path.sep}`;

    const affected = await this.knex(this.tableName)
      .where(qb => {
        qb.where('path', dir).orWhere('path', 'like', `${prefix}%`);
      })
      .del()
      .catch(() => 0);
    return Number(affected || 0) || 0;
  }

  async upsertFilesBatchIncremental(rows, { scanId }) {
    if (!rows || rows.length === 0) return { total: 0, inserted: 0, updatedScanId: 0 };
    const scan = this._toIntOrNull(scanId);
    if (scan === null) return { total: 0, inserted: 0, updatedScanId: 0 };

    const cleaned = [];
    for (const r of rows) {
      const row = this._normalizeRow({ ...r, scanId: scan });
      if (!row) continue;
      cleaned.push(row);
    }
    if (cleaned.length === 0) return { total: 0, inserted: 0, updatedScanId: 0 };

    let inserted = 0;
    let updatedScanId = 0;

    await this.knex.transaction(async trx => {
      for (let i = 0; i < cleaned.length; i += this.maxWhereInChunkSize) {
        const chunk = cleaned.slice(i, i + this.maxWhereInChunkSize);
        const pairs = chunk.map(r => [r.path, r.filename]);

        let existingRows = [];
        try {
          existingRows = await trx(this.tableName).select('path', 'filename', 'ext', 'mtimeMs', 'size', 'isDir', 'scanId').whereIn(['path', 'filename'], pairs);
        } catch (_) {
          existingRows = [];
        }

        const existingMap = new Map();
        for (const r of existingRows || []) {
          if (!r || !r.path || !r.filename) continue;
          existingMap.set(`${r.path}\n${r.filename}`, r);
        }

        const toInsert = [];
        const toTouch = [];

        for (const row of chunk) {
          const key = `${row.path}\n${row.filename}`;
          const prev = existingMap.get(key);
          if (!prev) {
            toInsert.push(row);
            continue;
          }

          const prevExt = prev.ext ? String(prev.ext) : '';
          const prevMtimeMs = prev.mtimeMs === null || prev.mtimeMs === undefined ? '' : String(prev.mtimeMs);
          const prevSize = prev.size === null || prev.size === undefined ? '' : String(prev.size);
          const prevIsDir = prev.isDir === null || prev.isDir === undefined ? '' : String(prev.isDir);

          const same =
            prevExt === String(row.ext || '') &&
            prevMtimeMs === (row.mtimeMs === undefined ? '' : String(row.mtimeMs)) &&
            prevSize === (row.size === undefined ? '' : String(row.size)) &&
            prevIsDir === (row.isDir === undefined ? '' : String(row.isDir));

          if (same) toTouch.push([row.path, row.filename]);
          else toInsert.push(row);
        }

        if (toTouch.length > 0) {
          try {
            const affected = await trx(this.tableName)
              .whereIn(['path', 'filename'], toTouch)
              .update({ scanId: String(scan) });
            updatedScanId += Number(affected || 0) || 0;
          } catch (_) {
            for (const [p, f] of toTouch) {
              const affected = await trx(this.tableName)
                .where({ path: p, filename: f })
                .update({ scanId: String(scan) })
                .catch(() => 0);
              updatedScanId += Number(affected || 0) || 0;
            }
          }
        }

        if (toInsert.length > 0) {
          for (let di = 0; di < toInsert.length; di += this.maxInsertChunkSize) {
            const delChunk = toInsert.slice(di, di + this.maxInsertChunkSize);
            const delPairs = delChunk.map(r => [r.path, r.filename]);
            try {
              await trx(this.tableName).whereIn(['path', 'filename'], delPairs).del();
            } catch (_) {
              for (const row of delChunk) {
                await trx(this.tableName)
                  .where({ path: row.path, filename: row.filename })
                  .del()
                  .catch(() => {});
              }
            }
          }

          for (let ii = 0; ii < toInsert.length; ii += this.maxInsertChunkSize) {
            const insChunk = toInsert.slice(ii, ii + this.maxInsertChunkSize);
            await trx(this.tableName)
              .insert(insChunk)
              .catch(() => {});
          }
          inserted += toInsert.length;
        }
      }
    });

    return { total: cleaned.length, inserted, updatedScanId };
  }

  async deleteRowsNotInScanIdUnderRoots(scanId, roots) {
    const scan = this._toIntOrNull(scanId);
    if (scan === null) return 0;
    const list = Array.isArray(roots) ? roots : [];
    const cleanedRoots = list.map(r => this._normalizeDirPath(r)).filter(Boolean);
    if (cleanedRoots.length === 0) return 0;

    let total = 0;
    for (const root of cleanedRoots) {
      const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
      const affected = await this.knex(this.tableName)
        .where('scanId', '!=', String(scan))
        .andWhere(qb => {
          qb.where('path', root).orWhere('path', 'like', `${prefix}%`);
        })
        .del()
        .catch(() => 0);
      total += Number(affected || 0) || 0;
    }
    return total;
  }
}

module.exports = FileAllIndexFtsStore;
