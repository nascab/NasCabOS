const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const { requirePermission } = require('../../middleware/permissionMiddleware');
const photoSourceController = require('./source/photoSourceController');
const photoConfigController = require('./config/photoConfigController');
const photoTimeLineController = require('./timeline/photoTimeLineController');
const photoAlbumController = require('./album/photoAlbumController');
const photoCollectionController = require('./collection/photoCollectionController');
const photoSmartAlbumController = require('./smartAlbum/photoSmartAlbumController');
const photoPropertiesController = require('./properties/photoPropertiesController');
const faceController = require('./face/faceController');
const placesController = require('./places/placesController');
const similarController = require('./similar/similarController');
const gpsSupplementController = require('./gps_add/gpsSupplementController');
const appAiController = require('./app_ai/appAiController');
const fileListController = require('../file/list/fileListController');

function createFileViewHandler(sourceType, action) {
  return (req, res) => {
    req.body = { ...(req.body || {}), sourceType };
    return fileListController[action](req, res);
  };
}
// 来源设置
router.post('/source/list', authenticateJWT, requireAdmin, photoSourceController.listSources);
router.post('/source/add', authenticateJWT, requireAdmin, photoSourceController.addSource);
router.post('/source/delete', authenticateJWT, requireAdmin, photoSourceController.deleteSource);
router.post('/source/update/:id', authenticateJWT, requireAdmin, photoSourceController.updateSource);
router.post('/source/relocate/:id', authenticateJWT, requireAdmin, photoSourceController.relocateSource);
router.post('/source/scan', authenticateJWT, requireAdmin, photoSourceController.scanSource);
router.post('/source/regenerate_thumbnails', authenticateJWT, requireAdmin, photoSourceController.regenerateThumbnails);
//是否启用ocr
router.post('/setAiOcrEnable', authenticateJWT, requireAdmin, photoConfigController.setAiOcrEnable);
router.post('/setAiPetEnable', authenticateJWT, requireAdmin, photoConfigController.setAiPetEnable);
router.post('/setAiFaceEnable', authenticateJWT, requireAdmin, photoConfigController.setAiFaceEnable);
router.post('/setAiFaceMinShowCount', authenticateJWT, requireAdmin, photoConfigController.setAiFaceMinShowCount);
router.post('/setAiPlaceEnable', authenticateJWT, requireAdmin, photoConfigController.setAiPlaceEnable);
router.post('/setAiSimilarEnable', authenticateJWT, requireAdmin, photoConfigController.setAiSimilarEnable);
router.post('/setAiGpuPrefer', authenticateJWT, requireAdmin, photoConfigController.setAiGpuPrefer);
router.post('/getAiConfig', authenticateJWT, requireAdmin, photoConfigController.getAiConfig);
router.post('/getPreviewConfig', authenticateJWT, photoConfigController.getPreviewConfig);
router.post('/setPreviewSize', authenticateJWT, photoConfigController.setPreviewSize);
 
// TimeLine
router.post('/timeline/count', authenticateJWT, photoTimeLineController.getPhotoTotalCount);
router.post('/timeline/dates', authenticateJWT, photoTimeLineController.getTimelineDateList);
router.post('/timeline/photos', authenticateJWT, photoTimeLineController.getTimelinePhotoList);
router.post('/timeline/years', authenticateJWT, photoTimeLineController.getTimelineYearList);
// places
router.post('/place/list', authenticateJWT, placesController.listPlaces);
router.post('/place/status/set', authenticateJWT, requireAdmin, placesController.setPlaceStatus);
router.post('/place/reset', authenticateJWT, requireAdmin, placesController.resetPlaces);

// map
router.post('/getBoundsPhoto', authenticateJWT, photoTimeLineController.getBoundsPhoto);

// Properties
router.post('/properties/get', authenticateJWT, requirePermission(['view'], { from: 'body.path' }), photoPropertiesController.get);

// Favorite
router.post('/favorite/toggle', authenticateJWT, photoTimeLineController.toggleFavorite);
router.post('/favorite/batch', authenticateJWT, photoTimeLineController.batchFavorite);
// 获取相册下载的所需信息
router.post('/download/info', authenticateJWT, photoAlbumController.getDownloadInfo);

// Album
router.post('/album/list', authenticateJWT, photoAlbumController.listAlbums);
router.post('/album/overview', authenticateJWT, photoAlbumController.getAlbumOverview);
router.post('/album/get', authenticateJWT, photoAlbumController.getAlbum);
router.post('/album/create', authenticateJWT, photoAlbumController.createAlbum);
router.post('/album/delete', authenticateJWT, photoAlbumController.deleteAlbum);
router.post('/album/update', authenticateJWT, photoAlbumController.updateAlbum);
router.post('/album/index/add', authenticateJWT, photoAlbumController.addAlbumIndexes);
router.post('/album/index/remove', authenticateJWT, photoAlbumController.removeAlbumIndexes);
router.post('/album/cover/set', authenticateJWT, photoAlbumController.setAlbumCover);
router.get('/album/download/:filename?', authenticateJWT, photoAlbumController.downloadAlbumPhotos);
// Collection
router.post('/collection/list', authenticateJWT, photoCollectionController.listCollections);
router.post('/collection/get', authenticateJWT, photoCollectionController.getCollection);
router.post('/collection/create', authenticateJWT, photoCollectionController.createCollection);
router.post('/collection/delete', authenticateJWT, photoCollectionController.deleteCollection);
router.post('/collection/update', authenticateJWT, photoCollectionController.updateCollection);

// Smart Album
router.post('/smart_album/list', authenticateJWT, photoSmartAlbumController.listSmartAlbums);
router.post('/smart_album/get', authenticateJWT, photoSmartAlbumController.getSmartAlbum);
router.post('/smart_album/create', authenticateJWT, photoSmartAlbumController.createSmartAlbum);
router.post('/smart_album/update', authenticateJWT, photoSmartAlbumController.updateSmartAlbum);
router.post('/smart_album/delete', authenticateJWT, photoSmartAlbumController.deleteSmartAlbum);

// Trash
router.post('/trash/add', authenticateJWT, photoTimeLineController.batchTrash);
router.post('/trash/list', authenticateJWT, photoTimeLineController.getTrashPhotoList);
router.post('/trash/restore', authenticateJWT, photoTimeLineController.restoreFromTrash);
router.post('/trash/delete', authenticateJWT, photoTimeLineController.deleteFromTrash);
router.post('/trash/empty', authenticateJWT, photoTimeLineController.emptyTrash);

// Face
router.post('/face/list', authenticateJWT, faceController.listFaces);
router.get('/face/download/:filename?', authenticateJWT, faceController.downloadFacePhotos);
router.post('/face/reset', authenticateJWT, requireAdmin, faceController.resetFaces);
router.post('/face/cover/set', authenticateJWT, requireAdmin, faceController.setFaceCover);
router.post('/face/name/update', authenticateJWT, requireAdmin, faceController.updateFaceName);
router.post('/face/merge', authenticateJWT, requireAdmin, faceController.mergeFaces);
router.post('/face/status/set', authenticateJWT, requireAdmin, faceController.setFaceStatus);
router.post('/face/photo/list', authenticateJWT, faceController.listPhotoFaces);
router.post('/face/photo/remove', authenticateJWT, requireAdmin, faceController.removePhotoFromFace);
router.post('/face/photo/move', authenticateJWT, requireAdmin, faceController.movePhotoToFace);
router.get('/face/image', authenticateJWT, faceController.faceImageGet);

// Similar
router.post('/similar/list', authenticateJWT, requireAdmin, similarController.listSimilarGroups);
router.post('/similar/delete', authenticateJWT, requireAdmin, similarController.batchDelete);
router.post('/similar/reset', authenticateJWT, requireAdmin, similarController.reset);

// GPS supplement
router.post('/gps_add/status', authenticateJWT, requireAdmin, gpsSupplementController.status);
router.post('/gps_add/start_scan', authenticateJWT, requireAdmin, gpsSupplementController.startScan);
router.post('/gps_add/apply', authenticateJWT, requireAdmin, gpsSupplementController.apply);
router.post('/gps_add/skip', authenticateJWT, requireAdmin, gpsSupplementController.skip);
router.post('/gps_add/reset', authenticateJWT, requireAdmin, gpsSupplementController.reset);

// App AI
router.post('/app_ai/overview', authenticateJWT, appAiController.overview);
router.post('/file_view/list', authenticateJWT, createFileViewHandler('photo', 'list'));
router.post('/file_view/search', authenticateJWT, createFileViewHandler('photo', 'globalSearch'));

module.exports = router;
