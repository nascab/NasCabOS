const express = require('express');
const router = express.Router();
const Logger = require('../../../utils/logger');
const { authenticateJWT } = require('../../middleware/authMiddleware');
const { requireQuickShareAccess } = require('../../middleware/quickShareAuthMiddleware');
const { requirePermission } = require('../../middleware/permissionMiddleware');
const quickShareController = require('./quickShareController');
const quickSharePublicController = require('./quickSharePublicController');

const getShareByToken = async (req, token) => {
  const knex = req.dbMain;
  const routePath = (req.originalUrl || req.url || '').split('?')[0];
  if (!knex) {
    Logger.warn('[quickShare] getShareByToken: no req.dbMain (main DB not attached)', {
      routePath,
      qt: token || '',
    });
    return null;
  }
  const row = await knex('quick_share').where({ token }).first();
  if (!row) {
    Logger.warn('[quickShare] getShareByToken: no row in quick_share', {
      routePath,
      qt: token || '',
    });
  } else {
    Logger.info('[quickShare] getShareByToken: ok', {
      routePath,
      qt: token || '',
      id: row.id,
      hasPath: !!(row.path && String(row.path).trim()),
    });
  }
  return row;
};

router.get('/list', authenticateJWT, (req, res) => quickShareController.list(req, res));
router.post('/create', authenticateJWT, requirePermission('share', { from: 'body.path' }), (req, res) => quickShareController.create(req, res));
router.post('/delete', authenticateJWT, (req, res) => quickShareController.remove(req, res));
router.post('/cleanExpired', authenticateJWT, (req, res) => quickShareController.cleanExpired(req, res));

router.post('/public/auth', express.raw({ type: 'application/octet-stream', limit: '64kb' }), (req, res) => quickSharePublicController.auth(req, res));
router.get('/public/list', requireQuickShareAccess({ getShareByToken }), (req, res) => quickSharePublicController.list(req, res));
router.get('/public/tiny', requireQuickShareAccess({ getShareByToken }), (req, res) => quickSharePublicController.tiny(req, res));
router.get('/public/raw', requireQuickShareAccess({ getShareByToken }), (req, res) => quickSharePublicController.raw(req, res));
router.get('/public/download', requireQuickShareAccess({ getShareByToken }), (req, res) => quickSharePublicController.download(req, res));

module.exports = router;
