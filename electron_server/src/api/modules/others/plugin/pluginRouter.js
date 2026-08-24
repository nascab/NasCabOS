const express = require('express');
const router = express.Router();
const { authenticateJWT } = require('../../../middleware/authMiddleware');
const pluginController = require('./pluginController');

router.post('/mountLibsStatus', authenticateJWT, (req, res) => pluginController.getMountLibsStatus(req, res));

module.exports = router;
