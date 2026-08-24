const ResponseUtil = require('../../../apiUtils/responseUtil');
const Logger = require('../../../../utils/logger');
const videoCollectionService = require('./videoCollectionService');

class VideoCollectionController {
  async listCollections(req, res) {
    try {
      const result = await videoCollectionService.listCollections({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('listCollections error:', error);
      const statusCode = error.statusCode || 500;
      if (error && error.args) {
        return ResponseUtil.errorWithArgs(req, res, error.message || 'common.ERROR', error.args, statusCode);
      }
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async getCollection(req, res) {
    try {
      const { id } = req.body || {};
      const result = await videoCollectionService.getCollection({ knexVideo: req.dbVideo }, id, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getCollection error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async createCollection(req, res) {
    try {
      const result = await videoCollectionService.createCollection({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 201);
    } catch (error) {
      Logger.error('createCollection error:', error);
      const statusCode = error.statusCode || 400;
      if (error && error.args) {
        return ResponseUtil.errorWithArgs(req, res, error.message || 'common.ERROR', error.args, statusCode);
      }
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async updateCollection(req, res) {
    try {
      await videoCollectionService.updateCollection({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, true, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('updateCollection error:', error);
      const statusCode = error.statusCode || 400;
      if (error && error.args) {
        return ResponseUtil.errorWithArgs(req, res, error.message || 'common.ERROR', error.args, statusCode);
      }
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async deleteCollection(req, res) {
    try {
      const result = await videoCollectionService.deleteCollection({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('deleteCollection error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }
}

module.exports = new VideoCollectionController();
