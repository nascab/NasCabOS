const express = require('express');
const AppearanceController = require('./appearanceController');
const { authenticateJWT, requireSuperAdmin } = require('../../../middleware/authMiddleware');
const multer = require('multer');
const path = require('path');
const fs = require('fs-extra');
const config = require('../../../../config/config');

const router = express.Router();
const appearanceController = new AppearanceController();

router.get('/wallpapers', authenticateJWT, appearanceController.getWallpapers.bind(appearanceController));
router.get('/wallpaperPreview', authenticateJWT, appearanceController.getWallpaperPreview.bind(appearanceController));
router.post('/setWallpaper', authenticateJWT, appearanceController.setWallpaper.bind(appearanceController));
router.post(
  '/uploadWallpaper',
  authenticateJWT,
  async (req, res, next) => {
    try {
      const stageDir = path.join(config.getUploadTempDir(), 'custom_wallpaper_uploads_stage');
      await fs.ensureDir(stageDir);
      const uploader = multer({
        storage: multer.diskStorage({
          destination: function (_req, _file, cb) {
            cb(null, stageDir);
          },
          filename: function (_req, file, cb) {
            const ext = path.extname(file.originalname || '').toLowerCase();
            cb(null, `${Date.now()}_${Math.round(Math.random() * 1e9)}${ext || '.img'}`);
          },
        }),
        limits: { fileSize: 50 * 1024 * 1024 },
      }).single('file');

      uploader(req, res, err => {
        if (err) {
          return res.status(400).json({ success: false, message: '上传失败', error: err.message });
        }
        next();
      });
    } catch (e) {
      return res.status(500).json({ success: false, message: '上传失败', error: e.message });
    }
  },
  appearanceController.uploadWallpaper.bind(appearanceController)
);
router.post('/deleteWallpaper', authenticateJWT, appearanceController.deleteWallpaper.bind(appearanceController));
router.post(
  '/setCustomHostname',
  authenticateJWT,
  requireSuperAdmin,
  appearanceController.setCustomHostname.bind(appearanceController)
);

module.exports = router;
