const ResponseUtil = require('../../../apiUtils/responseUtil');
const Logger = require('../../../../utils/logger');
const videoSmartAlbumService = require('./videoSmartAlbumService');

class VideoSmartAlbumController {
  async listSmartAlbums(req, res) {
    try {
      const result = await videoSmartAlbumService.listSmartAlbums({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('listSmartAlbums error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async getSmartAlbum(req, res) {
    try {
      const id = Number((req.body && req.body.id) || (req.query && req.query.id));
      const result = await videoSmartAlbumService.getSmartAlbum({ knexVideo: req.dbVideo }, id, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getSmartAlbum error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async createSmartAlbum(req, res) {
    try {
      const result = await videoSmartAlbumService.createSmartAlbum({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 201);
    } catch (error) {
      Logger.error('createSmartAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async updateSmartAlbum(req, res) {
    try {
      const result = await videoSmartAlbumService.updateSmartAlbum({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('updateSmartAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async deleteSmartAlbum(req, res) {
    try {
      const result = await videoSmartAlbumService.deleteSmartAlbum({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('deleteSmartAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }
}

module.exports = new VideoSmartAlbumController();
