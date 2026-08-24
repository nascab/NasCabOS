const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

class FileUtil {
  /**
   * Get unique ID for a file based on path, size, and mtime
   */
  static async getFileHash(filePath) {
    try {
      const stat = await fs.promises.stat(filePath);
      const str = `${path.basename(filePath)}_${stat.size}_${stat.birthtimeMs}`;
      return crypto.createHash('md5').update(str).digest('hex');
    } catch (e) {
      return null;
    }
  }
  static getErrorMessageKey(err) {
    if (!err || !err.code) return err && err.message ? err.message : 'file.UNKNOWN_ERROR';
    switch (err.code) {
      case 'EPERM':
      case 'EACCES':
        return 'file.NO_WRITE_PERMISSION';
      case 'EROFS':
        return 'file.FOLDER_IS_ONLY_READ';
      case 'EEXIST':
        return 'file.FILE_EXISTS';
      case 'ENOENT':
        return 'file.FOLDER_NOT_EXIST';
      case 'EBUSY':
        return 'file.FILE_BUSY';
      default:
        return err.message || 'file.UNKNOWN_ERROR';
    }
  }
  static isHideFile(filename) {
    if (!filename) return false;
    return filename.startsWith('.');
  }
  static temporaryFileSuffixes = ['.tmp', '.bc!', '.td', '.qkdownloading', '.xltd', '.downloading'];
  static isTemporaryOrDownloadingFile(filename) {
    if (!filename) return false;
    const lower = String(filename).toLowerCase();
    return FileUtil.temporaryFileSuffixes.some(suffix => lower.endsWith(suffix));
  }
  static shouldSkipIndexingFilename(filename) {
    if (!filename) return false;
    return FileUtil.isSystemFile(filename) || FileUtil.isHideFile(filename) || FileUtil.isTemporaryOrDownloadingFile(filename);
  }
  static watchIgnoredList = [
    '**/.git',
    '**/.DS_Store', // macOS
    '**/Thumbs.db', // Windows
    '**/desktop.ini', // Windows
    '**/.localized', // macOS
    '**/._*', // macOS resource fork
    '**/$RECYCLE.BIN', // Windows
    '**/System Volume Information', // Windows
    '**/@eaDir', //群晖临时文件
  ];
  static systemFiles = [
    '.DS_Store', // macOS
    'Thumbs.db', // Windows
    'desktop.ini', // Windows
    '.localized', // macOS
    '._*', // macOS resource fork
    '$RECYCLE.BIN', // Windows
    'System Volume Information', // Windows
    '@eaDir' //群晖临时文件
  ];
  static isSystemFile(filename) {
    if (!filename) return false;

    // Check exact matches
    if (FileUtil.systemFiles.includes(filename)) return true;
    // Check patterns
    if (filename.startsWith('._')) return true;
    return false;
  }

  // 判断是否为系统关键目录
  static isProtectedPath(filePath) {
    if (!filePath || typeof filePath !== 'string') return false;
    let normalized = path.normalize(filePath);

    // Remove trailing separator unless it is root
    if (normalized.length > 1 && normalized.endsWith(path.sep)) {
      normalized = normalized.slice(0, -1);
    }

    const platform = process.platform;

    if (platform === 'win32') {
      // Windows: Drive letters (e.g. C:, D:)
      // Case insensitive
      return /^[a-zA-Z]:[\\/]*$/.test(normalized);
    } else if (platform === 'darwin') {
      // macOS
      const protectedPaths = [
        '/System',
        '/Applications',
        '/bin',
        '/dev',
        '/home',
        '/opt',
        '/Users',
        '/sbin',
        '/usr',
        '/Library',
        '/private',
        '/var',
        '/tmp',
        '/cores',
        '/etc',
        '/Volumes',
        '/Volumes/Macintosh HD',
      ];
      // Root
      if (normalized === '/') return true;

      // Case insensitive check (macOS default is case insensitive)
      const lower = normalized.toLowerCase();
      return protectedPaths.some(p => p.toLowerCase() === lower);
    } else if (platform === 'linux') {
      // Linux
      const protectedPaths = ['/proc', '/sys', '/dev', '/run', '/tmp', '/root', '/lost+found', '/etc'];
      // Root
      if (normalized === '/') return true;

      // Case sensitive check
      return protectedPaths.includes(normalized);
    }
    return false;
  }
}

module.exports = FileUtil;
