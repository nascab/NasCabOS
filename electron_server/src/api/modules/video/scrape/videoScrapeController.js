const ResponseUtil = require('../../../apiUtils/responseUtil');
const ScrapeCleanupUtil = require('./scrapeCleanupUtil');
const path = require('path');
const { hasValidNfo } = require('../../../../workers/videoIndex/nfoParser');
const fileService = require('../../file/core/fileService');
const tableFileLog = require('../../../../db/table/tableFileLog');

class VideoScrapeController {
  async start(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const indexId = Number(body.index_id ?? body.indexId ?? 0) || 0;
      const tmdbIdRaw = String(body.tmdb_id ?? body.tmdbId ?? '').trim();
      const tmdbId = tmdbIdRaw ? Number(tmdbIdRaw || 0) || 0 : 0;
      const mode = String(body.mode ?? '').trim() || (tmdbId ? 'manual' : 'auto');

      if (!indexId) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      if (tmdbIdRaw && !tmdbId) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      if (mode !== 'manual' && mode !== 'auto') return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const resolvedIndexId = await ScrapeCleanupUtil.resolveTvIndexIdIfSeason(req.dbVideo, indexId);
      const targetIndexId = resolvedIndexId || indexId;

      if (mode === 'auto') {
        const row = await req
          .dbVideo('video_index')
          .where({ id: targetIndexId })
          .first('id', 'path', 'filename', 'media_type', 'is_file')
          .catch(() => null);
        if (row) {
          const mediaType = row.media_type ? String(row.media_type).trim() : '';
          const dirPath = row.path ? String(row.path).trim() : '';
          const filename = row.filename ? String(row.filename).trim() : '';
          let nfoPath = '';
          let expectedType = '';

          if ((mediaType === 'movie' || mediaType === 'episod' || mediaType === 'bdmv' || mediaType === 'video_ts') && dirPath && filename) {
            nfoPath = (mediaType === 'bdmv' || mediaType === 'video_ts')
              ? path.join(dirPath, filename, 'movie.nfo')
              : path.join(dirPath, `${path.parse(filename).name}.nfo`);
            expectedType = mediaType === 'episod' ? 'episodedetails' : 'movie';
          } else if (mediaType === 'tv' && dirPath && filename) {
            nfoPath = path.join(dirPath, filename, 'tvshow.nfo');
            expectedType = 'tvshow';
          } else if (mediaType === 'season' && dirPath && filename) {
            nfoPath = path.join(dirPath, filename, 'season.nfo');
            expectedType = 'season';
          }

          const hasNfo = nfoPath && expectedType ? await hasValidNfo(nfoPath, expectedType) : false;
          if (hasNfo) {
            if (mediaType === 'movie' || mediaType === 'episod' || mediaType === 'bdmv' || mediaType === 'video_ts') {
              return ResponseUtil.success(req, res, { requestId: '', started: false, skipped: true }, 'common.SUCCESS', 200);
            }

            if (mediaType === 'tv' && dirPath && filename) {
              const showFolder = path.join(dirPath, filename);
              const prefix = showFolder.endsWith(path.sep) ? showFolder : `${showFolder}${path.sep}`;

              const pendingSeason = await req
                .dbVideo('video_index')
                .where({ is_file: 0, media_type: 'season', nfo_get_state: 0, path: showFolder })
                .first('id')
                .catch(() => null);

              const pendingEpisode = await req
                .dbVideo('video_index')
                .where({ is_file: 1, media_type: 'episod', nfo_get_state: 0 })
                .andWhere(qb => {
                  qb.where('path', showFolder).orWhere('path', 'like', `${prefix}%`);
                })
                .first('id')
                .catch(() => null);

              if (!pendingSeason && !pendingEpisode) {
                return ResponseUtil.success(req, res, { requestId: '', started: false, skipped: true }, 'common.SUCCESS', 200);
              }
            }

            if (mediaType === 'season' && dirPath && filename) {
              const seasonFolder = path.join(dirPath, filename);
              const prefix = seasonFolder.endsWith(path.sep) ? seasonFolder : `${seasonFolder}${path.sep}`;

              const pendingEpisode = await req
                .dbVideo('video_index')
                .where({ is_file: 1, media_type: 'episod', nfo_get_state: 0 })
                .andWhere(qb => {
                  qb.where('path', seasonFolder).orWhere('path', 'like', `${prefix}%`);
                })
                .first('id')
                .catch(() => null);

              if (!pendingEpisode) {
                return ResponseUtil.success(req, res, { requestId: '', started: false, skipped: true }, 'common.SUCCESS', 200);
              }
            }
          }
        }
      }

      const requestId = `${Date.now()}_${Math.random().toString(16).slice(2)}`;
      try {
        if (typeof process.send === 'function') {
          process.send({
            type: 'startVideoScrape',
            data: {
              requestId,
              indexId: targetIndexId,
              tmdbId: tmdbId || undefined,
              mode,
            },
          });
        }
      } catch (_) {}

      return ResponseUtil.success(req, res, { requestId, started: true }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async cleanup(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const indexId = Number(body.index_id ?? body.indexId ?? 0) || 0;
      if (!indexId) return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);

      const result = await ScrapeCleanupUtil.cleanupByIndexId(req.dbVideo, indexId);
      const deletedPaths = result.deletedPaths || [];
      if (deletedPaths.length > 0) {
        await fileService.addFileLog(uid, tableFileLog.TYPE_DELETE, deletedPaths, null, tableFileLog.STATE_SUCCESS, 'SCRAPE_CLEANUP');
      }
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new VideoScrapeController();
