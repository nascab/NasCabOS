const AppearanceService = require('./appearanceService');
const tableConfig = require('../../../../db/table/tableConfig');
const fs = require('fs-extra');
const path = require('path');
const sharp = require('../../../../utils/sharpConfigured');
const sharpUtils = require('../../../../utils/sharpUtils');
const { v4: uuidv4 } = require('uuid');
const config = require('../../../../config/config');

class AppearanceController {
  constructor() {
    this.appearanceService = new AppearanceService();
  }

  /**
   * 获取墙纸列表
   * @param {Object} req - 请求对象
   * @param {Object} res - 响应对象
   */
  async getWallpapers(req, res) {
    try {
      const userId = req.user && req.user.id;
      const wallpapers = await this.appearanceService.getWallpapers();
      const customs = userId ? await this.appearanceService.getUserCustomWallpapers(userId) : [];
      const merged = [...wallpapers, ...customs];

      res.json({
        success: true,
        data: merged,
        message: '获取墙纸列表成功',
        count: merged.length,
      });
    } catch (error) {
      console.error('List wallpapers failed:', error);
      res.status(500).json({
        success: false,
        message: '获取墙纸列表失败',
        error: error.message,
      });
    }
  }

  async getWallpaperPreview(req, res) {
    try {
      const userId = req.user && req.user.id;
      const source = String(req.query?.source ?? 'system').trim().toLowerCase();
      const name = path.basename(String(req.query?.name ?? '').trim());
      const requestedWidth = parseInt(String(req.query?.width ?? '640'), 10);
      const width = Number.isFinite(requestedWidth)
        ? Math.min(Math.max(requestedWidth, 160), 1600)
        : 640;

      if (!name) {
        return res.status(400).json({ success: false, message: '参数错误' });
      }

      const item = await this.appearanceService.resolveWallpaperFile({
        source,
        userId,
        name,
      });
      if (!item) {
        return res.status(404).json({ success: false, message: '墙纸不存在' });
      }

      const buffer = await sharp(item.path, { failOnError: false })
        .rotate()
        .resize({ width, withoutEnlargement: true })
        .webp({ quality: 72 })
        .toBuffer();

      res.setHeader('Cache-Control', 'private, max-age=86400');
      res.type('image/webp');
      return res.send(buffer);
    } catch (error) {
      console.error('Get wallpaper preview failed:', error);
      return res.status(500).json({
        success: false,
        message: '获取墙纸预览失败',
        error: error.message,
      });
    }
  }

  /**
   * 设置用户墙纸（随机或固定）
   * body: { mode: 'random'|'fixed', name?: string }
   */
  async setWallpaper(req, res) {
    try {
      const userId = req.user.id;
      const { mode, name } = req.body || {};

      if (mode !== 'random' && mode !== 'fixed') {
        return res.status(400).json({ success: false, message: '参数错误' });
      }

      if (mode === 'random') {
        const value = JSON.stringify({ type: 'system', filename: '' });
        await tableConfig.setConfigByKey('user_wallpaper', value, userId);
        const wp = await this.appearanceService.getRandomWallpaper();
        return res.json({ success: true, data: wp, message: '墙纸设置为随机' });
      }

      const list = [...(await this.appearanceService.getWallpapers()), ...(await this.appearanceService.getUserCustomWallpapers(userId))];
      const found = list.find(w => w.name === name);
      if (!found) {
        return res.status(400).json({ success: false, message: '墙纸不存在' });
      }
      const isCustom = found && found.source === 'custom';
      const value = JSON.stringify({ type: isCustom ? 'custom' : 'system', filename: found.name });
      await tableConfig.setConfigByKey('user_wallpaper', value, userId);
      return res.json({ success: true, data: found, message: '墙纸设置成功' });
    } catch (error) {
      console.error('Set wallpaper failed:', error);
      res.status(500).json({ success: false, message: '设置墙纸失败', error: error.message });
    }
  }

  async uploadWallpaper(req, res) {
    let stagePath = '';
    try {
      const userId = req.user && req.user.id;
      if (!userId) {
        return res.status(401).json({ success: false, message: '未登录' });
      }

      const file = req.file;
      stagePath = file && file.path ? String(file.path) : '';
      if (!stagePath) {
        return res.status(400).json({ success: false, message: '未选择文件' });
      }

      const uid = String(userId).trim();
      const userDir = path.join(config.getCustomWallpaperPath(), uid);
      await fs.ensureDir(userDir);

      const filename = `wp_${Date.now()}_${uuidv4().replace(/-/g, '')}.webp`;
      const outPath = path.join(userDir, filename);

      const processed = await sharpUtils.transSpcielFormat(stagePath);
      let pipeline;
      if (processed && processed.input && processed.options) {
        pipeline = sharp(processed.input, processed.options);
      } else {
        pipeline = sharp(processed, { failOnError: false });
      }
      await pipeline.rotate().resize({ width: 6000, withoutEnlargement: true }).webp({ quality: 80 }).toFile(outPath);

      await fs.remove(stagePath).catch(() => {});
      stagePath = '';

      const item = {
        name: filename,
        url: `/customWallpaper/${encodeURIComponent(uid)}/${encodeURIComponent(filename)}`,
        previewUrl: `/api/appearance/wallpaperPreview?source=custom&name=${encodeURIComponent(filename)}`,
        type: 'webp',
        source: 'custom',
      };

      return res.json({ success: true, data: item, message: '上传成功' });
    } catch (error) {
      console.error('Upload wallpaper failed:', error);
      if (stagePath) {
        await fs.remove(stagePath).catch(() => {});
      }
      return res.status(500).json({ success: false, message: '上传墙纸失败', error: error.message });
    }
  }

  /**
   * 设置自定义主机名（1–10 字符，空字符串表示清除），写入 config 表 uid=0
   */
  async setCustomHostname(req, res) {
    try {
      const raw = req.body && req.body.customHostname != null ? String(req.body.customHostname) : '';
      const trimmed = raw.trim();
      if (trimmed.length > 10) {
        return res.status(400).json({ success: false, message: '主机名长度不能超过10个字符' });
      }
      if (trimmed.length === 0) {
        await tableConfig.deleteConfigByKey(tableConfig.KEY_CUSTOM_HOSTNAME, 0);
        return res.json({ success: true, data: { customHostname: null }, message: '已清除自定义主机名' });
      }
      const ok = await tableConfig.setConfigByKey(tableConfig.KEY_CUSTOM_HOSTNAME, trimmed, 0);
      if (!ok) {
        return res.status(500).json({ success: false, message: '保存失败' });
      }
      return res.json({ success: true, data: { customHostname: trimmed }, message: '保存成功' });
    } catch (error) {
      console.error('Set custom hostname failed:', error);
      return res.status(500).json({ success: false, message: '保存失败', error: error.message });
    }
  }

  async deleteWallpaper(req, res) {
    try {
      const userId = req.user && req.user.id;
      if (!userId) {
        return res.status(401).json({ success: false, message: '未登录' });
      }

      const nameRaw = (req.body && (req.body.name ?? req.body.filename)) ?? '';
      const name = path.basename(String(nameRaw).trim());
      if (!name) {
        return res.status(400).json({ success: false, message: '参数错误' });
      }

      const uid = String(userId).trim();
      const userDir = path.join(config.getCustomWallpaperPath(), uid);
      const filePath = path.join(userDir, name);
      const resolvedFile = path.resolve(filePath);
      const resolvedDir = path.resolve(userDir);
      const prefix = resolvedDir.endsWith(path.sep) ? resolvedDir : resolvedDir + path.sep;
      if (!(resolvedFile === resolvedDir || resolvedFile.startsWith(prefix))) {
        return res.status(400).json({ success: false, message: '参数错误' });
      }

      if (!(await fs.pathExists(resolvedFile))) {
        return res.status(404).json({ success: false, message: '文件不存在' });
      }

      await fs.remove(resolvedFile);

      let fallback = null;
      const cfg = await tableConfig.getConfigByKey('user_wallpaper', userId);
      if (cfg && cfg.trim()) {
        try {
          const pref = JSON.parse(cfg);
          if (pref && pref.type === 'custom' && String(pref.filename || '') === name) {
            const value = JSON.stringify({ type: 'system', filename: '' });
            await tableConfig.setConfigByKey('user_wallpaper', value, userId);
            fallback = await this.appearanceService.getRandomWallpaper();
          }
        } catch (_) {}
      }

      return res.json({ success: true, data: { deleted: true, fallback }, message: '删除成功' });
    } catch (error) {
      console.error('Delete wallpaper failed:', error);
      return res.status(500).json({ success: false, message: '删除墙纸失败', error: error.message });
    }
  }
}

module.exports = AppearanceController;
