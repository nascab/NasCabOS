const path = require('path');
const tableConfig = require('../db/table/tableConfig');

const ACCESS_SCOPE_ALL = 'all';
const ACCESS_SCOPE_SPECIFIED = 'specified';
const DEFAULT_TERMINAL_ENABLED = true;

function normalizePathItem(value) {
  if (typeof value !== 'string') return '';
  const trimmed = value.trim();
  if (!trimmed) return '';
  let input = trimmed;
  // Windows: path.resolve('D:') is relative to the process cwd on that drive, not the volume root.
  // Treat drive-only roots (D:, D:/, D:\) as D:\ so scope / prefix checks match real absolute paths.
  if (process.platform === 'win32') {
    const m = /^([a-zA-Z]):[/\\]?$/.exec(trimmed);
    if (m) {
      input = `${m[1].toUpperCase()}:\\`;
    }
  }
  return path.resolve(input);
}

function resolveUniquePaths(pathList) {
  return [...new Set((Array.isArray(pathList) ? pathList : []).map(normalizePathItem).filter(Boolean))];
}

function isPathInRoot(targetPath, rootPath) {
  const target = normalizePathItem(targetPath);
  const root = normalizePathItem(rootPath);
  if (!target || !root) return false;
  if (target === root) return true;
  // If root already ends with sep (e.g. Windows "E:\"), do not append sep again or we require "E:\\" and break "E:\foo".
  const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
  return target.startsWith(prefix);
}

function trimParentPaths(pathList) {
  const uniquePaths = resolveUniquePaths(pathList);
  return uniquePaths.filter(item => !uniquePaths.some(other => other !== item && isPathInRoot(other, item)));
}

function normalizeScopeMode(mode) {
  return mode === ACCESS_SCOPE_SPECIFIED ? ACCESS_SCOPE_SPECIFIED : ACCESS_SCOPE_ALL;
}

function normalizeTerminalEnabled(value) {
  if (value === false || value === 'false' || value === 0 || value === '0') return false;
  if (value === true || value === 'true' || value === 1 || value === '1') return true;
  return DEFAULT_TERMINAL_ENABLED;
}

function intersectRootLists(primaryRoots, limitRoots) {
  const primary = trimParentPaths(primaryRoots);
  const limits = trimParentPaths(limitRoots);
  if (limits.length === 0) return [];

  const intersections = [];
  for (const item of primary) {
    if (limits.some(limit => isPathInRoot(item, limit))) {
      intersections.push(item);
    }
  }
  for (const limit of limits) {
    if (primary.some(item => isPathInRoot(limit, item))) {
      intersections.push(limit);
    }
  }
  return trimParentPaths(intersections);
}

async function getAppAccessScopeConfig() {
  const modeRaw = await tableConfig.getConfigByKey(tableConfig.KEY_APP_ACCESS_SCOPE_MODE);
  const dirsRaw = await tableConfig.getJsonConfigByKey(tableConfig.KEY_APP_ACCESS_SCOPE_DIRS);
  const terminalEnabledRaw = await tableConfig.getConfigByKey(tableConfig.KEY_APP_TERMINAL_ENABLED);
  return {
    mode: normalizeScopeMode(modeRaw),
    dirs: trimParentPaths(Array.isArray(dirsRaw) ? dirsRaw : []),
    terminalEnabled: normalizeTerminalEnabled(terminalEnabledRaw),
  };
}

async function setAppAccessScopeConfig(payload = {}) {
  const mode = normalizeScopeMode(payload.mode);
  const dirs = trimParentPaths(Array.isArray(payload.dirs) ? payload.dirs : []);
  const terminalEnabled = normalizeTerminalEnabled(payload.terminalEnabled);
  const modeSaved = await tableConfig.setConfigByKey(tableConfig.KEY_APP_ACCESS_SCOPE_MODE, mode);
  const dirsSaved = await tableConfig.setJsonConfigByKey(tableConfig.KEY_APP_ACCESS_SCOPE_DIRS, dirs);
  const terminalSaved = await tableConfig.setConfigByKey(tableConfig.KEY_APP_TERMINAL_ENABLED, terminalEnabled ? 'true' : 'false');
  return modeSaved && dirsSaved && terminalSaved;
}

async function getAppSpecifiedRoots() {
  const config = await getAppAccessScopeConfig();
  return config.mode === ACCESS_SCOPE_SPECIFIED ? config.dirs : null;
}

async function isAppTerminalEnabled() {
  const raw = await tableConfig.getConfigByKey(tableConfig.KEY_APP_TERMINAL_ENABLED);
  return normalizeTerminalEnabled(raw);
}

function isPathAllowedByRoots(targetPath, rootPaths) {
  if (rootPaths === null) return true;
  const roots = Array.isArray(rootPaths) ? rootPaths : [];
  return roots.some(root => isPathInRoot(targetPath, root));
}

module.exports = {
  ACCESS_SCOPE_ALL,
  ACCESS_SCOPE_SPECIFIED,
  getAppAccessScopeConfig,
  setAppAccessScopeConfig,
  getAppSpecifiedRoots,
  isAppTerminalEnabled,
  isPathAllowedByRoots,
  intersectRootLists,
  isPathInRoot,
  normalizePathItem,
  resolveUniquePaths,
  trimParentPaths,
};
