const express = require('express');
const router = express.Router();
const { authenticateJWT } = require('../../../middleware/authMiddleware');
const hwController = require('./hwController');

//获取硬件指标
router.get('/metrics', authenticateJWT, (req, res) => hwController.getMetrics(req, res));

module.exports = router;
