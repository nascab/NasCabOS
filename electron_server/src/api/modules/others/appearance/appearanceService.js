const fs = require('fs');
const path = require('path');
const config = require('../../../../config/config');

class AppearanceService {
  constructor() {
    this.wallpaperPath = path.join(config.appRootPath, 'web', 'wallpaper');
    this.customWallpaperRoot = config.getCustomWallpaperPath();
  }

  _buildPreviewUrl({ source, name }) {
    const safeSource = String(source ?? '').trim();
    const safeName = path.basename(String(name ?? '').trim());
    if (!safeSource || !safeName) return '';
    return `/api/appearance/wallpaperPreview?source=${encodeURIComponent(safeSource)}&name=${encodeURIComponent(safeName)}`;
  }

  _getImageExtensions() {
    return ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];
  }

  _getUserCustomDir(userId) {
    const uid = String(userId ?? '').trim();
    if (!uid) return '';
    return path.join(this.customWallpaperRoot, uid);
  }

  async resolveWallpaperFile({ source, userId, name }) {
    const safeSource = String(source ?? '').trim().toLowerCase();
    const safeName = path.basename(String(name ?? '').trim());
    if (!safeName) return null;

    let baseDir = '';
    if (safeSource === 'system') {
      baseDir = this.wallpaperPath;
    } else if (safeSource === 'custom') {
      baseDir = this._getUserCustomDir(userId);
    } else {
      return null;
    }

    if (!baseDir) return null;

    const fullPath = path.join(baseDir, safeName);
    try {
      const stats = await fs.promises.stat(fullPath);
      if (!stats.isFile()) return null;
      return {
        name: safeName,
        path: fullPath,
        source: safeSource,
      };
    } catch (_) {
      return null;
    }
  }

  async _listWallpapersInDir(dirPath, { urlPrefix, source }) {
    try {
      if (!dirPath || !fs.existsSync(dirPath)) return [];

      const files = await fs.promises.readdir(dirPath);
      const imageExtensions = this._getImageExtensions();
      const wallpaperFiles = files.filter(file => imageExtensions.includes(path.extname(file).toLowerCase()));

      const items = await Promise.all(
        wallpaperFiles.map(async file => {
          const filePath = path.join(dirPath, file);
          const stats = await fs.promises.stat(filePath);
          return {
            name: file,
            url: `${urlPrefix}/${encodeURIComponent(file)}`,
            previewUrl: this._buildPreviewUrl({ source, name: file }),
            type: path.extname(file).toLowerCase().replace('.', ''),
            source,
            mtimeMs: stats.mtimeMs,
          };
        })
      );

      return items;
    } catch (error) {
      console.error('List wallpapers failed:', error);
      return [];
    }
  }

  /**
   * 获取一张随机系统墙纸
   * @returns {Promise<Object>} 墙纸信息
   */
  async getRandomWallpaper() {
    try {
      const wallpapers = await this.getWallpapers();
      if (wallpapers.length === 0) {
        return null;
      }
      const randomIndex = Math.floor(Math.random() * wallpapers.length);
      return wallpapers[randomIndex];
    } catch (error) {
      console.error('Random wallpaper failed:', error);
      return null;
    }
  }

  /**
   * 获取墙纸列表
   * @returns {Promise<Array>} 墙纸列表
   */
  async getWallpapers() {
    try {
      const wallpapers = await this._listWallpapersInDir(this.wallpaperPath, {
        urlPrefix: '/wallpaper',
        source: 'system',
      });

      // 按文件名排序（数字优先，然后字母）
      wallpapers.sort((a, b) => {
        const aNum = parseInt(a.name.match(/\d+/)?.[0] || '9999');
        const bNum = parseInt(b.name.match(/\d+/)?.[0] || '9999');

        if (aNum !== bNum) {
          return aNum - bNum;
        }

        return a.name.localeCompare(b.name);
      });

      return wallpapers;
    } catch (error) {
      console.error('List wallpapers failed:', error);
      return [];
    }
  }

  async getUserCustomWallpapers(userId) {
    const uid = String(userId ?? '').trim();
    const userDir = this._getUserCustomDir(uid);
    if (!userDir) return [];

    const items = await this._listWallpapersInDir(userDir, {
      urlPrefix: `/customWallpaper/${encodeURIComponent(uid)}`,
      source: 'custom',
    });

    items.sort((a, b) => (b.mtimeMs || 0) - (a.mtimeMs || 0));

    return items.map(it => {
      const { mtimeMs, ...rest } = it;
      return rest;
    });
  }

  async getUserCustomWallpaperByName(userId, filename) {
    const uid = String(userId ?? '').trim();
    const name = String(filename ?? '').trim();
    if (!uid || !name) return null;

    const base = path.basename(name);
    if (!base) return null;

    const userDir = this._getUserCustomDir(uid);
    if (!userDir) return null;

    const fullPath = path.join(userDir, base);
    try {
      const stats = await fs.promises.stat(fullPath);
      if (!stats.isFile()) return null;
      return {
        name: base,
        url: `/customWallpaper/${encodeURIComponent(uid)}/${encodeURIComponent(base)}`,
        previewUrl: this._buildPreviewUrl({ source: 'custom', name: base }),
        type: path.extname(base).toLowerCase().replace('.', ''),
        source: 'custom',
      };
    } catch (_) {
      return null;
    }
  }
}

module.exports = AppearanceService;
