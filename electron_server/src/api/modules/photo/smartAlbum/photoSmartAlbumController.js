const ResponseUtil = require('../../../apiUtils/responseUtil');
const Logger = require('../../../../utils/logger');
const photoSmartAlbumService = require('./photoSmartAlbumService');

class PhotoSmartAlbumController {
  async listSmartAlbums(req, res) {
    try {
      const result = await photoSmartAlbumService.listSmartAlbums({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('listSmartAlbums error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async getSmartAlbum(req, res) {
    try {
      const { id } = req.body || {};
      const result = await photoSmartAlbumService.getSmartAlbum({ knexPhoto: req.dbPhoto }, id, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getSmartAlbum error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async createSmartAlbum(req, res) {
    try {
      const result = await photoSmartAlbumService.createSmartAlbum({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 201);
    } catch (error) {
      Logger.error('createSmartAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async updateSmartAlbum(req, res) {
    try {
      await photoSmartAlbumService.updateSmartAlbum({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, true, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('updateSmartAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async deleteSmartAlbum(req, res) {
    try {
      const result = await photoSmartAlbumService.deleteSmartAlbum({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('deleteSmartAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }
}

module.exports = new PhotoSmartAlbumController();
