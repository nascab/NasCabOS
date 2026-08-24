const ResponseUtil = require('../../../apiUtils/responseUtil');
const path = require('path');
const fs = require('fs');
const Logger = require('../../../../utils/logger');

/**
 * 检查路径是否存在（支持多种格式）
 */
function resolveAndCheck(filePath) {
  const raw = (filePath || '').trim();
  if (!raw) return null;

  // 尝试多种解析方式
  const candidates = [raw];
  try {
    const resolved = path.resolve(raw);
    if (resolved !== raw) candidates.push(resolved);
  } catch (_) {}

  // 尝试 path.normalize
  try {
    const norm = path.normalize(raw);
    if (!candidates.includes(norm)) candidates.push(norm);
  } catch (_) {}

  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) {
        return p;
      }
    } catch (_) {}
  }

  Logger.warn('[fileSystemController] 路径不存在', {
    raw,
    candidates,
  });
  return null;
}

/**
 * 在系统中用默认程序打开文件/文件夹
 * POST /api/file/system/open  body: { path }
 */
function openInSystem(req, res) {
  try {
    const filePath = (req.body.path || '').trim();
    Logger.debug('[fileSystem/open] 收到请求 path:', filePath);

    if (!filePath) {
      return ResponseUtil.error(req, res, 'file.FILE_NOT_FOUND');
    }

    const resolved = resolveAndCheck(filePath);
    if (!resolved) {
      return ResponseUtil.error(req, res, 'file.FILE_NOT_FOUND');
    }

    if (!process.send) {
      return ResponseUtil.error(req, res, 'system.NOT_SUPPORTED');
    }

    process.send({
      type: 'shell',
      shellType: 'openPath',
      path: resolved,
    });

    return ResponseUtil.success(req, res, { path: resolved });
  } catch (err) {
    Logger.error('[fileSystem/open] 异常:', err);
    return ResponseUtil.serverError(req, res, err);
  }
}

/**
 * 在系统文件管理器中选中并显示文件/文件夹
 * POST /api/file/system/show  body: { path }
 */
function showInSystem(req, res) {
  try {
    const filePath = (req.body.path || '').trim();
    Logger.debug('[fileSystem/show] 收到请求 path:', filePath);

    if (!filePath) {
      return ResponseUtil.error(req, res, 'file.FILE_NOT_FOUND');
    }

    const resolved = resolveAndCheck(filePath);
    if (!resolved) {
      return ResponseUtil.error(req, res, 'file.FILE_NOT_FOUND');
    }

    if (!process.send) {
      return ResponseUtil.error(req, res, 'system.NOT_SUPPORTED');
    }

    process.send({
      type: 'shell',
      shellType: 'showItemInFolder',
      path: resolved,
    });

    return ResponseUtil.success(req, res, { path: resolved });
  } catch (err) {
    Logger.error('[fileSystem/show] 异常:', err);
    return ResponseUtil.serverError(req, res, err);
  }
}

module.exports = {
  openInSystem,
  showInSystem,
};
