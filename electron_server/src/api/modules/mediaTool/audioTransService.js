const PathUtil = require('../../../utils/pathUtil');
const tableMediaToolAudioTrans = require('../../../db/table/tableMediaToolAudioTrans');

function normalizeString(v) {
  if (v === undefined || v === null) return '';
  return String(v).trim();
}

function buildHttpError(msgKey, statusCode) {
  const err = new Error(String(msgKey || 'common.ERROR'));
  err.statusCode = Number(statusCode || 500) || 500;
  return err;
}

function normalizeTransConfig(raw) {
  if (raw === undefined || raw === null) return '';
  if (typeof raw === 'string') return raw.trim();
  if (typeof raw === 'object') {
    try {
      return JSON.stringify(raw);
    } catch (_) {
      return '';
    }
  }
  return '';
}

class AudioTransService {
  constructor(knexMain) {
    this.knexMain = knexMain;
    this.tableName = 'media_tool_audio_trans';
  }

  async list({ page, pageSize, keyword, sortBy, sortOrder } = {}) {
    const pageNum = Number(page || 1) || 1;
    const hasPageSize = pageSize !== undefined && pageSize !== null;
    const limit = hasPageSize ? Number(pageSize || 20) || 20 : null;
    const offset = limit === null ? 0 : (pageNum - 1) * limit;

    const sortCol = ['id', 'create_time', 'update_time', 'status'].includes(String(sortBy || 'id')) ? String(sortBy || 'id') : 'id';
    const sortDir = String(sortOrder || 'desc').toLowerCase() === 'asc' ? 'asc' : 'desc';

    let q = this.knexMain(this.tableName).select('*');
    let countQ = this.knexMain(this.tableName).count({ c: '*' });

    const kw = normalizeString(keyword);
    if (kw) {
      q = q.andWhere(builder => {
        builder.orWhere('source_path', 'like', `%${kw}%`).orWhere('target_path', 'like', `%${kw}%`);
      });
      countQ = countQ.andWhere(builder => {
        builder.orWhere('source_path', 'like', `%${kw}%`).orWhere('target_path', 'like', `%${kw}%`);
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
      items: rows || [],
    };
  }

  async upsert({ id, sourcePath, targetPath, transConfig, nonAudioPolicy }) {
    const idNum = id === undefined || id === null ? null : Number(id);
    const hasId = Number.isFinite(idNum) && idNum > 0;

    const source = normalizeString(sourcePath);
    const target = normalizeString(targetPath);
    const cfg = normalizeTransConfig(transConfig);
    const pol = normalizeString(nonAudioPolicy).toLowerCase();

    if (!source || !target) throw buildHttpError('common.INVALID_PARAMS', 400);

    const sourceNormalized = PathUtil.normalizeFsPathForCompare(source);
    const targetNormalized = PathUtil.normalizeFsPathForCompare(target);
    if (PathUtil.isMutualConflictPath(sourceNormalized, targetNormalized)) {
      throw buildHttpError('mediaTool.SOURCE_TARGET_PATH_CONFLICT', 400);
    }

    if (!cfg) throw buildHttpError('common.INVALID_PARAMS', 400);
    if (![tableMediaToolAudioTrans.NON_AUDIO_SKIP, tableMediaToolAudioTrans.NON_AUDIO_COPY].includes(pol)) {
      throw buildHttpError('common.INVALID_PARAMS', 400);
    }

    const now = new Date();

    if (hasId) {
      const existed = await this.knexMain(this.tableName).where({ id: idNum }).first();
      if (!existed) throw buildHttpError('common.NOT_FOUND', 404);
      const status = existed && existed.status ? String(existed.status).trim().toLowerCase() : '';
      if (status === tableMediaToolAudioTrans.STATUS_RUNNING) throw buildHttpError('common.ERROR', 409);

      await this.knexMain(this.tableName).where({ id: idNum }).update({
        source_path: source,
        target_path: target,
        trans_config: cfg,
        non_audio_policy: pol,
        update_time: now,
      });
      return { id: idNum };
    }

    const insertData = {
      source_path: source,
      target_path: target,
      trans_config: cfg,
      non_audio_policy: pol,
      status: tableMediaToolAudioTrans.STATUS_STOPPED,
      last_error: null,
      progress: '',
      total_files: 0,
      done_files: 0,
      handled_input_bytes: 0,
      handled_output_bytes: 0,
      processed_count: 0,
      skipped_count: 0,
      non_audio_count: 0,
      create_time: now,
      update_time: now,
      last_start_time: null,
      last_end_time: null,
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
}

module.exports = { AudioTransService };
