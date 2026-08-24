const ResponseUtil = require('../../../apiUtils/responseUtil');
const VideoHomeService = require('./videoHomeService');

class VideoHomeController {
  async getHomeData(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new VideoHomeService(req.dbVideo, req.user);
      const data = await service.getHomeData({
        recommendLimit: body.recommend_limit ?? body.recommendLimit,
        recentPlayLimit: body.recent_play_limit ?? body.recentPlayLimit,
        recentAddLimit: body.recent_add_limit ?? body.recentAddLimit,
      });
      return ResponseUtil.success(req, res, data, 'video.VIDEO_HOME_DATA_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'video.VIDEO_HOME_DATA_FAILED' : msgKey, statusCode);
    }
  }
}

module.exports = new VideoHomeController();
