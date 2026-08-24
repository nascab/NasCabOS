const path = require('path');
const fs = require('fs');
const config = require('../../config/config');
const { hasPermission } = require('../../utils/permissionUtil');
const { getLocalizedMessage } = require('../../utils/i18nUtil');

/**
 * 已登录用户读取原始文件：普通路径走文件权限；位于「播放器字幕上传目录」下的文件
 * （搜索/下载/上传字幕）允许读取，避免 /api/file/rawFile 因不在媒体库权限内而 403，
 * 与 stream-mp4 外挂字幕鉴权策略一致。
 */
async function requireDownloadViewOrSubtitleUploadFile(req, res, next) {
  try {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        message: getLocalizedMessage(req, 'auth.AUTHENTICATION_REQUIRED'),
      });
    }
    const pathUrl = req.query && req.query.path != null ? String(req.query.path).trim() : '';
    if (!pathUrl) {
      return res.status(400).send('Missing path');
    }
    let decoded = pathUrl;
    try {
      decoded = decodeURIComponent(pathUrl);
    } catch (_) {
      decoded = pathUrl;
    }
    const fullPath = path.resolve(decoded.trim());
    let root = '';
    try {
      root = path.resolve(String(config.getSubtitleUploadPath()));
    } catch (_) {
      root = '';
    }
    if (root) {
      const rel = path.relative(root, fullPath);
      const inside = rel && !rel.startsWith('..') && !path.isAbsolute(rel);
      if (inside) {
        try {
          const st = await fs.promises.stat(fullPath);
          if (st.isFile()) {
            return next();
          }
        } catch (_) {
          // fall through to normal permission
        }
      }
    }
    const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], fullPath, 'file');
    if (!ok) {
      return res.status(403).json({
        success: false,
        message: getLocalizedMessage(req, 'auth.PERMISSION_DENIED'),
      });
    }
    return next();
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: getLocalizedMessage(req, 'common.ERROR'),
    });
  }
}

module.exports = {
  requireDownloadViewOrSubtitleUploadFile,
};
