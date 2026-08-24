const path = require('path');
const knexUtil = require('../../../../db/knexUtil');
const dbUtil = require('../../../../db/dbUtil');
const userUtil = require('../../../../utils/userUtil');

class MusicSourceService {
  constructor(knex) {
    this.knex = knex;
    this.tableName = 'music_source';
  }

  async listSources() {
    const rows = await this.knex(this.tableName).select('*').orderBy('id', 'asc');
    return (rows || []).map(r => {
      const showType = r && r.show_type ? String(r.show_type) : '';
      return { ...r, show_type: showType || 'music' };
    });
  }

  async getValidPaths(user) {
    const sources = await this.knex(this.tableName)
      .select('path')
      .catch(() => []);
    const sourcePaths = (sources || []).map(s => (s && s.path ? String(s.path) : '')).filter(Boolean);
    if (sourcePaths.length === 0) return [];

    if (userUtil.isAdmin(user)) {
      return sourcePaths;
    }

    const uid = user && user.id ? Number(user.id) : 0;
    if (!uid) return [];

    const mainKnex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const permissions = await mainKnex('user_permission')
      .where({
        uid,
        action: 'view',
        res_type: 'file',
      })
      .select('res_path')
      .catch(() => []);
    const permissionPaths = (permissions || []).map(p => (p && p.res_path ? String(p.res_path) : '')).filter(Boolean);
    if (permissionPaths.length === 0) return [];

    const validPaths = [];
    for (const pPath of permissionPaths) {
      for (const sPath of sourcePaths) {
        if (String(pPath).startsWith(String(sPath)) || String(sPath).startsWith(String(pPath))) {
          validPaths.push(String(pPath).length > String(sPath).length ? pPath : sPath);
        }
      }
    }
    return [...new Set(validPaths)];
  }

  normalizePath(inputPath) {
    const p = String(inputPath || '').trim();
    if (!p) return '';
    return path.resolve(p);
  }

  isParentPath(parentPath, childPath) {
    const parent = String(parentPath || '');
    const child = String(childPath || '');
    if (!parent || !child) return false;
    if (parent === child) return false;

    const parentWithSep = parent.endsWith(path.sep) ? parent : `${parent}${path.sep}`;
    return child.startsWith(parentWithSep);
  }

  isChildPath(parentPath, childPath) {
    return this.isParentPath(parentPath, childPath);
  }

  async addSource(inputPath) {
    const normalizedPath = this.normalizePath(inputPath);
    if (!normalizedPath) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    const rows = await this.knex(this.tableName).select('id', 'path').orderBy('id', 'asc');

    const exact = rows.find(r => r.path === normalizedPath);
    if (exact) {
      throw new Error('music.MUSIC_SOURCE_EXISTS');
    }

    const parentRow = rows.find(r => this.isParentPath(r.path, normalizedPath));
    if (parentRow) {
      const err = new Error('music.MUSIC_SOURCE_PARENT_EXISTS');
      err.args = [normalizedPath, parentRow.path];
      throw err;
    }

    const childRows = rows.filter(r => this.isChildPath(normalizedPath, r.path));
    if (childRows.length > 0) {
      const keep = childRows[0];
      const removeIds = childRows.slice(1).map(r => r.id);

      const row = await this.knex.transaction(async trx => {
        await trx(this.tableName).where({ id: keep.id }).update({
          path: normalizedPath,
          scan_when_start: 1,
        });
        if (removeIds.length > 0) {
          await trx(this.tableName).whereIn('id', removeIds).delete();
        }
        return trx(this.tableName).where({ id: keep.id }).first();
      });

      return { row, action: 'update' };
    }

    const row = await this.knex.transaction(async trx => {
      const [id] = await trx(this.tableName).insert({
        path: normalizedPath,
        scan_when_start: 1,
        ctime: new Date(),
      });
      return trx(this.tableName).where({ id }).first();
    });

    return { row, action: 'insert' };
  }

  async deleteSource({ id, path: inputPath }) {
    const deleteById = Number(id);
    const deleteByPath = this.normalizePath(inputPath);
    const shouldDeleteById = Number.isFinite(deleteById) && deleteById > 0;
    const shouldDeleteByPath = !shouldDeleteById && !!deleteByPath;
    if (!shouldDeleteById && !shouldDeleteByPath) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    return this.knex.transaction(async trx => {
      const totalRow = await trx(this.tableName)
        .count({ cnt: 'id' })
        .first()
        .catch(() => ({ cnt: 0 }));
      const totalCount = Number(totalRow && totalRow.cnt ? totalRow.cnt : 0) || 0;

      const target = shouldDeleteById ? await trx(this.tableName).where({ id: deleteById }).first('id', 'path') : await trx(this.tableName).where({ path: deleteByPath }).first('id', 'path');

      if (!target || !target.id) return 0;

      const affected = await trx(this.tableName).where({ id: target.id }).delete();
      if (!affected) return 0;

      if (totalCount <= 1) {
        await trx('music_index')
          .delete()
          .catch(() => {});
        await trx('music_scan_task')
          .delete()
          .catch(() => {});
        return affected;
      }

      const resolved = target.path ? String(target.path) : '';
      if (!resolved) return affected;

      const scanPrefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;
      await trx('music_index')
        .where(qb => {
          qb.where('path', resolved).orWhere('path', 'like', `${scanPrefix}%`);
        })
        .delete()
        .catch(() => {});

      const parentDir = path.dirname(resolved);
      const folderName = path.basename(resolved);
      if (parentDir && folderName) {
        await trx('music_index')
          .where({ path: parentDir, filename: folderName })
          .delete()
          .catch(() => {});
      }

      await trx('music_scan_task')
        .where({ scan_path: resolved })
        .delete()
        .catch(() => {});

      return affected;
    });
  }

  async updateSource(id, payload = {}) {
    const sourceId = Number(id);
    if (!Number.isFinite(sourceId) || sourceId <= 0) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    const data = {};
    const bool01 = v => {
      if (v === true) return 1;
      if (v === false) return 0;
      const n = Number(v);
      if (n === 0 || n === 1) return n;
      return null;
    };

    if (payload.scan_when_start !== undefined) {
      const v = bool01(payload.scan_when_start);
      if (v === null) throw new Error('validation.VALIDATION_ERROR');
      data.scan_when_start = v;
    }
    if (payload.scan_when_change !== undefined) {
      const v = bool01(payload.scan_when_change);
      if (v === null) throw new Error('validation.VALIDATION_ERROR');
      data.scan_when_change = v;
    }
    if (payload.is_show !== undefined) {
      const v = bool01(payload.is_show);
      if (v === null) throw new Error('validation.VALIDATION_ERROR');
      data.is_show = v;
    }
    if (payload.scan_interval !== undefined) {
      const v = bool01(payload.scan_interval);
      if (v === null) throw new Error('validation.VALIDATION_ERROR');
      data.scan_interval = v;
    }
    if (payload.scan_interval_ms !== undefined) {
      const n = Number(payload.scan_interval_ms);
      if (!Number.isFinite(n) || n < 0) throw new Error('validation.VALIDATION_ERROR');
      data.scan_interval_ms = Math.floor(n);
    }
    if (payload.scan_interval_config !== undefined) {
      data.scan_interval_config = String(payload.scan_interval_config);
    }
    if (payload.last_scan_time !== undefined) {
      const n = Number(payload.last_scan_time);
      if (!Number.isFinite(n) || n < 0) throw new Error('validation.VALIDATION_ERROR');
      data.last_scan_time = Math.floor(n);
    }

    if (payload.show_type !== undefined) {
      const raw = payload.show_type === null ? '' : String(payload.show_type).trim().toLowerCase();
      if (raw) {
        if (raw !== 'music' && raw !== 'series') throw new Error('validation.VALIDATION_ERROR');
        data.show_type = raw;
      }
    }

    if (Object.keys(data).length === 0) throw new Error('validation.VALIDATION_ERROR');

    const result = await this.knex.transaction(async trx => {
      const current = await trx(this.tableName).where({ id: sourceId }).first();
      if (!current) throw new Error('common.NOT_FOUND');

      const resolved = current && current.path ? String(current.path) : '';
      const oldShowType = current && current.show_type ? String(current.show_type) : 'music';
      const newShowType = data.show_type ? String(data.show_type) : '';

      const showTypeChanged = !!newShowType && newShowType !== oldShowType;
      if (showTypeChanged && resolved) {
        const scanPrefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;
        await trx('music_index')
          .where(qb => {
            qb.where('path', resolved).orWhere('path', 'like', `${scanPrefix}%`);
          })
          .delete()
          .catch(() => {});

        const parentDir = path.dirname(resolved);
        const folderName = path.basename(resolved);
        if (parentDir && folderName) {
          await trx('music_index')
            .where({ path: parentDir, filename: folderName })
            .delete()
            .catch(() => {});
        }

        const existedTask = await trx('music_scan_task')
          .where({ scan_path: resolved })
          .first('id')
          .catch(() => null);
        if (!existedTask || !existedTask.id) {
          await trx('music_scan_task')
            .insert({
              scan_path: resolved,
              remark: 'source_show_type_change',
              create_time: new Date(),
            })
            .catch(() => {});
        }
      }

      await trx(this.tableName).where({ id: sourceId }).update(data);
      const row = await trx(this.tableName).where({ id: sourceId }).first();
      if (!row) throw new Error('common.NOT_FOUND');
      return { row, showTypeChanged, scanPath: resolved };
    });

    if (result && result.row) {
      const out = { ...result.row };
      const showType = out && out.show_type ? String(out.show_type) : '';
      out.show_type = showType || 'music';
      if (result.showTypeChanged && result.scanPath) out.rescan_scan_path = String(result.scanPath);
      return out;
    }
    throw new Error('common.NOT_FOUND');
  }

  async relocateSource(id, newPath) {
    const sourceId = Number(id);
    if (!Number.isFinite(sourceId) || sourceId <= 0) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    const normalizedNewPath = this.normalizePath(newPath);
    if (!normalizedNewPath) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    return this.knex.transaction(async trx => {
      const source = await trx(this.tableName).where({ id: sourceId }).first('id', 'path');
      if (!source || !source.id) {
        throw new Error('common.NOT_FOUND');
      }

      const oldPath = source.path ? this.normalizePath(source.path) : '';
      if (!oldPath) {
        throw new Error('validation.VALIDATION_ERROR');
      }

      if (oldPath === normalizedNewPath) {
        return { source_id: sourceId, old_path: oldPath, new_path: normalizedNewPath, updated: 0 };
      }

      const rows = await trx(this.tableName).select('id', 'path').orderBy('id', 'asc');
      const otherRows = (rows || []).filter(r => Number(r.id) !== sourceId);

      const exact = otherRows.find(r => r.path === normalizedNewPath);
      if (exact) {
        throw new Error('music.MUSIC_SOURCE_EXISTS');
      }

      const parentRow = otherRows.find(r => this.isParentPath(r.path, normalizedNewPath));
      if (parentRow) {
        const err = new Error('music.MUSIC_SOURCE_PARENT_EXISTS');
        err.args = [normalizedNewPath, parentRow.path];
        throw err;
      }

      const childRows = otherRows.filter(r => this.isChildPath(normalizedNewPath, r.path));
      if (childRows.length > 0) {
        const err = new Error('music.MUSIC_SOURCE_PARENT_EXISTS');
        err.args = [childRows[0].path, normalizedNewPath];
        throw err;
      }

      await trx(this.tableName).where({ id: sourceId }).update({ path: normalizedNewPath });

      await trx('music_scan_task')
        .where({ scan_path: oldPath })
        .update({ scan_path: normalizedNewPath })
        .catch(() => {});

      const oldPrefix = oldPath.endsWith(path.sep) ? oldPath : `${oldPath}${path.sep}`;
      const newPrefix = normalizedNewPath.endsWith(path.sep) ? normalizedNewPath : `${normalizedNewPath}${path.sep}`;

      const updatedDirect = await trx('music_index')
        .where({ path: oldPath })
        .update({ path: normalizedNewPath })
        .catch(() => 0);

      const startAt = oldPrefix.length + 1;
      const updatedSubtree = await trx('music_index')
        .where('path', 'like', `${oldPrefix}%`)
        .update({
          path: trx.raw(`? || substr(path, ?)`, [newPrefix, startAt]),
        })
        .catch(() => 0);

      const oldParent = path.dirname(oldPath);
      const oldName = path.basename(oldPath);
      const newParent = path.dirname(normalizedNewPath);
      const newName = path.basename(normalizedNewPath);

      const updatedRootDirIndex = await trx('music_index')
        .where({ path: oldParent, filename: oldName })
        .update({ path: newParent, filename: newName })
        .catch(() => 0);

      return {
        source_id: sourceId,
        old_path: oldPath,
        new_path: normalizedNewPath,
        updated: 1,
        updated_index_paths: Number(updatedDirect || 0) + Number(updatedSubtree || 0),
        updated_root_dir_index: Number(updatedRootDirIndex || 0),
      };
    });
  }
}

module.exports = MusicSourceService;
