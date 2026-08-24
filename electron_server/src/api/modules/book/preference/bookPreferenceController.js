const ResponseUtil = require('../../../apiUtils/responseUtil');
const BookPreferenceService = require('./bookPreferenceService');

class BookPreferenceController {
  async get(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const fileHash = req.query && req.query.file_hash !== undefined && req.query.file_hash !== null ? String(req.query.file_hash).trim() : '';
      if (!fileHash) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);

      const service = new BookPreferenceService(req.dbBook);
      const indexRow = await service.getIndexByFileHash(fileHash);
      if (!indexRow) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const can = await service.canUserAccessIndex(user, indexRow);
      if (!can) return ResponseUtil.forbidden(req, res);

      const pref = await service.getPreference({ uid, fileHash });
      const out = pref || { uid, file_hash: fileHash, font_size: null, spacing: null, flow: null, theme: null, updated_at: null };
      return ResponseUtil.success(req, res, out, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, 500);
    }
  }

  async upsert(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const fileHash = body.file_hash === undefined || body.file_hash === null ? '' : String(body.file_hash).trim();
      if (!fileHash) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);

      const service = new BookPreferenceService(req.dbBook);
      const indexRow = await service.getIndexByFileHash(fileHash);
      if (!indexRow) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const can = await service.canUserAccessIndex(user, indexRow);
      if (!can) return ResponseUtil.forbidden(req, res);

      const fontSize = body.font_size ?? body.fontSize;
      const spacing = body.spacing;
      const flow = body.flow;
      const theme = body.theme;

      const pref = await service.upsertPreference({ uid, fileHash, fontSize, spacing, flow, theme });
      return ResponseUtil.success(req, res, pref, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, 500);
    }
  }
}

module.exports = new BookPreferenceController();
