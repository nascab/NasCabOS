const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../../middleware/authMiddleware');
const photoMapController = require('./photoMapController');

router.get('/tile', authenticateJWT, photoMapController.tile);
router.get('/getZoom', authenticateJWT, photoMapController.getZoom);
router.post('/getZoom', authenticateJWT, photoMapController.getZoom);
router.post('/getTileServerList', authenticateJWT, photoMapController.getTileServerList);
router.post('/setTileServer', authenticateJWT, requireAdmin, photoMapController.setTileServer);
router.post('/addTileServer', authenticateJWT, requireAdmin, photoMapController.addTileServer);
router.post('/deleteTileServer', authenticateJWT, requireAdmin, photoMapController.deleteTileServer);
router.post('/getLocationStr', authenticateJWT, photoMapController.getLocationStr);
router.post('/getAlbumPhotoForMap', authenticateJWT, photoMapController.getAlbumPhotoForMap);
router.post('/getBoundsPhoto', authenticateJWT, photoMapController.getBoundsPhoto);

module.exports = router;
