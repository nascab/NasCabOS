const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function ensureString(value) {
  if (value === undefined || value === null) return '';
  return String(value);
}

function uniqueNonEmpty(items) {
  const out = [];
  const seen = new Set();
  for (const item of items || []) {
    const v = ensureString(item).trim();
    if (!v) continue;
    const key = process.platform === 'win32' ? v.toLowerCase() : v;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(v);
  }
  return out;
}

function existingArtifact(dirPath) {
  const base = ensureString(dirPath).trim();
  if (!base) return '';
  const candidates = [
    'bin\\winfsp-x64.dll',
    'bin\\winfsp-x86.dll',
    'bin\\winfsp-a64.dll',
    'bin\\fsptool-x64.exe',
    'bin\\fsptool-x86.exe',
    'bin\\fsptool-a64.exe',
  ];
  for (const relativePath of candidates) {
    const fullPath = path.join(base, relativePath);
    try {
      if (fs.existsSync(fullPath)) return fullPath;
    } catch (_) {}
  }
  return '';
}

function queryRegistryInstallDir(registryKey) {
  const key = ensureString(registryKey).trim();
  if (!key) return '';
  try {
    const res = spawnSync('reg', ['query', key, '/v', 'InstallDir'], {
      windowsHide: true,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 3000,
    });
    if (!res || res.status !== 0) return '';
    const text = `${ensureString(res.stdout)}\n${ensureString(res.stderr)}`;
    const match = text.match(/InstallDir\s+REG_\w+\s+([^\r\n]+)/i);
    return match ? ensureString(match[1]).trim() : '';
  } catch (_) {
    return '';
  }
}

function detectWinFsp() {
  if (process.platform !== 'win32') {
    return {
      platform: process.platform,
      isWindows: false,
      available: true,
      installDir: '',
      artifactPath: '',
      detectedBy: 'not_required',
      reason: 'fileMount.WINFSP_NOT_REQUIRED',
    };
  }

  const registryKeys = [
    'HKLM\\SOFTWARE\\WinFsp',
    'HKLM\\SOFTWARE\\WOW6432Node\\WinFsp',
  ];
  for (const key of registryKeys) {
    const installDir = queryRegistryInstallDir(key);
    const artifactPath = existingArtifact(installDir);
    if (installDir && artifactPath) {
      return {
        platform: process.platform,
        isWindows: true,
        available: true,
        installDir,
        artifactPath,
        detectedBy: 'registry',
        reason: '',
      };
    }
  }

  const pathEntries = uniqueNonEmpty(ensureString(process.env.PATH).split(';'));
  for (const entry of pathEntries) {
    const normalized = entry.replace(/\//g, '\\').toLowerCase();
    if (!normalized.includes('\\winfsp\\bin')) continue;
    const installDir = path.dirname(entry);
    const artifactPath = existingArtifact(installDir);
    if (artifactPath) {
      return {
        platform: process.platform,
        isWindows: true,
        available: true,
        installDir,
        artifactPath,
        detectedBy: 'path',
        reason: '',
      };
    }
  }

  const commonInstallDirs = uniqueNonEmpty([
    process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'WinFsp'),
    process.env['ProgramFiles(x86)'] && path.join(process.env['ProgramFiles(x86)'], 'WinFsp'),
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'WinFsp'),
  ]);
  for (const installDir of commonInstallDirs) {
    const artifactPath = existingArtifact(installDir);
    if (artifactPath) {
      return {
        platform: process.platform,
        isWindows: true,
        available: true,
        installDir,
        artifactPath,
        detectedBy: 'common_path',
        reason: '',
      };
    }
  }

  return {
    platform: process.platform,
    isWindows: true,
    available: false,
    installDir: '',
    artifactPath: '',
    detectedBy: '',
    reason: 'fileMount.WINFSP_NOT_AVAILABLE',
  };
}

module.exports = {
  detectWinFsp,
};
