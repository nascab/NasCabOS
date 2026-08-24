const express = require('express');
const router = express.Router();
const { authenticateJWT } = require('../../middleware/authMiddleware');
const homeController = require('./homeController');

router.get('/config', authenticateJWT, (req, res) => homeController.config(req, res));

module.exports = router;
