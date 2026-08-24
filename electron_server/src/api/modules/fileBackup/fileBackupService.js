const tableFileBackup = require('../../../db/table/tableFileBackup');
const tableFileBackupRecord = require('../../../db/table/tableFileBackupRecord');
const PathUtil = require('../../../utils/pathUtil');

function safeJsonParse(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

function normalizeString(v) {
  if (v === undefined || v === null) return '';
  return String(v).trim();
}

function normalizeStringArray(v) {
  if (!Array.isArray(v)) return [];
  return v.map(x => String(x || '').trim()).filter(Boolean);
}

function buildHttpError(msgKey, statusCode) {
  const err = new Error(String(msgKey || 'common.ERROR'));
  err.statusCode = Number(statusCode || 500) || 500;
  return err;
}

class FileBackupService {
  constructor(knexMain) {
    this.knexMain = knexMain;
    this.tableName = 'file_backup';
    this.recordTableName = 'file_backup_record';
  }

  _mapRow(row) {
    if (!row) return row;
    const source = safeJsonParse(row.source_path);
    const exclude = safeJsonParse(row.exclude_list);
    const taskConfig = safeJsonParse(row.task_config);
    return {
      ...row,
      source_path: Array.isArray(source) ? source : [],
      exclude_list: Array.isArray(exclude) ? exclude : [],
      task_config: taskConfig && typeof taskConfig === 'object' ? taskConfig : null,
    };
  }

  async list({ page, pageSize, status, type, keyword, sortBy, sortOrder } = {}) {
    const pageNum = Number(page || 1) || 1;
    const hasPageSize = pageSize !== undefined && pageSize !== null;
    const limit = hasPageSize ? Number(pageSize || 20) || 20 : null;
    const offset = limit === null ? 0 : (pageNum - 1) * limit;

    const sortCol = ['id', 'create_time', 'last_success_time', 'frenquence', 'status'].includes(String(sortBy || 'id')) ? String(sortBy || 'id') : 'id';
    const sortDir = String(sortOrder || 'desc').toLowerCase() === 'asc' ? 'asc' : 'desc';

    let q = this.knexMain(this.tableName).select('*');
    let countQ = this.knexMain(this.tableName).count({ c: '*' });

    if (status !== undefined && status !== null && String(status).trim()) {
      q = q.where({ status: String(status).trim() });
      countQ = countQ.where({ status: String(status).trim() });
    }
    if (type !== undefined && type !== null && String(type).trim()) {
      q = q.where({ type: String(type).trim() });
      countQ = countQ.where({ type: String(type).trim() });
    }

    const kw = normalizeString(keyword);
    if (kw) {
      q = q.andWhere(builder => {
        builder.orWhere('target_path', 'like', `%${kw}%`).orWhere('source_path', 'like', `%${kw}%`);
      });
      countQ = countQ.andWhere(builder => {
        builder.orWhere('target_path', 'like', `%${kw}%`).orWhere('source_path', 'like', `%${kw}%`);
      });
    }

    const countRows = await countQ;
    const total = Number((countRows && countRows[0] && (countRows[0].c ?? countRows[0]['count(*)'])) || 0) || 0;

    const ordered = q.orderBy(sortCol, sortDir);
    const rows = limit === null ? await ordered : await ordered.limit(limit).offset(offset);

    return {
      page: limit === null ? 1 : pageNum,
      pageSize: limit === null ? total : limit,
      total,
      items: rows.map(r => this._mapRow(r)),
    };
  }

  async get({ id }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) throw buildHttpError('validation.ID_INVALID', 400);
    const row = await this.knexMain(this.tableName).where({ id: idNum }).first();
    if (!row) throw buildHttpError('common.NOT_FOUND', 404);
    return this._mapRow(row);
  }

  async upsert({ id, sourcePathList, type, targetPath, taskConfig, frenquence, excludeList }) {
    const idNum = id === undefined || id === null ? null : Number(id);
    const hasId = Number.isFinite(idNum) && idNum > 0;

    const sourcePaths = normalizeStringArray(sourcePathList);
    const target = normalizeString(targetPath);
    const t = normalizeString(type);

    const freqNum = Number(frenquence);
    if (!sourcePaths.length || !target || (t !== tableFileBackup.TYPE_COPY && t !== tableFileBackup.TYPE_SYNC)) {
      throw buildHttpError('common.INVALID_PARAMS', 400);
    }
    if (!Number.isFinite(freqNum) || freqNum <= 0) {
      throw buildHttpError('common.INVALID_PARAMS', 400);
    }

    const targetNormalized = PathUtil.normalizeFsPathForCompare(target);
    const sourcesNormalized = sourcePaths.map(p => PathUtil.normalizeFsPathForCompare(p)).filter(Boolean);

    for (const src of sourcesNormalized) {
      if (PathUtil.isMutualConflictPath(src, targetNormalized)) {
        throw buildHttpError('fileBackup.SOURCE_TARGET_PATH_CONFLICT', 400);
      }
    }

    for (let i = 0; i < sourcesNormalized.length; i++) {
      for (let j = i + 1; j < sourcesNormalized.length; j++) {
        const a = sourcesNormalized[i];
        const b = sourcesNormalized[j];
        if (PathUtil.isMutualConflictPath(a, b)) {
          throw buildHttpError('fileBackup.SOURCE_PATH_CONFLICT', 400);
        }
      }
    }

    const exclude = normalizeStringArray(excludeList);
    const cfgText = taskConfig && typeof taskConfig === 'object' ? JSON.stringify(taskConfig) : null;

    if (hasId) {
      const existed = await this.knexMain(this.tableName).where({ id: idNum }).first();
      if (!existed) throw buildHttpError('common.NOT_FOUND', 404);

      const updateData = {
        source_path: JSON.stringify(sourcePaths),
        type: t,
        target_path: target,
        task_config: cfgText,
        frenquence: freqNum,
        exclude_list: JSON.stringify(exclude),
      };

      await this.knexMain(this.tableName).where({ id: idNum }).update(updateData);
      return { id: idNum };
    }

    const insertData = {
      source_path: JSON.stringify(sourcePaths),
      type: t,
      target_path: target,
      task_config: cfgText,
      create_time: new Date(),
      status: tableFileBackup.STATUS_STOPPED,
      last_error: null,
      frenquence: freqNum,
      progress: '',
      last_success_time: null,
      exclude_list: JSON.stringify(exclude),
    };
    const [newId] = await this.knexMain(this.tableName).insert(insertData);
    return { id: newId };
  }

  async remove({ id }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) throw buildHttpError('validation.ID_INVALID', 400);
    const existed = await this.knexMain(this.tableName).where({ id: idNum }).first();
    if (!existed) throw buildHttpError('common.NOT_FOUND', 404);
    await this.knexMain(this.tableName).where({ id: idNum }).del();
    return { ok: true };
  }

  _mapRecordRow(row) {
    if (!row) return row;
    const errors = safeJsonParse(row.error_file_list);
    return {
      ...row,
      error_file_list: Array.isArray(errors) ? errors : [],
    };
  }

  async listRecords({ taskId, page, pageSize } = {}) {
    const taskIdNum = Number(taskId);
    if (!Number.isFinite(taskIdNum) || taskIdNum <= 0) throw buildHttpError('validation.ID_INVALID', 400);
    const taskRow = await this.knexMain(this.tableName).where({ id: taskIdNum }).first();
    if (!taskRow) throw buildHttpError('common.NOT_FOUND', 404);

    const pageNum = Number(page || 1) || 1;
    const limit = Math.min(100, Math.max(1, Number(pageSize || 20) || 20));
    const offset = (pageNum - 1) * limit;

    const countRows = await this.knexMain(this.recordTableName).where({ task_id: taskIdNum }).count({ c: '*' });
    const total =
      Number((countRows && countRows[0] && (countRows[0].c ?? countRows[0]['count(*)'])) || 0) || 0;

    const rows = await this.knexMain(this.recordTableName)
      .where({ task_id: taskIdNum })
      .orderBy('id', 'desc')
      .limit(limit)
      .offset(offset);

    return {
      page: pageNum,
      pageSize: limit,
      total,
      max_kept_per_task: tableFileBackupRecord.MAX_ROWS_PER_TASK,
      items: rows.map(r => this._mapRecordRow(r)),
    };
  }
}

module.exports = { FileBackupService };
