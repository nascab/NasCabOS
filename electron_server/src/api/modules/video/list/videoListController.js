const ResponseUtil = require('../../../apiUtils/responseUtil');
const VideoListService = require('./videoListService');

class VideoListController {
  async list(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new VideoListService(req.dbVideo);
      const data = await service.listPaged(body, user);
      return ResponseUtil.success(req, res, data, 'video.VIDEO_LIST_FETCH_SUCCESS', 200);
    } catch (e) {
      console.log(e);
      const msgKey = e && e.message ? e.message : 'video.VIDEO_LIST_FETCH_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'video.VIDEO_LIST_FETCH_FAILED' : msgKey, statusCode);
    }
  }

  async count(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new VideoListService(req.dbVideo);
      const data = await service.getVisibleIndexCounts(body, user);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      console.log(e);
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async historyList(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const service = new VideoListService(req.dbVideo);
      const data = await service.listHistory(user);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      console.log(e);
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async clearHistory(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const service = new VideoListService(req.dbVideo);
      const data = await service.clearHistory(user);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      console.log(e);
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }
}

module.exports = new VideoListController();
