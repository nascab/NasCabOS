'use strict';

const path = require('path');
const FileUtil = require('../../utils/fileUtil');
const config = require('../../config/config');

const isWin = process.platform === 'win32';
const isMac = process.platform === 'darwin';

function _safeResolve(p) {
  if (!p) return '';
  try {
    return path.resolve(String(p));
  } catch (_) {
    return String(p);
  }
}

function _normalizeForMatch(p) {
  const resolved = _safeResolve(p);
  const posix = resolved.replace(/\\/g, '/');
  const normalized = isWin || isMac ? posix.toLowerCase() : posix;
  return normalized.endsWith('/') && normalized.length > 1 ? normalized.slice(0, -1) : normalized;
}

function _splitPosixSegments(normalizedPosixPath) {
  const cleaned = String(normalizedPosixPath || '').replace(/\\/g, '/');
  const parts = cleaned.split('/').filter(Boolean);
  if (isWin) {
    if (parts.length > 0 && /^[a-z]:$/i.test(parts[0])) parts[0] = parts[0].toLowerCase();
  }
  return parts;
}

const IGNORED_FILE_NAMES = new Set(
  ['pagefile.sys', 'hiberfil.sys', 'swapfile.sys', 'dumpstack.log', 'swapfile', 'desktop.ini', 'thumbs.db', '.ds_store'].map(s => (isWin || isMac ? s.toLowerCase() : s))
);

const IGNORED_FILE_SUFFIXES = [
  '.tmp',
  '.temp',
  '.cache',
  '.log',
  '.db-wal',
  '.db-shm',
  '.db-journal',
  '.sqlite-wal',
  '.sqlite-shm',
  '.journal',
  '.partial',
  '.part',
  '.crdownload',
  '.download',
  '.downloading',
  '.qkdownloading',
  '.xltd',
  '.td',
  '.aria2',
  '.swp',
  '.swo',
  '.sb-',
];

const IGNORED_FILE_EXTS = new Set(['.vhdx', '.vmdk', '.vdi', '.iso', '.img', '.bin', '.rar', '.7z', '.zip', '.enc', '.crypt', '.secure'].map(s => (isWin || isMac ? s.toLowerCase() : s)));

const IGNORED_DIR_NAMES = new Set(
  [
    'tmp',
    'temp',
    'cache',
    'caches',
    'logs',
    'log',
    'mongodb',
    'redis',
    'mysql',
    'postgresql',
    'node_modules',
    '__pycache__',
    'miniconda',
    'miniconda3',
    'anaconda',
    'anaconda3',
    'miniforge',
    'miniforge3',
    'mambaforge',
    'mambaforge3',
    '.npm',
    '.yarn',
    '.gradle',
    '.cargo',
    '.rustup',
    '.m2',
    '.vscode',
    '.idea',
    '.snapshots',
    '.zfs',
    '.encrypted',
    '@eadir',
    '$recycle.bin',
    'recycle.bin',
    'system volume information',
    'lost+found',
    'build',
    'dist',
    'out',
    'target',
    '.next',
    '.nuxt',
    '.output',
    'coverage',
    'obj',
    'bin',
    'release',
    'debug',
    'x64',
    'x86',
    'arm64',
    'ios',
    'android',
    'web',
    'electron',
    'cmake-build',
    '.gradle',
    'gradle',
    'maven',
    '.maven',
    'vendor',
    'bower_components',
    '.ember-cli',
    '.meteor',
    '.serverless',
    '.webpack',
    '.cache-loader',
    '.temp',
    '.vs',
  ].map(s => (isWin || isMac ? s.toLowerCase() : s))
);

const IGNORED_DIR_NAME_PREFIXES = ['@recently-snapshot', '@docker', '@database', '@appstore', '@synologydrive', '@cloudsync', '@sharebin', '@tmp', '@appdata'].map(s =>
  isWin || isMac ? s.toLowerCase() : s
);

const WINDOWS_IGNORED_PATH_PREFIXES = ['/windows', '/program files', '/program files (x86)', '/programdata', '/$winreagent', '/recovery', '/msocache', '/perflogs'].map(s => s.toLowerCase());

const UNIX_IGNORED_PATH_PREFIXES = [
  '/bin',
  '/boot',
  '/dev',
  '/etc',
  '/lib',
  '/lib64',
  '/nix',
  '/opt',
  '/run',
  '/sbin',
  '/snap',
  '/srv',
  '/sys',
  '/proc',
  '/initrd',
  '/lost+found',
  '/system',
  '/library',
  '/applications',
  '/private',
  '/var',
  '/usr',
].map(s => (isMac ? s.toLowerCase() : s));

const RE_PYTHON_VERSION_DIR = /^python\d+(\.\d+)*$/;
const RE_WINDOWS_DRIVE = /^[a-z]:$/i;
const RE_VOLUME_DIR = /^volume\d+$/i;

function isHiddenName(name) {
  if (!name) return false;
  return String(name).startsWith('.');
}

function isPythonVersionDirName(normNameLower) {
  const n = String(normNameLower || '').toLowerCase();
  if (!n.startsWith('python')) return false;
  return RE_PYTHON_VERSION_DIR.test(n);
}

function _isUnderPrefix(normPosix, prefixPosix) {
  if (!normPosix || !prefixPosix) return false;
  if (normPosix === prefixPosix) return true;
  return normPosix.startsWith(prefixPosix.endsWith('/') ? prefixPosix : `${prefixPosix}/`);
}

function shouldIgnorePath(fullPath) {
  const resolved = _safeResolve(fullPath);
  if (!resolved) return true;

  const norm = _normalizeForMatch(resolved);
  const segments = _splitPosixSegments(norm);
  const segmentsLower = segments.map(s => String(s || '').toLowerCase());
  const hasVolumeDir = segmentsLower.some(s => RE_VOLUME_DIR.test(s));
  if (segments.some(s => s.startsWith('.'))) return true;
  if (isMac) {
    if (segmentsLower.some(s => String(s || '').endsWith('.app'))) return true;
    if (segmentsLower.some(s => String(s || '').endsWith('.asar'))) return true;
    if (norm.includes('.asar/')) return true;
  }

  const cachePath = typeof config.getCachePath === 'function' ? config.getCachePath() : '';
  const dbPath = typeof config.getDatabasePath === 'function' ? config.getDatabasePath() : '';
  const userDataPath = typeof config.getUserDataPath === 'function' ? config.getUserDataPath() : '';

  const cacheNorm = cachePath ? _normalizeForMatch(cachePath) : '';
  const dbNorm = dbPath ? _normalizeForMatch(dbPath) : '';
  const userDataNorm = userDataPath ? _normalizeForMatch(userDataPath) : '';

  if (cacheNorm && _isUnderPrefix(norm, cacheNorm)) return true;
  if (dbNorm && _isUnderPrefix(norm, dbNorm)) return true;
  if (userDataNorm && _isUnderPrefix(norm, userDataNorm)) return true;

  if (isWin) {
    const pathWithoutDrive = norm.replace(/^[a-z]:/i, '');
    for (const p of WINDOWS_IGNORED_PATH_PREFIXES) {
      if (pathWithoutDrive.startsWith(p) || pathWithoutDrive.startsWith(p + '/')) return true;
    }
    if (segments.length >= 3 && segments[0] && RE_WINDOWS_DRIVE.test(segments[0])) {
      if (segments[1] === 'users' && (segments[2] || '').length > 0) {
        const rest = segments.slice(3);
        if (rest.includes('appdata') || rest.includes('local settings') || rest.includes('temp')) return true;
      }
    }
  } else {
    for (const p of UNIX_IGNORED_PATH_PREFIXES) {
      if (_isUnderPrefix(norm, p)) return true;
    }
    if (isMac) {
      if (_isUnderPrefix(norm, '/volumes/macintosh hd')) return true;
      if (segments.length >= 3 && segments[0] === 'users' && (segments[1] || '').length > 0) {
        const rest = segments.slice(2);
        if (rest[0] === 'library' || rest[0] === 'caches' || rest[0] === 'applications') return true;
      }
    }
  }

  for (const seg of segments) {
    const segNorm = isWin || isMac ? String(seg).toLowerCase() : String(seg);
    if (IGNORED_DIR_NAMES.has(segNorm)) return true;
    if (IGNORED_DIR_NAME_PREFIXES.some(prefix => segNorm.startsWith(prefix))) return true;
    if (isPythonVersionDirName(segNorm)) return true;
    if (segNorm.startsWith('@') && hasVolumeDir) return true;
    if (segNorm.includes('cache') && (segmentsLower.includes('chrome') || segmentsLower.includes('firefox') || segmentsLower.includes('edge'))) return true;
  }

  for (let i = 0; i < segments.length - 1; i++) {
    const a = String(segmentsLower[i] || '');
    const b = String(segmentsLower[i + 1] || '');
    if (a === 'go' && b === 'pkg') return true;
  }

  const base = path.basename(resolved);
  const baseNorm = isWin || isMac ? base.toLowerCase() : base;
  if (isHiddenName(baseNorm)) return true;
  if (FileUtil.isSystemFile(base)) return true;
  if (isMac && String(baseNorm).endsWith('.photoslibrary')) return true;
  if (IGNORED_FILE_NAMES.has(baseNorm)) return true;
  if (FileUtil.isTemporaryOrDownloadingFile(base)) return true;

  const ext = path.extname(baseNorm);
  if (isMac && ext === '.asar') return true;
  if (ext && IGNORED_FILE_EXTS.has(ext)) return true;
  for (const suffix of IGNORED_FILE_SUFFIXES) {
    const sfx = isWin || isMac ? suffix.toLowerCase() : suffix;
    if (baseNorm.endsWith(sfx)) return true;
  }

  return false;
}

function shouldIgnoreDirectoryEntry({ parentDir, name }) {
  if (!name) return true;
  if (isHiddenName(name)) return true;
  if (FileUtil.isSystemFile(name)) return true;

  const normName = isWin || isMac ? String(name).toLowerCase() : String(name);
  if (IGNORED_DIR_NAMES.has(normName)) return true;
  if (IGNORED_DIR_NAME_PREFIXES.some(prefix => normName.startsWith(prefix))) return true;
  if (isPythonVersionDirName(normName)) return true;
  if (isMac && String(normName).endsWith('.photoslibrary')) return true;

  const full = parentDir ? path.join(parentDir, name) : name;
  return shouldIgnorePath(full);
}

function shouldIgnoreFileEntry({ parentDir, name }) {
  if (!name) return true;
  if (isHiddenName(name)) return true;
  if (FileUtil.isSystemFile(name)) return true;
  if (IGNORED_FILE_NAMES.has(isWin || isMac ? String(name).toLowerCase() : String(name))) return true;
  if (FileUtil.isTemporaryOrDownloadingFile(name)) return true;

  const full = parentDir ? path.join(parentDir, name) : name;
  if (shouldIgnorePath(full)) return true;

  const ext = path.extname(name).toLowerCase();
  if (ext && IGNORED_FILE_EXTS.has(isWin || isMac ? ext.toLowerCase() : ext)) return true;
  const lowerName = isWin || isMac ? String(name).toLowerCase() : String(name);
  for (const suffix of IGNORED_FILE_SUFFIXES) {
    const sfx = isWin || isMac ? suffix.toLowerCase() : suffix;
    if (lowerName.endsWith(sfx)) return true;
  }

  return false;
}

function buildWatchIgnoredList() {
  const base = Array.isArray(FileUtil.watchIgnoredList) ? FileUtil.watchIgnoredList.slice() : [];
  const extra = [
    '**/.*',
    '**/.*/**',
    '**/node_modules',
    '**/node_modules/**',
    '**/__pycache__',
    '**/__pycache__/**',
    '**/miniconda',
    '**/miniconda/**',
    '**/miniconda3',
    '**/miniconda3/**',
    '**/anaconda',
    '**/anaconda/**',
    '**/anaconda3',
    '**/anaconda3/**',
    '**/miniforge',
    '**/miniforge/**',
    '**/miniforge3',
    '**/miniforge3/**',
    '**/mambaforge',
    '**/mambaforge/**',
    '**/mambaforge3',
    '**/mambaforge3/**',
    '**/*.photoslibrary',
    '**/*.photoslibrary/**',
    '**/*.app',
    '**/*.app/**',
    '**/*.asar',
    '**/*.asar/**',
    '**/tmp',
    '**/tmp/**',
    '**/temp',
    '**/temp/**',
    '**/cache',
    '**/cache/**',
    '**/Caches',
    '**/Caches/**',
    '**/logs',
    '**/logs/**',
    '**/Log',
    '**/Log/**',
    '**/.npm',
    '**/.npm/**',
    '**/.yarn',
    '**/.yarn/**',
    '**/.gradle',
    '**/.gradle/**',
    '**/.cargo',
    '**/.cargo/**',
    '**/.rustup',
    '**/.rustup/**',
    '**/.m2',
    '**/.m2/**',
    '**/.vscode',
    '**/.vscode/**',
    '**/.idea',
    '**/.idea/**',
    '**/.snapshots',
    '**/.snapshots/**',
    '**/.zfs',
    '**/.zfs/**',
    '**/.encrypted',
    '**/.encrypted/**',
    '**/Vault',
    '**/Vault/**',
    '**/mongodb',
    '**/mongodb/**',
    '**/redis',
    '**/redis/**',
    '**/mysql',
    '**/mysql/**',
    '**/postgresql',
    '**/postgresql/**',
    '**/build',
    '**/build/**',
    '**/dist',
    '**/dist/**',
    '**/out',
    '**/out/**',
    '**/target',
    '**/target/**',
    '**/.next',
    '**/.next/**',
    '**/.nuxt',
    '**/.nuxt/**',
    '**/.output',
    '**/.output/**',
    '**/coverage',
    '**/coverage/**',
    '**/obj',
    '**/obj/**',
    '**/bin',
    '**/bin/**',
    '**/release',
    '**/release/**',
    '**/debug',
    '**/debug/**',
    '**/x64',
    '**/x64/**',
    '**/x86',
    '**/x86/**',
    '**/arm64',
    '**/arm64/**',
    '**/ios',
    '**/ios/**',
    '**/android',
    '**/android/**',
    '**/web',
    '**/web/**',
    '**/electron',
    '**/electron/**',
    '**/cmake-build',
    '**/cmake-build/**',
    '**/gradle',
    '**/gradle/**',
    '**/maven',
    '**/maven/**',
    '**/.maven',
    '**/.maven/**',
    '**/vendor',
    '**/vendor/**',
    '**/bower_components',
    '**/bower_components/**',
    '**/.ember-cli',
    '**/.ember-cli/**',
    '**/.meteor',
    '**/.meteor/**',
    '**/.serverless',
    '**/.serverless/**',
    '**/.webpack',
    '**/.webpack/**',
    '**/.cache-loader',
    '**/.cache-loader/**',
    '**/.temp',
    '**/.temp/**',
    '**/.vs',
    '**/.vs/**',
  ];
  if (isWin) {
    extra.push(
      '**/Windows',
      '**/Windows/**',
      '**/Program Files',
      '**/Program Files/**',
      '**/Program Files (x86)',
      '**/Program Files (x86)/**',
      '**/ProgramData',
      '**/ProgramData/**',
      '**/AppData',
      '**/AppData/**'
    );
  }
  if (isMac) {
    extra.push('**/Library', '**/Library/**', '**/Caches', '**/Caches/**', '**/Applications', '**/Applications/**');
  }
  if (!isWin) {
    extra.push('**/opt', '**/opt/**', '**/snap', '**/snap/**', '**/nix', '**/nix/**');
  }
  return base.concat(extra);
}

module.exports = {
  shouldIgnorePath,
  shouldIgnoreDirectoryEntry,
  shouldIgnoreFileEntry,
  buildWatchIgnoredList,
};
