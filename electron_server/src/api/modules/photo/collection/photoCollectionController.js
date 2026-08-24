const ResponseUtil = require('../../../apiUtils/responseUtil');
const Logger = require('../../../../utils/logger');
const photoCollectionService = require('./photoCollectionService');

class PhotoCollectionController {
  async listCollections(req, res) {
    try {
      const result = await photoCollectionService.listCollections({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
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
      const result = await photoCollectionService.getCollection({ knexPhoto: req.dbPhoto }, id, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getCollection error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async createCollection(req, res) {
    try {
      const result = await photoCollectionService.createCollection({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
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
      await photoCollectionService.updateCollection({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
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
      const result = await photoCollectionService.deleteCollection({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('deleteCollection error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }
}

module.exports = new PhotoCollectionController();
