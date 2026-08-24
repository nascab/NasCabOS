const ResponseUtil = require('../../../apiUtils/responseUtil');
const FaceService = require('./faceService');
const archiver = require('archiver');
const path = require('path');
const fs = require('fs');
const Logger = require('../../../../utils/logger');
const photoTimeLineService = require('../timeline/photoTimeLineService');
const tableConfig = require('../../../../db/table/tableConfig');
const userUtil = require('../../../../utils/userUtil');

async function getEnableByKey(key) {
  try {
    const raw = await tableConfig.getConfigByKey(key);
    return raw === '1' ? 1 : 0;
  } catch (_) {
    return 0;
  }
}

class FaceController {
  async listFaces(req, res) {
    try {
      const faceEnable = await getEnableByKey('ai_face_enable');
      if (faceEnable !== 1) {
        const body = req.body || {};
        const page = Math.max(1, Number(body.page) || 1);
        const pageSize = Math.max(1, Math.min(200, Number(body.pageSize ?? body.page_size) || 60));
        return ResponseUtil.success(
          req,
          res,
          {
            faceEnable,
            items: [],
            pagination: {
              total: 0,
              page,
              pageSize,
            },
          },
          'common.SUCCESS',
          200
        );
      }
      let validPaths;
      if (req.user && !userUtil.isAdmin(req.user)) {
        const validPathsRaw = await photoTimeLineService.getValidPaths(req.user);
        validPaths = (validPathsRaw || []).map(p => (p ? String(p) : '')).filter(Boolean);
      }
      const service = new FaceService(req.dbPhoto);
      const result = await service.listFaces({ ...(req.body || {}), ...(validPaths !== undefined ? { validPaths } : {}) });
      return ResponseUtil.success(req, res, { faceEnable, ...result }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async setFaceCover(req, res) {
    try {
      const body = req.body || {};
      const service = new FaceService(req.dbPhoto);
      const result = await service.setFaceCover({
        faceId: body.face_id ?? body.faceId,
        fileHash: body.file_hash ?? body.fileHash,
      });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async updateFaceName(req, res) {
    try {
      const body = req.body || {};
      const service = new FaceService(req.dbPhoto);
      const result = await service.updateFaceName({
        faceId: body.face_id ?? body.faceId,
        name: body.name,
      });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async mergeFaces(req, res) {
    try {
      const body = req.body || {};
      const service = new FaceService(req.dbPhoto);
      const result = await service.mergeFaces({
        faceIds: body.face_ids ?? body.faceIds,
        fromFaceId: body.from_face_id ?? body.fromFaceId,
        toFaceId: body.to_face_id ?? body.toFaceId,
      });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async setFaceStatus(req, res) {
    try {
      const body = req.body || {};
      const service = new FaceService(req.dbPhoto);
      const result = await service.updateFaceStatus({
        faceId: body.face_id ?? body.faceId,
        status: body.status ?? body.state,
        is_hide: body.is_hide ?? body.isHide,
      });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async resetFaces(req, res) {
    try {
      const service = new FaceService(req.dbPhoto);
      const result = await service.resetFaceRecognition();
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async faceImage(req, res) {
    try {
      const body = req.body || {};
      const service = new FaceService(req.dbPhoto);
      const { buffer, mime } = await service.getFaceImageBuffer({
        faceId: body.face_id ?? body.faceId,
        fileHash: body.file_hash ?? body.fileHash,
        size: body.size,
        quality: body.quality,
      });
      res.set('Content-Type', mime || 'application/octet-stream');
      return res.send(buffer);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async faceImageGet(req, res) {
    try {
      const query = req.query || {};
      let validPaths;
      if (req.user && !userUtil.isAdmin(req.user)) {
        const validPathsRaw = await photoTimeLineService.getValidPaths(req.user);
        validPaths = (validPathsRaw || []).map(p => (p ? String(p) : '')).filter(Boolean);
      }
      const service = new FaceService(req.dbPhoto);
      const { buffer, mime } = await service.getFaceImageBuffer({
        faceId: query.face_id ?? query.faceId,
        fileHash: query.file_hash ?? query.fileHash,
        size: query.size,
        quality: query.quality,
        ...(validPaths !== undefined ? { validPaths } : {}),
      });
      res.set('Content-Type', mime || 'application/octet-stream');
      return res.send(buffer);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async listPhotoFaces(req, res) {
    try {
      const body = req.body || {};
      let validPaths;
      if (req.user && !userUtil.isAdmin(req.user)) {
        const validPathsRaw = await photoTimeLineService.getValidPaths(req.user);
        validPaths = (validPathsRaw || []).map(p => (p ? String(p) : '')).filter(Boolean);
      }
      const service = new FaceService(req.dbPhoto);
      const items = await service.listPhotoFaces({
        fileHash: body.file_hash ?? body.fileHash,
        ...(validPaths !== undefined ? { validPaths } : {}),
      });
      return ResponseUtil.success(req, res, { items }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async removePhotoFromFace(req, res) {
    try {
      const body = req.body || {};
      const service = new FaceService(req.dbPhoto);
      const result = await service.removePhotoFromFace({
        faceId: body.face_id ?? body.faceId,
        fileHash: body.file_hash ?? body.fileHash,
      });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async movePhotoToFace(req, res) {
    try {
      const body = req.body || {};
      const service = new FaceService(req.dbPhoto);
      const result = await service.movePhotoToFace({
        fromFaceId: body.from_face_id ?? body.fromFaceId,
        toFaceId: body.to_face_id ?? body.toFaceId,
        fileHashes: body.file_hashes ?? body.fileHashes,
      });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : msgKey === 'common.NOT_FOUND' ? 404 : msgKey === 'common.PARAM_ERROR' ? 400 : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async downloadFacePhotos(req, res) {
    try {
      const query = req.query || {};
      const body = req.body || {};

      const raw = query.face_ids ?? query.faceIds ?? query.face_id ?? query.faceId ?? body.face_ids ?? body.faceIds ?? body.face_id ?? body.faceId;

      const validPathsRaw = await photoTimeLineService.getValidPaths(req.user);
      const validPathsForQuery = (validPathsRaw || []).map(p => (p ? String(p) : '')).filter(Boolean);
      const validPaths = validPathsForQuery.map(p => path.resolve(String(p)));

      const service = new FaceService(req.dbPhoto);
      const rows = await service.listFacePhotoIndexRows({ faceIds: raw, validPaths: validPathsForQuery });

      const isUnder = (filePath, dirPath) => {
        const fileResolved = path.resolve(String(filePath || ''));
        const dirResolved = path.resolve(String(dirPath || ''));
        if (!fileResolved || !dirResolved) return false;
        if (fileResolved === dirResolved) return true;
        const prefix = dirResolved.endsWith(path.sep) ? dirResolved : dirResolved + path.sep;
        return fileResolved.startsWith(prefix);
      };

      const filtered = [];
      const seen = new Set();

      for (const r of rows) {
        const p = r && r.path ? String(r.path) : '';
        const filename = r && r.filename ? String(r.filename) : '';
        if (!p || !filename) continue;
        const fullPath = path.join(p, filename);
        const normalizedFullPath = path.resolve(fullPath);
        if (seen.has(normalizedFullPath)) continue;
        if (validPaths.length > 0 && !validPaths.some(vp => isUnder(normalizedFullPath, vp))) {
          continue;
        }
        try {
          const st = await fs.promises.stat(normalizedFullPath);
          if (!st.isFile()) continue;
        } catch (_) {
          continue;
        }
        seen.add(normalizedFullPath);
        filtered.push({
          fullPath: normalizedFullPath,
          filename,
          photoId: Number(r && r.photo_id ? r.photo_id : 0) || 0,
        });
      }

      if (filtered.length === 0) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }

      const faceIds = [];
      const rawFaceIds = Array.isArray(raw) ? raw : raw === null || raw === undefined ? [] : [raw];
      for (const v of rawFaceIds) {
        if (v === null || v === undefined || v === '') continue;
        if (typeof v === 'string' && v.includes(',')) {
          for (const part of v.split(',')) {
            const id = Number(part);
            if (Number.isFinite(id) && id > 0) faceIds.push(id);
          }
          continue;
        }
        const id = Number(v);
        if (Number.isFinite(id) && id > 0) faceIds.push(id);
      }
      const uniqueFaceIds = [...new Set(faceIds)];

      const filenameFromParams = req.params && req.params.filename ? String(req.params.filename) : '';
      const zipName = filenameFromParams || (uniqueFaceIds.length === 1 ? `face_${uniqueFaceIds[0]}.zip` : `faces_${uniqueFaceIds.length}.zip`);

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

      for (const item of filtered) {
        const base = path.basename(item.filename || item.fullPath);
        let entryName = base || 'photo';
        if (usedNames.has(entryName)) {
          const pid = item.photoId > 0 ? String(item.photoId) : 'dup';
          entryName = `${pid}_${entryName}`;
        }
        let i = 1;
        while (usedNames.has(entryName)) {
          const pid = item.photoId > 0 ? String(item.photoId) : 'dup';
          entryName = `${pid}_${i}_${base}`;
          i += 1;
        }
        usedNames.add(entryName);
        archive.file(item.fullPath, { name: entryName });
      }

      await archive.finalize();
    } catch (err) {
      Logger.error('Face download error', err);
      if (!res.headersSent) {
        return ResponseUtil.error(req, res, 'common.ERROR', 500);
      }
      res.destroy(err instanceof Error ? err : new Error('Face download error'));
    }
  }
}

module.exports = new FaceController();
