const fs = require('fs');
const path = require('path');

function getPathDelimiter() {
  return process.platform === 'win32' ? ';' : ':';
}

function normalizePathKey(item) {
  if (process.platform !== 'win32') return String(item || '').trim();
  return String(item || '').trim().toLowerCase();
}

function splitPathList(value) {
  return String(value || '')
    .split(getPathDelimiter())
    .map(s => s.trim())
    .filter(Boolean);
}

function uniqueJoinPathList(items) {
  const seen = new Set();
  const out = [];
  for (const item of items) {
    const p = String(item || '').trim();
    if (!p) continue;
    const key = normalizePathKey(p);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(p);
  }
  return out.join(getPathDelimiter());
}

function getWindowsPathHints() {
  const hints = [];
  const programFiles = process.env.ProgramFiles || 'C:\\Program Files';
  const programFilesX86 = process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';
  const localAppData = process.env.LOCALAPPDATA;
  const systemRoot = process.env.SystemRoot || process.env.windir || 'C:\\Windows';

  hints.push(path.join(programFiles, 'Docker', 'Docker', 'resources', 'bin'));
  hints.push(path.join(programFilesX86, 'Docker', 'Docker', 'resources', 'bin'));
  if (localAppData) {
    hints.push(path.join(localAppData, 'Docker', 'Docker', 'resources', 'bin'));
  }
  hints.push(path.join(systemRoot, 'System32'));
  hints.push(path.join(systemRoot, 'System32', 'Wbem'));
  hints.push(path.join(systemRoot, 'System32', 'WindowsPowerShell', 'v1.0'));
  return hints;
}

function getPlatformPathHints() {
  const platform = process.platform;
  if (platform === 'darwin') {
    return [
      // Docker Desktop CLI symlinks / wrappers
      '/usr/local/bin',
      '/opt/homebrew/bin',
      // Docker Desktop bundled CLI path (some setups rely on this)
      '/Applications/Docker.app/Contents/Resources/bin',
      // system defaults
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
    ];
  }
  if (platform === 'win32') {
    return getWindowsPathHints();
  }
  return ['/usr/local/bin', '/usr/bin', '/bin', '/usr/sbin', '/sbin'];
}

function readPathValue(env) {
  const base = env && typeof env === 'object' ? env : {};
  if (process.platform === 'win32') {
    return base.Path || base.PATH || base.path || '';
  }
  return base.PATH || base.Path || '';
}

function withAugmentedPath(env = {}) {
  const base = env && typeof env === 'object' ? env : {};
  const current = splitPathList(readPathValue(base));
  const hints = getPlatformPathHints();
  // Put hints first so "docker" resolves even if PATH is minimal.
  const merged = uniqueJoinPathList([...hints, ...current]);
  if (process.platform === 'win32') {
    return {
      ...base,
      Path: merged,
      PATH: merged,
    };
  }
  return {
    ...base,
    PATH: merged,
  };
}

let cachedDockerExecutable = null;

function resolveDockerExecutable() {
  if (cachedDockerExecutable) return cachedDockerExecutable;
  if (process.platform === 'win32') {
    for (const dir of getWindowsPathHints()) {
      const candidate = path.join(dir, 'docker.exe');
      try {
        if (fs.existsSync(candidate)) {
          cachedDockerExecutable = candidate;
          return cachedDockerExecutable;
        }
      } catch (_) {}
    }
  }
  cachedDockerExecutable = 'docker';
  return cachedDockerExecutable;
}

module.exports = {
  withAugmentedPath,
  resolveDockerExecutable,
};
