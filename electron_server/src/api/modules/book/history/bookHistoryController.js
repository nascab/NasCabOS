const ResponseUtil = require('../../../apiUtils/responseUtil');
const BookHistoryService = require('./bookHistoryService');

class BookHistoryController {
  async list(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const service = new BookHistoryService(req.dbBook);
      const data = await service.listHistory({ user, limit: 200 });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async get(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const fileHash = req.query && req.query.file_hash !== undefined && req.query.file_hash !== null ? String(req.query.file_hash).trim() : '';
      if (!fileHash) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);

      const service = new BookHistoryService(req.dbBook);
      const indexRow = await service.getIndexByFileHash(fileHash);
      if (!indexRow) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const can = await service.canUserAccessIndex(user, indexRow);
      if (!can) return ResponseUtil.forbidden(req, res);

      const progress = await service.getProgress({ uid, fileHash });
      const out = progress || {
        uid,
        file_hash: fileHash,
        current_page: 0,
        total_page: Number(indexRow.total_page || 0) || 0,
        fraction: 0,
        last_read_at: null,
      };
      return ResponseUtil.success(req, res, out, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, 500);
    }
  }

  async upsert(req, res) {
    console.log('图书历史设置', req.body);
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const fileHash = body.file_hash === undefined || body.file_hash === null ? '' : String(body.file_hash).trim();
      const currentPage = body.current_page;
      const totalPage = body.total_page;
      const fraction = body.fraction;
      if (!fileHash) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);

      const service = new BookHistoryService(req.dbBook);
      const indexRow = await service.getIndexByFileHash(fileHash);
      if (!indexRow) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const can = await service.canUserAccessIndex(user, indexRow);
      if (!can) return ResponseUtil.forbidden(req, res);

      const mergedTotal = totalPage === undefined || totalPage === null ? Number(indexRow.total_page || 0) || 0 : totalPage;
      const progress = await service.upsertProgress({ uid, fileHash, currentPage, totalPage: mergedTotal, fraction });
      return ResponseUtil.success(req, res, progress, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, 500);
    }
  }

  async clear(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const service = new BookHistoryService(req.dbBook);
      const deleted = await service.clearAll({ user });
      return ResponseUtil.success(req, res, { deleted }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }
}

module.exports = new BookHistoryController();
