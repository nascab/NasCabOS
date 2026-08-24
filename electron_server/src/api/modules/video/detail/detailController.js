const ResponseUtil = require('../../../apiUtils/responseUtil');
const VideoDetailService = require('./detailService');
const fs = require('fs');
const path = require('path');

class VideoDetailController {
  async getDetail(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;
      const service = new VideoDetailService(req.dbVideo);
      const data = await service.getDetail({ uid, indexId });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getEpisodes(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;
      const page = Number(q.page ?? 1) || 1;
      const pageSize = Number(q.page_size ?? q.pageSize ?? 50) || 50;
      const sortOrder = String(q.sort_order ?? q.sortOrder ?? 'asc');

      const service = new VideoDetailService(req.dbVideo);
      const data = await service.getEpisodesPaged({
        indexId,
        page,
        pageSize,
        sortOrder,
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getTvPlayInfo(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;

      const service = new VideoDetailService(req.dbVideo);
      const data = await service.getTvPlayInfo({ uid, indexId });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getDiscContents(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;

      const service = new VideoDetailService(req.dbVideo);
      const data = await service.getDiscContents({ indexId });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getDiscContentThumb(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return res.status(401).end();

      const q = req.query || {};
      const indexId = Number(q.index_id ?? q.indexId ?? 0) || 0;
      const internalPath = String(q.internal_path ?? q.internalPath ?? '').trim();
      const size = Math.max(1, Number(q.size ?? 320) || 320);

      const service = new VideoDetailService(req.dbVideo);
      const tinyPath = await service.getDiscContentThumbPath({
        indexId,
        internalPath,
        size,
      });
      if (!tinyPath) return res.status(404).end();

      res.set('Content-Type', 'image/webp');
      return res.sendFile(tinyPath);
    } catch (_) {
      return res.status(404).end();
    }
  }

  async setOpenSkip(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const indexId = Number(body.index_id ?? body.indexId ?? 0) || 0;
      const openSkipStartSec = body.open_skip_start_sec ?? body.openSkipStartSec ?? 0;
      const openSkipEndSec = body.open_skip_end_sec ?? body.openSkipEndSec ?? 0;

      const service = new VideoDetailService(req.dbVideo);
      const data = await service.setOpenSkip({
        indexId,
        openSkipStartSec,
        openSkipEndSec,
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getPersonImage(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return res.status(401).end();

      const q = req.query || {};
      const tmdbId = String(q.tmdb_id ?? q.tmdbId ?? '').trim();
      if (!tmdbId) return res.status(400).end();

      const size = 500;
      const thumb = String(q.thumb ?? '').trim();

      const service = new VideoDetailService(req.dbVideo);
      const info = await service.getPersonJpegCacheInfo({
        tmdbId,
        size,
        thumbUrl: thumb,
      });
      if (!info || !info.filePath) return res.status(404).end();

      const filePath = String(info.filePath || '').trim();
      const url = String(info.url || '').trim();
      if (!filePath) return res.status(404).end();

      if (info.exists) {
        res.set('Content-Type', 'image/jpeg');
        return res.sendFile(filePath);
      }

      if (!url) return res.status(404).end();
      try {
        if (typeof process.send === 'function') {
          process.send({ type: 'downloadUrlToFile', data: { url, targetPath: filePath, timeoutMs: 30000, allowProxy: true } });
        }
      } catch (_) {}

      res.set('Content-Type', 'image/jpeg');
      const deadlineAt = Date.now() + 15000;
      while (Date.now() < deadlineAt) {
        if (req.aborted) return;
        try {
          const st = await fs.promises.stat(filePath);
          if (st && st.isFile() && Number(st.size || 0) > 0) {
            return res.sendFile(filePath);
          }
        } catch (_) {}
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      return res.status(404).end();
    } catch (_) {
      return res.status(404).end();
    }
  }

  async getPosterImage(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return res.status(401).end();

      const q = req.query || {};
      const tmdbId = String(q.tmdb_id ?? q.tmdbId ?? '').trim();
      const mediaType = String(q.media_type ?? q.mediaType ?? '')
        .trim()
        .toLowerCase();
      if (!tmdbId) return res.status(400).end();
      if (mediaType !== 'movie' && mediaType !== 'tv') return res.status(400).end();

      const size = Math.max(1, Number(q.size ?? 342) || 342);
      const thumb = String(q.thumb ?? '').trim();

      const service = new VideoDetailService(req.dbVideo);
      const info = await service.getPosterJpegCacheInfo({
        tmdbId,
        mediaType,
        size,
        thumbUrl: thumb,
      });
      if (!info || !info.filePath) return res.status(404).end();

      const filePath = String(info.filePath || '').trim();
      const url = String(info.url || '').trim();
      if (!filePath) return res.status(404).end();

      if (info.exists) {
        res.set('Content-Type', 'image/jpeg');
        return res.sendFile(filePath);
      }

      if (!url) return res.status(404).end();
      try {
        await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
      } catch (_) {}

      try {
        if (typeof process.send === 'function') {
          process.send({ type: 'downloadUrlToFile', data: { url, targetPath: filePath, timeoutMs: 30000, allowProxy: true } });
        }
      } catch (_) {}

      res.set('Content-Type', 'image/jpeg');
      const deadlineAt = Date.now() + 15000;
      while (Date.now() < deadlineAt) {
        if (req.aborted) return;
        try {
          const st = await fs.promises.stat(filePath);
          if (st && st.isFile() && Number(st.size || 0) > 0) {
            return res.sendFile(filePath);
          }
        } catch (_) {}
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
      return res.status(404).end();
    } catch (_) {
      return res.status(404).end();
    }
  }
}

module.exports = new VideoDetailController();
