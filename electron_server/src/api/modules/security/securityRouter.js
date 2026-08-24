const express = require('express');
const { authenticateJWT, requireSuperAdmin } = require('../../middleware/authMiddleware');
const securityController = require('./securityController');

const router = express.Router();

router.get('/config', authenticateJWT, requireSuperAdmin, (req, res) => securityController.getConfig(req, res));
router.post('/config', authenticateJWT, requireSuperAdmin, (req, res) => securityController.setConfig(req, res));

router.get('/ipBlacklist', authenticateJWT, requireSuperAdmin, (req, res) => securityController.listIpBlacklist(req, res));
router.post('/ipBlacklist/delete', authenticateJWT, requireSuperAdmin, (req, res) => securityController.deleteIpBlacklist(req, res));
router.post('/ipBlacklist/clear', authenticateJWT, requireSuperAdmin, (req, res) => securityController.clearIpBlacklist(req, res));

module.exports = router;
