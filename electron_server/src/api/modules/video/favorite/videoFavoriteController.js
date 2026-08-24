const ResponseUtil = require('../../../apiUtils/responseUtil');
const VideoFavoriteService = require('./videoFavoriteService');

class VideoFavoriteController {
  async add(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const indexId = req.body && (req.body.index_id ?? req.body.indexId);
      if (!indexId) return ResponseUtil.error(req, res, 'common.PARAM_ERROR');

      const service = new VideoFavoriteService(req.dbVideo);
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

      const service = new VideoFavoriteService(req.dbVideo);
      const data = await service.removeFavorite(user, indexId);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }
}

module.exports = new VideoFavoriteController();
