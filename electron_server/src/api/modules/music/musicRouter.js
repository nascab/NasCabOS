const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const { requirePermission } = require('../../middleware/permissionMiddleware');
const musicSourceController = require('./source/musicSourceController');
const musicListController = require('./list/musicListController');
const playListController = require('./playlist/playListController');
const musicFavoriteController = require('./favorite/musicFavoriteController');
const musicCollectionController = require('./collection/musicCollectionController');
const lyricController = require('./lyric/lyricController');
const transcodeController = require('./transcode/transcodeController');
const fileListController = require('../file/list/fileListController');

function createFileViewHandler(sourceType, action) {
  return (req, res) => {
    req.body = { ...(req.body || {}), sourceType };
    return fileListController[action](req, res);
  };
}

router.post('/source/list', authenticateJWT, requireAdmin, musicSourceController.listSources);
router.post('/source/add', authenticateJWT, requireAdmin, musicSourceController.addSource);
router.post('/source/delete', authenticateJWT, requireAdmin, musicSourceController.deleteSource);
router.post('/source/update/:id', authenticateJWT, requireAdmin, musicSourceController.updateSource);
router.post('/source/relocate/:id', authenticateJWT, requireAdmin, musicSourceController.relocateSource);
router.post('/source/scan', authenticateJWT, requireAdmin, musicSourceController.scanSource);

router.post('/list', authenticateJWT, musicListController.list);
router.post('/list/count', authenticateJWT, musicListController.count);
router.post('/album/list', authenticateJWT, musicListController.listAlbums);
router.post('/artist/list', authenticateJWT, musicListController.listArtists);
router.post('/detail/get', authenticateJWT, musicListController.getDetailByPath);
router.post('/history/refresh', authenticateJWT, musicListController.refreshHistory);
router.get('/cover', authenticateJWT, musicListController.getCover);
router.post('/delete', authenticateJWT, musicListController.deleteEntries);

router.get('/transcode', authenticateJWT, requirePermission(['download', 'view'], { from: 'query.path' }), transcodeController.streamMp3);

router.post('/lyric/search', authenticateJWT, lyricController.search);
router.post('/lyric/set', authenticateJWT, lyricController.setLyric);

router.post('/playlist/list', authenticateJWT, playListController.list);
router.post('/playlist/get', authenticateJWT, playListController.get);
router.post('/playlist/create', authenticateJWT, playListController.create);
router.post('/playlist/update', authenticateJWT, playListController.update);
router.post('/playlist/delete', authenticateJWT, playListController.delete);
router.post('/playlist/index/add', authenticateJWT, playListController.addIndexes);
router.post('/playlist/index/remove', authenticateJWT, playListController.removeIndexes);

router.post('/favorite/add', authenticateJWT, musicFavoriteController.add);
router.post('/favorite/remove', authenticateJWT, musicFavoriteController.remove);
router.post('/favorite/batch', authenticateJWT, musicFavoriteController.batch);

router.post('/collection/list', authenticateJWT, musicCollectionController.listCollections);
router.post('/collection/get', authenticateJWT, musicCollectionController.getCollection);
router.post('/collection/create', authenticateJWT, musicCollectionController.createCollection);
router.post('/collection/delete', authenticateJWT, musicCollectionController.deleteCollection);
router.post('/collection/update', authenticateJWT, musicCollectionController.updateCollection);
router.post('/file_view/list', authenticateJWT, createFileViewHandler('music', 'list'));
router.post('/file_view/search', authenticateJWT, createFileViewHandler('music', 'globalSearch'));

module.exports = router;
