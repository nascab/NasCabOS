const fs = require('fs');
const path = require('path');
const multer = require('multer');
const ResponseUtil = require('../../apiUtils/responseUtil');
const config = require('../../../config/config');
const { TransmissionService } = require('./transmissionService');
const { TransmissionRpcClient } = require('./transmissionRpcClient');
const { ensureString, filterSessionSetArguments, ensureTrackersResolved, loadConfig, getDefaultTrackersForDaemon } = require('../../../workers/transmission/transmissionConfig');
const { resolveTrackerInput, getTrackerFetchTimeoutMs } = require('../../../workers/transmission/transmissionTrackerResolver');
const { enrichTorrentForClient, rememberTorrentDownloadDirsFromList, persistAddedTorrentPath } = require('./transmissionTorrentUtil');
const { setTorrentDownloadDir, removeTorrentDownloadDir, rememberDownloadDir } = require('../../../workers/transmission/transmissionTorrentPathStore');

function pickStatsBytes(obj) {
  if (!obj || typeof obj !== 'object') return { downloaded: undefined, uploaded: undefined };
  return {
    downloaded: obj.downloadedBytes ?? obj.downloaded_bytes,
    uploaded: obj.uploadedBytes ?? obj.uploaded_bytes,
  };
}

function normalizeSessionStats(raw) {
  if (!raw || typeof raw !== 'object') return {};
  const stats = { ...raw };
  const cumulative =
    stats['cumulative-stats'] || stats.cumulativeStats || stats.cumulative_stats || {};
  const current = stats['current-stats'] || stats.currentStats || stats.current_stats || {};
  const cum = pickStatsBytes(cumulative);
  const cur = pickStatsBytes(current);
  if (stats.downloadedBytes === undefined && cum.downloaded !== undefined) {
    stats.downloadedBytes = cum.downloaded;
  }
  if (stats.uploadedBytes === undefined && cum.uploaded !== undefined) {
    stats.uploadedBytes = cum.uploaded;
  }
  if (cum.downloaded !== undefined) stats.cumulativeDownloadedBytes = cum.downloaded;
  if (cum.uploaded !== undefined) stats.cumulativeUploadedBytes = cum.uploaded;
  if (cur.downloaded !== undefined) stats.currentDownloadedBytes = cur.downloaded;
  if (cur.uploaded !== undefined) stats.currentUploadedBytes = cur.uploaded;
  return stats;
}

function waitForIpcResponse({ requestId, responseType, timeoutMs }) {
  return new Promise((resolve, reject) => {
    if (typeof process.send !== 'function') {
      const err = new Error('common.ERROR');
      err.statusCode = 500;
      reject(err);
      return;
    }

    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      process.removeListener('message', onMessage);
      const err = new Error('common.ERROR');
      err.statusCode = 504;
      reject(err);
    }, Math.max(500, Number(timeoutMs || 0) || 0));

    const onMessage = message => {
      if (!message || message.type !== responseType) return;
      if (!message.data || message.data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      process.removeListener('message', onMessage);
      resolve(message.data || {});
    };

    process.on('message', onMessage);
  });
}

function buildHttpError(msgKey, statusCode) {
  const err = new Error(String(msgKey || 'common.ERROR'));
  err.statusCode = Number(statusCode || 500) || 500;
  return err;
}

class TransmissionController {
  constructor() {
    this.service = new TransmissionService();
    this.rpc = new TransmissionRpcClient();
  }

  async _startByIpc({ restart }) {
    const requestId = `startTransmission_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType: 'startTransmissionResponse', timeoutMs: 25000 });
    process.send({
      type: 'startTransmission',
      data: { requestId, restart: !!restart },
      timestamp: Date.now(),
    });
    const data = await wait;
    if (!data.started) {
      throw buildHttpError(data.error || 'transmission.START_FAILED', 500);
    }
    return data;
  }

  async _stopByIpc() {
    const requestId = `stopTransmission_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType: 'stopTransmissionResponse', timeoutMs: 15000 });
    process.send({
      type: 'stopTransmission',
      data: { requestId },
      timestamp: Date.now(),
    });
    const data = await wait;
    if (!data.stopped) {
      throw buildHttpError(data.error || 'transmission.STOP_FAILED', 500);
    }
    return data;
  }

  async _getStatusByIpc() {
    const requestId = `getTransmissionStatus_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType: 'getTransmissionStatusResponse', timeoutMs: 10000 });
    process.send({
      type: 'getTransmissionStatus',
      data: { requestId },
      timestamp: Date.now(),
    });
    return wait;
  }

  async getStatus(req, res) {
    try {
      const data = await this._getStatusByIpc();
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async start(req, res) {
    try {
      const data = await this._startByIpc({ restart: false });
      return ResponseUtil.success(req, res, data, 'transmission.STARTED', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async stop(req, res) {
    try {
      const data = await this._stopByIpc();
      return ResponseUtil.success(req, res, data, 'transmission.STOPPED', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async restart(req, res) {
    try {
      const data = await this._startByIpc({ restart: true });
      return ResponseUtil.success(req, res, data, 'transmission.RESTARTED', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async getConfig(req, res) {
    try {
      const data = await this.service.getConfig();
      const status = await this._getStatusByIpc().catch(() => null);
      return ResponseUtil.success(req, res, { ...data, running: !!(status && status.running) }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async saveConfig(req, res) {
    try {
      const body = req.body || {};
      const data = await this.service.saveConfig(body);
      await this.service.applyRuntimeSettings(this.rpc, body).catch(() => {});
      const needsRestart = !!(body.rpc_port || body.peer_port);
      return ResponseUtil.success(req, res, { ...data, needs_restart: needsRestart }, 'transmission.CONFIG_SAVED', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500, e.msgArgs);
    }
  }

  async setPorts(req, res) {
    try {
      const { rpc_port } = req.body || {};
      const data = await this.service.setRpcPort(rpc_port);
      return ResponseUtil.success(req, res, { ...data, needs_restart: true }, 'transmission.CONFIG_SAVED', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.msgKey || e.message || 'common.ERROR', e.statusCode || 500, e.msgArgs);
    }
  }

  async getSession(req, res) {
    try {
      await this.service.assertDaemonRunning();
      const session = await this.rpc.call('session-get');
      const rawStats = await this.rpc.call('session-stats').catch(() => ({}));
      const stats = normalizeSessionStats(rawStats);
      return ResponseUtil.success(req, res, { session, stats }, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async setSession(req, res) {
    try {
      await this.service.assertDaemonRunning();
      const raw = (req.body && req.body.arguments) || req.body || {};
      const args = filterSessionSetArguments(raw);
      if (!Object.keys(args).length) {
        return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      }
      const result = await this.rpc.call('session-set', args);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async listTorrents(req, res) {
    try {
      await this.service.assertDaemonRunning();
      const query = req.method === 'GET' ? req.query || {} : req.body || {};
      let ids = query.ids;
      if (typeof ids === 'string' && ids.trim()) {
        try {
          ids = JSON.parse(ids);
        } catch (_) {
          ids = ids.split(',').map(v => Number(v)).filter(v => Number.isFinite(v));
        }
      }
      let fields = query.fields;
      if (typeof fields === 'string' && fields.trim()) {
        try {
          fields = JSON.parse(fields);
        } catch (_) {
          fields = fields.split(',').map(v => v.trim()).filter(Boolean);
        }
      }
      const args = {};
      if (ids !== undefined) args.ids = ids;
      if (fields !== undefined) args.fields = fields;
      if (query.format) args.format = query.format;
      const result = await this.rpc.call('torrent-get', args);
      if (Array.isArray(result.torrents)) {
        await rememberTorrentDownloadDirsFromList(result.torrents).catch(() => {});
        result.torrents = result.torrents.map(enrichTorrentForClient);
      }
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async addTorrent(req, res) {
    try {
      await this.service.assertDaemonRunning();
      const cfg = await ensureTrackersResolved(await loadConfig());
      await this.rpc
        .call('session-set', { 'default-trackers': getDefaultTrackersForDaemon(cfg) })
        .catch(() => {});
      const body = req.body || {};
      const args = { ...(body.arguments || {}) };
      if (body.url) args.filename = String(body.url);
      if (body.metainfo) args.metainfo = String(body.metainfo);
      const localTorrentPath = ensureString(body.filename).trim();
      if (localTorrentPath) {
        const ext = path.extname(localTorrentPath).toLowerCase();
        if (ext !== '.torrent') {
          return ResponseUtil.error(req, res, 'transmission.TORRENT_FILE_REQUIRED', 400);
        }
        try {
          await fs.promises.access(localTorrentPath, fs.constants.R_OK);
        } catch (_) {
          return ResponseUtil.error(req, res, 'file.FILE_NOT_FOUND', 404);
        }
        args.filename = localTorrentPath;
      }
      const downloadDir = ensureString(body.download_dir).trim();
      if (!downloadDir) {
        return ResponseUtil.error(req, res, 'transmission.DOWNLOAD_DIR_REQUIRED', 400);
      }
      args['download-dir'] = downloadDir;
      if (body.paused !== undefined) args.paused = !!body.paused;
      const trackers = body.trackers
        ? await resolveTrackerInput(body.trackers, getTrackerFetchTimeoutMs(cfg))
        : [];
      if (trackers.length) args.trackerAdd = trackers;
      const result = await this.rpc.call('torrent-add', args);
      await persistAddedTorrentPath(result, downloadDir).catch(() => {});
      return ResponseUtil.success(req, res, result, 'transmission.TORRENT_ADDED', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  uploadTorrentMiddleware(req, res, next) {
    const tempDir = path.join(config.getCachePath(), 'transmission_upload');
    fs.mkdirSync(tempDir, { recursive: true });
    const uploader = multer({
      storage: multer.diskStorage({
        destination: (_req, _file, cb) => cb(null, tempDir),
        filename: (_req, file, cb) => {
          const base = path.basename(file.originalname || 'upload.torrent');
          cb(null, `${Date.now()}_${base}`);
        },
      }),
      limits: { fileSize: 20 * 1024 * 1024 },
      fileFilter: (_req, file, cb) => {
        const ext = path.extname(file.originalname || '').toLowerCase();
        if (ext !== '.torrent') {
          cb(new Error('transmission.TORRENT_FILE_REQUIRED'));
          return;
        }
        cb(null, true);
      },
    }).single('file');
    uploader(req, res, err => {
      if (err) {
        const msgKey =
          err.message === 'transmission.TORRENT_FILE_REQUIRED'
            ? 'transmission.TORRENT_FILE_REQUIRED'
            : 'common.ERROR';
        return ResponseUtil.error(req, res, msgKey, 400);
      }
      next();
    });
  }

  async uploadTorrent(req, res) {
    let tempPath = '';
    try {
      await this.service.assertDaemonRunning();
      const cfg = await ensureTrackersResolved(await loadConfig());
      await this.rpc
        .call('session-set', { 'default-trackers': getDefaultTrackersForDaemon(cfg) })
        .catch(() => {});
      if (!req.file || !req.file.path) {
        return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      }
      tempPath = req.file.path;
      const metainfo = await this.service.readTorrentFileBase64(tempPath);
      const body = req.body || {};
      const args = { metainfo };
      const downloadDir = ensureString(body.download_dir).trim();
      if (!downloadDir) {
        return ResponseUtil.error(req, res, 'transmission.DOWNLOAD_DIR_REQUIRED', 400);
      }
      args['download-dir'] = downloadDir;
      if (body.paused !== undefined) args.paused = body.paused === '1' || body.paused === 'true' || body.paused === true;
      const trackers = body.trackers
        ? await resolveTrackerInput(body.trackers, getTrackerFetchTimeoutMs(cfg))
        : [];
      if (trackers.length) args.trackerAdd = trackers;
      const result = await this.rpc.call('torrent-add', args);
      await persistAddedTorrentPath(result, downloadDir).catch(() => {});
      return ResponseUtil.success(req, res, result, 'transmission.TORRENT_ADDED', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    } finally {
      if (tempPath) {
        fs.promises.unlink(tempPath).catch(() => {});
      }
    }
  }

  async torrentAction(method, req, res) {
    try {
      await this.service.assertDaemonRunning();
      const body = req.body || {};
      const args = body.arguments || {};
      if (body.ids !== undefined) args.ids = body.ids;
      if (body.deleteLocalData !== undefined) args['delete-local-data'] = !!body.deleteLocalData;
      const result = await this.rpc.call(method, args);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  startTorrents = (req, res) => this.torrentAction('torrent-start', req, res);
  stopTorrents = (req, res) => this.torrentAction('torrent-stop', req, res);
  async removeTorrents(req, res) {
    try {
      await this.service.assertDaemonRunning();
      const body = req.body || {};
      let ids = body.ids;
      if (ids === undefined || ids === null) {
        return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      }
      if (!Array.isArray(ids)) ids = [ids];
      const lookup = await this.rpc.call('torrent-get', {
        ids,
        fields: ['hashString'],
      });
      const args = { ...(body.arguments || {}), ids };
      if (body.deleteLocalData !== undefined) args['delete-local-data'] = !!body.deleteLocalData;
      const result = await this.rpc.call('torrent-remove', args);
      const torrents = Array.isArray(lookup.torrents) ? lookup.torrents : [];
      await Promise.all(
        torrents.map(t => {
          const hash = t && (t.hashString || t.hash_string);
          return hash ? removeTorrentDownloadDir(hash) : Promise.resolve();
        })
      );
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }
  setTorrents = (req, res) => this.torrentAction('torrent-set', req, res);

  async setTorrentLocation(req, res) {
    try {
      await this.service.assertDaemonRunning();
      const body = req.body || {};
      const location = ensureString(body.location).trim();
      if (!location) return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      let ids = body.ids;
      if (ids === undefined || ids === null) {
        return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      }
      if (!Array.isArray(ids)) ids = [ids];
      const args = {
        ids,
        location,
        move: body.move !== false,
      };
      const result = await this.rpc.call('torrent-set-location', args);
      await rememberDownloadDir(location).catch(() => {});
      try {
        const lookup = await this.rpc.call('torrent-get', {
          ids,
          fields: ['hashString'],
        });
        const torrents = Array.isArray(lookup.torrents) ? lookup.torrents : [];
        await Promise.all(
          torrents.map(t => {
            const hash = t && (t.hashString || t.hash_string);
            return hash ? setTorrentDownloadDir(hash, location) : Promise.resolve();
          })
        );
      } catch (_) {}
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  verifyTorrents = (req, res) => this.torrentAction('torrent-verify', req, res);
  reannounceTorrents = (req, res) => this.torrentAction('torrent-reannounce', req, res);

  _normalizeFileWanted(value) {
    if (value === false || value === 0 || value === '0') return false;
    return true;
  }

  async getTorrentFiles(req, res) {
    try {
      await this.service.assertDaemonRunning();
      const query = req.method === 'GET' ? req.query || {} : req.body || {};
      const id = Number(query.id);
      if (!Number.isFinite(id)) {
        return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      }
      const result = await this.rpc.call('torrent-get', {
        ids: [id],
        fields: ['id', 'name', 'files', 'fileStats', 'wanted'],
      });
      const torrents = Array.isArray(result.torrents) ? result.torrents : [];
      const torrent = torrents[0];
      if (!torrent) {
        return ResponseUtil.success(req, res, { id, name: '', files: [] }, 'common.SUCCESS', 200);
      }
      const fileList = Array.isArray(torrent.files) ? torrent.files : [];
      const fileStats = Array.isArray(torrent.fileStats)
        ? torrent.fileStats
        : Array.isArray(torrent.file_stats)
          ? torrent.file_stats
          : [];
      const wantedList = Array.isArray(torrent.wanted) ? torrent.wanted : [];
      const files = fileList.map((file, index) => {
        const stat = fileStats[index] || {};
        let wanted = true;
        if (stat.wanted !== undefined && stat.wanted !== null) {
          wanted = this._normalizeFileWanted(stat.wanted);
        } else if (wantedList.length > index) {
          wanted = this._normalizeFileWanted(wantedList[index]);
        }
        return {
          index,
          name: file && file.name != null ? String(file.name) : '',
          length: Number(file && file.length) || 0,
          bytesCompleted:
            Number(stat.bytesCompleted ?? stat.bytes_completed ?? (file && file.bytesCompleted)) || 0,
          wanted,
        };
      });
      return ResponseUtil.success(
        req,
        res,
        { id: torrent.id, name: torrent.name || '', files },
        'common.SUCCESS',
        200
      );
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async setTorrentFiles(req, res) {
    try {
      await this.service.assertDaemonRunning();
      const body = req.body || {};
      let id = body.id;
      if (id === undefined && body.ids !== undefined) {
        id = Array.isArray(body.ids) ? body.ids[0] : body.ids;
      }
      id = Number(id);
      if (!Number.isFinite(id)) {
        return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      }
      const toIndexList = raw => {
        if (!Array.isArray(raw)) return [];
        return raw.map(v => Math.trunc(Number(v))).filter(v => Number.isFinite(v) && v >= 0);
      };
      const filesWanted = toIndexList(body.files_wanted ?? body.filesWanted);
      const filesUnwanted = toIndexList(body.files_unwanted ?? body.filesUnwanted);
      if (!filesWanted.length && !filesUnwanted.length) {
        return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      }
      const args = { ids: [id] };
      if (filesWanted.length) args['files-wanted'] = filesWanted;
      if (filesUnwanted.length) args['files-unwanted'] = filesUnwanted;
      const result = await this.rpc.call('torrent-set', args);
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }

  async freeSpace(req, res) {
    try {
      await this.service.assertDaemonRunning();
      const target = (req.query && req.query.path) || (req.body && req.body.path) || '';
      if (!target) return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      const result = await this.rpc.call('free-space', { path: String(target) });
      return ResponseUtil.success(req, res, result, 'common.SUCCESS', 200);
    } catch (e) {
      return ResponseUtil.error(req, res, e.message || 'common.ERROR', e.statusCode || 500);
    }
  }
}

module.exports = new TransmissionController();
