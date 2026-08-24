const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { pipeline } = require('stream/promises');

const TEMP_FILE_PREFIX = '.nascab-file-backup-';
const DEFAULT_CHUNK_SIZE = 4 * 1024 * 1024;
const DEFAULT_COPY_CONCURRENCY = 3;
const DEFAULT_MTIME_TOLERANCE_MS = 2000;
const DEFAULT_SMALL_FILE_VERIFY_HASH_MAX_SIZE = 32 * 1024 * 1024;
const MAX_FILE_ERRORS_PER_RUN = 100;
const REPLACE_RETRY_ERROR_CODES = new Set(['EEXIST', 'EPERM', 'EBUSY', 'ENOTEMPTY', 'EACCES']);
const REPLACE_RETRY_DELAYS_MS = [120, 250, 500, 1000, 1500];

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function clampInt(value, min, max, fallback) {
  const num = Math.floor(Number(value));
  if (!Number.isFinite(num)) return fallback;
  return Math.max(min, Math.min(max, num));
}

function toPosixPath(p) {
  return ensureString(p).replace(/\\/g, '/');
}

function globToRegExp(pattern) {
  const normalized = toPosixPath(pattern).trim().replace(/^\/+/, '').replace(/\/+/g, '/');
  if (!normalized) return null;

  let out = '^';
  for (let i = 0; i < normalized.length; i++) {
    const ch = normalized[i];
    const next = normalized[i + 1];
    if (ch === '*') {
      if (next === '*') {
        const after = normalized[i + 2];
        if (after === '/') {
          out += '(?:.*\\/)?';
          i += 2;
        } else {
          out += '.*';
          i += 1;
        }
      } else {
        out += '[^/]*';
      }
    } else if (ch === '?') {
      out += '[^/]';
    } else {
      out += /[|\\{}()[\]^$+?.]/.test(ch) ? `\\${ch}` : ch;
    }
  }
  out += '$';
  return new RegExp(out);
}

function compileExcludeMatchers(patterns) {
  const matchers = [];
  for (const raw of Array.isArray(patterns) ? patterns : []) {
    const value = toPosixPath(raw).trim();
    if (!value) continue;
    const dirOnly = value.endsWith('/');
    const basePattern = dirOnly ? value.slice(0, -1) : value;
    const normalized = basePattern.replace(/^\/+/, '').replace(/\/+/g, '/');
    if (!normalized) continue;
    const regex = globToRegExp(normalized);
    if (!regex) continue;
    matchers.push({
      dirOnly,
      hasSlash: normalized.includes('/'),
      regex,
    });
  }
  return matchers;
}

function shouldExclude(matchers, relativePath, isDirectory) {
  if (!relativePath) return false;
  const rel = toPosixPath(relativePath).replace(/^\/+/, '');
  const base = path.posix.basename(rel);
  for (const matcher of matchers) {
    if (matcher.dirOnly && !isDirectory) continue;
    if (matcher.regex.test(rel)) return true;
    if (!matcher.hasSlash && matcher.regex.test(base)) return true;
    if (isDirectory && matcher.regex.test(`${rel}/`)) return true;
  }
  return false;
}

function safeTimeValue(value) {
  const ts = Number(value);
  if (!Number.isFinite(ts) || ts < 0) return 0;
  return ts;
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, Math.max(0, Number(ms) || 0)));
}

function sameFileFingerprint(sourceStat, targetStat, toleranceMs) {
  if (!sourceStat || !targetStat) return false;
  if (!sourceStat.isFile() || !targetStat.isFile()) return false;
  if (Number(sourceStat.size) !== Number(targetStat.size)) return false;
  return Math.abs(safeTimeValue(sourceStat.mtimeMs) - safeTimeValue(targetStat.mtimeMs)) <= toleranceMs;
}

function isNewerTarget(sourceStat, targetStat, toleranceMs) {
  if (!sourceStat || !targetStat) return false;
  return safeTimeValue(targetStat.mtimeMs) - safeTimeValue(sourceStat.mtimeMs) > toleranceMs;
}

function formatBytes(bytes) {
  const num = Number(bytes) || 0;
  if (num < 1024) return `${num} B`;
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  let value = num / 1024;
  let idx = 0;
  while (value >= 1024 && idx < units.length - 1) {
    value /= 1024;
    idx += 1;
  }
  return `${value >= 100 ? value.toFixed(0) : value >= 10 ? value.toFixed(1) : value.toFixed(2)} ${units[idx]}`;
}

function isPathInsideRoot(rootPath, targetPath) {
  const root = path.resolve(rootPath);
  const target = path.resolve(targetPath);
  const rel = path.relative(root, target);
  if (!rel) return true;
  return rel !== '..' && !rel.startsWith(`..${path.sep}`) && rel !== path.parse(rel).root;
}

function summarizeProgress(progress) {
  const phase = ensureString(progress.phase) || 'running';
  const parts = [phase];
  if (Number.isFinite(progress.filesCopied) || Number.isFinite(progress.totalFiles)) {
    parts.push(`files ${progress.filesCopied || 0}/${progress.totalFiles || 0}`);
  }
  if (Number.isFinite(progress.filesSkipped) && progress.filesSkipped > 0) {
    parts.push(`skipped ${progress.filesSkipped}`);
  }
  if (Number.isFinite(progress.filesRemoved) && progress.filesRemoved > 0) {
    parts.push(`removed ${progress.filesRemoved}`);
  }
  if (Number.isFinite(progress.filesConflictSkipped) && progress.filesConflictSkipped > 0) {
    parts.push(`conflicts ${progress.filesConflictSkipped}`);
  }
  if (Number.isFinite(progress.bytesCopied) || Number.isFinite(progress.totalBytes)) {
    parts.push(`${formatBytes(progress.bytesCopied || 0)}/${formatBytes(progress.totalBytes || 0)}`);
  }
  if (progress.currentRelativePath) {
    parts.push(progress.currentRelativePath);
  }
  return parts.join(' ');
}

async function hashFileSha256(targetPath) {
  const hash = crypto.createHash('sha256');
  const stream = fs.createReadStream(targetPath, { highWaterMark: DEFAULT_CHUNK_SIZE });
  for await (const chunk of stream) {
    hash.update(chunk);
  }
  return hash.digest('hex');
}

class NodeFileBackupEngine {
  constructor({ type, sourceRoot, targetRoot, excludeList, taskConfig, onProgress, shouldStop, logger }) {
    this.type = type === 'sync' ? 'sync' : 'copy';
    this.sourceRoot = path.resolve(sourceRoot);
    this.targetRoot = path.resolve(targetRoot);
    this.excludeMatchers = compileExcludeMatchers(excludeList);
    this.taskConfig = taskConfig && typeof taskConfig === 'object' ? taskConfig : {};
    this.onProgress = typeof onProgress === 'function' ? onProgress : null;
    this.shouldStop = typeof shouldStop === 'function' ? shouldStop : () => false;
    this.logger = logger && typeof logger.warn === 'function' ? logger : console;
    this.copyConcurrency = clampInt(this.taskConfig.copy_concurrency, 1, 8, DEFAULT_COPY_CONCURRENCY);
    this.chunkSize = clampInt(this.taskConfig.chunk_size_bytes, 64 * 1024, 16 * 1024 * 1024, DEFAULT_CHUNK_SIZE);
    this.mtimeToleranceMs = clampInt(this.taskConfig.mtime_tolerance_ms, 0, 10 * 1000, DEFAULT_MTIME_TOLERANCE_MS);
    this.smallFileVerifyHashMaxSize = clampInt(this.taskConfig.verify_hash_max_size, 0, 256 * 1024 * 1024, DEFAULT_SMALL_FILE_VERIFY_HASH_MAX_SIZE);
    this.activeAbortControllers = new Set();
    this.lastProgressTs = 0;
    this.fileErrors = [];
    this.fsyncWarningShown = false;
    this.progressState = {
      phase: 'pending',
      totalFiles: 0,
      totalBytes: 0,
      filesCopied: 0,
      filesSkipped: 0,
      filesRemoved: 0,
      filesConflictSkipped: 0,
      bytesCopied: 0,
      currentRelativePath: '',
    };
  }

  cancel() {
    for (const controller of this.activeAbortControllers) {
      try {
        controller.abort();
      } catch (_) {}
    }
  }

  throwIfStopped() {
    if (this.shouldStop()) {
      const err = new Error('stopped');
      err.code = 'STOPPED';
      throw err;
    }
  }

  pushFileError(relativePath, err) {
    if (this.fileErrors.length >= MAX_FILE_ERRORS_PER_RUN) return;
    const msg = err && err.message ? String(err.message) : String(err);
    this.fileErrors.push({
      path: ensureString(relativePath).trim(),
      error: msg,
    });
  }

  emitProgress(extra = {}, force = false) {
    if (!this.onProgress) return;
    const now = Date.now();
    if (!force && now - this.lastProgressTs < 500) return;
    this.lastProgressTs = now;
    const payload = {
      ...this.progressState,
      ...extra,
      summary: summarizeProgress({ ...this.progressState, ...extra }),
    };
    try {
      this.onProgress(payload);
    } catch (_) {}
  }

  warnFsyncSkipped() {
    if (this.fsyncWarningShown) return;
    this.fsyncWarningShown = true;
  }

  async syncTempFile(tempPath) {
    let handle = null;
    try {
      try {
        handle = await fs.promises.open(tempPath, 'r+');
      } catch (err) {
        if (!err || !['EPERM', 'EACCES'].includes(err.code)) throw err;
        handle = await fs.promises.open(tempPath, 'r');
      }
      try {
        await handle.sync();
      } catch (err) {
        this.warnFsyncSkipped(tempPath, err);
      }
    } catch (err) {
      throw err;
    } finally {
      if (handle) {
        await handle.close().catch(() => null);
      }
    }
  }

  async run() {
    this.progressState.phase = 'scanning';
    this.emitProgress({}, true);

    const sourceManifest = await this.scanTree(this.sourceRoot, { collectBytes: true });
    this.progressState.totalFiles = sourceManifest.files.length;
    this.progressState.totalBytes = sourceManifest.totalBytes;
    this.emitProgress({}, true);

    this.progressState.phase = 'preparing';
    this.emitProgress({}, true);

    await this.ensureDirectories(sourceManifest.directories);

    const targetManifest = this.type === 'sync' ? await this.scanTree(this.targetRoot, { collectBytes: false }) : null;
    const sourceEntryMap = new Map(sourceManifest.entries.map(entry => [entry.relativePath, entry]));
    const extraTargetEntries = targetManifest ? targetManifest.entries.filter(entry => entry.relativePath && !sourceEntryMap.has(entry.relativePath)) : [];

    this.progressState.phase = 'copying';
    this.emitProgress({}, true);

    await this.copyFiles(sourceManifest.files);
    await this.copySymlinks(sourceManifest.symlinks);

    if (this.type === 'sync') {
      await this.assertSourceRootAvailableBeforeSyncDelete();
      this.progressState.phase = 'syncing';
      this.emitProgress({}, true);
      await this.removeExtraEntries(extraTargetEntries);
    }

    this.progressState.phase = 'completed';
    this.progressState.currentRelativePath = '';
    this.emitProgress({}, true);

    return {
      totalFiles: this.progressState.totalFiles,
      totalBytes: this.progressState.totalBytes,
      filesCopied: this.progressState.filesCopied,
      filesSkipped: this.progressState.filesSkipped,
      filesRemoved: this.progressState.filesRemoved,
      filesConflictSkipped: this.progressState.filesConflictSkipped,
      bytesCopied: this.progressState.bytesCopied,
      fileErrors: [...this.fileErrors],
    };
  }

  async assertSourceRootAvailableBeforeSyncDelete() {
    try {
      const stat = await fs.promises.stat(this.sourceRoot);
      if (!stat.isDirectory()) {
        const err = new Error('源文件夹不存在');
        err.code = 'SOURCE_ROOT_NOT_FOUND';
        throw err;
      }
      await fs.promises.access(this.sourceRoot, fs.constants.R_OK | (fs.constants.X_OK || 0));
    } catch (err) {
      if (err && err.code === 'STOPPED') throw err;
      if (err && err.code === 'EACCES') {
        const accessErr = new Error('源文件夹不可访问');
        accessErr.code = 'SOURCE_ROOT_NO_ACCESS';
        throw accessErr;
      }
      if (err && (err.code === 'SOURCE_ROOT_NOT_FOUND' || err.code === 'SOURCE_ROOT_NO_ACCESS')) {
        throw err;
      }
      const notFoundErr = new Error('源文件夹不存在');
      notFoundErr.code = 'SOURCE_ROOT_NOT_FOUND';
      throw notFoundErr;
    }
  }

  async scanTree(rootPath, { collectBytes }) {
    const directories = [];
    const files = [];
    const symlinks = [];
    const entries = [];
    let totalBytes = 0;
    const stack = [{ absPath: rootPath, relativePath: '' }];

    while (stack.length) {
      this.throwIfStopped();
      const current = stack.pop();
      const stat = await fs.promises.lstat(current.absPath);
      const isRoot = !current.relativePath;

      if (!isRoot && shouldExclude(this.excludeMatchers, current.relativePath, stat.isDirectory())) {
        continue;
      }

      if (!isRoot) {
        const item = {
          kind: stat.isDirectory() ? 'directory' : stat.isSymbolicLink() ? 'symlink' : 'file',
          relativePath: current.relativePath,
          absPath: current.absPath,
          stat,
        };
        entries.push(item);
        if (item.kind === 'directory') directories.push(item);
        else if (item.kind === 'symlink') symlinks.push(item);
        else {
          files.push(item);
          if (collectBytes) totalBytes += Number(stat.size) || 0;
        }
      }

      if (!stat.isDirectory()) {
        if (!isRoot) {
          this.emitProgress({
            currentRelativePath: current.relativePath,
          });
        }
        continue;
      }

      const children = await fs.promises.readdir(current.absPath, { withFileTypes: true });
      children.sort((a, b) => a.name.localeCompare(b.name));
      for (let i = children.length - 1; i >= 0; i--) {
        const child = children[i];
        const absPath = path.join(current.absPath, child.name);
        const relativePath = current.relativePath ? path.posix.join(current.relativePath, child.name) : child.name;
        if (shouldExclude(this.excludeMatchers, relativePath, child.isDirectory())) {
          continue;
        }
        stack.push({ absPath, relativePath });
      }
    }

    return { directories, files, symlinks, entries, totalBytes };
  }

  async ensureDirectories(directories) {
    const ordered = [...directories].sort((a, b) => a.relativePath.length - b.relativePath.length);
    for (const entry of ordered) {
      this.throwIfStopped();
      this.progressState.currentRelativePath = entry.relativePath;
      const destPath = path.join(this.targetRoot, entry.relativePath);
      await this.ensureParentPathIsDirectory(destPath);
      const existing = await this.safeLstat(destPath);
      if (existing && !existing.isDirectory()) {
        await fs.promises.rm(destPath, { recursive: true, force: true });
      }
      await fs.promises.mkdir(destPath, { recursive: true });
      await fs.promises.chmod(destPath, entry.stat.mode & 0o777).catch(() => null);
      this.emitProgress();
    }
  }

  async copyFiles(files) {
    await this.runWithConcurrency(files, this.copyConcurrency, async entry => {
      this.throwIfStopped();
      this.progressState.currentRelativePath = entry.relativePath;
      this.emitProgress();

      const destPath = path.join(this.targetRoot, entry.relativePath);
      await this.ensureParentPathIsDirectory(destPath);
      const existing = await this.safeLstat(destPath);

      if (existing && existing.isFile() && sameFileFingerprint(entry.stat, existing, this.mtimeToleranceMs)) {
        this.progressState.filesSkipped += 1;
        this.emitProgress();
        return;
      }

      if (existing && existing.isFile() && isNewerTarget(entry.stat, existing, this.mtimeToleranceMs)) {
        this.progressState.filesConflictSkipped += 1;
        this.emitProgress();
        return;
      }

      if (existing && !existing.isFile()) {
        await fs.promises.rm(destPath, { recursive: true, force: true });
      }

      await this.copyOneFile(entry, destPath);
      this.progressState.filesCopied += 1;
      this.emitProgress({}, true);
    });
  }

  async copySymlinks(entries) {
    for (const entry of entries) {
      try {
        this.throwIfStopped();
        this.progressState.currentRelativePath = entry.relativePath;
        const destPath = path.join(this.targetRoot, entry.relativePath);
        await this.ensureParentPathIsDirectory(destPath);

        const sourceLink = await fs.promises.readlink(entry.absPath);
        const safeTarget = await this.resolveSafeSymlinkTarget(entry, sourceLink);
        if (!safeTarget) {
          this.progressState.filesSkipped += 1;
          this.emitProgress({}, true);
          continue;
        }

        const linkText = path.relative(path.dirname(destPath), safeTarget.destTargetAbsPath) || '.';
        const existing = await this.safeLstat(destPath);
        if (existing) {
          if (existing.isSymbolicLink()) {
            const targetLink = await fs.promises.readlink(destPath).catch(() => null);
            if (targetLink === linkText) {
              this.progressState.filesSkipped += 1;
              this.emitProgress();
              continue;
            }
          }
          await fs.promises.rm(destPath, { recursive: true, force: true });
        }

        const symlinkType = process.platform === 'win32' ? (safeTarget.targetStat.isDirectory() ? 'junction' : 'file') : undefined;
        await fs.promises.symlink(linkText, destPath, symlinkType);
        this.progressState.filesCopied += 1;
        this.emitProgress({}, true);
      } catch (err) {
        if (err && err.code === 'STOPPED') throw err;
        this.pushFileError(entry.relativePath, err);
        this.emitProgress({}, true);
      }
    }
  }

  async resolveSafeSymlinkTarget(entry, sourceLink) {
    const linkText = ensureString(sourceLink);
    if (!linkText) {
      this.logger.warn(`[fileBackup] skip empty symlink: ${entry.relativePath}`);
      return null;
    }

    const resolvedSourceTarget = path.resolve(path.dirname(entry.absPath), linkText);
    if (!isPathInsideRoot(this.sourceRoot, resolvedSourceTarget)) {
      this.logger.warn(`[fileBackup] skip external symlink outside source root: ${entry.relativePath} -> ${linkText}`);
      return null;
    }

    const targetStat = await fs.promises.stat(resolvedSourceTarget).catch(() => null);
    if (!targetStat) {
      this.logger.warn(`[fileBackup] skip broken symlink: ${entry.relativePath} -> ${linkText}`);
      return null;
    }

    const relativeTargetPath = path.relative(this.sourceRoot, resolvedSourceTarget);
    const destTargetAbsPath = path.join(this.targetRoot, relativeTargetPath);
    if (!isPathInsideRoot(this.targetRoot, destTargetAbsPath)) {
      this.logger.warn(`[fileBackup] skip unsafe mapped symlink: ${entry.relativePath} -> ${linkText}`);
      return null;
    }

    return {
      targetStat,
      destTargetAbsPath,
    };
  }

  async removeExtraEntries(entries) {
    const ordered = [...entries].sort((a, b) => b.relativePath.length - a.relativePath.length);
    for (const entry of ordered) {
      try {
        this.throwIfStopped();
        this.progressState.currentRelativePath = entry.relativePath;
        await fs.promises.rm(entry.absPath, { recursive: true, force: true });
        this.progressState.filesRemoved += 1;
        this.emitProgress();
      } catch (err) {
        if (err && err.code === 'STOPPED') throw err;
        this.pushFileError(entry.relativePath, err);
        this.emitProgress();
      }
    }
  }

  async copyOneFile(entry, destPath) {
    const tempPath = path.join(path.dirname(destPath), `${TEMP_FILE_PREFIX}${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.partial`);
    const verifyWithHash = this.smallFileVerifyHashMaxSize > 0 && Number(entry.stat.size) <= this.smallFileVerifyHashMaxSize;
    const sourceHash = verifyWithHash ? crypto.createHash('sha256') : null;
    const controller = new AbortController();
    this.activeAbortControllers.add(controller);

    let copyError = null;
    try {
      const readStream = fs.createReadStream(entry.absPath, { highWaterMark: this.chunkSize });
      const writeStream = fs.createWriteStream(tempPath, { mode: entry.stat.mode & 0o777 });

      readStream.on('data', chunk => {
        if (sourceHash) sourceHash.update(chunk);
        this.progressState.bytesCopied += chunk.length;
        this.emitProgress();
      });

      await pipeline(readStream, writeStream, { signal: controller.signal });
      await this.syncTempFile(tempPath);

      await fs.promises.chmod(tempPath, entry.stat.mode & 0o777).catch(() => null);
      await this.replaceFileAtomic(tempPath, destPath);
      await fs.promises.utimes(destPath, entry.stat.atime, entry.stat.mtime).catch(() => null);

      const finalStat = await fs.promises.stat(destPath);
      if (!sameFileFingerprint(entry.stat, finalStat, this.mtimeToleranceMs)) {
        throw new Error(`verify_failed:${entry.relativePath}`);
      }

      if (sourceHash) {
        const sourceDigest = sourceHash.digest('hex');
        const destDigest = await hashFileSha256(destPath);
        if (sourceDigest !== destDigest) {
          throw new Error(`hash_mismatch:${entry.relativePath}`);
        }
      }
    } catch (err) {
      copyError = err;
      throw err;
    } finally {
      this.activeAbortControllers.delete(controller);
      if (copyError || this.shouldStop()) {
        await fs.promises.rm(tempPath, { force: true }).catch(() => null);
      }
    }
  }

  async replaceFileAtomic(tempPath, destPath) {
    let lastErr = null;
    for (let attempt = 0; attempt <= REPLACE_RETRY_DELAYS_MS.length; attempt++) {
      if (attempt > 0) {
        await sleep(REPLACE_RETRY_DELAYS_MS[attempt - 1]);
      }
      try {
        await fs.promises.rename(tempPath, destPath);
        return;
      } catch (err) {
        lastErr = err;
        if (!err || !REPLACE_RETRY_ERROR_CODES.has(err.code)) {
          throw err;
        }
      }

      await fs.promises.rm(destPath, { recursive: true, force: true }).catch(() => null);

      try {
        await fs.promises.rename(tempPath, destPath);
        return;
      } catch (err) {
        lastErr = err;
        if (!err || !REPLACE_RETRY_ERROR_CODES.has(err.code)) {
          throw err;
        }
      }
    }
    throw lastErr;
  }

  async ensureParentPathIsDirectory(targetPath) {
    await this.ensureDirectoryPath(path.dirname(targetPath));
  }

  async ensureDirectoryPath(dirPath) {
    if (!dirPath) return;
    const existing = await this.safeLstat(dirPath);
    if (existing) {
      if (existing.isDirectory()) return;
      await fs.promises.rm(dirPath, { recursive: true, force: true });
    }

    const parent = path.dirname(dirPath);
    if (parent && parent !== dirPath) {
      await this.ensureDirectoryPath(parent);
    }

    try {
      await fs.promises.mkdir(dirPath);
    } catch (err) {
      if (err && err.code === 'EEXIST') {
        const after = await this.safeLstat(dirPath);
        if (after && after.isDirectory()) return;
      }
      throw err;
    }
  }

  async safeLstat(targetPath) {
    try {
      return await fs.promises.lstat(targetPath);
    } catch (_) {
      return null;
    }
  }

  async runWithConcurrency(items, concurrency, handler) {
    if (!Array.isArray(items) || items.length === 0) return;
    const limit = Math.max(1, Math.min(concurrency || 1, items.length));
    let index = 0;
    let stoppedError = null;

    const worker = async () => {
      while (!stoppedError) {
        try {
          this.throwIfStopped();
        } catch (err) {
          if (err && err.code === 'STOPPED') stoppedError = err;
          return;
        }
        const currentIndex = index;
        index += 1;
        if (currentIndex >= items.length) return;
        try {
          await handler(items[currentIndex], currentIndex);
        } catch (err) {
          if (err && err.code === 'STOPPED') {
            stoppedError = err;
            return;
          }
          const entry = items[currentIndex];
          const rel = entry && entry.relativePath ? entry.relativePath : '';
          this.pushFileError(rel, err);
        }
      }
    };

    await Promise.all(Array.from({ length: limit }, () => worker()));
    if (stoppedError) throw stoppedError;
  }
}

module.exports = {
  NodeFileBackupEngine,
  formatBytes,
  summarizeProgress,
};
