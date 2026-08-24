const ResponseUtil = require('../../../apiUtils/responseUtil');
const Logger = require('../../../../utils/logger');
const userUtil = require('../../../../utils/userUtil');
const videoAlbumService = require('./videoAlbumService');
const videoCollectionService = require('../collection/videoCollectionService');
const videoSmartAlbumService = require('../smartAlbum/videoSmartAlbumService');

class VideoAlbumController {
  async listAlbums(req, res) {
    try {
      const result = await videoAlbumService.listAlbums({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('listAlbums error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async getAlbumOverview(req, res) {
    try {
      const body = req.body || {};
      const limit = Math.max(1, Math.min(12, Number(body.limit || 6)));

      const [albumResp, collectionResp, smartAlbumResp] = await Promise.all([
        videoAlbumService.listAlbums(
          { knexVideo: req.dbVideo },
          {
            page: 1,
            pageSize: limit * 3,
            sortField: 'create_time',
            sortOrder: 'desc',
            previewLimit: 1,
          },
          req.user
        ),
        videoCollectionService.listCollections(
          { knexVideo: req.dbVideo },
          {
            page: 1,
            pageSize: limit,
            sortField: 'create_time',
            sortOrder: 'desc',
            previewLimit: 1,
          },
          req.user
        ),
        videoSmartAlbumService.listSmartAlbums(
          { knexVideo: req.dbVideo },
          {
            page: 1,
            pageSize: limit,
            sortField: 'create_time',
            sortOrder: 'desc',
            previewLimit: 1,
          },
          req.user
        ),
      ]);

      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      const isAdmin = userUtil.isAdmin(req.user);
      const albumItems = (albumResp && albumResp.items) || [];
      const albums = (isAdmin ? albumItems : albumItems.filter(a => a && Number(a.owner_id) === Number(uid))).slice(0, limit);
      const collections = ((collectionResp && collectionResp.items) || []).slice(0, limit);
      const smartAlbums = ((smartAlbumResp && smartAlbumResp.items) || []).slice(0, limit);

      return ResponseUtil.success(
        req,
        res,
        {
          albums: { items: albums, total: albumResp?.pagination?.total ?? 0 },
          collections: { items: collections, total: collectionResp?.pagination?.total ?? 0 },
          smart_albums: { items: smartAlbums, total: smartAlbumResp?.pagination?.total ?? 0 },
        },
        'common.SUCCESS',
        200
      );
    } catch (error) {
      Logger.error('getAlbumOverview error:', error);
      const statusCode = error.statusCode || 500;
      if (error && error.args) {
        return ResponseUtil.errorWithArgs(req, res, error.message || 'common.ERROR', error.args, statusCode);
      }
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async getAlbum(req, res) {
    try {
      const { id } = req.body || {};
      const result = await videoAlbumService.getAlbum({ knexVideo: req.dbVideo }, id, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getAlbum error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async createAlbum(req, res) {
    try {
      const result = await videoAlbumService.createAlbum({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 201);
    } catch (error) {
      Logger.error('createAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async updateAlbum(req, res) {
    try {
      await videoAlbumService.updateAlbum({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, true, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('updateAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async deleteAlbum(req, res) {
    try {
      const result = await videoAlbumService.deleteAlbum({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('deleteAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async addAlbumIndexes(req, res) {
    try {
      const result = await videoAlbumService.addAlbumIndexes({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('addAlbumIndexes error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async removeAlbumIndexes(req, res) {
    try {
      const result = await videoAlbumService.removeAlbumIndexes({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('removeAlbumIndexes error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async setAlbumCover(req, res) {
    try {
      const result = await videoAlbumService.setAlbumCover({ knexVideo: req.dbVideo }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('setAlbumCover error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }
}

module.exports = new VideoAlbumController();
