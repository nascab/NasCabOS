const ResponseUtil = require('../../../apiUtils/responseUtil');
const VideoSourceService = require('./videoSourceService');
const FileUtil = require('../../../../utils/fileUtil');
const fs = require('fs');
const path = require('path');
async function stopVideoIndexWorkerBeforeDelete(timeoutMs = 8000) {
  const waitStopped = new Promise(resolve => {
    if (typeof process.send !== 'function') return resolve(false);

    const requestId = `${Date.now()}_${Math.random().toString(16).slice(2)}`;
    let done = false;
    const timer = setTimeout(
      () => {
        if (done) return;
        done = true;
        process.removeListener('message', onMessage);
        resolve(false);
      },
      Math.max(1000, Number(timeoutMs || 0) || 0)
    );

    const onMessage = message => {
      if (!message || message.type !== 'stopVideoIndexWorkerResponse') return;
      if (!message.data || message.data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      process.removeListener('message', onMessage);
      resolve(!!message.data.stopped);
    };
    process.on('message', onMessage);

    try {
      process.send({ type: 'stopVideoIndexWorker', data: { requestId } });
    } catch (_) {
      clearTimeout(timer);
      process.removeListener('message', onMessage);
      resolve(false);
    }
  });

  return await waitStopped;
}

async function enqueueScanTaskAndStartWorker(req, scanPath, remark) {
  const p = scanPath === undefined || scanPath === null ? '' : String(scanPath).trim();
  if (!p) return false;

  await req.dbVideo.transaction(async trx => {
    const existingRows = await trx('video_scan_task')
      .select('scan_path')
      .whereIn('scan_path', [p])
      .catch(() => []);
    const existing = new Set((existingRows || []).map(r => (r && r.scan_path ? String(r.scan_path) : '')).filter(Boolean));
    if (!existing.has(p)) {
      await trx('video_scan_task').insert({
        scan_path: p,
        remark: String(remark || ''),
        create_time: new Date(),
      });
    }
  });

  if (process.send) {
    try {
      process.send({ type: 'startVideoIndexWorker', data: { scanPath: p } });
    } catch (_) {}
  }
  return true;
}

class VideoSourceController {
  async listSources(req, res) {
    try {
      const service = new VideoSourceService(req.dbVideo);
      const list = await service.listSources();
      const enriched = await Promise.all(
        (list || []).map(async row => {
          const p = row && row.path ? String(row.path) : '';
          let exists = false;
          if (p) {
            try {
              const stat = await fs.promises.stat(p);
              exists = !!(stat && stat.isDirectory());
            } catch (_) {}
          }
          return { ...row, exists };
        })
      );
      return ResponseUtil.success(req, res, enriched, 'video.VIDEO_SOURCE_LIST_SUCCESS', 200);
    } catch (err) {
      return ResponseUtil.error(req, res, 'video.VIDEO_SOURCE_LIST_FAILED', 500);
    }
  }

  /**
   * 新增影音来源
   * body:
   * - path: string
   * - media_type: "movie" | "tv"
   * - match_nfo?: 0 | 1
   */
  async addSource(req, res) {
    try {
      const service = new VideoSourceService(req.dbVideo);
      const body = req.body || {};
      const inputPath = body.path;
      const mediaType = body.media_type ?? body.mediaType;
      const matchNfo = body.match_nfo ?? body.matchNfo ?? 0;
      const p = inputPath === undefined || inputPath === null ? '' : String(inputPath).trim();
      if (!p) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }
      if (FileUtil.isProtectedPath(p)) {
        return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
      }
      let stat;
      try {
        stat = await fs.promises.stat(p);
      } catch (_) {
        stat = null;
      }
      if (!stat || !stat.isDirectory()) {
        return ResponseUtil.error(req, res, 'file.FOLDER_NOT_EXIST');
      }

      const mt = String(mediaType || '')
        .trim()
        .toLowerCase();
      if (mt !== 'movie' && mt !== 'tv') {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }
      const mn = matchNfo === true ? 1 : matchNfo === false ? 0 : Number(matchNfo);
      if (!(mn === 0 || mn === 1)) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }

      const result = await service.addSource({ path: p, media_type: mt, match_nfo: mn });
      const statusCode = result.action === 'insert' ? 201 : 200;
      const messageKey = result.action === 'insert' ? 'video.VIDEO_SOURCE_ADD_SUCCESS' : 'video.VIDEO_SOURCE_UPDATE_SUCCESS';

      await enqueueScanTaskAndStartWorker(req, result?.row?.path, result.action === 'insert' ? 'add_source' : 'update_source');
      if (process.send) {
        try {
          process.send({ type: 'resetVideoWatchWorker' });
        } catch (_) {}
      }

      return ResponseUtil.success(req, res, result.row, messageKey, statusCode);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      const statusCode = msgKey === 'video.VIDEO_SOURCE_EXISTS' || msgKey === 'video.VIDEO_SOURCE_PARENT_EXISTS' ? 409 : 400;
      if (err && err.args) {
        return ResponseUtil.errorWithArgs(req, res, msgKey, err.args, statusCode);
      }
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  /**
   * 修改来源 media_type（管理员）
   * params: id
   * body: { media_type: "movie" | "tv" }
   */
  async updateMediaType(req, res) {
    try {
      await stopVideoIndexWorkerBeforeDelete();
      const service = new VideoSourceService(req.dbVideo);
      const id = req.params && req.params.id;
      const body = req.body || {};
      const mt = String(body.media_type ?? body.mediaType ?? '')
        .trim()
        .toLowerCase();
      if (mt !== 'movie' && mt !== 'tv') {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }
      const row = await service.updateMediaType(id, mt);
      await enqueueScanTaskAndStartWorker(req, row?.path, 'update_media_type');
      if (process.send) {
        try {
          process.send({ type: 'resetVideoWatchWorker' });
        } catch (_) {}
      }
      return ResponseUtil.success(req, res, row, 'video.VIDEO_SOURCE_UPDATE_SUCCESS', 200);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      const statusCode = msgKey === 'common.NOT_FOUND' ? 404 : 400;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  /**
   * 更新来源 match_nfo（管理员）
   * params: id
   * body: { match_nfo: 0 | 1 }
   */
  async updateMatchNfo(req, res) {
    try {
      const service = new VideoSourceService(req.dbVideo);
      const id = req.params && req.params.id;
      const body = req.body || {};
      const input = body.match_nfo ?? body.matchNfo;
      const v = input === true ? 1 : input === false ? 0 : Number(input);
      if (!(v === 0 || v === 1)) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }
      const row = await service.updateMatchNfo(id, v);
      if (process.send) {
        try {
          process.send({ type: 'resetVideoWatchWorker' });
        } catch (_) {}
      }
      return ResponseUtil.success(req, res, row, 'video.VIDEO_SOURCE_UPDATE_SUCCESS', 200);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      const statusCode = msgKey === 'common.NOT_FOUND' ? 404 : 400;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async deleteSource(req, res) {
    try {
      await stopVideoIndexWorkerBeforeDelete();
      const service = new VideoSourceService(req.dbVideo);
      const { id, path } = req.body || {};
      const affected = await service.deleteSource({ id, path });
      if (process.send) {
        try {
          process.send({ type: 'resetVideoWatchWorker' });
        } catch (_) {}
      }
      if (process.send) {
        try {
          process.send({ type: 'startVideoIndexWorker', data: {} });
        } catch (_) {}
      }
      return ResponseUtil.success(req, res, { affected }, 'video.VIDEO_SOURCE_DELETE_SUCCESS', 200);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      return ResponseUtil.error(req, res, msgKey, 400);
    }
  }

  async updateSource(req, res) {
    try {
      const service = new VideoSourceService(req.dbVideo);
      const id = req.params && req.params.id;
      const row = await service.updateSource(id, req.body || {});
      if (process.send) {
        try {
          process.send({ type: 'resetVideoWatchWorker' });
        } catch (_) {}
      }
      return ResponseUtil.success(req, res, row, 'video.VIDEO_SOURCE_UPDATE_SUCCESS', 200);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      const statusCode = msgKey === 'common.NOT_FOUND' ? 404 : 400;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async relocateSource(req, res) {
    try {
      const service = new VideoSourceService(req.dbVideo);
      const id = req.params && req.params.id;
      const { new_path: newPath } = req.body || {};
      if (FileUtil.isProtectedPath(newPath)) {
        return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
      }
      if (!newPath) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }

      let stat;
      try {
        stat = await fs.promises.stat(String(newPath));
      } catch (_) {
        stat = null;
      }
      if (!stat || !stat.isDirectory()) {
        return ResponseUtil.error(req, res, 'file.FOLDER_NOT_EXIST', 400);
      }

      const result = await service.relocateSource(id, newPath);

      if (process.send) {
        try {
          process.send({ type: 'resetVideoWatchWorker' });
        } catch (_) {}
      }

      return ResponseUtil.success(req, res, result, 'video.VIDEO_SOURCE_RELOCATE_SUCCESS', 200);
    } catch (err) {
      const msgKey = err && err.message ? err.message : 'common.ERROR';
      const statusCode = msgKey === 'common.NOT_FOUND' ? 404 : 400;
      if (err && err.args) {
        return ResponseUtil.errorWithArgs(req, res, msgKey, err.args, statusCode);
      }
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async scanSource(req, res) {
    try {
      const rawPath = req.body && req.body.path !== undefined ? req.body.path : req.body && req.body.scan_path !== undefined ? req.body.scan_path : '';
      const input = rawPath === undefined || rawPath === null ? '' : String(rawPath).trim();
      if (!input) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }

      let scanPaths = [];
      if (input === 'all') {
        const rows = await req
          .dbVideo('video_source')
          .select('path')
          .catch(() => []);
        scanPaths = (rows || []).map(r => (r && r.path ? String(r.path) : '')).filter(Boolean);
      } else {
        const scanPath = path.resolve(String(input));
        const sources = await req
          .dbVideo('video_source')
          .select('id', 'path')
          .catch(() => []);

        const matched = (sources || []).some(r => {
          const root = r && r.path ? path.resolve(String(r.path)) : '';
          if (!root) return false;
          const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
          return scanPath === root || scanPath.startsWith(prefix);
        });
        if (!matched) {
          return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
        }
        scanPaths = [scanPath];
      }

      const unique = Array.from(new Set((scanPaths || []).map(p => (p ? String(p) : '')).filter(Boolean)));
      if (unique.length === 0) {
        return ResponseUtil.success(req, res, { inserted: 0 }, 'common.SUCCESS', 200);
      }

      const inserted = await req.dbVideo.transaction(async trx => {
        const existingRows = await trx('video_scan_task')
          .select('scan_path')
          .whereIn('scan_path', unique)
          .catch(() => []);
        const existing = new Set((existingRows || []).map(r => (r && r.scan_path ? String(r.scan_path) : '')).filter(Boolean));

        const toInsert = [];
        for (const p of unique) {
          if (!existing.has(p)) {
            toInsert.push({
              scan_path: p,
              remark: input === 'all' ? 'manual_all' : 'manual',
              create_time: new Date(),
            });
          }
        }
        if (toInsert.length === 0) return 0;
        await trx('video_scan_task').insert(toInsert);
        return toInsert.length;
      });

      if (process.send) {
        try {
          process.send({ type: 'startVideoIndexWorker', data: { scanPaths: unique, scanPath: input === 'all' ? undefined : unique[0] } });
        } catch (_) {}
      }

      return ResponseUtil.success(req, res, { inserted }, 'common.SUCCESS', 200);
    } catch (err) {
      console.log(err);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async scanIndex(req, res) {
    try {
      const rawId = req.body && req.body.index_id !== undefined ? req.body.index_id : req.body && req.body.indexId !== undefined ? req.body.indexId : 0;
      const indexId = Number(rawId || 0) || 0;
      if (!indexId) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }

      const row = await req
        .dbVideo('video_index')
        .where({ id: indexId })
        .first('id', 'path', 'filename', 'is_file')
        .catch(() => null);
      if (!row) {
        return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      }

      const dirPath = row.path ? path.resolve(String(row.path)) : '';
      const filename = row.filename ? String(row.filename) : '';
      const isFile = Number(row.is_file || 0) === 1;

      const scanPath = isFile ? dirPath : dirPath && filename ? path.join(dirPath, filename) : '';
      if (!scanPath) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }

      let stat;
      try {
        stat = await fs.promises.stat(scanPath);
      } catch (_) {
        stat = null;
      }
      if (!stat || !stat.isDirectory()) {
        return ResponseUtil.error(req, res, 'file.FOLDER_NOT_EXIST', 400);
      }

      const sources = await req
        .dbVideo('video_source')
        .select('id', 'path')
        .catch(() => []);

      const matched = (sources || []).some(r => {
        const root = r && r.path ? path.resolve(String(r.path)) : '';
        if (!root) return false;
        const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
        return scanPath === root || scanPath.startsWith(prefix);
      });
      if (!matched) {
        return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      }

      const ok = await enqueueScanTaskAndStartWorker(req, scanPath, 'manual_index');
      return ResponseUtil.success(req, res, { queued: ok ? 1 : 0 }, 'common.SUCCESS', 200);
    } catch (err) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }
}

module.exports = new VideoSourceController();
