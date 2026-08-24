const express = require('express');
const { authenticateJWT } = require('../../middleware/authMiddleware');
const { requirePermission } = require('../../middleware/permissionMiddleware');
const editorController = require('./editorController');

const router = express.Router();

router.post('/open', authenticateJWT, requirePermission(['view'], { from: 'body.path' }), editorController.open);
router.post('/save', authenticateJWT, requirePermission(['update'], { from: 'body.path' }), editorController.save);
router.post('/config/get', authenticateJWT, editorController.getConfig);
router.post('/config/set', authenticateJWT, editorController.setConfig);
router.post('/config/reset', authenticateJWT, editorController.resetConfig);

module.exports = router;
