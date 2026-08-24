const express = require('express');
const router = express.Router();
const path = require('path');
const fs = require('fs');
const videoPlayerController = require('./videoPlayerController');
const rawController = require('../file/raw/fileRawController');
const { authenticateJWT } = require('../../middleware/authMiddleware');
const { requirePermission } = require('../../middleware/permissionMiddleware');
const { requireDownloadViewOrSubtitleUploadFile } = require('../../middleware/subtitleUploadRawAccess');
const { hasPermission } = require('../../../utils/permissionUtil');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');
const tableFileRecent = require('../../../db/table/tableFileRecent');

/** stream-mp4 外挂字幕路径需单独鉴权（与 filePath 可能不同） */
async function requireStreamMp4SubtitlePermission(req, res, next) {
  try {
    const raw = req.query && req.query.subtitlePath != null ? String(req.query.subtitlePath).trim() : '';
    if (!raw) return next();
    let decoded = raw;
    try {
      decoded = decodeURIComponent(raw);
    } catch (_) {}
    const subPath = typeof decoded === 'string' && decoded.trim() ? path.resolve(decoded.trim()) : '';
    if (!subPath) return next();
    // 路径无效时不在此拦截，由 streamMp4 忽略外挂并正常出流
    if (!fs.existsSync(subPath)) return next();
    try {
      if (!fs.statSync(subPath).isFile()) return next();
    } catch (_) {
      return next();
    }
    // 允许播放器“上传字幕”目录下的字幕（按 uid/fileHash 保存），不走 file 权限系统
    try {
      const root = path.resolve(String(require('../../../config/config').getSubtitleUploadPath()));
      const rel = path.relative(root, subPath);
      const inside = rel && !rel.startsWith('..') && !path.isAbsolute(rel);
      if (inside) return next();
    } catch (_) {}
    const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], subPath, 'file');
    if (!ok) {
      return res.status(403).json({
        success: false,
        message: getLocalizedMessage(req, 'auth.PERMISSION_DENIED'),
      });
    }
    return next();
  } catch (_) {
    return res.status(500).json({
      success: false,
      message: getLocalizedMessage(req, 'common.ERROR'),
    });
  }
}

/** subtitle-vtt 外挂字幕路径需单独鉴权（与 filePath 可能不同） */
async function requireSubtitleVttSubtitlePermission(req, res, next) {
  try {
    const raw = req.query && req.query.subtitlePath != null ? String(req.query.subtitlePath).trim() : '';
    if (!raw) return next();
    let decoded = raw;
    try {
      decoded = decodeURIComponent(raw);
    } catch (_) {}
    const subPath = typeof decoded === 'string' && decoded.trim() ? path.resolve(decoded.trim()) : '';
    if (!subPath) return next();
    // 路径无效时不在此拦截，由 subtitle-vtt 自行返回错误
    if (!fs.existsSync(subPath)) return next();
    try {
      if (!fs.statSync(subPath).isFile()) return next();
    } catch (_) {
      return next();
    }
    // 允许播放器“上传字幕”目录下的字幕（按 uid/fileHash 保存），不走 file 权限系统
    try {
      const root = path.resolve(String(require('../../../config/config').getSubtitleUploadPath()));
      const rel = path.relative(root, subPath);
      const inside = rel && !rel.startsWith('..') && !path.isAbsolute(rel);
      if (inside) return next();
    } catch (_) {}
    const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], subPath, 'file');
    if (!ok) {
      return res.status(403).json({
        success: false,
        message: getLocalizedMessage(req, 'auth.PERMISSION_DENIED'),
      });
    }
    return next();
  } catch (_) {
    return res.status(500).json({
      success: false,
      message: getLocalizedMessage(req, 'common.ERROR'),
    });
  }
}

/** subtitle-vtt: require permission for either filePath (video) or subtitlePath (external subtitle). */
async function requireSubtitleVttVideoOrSubtitlePermission(req, res, next) {
  try {
    const filePathRaw = req.query && req.query.filePath != null ? String(req.query.filePath).trim() : '';
    const subtitlePathRaw = req.query && req.query.subtitlePath != null ? String(req.query.subtitlePath).trim() : '';
    if (!filePathRaw && !subtitlePathRaw) {
      return res.status(400).json({
        success: false,
        message: getLocalizedMessage(req, 'videoPlayer.INVALID_PARAMS'),
      });
    }
    if (filePathRaw) {
      const resolved = path.resolve(filePathRaw);
      const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], resolved, 'file');
      if (!ok) {
        return res.status(403).json({
          success: false,
          message: getLocalizedMessage(req, 'auth.PERMISSION_DENIED'),
        });
      }
    }
    return next();
  } catch (_) {
    return res.status(500).json({
      success: false,
      message: getLocalizedMessage(req, 'common.ERROR'),
    });
  }
}

// 播放器原画直链（与 /api/file/rawFile 同一实现，专用于前端/P2P 识别，避免与下载、音乐等共用路径）
router.get(
  '/rawFile',
  authenticateJWT,
  requireDownloadViewOrSubtitleUploadFile,
  rawController.getRawFile
);

// Check info
router.get(
  '/info',
  authenticateJWT,
  requirePermission(['download', 'view'], { from: 'query.filePath' }),
  async (req, res, next) => {
    try {
      const uid = req.user && req.user.id;
      const filePath = req.query && req.query.filePath;
      if (uid && typeof filePath === 'string' && filePath) {
        await tableFileRecent.upsertRecent(uid, path.resolve(filePath), { knex: req.dbMain });
      }
    } catch (_) {}
    next();
  },
  videoPlayerController.getVideoInfo
);

// Start/Restart Transcoding (returns m3u8)
router.get('/transcode', authenticateJWT, requirePermission(['download', 'view'], { from: 'query.filePath' }), videoPlayerController.transcode);

// Get embedded subtitle as WebVTT (cached)
router.get(
  '/subtitle-vtt',
  authenticateJWT,
  requireSubtitleVttVideoOrSubtitlePermission,
  requireSubtitleVttSubtitlePermission,
  videoPlayerController.getSubtitleVtt
);

// Serve HLS files (no auth required strictly for segments if playId is secret enough,
// but usually auth is better. For standard HLS players, cookies/headers might be tricky.
// If using query token, we can use auth middleware.
// For now, let's keep auth if client can send it via cookie or query param.)
router.get('/hls/:playId/:filename', videoPlayerController.serveSegment);

// Stream as MP4 (for web / unsupported formats, e.g. Live Photo video)
router.get(
  '/stream-mp4',
  authenticateJWT,
  requirePermission(['download', 'view'], { from: 'query.filePath' }),
  requireStreamMp4SubtitlePermission,
  videoPlayerController.streamMp4
);

// Stop
router.post('/stop', authenticateJWT, videoPlayerController.stopTranscode);

// Save Preference
router.post('/preference', authenticateJWT, requirePermission(['download', 'view'], { from: 'body.filePath' }), videoPlayerController.saveVideoPreference);

// Upload external subtitle for a video (saved under subtitleUpload/<videoHash>/<uid>/)
router.post(
  '/uploadSubtitle',
  authenticateJWT,
  videoPlayerController.uploadSubtitle
);

router.post(
  '/clearUploadedSubtitles',
  authenticateJWT,
  videoPlayerController.clearUploadedSubtitles
);

// Search subtitles for a video file (Thunder subtitle service)
router.post(
  '/searchSubtitle',
  authenticateJWT,
  requirePermission(['download', 'view'], { from: 'body.filePath' }),
  videoPlayerController.searchSubtitle
);

// Download a searched subtitle into subtitleUpload/<videoHash>/<uid>/
router.post(
  '/downloadSearchedSubtitle',
  authenticateJWT,
  requirePermission(['download', 'view'], { from: 'body.filePath' }),
  videoPlayerController.downloadSearchedSubtitle
);

// Delete an external subtitle under subtitleUpload/<videoHash>/<uid>/
router.post(
  '/deleteExternalSubtitle',
  authenticateJWT,
  requirePermission(['download', 'view'], { from: 'body.filePath' }),
  videoPlayerController.deleteExternalSubtitle
);

module.exports = router;
