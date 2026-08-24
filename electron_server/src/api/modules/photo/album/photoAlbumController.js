const ResponseUtil = require('../../../apiUtils/responseUtil');
const Logger = require('../../../../utils/logger');
const photoAlbumService = require('./photoAlbumService');
const photoCollectionService = require('../collection/photoCollectionService');
const photoSmartAlbumService = require('../smartAlbum/photoSmartAlbumService');
const archiver = require('archiver');
const path = require('path');
const fs = require('fs');
const photoTimeLineService = require('../timeline/photoTimeLineService');
const FaceService = require('../face/faceService');

class PhotoAlbumController {
  async listAlbums(req, res) {
    try {
      const result = await photoAlbumService.listAlbums(
        { knexPhoto: req.dbPhoto, knexMain: req.dbMain },
        req.body || {},
        req.user
      );
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
        photoAlbumService.listAlbums(
          { knexPhoto: req.dbPhoto, knexMain: req.dbMain },
          {
            page: 1,
            pageSize: limit * 3,
            sortField: 'create_time',
            sortOrder: 'desc',
            type: 'all',
            previewLimit: 1,
          },
          req.user
        ),
        photoCollectionService.listCollections(
          { knexPhoto: req.dbPhoto },
          {
            page: 1,
            pageSize: limit,
            sortField: 'create_time',
            sortOrder: 'desc',
            previewLimit: 1,
          },
          req.user
        ),
        photoSmartAlbumService.listSmartAlbums(
          { knexPhoto: req.dbPhoto },
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

      const albums = ((albumResp && albumResp.items) || []).filter(a => a && a.is_owner).slice(0, limit);
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
      const result = await photoAlbumService.getAlbum({ knexPhoto: req.dbPhoto, knexMain: req.dbMain }, id, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('getAlbum error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async createAlbum(req, res) {
    try {
      const result = await photoAlbumService.createAlbum({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 201);
    } catch (error) {
      Logger.error('createAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async updateAlbum(req, res) {
    try {
      await photoAlbumService.updateAlbum({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, true, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('updateAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async deleteAlbum(req, res) {
    try {
      const result = await photoAlbumService.deleteAlbum({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('deleteAlbum error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async addAlbumIndexes(req, res) {
    try {
      const result = await photoAlbumService.addAlbumIndexes({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('addAlbumIndexes error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async removeAlbumIndexes(req, res) {
    try {
      const result = await photoAlbumService.removeAlbumIndexes({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('removeAlbumIndexes error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async setAlbumCover(req, res) {
    try {
      const result = await photoAlbumService.setAlbumCover({ knexPhoto: req.dbPhoto }, req.body || {}, req.user);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (error) {
      Logger.error('setAlbumCover error:', error);
      const statusCode = error.statusCode || 400;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async getDownloadInfo(req, res) {
    try {
      const body = req.body || {};
      const rawType = body.albumType ?? body.album_type ?? body.type ?? 'album';
      const albumType = String(rawType || 'album').toLowerCase();
      const rawId = body.albumId ?? body.album_id ?? body.id ?? body.faceId ?? body.face_id;
      const albumId = Number(rawId);
      if (!Number.isFinite(albumId) || albumId <= 0) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const validPathsRaw = await photoTimeLineService.getValidPaths(req.user);
      const validPathsForQuery = (validPathsRaw || []).map(p => (p ? String(p) : '')).filter(Boolean);
      if (validPathsForQuery.length === 0) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }
      const validPathsResolved = validPathsForQuery.map(p => path.resolve(String(p)));

      const isUnder = (filePath, dirPath) => {
        const fileResolved = path.resolve(String(filePath || ''));
        const dirResolved = path.resolve(String(dirPath || ''));
        if (!fileResolved || !dirResolved) return false;
        if (fileResolved === dirResolved) return true;
        const prefix = dirResolved.endsWith(path.sep) ? dirResolved : dirResolved + path.sep;
        return fileResolved.startsWith(prefix);
      };

      let rows = [];
      let name = '';
      let dedupePrefix = '';
      if (albumType === 'face') {
        const service = new FaceService(req.dbPhoto);
        const rootId = await service.getRootFaceId(albumId);
        const faceRow = await req
          .dbPhoto('photo_faces')
          .select('name')
          .where({ face_id: rootId })
          .first()
          .catch(() => null);
        const nameBuf = faceRow && faceRow.name ? faceRow.name : null;
        const faceName = Buffer.isBuffer(nameBuf) && nameBuf.length > 0 ? nameBuf.toString('utf8') : typeof nameBuf === 'string' && nameBuf ? nameBuf : '';
        name = faceName || `face_${rootId}`;
        dedupePrefix = 'face';
        rows = await service.listFacePhotoIndexRows({
          faceId: rootId,
          validPaths: validPathsForQuery,
        });
      } else if (albumType === 'album') {
        const album = await photoAlbumService.getAlbum({ knexPhoto: req.dbPhoto, knexMain: req.dbMain }, albumId, req.user);
        name = album && album.name ? String(album.name) : `album_${albumId}`;
        dedupePrefix = 'album';
        rows = await photoAlbumService.listAlbumPhotoIndexRows(
          { knexPhoto: req.dbPhoto },
          {
            albumId,
            validPaths: validPathsForQuery,
          },
          req.user
        );
      } else {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const seen = new Set();
      const usedNames = new Set();
      const rawFiles = [];

      for (const r of rows) {
        const dir = r && r.path ? String(r.path) : '';
        const filename = r && r.filename ? String(r.filename) : '';
        if (!dir || !filename) continue;
        const fullPath = path.resolve(path.join(dir, filename));
        if (seen.has(fullPath)) continue;
        if (validPathsResolved.length > 0 && !validPathsResolved.some(vp => isUnder(fullPath, vp))) continue;

        let st = null;
        try {
          st = await fs.promises.stat(fullPath);
          if (!st || !st.isFile()) continue;
        } catch (_) {
          continue;
        }

        seen.add(fullPath);
        rawFiles.push({
          fullPath,
          filename,
          size: Number(st.size) || 0,
          photoId: Number(r && r.photo_id ? r.photo_id : r && r.photoId ? r.photoId : 0) || 0,
          albumId: Number(r && r.album_id ? r.album_id : r && r.albumId ? r.albumId : 0) || 0,
        });
        if (rawFiles.length >= 10000) break;
      }

      const items = [];
      let totalSize = 0;
      for (const item of rawFiles) {
        const base = path.basename(item.filename || item.fullPath);
        let entryName = base || 'photo';
        if (usedNames.has(entryName)) {
          if (dedupePrefix === 'album') {
            const aid = item.albumId > 0 ? String(item.albumId) : 'alb';
            const pid = item.photoId > 0 ? String(item.photoId) : 'dup';
            entryName = `${aid}_${pid}_${entryName}`;
          } else {
            const pid = item.photoId > 0 ? String(item.photoId) : 'dup';
            entryName = `${pid}_${entryName}`;
          }
        }
        let i = 1;
        while (usedNames.has(entryName)) {
          if (dedupePrefix === 'album') {
            const aid = item.albumId > 0 ? String(item.albumId) : 'alb';
            const pid = item.photoId > 0 ? String(item.photoId) : 'dup';
            entryName = `${aid}_${pid}_${i}_${base}`;
          } else {
            const pid = item.photoId > 0 ? String(item.photoId) : 'dup';
            entryName = `${pid}_${i}_${base}`;
          }
          i += 1;
        }
        usedNames.add(entryName);

        const size = Number(item.size) || 0;
        totalSize += size;
        items.push({
          path: item.fullPath,
          rel: entryName,
          size,
        });
      }

      return ResponseUtil.success(
        req,
        res,
        {
          albumType,
          albumId,
          name,
          totalSize,
          count: items.length,
          items,
        },
        'common.SUCCESS',
        200
      );
    } catch (error) {
      Logger.error('getDownloadInfo error:', error);
      const statusCode = error.statusCode || 500;
      return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
    }
  }

  async downloadAlbumPhotos(req, res) {
    try {
      const query = req.query || {};
      const body = req.body || {};
      const raw = query.album_ids ?? query.albumIds ?? query.album_id ?? query.albumId ?? body.album_ids ?? body.albumIds ?? body.album_id ?? body.albumId;

      const validPathsRaw = await photoTimeLineService.getValidPaths(req.user);
      const validPathsForQuery = (validPathsRaw || []).map(p => (p ? String(p) : '')).filter(Boolean);
      if (validPathsForQuery.length === 0) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }
      const validPathsResolved = validPathsForQuery.map(p => path.resolve(String(p)));

      const rows = await photoAlbumService.listAlbumPhotoIndexRows(
        { knexPhoto: req.dbPhoto },
        {
          albumIds: raw,
          validPaths: validPathsForQuery,
        },
        req.user
      );

      const isUnder = (filePath, dirPath) => {
        const fileResolved = path.resolve(String(filePath || ''));
        const dirResolved = path.resolve(String(dirPath || ''));
        if (!fileResolved || !dirResolved) return false;
        if (fileResolved === dirResolved) return true;
        const prefix = dirResolved.endsWith(path.sep) ? dirResolved : dirResolved + path.sep;
        return fileResolved.startsWith(prefix);
      };

      const files = [];
      const seen = new Set();
      for (const r of rows) {
        const p = r && r.path ? String(r.path) : '';
        const filename = r && r.filename ? String(r.filename) : '';
        if (!p || !filename) continue;
        const fullPath = path.resolve(path.join(p, filename));
        if (seen.has(fullPath)) continue;
        if (validPathsResolved.length > 0 && !validPathsResolved.some(vp => isUnder(fullPath, vp))) continue;
        try {
          const st = await fs.promises.stat(fullPath);
          if (!st.isFile()) continue;
        } catch (_) {
          continue;
        }
        seen.add(fullPath);
        files.push({
          fullPath,
          filename,
          photoId: Number(r && r.photo_id ? r.photo_id : 0) || 0,
          albumId: Number(r && r.album_id ? r.album_id : 0) || 0,
        });
      }

      const albumIds = [];
      const rawIds = Array.isArray(raw) ? raw : raw === null || raw === undefined ? [] : [raw];
      for (const v of rawIds) {
        if (v === null || v === undefined || v === '') continue;
        if (typeof v === 'string' && v.includes(',')) {
          for (const part of v.split(',')) {
            const id = Number(part);
            if (Number.isFinite(id) && id > 0) albumIds.push(id);
          }
          continue;
        }
        const id = Number(v);
        if (Number.isFinite(id) && id > 0) albumIds.push(id);
      }
      const uniqueAlbumIds = [...new Set(albumIds)];

      const filenameFromParams = req.params && req.params.filename ? String(req.params.filename) : '';
      const zipName = filenameFromParams || (uniqueAlbumIds.length === 1 ? `album_${uniqueAlbumIds[0]}.zip` : `albums_${uniqueAlbumIds.length}.zip`);

      const archive = archiver('zip', { zlib: { level: 1 } });
      res.attachment(zipName);
      let stopped = false;
      const stop = err => {
        if (stopped) return;
        stopped = true;
        try {
          archive.abort();
        } catch (_) {}
        Logger.error('Archive error', err);
        if (!res.headersSent) {
          res.status(500).send({ error: err && err.message ? err.message : 'Archive error' });
          return;
        }
        res.destroy(err instanceof Error ? err : new Error('Archive error'));
      };
      archive.on('error', stop);
      res.on('error', stop);
      res.on('close', () => {
        if (stopped) return;
        stopped = true;
        try {
          archive.abort();
        } catch (_) {}
      });
      archive.pipe(res);

      const usedNames = new Set();
      for (const item of files) {
        const base = path.basename(item.filename || item.fullPath);
        let entryName = base || 'photo';
        if (usedNames.has(entryName)) {
          const aid = item.albumId > 0 ? String(item.albumId) : 'alb';
          const pid = item.photoId > 0 ? String(item.photoId) : 'dup';
          entryName = `${aid}_${pid}_${entryName}`;
        }
        let i = 1;
        while (usedNames.has(entryName)) {
          const aid = item.albumId > 0 ? String(item.albumId) : 'alb';
          const pid = item.photoId > 0 ? String(item.photoId) : 'dup';
          entryName = `${aid}_${pid}_${i}_${base}`;
          i += 1;
        }
        usedNames.add(entryName);
        archive.file(item.fullPath, { name: entryName });
      }

      await archive.finalize();
    } catch (error) {
      Logger.error('Album download error:', error);
      if (!res.headersSent) {
        const statusCode = error.statusCode || 400;
        return ResponseUtil.error(req, res, error.message || 'common.ERROR', statusCode);
      }
      res.destroy(error instanceof Error ? error : new Error('Album download error'));
    }
  }
}

module.exports = new PhotoAlbumController();
