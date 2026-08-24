const ResponseUtil = require('../../../apiUtils/responseUtil');
const BookFavoriteService = require('./bookFavoriteService');

class BookFavoriteController {
  async add(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const indexId = req.body && (req.body.index_id ?? req.body.indexId);
      if (!indexId) return ResponseUtil.error(req, res, 'common.PARAM_ERROR');

      const service = new BookFavoriteService(req.dbBook);
      const data = await service.addFavorite(user, indexId);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async remove(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const indexId = req.body && (req.body.index_id ?? req.body.indexId);
      if (!indexId) return ResponseUtil.error(req, res, 'common.PARAM_ERROR');

      const service = new BookFavoriteService(req.dbBook);
      const data = await service.removeFavorite(user, indexId);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async batch(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const indexIds = req.body && (req.body.index_ids ?? req.body.indexIds);
      if (!Array.isArray(indexIds)) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR');
      }
      const isFavoriteRaw = req.body && (req.body.is_favorite ?? req.body.isFavorite);
      const isFavorite = isFavoriteRaw === true || isFavoriteRaw === 1 || isFavoriteRaw === '1';

      const service = new BookFavoriteService(req.dbBook);
      await service.batchFavorite(user, indexIds, isFavorite);
      return ResponseUtil.success(req, res, null, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }
}

module.exports = new BookFavoriteController();
