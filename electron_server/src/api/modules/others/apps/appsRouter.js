const express = require('express');
const AppsController = require('./appsController');
const { authenticateJWT } = require('../../../middleware/authMiddleware');

const router = express.Router();
const appsController = new AppsController();

router.get('/getApps', authenticateJWT, appsController.getApps);

router.post('/setHideApps', authenticateJWT, appsController.setHideApps);

router.post('/hideApp', authenticateJWT, appsController.hideApp);

router.post('/unhideApp', authenticateJWT, appsController.unhideApp);

router.post('/setAppsOrder', authenticateJWT, appsController.setAppsOrder);

module.exports = router;
