const express = require('express');
const router = express.Router();
const { authenticateJWT, requireAdmin } = require('../../middleware/authMiddleware');
const videoSourceController = require('./source/videoSourceController');
const videoHomeController = require('./home/videoHomeController');
const videoDetailController = require('./detail/detailController');
const videoListController = require('./list/videoListController');
const videoFavoriteController = require('./favorite/videoFavoriteController');
const videoCollectionController = require('./collection/videoCollectionController');
const videoSmartAlbumController = require('./smartAlbum/videoSmartAlbumController');
const videoAlbumController = require('./album/videoAlbumController');
const videoConfigController = require('./config/videoConfigController');
const videoTmdbController = require('./tmdb/videoTmdbController');
const videoScrapeController = require('./scrape/videoScrapeController');
const fileListController = require('../file/list/fileListController');

function createFileViewHandler(sourceType, action) {
  return (req, res) => {
    req.body = { ...(req.body || {}), sourceType };
    return fileListController[action](req, res);
  };
}

router.post('/source/list', authenticateJWT, requireAdmin, videoSourceController.listSources);
router.post('/source/add', authenticateJWT, requireAdmin, videoSourceController.addSource);
router.post('/source/delete', authenticateJWT, requireAdmin, videoSourceController.deleteSource);
router.post('/source/update/:id', authenticateJWT, requireAdmin, videoSourceController.updateSource);
router.post('/source/media_type/:id', authenticateJWT, requireAdmin, videoSourceController.updateMediaType);
router.post('/source/match_nfo/:id', authenticateJWT, requireAdmin, videoSourceController.updateMatchNfo);
router.post('/source/relocate/:id', authenticateJWT, requireAdmin, videoSourceController.relocateSource);
router.post('/source/scan', authenticateJWT, requireAdmin, videoSourceController.scanSource);
router.post('/source/scan_index', authenticateJWT, requireAdmin, videoSourceController.scanIndex);

router.post('/getTmdbConfig', authenticateJWT, requireAdmin, videoConfigController.getTmdbConfig);
router.post('/setTmdbConfig', authenticateJWT, requireAdmin, videoConfigController.setTmdbConfig);
router.post('/getTranscodeConfig', authenticateJWT, requireAdmin, videoConfigController.getTranscodeConfig);
router.post('/setTranscodeConfig', authenticateJWT, requireAdmin, videoConfigController.setTranscodeConfig);
router.post('/getSubtitleConfig', authenticateJWT, requireAdmin, videoConfigController.getSubtitleConfig);
router.post('/setSubtitleConfig', authenticateJWT, requireAdmin, videoConfigController.setSubtitleConfig);

router.post('/tmdb/search', authenticateJWT, videoTmdbController.search);
router.post('/scrape/start', authenticateJWT, requireAdmin, videoScrapeController.start);
router.post('/scrape/cleanup', authenticateJWT, requireAdmin, videoScrapeController.cleanup);

router.post('/home/data', authenticateJWT, videoHomeController.getHomeData);

router.post('/list', authenticateJWT, videoListController.list);
router.post('/list/count', authenticateJWT, videoListController.count);
router.post('/history/list', authenticateJWT, videoListController.historyList);
router.post('/history/clear', authenticateJWT, videoListController.clearHistory);

router.post('/favorite/add', authenticateJWT, videoFavoriteController.add);
router.post('/favorite/remove', authenticateJWT, videoFavoriteController.remove);

router.post('/collection/list', authenticateJWT, videoCollectionController.listCollections);
router.post('/collection/get', authenticateJWT, videoCollectionController.getCollection);
router.post('/collection/create', authenticateJWT, videoCollectionController.createCollection);
router.post('/collection/delete', authenticateJWT, videoCollectionController.deleteCollection);
router.post('/collection/update', authenticateJWT, videoCollectionController.updateCollection);

router.post('/smart_album/list', authenticateJWT, videoSmartAlbumController.listSmartAlbums);
router.post('/smart_album/get', authenticateJWT, videoSmartAlbumController.getSmartAlbum);
router.post('/smart_album/create', authenticateJWT, videoSmartAlbumController.createSmartAlbum);
router.post('/smart_album/update', authenticateJWT, videoSmartAlbumController.updateSmartAlbum);
router.post('/smart_album/delete', authenticateJWT, videoSmartAlbumController.deleteSmartAlbum);

router.post('/album/list', authenticateJWT, videoAlbumController.listAlbums);
router.post('/album/overview', authenticateJWT, videoAlbumController.getAlbumOverview);
router.post('/album/get', authenticateJWT, videoAlbumController.getAlbum);
router.post('/album/create', authenticateJWT, videoAlbumController.createAlbum);
router.post('/album/update', authenticateJWT, videoAlbumController.updateAlbum);
router.post('/album/delete', authenticateJWT, videoAlbumController.deleteAlbum);
router.post('/album/index/add', authenticateJWT, videoAlbumController.addAlbumIndexes);
router.post('/album/index/remove', authenticateJWT, videoAlbumController.removeAlbumIndexes);
router.post('/album/cover/set', authenticateJWT, videoAlbumController.setAlbumCover);

router.get('/detail', authenticateJWT, videoDetailController.getDetail);
router.get('/episodes', authenticateJWT, videoDetailController.getEpisodes);
router.get('/tvPlayInfo', authenticateJWT, videoDetailController.getTvPlayInfo);
router.get('/discContents', authenticateJWT, videoDetailController.getDiscContents);
router.get('/discContents/thumb', authenticateJWT, videoDetailController.getDiscContentThumb);
router.post('/detail/open_skip/set', authenticateJWT, requireAdmin, videoDetailController.setOpenSkip);
router.get('/person/image', authenticateJWT, videoDetailController.getPersonImage);
router.get('/poster/image', authenticateJWT, videoDetailController.getPosterImage);
router.post('/file_view/list', authenticateJWT, createFileViewHandler('video', 'list'));
router.post('/file_view/search', authenticateJWT, createFileViewHandler('video', 'globalSearch'));

module.exports = router;
