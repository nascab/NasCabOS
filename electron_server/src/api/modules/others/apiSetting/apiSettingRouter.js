const express = require('express');
const { authenticateJWT, requireSuperAdmin, requireAdmin } = require('../../../middleware/authMiddleware');
const apiSettingController = require('./apiSettingController');

const router = express.Router();

router.get('/loginConfig', (req, res) => apiSettingController.loginConfig(req, res));
router.get('/get', authenticateJWT, requireSuperAdmin, (req, res) => apiSettingController.get(req, res));
router.post('/save', authenticateJWT, requireSuperAdmin, (req, res) => apiSettingController.save(req, res));
router.post('/saveWelcome', authenticateJWT, requireSuperAdmin, (req, res) => apiSettingController.saveWelcome(req, res));
router.post('/restart', authenticateJWT, requireAdmin, (req, res) => apiSettingController.restartService(req, res));

module.exports = router;
