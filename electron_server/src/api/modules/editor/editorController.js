const fs = require('fs');
const path = require('path');
const ResponseUtil = require('../../apiUtils/responseUtil');
const { EditorDocManager } = require('./editorDocManager');
const tableConfig = require('../../../db/table/tableConfig');
const { hasPermission } = require('../../../utils/permissionUtil');

const docManager = new EditorDocManager();
const MAX_EDITOR_FILE_BYTES = 20 * 1024 * 1024;
const EDITOR_CONFIG_KEY = 'editorConfig';

const DEFAULT_EDITOR_CONFIG = Object.freeze({
  fontSize: 14,
});

function getExt(p) {
  return path
    .extname(String(p || ''))
    .toLowerCase()
    .replace('.', '');
}

function isSupportedTextExt(ext) {
  const s = String(ext || '').toLowerCase();
  if (!s) return true;
  return new Set([
    'txt',
    'md',
    'markdown',
    'vue',
    'properties',
    'js',
    'ts',
    'jsx',
    'tsx',
    'json',
    'yaml',
    'yml',
    'py',
    'java',
    'c',
    'cc',
    'cpp',
    'h',
    'hpp',
    'css',
    'html',
    'xml',
    'dart',
    'go',
    'rs',
    'sh',
    'bat',
    'ini',
    'conf',
    'log',
    'php',
    'rb',
    'lua',
    'sql',
    'toml',
    'env',
    'gradle',
    'kt',
    'swift',
    'scss',
    'less',
    'svelte',
    'gitignore',
  ]).has(s);
}

function sanitizeEditorConfig(input) {
  const raw = input && typeof input === 'object' ? input : {};
  const fontRaw = raw.fontSize ?? raw.font_size ?? DEFAULT_EDITOR_CONFIG.fontSize;
  const fontSizeNum = Math.trunc(Number(fontRaw));
  const fontSize = Number.isFinite(fontSizeNum) ? Math.min(40, Math.max(10, fontSizeNum)) : DEFAULT_EDITOR_CONFIG.fontSize;

  return {
    fontSize,
  };
}

async function getUserEditorConfig(uid) {
  const id = Number(uid);
  if (!Number.isFinite(id) || id <= 0) return { ...DEFAULT_EDITOR_CONFIG };
  const raw = await tableConfig.getConfigByKey(EDITOR_CONFIG_KEY, id);
  if (!raw) return { ...DEFAULT_EDITOR_CONFIG };
  try {
    const parsed = JSON.parse(raw);
    return sanitizeEditorConfig(parsed);
  } catch (_) {
    return { ...DEFAULT_EDITOR_CONFIG };
  }
}

async function saveUserEditorConfig(uid, config) {
  const id = Number(uid);
  if (!Number.isFinite(id) || id <= 0) {
    const err = new Error('auth.AUTHENTICATION_REQUIRED');
    err.statusCode = 401;
    throw err;
  }
  const sanitized = sanitizeEditorConfig(config);
  const ok = await tableConfig.setConfigByKey(EDITOR_CONFIG_KEY, JSON.stringify(sanitized), id);
  if (!ok) {
    const err = new Error('common.ERROR');
    err.statusCode = 500;
    throw err;
  }
  return sanitized;
}

async function resetUserEditorConfig(uid) {
  const id = Number(uid);
  if (!Number.isFinite(id) || id <= 0) {
    const err = new Error('auth.AUTHENTICATION_REQUIRED');
    err.statusCode = 401;
    throw err;
  }
  const ok = await tableConfig.setConfigByKey(EDITOR_CONFIG_KEY, '', id);
  if (!ok) {
    const err = new Error('common.ERROR');
    err.statusCode = 500;
    throw err;
  }
  return { ...DEFAULT_EDITOR_CONFIG };
}

async function open(req, res) {
  try {
    const rawPath = req.body && req.body.path;
    if (!rawPath) return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
    const resolved = path.resolve(String(rawPath));

    const ext = getExt(resolved);
    if (ext && !isSupportedTextExt(ext)) {
      return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
    }

    const st = await fs.promises.stat(resolved).catch(() => null);
    if (!st || !st.isFile()) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
    if (st.size > MAX_EDITOR_FILE_BYTES) {
      return ResponseUtil.error(req, res, 'editor.FILE_TOO_LARGE', 413);
    }

    const docInfo = await docManager.open({ filePath: resolved });
    const uid = req.user && req.user.id;
    const config = await getUserEditorConfig(uid);
    const canWriteByPerm = await hasPermission(req.dbMain, req.user, 'update', resolved).catch(() => false);
    const canWriteByFs = await fs.promises
      .access(resolved, fs.constants.W_OK)
      .then(() => true)
      .catch(() => false);
    const canWrite = !!canWriteByPerm && !!canWriteByFs;

    return ResponseUtil.success(req, res, {
      docId: docInfo.docId,
      path: resolved,
      text: docInfo.ytext.toString(),
      rev: docInfo.rev,
      size: st.size,
      mtimeMs: st.mtimeMs,
      config,
      canWrite,
    });
  } catch (e) {
    return ResponseUtil.error(req, res, 'common.ERROR', 500, {
      error: e && e.message ? String(e.message) : String(e),
    });
  }
}

async function save(req, res) {
  try {
    const rawPath = req.body && req.body.path;
    const text = req.body && req.body.text;
    if (!rawPath || typeof text !== 'string') {
      return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
    }
    const resolved = path.resolve(String(rawPath));
    const canWriteByFs = await fs.promises
      .access(resolved, fs.constants.W_OK)
      .then(() => true)
      .catch(() => false);
    if (!canWriteByFs) {
      return ResponseUtil.error(req, res, 'file.NO_WRITE_PERMISSION', 403);
    }
    await fs.promises.writeFile(resolved, text, 'utf8');
    return ResponseUtil.success(req, res, { ok: true }, 'common.SUCCESS', 200);
  } catch (e) {
    return ResponseUtil.error(req, res, 'common.ERROR', 500, {
      error: e && e.message ? String(e.message) : String(e),
    });
  }
}

async function getConfig(req, res) {
  try {
    const uid = req.user && req.user.id;
    const config = await getUserEditorConfig(uid);
    return ResponseUtil.success(req, res, { config }, 'common.SUCCESS', 200);
  } catch (e) {
    const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
    const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
    return ResponseUtil.error(req, res, msgKey, statusCode, {
      error: e && e.message ? String(e.message) : String(e),
    });
  }
}

async function setConfig(req, res) {
  try {
    const uid = req.user && req.user.id;
    const payload = req.body && req.body.config;
    const config = await saveUserEditorConfig(uid, payload);
    return ResponseUtil.success(req, res, { config }, 'common.SUCCESS', 200);
  } catch (e) {
    const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
    const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
    return ResponseUtil.error(req, res, msgKey, statusCode, {
      error: e && e.message ? String(e.message) : String(e),
    });
  }
}

async function resetConfig(req, res) {
  try {
    const uid = req.user && req.user.id;
    const config = await resetUserEditorConfig(uid);
    return ResponseUtil.success(req, res, { config }, 'common.SUCCESS', 200);
  } catch (e) {
    const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
    const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
    return ResponseUtil.error(req, res, msgKey, statusCode, {
      error: e && e.message ? String(e.message) : String(e),
    });
  }
}

module.exports = {
  open,
  save,
  getConfig,
  setConfig,
  resetConfig,
  docManager,
};
